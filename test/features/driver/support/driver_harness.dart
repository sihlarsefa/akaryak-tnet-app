// Şoför özelliği test ortamı (A7): sahte kip, gecikmesiz sahte sunucu (yalnızca çekirdek + şoför
// uçları; diğer özelliklerin sahtelerine bağlı değildir), bellek içi depolar, sahte kamera, konum ve
// dosya deposu. Ağ yok.
import 'dart:async';
import 'dart:io';

import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/env/app_env.dart';
import 'package:akaryakitnet/core/env/app_info.dart';
import 'package:akaryakitnet/core/network/fake/core_fakes.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/offline/cache_store.dart';
import 'package:akaryakitnet/core/offline/connectivity.dart';
import 'package:akaryakitnet/core/offline/outbox_providers.dart';
import 'package:akaryakitnet/core/offline/outbox_store.dart';
import 'package:akaryakitnet/core/routing/nav_keys.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/storage/secure_store.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/driver/api.dart';
import 'package:akaryakitnet/features/driver/application/camera.dart';
import 'package:akaryakitnet/features/driver/application/location.dart';
import 'package:akaryakitnet/features/driver/data/deliver_draft.dart';
import 'package:akaryakitnet/features/driver/data/driver_models.dart';
import 'package:akaryakitnet/features/driver/driver_fake.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Küçük geçerli JPEG (FF D8 … FF D9); içerik önemli değil.
const sampleJpeg = <int>[
  0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, //
  0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9,
];

/// Eşzamanlı dosya işlemleri (testWidgets'ın sahte zamanında gerçek eşzamansız G/Ç beklemez).
class TestFileStore implements DriverFileStore {
  TestFileStore(this.dir);

  final Directory dir;
  int _seq = 0;
  final List<String> deleted = [];

  String _next(String ext) => '${dir.path}/f${_seq++}$ext';

  @override
  Future<String> persistFile(String sourcePath) {
    final target = _next('.jpg');
    File(sourcePath).copySync(target);
    return Future.value(target);
  }

  @override
  Future<String> persistBytes(List<int> bytes, {required String extension}) {
    final target = _next('.$extension');
    File(target).writeAsBytesSync(bytes, flush: true);
    return Future.value(target);
  }

  @override
  bool exists(String path) => File(path).existsSync();

  @override
  void deleteAll(Iterable<String> paths) {
    for (final p in paths) {
      deleted.add(p);
      final f = File(p);
      if (f.existsSync()) f.deleteSync();
    }
  }

  @override
  Future<void> sweep(Set<String> keep, {Duration olderThan = Duration.zero}) =>
      Future.value();
}

/// Sahte kamera: her çekimde küçük bir JPEG yazar.
class FakeCamera implements DriverCamera {
  FakeCamera(this.dir);

  final Directory dir;
  CaptureStatus next = CaptureStatus.ok;
  int shots = 0;
  bool primer = false;

  @override
  bool get needsCameraPrimer => primer;

  String _write() {
    final path = '${dir.path}/cam${shots++}.jpg';
    File(path).writeAsBytesSync(sampleJpeg, flush: true);
    return path;
  }

  CaptureResult _result() => switch (next) {
    CaptureStatus.ok => CaptureResult.ok([_write()]),
    CaptureStatus.cancelled => const CaptureResult.cancelled(),
    CaptureStatus.denied => const CaptureResult.denied(),
    CaptureStatus.failed => const CaptureResult.failed(),
  };

  @override
  Future<CaptureResult> takePhoto() => Future.value(_result());

  @override
  Future<CaptureResult> pickFromGallery({int limit = 6}) =>
      Future.value(_result());
}

/// Sahte konum servisi.
class FakeLocation implements DriverLocationService {
  bool enabled = true;
  DriverLocationPermission perm = DriverLocationPermission.granted;
  DriverLocationPermission afterRequest = DriverLocationPermission.granted;
  bool approximate = false;
  double? accuracy = 8;
  bool fail = false;
  int requests = 0;
  int settingsOpened = 0;

  @override
  Future<bool> serviceEnabled() => Future.value(enabled);

  @override
  Future<DriverLocationPermission> permission() => Future.value(perm);

  @override
  Future<DriverLocationPermission> requestPermission() {
    requests++;
    perm = afterRequest;
    return Future.value(perm);
  }

  @override
  Future<bool> isApproximate() => Future.value(approximate);

  @override
  Future<DriverPosition?> current({
    Duration timeLimit = const Duration(seconds: 8),
  }) => Future.value(
    fail
        ? null
        : DriverPosition(
            latitude: 40.911912,
            longitude: 29.301417,
            accuracyMeters: accuracy,
            approximate: approximate,
            capturedAt: DateTime.now().toUtc(),
          ),
  );

  @override
  Future<bool> openAppSettings() {
    settingsOpened++;
    return Future.value(true);
  }

  @override
  Future<bool> openLocationSettings() => openAppSettings();
}

/// Çevrimiçi / çevrimdışı anahtarı (bekleyen işlem gönderici ve arayüz okur).
final testOnlineProvider = StateProvider<bool>((ref) => true);

class DriverHarness {
  DriverHarness._(this.server, this.prefs, this.dir);

  final FakeServer server;
  final SharedPreferences prefs;
  final Directory dir;
  final MemorySecureStore secure = MemorySecureStore();
  final MemoryCacheStore cache = MemoryCacheStore();
  final MemoryOutboxStore outbox = MemoryOutboxStore();
  late final TestFileStore files = TestFileStore(dir);
  late final FakeCamera camera = FakeCamera(dir);
  final FakeLocation location = FakeLocation();

  FakeWorld get world => server.world;

  static Future<DriverHarness> create({
    Map<String, Object> prefs = const {'akn.onboardingDone': true},
    FakeWorld? world,
    SharedPreferences? reusePrefs,
  }) async {
    if (reusePrefs == null) SharedPreferences.setMockInitialValues(prefs);
    final p = reusePrefs ?? await SharedPreferences.getInstance();
    final server = FakeServer.forTests(world: world ?? FakeWorld.seeded());
    registerCoreFakes(server);
    registerDriverFakes(server);
    final dir = Directory.systemTemp.createTempSync('akn_driver_');
    return DriverHarness._(server, p, dir);
  }

  List<Override> get overrides => overridesFor();

  /// [freshDevice]: ayrı güvenli depo ve önbellek (başka bir telefon / kullanıcı).
  List<Override> overridesFor({bool freshDevice = false}) => [
    appEnvProvider.overrideWithValue(AppEnv.fakeForTests),
    appInfoProvider.overrideWithValue(AppInfo.test),
    prefsStoreProvider.overrideWithValue(PrefsStore(prefs)),
    secureStoreProvider.overrideWithValue(
      freshDevice ? MemorySecureStore() : secure,
    ),
    fakeServerProvider.overrideWithValue(server),
    cacheStoreProvider.overrideWithValue(
      freshDevice ? MemoryCacheStore() : cache,
    ),
    outboxStoreProvider.overrideWithValue(outbox),
    outboxHandlersProvider.overrideWith(driverOutboxHandlers),
    driverFileStoreProvider.overrideWithValue(files),
    driverCameraProvider.overrideWithValue(camera),
    driverLocationServiceProvider.overrideWithValue(location),
    connectivityProvider.overrideWith((ref) {
      final ctl = StreamController<bool>();
      ref.listen<bool>(
        testOnlineProvider,
        (_, v) => ctl.add(v),
        fireImmediately: true,
      );
      ref.onDispose(ctl.close);
      return ctl.stream;
    }),
  ];

  ProviderContainer container({bool freshDevice = false}) =>
      ProviderContainer(overrides: overridesFor(freshDevice: freshDevice));

  /// Sahte kullanıcıyla giriş (gerçek eşzamansız ortamda çalıştırın).
  static Future<void> login(ProviderContainer c, String key) async {
    final session = c.read(sessionControllerProvider.notifier);
    await session.restore();
    await session.loginWithPassword(key, 'demo');
  }

  void dispose() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// Hata ayıklama: `AKN_TEST_ERRLOG=<dosya>` verilirse Flutter hataları dosyaya da yazılır.
void _installErrorLog() {
  final path = Platform.environment['AKN_TEST_ERRLOG'];
  if (path == null || path.isEmpty) return;
  final old = FlutterError.onError;
  FlutterError.onError = (d) {
    final text =
        '${d.toString().split('\n').take(40).join('\n')}\n${(d.stack?.toString() ?? '').split('\n').take(60).join('\n')}';
    File(path).writeAsStringSync('$text\n----\n', mode: FileMode.append);
    old?.call(d);
  };
}

/// Şoför rotalarıyla sınanacak uygulama (gerçek yönlendirici: `context.push` çalışır).
Widget driverTestApp({
  required ProviderContainer container,
  required String initialLocation,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  bool reduceMotion = false,
}) {
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    routes: [
      ...driverRoutes(),
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(body: Text('home')),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const Scaffold(body: Text('notifications')),
      ),
    ],
  );
  AppToast.navigatorKey = rootNavigatorKey;
  _installErrorLog();
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      theme: AknTheme.light(),
      darkTheme: AknTheme.dark(),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
    ),
  );
}

/// Ekranı 360×640 yapar.
void phoneSize(WidgetTester tester, [Size size = const Size(360, 640)]) {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
}

/// Gerçek G/Ç (dosya, çok parçalı yükleme) ilerlesin diye gerçek zamanda kısa bekler, sonra sahte
/// zamanı ilerletir; [done] sağlanana kadar.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  int maxRounds = 120,
  Duration step = const Duration(milliseconds: 50),
}) async {
  for (var i = 0; i < maxRounds && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(step);
  }
}

/// Animasyonlar ve zamanlayıcılar için bir süre ilerletir.
Future<void> pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 50);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

/// Erişilebilirlik kılavuzları (spec C.7).
Future<void> expectA11y(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

/// Kimliği verilen seed sevkiyatının ilk kaydı (testlerde kısa yol).
Map<String, dynamic> shipmentWhere(
  FakeWorld w,
  bool Function(Map<String, dynamic> s) test,
) => w.shipments.firstWhere(test);

/// Bekleyen bir Future'ı gerçek zamanda tamamlar.
Future<T> real<T>(WidgetTester tester, Future<T> Function() f) async {
  late T value;
  await tester.runAsync(() async => value = await f());
  return value;
}

/// Gerçek zamanda kısa bir süre bekler (zamanlayıcı yok).
Future<void> settleReal(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
  await tester.pump();
}

/// `unawaited` için kısayol.
void fireAndForget(Future<void> f) => unawaited(f);

// A6 (saha) testleri için ortak düzen: sahte kip, gecikmesiz sahte sunucu (yalnızca çekirdek + saha
// uçları; paralel geliştirilen başka bir özelliğin derlenmeyen dosyası bu testleri düşürmesin diye
// `app/fakes.dart` içe aktarılmaz), bellek içi depolar, sahte konum ve dosya deposu, açılıp kapanabilen
// bağlantı. Ağ yok; altın (golden) test yok.
import 'dart:io';

import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/env/app_config_controller.dart';
import 'package:akaryakitnet/core/env/app_env.dart';
import 'package:akaryakitnet/core/env/app_info.dart';
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/network/fake/core_fakes.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/offline/connectivity.dart';
import 'package:akaryakitnet/core/offline/outbox_op.dart';
import 'package:akaryakitnet/core/offline/outbox_providers.dart';
import 'package:akaryakitnet/core/offline/outbox_store.dart';
import 'package:akaryakitnet/core/routing/nav_keys.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/storage/secure_store.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:akaryakitnet/features/field/api.dart';
import 'package:akaryakitnet/features/field/application/lead_wizard_controller.dart';
import 'package:akaryakitnet/features/field/data/field_location.dart';
import 'package:akaryakitnet/features/field/fake/field_fake_state.dart';
import 'package:akaryakitnet/features/field/field_fake.dart';
import 'package:akaryakitnet/features/weather/weather_fake.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Testte açılıp kapanan bağlantı (`isOnlineProvider` bunu izler).
final onlineProvider = StateProvider<bool>((ref) => true);

/// Sahte konum servisi: izin durumu, istem sonrası durum ve konum ayarlanabilir; çağrılar sayılır.
class FakeFieldLocation implements FieldLocationService {
  FieldLocationAccess access = FieldLocationAccess.notDetermined;
  FieldLocationAccess afterRequest = FieldLocationAccess.granted;
  double accuracy = 8;
  bool approximateFix = false;
  int requests = 0;
  int reads = 0;
  int appSettings = 0;
  int locationSettings = 0;

  @override
  Future<FieldLocationAccess> status() async => access;

  @override
  Future<FieldLocationAccess> request() async {
    requests++;
    access = afterRequest;
    return access;
  }

  @override
  Future<FieldLocationFix> current({
    Duration timeLimit = const Duration(seconds: 15),
  }) async {
    reads++;
    return FieldLocationFix(
      latitude: 40.80213,
      longitude: 29.43047,
      accuracyMeters: approximateFix ? 1800 : accuracy,
      at: DateTime.utc(2026, 10, 21, 9),
      approximate: approximateFix,
    );
  }

  @override
  Future<bool> openAppSettings() async {
    appSettings++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettings++;
    return true;
  }
}

/// Eşzamanlı dosya deposu (testWidgets'ın sahte zamanında gerçek eşzamansız G/Ç beklemez).
class MemoryFieldFileStore implements FieldFileStore {
  MemoryFieldFileStore(this.dir);

  final Directory dir;
  int _seq = 0;
  final List<String> deleted = [];

  @override
  Future<String> persist(String path) {
    final target = '${dir.path}/kept${_seq++}-${path.split('/').last}';
    File(path).copySync(target);
    return Future.value(target);
  }

  @override
  Future<void> delete(String path) {
    deleted.add(path);
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
    return Future.value();
  }
}

/// Küçük geçerli PNG (belge görüntüsü yerine).
const samplePng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

String tomorrowIso() => TrTime.isoDate(TrTime.addDays(TrTime.todayStart(), 1));

/// Ege Tarım (103) için tek satırlık form isteği. İzmit Motorin maliyeti 38.400 + 1.000 × 1,2 =
/// 39.600 ₺/m³: 42,10 → %6,31 (otomatik), 41,70 → %5,30 (yönetici), 41,30 → %4,29 (üst), 40,90 → ret.
JsonMap formRequest({
  int customerId = 103,
  int pointId = 1004,
  int productId = 1,
  double liters = 8000,
  double price = 42.10,
  String method = 'HAVALE',
  int term = 0,
  String location = 'İZMİT',
  bool exception = false,
  String? justification,
  double? tupras,
}) => {
  'stationId': 1,
  'customerId': customerId,
  'paymentTermDays': term,
  'paymentMethodCode': method,
  'refineryLocation': location,
  'shipDate': tomorrowIso(),
  'includesCostInputs': false,
  'strategicExceptionRequested': exception,
  'exceptionJustification': justification,
  'lines': [
    {
      'productId': productId,
      'deliveryPointId': pointId,
      'quantityLiters': liters,
      'requestedDeliveryDate': tomorrowIso(),
      'proposedUnitPrice': price,
      'tuprasPriceM3': tupras,
    },
  ],
};

/// Sahte kip ortamı: çekirdek + saha sahte uçları.
class FieldHarness {
  FieldHarness._(this.server, this.prefs, this.secure, this.location, this.dir)
    : files = MemoryFieldFileStore(dir);

  final FakeServer server;
  final SharedPreferences prefs;
  final MemorySecureStore secure;
  final FakeFieldLocation location;
  final Directory dir;
  final MemoryFieldFileStore files;

  static Future<FieldHarness> create() async {
    SharedPreferences.setMockInitialValues(const {'akn.onboardingDone': true});
    final prefs = await SharedPreferences.getInstance();
    final server = FakeServer()..latencyEnabled = false;
    registerCoreFakes(server);
    registerFieldFakes(server);
    // Saha ana sayfasındaki "Bulunduğunuz yerde hava" kartı (A8) için.
    registerWeatherFakes(server);
    final dir = Directory.systemTemp.createTempSync('akn-field-test');
    return FieldHarness._(
      server,
      prefs,
      MemorySecureStore(),
      FakeFieldLocation(),
      dir,
    );
  }

  /// Saha sahte durumu (ilk erişimde tohumlanır).
  FieldFakeState get state => FieldFakeState.of(server.world);

  /// Belge olarak seçilecek küçük bir PNG dosyası yazar.
  String writePng([String name = 'levha.png']) {
    final f = File('${dir.path}/$name')
      ..writeAsBytesSync(samplePng, flush: true);
    return f.path;
  }

  List<Override> get overrides => [
    appEnvProvider.overrideWithValue(AppEnv.fakeForTests),
    appInfoProvider.overrideWithValue(AppInfo.test),
    prefsStoreProvider.overrideWithValue(PrefsStore(prefs)),
    secureStoreProvider.overrideWithValue(secure),
    fakeServerProvider.overrideWith((ref) => server),
    outboxHandlersProvider.overrideWith(fieldOutboxHandlers),
    isOnlineProvider.overrideWith((ref) => ref.watch(onlineProvider)),
    fieldLocationServiceProvider.overrideWithValue(location),
    fieldFileStoreProvider.overrideWithValue(files),
  ];

  ProviderContainer container({List<Override> extra = const []}) =>
      ProviderContainer(overrides: [...overrides, ...extra]);

  void dispose() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

/// [persona] ile parola girişi (merkez iki adımlıdır).
Future<void> loginAs(ProviderContainer c, String persona) async {
  final session = c.read(sessionControllerProvider.notifier);
  final outcome = await session.loginWithPassword(persona, 'demo');
  if (outcome is LoginNeedsCode) {
    await session.verifyCode(outcome.challenge.challengeId, '123456');
  }
}

/// Koşul sağlanana kadar gerçek zamanda bekler (düz testler).
Future<void> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
  String? reason,
}) async {
  final sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > timeout) {
      fail('Zaman aşımı: ${reason ?? 'koşul sağlanmadı'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// İşlem [id] bitene (done / needsAttention / failed) kadar bekler.
Future<OutboxOp> waitOp(
  ProviderContainer c,
  String id, {
  Set<OutboxStatus> until = const {
    OutboxStatus.done,
    OutboxStatus.needsAttention,
    OutboxStatus.failed,
  },
}) async {
  final store = c.read(outboxStoreProvider);
  for (var i = 0; i < 500; i++) {
    final op = await store.get(id);
    if (op != null && until.contains(op.status)) return op;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return (await store.get(id))!;
}

/// Dio'dan geçen istekler (gövde ve başlıklarıyla).
class RequestLog {
  final List<RequestOptions> entries = [];

  void attach(ProviderContainer c) => c
      .read(dioProvider)
      .interceptors
      .add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            entries.add(o);
            h.next(o);
          },
        ),
      );

  List<RequestOptions> all(String method, String pathPart) => [
    for (final e in entries)
      if (e.method.toUpperCase() == method.toUpperCase() &&
          e.uri.path.contains(pathPart))
        e,
  ];

  /// Yolu tam olarak `/api/v1/<path>` olan istekler.
  List<RequestOptions> exact(String method, String path) => [
    for (final e in entries)
      if (e.method.toUpperCase() == method.toUpperCase() &&
          e.uri.path.endsWith('/api/v1/$path'))
        e,
  ];

  RequestOptions? last(String method, String pathPart) {
    final list = all(method, pathPart);
    return list.isEmpty ? null : list.last;
  }

  void clear() => entries.clear();
}

String? idempotencyKeyOf(RequestOptions o) {
  for (final e in o.headers.entries) {
    if (e.key.toLowerCase() == 'idempotency-key') return '${e.value}';
  }
  return null;
}

// ═══════════════════════════════════════════════════════════════════ Ekran testleri

/// Uygulamanın kökü (erişilebilirlik denetimleri için).
const fieldRootKey = ValueKey('field-root');

/// Pompalanmış saha uygulaması.
class FieldApp {
  FieldApp(this.harness, this.container, this.router, this.log);

  final FieldHarness harness;
  final ProviderContainer container;
  final GoRouter router;
  final RequestLog log;

  FakeServer get server => harness.server;
  FakeFieldLocation get location => harness.location;

  /// Açık rota (`/approvals/9601` …).
  String get currentUri =>
      router.routerDelegate.currentConfiguration.uri.toString();
}

/// Diğer özelliklerin rotaları: hangi yolun açıldığı test edilebilsin diye yer tutucu.
const _stubPaths = [
  '/approvals/:id',
  '/customers/:id',
  '/bayi/orders/:id',
  '/orders/:id',
  '/assistant',
  '/notifications',
];

GoRouter _router(String initial) => GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: initial,
  routes: [
    GoRoute(path: '/home', builder: (context, state) => const FieldHome()),
    ...fieldRoutes(),
    for (final p in _stubPaths)
      GoRoute(
        path: p,
        builder: (context, state) =>
            Scaffold(body: Center(child: Text('stub:${state.uri}'))),
      ),
  ],
);

/// Kısa adımlarla pompalar (sonsuz parıltı animasyonları yüzünden pumpAndSettle kullanılmaz).
Future<void> pumpFor(
  WidgetTester tester, [
  Duration total = const Duration(milliseconds: 1200),
]) async {
  const step = Duration(milliseconds: 50);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

ProviderContainer? _current;
FieldHarness? _currentHarness;

/// Testi kapatır: bildirim, ağaç, kapsayıcı ve bekleyen zamanlayıcılar temizlenir.
Future<void> finish(WidgetTester tester) async {
  AppToast.dismiss();
  await tester.pumpWidget(const SizedBox());
  _current?.dispose();
  _current = null;
  _currentHarness?.dispose();
  _currentHarness = null;
  await tester.pump(const Duration(seconds: 6));
}

/// [persona] ile giriş yapıp [location]'ı açar.
Future<FieldApp> pumpField(
  WidgetTester tester, {
  required String persona,
  required String location,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  Size size = const Size(360, 640),
  bool online = true,
  void Function(FieldHarness h)? setup,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  final h = await tester.runAsync(FieldHarness.create);
  setup?.call(h!);
  final container = h!.container(extra: overrides);
  _current = container;
  _currentHarness = h;
  container.read(onlineProvider.notifier).state = online;
  final log = RequestLog()..attach(container);
  await tester.runAsync(() => loginAs(container, persona));
  final router = _router(location);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: fieldRootKey,
        child: MaterialApp.router(
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
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await pumpFor(tester);
  return FieldApp(h, container, router, log);
}

/// Uygulama yapılandırmasını sahte sunucudan yükler (hava ve asistan kartları açılır).
Future<void> loadAppConfig(WidgetTester tester, FieldApp app) async {
  await tester.runAsync(
    () => app.container.read(appConfigProvider.notifier).load(),
  );
  await pumpFor(tester);
}

/// Üstteki bildirim dokunuşu örtmesin diye kapatıp [text] metnine dokunur.
Future<void> tapText(WidgetTester tester, String text, {bool last = false}) =>
    tapFinder(tester, last ? find.text(text).last : find.text(text).first);

Future<void> tapFinder(WidgetTester tester, Finder f) async {
  AppToast.dismiss();
  await tester.pump();
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await pumpFor(tester);
}

/// C.7 denetimleri: dokunma hedefi (Android 48 dp, iOS 44 pt), etiketli hedef, metin kontrastı.
Future<void> expectA11y(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

/// Ekranın ana (dikey, en yüksek) kaydırılabilir alanı.
ScrollableState? mainScrollable() {
  ScrollableState? main;
  var best = 0.0;
  for (final e in find.byType(Scrollable).evaluate()) {
    final w = e.widget as Scrollable;
    if (axisDirectionToAxis(w.axisDirection) != Axis.vertical) continue;
    final h = e.size?.height ?? 0;
    if (h > best) {
      best = h;
      main = (e as StatefulElement).state as ScrollableState;
    }
  }
  return main;
}

/// Tembel kurulan listede [f] görünene kadar ana alanı kaydırır.
Future<void> scrollToFind(WidgetTester tester, Finder f) async {
  final main = mainScrollable();
  for (var i = 0; i < 40 && f.evaluate().isEmpty && main != null; i++) {
    final pos = main.position;
    if (pos.pixels >= pos.maxScrollExtent) break;
    pos.jumpTo((pos.pixels + 200).clamp(0.0, pos.maxScrollExtent));
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (f.evaluate().isNotEmpty) {
    await tester.ensureVisible(f.first);
    await pumpFor(tester, const Duration(milliseconds: 300));
  }
}

/// Ana (dikey, en yüksek) kaydırılabilir alanı adım adım sonuna kadar kaydırır: tembel kurulan
/// bölümler de düzenlenir, taşma hataları testte yakalanır.
Future<void> scrollThrough(WidgetTester tester, {int maxSteps = 16}) async {
  final main = mainScrollable();
  if (main == null) return;
  for (var i = 0; i < maxSteps; i++) {
    final pos = main.position;
    if (pos.pixels >= pos.maxScrollExtent) break;
    pos.jumpTo((pos.pixels + 420).clamp(0.0, pos.maxScrollExtent));
    await pumpFor(tester, const Duration(milliseconds: 400));
  }
}

/// C.7 ekran matrisi (360×640): yazı ölçeği 1.0 ve 2.0 × açık ve koyu tema. Ekranın üstünde ve
/// sonuna kaydırıldıktan sonra denetler; taşma ya da hata olmamalı.
void a11yMatrix(
  String name, {
  required String persona,
  required String location,
  Future<void> Function(WidgetTester tester, FieldApp app)? prepare,
}) {
  for (final scale in const [1.0, 2.0]) {
    for (final b in const [Brightness.light, Brightness.dark]) {
      final theme = b == Brightness.dark ? 'koyu' : 'açık';
      testWidgets('$name · yazı ${scale}x · $theme', (tester) async {
        final app = await pumpField(
          tester,
          persona: persona,
          location: location,
          brightness: b,
          textScale: scale,
        );
        if (prepare != null) await prepare(tester, app);
        expect(tester.takeException(), isNull);
        await expectA11y(tester);
        await scrollThrough(tester);
        expect(tester.takeException(), isNull);
        await expectA11y(tester);
        await finish(tester);
      });
    }
  }
}

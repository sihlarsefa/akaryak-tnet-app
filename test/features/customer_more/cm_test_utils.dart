import 'dart:typed_data';

import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/env/app_env.dart';
import 'package:akaryakitnet/core/env/app_info.dart';
import 'package:akaryakitnet/core/media/image_capture.dart';
import 'package:akaryakitnet/core/models/enums.dart';
import 'package:akaryakitnet/core/network/fake/core_fakes.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/routing/nav_keys.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/storage/secure_store.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/customer_more/api.dart';
import 'package:akaryakitnet/features/customer_more/application/documents_controller.dart';
import 'package:akaryakitnet/features/customer_more/application/image_source.dart';
import 'package:akaryakitnet/features/customer_more/application/paged.dart';
import 'package:akaryakitnet/features/customer_more/customer_more_fake.dart';
import 'package:akaryakitnet/features/customer_more/data/location_service.dart';
import 'package:akaryakitnet/features/customer_more/data/pdf_cache.dart';
import 'package:akaryakitnet/features/customer_more/fake/cm_fake_images.dart';
import 'package:akaryakitnet/features/customer_more/presentation/documents/document_viewer.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kaydedilen istek (yöntem, yol, başlıklar).
class SeenRequest {
  SeenRequest(this.method, this.path, this.headers);
  final String method;
  final String path;
  final Map<String, dynamic> headers;

  String? get idempotencyKey {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == 'idempotency-key') return '${e.value}';
    }
    return null;
  }

  @override
  String toString() => '$method $path';
}

/// Sahte konum servisi.
class FakeLocationService implements CmLocationService {
  FakeLocationService({
    this.initial = LocationAccess.notAsked,
    this.afterRequest = LocationAccess.precise,
    this.fix = const LocationFix(
      latitude: 40.912345,
      longitude: 29.301234,
      accuracyMeters: 8,
    ),
  });

  LocationAccess initial;
  LocationAccess afterRequest;
  LocationFix? fix;
  int requests = 0;

  @override
  Future<LocationAccess> access() async => initial;

  @override
  Future<LocationAccess> request() async {
    requests++;
    initial = afterRequest;
    return afterRequest;
  }

  @override
  Future<LocationFix?> current() async => fix;

  @override
  Future<bool> openAppSettings() async => true;

  @override
  Future<bool> openLocationSettings() async => true;
}

/// Sahte görsel seçici (kamera / galeri).
class FakeImagePicker implements CmImagePicker {
  int picked = 0;

  CapturedImage _next() => CapturedImage(
    path: '',
    bytes: Uint8List.fromList(CmFakeImages.deliveryPhoto(900 + picked)),
    fileName: 'itiraz-${++picked}.jpg',
  );

  @override
  Future<CapturedImage?> pick(
    BuildContext context,
    CaptureSource source,
    AttachmentKind kind,
  ) async => _next();

  @override
  Future<List<CapturedImage>> pickMany({int limit = 6}) async => [_next()];
}

/// Yalnızca çekirdek ve A3 sahtelerini kaydeden sunucu (diğer özelliklerin yarım kalmış kodundan
/// bağımsız; dünya yine ortak tohumdur).
class CmHarness {
  CmHarness(this.server);
  final FakeServer server;
}

/// A3 test ortamı: sahte sunucu, oturum açmış persona, kaydedilen istekler, sahte cihaz servisleri.
class CmEnv {
  CmEnv._(this.harness, this.container, this.requests, this.opened);

  final CmHarness harness;
  final ProviderContainer container;
  final List<SeenRequest> requests;
  final List<GeneratedDoc> opened;

  FakeWorld get world => harness.server.world;

  static Future<CmEnv> create({
    String persona = 'musteri',
    List<Override> overrides = const [],
    CmLocationService? location,
    CmImagePicker? picker,
  }) async {
    SharedPreferences.setMockInitialValues({'akn.onboardingDone': true});
    final prefs = await SharedPreferences.getInstance();
    final server = FakeServer.forTests(world: FakeWorld.seeded());
    registerCoreFakes(server);
    registerCustomerMoreFakes(server);
    final h = CmHarness(server);
    final opened = <GeneratedDoc>[];
    final c = ProviderContainer(
      overrides: [
        appEnvProvider.overrideWithValue(AppEnv.fakeForTests),
        appInfoProvider.overrideWithValue(AppInfo.test),
        prefsStoreProvider.overrideWithValue(PrefsStore(prefs)),
        secureStoreProvider.overrideWithValue(MemorySecureStore()),
        fakeServerProvider.overrideWith((ref) => server),
        pdfCacheProvider.overrideWithValue(MemoryPdfCache()),
        cmRetryDelaysProvider.overrideWithValue(const []),
        cmLocationServiceProvider.overrideWithValue(
          location ?? FakeLocationService(),
        ),
        cmImagePickerProvider.overrideWithValue(picker ?? FakeImagePicker()),
        cmDocOpenerProvider.overrideWithValue((context, doc) async {
          opened.add(doc);
        }),
        ...overrides,
      ],
    );
    final requests = <SeenRequest>[];
    c
        .read(dioProvider)
        .interceptors
        .add(
          InterceptorsWrapper(
            onRequest: (o, handler) {
              requests.add(
                SeenRequest(
                  o.method,
                  o.uri.path.replaceFirst(RegExp(r'^.*/api/v1/'), ''),
                  Map.of(o.headers),
                ),
              );
              handler.next(o);
            },
          ),
        );
    await c
        .read(sessionControllerProvider.notifier)
        .loginWithPassword(persona, 'demo');
    // Riverpod'un oturum açılırken bu (gerçek) bölgede kurduğu bekleyen görevleri bitir; yoksa
    // widget testinin sahte saatinde autoDispose sağlayıcılar hiç kapanmaz.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    requests.clear();
    return CmEnv._(h, c, requests, opened);
  }

  void dispose() => container.dispose();
}

/// İşlev testlerinin varsayılan yüzeyi: uzun bir telefon (içerik çoğunlukla kaydırmadan görünür).
/// Erişilebilirlik testleri 360×640 kullanır.
const cmTallPhone = Size(412, 1400);

/// Yönlendiricili test uygulaması (A3 rotaları + diğer özelliklerin yer tutucuları).
Future<GoRouter> pumpCmApp(
  WidgetTester tester,
  CmEnv env, {
  required String location,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  Size size = cmTallPhone,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = size * 2;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Widget stub(BuildContext context, GoRouterState s) =>
      Scaffold(body: Center(child: Text('stub ${s.uri}')));
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: location,
    routes: [
      ...customerMoreRoutes(),
      GoRoute(path: '/orders/new', builder: stub),
      GoRoute(path: '/orders/:id', builder: stub),
      GoRoute(path: '/approvals', builder: stub),
      GoRoute(path: '/approvals/:id', builder: stub),
      GoRoute(path: '/home', builder: stub),
    ],
  );
  addTearDown(router.dispose);
  AppToast.navigatorKey = rootNavigatorKey;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: env.container,
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
  );
  await pumpFor(tester, const Duration(milliseconds: 800));
  return router;
}

final _vertical = find.byWidgetPredicate(
  (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
);

/// [f] görünene kadar sayfanın (ya da açık alt sayfanın) dikey kaydırıcısını kaydırır.
Future<void> scrollTo(
  WidgetTester tester,
  Finder f, {
  bool inSheet = false,
  double delta = 250,
}) async {
  final scrollable = inSheet
      ? find.descendant(of: find.byType(BottomSheet), matching: _vertical).first
      : _vertical.first;
  await tester.scrollUntilVisible(f, delta, scrollable: scrollable);
  await tester.pump(const Duration(milliseconds: 100));
}

/// Sabit adımlarla zaman ilerletir (sonsuz animasyonlar `pumpAndSettle`i bitirmez).
Future<void> pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 50);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

/// Bildirimler ve animasyonlar bitene kadar bekler, ağacı kapatır.
Future<void> finish(WidgetTester tester) async {
  await pumpFor(tester, const Duration(seconds: 5));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// Etiketi alanın üstünde duran (tasarım v2 §6.10) metin alanı: [label] metnini taşıyan
/// `AknTextField`'ın içindeki `TextFormField`.
Finder fieldLabeled(String label) => find
    .descendant(
      of: find.ancestor(
        of: find.text(label),
        matching: find.byType(AknTextField),
      ),
      matching: find.byType(TextFormField),
    )
    .first;

// A5 (Onaylarım, Finans, Tahsilat) ekran testleri için ortak düzen: sahte kip, gecikmesiz sahte
// sunucu (çekirdek + A5 uçları), persona girişi, yalnızca A5 rotaları + diğer özelliklerin rotaları
// için yer tutucular. `app/fakes.dart` bilerek içe aktarılmaz: paralel geliştirilen başka bir
// özelliğin derlenmeyen dosyası bu testleri düşürmesin. Ağ yok; altın (golden) test yok.
import 'dart:typed_data';

import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/env/app_env.dart';
import 'package:akaryakitnet/core/env/app_info.dart';
import 'package:akaryakitnet/core/models/enums.dart';
import 'package:akaryakitnet/core/network/fake/core_fakes.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/offline/connectivity.dart';
import 'package:akaryakitnet/core/routing/nav_keys.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/storage/secure_store.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/approvals/api.dart';
import 'package:akaryakitnet/features/approvals/approvals_fake.dart';
import 'package:akaryakitnet/features/finance/api.dart';
import 'package:akaryakitnet/features/finance/finance_fake.dart';
import 'package:akaryakitnet/features/payments/api.dart';
import 'package:akaryakitnet/features/payments/payments_fake.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sahte kip ortamı: çekirdek + A5 sahte uçları, bellek içi depolar (bkz. `test/support/test_app.dart`).
class A5Harness {
  A5Harness._(this.server, this.prefs, this.secure);

  final FakeServer server;
  final SharedPreferences prefs;
  final MemorySecureStore secure;

  static Future<A5Harness> create() async {
    SharedPreferences.setMockInitialValues(const {'akn.onboardingDone': true});
    final prefs = await SharedPreferences.getInstance();
    final server = FakeServer()..latencyEnabled = false;
    registerCoreFakes(server);
    registerApprovalsFakes(server);
    registerFinanceFakes(server);
    registerPaymentsFakes(server);
    return A5Harness._(server, prefs, MemorySecureStore());
  }

  List<Override> get overrides => [
    appEnvProvider.overrideWithValue(AppEnv.fakeForTests),
    appInfoProvider.overrideWithValue(AppInfo.test),
    prefsStoreProvider.overrideWithValue(PrefsStore(prefs)),
    secureStoreProvider.overrideWithValue(secure),
    fakeServerProvider.overrideWith((ref) => server),
  ];

  ProviderContainer container({List<Override> extra = const []}) =>
      ProviderContainer(overrides: [...overrides, ...extra]);
}

/// Testte seçilen "dosya": belge görünümlü küçük PNG.
class TestFileSource implements A5FileSource {
  TestFileSource();

  int picks = 0;

  /// Son seçimde istenen tür.
  AttachmentKind? lastKind;

  @override
  Future<PickedFile?> pick(BuildContext context, AttachmentKind kind) async {
    picks++;
    lastKind = kind;
    return PickedFile(
      bytes: _png,
      fileName: 'test-$picks.png',
      contentType: 'image/png',
    );
  }

  static final Uint8List _png = Uint8List.fromList(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
    0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00,
    0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);
}

/// Bağlantı yok (karar düğmeleri kapalı olmalı).
final offlineOverride = isOnlineProvider.overrideWithValue(false);

/// Uygulamanın kökü (görüntü alma ve erişilebilirlik denetimleri için).
const a5RootKey = ValueKey('a5-root');

/// Pompalanmış A5 uygulaması.
class A5App {
  A5App(this.harness, this.container, this.router, this.files, this.log);

  final A5Harness harness;
  final ProviderContainer container;
  final GoRouter router;
  final TestFileSource files;
  final RequestLog log;

  FakeServer get server => harness.server;
}

/// Diğer özelliklerin rotaları: hangi yolun açıldığı test edilebilsin diye yer tutucu.
final List<String> _stubPaths = [
  '/home',
  '/orders/new',
  '/orders/:id',
  '/bayi/orders/:id',
  '/customers/:id',
  '/field/forms/:id',
  '/field/leads/:id',
  '/company/requests/:id',
  '/notifications',
];

GoRouter _router(String initial) => GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: initial,
  routes: [
    ...approvalsRoutes(),
    ...financeRoutes(),
    ...paymentsRoutes(),
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

/// Son pompalanan uygulamanın kapsayıcısı ([finish] kapatır).
ProviderContainer? _current;

/// Testi kapatır: bildirim, ağaç, kapsayıcı (okunmamış sayacı gibi periyodik zamanlayıcılar) ve
/// bekleyen zamanlayıcılar temizlenir.
Future<void> finish(WidgetTester tester) async {
  AppToast.dismiss();
  await tester.pumpWidget(const SizedBox());
  _current?.dispose();
  _current = null;
  await tester.pump(const Duration(seconds: 6));
}

/// [persona] ile giriş yapıp [location]'ı açar.
Future<A5App> pumpA5(
  WidgetTester tester, {
  required String persona,
  required String location,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  Size size = const Size(360, 640),
  // Varsayılan kapalı: çekirdek `FilterChips` / `AknButton` içindeki `AnimatedSize`, azaltılmış
  // harekette `Duration.zero` alır ve seçim değişince Flutter hata ayıklama doğrulamasına takılır
  // (contract-changes.md A5).
  bool reduceMotion = false,
  List<Override> overrides = const [],
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  final h = await A5Harness.create();
  final files = TestFileSource();
  final container = h.container(
    extra: [
      a5RetryScheduleProvider.overrideWithValue(const [
        Duration(milliseconds: 10),
        Duration(milliseconds: 10),
      ]),
      a5FileSourceProvider.overrideWithValue(files),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  _current = container;
  final log = RequestLog()..attach(container);
  await tester.runAsync(() async {
    final session = container.read(sessionControllerProvider.notifier);
    final outcome = await session.loginWithPassword(persona, 'demo');
    if (outcome is LoginNeedsCode) {
      await session.verifyCode(outcome.challenge.challengeId, '123456');
    }
  });
  final router = _router(location);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(
        key: a5RootKey,
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
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: reduceMotion,
            ),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await pumpFor(tester);
  return A5App(h, container, router, files, log);
}

/// Üstteki bildirim (toast) dokunuşu örtmesin diye kapatıp [text] metnine dokunur.
Future<void> tapText(
  WidgetTester tester,
  String text, {
  bool last = false,
  bool first = false,
}) async {
  final f = last
      ? find.text(text).last
      : (first ? find.text(text).first : find.text(text));
  await tapFinder(tester, f);
}

/// Bildirimi kapatıp [f] görünür olana dek kaydırır ve dokunur.
Future<void> tapFinder(WidgetTester tester, Finder f) async {
  AppToast.dismiss();
  await tester.pump();
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await pumpFor(tester);
}

/// Açık alt sayfanın ([AppSheet]) içindeki eşleşmeler (arkadaki sayfa hariç).
Finder inSheet(Finder f) =>
    find.descendant(of: find.byType(AppSheet), matching: f);

/// [label] etiketli metin alanı.
Finder fieldLabeled(String label) => find.ancestor(
  of: find.textContaining(label),
  matching: find.byType(TextField),
);

/// [label] etiketli alana yazar.
Future<void> typeInto(WidgetTester tester, String label, String text) async {
  final f = fieldLabeled(label).first;
  await tester.ensureVisible(f);
  await tester.enterText(f, text);
  await tester.pump();
}

/// C.7 denetimleri: dokunma hedefi (Android 48 dp, iOS 44 pt), etiketli hedef, metin kontrastı.
Future<void> expectA11y(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

/// Ana (dikey, en yüksek) kaydırılabilir alanı adım adım sonuna kadar kaydırır: tembel kurulan
/// bölümler de düzenlenir, taşma hataları testte yakalanır.
Future<void> scrollThrough(WidgetTester tester, {int maxSteps = 16}) async {
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
  Future<void> Function(WidgetTester tester, A5App app)? prepare,
}) {
  for (final scale in const [1.0, 2.0]) {
    for (final b in const [Brightness.light, Brightness.dark]) {
      final theme = b == Brightness.dark ? 'koyu' : 'açık';
      testWidgets('$name · yazı ${scale}x · $theme', (tester) async {
        final app = await pumpA5(
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

/// Dio'dan geçen istekler (gövde ve başlıklarıyla) — gönderilen JSON'u doğrulamak için.
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

  /// [method] ve yolu [pathPart] içeren son istek.
  RequestOptions? last(String method, String pathPart) {
    for (final e in entries.reversed) {
      if (e.method.toUpperCase() == method.toUpperCase() &&
          e.uri.path.contains(pathPart)) {
        return e;
      }
    }
    return null;
  }

  List<RequestOptions> all(String method, String pathPart) => [
    for (final e in entries)
      if (e.method.toUpperCase() == method.toUpperCase() &&
          e.uri.path.contains(pathPart))
        e,
  ];
}

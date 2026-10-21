// A1 (kimlik + tanıtım) test yardımcıları: yalnızca çekirdek + kimlik sahteleriyle çalışan küçük ortam
// (diğer özelliklerin sahtelerine bağlı değil), sayfayı A1 rotalarıyla açan test yönlendiricisi (kural
// yok), sahte saat, sahte biyometri, bağlantı kaydı ve spec C.7 erişilebilirlik denetimleri.
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/env/app_env.dart';
import 'package:akaryakitnet/core/env/app_info.dart';
import 'package:akaryakitnet/core/network/fake/core_fakes.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/storage/secure_store.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/auth/api.dart';
import 'package:akaryakitnet/features/auth/application/auth_clock.dart';
import 'package:akaryakitnet/features/auth/application/link_opener.dart';
import 'package:akaryakitnet/features/auth/auth_fake.dart';
import 'package:akaryakitnet/features/onboarding/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sahte kipte küçük ortam: gecikmesiz sahte sunucu (çekirdek + kimlik sahteleri), bellek içi depolar.
class AuthHarness {
  AuthHarness._(this.server, this.prefs, this.secure);

  final FakeServer server;
  final SharedPreferences prefs;
  final MemorySecureStore secure;

  static Future<AuthHarness> create({
    Map<String, Object> prefs = const {'akn.onboardingDone': true},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final p = await SharedPreferences.getInstance();
    final server = FakeServer.forTests();
    registerCoreFakes(server);
    registerAuthFakes(server);
    return AuthHarness._(server, p, MemorySecureStore());
  }

  AuthFakeControls get controls => AuthFakeControls.of(server);

  List<Override> get overrides => [
    appEnvProvider.overrideWithValue(AppEnv.fakeForTests),
    appInfoProvider.overrideWithValue(AppInfo.test),
    prefsStoreProvider.overrideWithValue(PrefsStore(prefs)),
    secureStoreProvider.overrideWithValue(secure),
    fakeServerProvider.overrideWithValue(server),
  ];

  ProviderContainer container({List<Override> extra = const []}) =>
      ProviderContainer(overrides: [...overrides, ...extra]);
}

/// Elle ilerletilen saat (geri sayımlar `DateTime.now()` yerine bunu okur).
class TestClock {
  TestClock([DateTime? start]) : now = start ?? DateTime.utc(2026, 10, 21, 9);

  DateTime now;

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
}

/// Sıradaki sonuçları veren sahte biyometri.
class FakeBiometric implements BiometricAuthenticator {
  FakeBiometric({
    this.supportValue = const BiometricSupport(
      available: true,
      kind: BiometricKind.face,
    ),
    List<BiometricOutcome>? outcomes,
  }) : outcomes = outcomes ?? [];

  BiometricSupport supportValue;
  final List<BiometricOutcome> outcomes;
  int calls = 0;

  @override
  Future<BiometricSupport> support() async => supportValue;

  @override
  Future<BiometricOutcome> authenticate(String reason) async {
    calls++;
    return outcomes.isEmpty ? BiometricOutcome.success : outcomes.removeAt(0);
  }
}

/// Açılan bağlantıların kaydı.
class LinkLog {
  final List<({Uri uri, bool external})> opened = [];

  Future<bool> open(Uri uri, {bool external = false}) async {
    opened.add((uri: uri, external: external));
    return true;
  }

  List<Uri> get uris => [for (final o in opened) o.uri];
}

/// Görüntü boyutu (spec C.7: 360×640).
void setPhoneSize(WidgetTester tester, [Size size = const Size(360, 640)]) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

/// [location] rotasını A1 rotalarıyla (yönlendirme kuralı olmadan) açar. `/home` ve `/profile` boş
/// yer tutuculardır.
Future<ProviderContainer> pumpAuthRoute(
  WidgetTester tester,
  String location, {
  AuthHarness? harness,
  List<Override> overrides = const [],
  double textScale = 1,
  Brightness brightness = Brightness.light,
  bool reduceMotion = false,
  bool accessibleNavigation = false,
  Object? extra,
}) async {
  final h = harness ?? await AuthHarness.create();
  final router = GoRouter(
    initialLocation: location,
    initialExtra: extra,
    routes: [
      ...authRoutes(),
      ...onboardingRoutes(),
      GoRoute(
        path: '/home',
        builder: (context, state) => const Scaffold(body: Text('ANA SAYFA')),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const Scaffold(body: Text('PROFİL')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...h.overrides, ...overrides],
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: router,
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
            accessibleNavigation: accessibleNavigation,
          ),
          child: child!,
        ),
      ),
    ),
  );
  await pumpFor(tester, const Duration(milliseconds: 600));
  return ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
    listen: false,
  );
}

/// Zamanı adım adım ilerletir (animasyonlar ve zamanlayıcılar çalışır).
Future<void> pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

/// [condition] sağlanana kadar kısa adımlarla pompalar (en fazla [max]).
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration max = const Duration(seconds: 5),
}) async {
  const step = Duration(milliseconds: 50);
  for (var t = Duration.zero; t < max && !condition(); t += step) {
    await tester.pump(step);
  }
}

/// Görünür kılıp dokunur. Önce klavye odağı bırakılır: odaklı alan imleci göstermek için listeyi
/// kaydırırken (kısa animasyon) liste dokunuşları yok sayar.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
  await tester.tap(finder);
  await tester.pump();
}

bool isSignedIn(ProviderContainer c) =>
    c.read(sessionControllerProvider) is SessionAuthenticated;

/// Demo personasıyla oturum açar (2FA gerekiyorsa kodu da girer).
Future<void> signIn(
  WidgetTester tester,
  ProviderContainer c,
  String key,
) async {
  await tester.runAsync(() async {
    final s = c.read(sessionControllerProvider.notifier);
    final outcome = await s.loginWithPassword(key, 'demo');
    if (outcome is LoginNeedsCode) {
      await s.verifyCode(outcome.challenge.challengeId, '123456');
    }
  });
  await tester.pump();
}

/// Spec C.7: dokunma hedefleri (Android 48 dp, iOS 44 pt), etiketli hedefler ve metin kontrastı.
Future<void> expectAccessible(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

/// Yazı ölçeği 1,0 ve 2,0 × açık ve koyu tema (spec C.7) için birer test: 360×640, taşma yok,
/// erişilebilirlik yönergeleri.
void a11yMatrix(
  String description,
  Future<void> Function(
    WidgetTester tester,
    double textScale,
    Brightness brightness,
  )
  body,
) {
  for (final scale in const [1.0, 2.0]) {
    for (final b in Brightness.values) {
      testWidgets('$description · ${scale}x · ${b.name}', (tester) async {
        setPhoneSize(tester);
        final semantics = tester.ensureSemantics();
        await body(tester, scale, b);
        expect(tester.takeException(), isNull, reason: 'taşma ya da hata');
        await expectAccessible(tester);
        semantics.dispose();
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}

/// Saat ve bağlantı sağlayıcılarını ezer.
List<Override> clockAndLinks({TestClock? clock, LinkLog? links}) => [
  if (clock != null) authClockProvider.overrideWithValue(clock.call),
  if (links != null) linkOpenerProvider.overrideWithValue(links.open),
];

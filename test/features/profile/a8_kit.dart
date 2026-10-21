// A8 (bildirimler, asistan, hava durumu, profil) test yardımcıları: yalnızca çekirdek + A8 sahteleriyle
// çalışan küçük ortam (diğer özelliklerin sahtelerine bağlı değil), A8 rotalarını açan test
// yönlendiricisi (kural yok; kök gezgin anahtarı uygulamadakiyle aynı), demo girişi, sabit saat,
// bağlantı kaydı, sahte biyometri ve spec C.7 erişilebilirlik denetimleri.
import 'dart:async';

import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/env/app_config_controller.dart';
import 'package:akaryakitnet/core/env/app_env.dart';
import 'package:akaryakitnet/core/env/app_info.dart';
import 'package:akaryakitnet/core/network/fake/core_fakes.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/offline/cache_store.dart';
import 'package:akaryakitnet/core/offline/outbox_store.dart';
import 'package:akaryakitnet/core/routing/nav_keys.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/storage/secure_store.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:akaryakitnet/features/assistant/api.dart';
import 'package:akaryakitnet/features/assistant/assistant_fake.dart';
import 'package:akaryakitnet/features/auth/api.dart';
import 'package:akaryakitnet/features/notifications/api.dart';
import 'package:akaryakitnet/features/notifications/notifications_fake.dart';
import 'package:akaryakitnet/features/profile/api.dart';
import 'package:akaryakitnet/features/profile/profile_fake.dart';
import 'package:akaryakitnet/features/weather/weather_fake.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sabit "şimdi": 21.10.2026 10:00 Türkiye (07:00Z).
final DateTime a8Now = DateTime.utc(2026, 10, 21, 7);

/// Gecikmesiz sahte sunucu (çekirdek + A8 sahteleri), bellek içi depolar.
class A8Harness {
  A8Harness._(this.server, this.prefs, this.secure);

  final FakeServer server;
  final SharedPreferences prefs;
  final MemorySecureStore secure;
  final MemoryCacheStore cache = MemoryCacheStore();
  final MemoryOutboxStore outbox = MemoryOutboxStore();
  final LinkLog links = LinkLog();
  final FakeBio biometric = FakeBio();

  static Future<A8Harness> create({
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues({
      'akn.onboardingDone': true,
      ...prefs,
    });
    final p = await SharedPreferences.getInstance();
    final server = FakeServer.forTests();
    registerCoreFakes(server);
    registerNotificationsFakes(server);
    registerAssistantFakes(server);
    registerWeatherFakes(server);
    registerProfileFakes(server);
    WeatherFakeControls.of(server).now = () => a8Now;
    return A8Harness._(server, p, MemorySecureStore());
  }

  AssistantFakeControls get assistant => AssistantFakeControls.of(server);
  WeatherFakeControls get weather => WeatherFakeControls.of(server);
  NotificationsFakeControls get notifications =>
      NotificationsFakeControls.of(server);
  ProfileFakeControls get profile => ProfileFakeControls.of(server);

  List<Override> get overrides => [
    appEnvProvider.overrideWithValue(AppEnv.fakeForTests),
    appInfoProvider.overrideWithValue(AppInfo.test),
    prefsStoreProvider.overrideWithValue(PrefsStore(prefs)),
    secureStoreProvider.overrideWithValue(secure),
    fakeServerProvider.overrideWithValue(server),
    cacheStoreProvider.overrideWithValue(cache),
    outboxStoreProvider.overrideWithValue(outbox),
    profileLinkOpenerProvider.overrideWithValue(links.open),
    biometricAuthenticatorProvider.overrideWithValue(biometric),
  ];

  ProviderContainer container({List<Override> extra = const []}) =>
      ProviderContainer(overrides: [...overrides, ...extra]);
}

/// Açılan bağlantıların kaydı.
class LinkLog {
  final List<({Uri uri, bool external})> opened = [];

  Future<bool> open(Uri uri, {bool external = false}) async {
    opened.add((uri: uri, external: external));
    return true;
  }

  List<String> get urls => [for (final o in opened) '${o.uri}'];
}

/// Sıradaki sonuçları veren sahte biyometri.
class FakeBio implements BiometricAuthenticator {
  BiometricSupport supportValue = const BiometricSupport(
    available: true,
    kind: BiometricKind.face,
  );
  final List<BiometricOutcome> outcomes = [];
  int calls = 0;

  @override
  Future<BiometricSupport> support() async => supportValue;

  @override
  Future<BiometricOutcome> authenticate(String reason) async {
    calls++;
    return outcomes.isEmpty ? BiometricOutcome.success : outcomes.removeAt(0);
  }
}

/// Görüntü boyutu (spec C.7: 360×640).
void setPhoneSize(WidgetTester tester, [Size size = const Size(360, 640)]) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

/// Saati sabitler (göreli zamanlar, gün başlıkları, hava penceresi).
void fixClock([DateTime? now]) {
  final at = now ?? a8Now;
  TrTime.clock = () => at;
  addTearDown(() => TrTime.clock = () => DateTime.now().toUtc());
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

/// Görünür kılıp dokunur.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tap(finder);
  await tester.pump();
}

/// Demo personasıyla oturum açar (2FA gerekiyorsa kodu da girer) ve uygulama ayarlarını yükler.
Future<void> signIn(
  WidgetTester tester,
  ProviderContainer c,
  String key,
) async {
  await tester.runAsync(() async {
    await c.read(appConfigProvider.notifier).load();
    final s = c.read(sessionControllerProvider.notifier);
    final outcome = await s.loginWithPassword(key, 'demo');
    if (outcome is LoginNeedsCode) {
      await s.verifyCode(outcome.challenge.challengeId, '123456');
    }
  });
  await tester.pump();
}

bool isSignedIn(ProviderContainer c) =>
    c.read(sessionControllerProvider) is SessionAuthenticated;

String? signOutMessage(ProviderContainer c) {
  final s = c.read(sessionControllerProvider);
  return s is SessionUnauthenticated ? s.message : null;
}

/// A8 rotalarını (bildirimler, asistan, profil) + A1 telefon doğrulama + birkaç yer tutucu ile açılan
/// uygulama. Önce [persona] ile giriş yapılır, sonra [location] açılır.
Future<ProviderContainer> pumpA8(
  WidgetTester tester,
  String location, {
  A8Harness? harness,
  String? persona = 'musteri',
  List<Override> overrides = const [],
  double textScale = 1,
  Brightness brightness = Brightness.light,
  bool reduceMotion = false,
  bool accessibleNavigation = false,
  List<RouteBase> extraRoutes = const [],
  Future<void> Function(ProviderContainer c)? beforeOpen,
}) async {
  final h = harness ?? await A8Harness.create();
  AppToast.navigatorKey = rootNavigatorKey;
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/home',
    routes: [
      ...notificationsRoutes(),
      ...assistantRoutes(),
      ...profileRoutes(),
      ...authRoutes(),
      ...extraRoutes,
      GoRoute(
        path: '/home',
        builder: (_, _) => const _Placeholder('ANA SAYFA'),
      ),
      GoRoute(path: '/dev', builder: (_, _) => const _Placeholder('DEV')),
      GoRoute(
        path: '/orders/:id',
        builder: (_, s) => _Placeholder('SİPARİŞ ${s.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/shipments/:id',
        builder: (_, s) => _Placeholder('TESLİMAT ${s.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/approvals/:id',
        builder: (_, s) => _Placeholder('ONAY ${s.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/bayi/orders/:id',
        builder: (_, s) =>
            _Placeholder('BAYİ SİPARİŞ ${s.pathParameters['id']}'),
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
  final c = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
    listen: false,
  );
  if (persona != null) await signIn(tester, c, persona);
  if (beforeOpen != null) {
    await tester.runAsync(() => beforeOpen(c));
  }
  if (location != '/home') unawaited(router.push(location));
  await pumpFor(tester, const Duration(milliseconds: 800));
  return c;
}

/// Testin sonunda: açık bildirimi kapatır, ağacı söker.
Future<void> finish(WidgetTester tester) async {
  AppToast.dismiss();
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text(text)));
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
        await finish(tester);
      });
    }
  }
}

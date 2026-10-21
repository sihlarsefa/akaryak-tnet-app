import 'dart:async';

import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/env/app_env.dart';
import 'package:akaryakitnet/core/env/app_info.dart';
import 'package:akaryakitnet/core/network/fake/core_fakes.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/offline/cache_store.dart';
import 'package:akaryakitnet/core/routing/nav_keys.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/storage/secure_store.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/customer_home/api.dart';
import 'package:akaryakitnet/features/customer_home/customer_home_fake.dart';
import 'package:akaryakitnet/features/customer_orders/api.dart';
import 'package:akaryakitnet/features/customer_orders/application/retry_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gerçek olay döngüsünde [condition] sağlanana kadar bekler (en çok ~2 sn).
Future<void> settle(bool Function() condition, {int rounds = 400}) async {
  for (var i = 0; i < rounds && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// A2 testleri için ortam: gecikmesiz sahte sunucu (çekirdek + A2 sahteleri; diğer özelliklerin
/// süren işlerinden bağımsız), bellek içi önbellek ve güvenli depo, sahte tercihler. Ağ yok.
class A2Env {
  A2Env._(this.server, this.prefs, this.cache);

  final FakeServer server;
  final SharedPreferences prefs;
  final MemoryCacheStore cache;
  final MemorySecureStore secure = MemorySecureStore();

  /// Bekleme süreleri (yeniden deneme planı); anında döner.
  final List<Duration> waits = [];

  FakeWorld get world => server.world;
  CustomerOrdersFakeControls get controls =>
      CustomerOrdersFakeControls.of(world);

  static Future<A2Env> create({
    MemoryCacheStore? cache,
    FakeWorld? world,
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues({
      'akn.onboardingDone': true,
      ...prefs,
    });
    final p = await SharedPreferences.getInstance();
    final server = FakeServer.forTests(world: world ?? FakeWorld.seeded());
    registerCoreFakes(server);
    registerCustomerHomeFakes(server);
    registerCustomerOrdersFakes(server);
    return A2Env._(server, p, cache ?? MemoryCacheStore());
  }

  List<Override> overrides({List<Override> extra = const []}) => [
    appEnvProvider.overrideWithValue(AppEnv.fakeForTests),
    appInfoProvider.overrideWithValue(AppInfo.test),
    prefsStoreProvider.overrideWithValue(PrefsStore(prefs)),
    secureStoreProvider.overrideWithValue(secure),
    fakeServerProvider.overrideWithValue(server),
    cacheStoreProvider.overrideWithValue(cache),
    a2WaitProvider.overrideWithValue((d) async => waits.add(d)),
    ...extra,
  ];

  ProviderContainer container({List<Override> extra = const []}) =>
      ProviderContainer(overrides: overrides(extra: extra));

  /// Oturum açmış kapsayıcı (birim testleri).
  Future<ProviderContainer> signedIn(
    String persona, {
    List<Override> extra = const [],
  }) async {
    final c = container(extra: extra);
    final s = c.read(sessionControllerProvider.notifier);
    await s.restore();
    await s.loginWithPassword(persona, 'demo');
    expect(c.read(sessionControllerProvider), isA<SessionAuthenticated>());
    return c;
  }
}

/// Bilinmeyen rotaya gidildiğinde gösterilen sayfa: hedef `ROUTE:/yol?x=1` metniyle okunur.
class RouteProbe extends StatelessWidget {
  const RouteProbe({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('ROUTE:$location')));
}

/// Sayfayı uygulama teması, Türkçe yerel ayar ve A2 rotalarıyla açar.
Future<GoRouter> pumpA2(
  WidgetTester tester,
  ProviderContainer container, {
  required String initialLocation,
  Brightness brightness = Brightness.light,
  double textScale = 1,
  bool reduceMotion = true,
  Size size = const Size(360, 640),
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/home', builder: (_, _) => const CustomerHome()),
      ...customerOrdersRoutes(),
      ...customerHomeRoutes(),
    ],
    errorBuilder: (context, state) =>
        RouteProbe(location: state.uri.toString()),
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
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
            disableAnimations: reduceMotion,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
      ),
    ),
  );
  return router;
}

/// Gerçek zamanlı işleri (sahte sunucu, önbellek) tamamlatıp kareleri çizer.
Future<void> pumpReal(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// [finder] görünene kadar gerçek zamanlı bekler.
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  int rounds = 60,
}) async {
  for (var i = 0; i < rounds; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await pumpReal(tester, rounds: 1);
  }
}

/// Spec C.7 erişilebilirlik denetimleri.
Future<void> expectA11y(WidgetTester tester, {bool contrast = true}) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  if (contrast) {
    await expectLater(tester, meetsGuideline(textContrastGuideline));
  }
}

/// Testin sonunda ağaç ve zamanlayıcılar temizlenir.
Future<void> tearDownUi(WidgetTester tester) async {
  AppToast.dismiss();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 4));
}

/// Kullanılmayan uyarısı için.
void ignore(Object? _) {}

/// Kullanıcı tanımlı tamamlayıcı (asılı yanıt).
Completer<T> hold<T>() => Completer<T>();

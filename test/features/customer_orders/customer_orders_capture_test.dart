// Müşteri sipariş ekranlarının görüntüleri (tasarım v2 §7.7–7.10; pano ekran 4 ve 5 ile göz
// karşılaştırması için). Altın test değildir; normal çalışmada atlanır:
//
//   flutter test test/features/customer_orders/customer_orders_capture_test.dart \
//     --dart-define=AKN_SCREENS_DIR=/tam/yol
//
// 390 × 844 dp (iPhone, 2× piksel), gerçek Mona Sans ve Material simgeleriyle; açık 1,0×, koyu
// 1,0× ve açık 2,0×. Siparişlerim (karar / aktif / geçmiş), sipariş ayrıntısı (karar, yolda, teklif
// bekleyen, tamamlanan), sihirbazın dört adımı ve sonuç ekranı.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:akaryakitnet/core/auth/session_controller.dart';
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
import 'package:akaryakitnet/features/customer_home/customer_home_fake.dart';
import 'package:akaryakitnet/features/customer_orders/api.dart';
import 'package:akaryakitnet/features/customer_orders/application/retry_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fonts.dart';

// Bu dosya `support/a2_support.dart`'ı içe aktarmaz: müşteri ana sayfası (istatistik destesi)
// derlenmeden de sipariş ekranları görüntülenebilsin.

/// Gerçek zamanlı işleri tamamlatıp kareleri çizer.
Future<void> pumpReal(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

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

class _Env {
  _Env(this.server, this.prefs);

  final FakeServer server;
  final SharedPreferences prefs;
  final cache = MemoryCacheStore();
  final secure = MemorySecureStore();

  FakeWorld get world => server.world;

  static Future<_Env> create() async {
    SharedPreferences.setMockInitialValues({'akn.onboardingDone': true});
    final p = await SharedPreferences.getInstance();
    final server = FakeServer.forTests(world: FakeWorld.seeded());
    registerCoreFakes(server);
    registerCustomerHomeFakes(server);
    registerCustomerOrdersFakes(server);
    return _Env(server, p);
  }

  Future<ProviderContainer> signedIn(String persona) async {
    final c = ProviderContainer(
      overrides: [
        appEnvProvider.overrideWithValue(AppEnv.fakeForTests),
        appInfoProvider.overrideWithValue(AppInfo.test),
        prefsStoreProvider.overrideWithValue(PrefsStore(prefs)),
        secureStoreProvider.overrideWithValue(secure),
        fakeServerProvider.overrideWithValue(server),
        cacheStoreProvider.overrideWithValue(cache),
        a2WaitProvider.overrideWithValue((d) async {}),
      ],
    );
    final s = c.read(sessionControllerProvider.notifier);
    await s.restore();
    await s.loginWithPassword(persona, 'demo');
    return c;
  }
}

const _outDir = String.fromEnvironment('AKN_SCREENS_DIR');

final _key = GlobalKey();

Future<void> _shot(WidgetTester tester, String name) async {
  final boundary =
      _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_outDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<GoRouter> _pump(
  WidgetTester tester,
  ProviderContainer container, {
  required String location,
  required Brightness brightness,
  required double scale,
}) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(390, 844) * 2;
  tester.view.padding = const FakeViewPadding(top: 47 * 2, bottom: 34 * 2);
  tester.view.viewPadding = const FakeViewPadding(top: 47 * 2, bottom: 34 * 2);
  addTearDown(tester.view.reset);
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: location,
    routes: [...customerOrdersRoutes()],
    errorBuilder: (context, state) =>
        Scaffold(body: Center(child: Text('ROUTE:${state.uri}'))),
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _key,
      child: UncontrolledProviderScope(
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
              disableAnimations: true,
              textScaler: TextScaler.linear(scale),
            ),
            child: child!,
          ),
        ),
      ),
    ),
  );
  return router;
}

void main() {
  setUpAll(() async {
    if (_outDir.isNotEmpty) await loadRealFonts();
  });

  const variants = [
    ('acik-1x', Brightness.light, 1.0),
    ('koyu-1x', Brightness.dark, 1.0),
    ('acik-2x', Brightness.light, 2.0),
  ];

  for (final (tag, brightness, scale) in variants) {
    testWidgets('siparişlerim ve ayrıntı $tag', (tester) async {
      debugDisableShadows = false;
      final env = await tester.runAsync(_Env.create);
      final w = env!.world;
      int idOf(bool Function(Map<String, dynamic> o) test) =>
          w.orders.firstWhere(test)['id'] as int;
      final decision = idOf((o) => o['status'] == 2);
      final transit = idOf((o) => o['status'] == 3 && o['customerId'] == 101);
      final waiting = idOf((o) => o['status'] == 1 && o['customerId'] == 101);
      final done = w.orders
          .where((o) => o['status'] == 7 && o['customerId'] == 101)
          .map((o) => o['id'] as int)
          .firstOrNull;
      final c = (await tester.runAsync(() => env.signedIn('musteri')))!;
      addTearDown(c.dispose);

      Future<void> open(String location, String name, {Finder? until}) async {
        await _pump(
          tester,
          c,
          location: location,
          brightness: brightness,
          scale: scale,
        );
        await pumpUntil(tester, until ?? find.byType(AknListTile));
        await pumpReal(tester, rounds: 10);
        await _shot(tester, '$tag/$name');
      }

      await open('/orders?segment=decision', 'siparisler_1_karar');
      await open('/orders?segment=active', 'siparisler_2_aktif');
      await open('/orders?segment=history', 'siparisler_3_gecmis');
      await open(
        '/orders/$decision',
        'detay_1_karar',
        until: find.byType(AknPlate),
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -380));
      await pumpReal(tester, rounds: 4);
      await _shot(tester, '$tag/detay_1_karar_orta');
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await pumpReal(tester, rounds: 4);
      await _shot(tester, '$tag/detay_1_karar_alt');
      await open(
        '/orders/$transit',
        'detay_2_yolda',
        until: find.byType(AknPlate),
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await pumpReal(tester, rounds: 4);
      await _shot(tester, '$tag/detay_2_yolda_alt');
      await open(
        '/orders/$waiting',
        'detay_3_teklif_bekleniyor',
        until: find.byType(AknFlowLine),
      );
      if (done != null) {
        await open(
          '/orders/$done',
          'detay_4_tamamlandi',
          until: find.byType(AknFlowLine),
        );
      }
      AppToast.dismiss();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
      debugDisableShadows = true;
    }, skip: _outDir.isEmpty);

    testWidgets('sihirbaz $tag', (tester) async {
      debugDisableShadows = false;
      final env = await tester.runAsync(_Env.create);
      final c = (await tester.runAsync(() => env!.signedIn('musteri')))!;
      addTearDown(c.dispose);
      await _pump(
        tester,
        c,
        location: '/orders/new',
        brightness: brightness,
        scale: scale,
      );
      await pumpUntil(tester, find.byType(ChoiceCard));
      await pumpReal(tester, rounds: 8);
      await _shot(tester, '$tag/sihirbaz_1_urun_bos');
      final motorin = find.widgetWithText(ChoiceCard, 'Motorin').first;
      await tester.ensureVisible(motorin);
      await tester.pump();
      await tester.tap(motorin);
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, '8000');
      await pumpReal(tester, rounds: 4);
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await pumpReal(tester, rounds: 4);
      await _shot(tester, '$tag/sihirbaz_1_urun');
      Future<void> next() async {
        await tester.tap(find.widgetWithText(AknButton, 'Devam'));
        await pumpReal(tester, rounds: 10);
      }

      await next();
      await _shot(tester, '$tag/sihirbaz_2_teslimat');
      await next();
      await _shot(tester, '$tag/sihirbaz_3_odeme');
      final nakit = find.widgetWithText(ChoiceCard, 'Nakit');
      if (nakit.evaluate().isNotEmpty) {
        await tester.ensureVisible(nakit.first);
        await tester.pump();
        await tester.tap(nakit.first);
        await pumpReal(tester, rounds: 4);
      }
      await next();
      await _shot(tester, '$tag/sihirbaz_4_ozet');
      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await pumpReal(tester, rounds: 4);
      await _shot(tester, '$tag/sihirbaz_4_ozet_alt');
      final send = find.widgetWithText(AknButton, OrdersCopy.send);
      if (send.evaluate().isNotEmpty) {
        await tester.tap(send);
        await pumpReal(tester, rounds: 20);
        await _shot(tester, '$tag/sihirbaz_5_sonuc');
      }
      AppToast.dismiss();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
      debugDisableShadows = true;
    }, skip: _outDir.isEmpty);
  }
}

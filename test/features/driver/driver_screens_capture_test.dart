// Şoför ekranlarının görüntüleri (tasarım v2 tahta ekran 6 ile karşılaştırmak için). Normal test
// çalışmasında atlanır; görüntü almak için:
//
//   flutter test test/features/driver/driver_screens_capture_test.dart \
//     --dart-define=AKN_SCREENS_DIR=/tam/yol/klasor
//
// 390 × 844 pt, 2× piksel, gerçek Mona Sans (test/flutter_test_config.dart yükler). Ana sayfa alttaki
// şoför menüsüyle (Teslimat, Bildirim, Asistan, Profil) çizilir. Altın karşılaştırma değildir.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:akaryakitnet/core/routing/nav_keys.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/driver/api.dart';
import 'package:akaryakitnet/features/driver/application/driver_lists.dart';
import 'package:akaryakitnet/features/driver/data/driver_models.dart';
import 'package:akaryakitnet/features/driver/presentation/deliver_flow_page.dart';
import 'package:akaryakitnet/features/driver/presentation/shipment_detail_page.dart';
import 'package:akaryakitnet/features/driver/presentation/widgets/litre_keypad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/driver_harness.dart';

const _outDir = String.fromEnvironment('AKN_SCREENS_DIR');

/// Pendik Lojistik Merkezi'ne kuş uçuşu ~17 km (Ataşehir).
const _farLat = 40.9923;
const _farLng = 29.1244;

Widget _app(
  ProviderContainer c,
  String location, {
  required GlobalKey boundary,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) {
  final shellKey = GlobalKey<NavigatorState>();
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: location,
    routes: [
      ShellRoute(
        navigatorKey: shellKey,
        builder: (context, state, child) => Scaffold(
          body: child,
          bottomNavigationBar: AknDriverScope(
            child: AnimatedBottomBar(
              currentIndex: 0,
              onSelected: (_) {},
              items: const [
                AknNavItem(
                  icon: PhosphorIconsRegular.truck,
                  selectedIcon: PhosphorIconsFill.truck,
                  label: 'Teslimat',
                ),
                AknNavItem(
                  icon: PhosphorIconsRegular.bell,
                  selectedIcon: PhosphorIconsFill.bell,
                  label: 'Bildirim',
                  badgeCount: 1,
                ),
                AknNavItem(
                  icon: PhosphorIconsRegular.chatCircle,
                  selectedIcon: PhosphorIconsFill.chatCircle,
                  label: 'Asistan',
                ),
                AknNavItem(
                  icon: PhosphorIconsRegular.user,
                  selectedIcon: PhosphorIconsFill.user,
                  label: 'Profil',
                ),
              ],
            ),
          ),
        ),
        routes: driverRoutes(),
      ),
    ],
  );
  AppToast.navigatorKey = rootNavigatorKey;
  return RepaintBoundary(
    key: boundary,
    child: UncontrolledProviderScope(
      container: c,
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
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
      ),
    ),
  );
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_outDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = const Size(780, 1688);
  tester.view.padding = const FakeViewPadding(top: 94, bottom: 68);
  tester.view.viewPadding = const FakeViewPadding(top: 94, bottom: 68);
  addTearDown(tester.view.reset);
}

enum _Scene { board, real }

void main() {
  late DriverHarness h;
  late ProviderContainer c;

  Future<void> boot(
    WidgetTester tester, {
    _Scene scene = _Scene.board,
    bool offline = false,
  }) async {
    _phone(tester);
    h = await real(
      tester,
      () => DriverHarness.create(
        prefs: {
          'akn.onboardingDone': true,
          if (scene == _Scene.board) 'akn.driver.slideTipSeen.u-sofor': true,
        },
      ),
    );
    c = h.container();
    await tester.runAsync(() => DriverHarness.login(c, 'sofor'));
    if (scene == _Scene.board) {
      // Tahtadaki an: yoldayken noktaya ~17 km, itiraz yok.
      h.location
        ..latitude = _farLat
        ..longitude = _farLng;
      for (final s in h.world.shipments) {
        if (s['status'] == 4) s['status'] = 3;
      }
    }
    if (offline) c.read(testOnlineProvider.notifier).state = false;
  }

  Future<void> show(
    WidgetTester tester,
    GlobalKey key,
    String location, {
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    await tester.pumpWidget(
      _app(
        c,
        location,
        boundary: key,
        brightness: brightness,
        textScale: textScale,
      ),
    );
    await pumpUntil(
      tester,
      () => c.read(driverListProvider(DriverTab.today)).hasValue,
    );
    await settleReal(tester);
    await pumpFor(tester, const Duration(milliseconds: 1200));
    await settleReal(tester);
    await pumpFor(tester, const Duration(milliseconds: 600));
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await pumpFor(tester, const Duration(milliseconds: 300));
    c.dispose();
    h.dispose();
  }

  int shipmentId(int status) =>
      h.world.shipments.firstWhere(
            (s) => s['status'] == status && s['driverUserId'] == 'u-sofor',
          )['id']
          as int;

  final variants = <(String, Brightness, double)>[
    ('light-1x', Brightness.light, 1),
    ('dark-1x', Brightness.dark, 1),
    ('light-1.3x', Brightness.light, 1.3),
    ('light-2x', Brightness.light, 2),
  ];

  for (final (tag, b, scale) in variants) {
    testWidgets('ana sayfa (tahta), $tag', (tester) async {
      final key = GlobalKey();
      await boot(tester, offline: true);
      await show(tester, key, '/driver', brightness: b, textScale: scale);
      await _shot(tester, key, 'home-board-$tag');
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await pumpFor(tester, const Duration(milliseconds: 600));
      await _shot(tester, key, 'home-board-$tag-scrolled');
      expect(tester.takeException(), isNull);
      await finish(tester);
    }, skip: _outDir.isEmpty);
  }

  testWidgets('ana sayfa (gerçek sahte veri: itiraz, ipucu, noktada)', (
    tester,
  ) async {
    final key = GlobalKey();
    await boot(tester, scene: _Scene.real);
    await show(tester, key, '/driver');
    await _shot(tester, key, 'home-real-light-1x');
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await pumpFor(tester, const Duration(milliseconds: 600));
    await _shot(tester, key, 'home-real-light-1x-scrolled');
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await pumpFor(tester, const Duration(milliseconds: 600));
    await _shot(tester, key, 'home-real-light-1x-scrolled2');
    expect(tester.takeException(), isNull);
    await finish(tester);
  }, skip: _outDir.isEmpty);

  for (final (tag, b, scale) in variants) {
    testWidgets('ayrıntı: yolda ve planlı, $tag', (tester) async {
      final key = GlobalKey();
      await boot(tester);
      final moving = shipmentId(1);
      final planned = shipmentId(0);
      await show(
        tester,
        key,
        '/driver/shipments/$moving',
        brightness: b,
        textScale: scale,
      );
      expect(find.byType(ShipmentDetailPage), findsOneWidget);
      await _shot(tester, key, 'detail-intransit-$tag');
      await tester.drag(find.byType(ListView).first, const Offset(0, -700));
      await pumpFor(tester, const Duration(milliseconds: 600));
      await _shot(tester, key, 'detail-intransit-$tag-scrolled');
      await tester.pumpWidget(const SizedBox());
      await show(
        tester,
        key,
        '/driver/shipments/$planned',
        brightness: b,
        textScale: scale,
      );
      await _shot(tester, key, 'detail-planned-$tag');
      expect(tester.takeException(), isNull);
      await finish(tester);
    }, skip: _outDir.isEmpty);
  }

  testWidgets('ayrıntı: itirazlı ve kabul bekleyen', (tester) async {
    final key = GlobalKey();
    await boot(tester, scene: _Scene.real);
    await show(tester, key, '/driver/shipments/${shipmentId(4)}');
    await _shot(tester, key, 'detail-disputed-light-1x');
    await tester.pumpWidget(const SizedBox());
    await show(tester, key, '/driver/shipments/${shipmentId(2)}');
    await _shot(tester, key, 'detail-reported-light-1x');
    expect(tester.takeException(), isNull);
    await finish(tester);
  }, skip: _outDir.isEmpty);

  for (final (tag, b, scale) in variants) {
    testWidgets(
      'teslim sihirbazı: adımlar, $tag',
      (tester) async {
        final key = GlobalKey();
        await boot(tester);
        final id = shipmentId(1);
        await show(
          tester,
          key,
          '/driver/shipments/$id/deliver',
          brightness: b,
          textScale: scale,
        );
        expect(find.byType(DeliverFlowPage), findsOneWidget);
        await _shot(tester, key, 'deliver-1-liters-empty-$tag');
        Finder k(String label) => find.descendant(
          of: find.byType(DeliverFlowPage),
          matching: find.bySemanticsLabel(label),
        );
        await tester.scrollUntilVisible(
          find.byType(LitreKeypad),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        for (final d in ['9', '9', '8', '0']) {
          await tester.ensureVisible(k(d).first);
          await tester.pump();
          await tester.tap(k(d).first);
          await tester.pump(const Duration(milliseconds: 60));
        }
        await pumpFor(tester, const Duration(milliseconds: 400));
        await _shot(tester, key, 'deliver-1-liters-$tag');
        Future<void> next() async {
          await tester.ensureVisible(find.text('İleri'));
          await tester.tap(find.text('İleri'));
          await settleReal(tester);
          await pumpFor(tester, const Duration(milliseconds: 700));
        }

        await next();
        await tester.enterText(find.byType(TextField).first, 'IRS-5001');
        await pumpFor(tester, const Duration(milliseconds: 300));
        await _shot(tester, key, 'deliver-2-document-$tag');
        await next();
        await _shot(tester, key, 'deliver-3-recipient-$tag');
        await next();
        await _shot(tester, key, 'deliver-4-photos-empty-$tag');
        await tester.ensureVisible(find.text('Fotoğraf çek').last);
        await tester.pump();
        await tester.tap(find.text('Fotoğraf çek').last);
        await pumpUntil(
          tester,
          () => find.text('1 fotoğraf').evaluate().isNotEmpty,
        );
        await pumpFor(tester, const Duration(milliseconds: 500));
        await _shot(tester, key, 'deliver-4-photos-$tag');
        await next();
        await _shot(tester, key, 'deliver-5-signature-$tag');
        await tester.ensureVisible(find.text('İmza alınamıyor'));
        await tester.pump();
        await tester.tap(find.text('İmza alınamıyor'));
        await pumpFor(tester, const Duration(milliseconds: 600));
        await _shot(tester, key, 'deliver-5-waiver-sheet-$tag');
        await tester.ensureVisible(
          find.bySemanticsLabel(RegExp('^İmzadan imtina')),
        );
        await tester.tap(find.bySemanticsLabel(RegExp('^İmzadan imtina')));
        await pumpFor(tester, const Duration(milliseconds: 200));
        await tester.ensureVisible(find.text('Nedeni kaydet'));
        await tester.pump();
        await tester.tap(find.text('Nedeni kaydet'));
        await pumpFor(tester, const Duration(milliseconds: 600));
        await _shot(tester, key, 'deliver-5-waived-$tag');
        await next();
        await settleReal(tester);
        await pumpFor(tester, const Duration(milliseconds: 600));
        await _shot(tester, key, 'deliver-6-summary-$tag');
        c.read(testOnlineProvider.notifier).state = false;
        await tester.pump();
        tester.semantics.tap(
          find.semantics.byLabel('Teslimatı kaydetmek için kaydırın'),
        );
        await settleReal(tester);
        await pumpFor(tester, const Duration(milliseconds: 1200));
        await _shot(tester, key, 'deliver-7-result-queued-$tag');
        expect(tester.takeException(), isNull);
        await finish(tester);
      },
      semanticsEnabled: true,
      skip: _outDir.isEmpty,
    );
  }
}

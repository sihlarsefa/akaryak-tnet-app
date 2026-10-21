// Bayi operasyon ekranlarının görüntüleri (tasarım v2 "Turuncu Plaka" karşılaştırması): Teklif masası,
// Siparişler, sipariş ayrıntısı (+ teklif sayfası), Sevkiyat panosu (+ planlama sayfası), Cariler,
// Cari 360, Ekip (Onaylarım: `test/features/approvals/approvals_capture_test.dart`). Normal test çalışmasında atlanır; görüntü almak için:
//
//   flutter test test/features/bayi/bayi_ops_capture_test.dart --dart-define=AKN_SCREENS_DIR=/tam/yol
//
// 390×844 dp, 2× piksel; açık 1,0×, koyu 1,0× ve açık 2,0× yazı. Altın (golden) karşılaştırma değildir.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/offline/connectivity.dart';
import 'package:akaryakitnet/core/routing/nav_keys.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/bayi/bayi_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fonts.dart';
import 'support/bayi_harness.dart';

/// Yalnızca bayi operasyon rotalarıyla (ana sayfa ve istatistik yok) uygulama: paralel geliştirilen
/// başka bir özelliğin derlenmeyen dosyası görüntü almayı durdurmasın.
class _App {
  _App(this.harness, this.container, this.router);

  final BayiHarness harness;
  final ProviderContainer container;
  final GoRouter router;

  static Future<_App> start(
    WidgetTester tester, {
    required String persona,
    required String location,
    required Size size,
    Brightness brightness = Brightness.light,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    late BayiHarness h;
    await tester.runAsync(() async => h = await BayiHarness.create());
    final c = h.container(extra: [isOnlineProvider.overrideWithValue(true)]);
    await tester.runAsync(() => BayiHarness.login(c, persona));
    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: location,
      routes: [
        ...bayiRoutes(),
        for (final p in const ['/approvals/:id', '/payments/:id', '/home'])
          GoRoute(path: p, builder: (context, state) => const SizedBox()),
      ],
    );
    AppToast.navigatorKey = rootNavigatorKey;
    await tester.pumpWidget(
      UncontrolledProviderScope(
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
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: true,
            ),
            child: child!,
          ),
        ),
      ),
    );
    await settle(tester);
    return _App(h, c, router);
  }

  Future<void> push(WidgetTester tester, String location) async {
    unawaited(router.push(location));
    await settle(tester);
  }

  static Future<void> settle(WidgetTester tester, {int rounds = 12}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 4)),
      );
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> finish(WidgetTester tester) async {
    AppToast.dismiss();
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  }
}

const _outDir = String.fromEnvironment('AKN_SCREENS_DIR');
const _only = String.fromEnvironment('AKN_ONLY');

const _size = Size(390, 844);

Future<void> _shot(WidgetTester tester, String name) async {
  final element = tester.element(find.byType(MaterialApp).first);
  await tester.runAsync(() async {
    var ro = element.renderObject;
    while (ro != null && !ro.isRepaintBoundary) {
      ro = ro.parent;
    }
    final layer = ro!.debugLayer! as OffsetLayer;
    final image = await layer.toImage(
      Offset.zero & ro.paintBounds.size,
      pixelRatio: 2,
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_outDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

typedef _Variant = ({String tag, Brightness b, double scale});

const List<_Variant> _variants = [
  (tag: 'light', b: Brightness.light, scale: 1),
  (tag: 'dark', b: Brightness.dark, scale: 1),
  (tag: 'light-2x', b: Brightness.light, scale: 2),
];

/// Ekranı açar, görüntüyü alır; [then] sonrası ek görüntüler.
void _bayi(
  String name, {
  required String persona,
  required String location,
  String Function(_App app)? push,
  Future<void> Function(WidgetTester tester, _App app, String tag)?
  then,
}) {
  for (final v in _variants) {
    testWidgets('$name ${v.tag}', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = true);
      final app = await _App.start(
        tester,
        persona: persona,
        location: location,
        size: _size,
        brightness: v.b,
        textScale: v.scale,
      );
      if (push != null) await app.push(tester, push(app));
      await _App.settle(tester);
      await _shot(tester, '$name-${v.tag}');
      if (then != null) await then(tester, app, v.tag);
      debugDisableShadows = true;
      await app.finish(tester);
    }, skip: _outDir.isEmpty || (_only.isNotEmpty && !name.startsWith(_only)));
  }
}

Map<String, dynamic> _order(_App app, OrderStatus status) =>
    app.harness.world.orders.firstWhere(
      (o) => o['status'] == status.code && o['stationId'] == 1,
    );

void main() {
  setUpAll(() async {
    if (_outDir.isNotEmpty) await loadRealFonts();
  });

  _bayi('01-desk', persona: 'siparis', location: '/quote-desk');
  _bayi('02-orders', persona: 'sahip', location: '/bayi/orders');
  _bayi(
    '03-order-quote',
    persona: 'sahip',
    location: '/bayi/orders',
    push: (app) =>
        '/bayi/orders/${_order(app, OrderStatus.awaitingApproval)['id']}',
  );
  _bayi(
    '04-order-new',
    persona: 'sahip',
    location: '/bayi/orders',
    push: (app) =>
        '/bayi/orders/${_order(app, OrderStatus.awaitingQuote)['id']}',
    then: (tester, app, tag) async {
      final f = find.text('Teklif ver');
      if (f.evaluate().isEmpty) return;
      await tester.tap(f.last, warnIfMissed: false);
      await _App.settle(tester);
      await _shot(tester, '05-quote-sheet-$tag');
    },
  );
  _bayi(
    '06-order-approved',
    persona: 'sahip',
    location: '/bayi/orders',
    push: (app) => '/bayi/orders/${_order(app, OrderStatus.approved)['id']}',
  );
  _bayi(
    '07-dispatch',
    persona: 'sevkiyat',
    location: '/dispatch',
    then: (tester, app, tag) async {
      final f = find.text('Planla');
      if (f.evaluate().isEmpty) return;
      await tester.ensureVisible(f.first);
      await tester.tap(f.first, warnIfMissed: false);
      await _App.settle(tester);
      await _shot(tester, '08-plan-sheet-$tag');
    },
  );
  _bayi('09-customers', persona: 'sahip', location: '/customers');
  _bayi('10-customer', persona: 'sahip', location: '/customers/101');
  _bayi('11-staff', persona: 'sahip', location: '/bayi/staff');
}

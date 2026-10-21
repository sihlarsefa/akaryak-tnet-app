// Müşteri ekranlarının görüntüleri (tasarım v2 "Turuncu Plaka", pano ekran 2 ve 9 ile karşılaştırma).
// Normal test çalışmasında atlanır; görüntü almak için:
//
//   flutter test test/features/customer_home/customer_screens_capture_test.dart \
//     --dart-define=AKN_SCREENS_DIR=/tam/yol/customer-home
//
// Uygulamanın tamamı (kabuk, alt menü, sahte sunucu) 390×844 dp telefonda açılır; ana sayfa ve müşteri
// sayfaları (Limitlerim, Belgeler, Harcamalar, Teslimat noktaları, Kullanıcılar, Sevkiyatlar, sevkiyat
// ayrıntısı, Talepler, Finans ek bilgi) 2× piksel PNG olarak yazılır. Altın karşılaştırma değildir.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/routing/app_routes.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/a11y.dart';
import '../../support/test_app.dart';

const _outDir = String.fromEnvironment('AKN_SCREENS_DIR');

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
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

void main() {
  const phone = Size(390, 844);

  late TestHarness harness;

  Future<ProviderContainer> boot(
    WidgetTester tester,
    GlobalKey key,
    String persona,
    A11yVariant v, {
    Size size = phone,
  }) async {
    setA11yPhone(tester, size: size);
    setA11yPlatform(tester, v);
    debugDisableShadows = false;
    tester.view.padding = const FakeViewPadding(top: 54, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 54, bottom: 34);
    final h = harness = await TestHarness.create(
      prefs: const {'akn.onboardingDone': true},
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ProviderScope(overrides: h.overrides, child: const AknApp()),
      ),
    );
    await pumpSteps(tester, const Duration(seconds: 2));
    final c = ProviderScope.containerOf(tester.element(find.byType(AknApp)));
    await tester.runAsync(() async {
      final s = c.read(sessionControllerProvider.notifier);
      await s.loginWithPassword(persona, 'demo');
    });
    await pumpSteps(tester, const Duration(seconds: 3));
    expect(c.read(sessionControllerProvider), isA<SessionAuthenticated>());
    await settleIo(tester);
    await pumpSteps(tester, const Duration(seconds: 2));
    await settleIo(tester);
    await pumpSteps(tester, const Duration(milliseconds: 800));
    return c;
  }

  Future<void> open(
    WidgetTester tester,
    ProviderContainer c,
    String loc,
  ) async {
    unawaited(c.read(routerProvider).push(loc));
    await pumpSteps(tester, const Duration(seconds: 1));
    await settleIo(tester);
    await pumpSteps(tester, const Duration(milliseconds: 800));
    await settleIo(tester);
    await pumpSteps(tester, const Duration(milliseconds: 400));
  }

  Future<void> back(WidgetTester tester, ProviderContainer c) async {
    c.read(routerProvider).pop();
    await pumpSteps(tester, const Duration(milliseconds: 600));
  }

  const variants = [
    ('acik-1x', A11yVariant(1, Brightness.light)),
    ('koyu-1x', A11yVariant(1, Brightness.dark)),
    ('acik-2x', A11yVariant(2, Brightness.light)),
    ('koyu-2x', A11yVariant.largeDark),
  ];

  for (final persona in ['musteri', 'talep', 'onay']) {
    for (final (tag, v) in variants) {
      if (persona != 'musteri' && tag != 'acik-1x') continue;
      testWidgets('$persona $tag ana sayfa', (tester) async {
        final key = GlobalKey();
        await boot(tester, key, persona, v);
        await _capture(tester, key, '$persona/home_$tag');
        await tester.pumpWidget(const SizedBox());
        debugDisableShadows = true;
      }, skip: _outDir.isEmpty);
    }
    testWidgets('$persona ana sayfa (uzun)', (tester) async {
      final key = GlobalKey();
      await boot(
        tester,
        key,
        persona,
        const A11yVariant(1, Brightness.light),
        size: const Size(390, 2000),
      );
      await _capture(tester, key, '$persona/home_tall');
      await tester.pumpWidget(const SizedBox());
      debugDisableShadows = true;
    }, skip: _outDir.isEmpty);
  }

  const pages = [
    ('limits', AppRoutes.limits),
    ('documents', AppRoutes.documents),
    ('spending', AppRoutes.spending),
    ('delivery_points', AppRoutes.deliveryPoints),
    ('company_users', AppRoutes.companyUsers),
    ('shipments', AppRoutes.shipments),
    ('requests', AppRoutes.companyRequests),
    ('finance_info', AppRoutes.financeInfo),
  ];
  for (final (tag, v) in [
    ('acik-1x', const A11yVariant(1, Brightness.light)),
    ('koyu-1x', const A11yVariant(1, Brightness.dark)),
    ('acik-2x', const A11yVariant(2, Brightness.light)),
  ]) {
    testWidgets('musteri sayfaları $tag', (tester) async {
      final key = GlobalKey();
      final c = await boot(tester, key, 'musteri', v);
      for (final (name, loc) in pages) {
        await open(tester, c, loc);
        await _capture(tester, key, 'pages/${name}_$tag');
        await back(tester, c);
      }
      // Müşterinin her durumdan bir sevkiyatı (planlı, yolda, teslim bildirildi, kabul, itirazlı).
      final world = harness.server.world;
      for (final status in const [0, 1, 2, 3, 4]) {
        final ship = world.shipments
            .where((x) => x['customerId'] == 101 && x['status'] == status)
            .firstOrNull;
        if (ship == null) continue;
        await open(tester, c, AppRoutes.shipment(ship['id'] as int));
        await _capture(tester, key, 'pages/shipment_s${status}_$tag');
        await back(tester, c);
      }
      for (final id in const [2987]) {
        await open(tester, c, AppRoutes.companyRequest(id));
        await _capture(tester, key, 'pages/request_${id}_$tag');
        await back(tester, c);
      }
      await open(tester, c, '${AppRoutes.deliveryPoints}/new');
      await _capture(tester, key, 'pages/delivery_point_new_$tag');
      await tester.pumpWidget(const SizedBox());
      debugDisableShadows = true;
    }, skip: _outDir.isEmpty);
  }
}

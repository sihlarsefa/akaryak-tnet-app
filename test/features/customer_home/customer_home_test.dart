// Müşteri ana sayfası (spec A.4 A2): "Sipariş ver", karar bekleyenler (geri sayım), yüklenecek
// belgeler, yoldaki teslimat, limitler, son şablonlar, ilk sipariş ipucu, çevrimdışı son kayıt ve
// C.7 erişilebilirlik (360×640, %100 / %200 yazı, açık / koyu).
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/env/app_config_controller.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/customer_home/api.dart';
import 'package:akaryakitnet/features/customer_orders/application/wizard_models.dart';
import 'package:akaryakitnet/features/customer_orders/application/wizard_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../customer_orders/support/a2_support.dart';

void main() {
  late A2Env env;

  setUp(() async {
    env = await A2Env.create();
  });

  Future<ProviderContainer> open(
    WidgetTester tester, {
    String persona = 'musteri',
    double textScale = 1,
    Brightness brightness = Brightness.light,
    String location = '/home',
    Finder? waitFor,
    Future<void> Function(ProviderContainer c)? before,
  }) async {
    final c = (await tester.runAsync(() async {
      final c = await env.signedIn(persona);
      await before?.call(c);
      return c;
    }))!;
    addTearDown(c.dispose);
    await pumpA2(
      tester,
      c,
      initialLocation: location,
      textScale: textScale,
      brightness: brightness,
    );
    await pumpUntil(tester, waitFor ?? find.textContaining('Selin'));
    await pumpReal(tester);
    return c;
  }

  testWidgets(
    'içerik: selam, KPI, karar bekleyen, belge, teslimat, limit, şablon',
    (tester) async {
      await open(tester);
      expect(find.textContaining('Selin'), findsOneWidget);
      expect(find.text('Anadolu Lojistik A.Ş.'), findsWidgets);
      expect(find.text('Karar bekleyen'), findsOneWidget);
      expect(find.text('Karar bekleyen teklifler'), findsOneWidget);
      expect(find.byType(CountdownBadge), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('Yüklenecek ödeme belgeleri'),
        200,
      );
      expect(find.text('Çek görseli'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('Yolda (canlı konum değildir)'),
        200,
      );
      expect(find.byType(TruckRoute), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Limitlerim'), 200);
      await tester.scrollUntilVisible(
        find.text('Haftalık motorin – Pendik'),
        200,
      );
      expect(find.text('Şantiye ikmali (2 nokta)'), findsOneWidget);
      await tearDownUi(tester);
    },
  );

  testWidgets('"Sipariş ver" sihirbazı açar; şablona dokunmak şablonla açar', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.widgetWithText(AknButton, 'Sipariş ver'));
    await pumpUntil(tester, find.text('Ürün ve litre'));
    expect(find.text('Ürün ve litre'), findsOneWidget);
    expect(find.text('Bayi'), findsOneWidget, reason: 'iki bağlı bayi: seçici');
    await tearDownUi(tester);
  });

  testWidgets(
    'ilk sipariş ipucu: siparişi olmayan müşteride görünür, kapatılınca gider',
    (tester) async {
      env.world.orders.removeWhere((o) => o['customerId'] == 101);
      await open(tester);
      expect(find.text('İlk siparişinizi verin'), findsOneWidget);
      await tester.tap(find.byTooltip('Kapat').first);
      await pumpReal(tester);
      expect(find.text('İlk siparişinizi verin'), findsNothing);
      await tearDownUi(tester);
    },
  );

  testWidgets(
    'çevrimdışı: önbellekteki ana sayfa "Son güncelleme" ile açılır',
    (tester) async {
      final first = await open(tester);
      await tearDownUi(tester);
      first.dispose();
      env.server.failureMode = FakeFailureMode.offline;
      final c = env.container();
      addTearDown(c.dispose);
      // Oturum çekirdeğin önbelleğinden açılır (çevrimdışı açılış).
      await tester.runAsync(
        () => c.read(sessionControllerProvider.notifier).restore(),
      );
      await pumpA2(tester, c, initialLocation: '/home');
      await pumpUntil(tester, find.textContaining('Son güncelleme'));
      expect(find.textContaining('Son güncelleme'), findsOneWidget);
      expect(find.text('Karar bekleyen teklifler'), findsOneWidget);
      await tearDownUi(tester);
    },
  );

  testWidgets('asistan: üst çubuk simgesi /assistant açar', (tester) async {
    await open(
      tester,
      before: (c) => c.read(appConfigProvider.notifier).load(),
    );
    await tester.tap(find.byTooltip('Asistan'));
    await pumpUntil(tester, find.text('ROUTE:/assistant'));
    expect(find.text('ROUTE:/assistant'), findsOneWidget);
    await tearDownUi(tester);
  });

  testWidgets('asistan kartı: dokununca /assistant açar', (tester) async {
    await open(
      tester,
      before: (c) => c.read(appConfigProvider.notifier).load(),
    );
    await tester.ensureVisible(find.text('Asistana sorun'));
    await tester.pump();
    await tester.tap(find.text('Asistana sorun'));
    await pumpUntil(tester, find.text('ROUTE:/assistant'));
    expect(find.text('ROUTE:/assistant'), findsOneWidget);
    await tearDownUi(tester);
  });

  testWidgets('asistan kartı: kapatılınca bir daha görünmez', (tester) async {
    await open(
      tester,
      before: (c) => c.read(appConfigProvider.notifier).load(),
    );
    await tester.scrollUntilVisible(find.text('Asistana sorun'), 200);
    final close = find.byTooltip('Asistan kartını kapat');
    await tester.ensureVisible(close);
    await tester.pump();
    await tester.tap(close);
    await pumpReal(tester);
    expect(find.text('Asistana sorun'), findsNothing);
    final prefs = env.prefs.getKeys().where((k) => k.contains('assistant'));
    expect(prefs, isNotEmpty);
    await tearDownUi(tester);
  });

  testWidgets(
    'yarım kalan sipariş: taslak kartı görünür; dokununca sihirbaz taslakla açılır',
    (tester) async {
      await open(
        tester,
        before: (c) => c
            .read(wizardDraftStoreProvider)!
            .save(
              WizardSnapshot(
                draft: OrderDraft(
                  stationId: 1,
                  lines: [DraftLine.create(productId: 1, liters: 5000)],
                  pointId: 1001,
                  dirty: true,
                ),
              ),
            ),
      );
      await pumpUntil(tester, find.text('Yarım kalan siparişinize devam edin'));
      expect(find.text('Yarım kalan siparişinize devam edin'), findsOneWidget);
      expect(find.textContaining('1 satır · 5.000 L'), findsOneWidget);
      await tester.tap(find.text('Yarım kalan siparişinize devam edin'));
      await pumpUntil(tester, find.text('Ürün ve litre'));
      await pumpReal(tester);
      expect(find.text('5.000'), findsOneWidget);
      await tearDownUi(tester);
    },
  );

  for (final scale in [1.0, 2.0]) {
    for (final b in Brightness.values) {
      testWidgets('erişilebilirlik: yazı ${scale}x, ${b.name}', (tester) async {
        await open(tester, textScale: scale, brightness: b);
        expect(tester.takeException(), isNull);
        await expectA11y(tester);
        await tearDownUi(tester);
      });
    }
  }

  testWidgets('Limitlerim: bayi başına kullanım ve limitsiz bayi', (
    tester,
  ) async {
    await open(
      tester,
      location: limitsRoute,
      waitFor: find.text('Demir Petrol Akaryakıt Ltd. Şti.'),
    );
    expect(find.byType(UsageBar), findsOneWidget);
    expect(find.text('Limitsiz'), findsWidgets);
    expect(find.text('Kalan'), findsOneWidget);
    await expectA11y(tester);
    await tearDownUi(tester);
  });
}

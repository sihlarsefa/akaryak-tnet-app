// Siparişlerim (spec A.4): Karar bekleyen / Aktif / Geçmiş bölümleri, sunucu araması, boş arama →
// "Filtreleri temizle", satır → ayrıntı, çevrimdışı ilk sayfa ("Son güncelleme"), şablonlar
// kısayolu ve C.7 erişilebilirlik (360×640, %100 / %200, açık / koyu).
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/customer_orders/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/a2_support.dart';

void main() {
  late A2Env env;

  setUp(() async {
    env = await A2Env.create();
  });

  String numberOf(bool Function(Map<String, dynamic> o) test) =>
      env.world.orders.firstWhere(test)['orderNumber'] as String;

  Future<ProviderContainer> open(
    WidgetTester tester, {
    String location = '/orders?segment=decision',
    double textScale = 1,
    Brightness brightness = Brightness.light,
    required Finder waitFor,
  }) async {
    final c = (await tester.runAsync(() => env.signedIn('musteri')))!;
    addTearDown(c.dispose);
    await pumpA2(
      tester,
      c,
      initialLocation: location,
      textScale: textScale,
      brightness: brightness,
    );
    await pumpUntil(tester, waitFor);
    await pumpReal(tester);
    return c;
  }

  Future<void> typeSearch(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    await tester.pump(const Duration(milliseconds: 350)); // arama gecikmesi
    await pumpReal(tester);
  }

  testWidgets(
    'bölümler: karar bekleyen → aktif → geçmiş, her biri kendi siparişleri',
    (tester) async {
      final decision = numberOf((o) => o['status'] == 2);
      final active = numberOf(
        (o) => o['status'] == 3 && o['customerId'] == 101,
      );
      final history = numberOf(
        (o) => const {4, 6, 7}.contains(o['status']) && o['customerId'] == 101,
      );
      await open(tester, waitFor: find.text(decision));
      expect(find.text(decision), findsOneWidget);
      expect(find.text(active), findsNothing);
      expect(find.byType(CountdownBadge), findsWidgets);

      await tester.tap(find.text('Aktif'));
      await pumpUntil(tester, find.text(active));
      expect(find.text(active), findsOneWidget);
      expect(find.text(decision), findsNothing);

      await tester.tap(find.text('Geçmiş'));
      await pumpUntil(tester, find.text(history));
      expect(find.text(history), findsOneWidget);
      expect(find.text(active), findsNothing);
      await tearDownUi(tester);
    },
  );

  testWidgets(
    'arama sunucuda süzer; eşleşme yoksa "Filtreleri temizle" listeyi geri getirir',
    (tester) async {
      final pendik = numberOf(
        (o) =>
            o['status'] == 3 &&
            o['customerId'] == 101 &&
            o['deliveryPointId'] == 1001,
      );
      final tuzla = numberOf(
        (o) =>
            o['status'] == 3 &&
            o['customerId'] == 101 &&
            o['deliveryPointId'] == 1002,
      );
      await open(
        tester,
        location: '/orders?segment=active',
        waitFor: find.text(pendik),
      );

      await typeSearch(tester, 'tuzla');
      await pumpUntil(tester, find.text(tuzla));
      expect(find.text(tuzla), findsOneWidget);
      expect(find.text(pendik), findsNothing);

      await typeSearch(tester, 'zzzz-yok');
      await pumpUntil(tester, find.text(OrdersCopy.emptyFiltered));
      expect(find.text(OrdersCopy.emptyFiltered), findsOneWidget);
      await tester.tap(find.text(OrdersCopy.clearFilters));
      await pumpUntil(tester, find.text(pendik));
      expect(find.text(pendik), findsOneWidget);
      expect(find.text(tuzla), findsOneWidget);
      await tearDownUi(tester);
    },
  );

  testWidgets('satıra dokununca sipariş ayrıntısı açılır', (tester) async {
    final decision = numberOf((o) => o['status'] == 2);
    await open(tester, waitFor: find.text(decision));
    await tester.tap(find.text(decision));
    await pumpUntil(tester, find.text('Teklif hazır'));
    expect(find.text('Teklif hazır'), findsOneWidget);
    await tearDownUi(tester);
  });

  testWidgets('şablonlar kısayolu Şablonlarım sayfasını açar', (tester) async {
    final decision = numberOf((o) => o['status'] == 2);
    await open(tester, waitFor: find.text(decision));
    await tester.tap(find.bySemanticsLabel(OrdersCopy.templates));
    await pumpUntil(tester, find.text('Haftalık motorin – Pendik'));
    expect(find.text('Haftalık motorin – Pendik'), findsOneWidget);
    await tearDownUi(tester);
  });

  testWidgets(
    'çevrimdışı: önbellekteki ilk sayfa "Son güncelleme" ile gösterilir',
    (tester) async {
      final decision = numberOf((o) => o['status'] == 2);
      final first = await open(tester, waitFor: find.text(decision));
      await tearDownUi(tester);
      first.dispose();

      env.server.failureMode = FakeFailureMode.offline;
      final c = env.container();
      addTearDown(c.dispose);
      await tester.runAsync(
        () => c.read(sessionControllerProvider.notifier).restore(),
      );
      await pumpA2(tester, c, initialLocation: '/orders?segment=decision');
      await pumpUntil(tester, find.textContaining(OrdersCopy.lastUpdate));
      expect(find.textContaining(OrdersCopy.lastUpdate), findsOneWidget);
      expect(find.text(decision), findsOneWidget);
      await tearDownUi(tester);
    },
  );

  testWidgets('çevrimdışı ve önbellek yok: açıklayıcı boş durum', (
    tester,
  ) async {
    final c = (await tester.runAsync(() => env.signedIn('musteri')))!;
    addTearDown(c.dispose);
    env.server.failureMode = FakeFailureMode.offline;
    await pumpA2(tester, c, initialLocation: '/orders?segment=history');
    await pumpUntil(tester, find.text(OrdersCopy.offlineNoData));
    expect(find.text(OrdersCopy.offlineNoData), findsOneWidget);
    expect(find.text(OrdersCopy.retry), findsOneWidget);
    await tearDownUi(tester);
  });

  for (final scale in [1.0, 2.0]) {
    for (final b in Brightness.values) {
      testWidgets('erişilebilirlik: Siparişlerim ${scale}x ${b.name}', (
        tester,
      ) async {
        final decision = numberOf((o) => o['status'] == 2);
        await open(
          tester,
          waitFor: find.text(decision),
          textScale: scale,
          brightness: b,
        );
        expect(tester.takeException(), isNull);
        await expectA11y(tester);
        await tester.tap(find.text('Aktif'));
        await pumpReal(tester);
        expect(tester.takeException(), isNull);
        await expectA11y(tester);
        await tearDownUi(tester);
      });
    }
  }
}

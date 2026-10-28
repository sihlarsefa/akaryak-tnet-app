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

  /// Siparişin satırı (müşteri satırı numarayı göstermez; satır anahtarı sipariş kimliğidir).
  Finder rowOf(bool Function(Map<String, dynamic> o) test) => find.byKey(
    ValueKey('order-row-${env.world.orders.firstWhere(test)['id']}'),
  );

  /// Kart başlığı. Başlık satıra sığmayınca sayı ile birim arasındaki boşluk bölünmez boşluk
  /// (U+00A0) olur ("Motorin," / "8.000 L" kırılır, `keepUnits`); görünüm aynı olduğundan iki
  /// boşluk da eşleşir.
  Finder titleText(String text) => find.byWidgetPredicate(
    (w) => w is Text && w.data?.replaceAll('\u00A0', ' ') == text,
    description: 'başlık "$text" (U+00A0 boşluk sayılır)',
  );

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

  /// Sekmeye dokunur (dar ekranda / büyük yazıda sekme satırı kayar).
  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pump();
    await tester.tap(find.text(label));
  }

  Future<void> typeSearch(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    await tester.pump(const Duration(milliseconds: 350)); // arama gecikmesi
    await pumpReal(tester);
  }

  testWidgets(
    'bölümler: karar bekleyen → aktif → geçmiş, her biri kendi siparişleri',
    (tester) async {
      final decision = rowOf((o) => o['status'] == 2);
      final active = rowOf((o) => o['status'] == 3 && o['customerId'] == 101);
      final history = rowOf(
        (o) => const {4, 6, 7}.contains(o['status']) && o['customerId'] == 101,
      );
      await open(tester, waitFor: decision);
      expect(decision, findsOneWidget);
      expect(active, findsNothing);
      expect(find.byType(CountdownBadge), findsWidgets);

      await tapTab(tester, 'Aktif');
      await pumpUntil(tester, active);
      expect(active, findsOneWidget);
      expect(decision, findsNothing);

      await tapTab(tester, 'Geçmiş');
      await pumpUntil(tester, history);
      expect(history, findsOneWidget);
      expect(active, findsNothing);
      await tearDownUi(tester);
    },
  );

  testWidgets(
    'sipariş kartı (v3): ürün + litre başlık, izleyiciye göre lamba, geri sayım; sekme sayısı ve dip cümlesi',
    (tester) async {
      final decision = rowOf((o) => o['status'] == 2);
      await open(tester, waitFor: decision);
      final row = find.descendant(of: decision, matching: find.byType(Text));
      expect(
        find.descendant(of: decision, matching: titleText('Motorin, 8.000 L')),
        findsOneWidget,
      );
      expect(row, findsWidgets);
      expect(
        find.descendant(
          of: decision,
          matching: find.text('Kararınızı bekliyor'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: decision, matching: find.byType(CountdownBadge)),
        findsOneWidget,
      );
      expect(
        tester
            .widget<CountdownBadge>(
              find.descendant(
                of: decision,
                matching: find.byType(CountdownBadge),
              ),
            )
            .yourMove,
        isTrue,
        reason: 'sıra müşteride: Pas geri sayım',
      );
      expect(
        find.bySemanticsLabel(RegExp(r'^Karar bekleyen, \d+ sipariş$')),
        findsOneWidget,
      );
      expect(find.text(OrdersCopy.decisionFooter), findsOneWidget);

      await tapTab(tester, 'Aktif');
      final transit = rowOf(
        (o) =>
            o['status'] == 3 &&
            o['customerId'] == 101 &&
            env.world.shipments.any(
              (x) => x['orderId'] == o['id'] && x['status'] == 1,
            ),
      );
      await pumpUntil(tester, transit);
      expect(
        find.descendant(of: transit, matching: find.byType(TruckRoute)),
        findsOneWidget,
        reason: 'yoldaki siparişte rota çizgisi',
      );
      // v3 kartları daha yüksek: dip cümlesi listenin sonunda, ilk ekranın altında kalır.
      final list = find
          .ancestor(of: transit, matching: find.byType(Scrollable))
          .evaluate()
          .first;
      await tester.scrollUntilVisible(
        find.text(OrdersCopy.activeFooter),
        200,
        scrollable: find.byElementPredicate((e) => identical(e, list)),
      );
      expect(find.text(OrdersCopy.activeFooter), findsOneWidget);
      await tearDownUi(tester);
    },
  );

  testWidgets('geçmiş güne göre gruplanır', (tester) async {
    final history = rowOf(
      (o) => const {4, 6, 7}.contains(o['status']) && o['customerId'] == 101,
    );
    await open(tester, location: '/orders?segment=history', waitFor: history);
    final headers = find.byWidgetPredicate(
      (w) =>
          w is Semantics &&
          (w.properties.header ?? false) &&
          w.child is Text &&
          RegExp(
            r'^(Bugün|Dün|Yarın|\d+ \S+)$',
          ).hasMatch((w.child! as Text).data ?? ''),
    );
    expect(headers, findsWidgets);
    await tearDownUi(tester);
  });

  testWidgets(
    'arama sunucuda süzer; eşleşme yoksa "Filtreleri temizle" listeyi geri getirir',
    (tester) async {
      final pendik = rowOf(
        (o) =>
            o['status'] == 3 &&
            o['customerId'] == 101 &&
            o['deliveryPointId'] == 1001,
      );
      final tuzla = rowOf(
        (o) =>
            o['status'] == 3 &&
            o['customerId'] == 101 &&
            o['deliveryPointId'] == 1002,
      );
      await open(tester, location: '/orders?segment=active', waitFor: pendik);

      await typeSearch(tester, 'tuzla');
      await pumpUntil(tester, tuzla);
      expect(tuzla, findsOneWidget);
      expect(pendik, findsNothing);

      await typeSearch(tester, 'zzzz-yok');
      await pumpUntil(tester, find.text(OrdersCopy.emptyFiltered));
      expect(find.text(OrdersCopy.emptyFiltered), findsOneWidget);
      await tester.tap(find.text(OrdersCopy.clearFilters));
      await pumpUntil(tester, pendik);
      expect(pendik, findsOneWidget);
      expect(tuzla, findsOneWidget);
      await tearDownUi(tester);
    },
  );

  testWidgets('satıra dokununca sipariş ayrıntısı açılır', (tester) async {
    final decision = rowOf((o) => o['status'] == 2);
    await open(tester, waitFor: decision);
    await tester.tap(decision);
    await pumpUntil(tester, find.byType(AknPlate));
    expect(find.text('Demir Petrol teklifi'), findsOneWidget);
    expect(find.text(OrdersCopy.approve), findsOneWidget);
    await tearDownUi(tester);
  });

  testWidgets('şablonlar kısayolu Şablonlarım sayfasını açar', (tester) async {
    final decision = rowOf((o) => o['status'] == 2);
    await open(tester, waitFor: decision);
    await tester.tap(find.bySemanticsLabel(OrdersCopy.templates));
    await pumpUntil(tester, find.text('Haftalık motorin – Pendik'));
    expect(find.text('Haftalık motorin – Pendik'), findsOneWidget);
    await tearDownUi(tester);
  });

  testWidgets(
    'çevrimdışı: önbellekteki ilk sayfa "Son güncelleme" ile gösterilir',
    (tester) async {
      final decision = rowOf((o) => o['status'] == 2);
      final first = await open(tester, waitFor: decision);
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
      expect(decision, findsOneWidget);
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
        final decision = rowOf((o) => o['status'] == 2);
        await open(tester, waitFor: decision, textScale: scale, brightness: b);
        expect(tester.takeException(), isNull);
        await expectA11y(tester);
        await tapTab(tester, 'Aktif');
        await pumpReal(tester);
        expect(tester.takeException(), isNull);
        await expectA11y(tester);
        await tearDownUi(tester);
      });
    }
  }
}

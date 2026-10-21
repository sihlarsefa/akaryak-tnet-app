// Büyük liste senaryosu (spec D.7.8 performans bütçesinin ana makine kopyası): 120 teklif bekleyen
// siparişle teklif masası ve sipariş listesi kaydırıldıkça sonraki sayfaları yükler, hata vermez.
// Kare süreleri cihazda ölçülür (`integration_test/perf_test.dart`, profil kipi).
import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/bayi/application/desk_controller.dart';
import 'package:akaryakitnet/features/bayi/application/orders_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/smoke_flows.dart';

/// Dio 50 KB üstü JSON'u arka plan isolate'unda çözer (`BackgroundTransformer`); sahte zamanda bu
/// gerçek zaman ister. Koşul sağlanana kadar kısa gerçek beklemelerle kare çizer.
Future<void> _until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 60 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('120 siparişle masa ve liste sayfa sayfa kayar', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final world = FakeWorld.seeded()..addBulkPendingOrders(120);
    final c = await launchFakeApp(tester, world: world);
    await signInAs(tester, c, 'siparis');
    final layout = c.read(navLayoutProvider);
    final bar = find.byType(AnimatedBottomBar);

    Future<void> openTab(DestinationId id) async {
      final i = layout.bar.indexWhere((d) => d.id == id);
      expect(i, greaterThanOrEqualTo(0), reason: '$id alt menüde');
      await tester.tap(
        find.descendant(of: bar, matching: find.text(layout.bar[i].barLabel)),
      );
      await pumpFor(tester, const Duration(seconds: 2));
    }

    /// Listenin sonuna gider, sonraki sayfa gelene kadar bekler; [rows] satıra ulaşınca durur.
    Future<void> scrollThrough(
      int rows,
      ({int items, bool more, bool hasMore}) Function() read,
    ) async {
      for (var k = 0; k < 12; k++) {
        final s = read();
        if (s.items >= rows || !s.hasMore) break;
        final pos = tester.state<ScrollableState>(mainVerticalList(tester));
        pos.position.jumpTo(pos.position.maxScrollExtent);
        await pumpFor(tester, const Duration(milliseconds: 300));
        await _until(tester, () => !read().more);
        await pumpFor(tester, const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
      }
      // Gerçek parmak hareketiyle başa dön.
      for (var k = 0; k < 6; k++) {
        await tester.fling(
          mainVerticalList(tester),
          const Offset(0, 900),
          3000,
        );
        await pumpFor(tester, const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
      }
    }

    await openTab(DestinationId.quoteDesk);
    await _until(tester, () => !c.read(quoteDeskProvider).list.loading);
    expect(
      c.read(quoteDeskProvider).list.totalCount,
      greaterThanOrEqualTo(120),
    );
    await scrollThrough(100, () {
      final l = c.read(quoteDeskProvider).list;
      return (items: l.items.length, more: l.loadingMore, hasMore: l.hasMore);
    });
    final desk = c.read(quoteDeskProvider).list;
    expect(desk.page, greaterThan(1), reason: 'sonraki sayfalar yüklendi');
    expect(desk.items.length, greaterThanOrEqualTo(100));
    expect(desk.moreError, isNull);

    await openTab(DestinationId.bayiOrders);
    await _until(tester, () => !c.read(bayiOrdersProvider).list.loading);
    await scrollThrough(100, () {
      final l = c.read(bayiOrdersProvider).list;
      return (items: l.items.length, more: l.loadingMore, hasMore: l.hasMore);
    });
    final orders = c.read(bayiOrdersProvider).list;
    expect(orders.totalCount, greaterThanOrEqualTo(120));
    expect(orders.page, greaterThan(1));
    expect(orders.items.length, greaterThanOrEqualTo(100));
    expect(orders.moreError, isNull);

    await tester.pumpWidget(const SizedBox());
  });
}

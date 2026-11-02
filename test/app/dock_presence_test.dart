// Docks never depend on slow or failed side data (diagnosis 2026-11-02 #3, #5):
//
// * the finance unit sees "Finans kararını ver" on an order waiting for its decision even when the
//   Onaylar › Bende list (approvals?scope=0&type=4) answers 429 from the start — optimistic while the
//   list loads, the order's own request once it failed (the approval page checks the right again);
// * a viewer with no step on an order waiting for finance gets a dock note instead of nothing;
// * an order detail shown from the cache offers no step until the server confirmed it ("Güncelleniyor").
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/routing/app_routes.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/bayi/copy.dart';
import 'package:akaryakitnet/features/bayi/fake/order_support.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/live_device.dart';

/// An open order of the demo station, routed to finance by its owner (as the server does for every
/// new order since 2e379cb).
JsonMap _orderAwaitingFinance(LiveDevice device) {
  final w = device.server.world;
  final o = w.orders.firstWhere(
    (o) =>
        o['stationId'] == 1 &&
        (o['status'] == 1 || o['status'] == 0) &&
        (o['financeStatus'] as num? ?? 0) == 0,
  );
  routeToFinance(w, o, 125000, w.persona('sahip')!);
  return o;
}

Future<void> _open(WidgetTester tester, ProviderContainer c, String route) async {
  c.read(routerProvider).push<Object?>(route).ignore();
  await pumpFor(tester, const Duration(milliseconds: 600));
}

final _bendeList = NetRule(
  match: (m, p, q) => m == 'GET' && p == 'approvals',
  status: 429,
  retryAfterSeconds: 1,
);

void main() {
  setUpAll(() {
    AknMotion.ambient = false;
    AknHaptics.enabled = false;
  });

  testWidgets(
    'finans: Bende 429 since launch → "Finans kararını ver" is still docked',
    (tester) async {
      final device = await LiveDevice.create();
      final c1 = await launchApp(tester, device);
      await signIn(tester, c1, 'finans');
      await killApp(tester);
      final o = _orderAwaitingFinance(device);

      final c2 = await launchApp(tester, device, rules: [_bendeList]);
      await _open(tester, c2, AppRoutes.bayiOrder(o['id']! as int));
      final decide = find.byKey(const ValueKey('order-finance-decide'));
      expect(decide, findsOneWidget, reason: 'while the Bende list is still retrying');
      // Retries used up (Retry-After 1 s, twice): the list failed for good, the dock stays.
      await pumpFor(tester, const Duration(seconds: 6));
      expect(device.net.count('approvals'), greaterThanOrEqualTo(2));
      expect(decide, findsOneWidget, reason: 'after the Bende list failed');
      await killApp(tester);
    },
  );

  testWidgets(
    'ikmal: order waiting for finance, no step of his → a dock note, not an empty bottom',
    (tester) async {
      final device = await LiveDevice.create();
      final c1 = await launchApp(tester, device);
      await signIn(tester, c1, 'ikmal');
      final o = _orderAwaitingFinance(device);
      await _open(tester, c1, AppRoutes.bayiOrder(o['id']! as int));
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.byType(ActionBar), findsOneWidget);
      expect(find.text(BayiCopy.financePendingNote), findsOneWidget);
      await killApp(tester);
    },
  );

  testWidgets(
    'order detail from the cache: "Güncelleniyor" dock until the server confirms, then the steps',
    (tester) async {
      final device = await LiveDevice.create();
      final c1 = await launchApp(tester, device);
      await signIn(tester, c1, 'sahip');
      final w = device.server.world;
      final o = w.orders.firstWhere(
        (o) =>
            o['stationId'] == 1 &&
            o['status'] == 1 &&
            (o['financeStatus'] as num? ?? 0) == 0,
      );
      final id = o['id']! as int;
      await _open(tester, c1, AppRoutes.bayiOrder(id));
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.text('Teklif ver'), findsWidgets, reason: 'fresh: the step is there');
      await killApp(tester);

      // Reopen: the detail comes from the cache at once; the server is slow (3 s).
      final c2 = await launchApp(
        tester,
        device,
        rules: [getRule('orders/$id', delay: const Duration(seconds: 3))],
      );
      await _open(tester, c2, AppRoutes.bayiOrder(id));
      expect(find.byKey(const ValueKey('order-dock-refreshing')), findsOneWidget);
      expect(find.text(BayiCopy.dockRefreshing), findsOneWidget);
      expect(
        find.descendant(of: find.byType(ActionBar), matching: find.text('Teklif ver')),
        findsNothing,
        reason: 'no step on cached data',
      );
      await pumpFor(tester, const Duration(seconds: 4));
      expect(find.byKey(const ValueKey('order-dock-refreshing')), findsNothing);
      expect(
        find.descendant(of: find.byType(ActionBar), matching: find.text('Teklif ver')),
        findsOneWidget,
      );
      await killApp(tester);
    },
  );
}

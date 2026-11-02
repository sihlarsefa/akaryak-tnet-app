// "Veriler çok yavaş" (2026-11-02): main screens open from the last data at once and refresh in the
// background ("güncelleniyor"), identical reads in flight are one request, a write evicts what it
// changed, and cached data never leaks to another user or between the demo world and the live API.
// Live stack (TestFlight env) with the in-app world behind the live adapter; stores survive a reopen.
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/env/app_env.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/network/response_cache.dart';
import 'package:akaryakitnet/core/routing/app_routes.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/bayi/application/orders_controller.dart';
import 'package:akaryakitnet/features/bayi/data/bayi_repository.dart';
import 'package:akaryakitnet/features/bayi/data/order_models.dart';
import 'package:akaryakitnet/features/customer_more/application/delivery_points_controller.dart';
import 'package:akaryakitnet/features/payments/application/payments_providers.dart';
import 'package:akaryakitnet/features/payments/data/payments_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/live_device.dart';

Finder _refreshBar() => find.byWidgetPredicate((w) => w is TopProgressBar && w.active);

Future<void> _go(WidgetTester tester, ProviderContainer c, String route, {Duration settle = const Duration(milliseconds: 300)}) async {
  c.read(routerProvider).go(route);
  await pumpFor(tester, settle);
}

Iterable<String> _http(LiveDevice d) => d.cache.keys.where((k) => k.contains(':http.'));

void main() {
  setUpAll(() {
    AknMotion.ambient = false;
    AknHaptics.enabled = false;
  });

  group('cache-first (stale-while-revalidate)', () {
    testWidgets('sahip: Siparişler on the next launch shows the last list at once, then the fresh one', (tester) async {
      final device = await LiveDevice.create();
      final c1 = await launchApp(tester, device);
      await signIn(tester, c1, 'sahip');
      await _go(tester, c1, AppRoutes.bayiOrders, settle: const Duration(seconds: 1));
      expect(c1.read(bayiOrdersProvider).list.items, isNotEmpty);
      await killApp(tester);

      final c2 = await launchApp(
        tester,
        device,
        rules: [getRule('bayi/orders', delay: const Duration(seconds: 4))],
        settle: const Duration(milliseconds: 1600),
      );
      await _go(tester, c2, AppRoutes.bayiOrders);
      final cached = c2.read(bayiOrdersProvider).list;
      expect(cached.items, isNotEmpty, reason: 'no skeleton: the cached first page');
      expect(cached.refreshing, isTrue, reason: '"güncelleniyor" while the server answers');
      expect(_refreshBar(), findsWidgets);
      await pumpFor(tester, const Duration(seconds: 5));
      final fresh = c2.read(bayiOrdersProvider).list;
      expect(fresh.refreshing, isFalse);
      expect(DateTime.now().toUtc().difference(fresh.updatedAt!), lessThan(const Duration(seconds: 30)));
      await killApp(tester);
    });

    testWidgets('finans: Tahsilat on the next launch shows the last page at once', (tester) async {
      final device = await LiveDevice.create();
      final c1 = await launchApp(tester, device);
      await signIn(tester, c1, 'finans');
      await _go(tester, c1, AppRoutes.payments, settle: const Duration(seconds: 1));
      expect(c1.read(paymentsListProvider(const PaymentsQuery())).hasData, isTrue);
      await killApp(tester);

      final c2 = await launchApp(
        tester,
        device,
        rules: [getRule('payments', delay: const Duration(seconds: 4))],
        settle: const Duration(milliseconds: 1600),
      );
      await _go(tester, c2, AppRoutes.payments);
      final s = c2.read(paymentsListProvider(const PaymentsQuery()));
      expect(s.hasData, isTrue, reason: 'cached page instead of a skeleton');
      expect(s.refreshing, isTrue);
      await pumpFor(tester, const Duration(seconds: 5));
      expect(c2.read(paymentsListProvider(const PaymentsQuery())).refreshing, isFalse);
      await killApp(tester);
    });

    testWidgets('musteri: Teslimat noktaları on the next launch shows the last list at once', (tester) async {
      final device = await LiveDevice.create();
      final c1 = await launchApp(tester, device);
      await signIn(tester, c1, 'musteri');
      c1.read(routerProvider).push<Object?>(AppRoutes.deliveryPoints).ignore();
      await pumpFor(tester, const Duration(seconds: 1));
      expect(c1.read(deliveryPointsControllerProvider).points, isNotEmpty);
      await killApp(tester);

      final c2 = await launchApp(
        tester,
        device,
        rules: [getRule('customers/me/delivery-points', delay: const Duration(seconds: 4))],
        settle: const Duration(milliseconds: 1600),
      );
      c2.read(routerProvider).push<Object?>(AppRoutes.deliveryPoints).ignore();
      await pumpFor(tester, const Duration(milliseconds: 300));
      final s = c2.read(deliveryPointsControllerProvider);
      expect(s.points, isNotEmpty, reason: 'cache-first, not network-first');
      expect(s.refreshing, isTrue);
      await pumpFor(tester, const Duration(seconds: 5));
      expect(c2.read(deliveryPointsControllerProvider).refreshing, isFalse);
      await killApp(tester);
    });

    testWidgets('session-ready prefetch: home and month stats are asked for during the splash', (tester) async {
      final device = await LiveDevice.create();
      final c1 = await launchApp(tester, device);
      await signIn(tester, c1, 'musteri');
      await killApp(tester);
      final c2 = await launchApp(tester, device, settle: const Duration(milliseconds: 500));
      expect(c2.read(splashDoneProvider), isFalse, reason: 'still on the splash');
      expect(device.net.count('home/customer'), 1);
      expect(device.net.count('stats/customer'), 1);
      await pumpFor(tester, const Duration(seconds: 2));
      expect(device.net.count('home/customer'), 1, reason: 'the home page reuses the warmed provider');
      await killApp(tester);
    });

    testWidgets('identical reads in flight are one request (bayi/orders/counts on the owner home)', (tester) async {
      final device = await LiveDevice.create();
      final c1 = await launchApp(tester, device);
      await signIn(tester, c1, 'sahip');
      await killApp(tester);
      await launchApp(tester, device, settle: const Duration(seconds: 4));
      // Before: 3–5 per home load (two providers, again on every home update).
      expect(device.net.count('bayi/orders/counts'), lessThanOrEqualTo(3));
      expect(device.net.count('home/bayi'), 1);
      await killApp(tester);
    });
  });

  testWidgets('a write evicts the cached reads it changed (quote → lists, order, home)', (tester) async {
    final device = await LiveDevice.create();
    final c = await launchApp(tester, device);
    await signIn(tester, c, 'sahip');
    await _go(tester, c, AppRoutes.bayiOrders, settle: const Duration(seconds: 1));
    final row = c.read(bayiOrdersProvider).list.items.firstWhere(
      (r) => r.status.code == 1,
    );
    await tester.runAsync(() => c.read(bayiRepositoryProvider).order(row.id));
    expect(_http(device).where((k) => k.contains('|bayi/orders?')), isNotEmpty);
    expect(_http(device).where((k) => k.endsWith('|orders/${row.id}')), isNotEmpty);
    await tester.runAsync(
      () => c.read(bayiRepositoryProvider).quoteOrder(
        row.id,
        unitPrice: 41.5,
        deliveryDate: DateTime.now().add(const Duration(days: 2)),
      ),
    );
    expect(_http(device).where((k) => k.contains('|bayi/orders?')), isEmpty);
    expect(_http(device).where((k) => k.endsWith('|orders/${row.id}')), isEmpty);
    expect(_http(device).where((k) => k.contains('|home/')), isEmpty);
    await killApp(tester);
  });

  group('privacy', () {
    testWidgets('sign-out wipes every cached response; the next user reads none of them', (tester) async {
      final device = await LiveDevice.create();
      final c = await launchApp(tester, device);
      await signIn(tester, c, 'sahip');
      await _go(tester, c, AppRoutes.bayiOrders, settle: const Duration(seconds: 1));
      final owner = c.read(currentUserIdProvider)!;
      expect(_http(device).where((k) => k.startsWith('$owner:')), isNotEmpty);

      await tester.runAsync(() => c.read(sessionControllerProvider.notifier).signOut());
      await pumpFor(tester, const Duration(seconds: 1));
      expect(_http(device), isEmpty, reason: 'nothing of the previous user is left');
      expect(device.cache.keys.where((k) => k.startsWith('$owner:')), isEmpty);

      await signIn(tester, c, 'finans');
      final other = c.read(currentUserIdProvider)!;
      expect(other, isNot(owner));
      final peek = await tester.runAsync(
        () => c.read(apiClientProvider).peek(
          'bayi/orders',
          query: const BayiOrdersFilter().toQuery(page: 1, pageSize: BayiRepository.listPageSize),
          parse: (j) => j,
        ),
      );
      expect(peek, isNull);
      expect(_http(device).where((k) => !k.startsWith('$other:')), isEmpty);
      await killApp(tester);
    });

    testWidgets('demo world and live API never share cache entries', (tester) async {
      final device = await LiveDevice.create();
      final c = await launchApp(tester, device);
      // Demo card: the session runs on the in-app world.
      expect(c.read(demoSessionProvider.notifier).start(), isTrue);
      await pumpFor(tester, const Duration(milliseconds: 300));
      await signIn(tester, c, 'sahip');
      await _go(tester, c, AppRoutes.bayiOrders, settle: const Duration(seconds: 1));
      expect(_http(device).where((k) => k.contains(':http.demo.')), isNotEmpty);
      expect(_http(device).where((k) => k.contains(':http.live.')), isEmpty);

      await tester.runAsync(() => c.read(sessionControllerProvider.notifier).signOut());
      await pumpFor(tester, const Duration(seconds: 1));
      expect(c.read(appEnvProvider).isFake, isFalse, reason: 'back on the live API');
      expect(_http(device), isEmpty, reason: 'the demo session left nothing behind');

      await signIn(tester, c, 'sahip');
      await _go(tester, c, AppRoutes.bayiOrders, settle: const Duration(seconds: 1));
      expect(_http(device).where((k) => k.contains(':http.live.')), isNotEmpty);
      expect(_http(device).where((k) => k.contains(':http.demo.')), isEmpty);

      // Even an entry of the demo world under the same user id is invisible to the live session.
      final uid = c.read(currentUserIdProvider)!;
      final demoCache = ResponseCache(store: device.cache, mode: 'demo', userId: () => uid);
      await tester.runAsync(
        () => device.cache.write(demoCache.keyFor(uid, 'home/bayi', null), {'world': 'demo'}, userId: uid),
      );
      final live = await tester.runAsync(
        () => c.read(apiClientProvider).peek('home/bayi', parse: (j) => j),
      );
      expect(live?.value, isNot(equals({'world': 'demo'})));
      await killApp(tester);
    });
  });
}

import 'package:akaryakitnet/core/routing/nav_keys.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/driver/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/driver_harness.dart';

void main() {
  Future<(DriverHarness, ProviderContainer)> boot(
    WidgetTester tester,
    String user,
  ) async {
    phoneSize(tester, const Size(400, 900));
    final h = await real(tester, DriverHarness.create);
    final c = h.container();
    await tester.runAsync(() => DriverHarness.login(c, user));
    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: AssignedDeliveriesCard(),
            ),
          ),
        ),
        ...driverRoutes(),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp.router(
          routerConfig: router,
          theme: AknTheme.light(),
        ),
      ),
    );
    await pumpUntil(tester, () => false, maxRounds: 20);
    return (h, c);
  }

  testWidgets('sahibine atanmış teslimat: kart görünür, Teslimatlarım açılır', (
    tester,
  ) async {
    final (h, c) = await boot(tester, 'sahip');
    expect(find.text('Size atanmış 1 teslimat'), findsOneWidget);
    await tester.tap(find.text('Size atanmış 1 teslimat'));
    await pumpUntil(
      tester,
      () => find.byType(DriverHome).evaluate().isNotEmpty,
    );
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.byType(DriverHome), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await pumpFor(tester, const Duration(milliseconds: 300));
    c.dispose();
    h.dispose();
  });

  testWidgets('yalnızca şoför ve atanmış teslimatı olmayan: kart çizilmez', (
    tester,
  ) async {
    for (final user in ['sofor', 'siparis']) {
      final (h, c) = await boot(tester, user);
      expect(find.byType(AknCard), findsNothing, reason: user);
      await tester.pumpWidget(const SizedBox());
      await pumpFor(tester, const Duration(milliseconds: 300));
      c.dispose();
      h.dispose();
    }
  });
}

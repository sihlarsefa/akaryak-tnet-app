// Regression: "alttaki tuşlar gelmiyor" (TestFlight 1.0.0 (4)–(10), real accounts on the live API).
//
// Reopening the app with a saved session (cold start: SessionUnknown → SessionAuthenticated or
// SessionLocked straight away) used to build the router without the tab shell: navLayoutProvider read
// the derived accessPolicyProvider inside the router's session listener, before Riverpod had marked it
// dirty, so the layout came out empty and stayed cached. No tab bar, no "Diğer", no centre key for the
// whole session, for every persona. A fresh sign-in worked by accident, which is why demo cards and the
// old tests never showed it.
import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/core/auth/permissions.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/routing/app_routes.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/live_device.dart';

void main() {
  setUpAll(() {
    AknMotion.ambient = false;
    AknHaptics.enabled = false;
  });

  for (final user in livePersonas) {
    testWidgets('$user: sign in, reopen the app → the tab bar is there', (
      tester,
    ) async {
      final device = await LiveDevice.create();
      final c1 = await launchApp(tester, device);
      await signIn(tester, c1, user);
      expect(
        find.byType(AnimatedBottomBar),
        findsOneWidget,
        reason: 'after sign-in: ${describeShell(c1)}',
      );
      final barAfterLogin = c1.read(navLayoutProvider).signature;
      await killApp(tester);

      final c2 = await launchApp(tester, device);
      await pumpFor(tester, const Duration(seconds: 2));
      final state = describeShell(c2);
      expect(c2.read(sessionControllerProvider), isA<SessionAuthenticated>());
      expect(
        find.byType(AnimatedBottomBar),
        findsOneWidget,
        reason: 'after reopen: $state',
      );
      expect(inShell(c2), isTrue, reason: state);
      expect(c2.read(navLayoutProvider).bar.length, greaterThanOrEqualTo(3));
      // The same bar as after the sign-in (v4 §3.1: the bar is fixed per access).
      expect(c2.read(navLayoutProvider).signature, barAfterLogin);
      if (user == 'sofor') {
        expect(currentLocation(c2), AppRoutes.driver, reason: state);
      }
      await killApp(tester);
    });
  }

  testWidgets('sahip with Face ID lock: reopen, unlock → the tab bar is there', (
    tester,
  ) async {
    final device = await LiveDevice.create(biometricLock: true);
    final c1 = await launchApp(tester, device);
    await signIn(tester, c1, 'sahip');
    await killApp(tester);

    final c2 = await launchApp(tester, device);
    expect(c2.read(sessionControllerProvider), isA<SessionLocked>());
    c2.read(sessionControllerProvider.notifier).unlock();
    await pumpFor(tester, const Duration(seconds: 2));
    expect(
      find.byType(AnimatedBottomBar),
      findsOneWidget,
      reason: 'after unlock: ${describeShell(c2)}',
    );
    expect(inShell(c2), isTrue);
    await killApp(tester);
  });

  testWidgets(
    'reopen, then the server changes the access → the new tabs, not one change behind',
    (tester) async {
      final device = await LiveDevice.create();
      final c1 = await launchApp(tester, device);
      await signIn(tester, c1, 'sahip');
      expect(
        c1.read(navLayoutProvider).inBar(DestinationId.quoteDesk),
        isTrue,
      );
      await killApp(tester);

      final c2 = await launchApp(tester, device);
      await pumpFor(tester, const Duration(seconds: 2));
      expect(inShell(c2), isTrue, reason: describeShell(c2));

      // The owner loses the quote desk (a role change on the panel).
      final server = device.server;
      server.get('me/access', (req) {
        final j = Map<String, Object?>.of(
          server.world.meAccess(req.requireUser()),
        );
        j['pages'] = [
          for (final p in (j['pages']! as List).cast<String>())
            if (!p.startsWith('${Pg.stationQuoteDesk}:')) p,
        ];
        j['accessVersion'] = '2';
        return j;
      });
      await tester.runAsync(
        () => c2
            .read(sessionControllerProvider.notifier)
            .refreshAccess(force: true),
      );
      await pumpFor(tester, const Duration(seconds: 1));
      final layout = c2.read(navLayoutProvider);
      expect(layout.inBar(DestinationId.quoteDesk), isFalse, reason: '$layout');
      expect(layout.contains(DestinationId.quoteDesk), isFalse);
      expect(
        find.byType(AnimatedBottomBar),
        findsOneWidget,
        reason: describeShell(c2),
      );
      expect(inShell(c2), isTrue);
      await killApp(tester);
    },
  );
}

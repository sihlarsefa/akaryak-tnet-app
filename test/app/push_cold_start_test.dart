// Push dokunuşu oturum bilinmeden gelirse (soğuk açılış: `getInitialMessage`, oturum geri yüklenmeden):
// rota o anki (oturumsuz) yetkiyle reddedilip gelen kutusuna düşmez; olduğu gibi saklanır ve oturum
// açılınca kullanıcının yetkisiyle açılır. İzin yoksa `/notifications` (spec C.4).
import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/models/app_config.dart';
import 'package:akaryakitnet/core/push/local_notifications.dart';
import 'package:akaryakitnet/core/push/push_providers.dart';
import 'package:akaryakitnet/core/routing/route_access.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

String _location(ProviderContainer c) =>
    c.read(routerProvider).routerDelegate.currentConfiguration.uri.toString();

Future<void> _login(
  WidgetTester tester,
  ProviderContainer c,
  String key,
) async {
  await tester.runAsync(() async {
    final session = c.read(sessionControllerProvider.notifier);
    final outcome = await session.loginWithPassword(key, 'demo');
    if (outcome is LoginNeedsCode) {
      await session.verifyCode(outcome.challenge.challengeId, '123456');
    }
  });
  await _pumpFor(tester, const Duration(seconds: 2));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'oturum geri yüklenmeden gelen dokunuş rota olarak saklanır (gelen kutusuna düşmez)',
    () async {
      LocalNotifications.onTap = null;
      final h = await TestHarness.create(
        prefs: const {'akn.onboardingDone': true},
      );
      final c = h.container();
      addTearDown(c.dispose);
      // AknApp gibi: push koordinatörü oturum geri yüklenmeden başlar.
      c.read(pushCoordinatorProvider);
      for (var i = 0; i < 100 && LocalNotifications.onTap == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(c.read(sessionControllerProvider), isA<SessionUnknown>());
      LocalNotifications.onTap!('/orders/123');
      await pumpEventQueue();
      expect(c.read(pendingDeepLinkProvider), '/orders/123');
      expect(c.read(pendingDeepLinkProvider.notifier).fromPush, isTrue);
      // Biçimsiz rota yine gelen kutusu.
      LocalNotifications.onTap!('orders/123');
      await pumpEventQueue();
      expect(c.read(pendingDeepLinkProvider), '/notifications');
    },
  );

  testWidgets('oturumsuzken dokunulan push: girişten sonra sipariş açılır', (
    tester,
  ) async {
    final h = await TestHarness.create(
      prefs: const {'akn.onboardingDone': true},
    );
    await tester.pumpWidget(
      ProviderScope(overrides: h.overrides, child: const AknApp()),
    );
    await _pumpFor(tester, const Duration(seconds: 2));
    final c = ProviderScope.containerOf(tester.element(find.byType(AknApp)));
    expect(c.read(sessionControllerProvider), isA<SessionUnauthenticated>());
    final orderId = h.server.world.orders.firstWhere(
      (o) => o['customerId'] == 101,
    )['id'];
    LocalNotifications.onTap!('/orders/$orderId');
    await tester.pump();
    expect(c.read(pendingDeepLinkProvider), '/orders/$orderId');
    await _login(tester, c, 'musteri');
    expect(_location(c), '/orders/$orderId');
    expect(c.read(pendingDeepLinkProvider), isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'oturumsuzken dokunulan push: kullanıcının açamadığı rota gelen kutusuna düşer',
    (tester) async {
      final h = await TestHarness.create(
        prefs: const {'akn.onboardingDone': true},
      );
      await tester.pumpWidget(
        ProviderScope(overrides: h.overrides, child: const AknApp()),
      );
      await _pumpFor(tester, const Duration(seconds: 2));
      final c = ProviderScope.containerOf(tester.element(find.byType(AknApp)));
      LocalNotifications.onTap!('/bayi/orders/12');
      await tester.pump();
      await _login(tester, c, 'musteri');
      expect(_location(c), '/notifications');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('oturum açıkken dokunuş hemen yetkiyle çözülür', () async {
    LocalNotifications.onTap = null;
    final h = await TestHarness.create(
      prefs: const {'akn.onboardingDone': true},
    );
    final c = h.container();
    addTearDown(c.dispose);
    c.read(pushCoordinatorProvider);
    final s = c.read(sessionControllerProvider.notifier);
    await s.restore();
    await s.loginWithPassword('musteri', 'demo');
    for (var i = 0; i < 100 && LocalNotifications.onTap == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    LocalNotifications.onTap!('/bayi/orders/12');
    await pumpEventQueue();
    expect(c.read(pendingDeepLinkProvider), '/notifications');
    expect(c.read(pendingDeepLinkProvider.notifier).fromPush, isFalse);
    expect(
      RouteAccess.resolvePushRoute(
        '/orders/7',
        c.read(accessPolicyProvider),
        const AppFeatures(),
      ),
      '/orders/7',
    );
  });
}

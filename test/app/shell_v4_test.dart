// v4 "Sade" shell (spec §3.1, §3.5, §9 core tests): the bar is fixed at login, Android back on a tab
// root springs home, a page that cannot pop leads home with the "Ana sayfa" button, and the Diğer dot
// lights only for your-move items that live in Diğer.
import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/app/shell/shell_badges.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/push/unread_count_provider.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

Future<ProviderContainer> _app(WidgetTester tester, String key) async {
  final h = await TestHarness.create(prefs: const {'akn.onboardingDone': true});
  await tester.pumpWidget(
    ProviderScope(overrides: h.overrides, child: const AknApp()),
  );
  await _pumpFor(tester, const Duration(seconds: 2));
  final c = ProviderScope.containerOf(tester.element(find.byType(AknApp)));
  await tester.runAsync(() async {
    final s = c.read(sessionControllerProvider.notifier);
    final outcome = await s.loginWithPassword(key, 'demo');
    if (outcome is LoginNeedsCode) {
      await s.verifyCode(outcome.challenge.challengeId, '123456');
    }
  });
  await _pumpFor(tester, const Duration(seconds: 3));
  expect(c.read(sessionControllerProvider), isA<SessionAuthenticated>());
  return c;
}

String _top(ProviderContainer c) => c
    .read(routerProvider)
    .routerDelegate
    .currentConfiguration
    .last
    .matchedLocation;

void main() {
  test('çubuk girişte sabittir: bekleyen onay çubuğu değiştirmez', () async {
    final h = await TestHarness.create();
    final c = h.container();
    addTearDown(c.dispose);
    final s = c.read(sessionControllerProvider.notifier);
    final outcome = await s.loginWithPassword('muhasebe', 'demo');
    if (outcome is LoginNeedsCode) {
      await s.verifyCode(outcome.challenge.challengeId, '123456');
    }
    final before = c.read(navLayoutProvider);
    expect(before.inBar(DestinationId.approvals), isFalse);
    c.read(unreadCountProvider.notifier).adjust(approvals: 5);
    await Future<void>.delayed(Duration.zero);
    final after = c.read(navLayoutProvider);
    expect(after, before);
    expect(after.inBar(DestinationId.approvals), isFalse);
  });

  testWidgets('Android geri: sekme kökünde Ana sayfa\'ya döner', (
    tester,
  ) async {
    final c = await _app(tester, 'sahip');
    c.read(routerProvider).go('/approvals');
    await _pumpFor(tester, const Duration(milliseconds: 800));
    expect(_top(c), '/approvals');
    await tester.binding.handlePopRoute();
    await _pumpFor(tester, const Duration(milliseconds: 800));
    expect(_top(c), '/home');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('geri dönülemeyen sayfa "Ana sayfa" düğmesiyle eve döner', (
    tester,
  ) async {
    final c = await _app(tester, 'musteri');
    c.read(routerProvider).go('/stats');
    await _pumpFor(tester, const Duration(milliseconds: 1200));
    expect(_top(c), '/stats');
    final home = find.byTooltip('Ana sayfa');
    expect(home, findsOneWidget);
    await tester.tap(home);
    await _pumpFor(tester, const Duration(milliseconds: 800));
    expect(_top(c), '/home');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Diğer noktası okunmamış bildirim için yanmaz', (tester) async {
    final c = await _app(tester, 'musteri');
    c.read(unreadCountProvider.notifier).adjust(notifications: 7);
    await _pumpFor(tester, const Duration(milliseconds: 400));
    final badges = c.read(destinationBadgesProvider);
    final layout = c.read(navLayoutProvider);
    final expected = layout.more.any(
      (d) => yourMoveDestinations.contains(d.id) && (badges[d.id] ?? 0) > 0,
    );
    final bar = tester.widget<AnimatedBottomBar>(
      find.byType(AnimatedBottomBar),
    );
    final more = bar.items.last;
    expect(more.label, NavLayout.moreLabel);
    expect(more.showDot, expected);
    // The key's label is ink (only the selected tab is orange).
    final key = find.text('Sipariş ver');
    expect(key, findsOneWidget);
    expect(tester.widget<Text>(key).style!.color, AknColors.light.ink);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

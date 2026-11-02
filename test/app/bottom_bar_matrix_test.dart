// "Alttaki tuşlar gelmiyor": the tab bar must be there for every persona, on every phone size, whatever
// the network does. Matrix on the path that was broken in TestFlight 4–10 (reopening the app with a
// saved session, live stack):
//
// * personas × iPhone sizes (375×667 without a home indicator; 390×844 and 430×932 with 34 dp) on a
//   healthy network: the bar is in the shell, fully on screen, flush with the bottom, at least three
//   destinations, the centre key where the role has one;
// * personas × data states (every GET slow 6 s, every GET 429 with Retry-After, every GET 503): the
//   bar never waits for data — it is there as soon as the splash ends and stays.
import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/live_device.dart';

const _sizes = <(String, Size, double)>[
  ('375x667', Size(375, 667), 0),
  ('390x844', Size(390, 844), 34),
  ('430x932', Size(430, 932), 34),
];

enum _Net { ok, slow, rateLimited, unavailable }

/// Every GET (including me/access and app/config) shaped; sign-in (POST) is not part of the reopen.
List<NetRule> _rules(_Net n) => switch (n) {
  _Net.ok => const [],
  _Net.slow => [
    NetRule(match: (m, _, _) => m == 'GET', delay: const Duration(seconds: 6)),
  ],
  _Net.rateLimited => [
    NetRule(match: (m, _, _) => m == 'GET', status: 429, retryAfterSeconds: 1),
  ],
  _Net.unavailable => [NetRule(match: (m, _, _) => m == 'GET', status: 503)],
};

void _setPhone(WidgetTester tester, Size size, double bottomInset) {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  final top = bottomInset > 0 ? 47.0 : 20.0;
  tester.view.padding = FakeViewPadding(top: top * 3, bottom: bottomInset * 3);
  tester.view.viewPadding = FakeViewPadding(
    top: top * 3,
    bottom: bottomInset * 3,
  );
}

Future<void> _expectUsableBar(
  WidgetTester tester,
  ProviderContainer c,
  Size screen,
  String why,
) async {
  final bar = find.byType(AnimatedBottomBar);
  expect(bar, findsOneWidget, reason: '$why: ${describeShell(c)}');
  expect(inShell(c), isTrue, reason: why);
  final layout = c.read(navLayoutProvider);
  expect(layout.bar.length, greaterThanOrEqualTo(3), reason: why);
  final r = tester.getRect(bar);
  expect(r.left, greaterThanOrEqualTo(-0.5), reason: '$why: $r');
  expect(r.right, lessThanOrEqualTo(screen.width + 0.5), reason: '$why: $r');
  // Flush with the bottom edge (the safe area is inside the bar), never under it.
  expect(r.bottom, closeTo(screen.height, 0.5), reason: '$why: $r');
  expect(r.height, greaterThanOrEqualTo(56), reason: '$why: $r');
  final center = layout.center;
  if (center != null) {
    expect(
      find.descendant(of: bar, matching: find.text(center.label)),
      findsOneWidget,
      reason: '$why: centre key ${center.label}',
    );
  }
}

void main() {
  setUpAll(() {
    AknMotion.ambient = false;
    AknHaptics.enabled = false;
  });

  group('sizes', () {
    for (final (name, size, inset) in _sizes) {
      for (final user in livePersonas) {
        testWidgets('$user on $name: reopen → usable bar', (tester) async {
          addTearDown(tester.view.reset);
          _setPhone(tester, size, inset);
          final device = await LiveDevice.create();
          final c1 = await launchApp(tester, device);
          await signIn(tester, c1, user);
          await killApp(tester);
          final c2 = await launchApp(
            tester,
            device,
            settle: const Duration(milliseconds: 1600),
          );
          await _expectUsableBar(tester, c2, size, '$user $name');
          await killApp(tester);
        });
      }
    }
  });

  group('data states', () {
    const size = Size(390, 844);
    for (final net in [_Net.slow, _Net.rateLimited, _Net.unavailable]) {
      for (final user in livePersonas) {
        testWidgets('$user, every GET ${net.name}: the bar does not wait', (
          tester,
        ) async {
          addTearDown(tester.view.reset);
          _setPhone(tester, size, 34);
          final device = await LiveDevice.create();
          final c1 = await launchApp(tester, device);
          await signIn(tester, c1, user);
          await killApp(tester);
          final c2 = await launchApp(
            tester,
            device,
            rules: _rules(net),
            settle: const Duration(milliseconds: 1600),
          );
          await _expectUsableBar(tester, c2, size, '$user ${net.name} t=1.6s');
          // Still there once the data arrived (or failed for good).
          await pumpFor(tester, const Duration(seconds: 8));
          await _expectUsableBar(tester, c2, size, '$user ${net.name} t=9.6s');
          await killApp(tester);
        });
      }
    }
  });
}

// Owner decision G with v4 §3.3 / §7: every home leads with the "Sıra sizde" card — the first child of
// the band overlap is AknTaskCard (the white hero card on the orange band); the driver keeps its stop
// plate. Core wired Merkez; areas A (musteri, talep) and B (sahip, saha) wired their homes in Phase 2.
import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
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

Future<void> _home(WidgetTester tester, String key) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
}

/// The first band overlap's hero is the "Sıra sizde" card.
void _expectTaskHero(WidgetTester tester) {
  final overlap = find.byType(AknBandOverlap).first;
  expect(
    find.descendant(of: overlap, matching: find.byType(AknTaskCard)),
    findsOneWidget,
  );
  // The card sits on the band and starts in the first viewport.
  final card = tester.getRect(find.byType(AknTaskCard).first);
  expect(card.top, lessThan(260));
}

void main() {
  testWidgets('merkez: "Sıra sizde" bandın üstünde, sonra Web portalı', (
    tester,
  ) async {
    await _home(tester, 'merkez');
    _expectTaskHero(tester);
    expect(find.text('Web portalı'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  // Areas A (musteri, talep) and B (sahip, saha) wire AknTaskCard as their home hero (spec §3.3, §8).
  for (final key in ['musteri', 'talep', 'sahip', 'saha']) {
    testWidgets('$key: kahraman "Sıra sizde"', (tester) async {
      await _home(tester, key);
      _expectTaskHero(tester);
      final error = tester.takeException();
      expect(error, isNull, reason: '$error');
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('sofor: durak plakası kalır (görev kartı yok)', (tester) async {
    await _home(tester, 'sofor');
    expect(find.byType(AknTaskCard), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

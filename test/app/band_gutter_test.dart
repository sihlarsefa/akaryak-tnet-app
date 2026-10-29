// v4 §5 09 ("pushed from Diğer, the page looks the same"): a band page opened with a leading button —
// the house on a cold start, the back button when pushed from Diğer — still ends on the page gutter,
// in line with the switcher and the ledgers under it (it ran 12 dp past them before).
import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/ui/ui_test_helpers.dart';
import '../support/test_app.dart';

Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

Future<ProviderContainer> _signedIn(WidgetTester tester, String key) async {
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
  return c;
}

/// The right edge of the content under the band: the switcher's track, else
/// the first ledger's card (both keep their own page margin, so the widest
/// painted box inside them is measured).
double _contentRight(WidgetTester tester) {
  final seg = find.byWidgetPredicate((w) => w is AknSegmented);
  final host = seg.evaluate().isNotEmpty
      ? seg.first
      : find.byType(AknLedger).first;
  final boxes = find.descendant(
    of: host,
    matching: find.byWidgetPredicate(
      (w) => w is DecoratedBox || w is Container,
    ),
  );
  Rect? widest;
  for (final e in boxes.evaluate()) {
    final ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize) continue;
    final r = ro.localToGlobal(Offset.zero) & ro.size;
    if (r.right > 389.5) continue;
    if (widest == null || r.width > widest.width) widest = r;
  }
  expect(widest, isNotNull, reason: 'no painted box under the band');
  return widest!.right;
}

void main() {
  for (final leading in ['house', 'back']) {
    testWidgets('AppScaffold: the band behind a $leading button ends on the '
        'gutter', (tester) async {
      Widget page(BuildContext context) => AppScaffold(
        title: 'Finans',
        bandIcon: PhosphorIconsRegular.bank,
        largeTitle: true,
        status: '1 cari finans onayınızı bekliyor',
        leading: leading == 'house' ? AknHomeButton(onPressed: () {}) : null,
        actions: [
          AknSearchReveal.button(semanticLabel: 'Ara', onPressed: () {}),
        ],
        body: const Padding(
          padding: EdgeInsets.symmetric(horizontal: AknSpace.page),
          child: SizedBox(key: ValueKey('content'), height: 40),
        ),
      );
      await pumpUi(
        tester,
        Builder(
          builder: (context) => leading == 'house'
              ? page(context)
              : Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).push(MaterialPageRoute<void>(builder: page)),
                      child: const Text('aç'),
                    ),
                  ),
                ),
        ),
        scaffold: false,
        size: const Size(390, 844),
      );
      if (leading == 'back') {
        await tester.tap(find.text('aç'));
        await tester.pumpAndSettle();
        expect(find.byType(BackButton), findsOneWidget);
      } else {
        expect(find.byType(AknHomeButton), findsOneWidget);
      }
      final band = tester.getRect(find.byType(AknPageBand));
      final content = tester.getRect(find.byKey(const ValueKey('content')));
      expect(band.right, moreOrLessEquals(content.right, epsilon: 0.5));
      expect(band.right, moreOrLessEquals(390 - AknSpace.page, epsilon: 0.5));
      expect(tester.takeException(), isNull);
    });
  }

  for (final (persona, route, title) in [
    ('sahip', '/finance', 'Finans'),
    ('sahip', '/payments', 'Tahsilat'),
    ('muhasebe', '/approvals', 'Onaylar'),
  ]) {
    testWidgets('$persona $route (house): the band ends where the switcher '
        'and the ledgers end', (tester) async {
      final c = await _signedIn(tester, persona);
      c.read(routerProvider).go(route);
      await _pumpFor(tester, const Duration(seconds: 2));
      final band = find.byType(AknPageBand);
      expect(band, findsOneWidget);
      expect(tester.widget<AknPageBand>(band).title, title);
      expect(find.byType(AknHomeButton), findsOneWidget);
      final right = tester.getRect(band).right;
      expect(right, moreOrLessEquals(390 - AknSpace.page, epsilon: 0.5));
      expect(right, moreOrLessEquals(_contentRight(tester), epsilon: 0.5));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

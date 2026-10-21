// Ana sayfadaki deste, uygulamanın kendisinde (görsel kontrol; altın karşılaştırma değildir). Normal
// çalışmada atlanır:
//
//   flutter test test/features/stats/stats_home_capture_test.dart --dart-define=AKN_SCREENS_DIR=/tam/yol
//
// Sahip, müşteri ve saha temsilcisinin ana sayfası 390 × 844'te (açık 1,0×, koyu 1,0×, açık 2,0×), Mona
// Sans ile çizilir; tasarım panosunun 2, 3, 8 ve 9. ekranlarıyla karşılaştırın.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/a11y.dart';
import '../../support/fonts.dart';
import '../../support/test_app.dart';

const _screens = String.fromEnvironment('AKN_SCREENS_DIR');
const _legacy = String.fromEnvironment('AKN_STATS_SHOTS');
const _outDir = _screens == '' ? _legacy : _screens;

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_outDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    if (_outDir.isNotEmpty) await loadRealFonts();
  });

  const variants = [
    ('acik', A11yVariant(1, Brightness.light)),
    ('koyu', A11yVariant(1, Brightness.dark)),
    ('buyuk', A11yVariant(2, Brightness.light)),
  ];

  for (final persona in ['sahip', 'musteri', 'saha']) {
    for (final (tag, variant) in variants) {
      testWidgets('$persona $tag ana sayfa', (tester) async {
        setA11yPhone(tester, size: const Size(390, 844));
        setA11yPlatform(tester, variant);
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = true);
        tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
        tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
        final key = GlobalKey();
        final h = await TestHarness.create(
          prefs: const {'akn.onboardingDone': true, 'akn.stats.deckHint': true},
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: ProviderScope(overrides: h.overrides, child: const AknApp()),
          ),
        );
        await pumpSteps(tester, const Duration(seconds: 2));
        final c = ProviderScope.containerOf(
          tester.element(find.byType(AknApp)),
        );
        await tester.runAsync(() async {
          final s = c.read(sessionControllerProvider.notifier);
          final outcome = await s.loginWithPassword(persona, 'demo');
          if (outcome is LoginNeedsCode) {
            await s.verifyCode(outcome.challenge.challengeId, '123456');
          }
        });
        await pumpSteps(tester, const Duration(seconds: 2));
        await settleIo(tester, rounds: 10);
        await pumpSteps(tester, const Duration(seconds: 3));
        await _capture(tester, key, 'ev/${persona}_$tag');
        await tester.pumpWidget(const SizedBox());
        debugDisableShadows = true;
      }, skip: _outDir.isEmpty);
    }
  }
}

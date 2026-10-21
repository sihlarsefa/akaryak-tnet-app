import 'package:akaryakitnet/app/splash/splash_screen.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test_helpers.dart';

LogoMarkPainter _markPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((p) => p.painter)
    .whereType<LogoMarkPainter>()
    .single;

void main() {
  testWidgets('first frame reproduces the native splash; then draws in', (
    tester,
  ) async {
    var finished = 0;
    await pumpUi(
      tester,
      SplashScreen(onFinished: () => finished++),
      scaffold: false,
    );
    // Frame 0: the full mark at the native size on navy.
    final mark = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is LogoMarkPainter,
    );
    expect(
      tester.getSize(mark),
      const Size.square(SplashScreen.nativeMarkSize),
    );
    expect(_markPainter(tester).trackOpacity, 1);
    expect(_markPainter(tester).progress, 0);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AknColors.light.navy);

    // Mid-way the chevrons are being drawn over a faint track.
    await tester.pump(const Duration(milliseconds: 400));
    final mid = _markPainter(tester);
    expect(mid.progress, greaterThan(0));
    expect(mid.progress, lessThan(1));
    expect(mid.trackOpacity, lessThan(0.5));

    await tester.pump(SplashScreen.minimumDisplay);
    expect(finished, 1);
    expect(_markPainter(tester).progress, 1);
    expect(
      tester.getSize(mark),
      const Size.square(SplashScreen.settledMarkSize),
    );
    expect(find.text('Siparişten teslimata'), findsOneWidget);

    // Still waiting a while later: a quiet loader appears.
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ChevronSpinner), findsOneWidget);
  });

  testWidgets('reduce motion: final frame at once, done after 300 ms', (
    tester,
  ) async {
    var finished = 0;
    await pumpUi(
      tester,
      SplashScreen(onFinished: () => finished++),
      scaffold: false,
      reduceMotion: true,
    );
    expect(_markPainter(tester).progress, 1);
    expect(finished, 0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(finished, 1);
  });

  testWidgets('splash is never purple', (tester) async {
    await pumpUi(tester, const SplashScreen(), scaffold: false);
    await tester.pump(SplashScreen.minimumDisplay);
    final p = _markPainter(tester);
    for (final color in [p.tileColor, p.chevronColor, AknColors.light.navy]) {
      final hsv = HSVColor.fromColor(color);
      expect(hsv.saturation > 0.2 && hsv.hue >= 255 && hsv.hue <= 320, isFalse);
    }
    expect(p.tileColor, const Color(0xFFFF5001));
    // Let the delayed loader timer run out before the tree is disposed.
    await tester.pump(const Duration(seconds: 2));
  });
}

import 'package:akaryakitnet/app/splash/splash_screen.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test_helpers.dart';

LogoMarkPainter _markPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((p) => p.painter)
    .whereType<LogoMarkPainter>()
    .single;

/// Purple (owner decision 5): hue 250°–330° with clear saturation and
/// brightness.
bool _isPurple(Color c) {
  final hsv = HSVColor.fromColor(c);
  return c.a > 0.2 &&
      hsv.saturation > 0.25 &&
      hsv.value > 0.2 &&
      hsv.hue >= 250 &&
      hsv.hue <= 330;
}

/// The brand orange of the logo tile (#FF5001: hue ≈ 19°, fully saturated).
bool _isBrandOrange(Color c) {
  final hsv = HSVColor.fromColor(c);
  return c.a > 0.9 &&
      hsv.saturation > 0.9 &&
      hsv.value > 0.9 &&
      hsv.hue >= 12 &&
      hsv.hue <= 26;
}

/// Purple and brand-orange pixels in the image of the [key]ed repaint
/// boundary (every third pixel).
Future<({int purple, int orange})> _pixels(
  WidgetTester tester,
  GlobalKey key,
) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final counts = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData();
    image.dispose();
    final bytes = data!.buffer.asUint8List();
    var purple = 0;
    var orange = 0;
    for (var i = 0; i + 3 < bytes.length; i += 4 * 3) {
      final c = Color.fromARGB(
        bytes[i + 3],
        bytes[i],
        bytes[i + 1],
        bytes[i + 2],
      );
      if (_isPurple(c)) purple++;
      if (_isBrandOrange(c)) orange++;
    }
    return (purple: purple, orange: orange);
  });
  return counts ?? (purple: 0, orange: 0);
}

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
    // Frame 0: the full mark at the native size on white (native splash),
    // nothing else yet.
    final mark = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is LogoMarkPainter,
    );
    final word = find.byType(AknWordmark);
    double wordOpacity() => tester
        .widget<Opacity>(
          find.ancestor(of: word, matching: find.byType(Opacity)).first,
        )
        .opacity;
    expect(
      tester.getSize(mark),
      const Size.square(SplashScreen.nativeMarkSize),
    );
    expect(_markPainter(tester).trackOpacity, 1);
    expect(_markPainter(tester).progress, 0);
    expect(wordOpacity(), 0);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, const Color(0xFFFFFFFF));
    // Dark status-bar icons on white (never light icons on white).
    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
    );
    expect(region.value.statusBarIconBrightness, Brightness.dark);

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
    // v3: the "AkaryakıtNet" wordmark has risen under the settled tile; no
    // tagline.
    expect(find.text('Siparişten teslimata'), findsNothing);
    expect(word, findsOneWidget);
    expect(wordOpacity(), 1);
    expect(tester.getRect(word).top, greaterThan(tester.getRect(mark).bottom));
    expect(tester.getCenter(word).dx, closeTo(tester.getCenter(mark).dx, 0.5));

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

  for (final b in Brightness.values) {
    testWidgets('splash is never purple [${b.name}]', (tester) async {
      final key = GlobalKey();
      await pumpUi(
        tester,
        RepaintBoundary(key: key, child: const SplashScreen()),
        scaffold: false,
        brightness: b,
      );
      await tester.pump(SplashScreen.minimumDisplay);
      final p = _markPainter(tester);
      for (final color in [
        p.tileColor,
        p.chevronColor,
        SplashScreen.background(AknColors.light),
        SplashScreen.background(AknColors.dark),
      ]) {
        final hsv = HSVColor.fromColor(color);
        expect(
          hsv.saturation > 0.2 && hsv.hue >= 255 && hsv.hue <= 320,
          isFalse,
        );
      }
      expect(p.tileColor, const Color(0xFFFF5001));
      expect(p.chevronColor, const Color(0xFFFFFFFF));
      // The page itself stays flat (white; the dark page in dark mode): no
      // decorated box paints a gradient wash over it.
      for (final box in tester.widgetList<DecoratedBox>(
        find.byType(DecoratedBox),
      )) {
        final d = box.decoration;
        expect(d is BoxDecoration && d.gradient != null, isFalse);
      }
      // v3: the only light is the warm glow painted behind the mark — every
      // drawn pixel (the light, the tile, the wordmark) stays off purple.
      final pixels = await _pixels(tester, key);
      expect(pixels.orange, greaterThan(0), reason: 'the tile is drawn');
      expect(pixels.purple, 0);
      // Let the delayed loader timer run out before the tree is disposed.
      await tester.pump(const Duration(seconds: 2));
    });
  }

  testWidgets('dark mode: the graphite page, light status icons', (
    tester,
  ) async {
    await pumpUi(
      tester,
      const SplashScreen(),
      scaffold: false,
      brightness: Brightness.dark,
    );
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AknColors.dark.bg);
    final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
    );
    expect(region.value.statusBarIconBrightness, Brightness.light);
    await tester.pump(SplashScreen.minimumDisplay);
    await tester.pump(const Duration(seconds: 2));
  });
}

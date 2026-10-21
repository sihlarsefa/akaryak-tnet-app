import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [child] inside a themed MaterialApp (+ Scaffold) for design-system
/// tests. [reduceMotion] and [textScale] are applied through MediaQuery.
Future<void> pumpUi(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  bool reduceMotion = false,
  double textScale = 1,
  bool scaffold = true,
  bool scroll = false,
  Size? size,
}) async {
  if (size != null) {
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
  }
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AknTheme.light(),
      darkTheme: AknTheme.dark(),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reduceMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: app!,
      ),
      home: scaffold
          ? Scaffold(
              body: scroll
                  ? SingleChildScrollView(child: child)
                  : SafeArea(child: child),
            )
          : child,
    ),
  );
}

/// Runs [body] once per theme brightness (light, dark).
void testBothThemes(
  String description,
  Future<void> Function(WidgetTester tester, Brightness brightness) body,
) {
  for (final b in Brightness.values) {
    testWidgets('$description [${b.name}]', (tester) => body(tester, b));
  }
}

/// WCAG 2.x contrast ratio of two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// [fg] composited over [bg] (for translucent tokens).
Color over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

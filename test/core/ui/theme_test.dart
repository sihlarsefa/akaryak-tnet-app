import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AknTheme', () {
    for (final (name, theme, colors) in [
      ('light', AknTheme.light(), AknColors.light),
      ('dark', AknTheme.dark(), AknColors.dark),
    ]) {
      test('$name carries the token extensions', () {
        final c = theme.extension<AknColors>();
        final t = theme.extension<AknTextStyles>();
        expect(c, isNotNull);
        expect(t, isNotNull);
        expect(c!.brightness, colors.brightness);
        expect(theme.brightness, colors.brightness);
        expect(theme.colorScheme.primary, colors.brand);
        expect(theme.scaffoldBackgroundColor, colors.bg);
        expect(theme.useMaterial3, isTrue);
      });

      test(
        '$name page transitions: predictive back on Android, Cupertino on iOS',
        () {
          final builders = theme.pageTransitionsTheme.builders;
          expect(
            builders[TargetPlatform.android],
            isA<AknPredictiveBackPageTransitionsBuilder>(),
          );
          expect(
            builders[TargetPlatform.iOS],
            isA<CupertinoPageTransitionsBuilder>(),
          );
        },
      );

      test('$name filled buttons use the AA orange with a white label', () {
        final style = theme.filledButtonTheme.style!;
        final bg = style.backgroundColor!.resolve(<WidgetState>{});
        final fg = style.foregroundColor!.resolve(<WidgetState>{});
        expect(bg, const Color(0xFFC94C0C));
        expect(fg, const Color(0xFFFFFFFF));
        final min = style.minimumSize!.resolve(<WidgetState>{});
        expect(min!.height, greaterThanOrEqualTo(48));
      });
    }

    test('type scale matches spec C.5', () {
      final t = AknTextStyles.from(AknColors.light);
      void check(TextStyle s, double size, double line, FontWeight w) {
        expect(s.fontSize, size);
        expect((s.height! * size).roundToDouble(), line);
        expect(s.fontWeight, w);
      }

      check(t.display, 32, 40, FontWeight.w700);
      check(t.title, 22, 28, FontWeight.w700);
      check(t.headline, 18, 24, FontWeight.w600);
      check(t.body, 15, 22, FontWeight.w400);
      check(t.label, 13, 18, FontWeight.w600);
      check(t.caption, 12, 16, FontWeight.w400);
      expect(
        t.amount.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      expect(
        t.amountLarge.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    test('of(brightness) picks the matching theme', () {
      expect(AknTheme.of(Brightness.dark).brightness, Brightness.dark);
      expect(AknTheme.of(Brightness.light).brightness, Brightness.light);
    });
  });

  testWidgets('context.akn / aknText read the active theme', (tester) async {
    late AknColors seen;
    late AknTextStyles text;
    await tester.pumpWidget(
      MaterialApp(
        theme: AknTheme.dark(),
        home: Builder(
          builder: (context) {
            seen = context.akn;
            text = context.aknText;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen.brightness, Brightness.dark);
    expect(text.body.color, AknColors.dark.text);
  });

  testWidgets('context.akn falls back to light outside an Akn theme', (
    tester,
  ) async {
    late AknColors seen;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            seen = context.akn;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen.brand, AknColors.light.brand);
  });

  testWidgets('OnNavy re-themes content for navy panels', (tester) async {
    late AknColors inside;
    await tester.pumpWidget(
      MaterialApp(
        theme: AknTheme.light(),
        home: AknHeroPanel(
          child: Builder(
            builder: (context) {
              inside = context.akn;
              return const Text('Merhaba');
            },
          ),
        ),
      ),
    );
    expect(inside.ink, const Color(0xFFFFFFFF));
    expect(inside.surface, AknColors.light.navyRaised);
  });

  testWidgets('buttons inside a navy hero stay legible', (tester) async {
    late ThemeData inner;
    await tester.pumpWidget(
      MaterialApp(
        theme: AknTheme.light(),
        home: AknHeroPanel(
          child: Builder(
            builder: (context) {
              inner = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    final text = inner.textButtonTheme.style!.foregroundColor!.resolve({})!;
    final icon = inner.iconButtonTheme.style!.foregroundColor!.resolve({})!;
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
    }

    expect(contrast(text, AknColors.light.navy), greaterThanOrEqualTo(4.5));
    expect(icon, const Color(0xFFFFFFFF));
  });
}

// Driver mode (§6.30, §3.4): type one step larger, 64 px buttons (r14) and targets, 76 px rows,
// 64 px bar items; idempotent; dark driver keeps the dark tokens (plate and primary #E64800).
import 'package:akaryakitnet/core/ui/driver_mode.dart';
import 'package:akaryakitnet/core/ui/theme.dart';
import 'package:akaryakitnet/core/ui/tokens.dart';
import 'package:akaryakitnet/core/ui/typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _none = <WidgetState>{};

void main() {
  group('AknDriverMode.textStyles (§3.4)', () {
    final base = AknTextStyles.from(AknColors.light);
    final d = AknDriverMode.textStyles(base);

    void size(String name, TextStyle s, double fontSize, double line) {
      expect(s.fontSize, fontSize, reason: name);
      expect(s.height! * fontSize, closeTo(line, 1e-9), reason: name);
    }

    test('one step larger', () {
      size('display', d.display, 34, 40);
      size('title', d.title, 22, 28);
      size('headline', d.headline, 20, 26);
      size('body', d.body, 17, 24);
      size('bodySmall', d.bodySmall, 15, 20);
      size('label', d.label, 15, 20);
      size('button', d.button, 18, 22);
      size('navLabel', d.navLabel, 12, 15);
      size('plateFigure', d.plateFigure, 64, 62);
      size('plateUnit', d.plateUnit, 34, 34);
      size('number', d.number, 28, 32);
      size('stop name', AknDriverMode.stopName(d), 24, 30);
    });

    test('keeps families, weights and colours', () {
      expect(d.plateFigure.fontFamily, AknFonts.condensed);
      expect(d.plateFigure.fontWeight, FontWeight.w800);
      expect(d.body.color, base.body.color);
      expect(d.headline.fontWeight, base.headline.fontWeight);
      expect(d.body.leadingDistribution, TextLeadingDistribution.even);
    });

    test('applying it twice is the same as once', () {
      expect(AknDriverMode.textStyles(d), d);
    });
  });

  group('AknDriverMode.theme', () {
    for (final (name, theme, colors) in [
      ('light', AknTheme.light(), AknColors.light),
      ('dark (cab night)', AknTheme.dark(), AknColors.dark),
    ]) {
      test('$name: 64 px buttons with radius 14 and an 18/22 label', () {
        final dt = AknDriverMode.theme(theme);
        expect(dt.extension<AknDriverMode>(), AknDriverMode.standard);
        for (final style in [
          dt.filledButtonTheme.style!,
          dt.outlinedButtonTheme.style!,
          dt.textButtonTheme.style!,
        ]) {
          expect(style.minimumSize!.resolve(_none)!.height, 64);
          final shape = style.shape!.resolve(_none)! as RoundedRectangleBorder;
          expect(
            shape.borderRadius,
            const BorderRadius.all(Radius.circular(14)),
          );
          expect(style.textStyle!.resolve(_none)!.fontSize, 18);
          expect(style.iconSize!.resolve(_none), 24);
        }
        // Colours are unchanged: the dark plate and primary are #E64800.
        expect(
          dt.filledButtonTheme.style!.backgroundColor!.resolve(_none),
          colors.brandFill,
        );
        expect(dt.extension<AknColors>(), colors);
        expect(
          dt.iconButtonTheme.style!.minimumSize!.resolve(_none),
          const Size(64, 64),
        );
        expect(dt.listTileTheme.minTileHeight, 76);
        expect(dt.navigationBarTheme.height, 64);
        expect(dt.navigationBarTheme.iconTheme!.resolve(_none)!.size, 26);
        expect(dt.extension<AknTextStyles>()!.body.fontSize, 17);
        expect(dt.textTheme.bodyMedium!.fontSize, 17);
        // Idempotent.
        expect(identical(AknDriverMode.theme(dt), dt), isTrue);
      });
    }

    test('dark driver: the dark card and the gradient primary as they are', () {
      final c = AknDriverMode.theme(AknTheme.dark()).extension<AknColors>()!;
      // Decision G: the plate is the dark card, the primary keeps its
      // orange gradient with a white label at night too.
      expect(c.plate, AknColors.dark.plate);
      expect(c.brandFill, const Color(0xFFE8590C));
      expect(c.onBrandFill, const Color(0xFFFFFFFF));
    });

    test('copyWith and lerp', () {
      const a = AknDriverMode.standard;
      final b = a.copyWith(minTap: 72);
      expect(b.minTap, 72);
      expect(b.buttonHeight, 64);
      expect(a.lerp(b, 0.5).minTap, 68);
      expect(a.lerp(null, 0.5), a);
      expect(a.copyWith(), a);
    });
  });

  testWidgets('AknDriverScope puts its subtree in driver mode', (tester) async {
    late bool outside;
    late bool inside;
    late double tapOutside;
    late double tapInside;
    late AknTextStyles text;
    late bool disabled;
    await tester.pumpWidget(
      MaterialApp(
        theme: AknTheme.light(),
        home: Column(
          children: [
            Builder(
              builder: (context) {
                outside = context.isDriverMode;
                tapOutside = context.minTap;
                return const SizedBox();
              },
            ),
            AknDriverScope(
              child: AknDriverScope(
                child: Builder(
                  builder: (context) {
                    inside = context.isDriverMode;
                    tapInside = AknDriverMode.minTapOf(context);
                    text = context.aknText;
                    return const SizedBox();
                  },
                ),
              ),
            ),
            AknDriverScope(
              enabled: false,
              child: Builder(
                builder: (context) {
                  disabled = context.isDriverMode;
                  return const SizedBox();
                },
              ),
            ),
          ],
        ),
      ),
    );
    expect(outside, isFalse);
    expect(tapOutside, 48);
    expect(inside, isTrue);
    expect(tapInside, 64);
    expect(text.plateFigure.fontSize, 64);
    expect(text.headline.fontSize, 20);
    expect(disabled, isFalse);
  });
}

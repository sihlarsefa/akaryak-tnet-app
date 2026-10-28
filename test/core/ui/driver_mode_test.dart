// Driver mode (design v3, from v2 §6.30 and §3.4): type one step larger (the hero figure 56/60,
// tabular figures kept), 64 px superellipse buttons (r18) and targets, 76 px rows, 64 px bar items;
// idempotent; cab night keeps the dark tokens (the primary's orange gradient with a white label).
import 'package:akaryakitnet/core/ui/driver_mode.dart';
import 'package:akaryakitnet/core/ui/theme.dart';
import 'package:akaryakitnet/core/ui/tokens.dart';
import 'package:akaryakitnet/core/ui/typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _none = <WidgetState>{};

/// The theme's button background builders ignore their context.
class _NoContext extends Fake implements BuildContext {}

/// What [style] paints behind its label: the decoration of the gradient box
/// its `backgroundBuilder` returns (null: the plain fill).
ShapeDecoration? _painted(ButtonStyle style) {
  final built = style.backgroundBuilder?.call(
    _NoContext(),
    _none,
    const SizedBox(),
  );
  return built is DecoratedBox ? built.decoration as ShapeDecoration : null;
}

void main() {
  group('AknDriverMode.textStyles (v3, from §3.4)', () {
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
      size('bodyStrong', d.bodyStrong, 17, 24);
      size('bodySmall', d.bodySmall, 15, 20);
      size('label', d.label, 15, 20);
      size('caption', d.caption, 13, 18);
      size('captionStrong', d.captionStrong, 13, 18);
      size('button', d.button, 18, 22);
      size('navLabel', d.navLabel, 12, 15);
      size('amount', d.amount, 20, 26);
      size('amountLarge', d.amountLarge, 30, 34);
      size('number', d.number, 28, 32);
      size('numberLarge', d.numberLarge, 36, 40);
      size('plateFigure', d.plateFigure, 56, 60);
      size('plateUnit', d.plateUnit, 28, 32);
      size('figureWord', d.figureWord, 22, 26);
      size('readoutUnit', d.readoutUnit, 17, 32);
      size('stop name', AknDriverMode.stopName(d), 24, 30);
    });

    test('keeps the family, weights, colours and tabular figures', () {
      // One family in v3: Plus Jakarta Sans for words and figures.
      expect(d.plateFigure.fontFamily, AknFonts.sans);
      expect(d.body.fontFamily, AknFonts.sans);
      expect(d.plateFigure.fontWeight, FontWeight.w800);
      expect(d.button.fontWeight, base.button.fontWeight);
      expect(d.body.color, base.body.color);
      expect(d.headline.fontWeight, base.headline.fontWeight);
      expect(d.body.leadingDistribution, TextLeadingDistribution.even);
      for (final s in [d.plateFigure, d.plateUnit, d.number, d.amount]) {
        expect(s.fontFeatures, AknNumerals.tabular);
      }
      expect(d.body.fontFeatures ?? const [], isEmpty);
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
      test('$name: 64 px buttons with radius 18 and an 18/22 label', () {
        final dt = AknDriverMode.theme(theme);
        expect(dt.extension<AknDriverMode>(), AknDriverMode.standard);
        const shape = RoundedSuperellipseBorder(
          borderRadius: AknRadius.buttonDriver,
        );
        expect(
          AknRadius.buttonDriver,
          const BorderRadius.all(Radius.circular(18)),
        );
        for (final style in [
          dt.filledButtonTheme.style!,
          dt.elevatedButtonTheme.style!,
          dt.outlinedButtonTheme.style!,
          dt.textButtonTheme.style!,
        ]) {
          expect(style.minimumSize!.resolve(_none)!.height, 64);
          expect(style.shape!.resolve(_none), shape);
          final label = style.textStyle!.resolve(_none)!;
          expect(label.fontSize, 18);
          expect(label.height! * 18, closeTo(22, 1e-9));
          expect(label.fontWeight, FontWeight.w700);
          expect(style.iconSize!.resolve(_none), 24);
        }
        // The primary's gradient follows the driver radius; the others stay
        // plain.
        for (final primary in [
          dt.filledButtonTheme.style!,
          dt.elevatedButtonTheme.style!,
        ]) {
          expect(
            _painted(primary),
            ShapeDecoration(shape: shape, gradient: colors.buttonGradient),
          );
        }
        expect(_painted(dt.outlinedButtonTheme.style!), isNull);
        expect(_painted(dt.textButtonTheme.style!), isNull);
        // Colours are unchanged: the primary keeps the brand fill.
        expect(
          dt.filledButtonTheme.style!.backgroundColor!.resolve(_none),
          colors.brandFill,
        );
        expect(
          dt.filledButtonTheme.style!.foregroundColor!.resolve(_none),
          colors.onBrandFill,
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
      // orange gradient (#FF7B35 → #E5530A) with a white label at night too.
      expect(c.plate, AknColors.dark.plate);
      expect(c.brandFillStart, const Color(0xFFFF7B35));
      expect(c.brandFill, const Color(0xFFE5530A));
      expect(c.onBrandFill, const Color(0xFFFFFFFF));
    });

    test('copyWith and lerp', () {
      const a = AknDriverMode.standard;
      final b = a.copyWith(minTap: 72);
      expect(b.minTap, 72);
      expect(b.buttonHeight, 64);
      expect(a.buttonRadius, 18);
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
    expect(text.plateFigure.fontSize, 56);
    expect(text.headline.fontSize, 20);
    expect(disabled, isFalse);
  });
}

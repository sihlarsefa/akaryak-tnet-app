import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test_helpers.dart';

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

      test(
        '$name filled buttons: brandFill, white label, 52 dp, 14 radius',
        () {
          final style = theme.filledButtonTheme.style!;
          final bg = style.backgroundColor!.resolve(<WidgetState>{});
          final fg = style.foregroundColor!.resolve(<WidgetState>{});
          expect(bg, const Color(0xFFD14408));
          expect(fg, const Color(0xFFFFFFFF));
          final min = style.minimumSize!.resolve(<WidgetState>{});
          expect(min!.height, greaterThanOrEqualTo(52));
          final shape =
              style.shape!.resolve(<WidgetState>{})! as RoundedRectangleBorder;
          expect(shape.borderRadius, AknRadius.button);
          final label = style.textStyle!.resolve(<WidgetState>{})!;
          expect(label.fontWeight, FontWeight.w700);
        },
      );

      test('$name app bar: surface, ink title w800, no elevation at rest', () {
        final a = theme.appBarTheme;
        expect(a.backgroundColor, colors.surface);
        expect(a.foregroundColor, colors.ink);
        expect(a.elevation, 0);
        expect(a.centerTitle, isFalse);
        expect(a.titleTextStyle!.fontWeight, FontWeight.w800);
        expect(a.titleTextStyle!.letterSpacing, -0.3);
        expect(a.systemOverlayStyle, AknTheme.overlayFor(colors.brightness));
      });

      test('$name inputs: filled surfaceAlt, no border until focused', () {
        final i = theme.inputDecorationTheme;
        expect(i.filled, isTrue);
        expect(i.fillColor, colors.surfaceAlt);
        expect(i.floatingLabelBehavior, FloatingLabelBehavior.always);
        final enabled = i.enabledBorder! as OutlineInputBorder;
        expect(enabled.borderSide.color.a, 0);
        expect(enabled.borderRadius, AknRadius.input);
        final focused = i.focusedBorder! as OutlineInputBorder;
        expect(focused.borderSide.color, colors.brand);
        expect(focused.borderSide.width, 2);
      });

      test('$name chips are pills; selected = brandFill', () {
        final ch = theme.chipTheme;
        expect(ch.shape, isA<StadiumBorder>());
        expect(ch.selectedColor, colors.brandFill);
      });

      test('$name sheets and dialogs: raised surface, 24 radius', () {
        expect(theme.bottomSheetTheme.backgroundColor, colors.surfaceRaised);
        expect(
          (theme.bottomSheetTheme.shape! as RoundedRectangleBorder)
              .borderRadius,
          AknRadius.sheet,
        );
        expect(
          (theme.dialogTheme.shape! as RoundedRectangleBorder).borderRadius,
          AknRadius.dialog,
        );
      });

      test('$name inverse surfaces are charcoal, never navy', () {
        final snack = theme.snackBarTheme.backgroundColor!;
        final hsv = HSVColor.fromColor(snack);
        expect(hsv.saturation, lessThan(0.3), reason: '$snack');
        expect(
          contrast(const Color(0xFFFFFFFF), snack),
          greaterThanOrEqualTo(4.5),
        );
      });
    }

    test('type scale: display / title w800 with tight tracking', () {
      final t = AknTextStyles.from(AknColors.light);
      void check(TextStyle s, double size, double line, FontWeight w) {
        expect(s.fontSize, size);
        expect((s.height! * size).roundToDouble(), line);
        expect(s.fontWeight, w);
      }

      check(t.display, 32, 40, FontWeight.w800);
      check(t.title, 22, 28, FontWeight.w800);
      check(t.headline, 18, 24, FontWeight.w700);
      check(t.body, 15, 22, FontWeight.w400);
      check(t.label, 13, 18, FontWeight.w600);
      check(t.caption, 12, 16, FontWeight.w400);
      check(t.number, 28, 34, FontWeight.w800);
      check(t.numberLarge, 34, 40, FontWeight.w800);
      expect(t.display.letterSpacing, lessThan(0));
      expect(t.title.letterSpacing, lessThan(0));
      for (final s in [t.amount, t.amountLarge, t.number, t.numberLarge]) {
        expect(s.fontFeatures, contains(const FontFeature.tabularFigures()));
      }
    });

    test('text styles lerp and copyWith keep the number styles', () {
      final a = AknTextStyles.from(AknColors.light);
      final b = AknTextStyles.from(AknColors.dark);
      expect(a.lerp(b, 1).number.color, b.number.color);
      expect(a.copyWith().numberLarge, a.numberLarge);
    });

    test('of(brightness) picks the matching theme', () {
      expect(AknTheme.of(Brightness.dark).brightness, Brightness.dark);
      expect(AknTheme.of(Brightness.light).brightness, Brightness.light);
    });

    test('system bars: dark icons on light pages, light icons on the hero', () {
      final light = AknTheme.overlayFor(Brightness.light);
      expect(light.statusBarIconBrightness, Brightness.dark);
      expect(light.statusBarBrightness, Brightness.light);
      expect(light.systemNavigationBarIconBrightness, Brightness.dark);
      final dark = AknTheme.overlayFor(Brightness.dark);
      expect(dark.statusBarIconBrightness, Brightness.light);
      expect(dark.statusBarBrightness, Brightness.dark);
      expect(dark.systemNavigationBarIconBrightness, Brightness.light);
      const hero = AknTheme.overlayOnHero;
      expect(hero.statusBarIconBrightness, Brightness.light);
      expect(hero.statusBarBrightness, Brightness.dark);
      expect(AknTheme.overlayOnNavy, same(AknTheme.overlayOnHero));
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

  testWidgets('AknHeroPanel re-themes its content on the hero', (tester) async {
    late AknColors inside;
    late bool onHero;
    await tester.pumpWidget(
      MaterialApp(
        theme: AknTheme.light(),
        home: AknHeroPanel(
          child: Builder(
            builder: (context) {
              inside = context.akn;
              onHero = OnHero.isOn(context);
              return const Text('Merhaba');
            },
          ),
        ),
      ),
    );
    expect(inside.ink, const Color(0xFFFFFFFF));
    expect(inside.dim, const Color(0xFFFFFFFF));
    expect(inside.surface, OnHero.glass);
    expect(inside.brandFill, const Color(0xFFFFFFFF));
    expect(onHero, isTrue);
    // The gradient painter sits under the content.
    expect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is HeroBackdropPainter,
      ),
      findsOneWidget,
    );
  });

  testWidgets('buttons inside the hero stay legible', (tester) async {
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
    final filledBg = inner.filledButtonTheme.style!.backgroundColor!.resolve(
      {},
    )!;
    final filledFg = inner.filledButtonTheme.style!.foregroundColor!.resolve(
      {},
    )!;
    expect(contrast(text, AknColors.light.heroEnd), greaterThanOrEqualTo(4.5));
    expect(icon, const Color(0xFFFFFFFF));
    expect(filledBg, const Color(0xFFFFFFFF));
    expect(contrast(filledFg, filledBg), greaterThanOrEqualTo(4.5));
    expect(inner.appBarTheme.systemOverlayStyle, AknTheme.overlayOnHero);
  });

  testWidgets('OnNavy still works (alias of OnHero)', (tester) async {
    late AknColors inside;
    await tester.pumpWidget(
      MaterialApp(
        theme: AknTheme.dark(),
        home: OnNavy(
          child: Builder(
            builder: (context) {
              inside = context.akn;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(inside.ink, const Color(0xFFFFFFFF));
    expect(inside.bg, AknColors.dark.heroEnd);
  });

  testWidgets('date picker uses the orange fill for the selected day', (
    tester,
  ) async {
    final theme = AknTheme.light();
    final day = theme.datePickerTheme.dayBackgroundColor!.resolve({
      WidgetState.selected,
    });
    expect(day, AknColors.light.brandFill);
    final sys = theme.appBarTheme.systemOverlayStyle!;
    expect(sys.statusBarColor, const Color(0x00000000));
    expect(
      SystemUiOverlayStyle.dark.statusBarIconBrightness,
      sys.statusBarIconBrightness,
    );
  });
}

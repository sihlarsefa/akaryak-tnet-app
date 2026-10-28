// AknTheme v3 "Akış": token extensions, Plus Jakarta Sans everywhere (no tabular figures on words),
// the component themes of v3 §4 — superellipse buttons (the primary an orange gradient with a WHITE
// 16 px w700 label and a warm glow), white inputs with a 1.5 px control border and a soft orange
// focus glow, white pill chips that turn ink with a check, orange tab, switch, checkbox and radio
// marks, sheets and dialogs r28 — the badge, navigation and picker themes, status-bar styles, the
// global focus ring (§0.4) and the plate re-theming (`AknTheme.onPlate`, `OnHero`).
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test_helpers.dart';

const _none = <WidgetState>{};
const _pressed = {WidgetState.pressed};
const _disabled = {WidgetState.disabled};
const _selected = {WidgetState.selected};
const _focused = {WidgetState.focused};
const _white = Color(0xFFFFFFFF);
const _transparent = Color(0x00000000);

/// The theme's button background builders ignore their context.
class _NoContext extends Fake implements BuildContext {}

/// What [style] paints behind its label in [states]: the decoration of the
/// gradient box its `backgroundBuilder` returns (null: the plain fill).
ShapeDecoration? _painted(ButtonStyle style, Set<WidgetState> states) {
  final built = style.backgroundBuilder?.call(
    _NoContext(),
    states,
    const SizedBox(),
  );
  return built is DecoratedBox ? built.decoration as ShapeDecoration : null;
}

void main() {
  group('AknTheme', () {
    for (final (name, theme, colors) in [
      ('light', AknTheme.light(), AknColors.light),
      ('dark', AknTheme.dark(), AknColors.dark),
    ]) {
      test('$name carries the token extensions and Plus Jakarta Sans', () {
        final c = theme.extension<AknColors>();
        final t = theme.extension<AknTextStyles>();
        expect(c, colors);
        expect(t, AknTextStyles.from(colors));
        expect(theme.brightness, colors.brightness);
        expect(theme.colorScheme.primary, colors.brand);
        // Decision G: white on the orange primary.
        expect(theme.colorScheme.onPrimary, _white);
        expect(theme.scaffoldBackgroundColor, colors.bg);
        expect(theme.useMaterial3, isTrue);
        for (final s in [
          theme.textTheme.bodyMedium!,
          theme.textTheme.titleLarge!,
          theme.textTheme.labelLarge!,
          theme.textTheme.displaySmall!,
        ]) {
          expect(s.fontFamily, AknFonts.sans);
          // Words keep the face's own figures; tnum is for numeric styles.
          expect(s.fontFeatures ?? const [], isEmpty);
        }
        // No ripples: pressed is a soft fill and a press scale.
        expect(theme.splashFactory, NoSplash.splashFactory);
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
        '$name primary: orange gradient, white 16 px w700, 52 dp, r16 squircle, warm glow',
        () {
          final style = theme.filledButtonTheme.style!;
          expect(style.backgroundColor!.resolve(_none), colors.brandFill);
          expect(style.foregroundColor!.resolve(_none), _white);
          // The white label on the gradient's end colour (owner decision G):
          // 3.77:1.
          expect(
            contrast(
              style.foregroundColor!.resolve(_none)!,
              style.backgroundColor!.resolve(_none)!,
            ),
            greaterThanOrEqualTo(3.5),
          );
          // The gradient is painted inside the shape by the background
          // builder: one step darker while pressed, none when disabled.
          const shape = RoundedSuperellipseBorder(
            borderRadius: AknRadius.button,
          );
          expect(
            _painted(style, _none),
            ShapeDecoration(shape: shape, gradient: colors.buttonGradient),
          );
          expect(
            _painted(style, _pressed),
            ShapeDecoration(
              shape: shape,
              gradient: colors.buttonGradientPressed,
            ),
          );
          expect(_painted(style, _disabled), isNull);
          expect(
            style.backgroundColor!.resolve(_pressed),
            colors.brandFillPressed,
          );
          expect(style.backgroundColor!.resolve(_disabled), colors.surfaceAlt);
          expect(style.foregroundColor!.resolve(_disabled), colors.faint);
          expect(style.minimumSize!.resolve(_none)!.height, 52);
          expect(style.shape!.resolve(_none), shape);
          final label = style.textStyle!.resolve(_none)!;
          expect(label.fontFamily, AknFonts.sans);
          expect(label.fontSize, 16);
          expect(label.height! * 16, closeTo(20, 1e-9));
          expect(label.fontWeight, FontWeight.w700);
          // The warm glow (v3 §3 `button`): a brand-fill shadow that settles
          // while pressed and goes when disabled.
          expect(
            style.shadowColor!.resolve(_none)!.withValues(alpha: 1),
            colors.brandFill,
          );
          expect(style.elevation!.resolve(_none), 3);
          expect(style.elevation!.resolve(_pressed), 1);
          expect(style.elevation!.resolve(_disabled), 0);
          expect(style.splashFactory, NoSplash.splashFactory);
          // The elevated button is the same primary.
          final elevated = theme.elevatedButtonTheme.style!;
          expect(elevated.backgroundColor!.resolve(_none), colors.brandFill);
          expect(_painted(elevated, _none)!.gradient, colors.buttonGradient);
        },
      );

      test(
        '$name secondary and ghost: ink labels, never orange; destructive flat red',
        () {
          final o = theme.outlinedButtonTheme.style!;
          // Light: a white key with a 1.5 px lineStrong 60 % rim; dark: the
          // well, no rim.
          final rest = o.backgroundColor!.resolve(_none);
          expect(rest, colors.isDark ? colors.surfaceAlt : colors.surface);
          if (colors.isDark) {
            expect(o.backgroundColor!.resolve(_pressed), isNot(rest));
          } else {
            expect(o.backgroundColor!.resolve(_pressed), colors.surfaceAlt);
          }
          expect(o.backgroundColor!.resolve(_disabled), colors.surfaceAlt);
          expect(o.foregroundColor!.resolve(_none), colors.ink);
          expect(o.foregroundColor!.resolve(_disabled), colors.faint);
          expect(
            AknTheme.secondaryBorder(colors),
            colors.lineStrong.withValues(alpha: 0.6),
          );
          final side = o.side!.resolve(_none)!;
          if (colors.isDark) {
            expect(side.width, 0);
          } else {
            expect(side.color, AknTheme.secondaryBorder(colors));
            expect(side.width, 1.5);
          }
          expect(
            o.shape!.resolve(_none),
            const RoundedSuperellipseBorder(borderRadius: AknRadius.button),
          );
          expect(o.minimumSize!.resolve(_none)!.height, 52);
          expect(o.textStyle!.resolve(_none)!.fontWeight, FontWeight.w700);
          expect(_painted(o, _none), isNull);
          final danger = AknTheme.secondaryButtonStyle(
            colors,
            AknTextStyles.from(colors),
            danger: true,
          );
          expect(danger.foregroundColor!.resolve(_none), colors.danger.fg);
          expect(danger.side!.resolve(_none), side);

          final g = theme.textButtonTheme.style!;
          expect(g.backgroundColor!.resolve(_none)!.a, 0);
          expect(g.backgroundColor!.resolve(_pressed), colors.surfaceAlt);
          expect(g.foregroundColor!.resolve(_none), colors.ink);
          expect(
            g.shape!.resolve(_none),
            const RoundedSuperellipseBorder(
              borderRadius: AknRadius.buttonSmall,
            ),
          );

          final d = AknTheme.destructiveButtonStyle(
            colors,
            AknTextStyles.from(colors),
          );
          expect(d.backgroundColor!.resolve(_none), colors.dangerFill);
          expect(d.foregroundColor!.resolve(_none), colors.onDangerFill);
          // A flat red key: no gradient, no glow.
          expect(_painted(d, _none), isNull);
          expect(d.elevation!.resolve(_none), 0);
        },
      );

      test('$name focus ring: 3 px brand, 2 px outside (v3 §0.4)', () {
        for (final style in [
          theme.filledButtonTheme.style!,
          theme.outlinedButtonTheme.style!,
          theme.textButtonTheme.style!,
          theme.iconButtonTheme.style!,
        ]) {
          final ring = style.side!.resolve(_focused)!;
          expect(ring.color, colors.brand);
          expect(ring.width, 3);
          // Inner edge 2 px outside the shape, outer edge 5 px.
          expect(ring.strokeInset, closeTo(-2, 1e-9));
          expect(ring.strokeOutset, closeTo(5, 1e-9));
        }
        expect(AknTheme.focusRing(colors).color, colors.brand);
      });

      test('$name app bar: page colour, ink headline title, flat, 52 dp', () {
        final a = theme.appBarTheme;
        expect(a.backgroundColor, colors.bg);
        expect(a.foregroundColor, colors.ink);
        // Flat; `AppScaffold` frosts it when content scrolls under.
        expect(a.elevation, 0);
        expect(a.scrolledUnderElevation, 0);
        expect(a.surfaceTintColor, _transparent);
        expect(a.centerTitle, isFalse);
        expect(a.toolbarHeight, AknTheme.pushedBarHeight);
        expect(AknTheme.pushedBarHeight, 52);
        expect(a.titleSpacing, 20);
        final title = a.titleTextStyle!;
        expect(title, AknTextStyles.from(colors).headline);
        expect(title.fontSize, 17);
        expect(title.fontWeight, FontWeight.w700);
        expect(title.color, colors.ink);
        expect(a.systemOverlayStyle, AknTheme.overlayFor(colors.brightness));
      });

      test(
        '$name inputs: white, 1.5 px control border, 2 px orange focus with a soft glow',
        () {
          final i = theme.inputDecorationTheme;
          expect(i.filled, isTrue);
          expect(
            WidgetStateProperty.resolveAs<Color>(i.fillColor!, _none),
            colors.surface,
          );
          expect(
            WidgetStateProperty.resolveAs<Color>(i.fillColor!, _disabled),
            colors.surfaceAlt,
          );
          // At rest: the full control border (≥ 3:1, contrast_test.dart).
          final enabled = i.enabledBorder! as AknInputBorder;
          expect(enabled.borderSide.color, colors.lineStrong);
          expect(enabled.borderSide.width, 1.5);
          expect(enabled.borderRadius, AknRadius.input);
          expect(enabled.glowWidth, 0);
          expect(i.border, enabled);
          // Focus: 2 px orange and a 4 px warm glow outside it.
          final focused = i.focusedBorder! as AknInputBorder;
          expect(focused.borderSide.color, colors.brand);
          expect(focused.borderSide.width, 2);
          expect(focused.glowWidth, 4);
          expect(focused.glowColor, AknTheme.focusGlow(colors));
          expect(
            AknTheme.focusGlow(colors),
            Color.lerp(colors.brandSoft, colors.brandLine, 0.5),
          );
          final error = i.errorBorder! as AknInputBorder;
          expect(error.borderSide.color, colors.danger.fg);
          expect(error.borderSide.width, 1.5);
          final focusedError = i.focusedErrorBorder! as AknInputBorder;
          expect(focusedError.borderSide.color, colors.danger.fg);
          expect(focusedError.borderSide.width, 2);
          expect(focusedError.glowWidth, 4);
          expect(focusedError.glowColor, AknTheme.errorGlow(colors));
          final disabled = i.disabledBorder! as AknInputBorder;
          expect(disabled.borderSide.color, colors.line);
          // Hints are dim (AA), never faint.
          expect(i.hintStyle!.color, colors.dim);
          expect(i.errorStyle!.color, colors.danger.fg);
          // 52 dp: 22 px line + 15 + 15.
          expect(i.contentPadding!.vertical, 30);
          expect(theme.textSelectionTheme.cursorColor, colors.brand);
        },
      );

      test(
        '$name chips: white pills with a hairline; selected = ink fill, page label, a check',
        () {
          final ch = theme.chipTheme;
          expect(
            (ch.shape! as RoundedRectangleBorder).borderRadius,
            AknRadius.chip,
          );
          expect(AknRadius.chip, AknRadius.pillAll);
          expect(ch.color!.resolve(_none), colors.surface);
          expect(ch.color!.resolve(_selected), colors.ink);
          expect(ch.color!.resolve(_disabled), colors.surfaceAlt);
          expect(ch.selectedColor, colors.ink);
          expect(ch.showCheckmark, isTrue);
          expect(ch.checkmarkColor, colors.bg);
          final rest = WidgetStateProperty.resolveAs<BorderSide?>(
            ch.side,
            _none,
          )!;
          expect(rest.color, colors.line);
          expect(rest.width, 1);
          expect(
            WidgetStateProperty.resolveAs<BorderSide?>(
              ch.side,
              _selected,
            )!.width,
            0,
          );
          final label = ch.labelStyle!;
          expect(
            WidgetStateProperty.resolveAs<Color?>(label.color, _selected),
            colors.bg,
          );
          expect(
            WidgetStateProperty.resolveAs<Color?>(label.color, _none),
            colors.ink,
          );
          expect(
            WidgetStateProperty.resolveAs<Color?>(label.color, _disabled),
            colors.faint,
          );
          expect(label.fontSize, 14);
          expect(label.fontWeight, FontWeight.w600);
        },
      );

      test('$name tabs, switch, checkbox, radio: orange marks (v3 §4)', () {
        final tabs = theme.tabBarTheme;
        expect(tabs.labelColor, colors.ink);
        expect(tabs.unselectedLabelColor, colors.dim);
        expect(tabs.labelStyle!.fontSize, 16);
        expect(tabs.labelStyle!.fontWeight, FontWeight.w700);
        // A 3 px logo-orange bar with round ends that follows the selection
        // on a spring.
        expect(tabs.indicator, AknTabIndicator(color: colors.logo));
        final ind = tabs.indicator! as AknTabIndicator;
        expect(ind.borderSide.color, colors.logo);
        expect(ind.borderSide.width, 3);
        expect(ind.animate, isTrue);
        expect(tabs.indicatorSize, TabBarIndicatorSize.label);
        expect(tabs.dividerColor, colors.line);

        final sw = theme.switchTheme;
        expect(sw.trackColor!.resolve(_selected), colors.logo);
        expect(sw.trackColor!.resolve(_none), colors.lineStrong);
        expect(sw.thumbColor!.resolve(_selected), _white);

        // Checkbox and radio: the orange mark (white check); the control
        // border at rest.
        final cb = theme.checkboxTheme;
        expect(cb.fillColor!.resolve(_selected), colors.brand);
        expect(cb.checkColor!.resolve(_selected), colors.onBrandFill);
        final box = WidgetStateProperty.resolveAs<BorderSide?>(cb.side, _none)!;
        expect(box.color, colors.lineStrong);
        expect(box.width, 1.6);
        final radio = theme.radioTheme.fillColor!;
        expect(radio.resolve(_selected), colors.brand);
        expect(radio.resolve(_none), colors.lineStrong);
      });

      test(
        '$name sheets and dialogs: raised surface, r28 squircle, 40×5 handle',
        () {
          final s = theme.bottomSheetTheme;
          expect(s.backgroundColor, colors.surfaceRaised);
          expect(
            s.shape,
            const RoundedSuperellipseBorder(borderRadius: AknRadius.sheet),
          );
          expect(AknRadius.sheet.topLeft, const Radius.circular(28));
          expect(s.showDragHandle, isTrue);
          expect(s.dragHandleSize, const Size(40, 5));
          expect(s.dragHandleColor, colors.lineStrong.withValues(alpha: 0.5));
          expect(s.modalBarrierColor, colors.scrim);
          final d = theme.dialogTheme;
          expect(d.backgroundColor, colors.surfaceRaised);
          expect(
            d.shape,
            const RoundedSuperellipseBorder(borderRadius: AknRadius.dialog),
          );
          expect(AknRadius.dialog, const BorderRadius.all(Radius.circular(28)));
          // Dialogs float on the raised shadow.
          expect(d.elevation, greaterThan(0));
          expect(d.titleTextStyle!.fontSize, 20);
          expect(d.barrierColor, colors.scrim);
        },
      );

      test('$name inverse surfaces are charcoal, never navy', () {
        final snack = theme.snackBarTheme.backgroundColor!;
        expect(snack, colors.inverse);
        final hsv = HSVColor.fromColor(snack);
        expect(hsv.saturation, lessThan(0.3), reason: '$snack');
        expect(contrast(colors.onInverse, snack), greaterThanOrEqualTo(4.5));
      });

      test('$name badge: a deep-orange pill with white tabular figures', () {
        // v3 §4 "Badges"; the figures' contrast is checked in
        // contrast_test.dart.
        final b = theme.badgeTheme;
        expect(b.backgroundColor, colors.brandFillPressed);
        expect(b.textColor, colors.onBrandFill);
        expect(b.smallSize, 8);
        expect(b.largeSize, 18);
        expect(b.textStyle!.fontSize, 10);
        expect(b.textStyle!.fontWeight, FontWeight.w800);
        expect(b.textStyle!.fontFeatures, AknNumerals.tabular);
        expect(b.textStyle!.color, colors.onBrandFill);
      });

      test(
        '$name navigation bar: soft orange pill, ink active (w700), navInactive rest',
        () {
          final n = theme.navigationBarTheme;
          expect(n.backgroundColor, colors.surfaceRaised);
          expect(n.indicatorColor, colors.brandSoft);
          expect(n.indicatorShape, const StadiumBorder());
          expect(n.iconTheme!.resolve(_selected)!.color, colors.ink);
          expect(n.iconTheme!.resolve(_none)!.color, colors.navInactive);
          final active = n.labelTextStyle!.resolve(_selected)!;
          final rest = n.labelTextStyle!.resolve(_none)!;
          expect(active.color, colors.ink);
          expect(active.fontWeight, FontWeight.w700);
          expect(rest.color, colors.navInactive);
          expect(rest.fontWeight, FontWeight.w600);
          expect(rest.fontSize, 11);
          expect(n.elevation, 0);
        },
      );

      test(
        '$name pickers: deep-orange selection with white figures, Pas today',
        () {
          final dp = theme.datePickerTheme;
          final day = dp.dayBackgroundColor!.resolve(_selected)!;
          final figure = dp.dayForegroundColor!.resolve(_selected)!;
          expect(day, colors.brandFillPressed);
          expect(figure, colors.onBrandFill);
          // The selected day's figure is text: AA on the deep orange.
          expect(contrast(figure, day), greaterThanOrEqualTo(4.5));
          expect(dp.dayBackgroundColor!.resolve(_none), _transparent);
          expect(dp.dayForegroundColor!.resolve(_none), colors.ink);
          expect(dp.todayBorder!.color, colors.brand);
          final today = dp.todayForegroundColor!.resolve(_none)!;
          expect(today, colors.brandInk);
          expect(
            contrast(today, dp.backgroundColor!),
            greaterThanOrEqualTo(4.5),
          );
          expect(dp.rangeSelectionBackgroundColor, colors.brandSoft);
          // "Seç" is the orange (Pas) action.
          expect(
            dp.confirmButtonStyle!.foregroundColor!.resolve(_none),
            colors.brandInk,
          );
          expect(theme.timePickerTheme.dialHandColor, colors.brandFillPressed);
        },
      );
    }

    test('of(brightness) picks the matching theme', () {
      expect(AknTheme.of(Brightness.dark).brightness, Brightness.dark);
      expect(AknTheme.of(Brightness.light).brightness, Brightness.light);
    });

    test(
      'system bars: pages follow the theme; the orange band has light icons',
      () {
        final light = AknTheme.overlayFor(Brightness.light);
        expect(light.statusBarIconBrightness, Brightness.dark);
        expect(light.statusBarBrightness, Brightness.light);
        expect(light.systemNavigationBarIconBrightness, Brightness.dark);
        final dark = AknTheme.overlayFor(Brightness.dark);
        expect(dark.statusBarIconBrightness, Brightness.light);
        expect(dark.statusBarBrightness, Brightness.dark);
        expect(dark.systemNavigationBarIconBrightness, Brightness.light);
        // Decision G: white content on the orange band, light status icons
        // on the homes and the login band.
        const hero = AknTheme.overlayOnHero;
        expect(hero.statusBarIconBrightness, Brightness.light);
        expect(hero.statusBarBrightness, Brightness.dark);
        expect(hero.statusBarColor, _transparent);
        expect(AknTheme.overlayOnNavy, same(AknTheme.overlayOnHero));
        final night = AknTheme.overlayOnPlate(Brightness.dark);
        expect(night.statusBarIconBrightness, Brightness.light);
        expect(night.systemNavigationBarIconBrightness, Brightness.light);
        expect(AknTheme.overlayOnBand(Brightness.dark), night);
        expect(
          AknTheme.overlayOnPlate(
            Brightness.light,
          ).systemNavigationBarIconBrightness,
          Brightness.dark,
        );
      },
    );

    test('app-bar titles: pushed = headline, root = display', () {
      final t = AknTextStyles.from(AknColors.light);
      expect(AknTheme.appBarTitle(t), t.headline);
      expect(AknTheme.rootAppBarTitle(t), t.display);
      expect(AknTheme.rootBarHeight, 60);
      expect(AknTheme.homeBarHeight, 62);
    });
  });

  group('plate re-theming', () {
    for (final (name, theme, colors) in [
      ('light', AknTheme.light(), AknColors.light),
      ('dark', AknTheme.dark(), AknColors.dark),
    ]) {
      test('$name AknTheme.onPlate prints in ink on the white card', () {
        final p = AknTheme.onPlate(theme);
        final c = p.extension<AknColors>()!;
        final t = p.extension<AknTextStyles>()!;
        expect(c, colors.plateInk());
        expect(t.body.color, colors.onPlate);
        expect(t.plateFigure.color, colors.onPlate);
        // Secondary text stays dim on the white card.
        expect(t.bodySmall.color, colors.dim);
        expect(p.textTheme.bodyMedium!.color, colors.onPlate);
        // The card is white: stock controls keep their normal looks (the
        // primary stays the orange gradient with a white label).
        final key = p.filledButtonTheme.style!;
        expect(key.backgroundColor!.resolve(_none), colors.brandFill);
        expect(key.foregroundColor!.resolve(_none), colors.onBrandFill);
        expect(_painted(key, _none)!.gradient, colors.buttonGradient);
        expect(
          p.outlinedButtonTheme.style!.foregroundColor!.resolve(_none),
          colors.ink,
        );
        expect(p.dividerColor, colors.plateLine);
        // Idempotent.
        final again = AknTheme.onPlate(p);
        expect(again.extension<AknColors>(), c);
        expect(again.extension<AknTextStyles>(), t);
      });
    }

    test('withPalette swaps the colours and keeps the type sizes', () {
      final theme = AknTheme.light();
      final plate = AknColors.light.plateInk();
      final swapped = AknTheme.withPalette(theme, plate);
      expect(swapped.extension<AknColors>(), plate);
      final t = swapped.extension<AknTextStyles>()!;
      expect(t.display.color, plate.ink);
      expect(t.display.fontSize, 28);
      expect(t.plateFigure.fontSize, 46);
      // Every other extension survives.
      expect(swapped.extensions.length, theme.extensions.length);
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
    late AknTextStyles text;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            seen = context.akn;
            text = context.aknText;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen.brand, AknColors.light.brand);
    expect(text.body.fontFamily, AknFonts.sans);
  });

  // OnHero / AknHeroPanel (cards.dart) re-theme their subtree with the plate palette (v3 §2, §4).
  testWidgets('AknHeroPanel prints its content in plate ink', (tester) async {
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
    expect(inside.ink, AknColors.light.onPlate);
    expect(inside.dim, AknColors.light.dim);
    expect(inside.surface, AknColors.light.plate);
    expect(inside.isPlatePalette, isTrue);
    expect(onHero, isTrue);
    expect(OnHero.palette(AknColors.light), AknColors.light.plateInk());
    // The card itself: the G decoration (white + warm wash, border, r26,
    // the plate shadow).
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(AknPlate),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect(box.decoration, AknColors.light.plateDecoration());
  });

  testWidgets('buttons inside the plate stay legible', (tester) async {
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
    // The card is white (decision G); its warm wash is #FFF4EE at the top.
    const plate = Color(0xFFFFFFFF);
    const tint = Color(0xFFFFF4EE);
    expect(AknColors.light.plateTint, tint);
    final text = inner.textButtonTheme.style!.foregroundColor!.resolve({})!;
    final icon =
        inner.iconButtonTheme.style?.foregroundColor?.resolve({}) ??
        inner.extension<AknColors>()!.ink;
    final filledBg = inner.filledButtonTheme.style!.backgroundColor!.resolve(
      {},
    )!;
    final filledFg = inner.filledButtonTheme.style!.foregroundColor!.resolve(
      {},
    )!;
    expect(contrast(text, plate), greaterThanOrEqualTo(4.5));
    expect(contrast(text, tint), greaterThanOrEqualTo(4.5));
    expect(contrast(icon, plate), greaterThanOrEqualTo(4.5));
    // The white 16 px w700 primary label (owner decision G).
    expect(contrast(filledFg, filledBg), greaterThanOrEqualTo(3.5));
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
    expect(inside.ink, AknColors.dark.onPlate);
    expect(inside.bg, AknColors.dark.plate);
  });

  testWidgets('the app bar status bar is transparent with dark icons', (
    tester,
  ) async {
    final theme = AknTheme.light();
    final sys = theme.appBarTheme.systemOverlayStyle!;
    expect(sys.statusBarColor, _transparent);
    expect(
      SystemUiOverlayStyle.dark.statusBarIconBrightness,
      sys.statusBarIconBrightness,
    );
  });
}

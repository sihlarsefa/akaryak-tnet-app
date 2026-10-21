// AknTheme v2 "Turuncu Plaka": token extensions, Mona Sans everywhere, the component themes of
// §6.5 (buttons: orange primary with a BLACK label), §6.10 (white inputs), §6.11 (chips, tabs,
// switches), §6.21 (sheets, dialogs), badge and navigation themes, status-bar styles, the global
// focus ring (§12) and the plate re-theming (`AknTheme.onPlate`, `OnHero`).
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

void main() {
  group('AknTheme', () {
    for (final (name, theme, colors) in [
      ('light', AknTheme.light(), AknColors.light),
      ('dark', AknTheme.dark(), AknColors.dark),
    ]) {
      test('$name carries the token extensions and Mona Sans', () {
        final c = theme.extension<AknColors>();
        final t = theme.extension<AknTextStyles>();
        expect(c, colors);
        expect(t, AknTextStyles.from(colors));
        expect(theme.brightness, colors.brightness);
        expect(theme.colorScheme.primary, colors.brand);
        // Decision G: white on the orange primary.
        expect(theme.colorScheme.onPrimary, const Color(0xFFFFFFFF));
        expect(theme.scaffoldBackgroundColor, colors.bg);
        expect(theme.useMaterial3, isTrue);
        for (final s in [
          theme.textTheme.bodyMedium!,
          theme.textTheme.titleLarge!,
          theme.textTheme.labelLarge!,
          theme.textTheme.displaySmall!,
        ]) {
          expect(s.fontFamily, AknFonts.sans);
          expect(s.fontFeatures ?? const [], isEmpty);
        }
        // No ripples: pressed is a flat fill.
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

      test('$name primary: orange gradient, white 17 px w700, 52 dp, r12', () {
        final style = theme.filledButtonTheme.style!;
        expect(style.backgroundColor!.resolve(_none), colors.brandFill);
        expect(style.foregroundColor!.resolve(_none), const Color(0xFFFFFFFF));
        // The 17 px w700 label on the gradient's end colour (owner decision
        // G, like F2GO): 3.58:1.
        expect(
          contrast(
            style.foregroundColor!.resolve(_none)!,
            style.backgroundColor!.resolve(_none)!,
          ),
          greaterThanOrEqualTo(3.5),
        );
        // The gradient is painted by the background builder.
        expect(style.backgroundBuilder, isNotNull);
        expect(
          style.backgroundColor!.resolve(_pressed),
          colors.brandFillPressed,
        );
        expect(style.backgroundColor!.resolve(_disabled), colors.surfaceAlt);
        expect(style.foregroundColor!.resolve(_disabled), colors.faint);
        expect(style.minimumSize!.resolve(_none)!.height, 52);
        final shape = style.shape!.resolve(_none)! as RoundedRectangleBorder;
        expect(shape.borderRadius, AknRadius.button);
        final label = style.textStyle!.resolve(_none)!;
        expect(label.fontFamily, AknFonts.sans);
        expect(label.fontSize, 17);
        expect(label.fontWeight, FontWeight.w700);
        expect(style.elevation!.resolve(_none), 0);
        expect(style.splashFactory, NoSplash.splashFactory);
        // The elevated button is the same primary.
        expect(
          theme.elevatedButtonTheme.style!.backgroundColor!.resolve(_none),
          colors.brandFill,
        );
      });

      test('$name secondary and ghost: ink on white / none, never orange', () {
        final o = theme.outlinedButtonTheme.style!;
        expect(o.backgroundColor!.resolve(_none), colors.surface);
        expect(o.backgroundColor!.resolve(_pressed), colors.surfaceAlt);
        expect(o.foregroundColor!.resolve(_none), colors.ink);
        final side = o.side!.resolve(_none)!;
        expect(side.color, colors.lineStrong);
        expect(side.width, 1.5);
        final danger = AknTheme.secondaryButtonStyle(
          colors,
          AknTextStyles.from(colors),
          danger: true,
        );
        expect(danger.foregroundColor!.resolve(_none), colors.danger.fg);
        expect(danger.side!.resolve(_none)!.color, colors.lineStrong);

        final g = theme.textButtonTheme.style!;
        expect(g.backgroundColor!.resolve(_none)!.a, 0);
        expect(g.backgroundColor!.resolve(_pressed), colors.surfaceAlt);
        expect(g.foregroundColor!.resolve(_none), colors.ink);
        expect(
          (g.shape!.resolve(_none)! as RoundedRectangleBorder).borderRadius,
          AknRadius.buttonSmall,
        );

        final d = AknTheme.destructiveButtonStyle(
          colors,
          AknTextStyles.from(colors),
        );
        expect(d.backgroundColor!.resolve(_none), colors.dangerFill);
        expect(d.foregroundColor!.resolve(_none), colors.onDangerFill);
      });

      test('$name focus ring: 3 px brand, 2 px outside (§12)', () {
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
        expect(a.elevation, 0);
        expect(a.scrolledUnderElevation, 0);
        expect(a.centerTitle, isFalse);
        expect(a.toolbarHeight, AknTheme.pushedBarHeight);
        expect(a.titleSpacing, 20);
        final title = a.titleTextStyle!;
        expect(title.fontSize, 17);
        expect(title.fontWeight, FontWeight.w600);
        expect(title.color, colors.ink);
        expect(a.systemOverlayStyle, AknTheme.overlayFor(colors.brightness));
      });

      test('$name inputs: white, 1 px control border, 2 px orange focus', () {
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
        final enabled = i.enabledBorder! as OutlineInputBorder;
        expect(enabled.borderSide.color, colors.lineStrong);
        expect(enabled.borderSide.width, 1);
        expect(enabled.borderRadius, AknRadius.input);
        final focused = i.focusedBorder! as OutlineInputBorder;
        expect(focused.borderSide.color, colors.brand);
        expect(focused.borderSide.width, 2);
        final error = i.errorBorder! as OutlineInputBorder;
        expect(error.borderSide.color, colors.danger.fg);
        expect(error.borderSide.width, 2);
        final disabled = i.disabledBorder! as OutlineInputBorder;
        expect(disabled.borderSide.color, colors.line);
        // Hints are dim (AA), never faint.
        expect(i.hintStyle!.color, colors.dim);
        expect(i.errorStyle!.color, colors.danger.fg);
        // 52 dp: 22 px line + 15 + 15.
        expect(i.contentPadding!.vertical, 30);
        expect(theme.textSelectionTheme.cursorColor, colors.brand);
      });

      test('$name chips: Beton r10; selected = ink fill, page label', () {
        final ch = theme.chipTheme;
        expect(
          (ch.shape! as RoundedRectangleBorder).borderRadius,
          AknRadius.chip,
        );
        expect(ch.color!.resolve(_none), colors.surfaceAlt);
        expect(ch.color!.resolve(_selected), colors.ink);
        expect(ch.selectedColor, colors.ink);
        expect(ch.showCheckmark, isFalse);
        final label = ch.labelStyle!;
        expect(
          WidgetStateProperty.resolveAs<Color?>(label.color, _selected),
          colors.bg,
        );
        expect(
          WidgetStateProperty.resolveAs<Color?>(label.color, _none),
          colors.ink,
        );
        expect(label.fontWeight, FontWeight.w600);
      });

      test('$name tabs, switch, checkbox, radio (§6.11)', () {
        final tabs = theme.tabBarTheme;
        expect(tabs.labelColor, colors.ink);
        expect(tabs.unselectedLabelColor, colors.dim);
        expect(tabs.labelStyle!.fontSize, 16);
        final ind = tabs.indicator! as UnderlineTabIndicator;
        expect(ind.borderSide.color, colors.logo);
        expect(ind.borderSide.width, 3);
        expect(tabs.dividerColor, colors.line);

        final sw = theme.switchTheme;
        expect(sw.trackColor!.resolve(_selected), colors.logo);
        expect(sw.trackColor!.resolve(_none), colors.lineStrong);
        expect(sw.thumbColor!.resolve(_selected), const Color(0xFFFFFFFF));

        final cb = theme.checkboxTheme;
        expect(cb.fillColor!.resolve(_selected), colors.ink);
        expect(cb.checkColor!.resolve(_selected), colors.bg);
        expect(theme.radioTheme.fillColor!.resolve(_selected), colors.ink);
      });

      test('$name sheets and dialogs: raised surface, r20, 36×4 handle', () {
        final s = theme.bottomSheetTheme;
        expect(s.backgroundColor, colors.surfaceRaised);
        expect(
          (s.shape! as RoundedRectangleBorder).borderRadius,
          AknRadius.sheet,
        );
        expect(s.dragHandleSize, const Size(36, 4));
        expect(s.dragHandleColor, colors.lineStrong);
        expect(s.modalBarrierColor, colors.scrim);
        expect(theme.dialogTheme.backgroundColor, colors.surfaceRaised);
        expect(
          (theme.dialogTheme.shape! as RoundedRectangleBorder).borderRadius,
          AknRadius.dialog,
        );
        expect(theme.dialogTheme.titleTextStyle!.fontSize, 20);
      });

      test('$name inverse surfaces are charcoal, never navy', () {
        final snack = theme.snackBarTheme.backgroundColor!;
        expect(snack, colors.inverse);
        final hsv = HSVColor.fromColor(snack);
        expect(hsv.saturation, lessThan(0.3), reason: '$snack');
        expect(contrast(colors.onInverse, snack), greaterThanOrEqualTo(4.5));
      });

      test(
        '$name badge: ink pill with page-coloured digits (red = danger)',
        () {
          final b = theme.badgeTheme;
          expect(b.backgroundColor, colors.ink);
          expect(b.textColor, colors.bg);
          expect(b.largeSize, 18);
          expect(b.textStyle!.fontSize, 11);
          expect(b.textStyle!.fontWeight, FontWeight.w700);
        },
      );

      test('$name navigation bar: no pill, ink active, navInactive rest', () {
        final n = theme.navigationBarTheme;
        expect(n.indicatorColor!.a, 0);
        expect(n.iconTheme!.resolve(_selected)!.color, colors.ink);
        expect(n.iconTheme!.resolve(_none)!.color, colors.navInactive);
        expect(
          n.labelTextStyle!.resolve(_selected)!.fontWeight,
          FontWeight.w600,
        );
        expect(n.labelTextStyle!.resolve(_none)!.fontSize, 11);
        expect(n.elevation, 0);
      });

      test('$name pickers: ink selection, no orange fills', () {
        final dp = theme.datePickerTheme;
        expect(dp.dayBackgroundColor!.resolve(_selected), colors.ink);
        expect(dp.dayForegroundColor!.resolve(_selected), colors.bg);
        expect(dp.todayBorder!.color, colors.ink);
        final tp = theme.timePickerTheme;
        expect(tp.dialHandColor, colors.ink);
      });
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
        expect(hero.statusBarColor, const Color(0x00000000));
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
        expect(key.backgroundBuilder, isNotNull);
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
      expect(t.display.fontSize, 30);
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

  // OnHero / AknHeroPanel (cards.dart) re-theme their subtree with the plate palette (§2.2, §6.28).
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
    // The card itself: the G decoration (white + orange tint, border, r22).
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
    // The card is white (decision G); its tint is #FFEDE2 at the top.
    const plate = Color(0xFFFFFFFF);
    const tint = Color(0xFFFFEDE2);
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
    // The white 17 px w700 primary label (owner decision G).
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
    expect(sys.statusBarColor, const Color(0x00000000));
    expect(
      SystemUiOverlayStyle.dark.statusBarIconBrightness,
      sys.statusBarIconBrightness,
    );
  });
}

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';

import 'motion.dart';
import 'tokens.dart';
import 'typography.dart';

/// Light and dark [ThemeData] for AkaryakıtNet — design v3 "Akış".
///
/// ```dart
/// MaterialApp.router(
///   theme: AknTheme.light(),
///   darkTheme: AknTheme.dark(),
///   themeMode: themeMode, // Sistem / Açık / Koyu
/// )
/// ```
///
/// Stock Material widgets pick up the identity through the component themes:
/// the off-white page with white cards, superellipse buttons (the primary an
/// orange gradient with a white label and a warm glow), white inputs with a
/// 1.5 px control border that turns orange and glows on focus, white pill
/// chips that turn ink (with a check) when selected, tabs whose orange bar
/// follows the selection on a spring ([AknTabIndicator]), orange switches,
/// checkboxes, radios, sliders and progress, sheets and dialogs on the raised
/// surface (r28) with soft shadows, inverse tooltips and snack bars — no
/// ripples, no tints, never blue or purple. AkaryakıtNet widgets read tokens
/// with `context.akn` and `context.aknText`. Content on the plate is
/// re-themed by [AknTheme.onPlate], content on the band by [AknTheme.onBand].
abstract final class AknTheme {
  static ThemeData light() => build(AknColors.light);

  static ThemeData dark() => build(AknColors.dark);

  static ThemeData of(Brightness brightness) =>
      brightness == Brightness.dark ? dark() : light();

  /// Home bar (`AknHomeHeader`) height (§6.2).
  static const double homeBarHeight = 62;

  /// Root tab pages: app bar height with a `display` title (§6.1).
  static const double rootBarHeight = 60;

  /// Pushed pages: app bar height with a `headline` title (§6.1).
  static const double pushedBarHeight = 52;

  /// System bars over content on `bg` / `surface`: dark icons on light pages
  /// (iOS `statusBarBrightness: light`), light icons in dark mode. The
  /// navigation bar stays transparent (edge-to-edge) so the bottom bar or
  /// page shows through, with matching icons.
  static SystemUiOverlayStyle overlayFor(Brightness brightness) =>
      brightness == Brightness.dark
      ? const SystemUiOverlayStyle(
          statusBarColor: Color(0x00000000),
          statusBarBrightness: Brightness.dark,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Color(0x00000000),
          systemNavigationBarDividerColor: Color(0x00000000),
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarContrastEnforced: false,
        )
      : const SystemUiOverlayStyle(
          statusBarColor: Color(0x00000000),
          statusBarBrightness: Brightness.light,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: Color(0x00000000),
          systemNavigationBarDividerColor: Color(0x00000000),
          systemNavigationBarIconBrightness: Brightness.dark,
          systemNavigationBarContrastEnforced: false,
        );

  /// Status bar over the orange header band (owner decision G: every home
  /// and the login band): **light** icons on the orange gradient. The
  /// navigation bar sits over the page below the band.
  static const SystemUiOverlayStyle overlayOnHero = SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0x00000000),
    systemNavigationBarDividerColor: Color(0x00000000),
    systemNavigationBarIconBrightness: Brightness.dark,
    systemNavigationBarContrastEnforced: false,
  );

  /// Deprecated alias of [overlayOnHero] (the navy header is gone).
  static const SystemUiOverlayStyle overlayOnNavy = overlayOnHero;

  /// [overlayOnHero] for a page of [pageBrightness]: light status icons on
  /// the orange band in both themes; navigation-bar icons follow the page
  /// under the band (light icons over the dark page).
  static SystemUiOverlayStyle overlayOnPlate(Brightness pageBrightness) =>
      overlayOnHero.copyWith(
        systemNavigationBarIconBrightness: pageBrightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
      );

  /// Same as [overlayOnPlate]: the status bar over the header band.
  static SystemUiOverlayStyle overlayOnBand(Brightness pageBrightness) =>
      overlayOnPlate(pageBrightness);

  /// The keyboard / switch-access focus ring (§12): 3 px [AknColors.brand]
  /// drawn 2 px outside the control's shape. Use it as the `side` of an
  /// [OutlinedBorder] or a [BoxBorder] (it does not change layout).
  static BorderSide focusRing(AknColors c) =>
      BorderSide(color: c.brand, width: 3, strokeAlign: _focusRingAlign);

  /// strokeAlign that puts a 3 px stroke 2 px outside the edge:
  /// outset = 3 · (1 + a) / 2 = 5, inset = 3 · (1 − (1 + a) / 2) = −2.
  static const double _focusRingAlign = 7 / 3;

  /// The soft halo around a focused field (v3 §4 Inputs): halfway between
  /// `brandSoft` and `brandLine` — a warm 4 px glow outside the 2 px orange
  /// border (#FFE4D6; dark #462516).
  static Color focusGlow(AknColors c) =>
      Color.lerp(c.brandSoft, c.brandLine, 0.5)!;

  /// The halo around a focused field in error: the danger well and its line.
  static Color errorGlow(AknColors c) =>
      Color.lerp(c.danger.bg, c.danger.line, 0.5)!;

  /// The field borders of v3 (§4 Inputs) for [c]: at rest 1.5 px
  /// `lineStrong` (3.44:1), disabled 1.5 px `line`, focused 2 px orange with
  /// the 4 px [focusGlow], error 1.5 px danger (focused: 2 px with the
  /// [errorGlow]); radius 14. The input decorator animates between them
  /// (~170 ms): the border colours and the glow blooms. [snap] (reduce
  /// motion) makes every change jump.
  static ({
    AknInputBorder rest,
    AknInputBorder disabled,
    AknInputBorder focused,
    AknInputBorder error,
    AknInputBorder focusedError,
  })
  inputBorders(AknColors c, {bool snap = false}) {
    AknInputBorder border(Color color, double width, [Color? glow]) =>
        AknInputBorder(
          borderSide: BorderSide(color: color, width: width),
          glowColor: glow ?? const Color(0x00000000),
          glowWidth: glow == null ? 0 : 4,
          snap: snap,
        );
    return (
      rest: border(c.lineStrong, 1.5),
      disabled: border(c.line, 1.5),
      focused: border(c.brand, 2, focusGlow(c)),
      error: border(c.danger.fg, 1.5),
      focusedError: border(c.danger.fg, 2, errorGlow(c)),
    );
  }

  static bool _disabled(Set<WidgetState> s) => s.contains(WidgetState.disabled);
  static bool _pressed(Set<WidgetState> s) => s.contains(WidgetState.pressed);
  static bool _selected(Set<WidgetState> s) => s.contains(WidgetState.selected);
  static bool _focused(Set<WidgetState> s) => s.contains(WidgetState.focused);

  /// A superellipse ("squircle") shape of radius [r] (v3 §3).
  static OutlinedBorder _squircle(BorderRadius r) =>
      RoundedSuperellipseBorder(borderRadius: r);

  /// The primary label (v3 §4): `button` 16/20 w700, white on the orange.
  static TextStyle primaryLabel(AknTextStyles t) =>
      t.button.copyWith(fontWeight: FontWeight.w700);

  /// The primary button (§4 Buttons, owner decision G): the orange gradient
  /// [AknColors.buttonGradient] (#FF7B35 → #E5530A) with a WHITE 16 px w700
  /// label and a warm orange glow under it (it settles while pressed, none
  /// when disabled); pressed [AknColors.buttonGradientPressed]; disabled
  /// `surfaceAlt` with a faint label. No ripple, superellipse [radius] (r16),
  /// 52 high. The gradient is painted by `backgroundBuilder` inside the shape
  /// (stock buttons do not clip it), so every `FilledButton` /
  /// `ElevatedButton` picks it up from the theme.
  static ButtonStyle primaryButtonStyle(
    AknColors c,
    AknTextStyles t, {
    BorderRadius radius = AknRadius.button,
  }) => ButtonStyle(
    textStyle: WidgetStatePropertyAll<TextStyle>(primaryLabel(t)),
    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
    minimumSize: const WidgetStatePropertyAll<Size>(Size(64, 52)),
    iconSize: const WidgetStatePropertyAll<double>(20),
    // The warm glow (§3 `button`): an orange elevation shadow that
    // settles while pressed.
    elevation: WidgetStateProperty.resolveWith(
      (s) => _disabled(s)
          ? 0
          : _pressed(s)
          ? 1
          : 3,
    ),
    shadowColor: WidgetStatePropertyAll<Color>(
      c.brandFill.withValues(alpha: c.isDark ? 0.6 : 1),
    ),
    surfaceTintColor: const WidgetStatePropertyAll<Color>(Color(0x00000000)),
    shape: WidgetStatePropertyAll<OutlinedBorder>(_squircle(radius)),
    backgroundColor: WidgetStateProperty.resolveWith(
      (s) => _disabled(s)
          ? c.surfaceAlt
          : _pressed(s)
          ? c.brandFillPressed
          : c.brandFill,
    ),
    backgroundBuilder: (context, states, child) => _disabled(states)
        ? (child ?? const SizedBox.shrink())
        : DecoratedBox(
            decoration: ShapeDecoration(
              shape: _squircle(radius),
              gradient: _pressed(states)
                  ? c.buttonGradientPressed
                  : c.buttonGradient,
            ),
            child: child,
          ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (s) => _disabled(s) ? c.faint : c.onBrandFill,
    ),
    iconColor: WidgetStateProperty.resolveWith(
      (s) => _disabled(s) ? c.faint : c.onBrandFill,
    ),
    overlayColor: const WidgetStatePropertyAll<Color>(Color(0x00000000)),
    side: WidgetStateProperty.resolveWith(
      (s) => _focused(s) ? focusRing(c) : null,
    ),
    splashFactory: NoSplash.splashFactory,
    animationDuration: AknMotion.press,
  );

  /// The secondary / outline button (§4 Buttons): white `surface` with a
  /// 1.5 px `lineStrong` 60 % border and an ink label (dark: a `surfaceAlt`
  /// fill, no border); pressed `surfaceAlt`. [danger] paints the label in the
  /// danger tone (Reddet).
  static ButtonStyle secondaryButtonStyle(
    AknColors c,
    AknTextStyles t, {
    bool danger = false,
  }) => ButtonStyle(
    textStyle: WidgetStatePropertyAll<TextStyle>(primaryLabel(t)),
    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    ),
    minimumSize: const WidgetStatePropertyAll<Size>(Size(64, 52)),
    iconSize: const WidgetStatePropertyAll<double>(20),
    elevation: const WidgetStatePropertyAll<double>(0),
    shadowColor: const WidgetStatePropertyAll<Color>(Color(0x00000000)),
    surfaceTintColor: const WidgetStatePropertyAll<Color>(Color(0x00000000)),
    shape: WidgetStatePropertyAll<OutlinedBorder>(_squircle(AknRadius.button)),
    backgroundColor: WidgetStateProperty.resolveWith(
      (s) => _disabled(s)
          ? c.surfaceAlt
          : _pressed(s)
          ? (c.isDark ? _pressedOn(c, c.surfaceAlt) : c.surfaceAlt)
          : (c.isDark ? c.surfaceAlt : c.surface),
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (s) => _disabled(s)
          ? c.faint
          : danger
          ? c.danger.fg
          : c.ink,
    ),
    iconColor: WidgetStateProperty.resolveWith(
      (s) => _disabled(s)
          ? c.faint
          : danger
          ? c.danger.fg
          : c.ink,
    ),
    side: WidgetStateProperty.resolveWith(
      (s) => _focused(s)
          ? focusRing(c)
          : _disabled(s) || c.isDark
          ? const BorderSide(color: Color(0x00000000), width: 0)
          : BorderSide(color: secondaryBorder(c), width: 1.5),
    ),
    overlayColor: const WidgetStatePropertyAll<Color>(Color(0x00000000)),
    splashFactory: NoSplash.splashFactory,
    animationDuration: AknMotion.press,
  );

  /// The border of a secondary / outline button: `lineStrong` at 60 %.
  static Color secondaryBorder(AknColors c) =>
      c.lineStrong.withValues(alpha: 0.6);

  /// A pressed fill on [base]: ink at 8 % over it (dark surfaces).
  static Color _pressedOn(AknColors c, Color base) =>
      Color.alphaBlend(c.ink.withValues(alpha: 0.08), base);

  /// The ghost (tertiary) button (§4 Buttons): no fill, an ink label;
  /// pressed `surfaceAlt` (superellipse r12). Never orange, never blue.
  static ButtonStyle ghostButtonStyle(AknColors c, AknTextStyles t) =>
      ButtonStyle(
        textStyle: WidgetStatePropertyAll<TextStyle>(primaryLabel(t)),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        minimumSize: const WidgetStatePropertyAll<Size>(Size(48, 44)),
        iconSize: const WidgetStatePropertyAll<double>(20),
        elevation: const WidgetStatePropertyAll<double>(0),
        shape: WidgetStatePropertyAll<OutlinedBorder>(
          _squircle(AknRadius.buttonSmall),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => _pressed(s) && !_disabled(s)
              ? c.surfaceAlt
              : const Color(0x00000000),
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => _disabled(s) ? c.faint : c.ink,
        ),
        iconColor: WidgetStateProperty.resolveWith(
          (s) => _disabled(s) ? c.faint : c.ink,
        ),
        side: WidgetStateProperty.resolveWith(
          (s) => _focused(s) ? focusRing(c) : null,
        ),
        overlayColor: const WidgetStatePropertyAll<Color>(Color(0x00000000)),
        splashFactory: NoSplash.splashFactory,
        animationDuration: AknMotion.press,
      );

  /// The destructive confirm button of a sheet (§6.21): a flat `dangerFill`
  /// with a white label (no glow); pressed 8 % darker.
  static ButtonStyle destructiveButtonStyle(AknColors c, AknTextStyles t) =>
      primaryButtonStyle(c, t).copyWith(
        elevation: const WidgetStatePropertyAll<double>(0),
        backgroundBuilder: (context, states, child) =>
            child ?? const SizedBox.shrink(),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => _disabled(s)
              ? c.surfaceAlt
              : _pressed(s)
              ? Color.alphaBlend(const Color(0x14000000), c.dangerFill)
              : c.dangerFill,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => _disabled(s) ? c.faint : c.onDangerFill,
        ),
        iconColor: WidgetStateProperty.resolveWith(
          (s) => _disabled(s) ? c.faint : c.onDangerFill,
        ),
      );

  static ThemeData build(AknColors c) {
    final t = AknTextStyles.from(c);
    final dark = c.isDark;
    const transparent = Color(0x00000000);
    // Raised things (dialogs, menus, snack bars) cast a soft ink shadow
    // (dark: black).
    final raisedShadow = dark ? const Color(0xFF000000) : c.ink;

    final scheme = ColorScheme(
      brightness: c.brightness,
      // Marks: focus, progress, selection handles, switches, checkboxes.
      primary: c.brand,
      onPrimary: c.onBrandFill,
      primaryContainer: c.brandSoft,
      onPrimaryContainer: c.brandInk,
      // Chip and segment selection is ink: never blue, never purple.
      secondary: c.ink,
      onSecondary: c.bg,
      secondaryContainer: c.surfaceAlt,
      onSecondaryContainer: c.ink,
      tertiary: c.info.fg,
      onTertiary: c.bg,
      tertiaryContainer: c.surfaceAlt,
      onTertiaryContainer: c.ink,
      error: c.danger.fg,
      onError: c.onDangerFill,
      errorContainer: c.danger.bg,
      onErrorContainer: c.danger.fg,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.dim,
      surfaceDim: c.bg,
      surfaceBright: c.surfaceRaised,
      surfaceContainerLowest: c.bg,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surfaceAlt,
      surfaceContainerHigh: c.surfaceAlt,
      surfaceContainerHighest: dark ? c.surfaceRaised : c.surfaceAlt,
      outline: c.lineStrong,
      outlineVariant: c.line,
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      inverseSurface: c.inverse,
      onInverseSurface: c.onInverse,
      inversePrimary: c.brand,
      surfaceTint: transparent,
    );

    final primary = primaryButtonStyle(c, t);
    final secondary = secondaryButtonStyle(c, t);
    final ghost = ghostButtonStyle(c, t);
    // The confirm action of pickers and dialogs: a ghost with an orange
    // ("your move") label.
    final confirm = ghost.copyWith(
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => _disabled(s) ? c.faint : c.brandInk,
      ),
    );

    // White inputs (§4 Inputs): 1.5 px control border, r14; focus = 2 px
    // orange + a soft 4 px glow; error = danger; `surfaceAlt` when disabled.
    final borders = inputBorders(c);
    final value = t.body.copyWith(fontSize: 16, height: 22 / 16);
    final inputs = InputDecorationThemeData(
      filled: true,
      fillColor: WidgetStateColor.resolveWith(
        (s) => _disabled(s) ? c.surfaceAlt : c.surface,
      ),
      hoverColor: transparent,
      focusColor: transparent,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: borders.rest,
      enabledBorder: borders.rest,
      disabledBorder: borders.disabled,
      focusedBorder: borders.focused,
      errorBorder: borders.error,
      focusedErrorBorder: borders.focusedError,
      labelStyle: t.label.copyWith(color: c.ink),
      floatingLabelStyle: WidgetStateTextStyle.resolveWith((s) {
        if (s.contains(WidgetState.error)) {
          return t.label.copyWith(color: c.danger.fg);
        }
        if (_disabled(s)) return t.label.copyWith(color: c.faint);
        return t.label.copyWith(color: c.ink);
      }),
      hintStyle: value.copyWith(color: c.dim),
      helperStyle: t.label.copyWith(color: c.dim, fontWeight: FontWeight.w500),
      helperMaxLines: 3,
      errorStyle: t.label.copyWith(color: c.danger.fg),
      errorMaxLines: 3,
      prefixIconColor: WidgetStateColor.resolveWith(
        (s) => _disabled(s)
            ? c.faint
            : _focused(s)
            ? c.ink
            : c.dim,
      ),
      suffixIconColor: WidgetStateColor.resolveWith(
        (s) => _disabled(s)
            ? c.faint
            : _focused(s)
            ? c.ink
            : c.dim,
      ),
      prefixStyle: value.copyWith(color: c.dim),
      suffixStyle: value.copyWith(fontWeight: FontWeight.w600, color: c.dim),
      counterStyle: t.caption,
      alignLabelWithHint: true,
    );

    final chipLabel = t.label.copyWith(
      fontSize: 14,
      height: 18 / 14,
      fontWeight: FontWeight.w600,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: c.brightness,
      colorScheme: scheme,
      fontFamily: AknFonts.sans,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      cardColor: c.surface,
      dividerColor: c.lineSoft,
      disabledColor: c.faint,
      hintColor: c.dim,
      shadowColor: raisedShadow,
      // Pressed = a soft fill and a press scale, never a ripple (§5).
      splashFactory: NoSplash.splashFactory,
      splashColor: transparent,
      highlightColor: c.ink.withValues(alpha: dark ? 0.06 : 0.05),
      hoverColor: c.ink.withValues(alpha: 0.04),
      focusColor: c.brand.withValues(alpha: 0.16),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      textTheme: t.toTextTheme(),
      iconTheme: IconThemeData(color: c.ink, size: 24),
      primaryIconTheme: IconThemeData(color: c.ink, size: 24),
      extensions: <ThemeExtension<dynamic>>[c, t],
      cupertinoOverrideTheme: NoDefaultCupertinoThemeData(
        brightness: c.brightness,
        primaryColor: c.brand,
        primaryContrastingColor: c.onBrandFill,
        scaffoldBackgroundColor: c.bg,
        barBackgroundColor: c.bg,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          // Android 14+ geri hareketi önceki sayfayı önizler (spec D.7).
          TargetPlatform.android: AknPredictiveBackPageTransitionsBuilder(),
          TargetPlatform.fuchsia: AknSharedAxisPageTransitionsBuilder(),
          TargetPlatform.linux: AknSharedAxisPageTransitionsBuilder(),
          TargetPlatform.windows: AknSharedAxisPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      // The bar is the page colour with an ink title (pushed pages: headline
      // 17/22, 52 high). `AppScaffold` turns it frosted with a soft shadow
      // once content scrolls under it; no orange strip, no hairline.
      appBarTheme: AppBarThemeData(
        backgroundColor: c.bg,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: transparent,
        surfaceTintColor: transparent,
        centerTitle: false,
        titleSpacing: AknSpace.page,
        toolbarHeight: pushedBarHeight,
        titleTextStyle: AknTheme.appBarTitle(t),
        toolbarTextStyle: t.body,
        iconTheme: IconThemeData(color: c.ink, size: 24),
        actionsIconTheme: IconThemeData(color: c.ink, size: 24),
        actionsPadding: const EdgeInsets.only(right: 8),
        systemOverlayStyle: overlayFor(c.brightness),
      ),
      bottomAppBarTheme: BottomAppBarThemeData(
        color: c.surfaceRaised,
        elevation: 0,
        surfaceTintColor: transparent,
        shadowColor: transparent,
      ),
      // Cards float (§3): white r20 on the off-white page with a soft
      // shadow; dark cards keep a 1 px `line` instead.
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: dark ? 0 : 1.5,
        margin: EdgeInsets.zero,
        surfaceTintColor: transparent,
        shadowColor: dark ? transparent : c.ink.withValues(alpha: 0.4),
        clipBehavior: Clip.antiAlias,
        shape: RoundedSuperellipseBorder(
          borderRadius: AknRadius.card,
          side: dark ? BorderSide(color: c.line) : BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: primary),
      elevatedButtonTheme: ElevatedButtonThemeData(style: primary),
      outlinedButtonTheme: OutlinedButtonThemeData(style: secondary),
      textButtonTheme: TextButtonThemeData(style: ghost),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll<Size>(Size(48, 48)),
          iconSize: const WidgetStatePropertyAll<double>(24),
          shape: const WidgetStatePropertyAll<OutlinedBorder>(CircleBorder()),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => _disabled(s) ? c.faint : c.ink,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => _pressed(s) && !_disabled(s) ? c.surfaceAlt : null,
          ),
          overlayColor: const WidgetStatePropertyAll<Color>(transparent),
          side: WidgetStateProperty.resolveWith(
            (s) => _focused(s) ? focusRing(c) : null,
          ),
          splashFactory: NoSplash.splashFactory,
          animationDuration: AknMotion.press,
        ),
      ),
      // A FAB, if any, is the orange key: brand fill, white glyph, r16.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.brandFill,
        foregroundColor: c.onBrandFill,
        elevation: 3,
        focusElevation: 3,
        hoverElevation: 4,
        highlightElevation: 1,
        disabledElevation: 0,
        splashColor: transparent,
        shape: _squircle(AknRadius.button),
        extendedTextStyle: primaryLabel(t),
      ),
      inputDecorationTheme: inputs,
      // Chips (§4 Chips): white pills (36 high) with a 1 px `line`, ink
      // 14/18 600 labels; selected = an ink fill with a page-coloured label
      // and a check that slides in.
      // Chips (the panel's `.chip`): white pills with a hairline; selected =
      // the soft orange well, its orange line, a Pas label and check.
      chipTheme: ChipThemeData(
        color: WidgetStateProperty.resolveWith(
          (s) => _selected(s) && !_disabled(s)
              ? c.brandSoft
              : _disabled(s)
              ? c.surfaceAlt
              : c.surface,
        ),
        backgroundColor: c.surface,
        selectedColor: c.brandSoft,
        disabledColor: c.surfaceAlt,
        checkmarkColor: c.brandInk,
        deleteIconColor: c.dim,
        labelStyle: chipLabel.copyWith(
          color: WidgetStateColor.resolveWith(
            (s) => _disabled(s)
                ? c.faint
                : _selected(s)
                ? c.brandInk
                : c.ink,
          ),
        ),
        secondaryLabelStyle: chipLabel.copyWith(color: c.brandInk),
        iconTheme: IconThemeData(color: c.ink, size: 18),
        side: WidgetStateBorderSide.resolveWith(
          (s) => _selected(s) && !_disabled(s)
              ? BorderSide(color: c.brandLine)
              : BorderSide(color: c.line),
        ),
        shape: const RoundedRectangleBorder(borderRadius: AknRadius.chip),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
        showCheckmark: true,
        elevation: 0,
        pressElevation: 0,
        shadowColor: transparent,
        selectedShadowColor: transparent,
        surfaceTintColor: transparent,
      ),
      // Sheets (§4 Sheets): raised surface, superellipse top r28, a 40 × 5
      // pill handle (`lineStrong` 50 %), the scrim behind.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceRaised,
        modalBackgroundColor: c.surfaceRaised,
        surfaceTintColor: transparent,
        elevation: 0,
        modalElevation: 0,
        shadowColor: transparent,
        modalBarrierColor: c.scrim,
        showDragHandle: true,
        dragHandleColor: c.lineStrong.withValues(alpha: 0.5),
        dragHandleSize: const Size(40, 5),
        clipBehavior: Clip.antiAlias,
        shape: _squircle(AknRadius.sheet),
      ),
      // Dialogs (§4 Dialogs): r28 on the raised surface with a soft shadow;
      // only for blocking errors and irreversible confirmations.
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: transparent,
        shadowColor: raisedShadow,
        elevation: 12,
        shape: _squircle(AknRadius.dialog),
        titleTextStyle: t.title,
        contentTextStyle: t.body,
        barrierColor: c.scrim,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      ),
      // Snack bar = the toast look (§4 Toasts): an inverse card r16, white
      // 15/20 500, floating 12 above the bottom; actions white.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: c.inverse,
        contentTextStyle: t.body.copyWith(
          height: 20 / 15,
          fontWeight: FontWeight.w500,
          color: c.onInverse,
        ),
        actionTextColor: c.onInverse,
        disabledActionTextColor: c.onInverse.withValues(alpha: 0.6),
        closeIconColor: c.onInverse,
        elevation: 6,
        insetPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        shape: _squircle(AknRadius.button),
      ),
      // Rows inside cards are separated by soft inset hairlines (§4).
      dividerTheme: DividerThemeData(color: c.lineSoft, thickness: 1, space: 1),
      // Rows (§4 AknListTile): 20 px gutters, a 15/20 600 title, a
      // bodySmall second line, ink icons; selected = the soft orange well.
      listTileTheme: ListTileThemeData(
        iconColor: c.ink,
        textColor: c.ink,
        titleTextStyle: t.bodyStrong.copyWith(height: 20 / 15),
        subtitleTextStyle: t.bodySmall,
        leadingAndTrailingTextStyle: t.bodySmall,
        selectedColor: c.ink,
        selectedTileColor: c.brandSoft,
        contentPadding: const EdgeInsets.symmetric(horizontal: AknSpace.page),
        minVerticalPadding: 12,
        horizontalTitleGap: 14,
        minLeadingWidth: 24,
        shape: const RoundedRectangleBorder(),
      ),
      // Top tabs (§4 Tabs, the panel's `.tab`): 16/20 w700 labels, selected
      // Pas (the panel's "you are here"), others dim; a 3 px accent bar with
      // round ends as wide as the label that follows the selection on a
      // spring ([AknTabIndicator]: it stretches in flight, overshoots a touch
      // and settles); a hairline under the bar.
      tabBarTheme: TabBarThemeData(
        labelColor: c.brandInk,
        unselectedLabelColor: c.dim,
        labelStyle: primaryLabel(t),
        unselectedLabelStyle: primaryLabel(t),
        labelPadding: const EdgeInsets.symmetric(horizontal: 14),
        indicatorSize: TabBarIndicatorSize.label,
        indicatorColor: c.brand,
        indicator: AknTabIndicator(color: c.brand),
        // The spring does the stretching; the controller's path stays plain.
        indicatorAnimation: TabIndicatorAnimation.linear,
        dividerColor: c.line,
        dividerHeight: 1,
        overlayColor: const WidgetStatePropertyAll<Color>(transparent),
        splashFactory: NoSplash.splashFactory,
      ),
      // Switch: on = the orange track + white thumb (the thumb grows); off =
      // the control track (`lineStrong`, 3.44:1) with a white thumb.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => _disabled(s) && !_selected(s)
              ? c.surfaceAlt
              : const Color(0xFFFFFFFF),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => _disabled(s)
              ? (_selected(s) ? c.brand.withValues(alpha: 0.38) : c.line)
              : _selected(s)
              ? c.logo
              : c.lineStrong,
        ),
        trackOutlineColor: const WidgetStatePropertyAll<Color>(transparent),
        overlayColor: const WidgetStatePropertyAll<Color>(transparent),
        splashRadius: 0,
      ),
      // Checkbox / radio: selected = the orange mark with a white check;
      // rest = a 1.6 px control border.
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) =>
              _selected(s) ? (_disabled(s) ? c.faint : c.brand) : transparent,
        ),
        checkColor: WidgetStatePropertyAll<Color>(c.onBrandFill),
        side: WidgetStateBorderSide.resolveWith(
          (s) => _selected(s)
              ? const BorderSide(color: transparent, width: 0)
              : BorderSide(
                  color: _disabled(s) ? c.line : c.lineStrong,
                  width: 1.6,
                ),
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
        overlayColor: const WidgetStatePropertyAll<Color>(transparent),
        splashRadius: 0,
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => _disabled(s)
              ? c.faint
              : _selected(s)
              ? c.brand
              : c.lineStrong,
        ),
        overlayColor: const WidgetStatePropertyAll<Color>(transparent),
        splashRadius: 0,
      ),
      // Slider: the orange track and thumb over a `line` track that stays
      // visible on the page and on white cards; the value bubble is inverse.
      sliderTheme: SliderThemeData(
        activeTrackColor: c.logo,
        inactiveTrackColor: c.line,
        thumbColor: c.logo,
        trackHeight: 4,
        overlayColor: c.brand.withValues(alpha: 0.12),
        valueIndicatorColor: c.inverse,
        valueIndicatorTextStyle: t.label.copyWith(
          color: c.onInverse,
          fontFeatures: AknNumerals.tabular,
        ),
      ),
      // Progress (§4): logo orange on `surfaceAlt`, rounded ends.
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.logo,
        linearTrackColor: c.surfaceAlt,
        linearMinHeight: 4,
        circularTrackColor: transparent,
        refreshBackgroundColor: c.surfaceRaised,
        borderRadius: AknRadius.pillAll,
        strokeCap: StrokeCap.round,
      ),
      // Tooltips: an inverse bubble r10 with white 13/18 600 text.
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.inverse,
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          boxShadow: [
            BoxShadow(
              color: raisedShadow.withValues(alpha: dark ? 0.5 : 0.18),
              offset: const Offset(0, 6),
              blurRadius: 16,
              spreadRadius: -4,
            ),
          ],
        ),
        textStyle: t.label.copyWith(color: c.onInverse),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        waitDuration: const Duration(milliseconds: 500),
      ),
      // Menus (§3 raised): the raised surface r16 with a soft shadow; dark
      // menus keep a 1 px `line`.
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceRaised,
        surfaceTintColor: transparent,
        elevation: 8,
        shadowColor: raisedShadow.withValues(alpha: dark ? 1 : 0.5),
        textStyle: t.body.copyWith(color: c.ink),
        labelTextStyle: WidgetStatePropertyAll<TextStyle>(
          t.body.copyWith(color: c.ink),
        ),
        iconColor: c.ink,
        shape: RoundedSuperellipseBorder(
          borderRadius: AknRadius.button,
          side: dark ? BorderSide(color: c.line) : BorderSide.none,
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll<Color>(c.surfaceRaised),
          surfaceTintColor: const WidgetStatePropertyAll<Color>(transparent),
          shadowColor: WidgetStatePropertyAll<Color>(
            raisedShadow.withValues(alpha: dark ? 1 : 0.5),
          ),
          elevation: const WidgetStatePropertyAll<double>(8),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedSuperellipseBorder(
              borderRadius: AknRadius.button,
              side: dark ? BorderSide(color: c.line) : BorderSide.none,
            ),
          ),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: value,
        inputDecorationTheme: inputs,
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll<Color>(c.surfaceRaised),
          surfaceTintColor: const WidgetStatePropertyAll<Color>(transparent),
          shadowColor: WidgetStatePropertyAll<Color>(
            raisedShadow.withValues(alpha: dark ? 1 : 0.5),
          ),
          elevation: const WidgetStatePropertyAll<double>(8),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedSuperellipseBorder(
              borderRadius: AknRadius.button,
              side: dark ? BorderSide(color: c.line) : BorderSide.none,
            ),
          ),
        ),
      ),
      // Search (§4 Inputs): a `surfaceAlt` pill, 48 high; on focus it turns
      // white with a 2 px orange border.
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll<double>(0),
        shadowColor: const WidgetStatePropertyAll<Color>(transparent),
        surfaceTintColor: const WidgetStatePropertyAll<Color>(transparent),
        overlayColor: const WidgetStatePropertyAll<Color>(transparent),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => _focused(s) ? c.surface : c.surfaceAlt,
        ),
        side: WidgetStateProperty.resolveWith(
          (s) => _focused(s)
              ? BorderSide(color: c.brand, width: 2)
              : const BorderSide(color: transparent, width: 0),
        ),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(StadiumBorder()),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 14),
        ),
        textStyle: WidgetStatePropertyAll<TextStyle>(
          t.body.copyWith(height: 20 / 15, color: c.ink),
        ),
        hintStyle: WidgetStatePropertyAll<TextStyle>(
          t.body.copyWith(height: 20 / 15, color: c.dim),
        ),
        constraints: const BoxConstraints(minHeight: 48, maxHeight: 48),
      ),
      // Date and time pickers (brand): the selected day is a deep-orange
      // disc with a white figure (4.7:1), today an orange ring with Pas
      // figures, ranges the soft orange well; "Seç" is the orange action.
      datePickerTheme: DatePickerThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: transparent,
        shadowColor: raisedShadow,
        elevation: 12,
        shape: _squircle(AknRadius.dialog),
        headerBackgroundColor: c.surfaceRaised,
        headerForegroundColor: c.ink,
        headerHeadlineStyle: t.title,
        headerHelpStyle: t.label.copyWith(color: c.dim),
        weekdayStyle: t.captionStrong,
        dayStyle: t.body.copyWith(
          fontWeight: FontWeight.w600,
          fontFeatures: AknNumerals.tabular,
        ),
        yearStyle: t.body.copyWith(
          fontWeight: FontWeight.w600,
          fontFeatures: AknNumerals.tabular,
        ),
        dayForegroundColor: WidgetStateProperty.resolveWith(
          (s) => _selected(s)
              ? c.onBrandFill
              : _disabled(s)
              ? c.faint
              : c.ink,
        ),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (s) => _selected(s) ? c.brandFillPressed : transparent,
        ),
        dayOverlayColor: WidgetStatePropertyAll<Color>(c.brandSoft),
        todayForegroundColor: WidgetStateProperty.resolveWith(
          (s) => _selected(s) ? c.onBrandFill : c.brandInk,
        ),
        todayBackgroundColor: WidgetStateProperty.resolveWith(
          (s) => _selected(s) ? c.brandFillPressed : transparent,
        ),
        todayBorder: BorderSide(color: c.brand, width: 1.5),
        yearForegroundColor: WidgetStateProperty.resolveWith(
          (s) => _selected(s) ? c.onBrandFill : c.ink,
        ),
        yearBackgroundColor: WidgetStateProperty.resolveWith(
          (s) => _selected(s) ? c.brandFillPressed : transparent,
        ),
        yearOverlayColor: WidgetStatePropertyAll<Color>(c.brandSoft),
        rangeSelectionBackgroundColor: c.brandSoft,
        rangePickerBackgroundColor: c.surfaceRaised,
        rangePickerHeaderBackgroundColor: c.surfaceRaised,
        rangePickerHeaderForegroundColor: c.ink,
        dividerColor: c.lineSoft,
        cancelButtonStyle: ghost,
        confirmButtonStyle: confirm,
        inputDecorationTheme: inputs,
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: c.surfaceRaised,
        elevation: 12,
        shape: _squircle(AknRadius.dialog),
        helpTextStyle: t.label.copyWith(color: c.dim),
        hourMinuteShape: _squircle(AknRadius.input),
        hourMinuteColor: WidgetStateColor.resolveWith(
          (s) => _selected(s) ? c.brandSoft : c.surfaceAlt,
        ),
        hourMinuteTextColor: WidgetStateColor.resolveWith(
          (s) => _selected(s) ? c.brandInk : c.ink,
        ),
        hourMinuteTextStyle: t.numberLarge,
        dayPeriodShape: _squircle(AknRadius.input),
        dayPeriodColor: WidgetStateColor.resolveWith(
          (s) => _selected(s) ? c.brandSoft : transparent,
        ),
        dayPeriodTextColor: WidgetStateColor.resolveWith(
          (s) => _selected(s) ? c.brandInk : c.ink,
        ),
        dayPeriodBorderSide: BorderSide(color: c.lineStrong),
        dialBackgroundColor: c.surfaceAlt,
        dialHandColor: c.brandFillPressed,
        dialTextColor: WidgetStateColor.resolveWith(
          (s) => _selected(s) ? c.onBrandFill : c.ink,
        ),
        dialTextStyle: t.body.copyWith(fontFeatures: AknNumerals.tabular),
        entryModeIconColor: c.dim,
        cancelButtonStyle: ghost,
        confirmButtonStyle: confirm,
        inputDecorationTheme: inputs,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.brand,
        selectionColor: c.brand.withValues(alpha: 0.24),
        selectionHandleColor: c.brand,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll<Color>(
          c.lineStrong.withValues(alpha: 0.6),
        ),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll<double>(4),
        minThumbLength: 40,
      ),
      // Count badge (§4): a deep-orange pill with white 10 w800 figures
      // (brandFillPressed: 4.70:1, AA for small text).
      badgeTheme: BadgeThemeData(
        backgroundColor: c.brandFillPressed,
        textColor: c.onBrandFill,
        smallSize: 8,
        largeSize: 18,
        textStyle: t.captionStrong.copyWith(
          fontSize: 10,
          height: 18 / 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
          color: c.onBrandFill,
          fontFeatures: AknNumerals.tabular,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 5),
      ),
      // Docked bottom bar (§4): raised surface; the active item is the
      // panel's "you are here" — a soft orange pill with a Pas icon + label
      // (w700); the rest `navInactive`.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: transparent,
        shadowColor: transparent,
        elevation: 0,
        height: 64,
        indicatorColor: c.brandSoft,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        overlayColor: const WidgetStatePropertyAll<Color>(transparent),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: _selected(s) ? c.brandInk : c.navInactive,
            size: 24,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => t.navLabel.copyWith(
            color: _selected(s) ? c.brandInk : c.navInactive,
            fontWeight: _selected(s) ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.surfaceRaised,
        elevation: 0,
        indicatorColor: c.brandSoft,
        indicatorShape: const StadiumBorder(),
        selectedIconTheme: IconThemeData(color: c.brandInk, size: 24),
        unselectedIconTheme: IconThemeData(color: c.navInactive, size: 24),
        selectedLabelTextStyle: t.navLabel.copyWith(
          color: c.brandInk,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: t.navLabel,
      ),
      // Material's SegmentedButton, kept close to `AknSegmented` (§4): pill
      // segments on `surfaceAlt`, the selected one white with a Pas w700
      // label (the panel's `.seg-btn`), the others dim w600.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStateProperty.resolveWith(
            (s) => chipLabel.copyWith(
              fontWeight: _selected(s) ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => _selected(s)
                ? (dark ? c.surfaceRaised : c.surface)
                : c.surfaceAlt,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => _disabled(s)
                ? c.faint
                : _selected(s)
                ? c.brandInk
                : c.dim,
          ),
          side: WidgetStatePropertyAll<BorderSide>(BorderSide(color: c.line)),
          shape: const WidgetStatePropertyAll<OutlinedBorder>(StadiumBorder()),
          overlayColor: const WidgetStatePropertyAll<Color>(transparent),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: c.ink,
        collapsedIconColor: c.dim,
        textColor: c.ink,
        collapsedTextColor: c.ink,
        shape: const Border(),
        collapsedShape: const Border(),
        expansionAnimationStyle: const AnimationStyle(
          curve: AknMotion.emphasizedCurve,
          duration: Duration(milliseconds: 320),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: transparent,
        elevation: 0,
      ),
    );
  }

  /// Pushed-page app-bar title: `headline` 17/22 700 (§1, §4 App bar).
  static TextStyle appBarTitle(AknTextStyles t) => t.headline;

  /// Root tab-page app-bar title: `display` 28/34 800 (§1, §4 App bar).
  static TextStyle rootAppBarTitle(AknTextStyles t) => t.display;

  /// [theme] with its token extensions replaced by [colors] (and the text
  /// styles re-coloured to match, sizes kept). The deck uses it for every
  /// layer while the plate palette is handed from card to card (§5.3).
  static ThemeData withPalette(ThemeData theme, AknColors colors) {
    final text = theme.extension<AknTextStyles>() ?? AknTextStyles.from(colors);
    return theme.copyWith(
      extensions: theme.extensions.values
          .where((e) => e is! AknColors && e is! AknTextStyles)
          .followedBy([colors, text.recolor(colors)]),
    );
  }

  /// [theme] re-themed for content printed ON the plate card (owner
  /// decision G): the palette is `plateInk()` — ink stays ink, hairlines are
  /// `plateLine`, surfaces are the card, charts use the orange accent — and
  /// the text styles are re-coloured (sizes kept). The card is white, so
  /// stock controls keep their normal looks (the primary stays the orange
  /// gradient with a white label).
  ///
  /// `OnHero` / `AknPlate` wrap their subtree in
  /// `Theme(data: AknTheme.onPlate(Theme.of(context)), child: …)`.
  /// Idempotent: a plate inside a plate keeps the same theme.
  static ThemeData onPlate(ThemeData theme) {
    final base = theme.extension<AknColors>() ?? AknColors.light;
    final p = base.plateInk();
    final text = (theme.extension<AknTextStyles>() ?? AknTextStyles.from(p))
        .recolor(p);
    return theme.copyWith(
      extensions: theme.extensions.values
          .where((e) => e is! AknColors && e is! AknTextStyles)
          .followedBy([p, text]),
      textTheme: text.toTextTheme(),
      dividerColor: p.line,
      dividerTheme: theme.dividerTheme.copyWith(color: p.line),
      progressIndicatorTheme: theme.progressIndicatorTheme.copyWith(
        linearTrackColor: p.chartTrack,
      ),
      colorScheme: theme.colorScheme.copyWith(
        surface: p.surface,
        outlineVariant: p.line,
      ),
    );
  }

  /// The palette for content ON the orange header band (owner decision G):
  /// ink, icons, links and the focus ring are white ([AknColors.onHero]),
  /// secondary text white 92 %, quiet fills and hairlines white 20 %
  /// ([AknColors.navyRaised]), the page colour is the band's middle colour
  /// (so a count badge reads white with orange figures and an orange ring).
  static AknColors bandPalette(AknColors c) => c.copyWith(
    ink: c.onHero,
    text: c.onHero,
    dim: c.onHeroDim,
    faint: c.onHeroDim,
    link: c.onHero,
    brand: c.onHero,
    brandInk: c.onHero,
    lineStrong: c.onHero,
    line: c.navyRaised,
    lineSoft: c.navyRaised,
    bg: c.heroMid,
    surface: c.heroMid,
    surfaceRaised: c.heroMid,
    surfaceAlt: c.navyRaised,
    navInactive: c.onHeroDim,
  );

  /// [theme] re-themed for content on the header band ([bandPalette]):
  /// white text and icons; the status bar keeps light icons.
  static ThemeData onBand(ThemeData theme) {
    final base = theme.extension<AknColors>() ?? AknColors.light;
    final p = bandPalette(base);
    final text = (theme.extension<AknTextStyles>() ?? AknTextStyles.from(p))
        .recolor(p);
    return theme.copyWith(
      extensions: theme.extensions.values
          .where((e) => e is! AknColors && e is! AknTextStyles)
          .followedBy([p, text]),
      textTheme: text.toTextTheme(),
      iconTheme: theme.iconTheme.copyWith(color: p.ink),
      primaryIconTheme: theme.primaryIconTheme.copyWith(color: p.ink),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.ink,
        selectionColor: p.navyRaised,
        selectionHandleColor: p.ink,
      ),
    );
  }
}

/// The v3 field outline (§4 Inputs): an [OutlineInputBorder] (radius 14)
/// with an optional soft halo — [glowColor], [glowWidth] px — painted just
/// outside the shape: the focus glow of AkaryakıtNet fields. The input
/// decorator animates between its borders (~170 ms), so the halo blooms out
/// and fades with the focus border; [snap] (reduce motion) makes a change
/// jump instead. See [AknTheme.inputBorders].
class AknInputBorder extends OutlineInputBorder {
  const AknInputBorder({
    super.borderSide = const BorderSide(),
    super.borderRadius = AknRadius.input,
    super.gapPadding = 4.0,
    this.glowColor = const Color(0x00000000),
    this.glowWidth = 0,
    this.snap = false,
  });

  /// The halo colour (transparent: none).
  final Color glowColor;

  /// How far the halo reaches outside the border (4 on focus).
  final double glowWidth;

  /// Jump to this border instead of animating (reduce motion).
  final bool snap;

  bool get _glows => glowWidth > 0 && glowColor.a > 0;

  @override
  AknInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
    Color? glowColor,
    double? glowWidth,
    bool? snap,
  }) => AknInputBorder(
    borderSide: borderSide ?? this.borderSide,
    borderRadius: borderRadius ?? this.borderRadius,
    gapPadding: gapPadding ?? this.gapPadding,
    glowColor: glowColor ?? this.glowColor,
    glowWidth: glowWidth ?? this.glowWidth,
    snap: snap ?? this.snap,
  );

  @override
  AknInputBorder scale(double t) => AknInputBorder(
    borderSide: borderSide.scale(t),
    borderRadius: borderRadius * t,
    gapPadding: gapPadding * t,
    glowColor: glowColor,
    glowWidth: glowWidth * t,
    snap: snap,
  );

  /// [a] → [b] at [t]. A side without a halo fades from / to the other
  /// side's colour at zero opacity (never through black).
  static AknInputBorder _lerp(
    OutlineInputBorder a,
    OutlineInputBorder b,
    double t,
  ) {
    final ag = a is AknInputBorder && a._glows ? a : null;
    final bg = b is AknInputBorder && b._glows ? b : null;
    final hue = (ag ?? bg)?.glowColor ?? const Color(0x00000000);
    return AknInputBorder(
      borderRadius: BorderRadius.lerp(a.borderRadius, b.borderRadius, t)!,
      borderSide: BorderSide.lerp(a.borderSide, b.borderSide, t),
      gapPadding: lerpDouble(a.gapPadding, b.gapPadding, t)!,
      glowColor: Color.lerp(
        ag?.glowColor ?? hue.withValues(alpha: 0),
        bg?.glowColor ?? hue.withValues(alpha: 0),
        t,
      )!,
      glowWidth: math.max(
        0,
        lerpDouble(ag?.glowWidth ?? 0, bg?.glowWidth ?? 0, t)!,
      ),
    );
  }

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (snap) return this;
    if (a is OutlineInputBorder) return _lerp(a, this, t);
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (snap && b != null) return b;
    if (b is OutlineInputBorder) return _lerp(this, b, t);
    return super.lerpTo(b, t);
  }

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    if (_glows) {
      // A ring from the border's outer edge [glowWidth] px outwards.
      final halo = borderRadius.toRRect(rect).inflate(glowWidth / 2);
      canvas.drawRRect(
        halo,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = glowWidth
          ..color = glowColor,
      );
    }
    super.paint(
      canvas,
      rect,
      gapStart: gapStart,
      gapExtent: gapExtent,
      gapPercentage: gapPercentage,
      textDirection: textDirection,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AknInputBorder &&
        other.borderSide == borderSide &&
        other.borderRadius == borderRadius &&
        other.gapPadding == gapPadding &&
        other.glowColor == glowColor &&
        other.glowWidth == glowWidth &&
        other.snap == snap;
  }

  @override
  int get hashCode => Object.hash(
    borderSide,
    borderRadius,
    gapPadding,
    glowColor,
    glowWidth,
    snap,
  );
}

/// The v3 tab indicator (§4 Tabs, §5 Selection): a [thickness] px bar with
/// round ends in [color] (logo orange) under the selected label that
/// follows the tab controller on a spring — the leading edge runs ahead, the
/// trailing edge catches up (the bar stretches in flight), then it
/// overshoots a touch and settles (~0.6 s, finite). With [animate] false
/// (reduce motion; also when the platform asks for it) the bar sticks to the
/// controller's own position.
///
/// An [UnderlineTabIndicator], laid out like one; use it as
/// `TabBar.indicator` or `tabBarTheme.indicator` with
/// [TabIndicatorAnimation.linear] (the spring does the stretching).
class AknTabIndicator extends UnderlineTabIndicator {
  const AknTabIndicator({
    required this.color,
    this.thickness = 3,
    this.animate = true,
  }) : super(
         borderSide: const BorderSide(width: 3),
         borderRadius: const BorderRadius.all(Radius.circular(3)),
       );

  /// The bar colour (logo orange).
  final Color color;

  /// The bar height (3).
  final double thickness;

  /// Follow the selection on a spring (false: reduce motion).
  final bool animate;

  @override
  BorderSide get borderSide => BorderSide(color: color, width: thickness);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _AknTabIndicatorPainter(this, onChanged);

  @override
  Decoration? lerpFrom(Decoration? a, double t) => a is AknTabIndicator
      ? AknTabIndicator(
          color: Color.lerp(a.color, color, t)!,
          thickness: lerpDouble(a.thickness, thickness, t)!,
          animate: t < 0.5 ? a.animate : animate,
        )
      : super.lerpFrom(a, t);

  @override
  Decoration? lerpTo(Decoration? b, double t) => b is AknTabIndicator
      ? AknTabIndicator(
          color: Color.lerp(color, b.color, t)!,
          thickness: lerpDouble(thickness, b.thickness, t)!,
          animate: t < 0.5 ? animate : b.animate,
        )
      : super.lerpTo(b, t);

  @override
  bool operator ==(Object other) =>
      other is AknTabIndicator &&
      other.color == color &&
      other.thickness == thickness &&
      other.animate == animate &&
      other.insets == insets;

  @override
  int get hashCode => Object.hash(color, thickness, animate, insets);
}

/// Paints [AknTabIndicator]: each edge of the bar is a damped spring pulled
/// towards the rect the tab bar asks for this frame. The edge that leads in
/// the direction of travel is quicker and livelier (ω 26, ζ 0.5) than the
/// one that trails (ω 20, ζ 0.8): a next-tab move stretches the bar by about
/// a third and overshoots by ~2 px. A private [Ticker] runs only while the
/// bar is out of place and stops (or is disposed with the painter) once it
/// settles; the springs step at 240 Hz whatever the frame rate.
class _AknTabIndicatorPainter extends BoxPainter {
  _AknTabIndicatorPainter(this._indicator, super.onChanged);

  final AknTabIndicator _indicator;

  static const double _leadOmega = 26;
  static const double _leadZeta = 0.5;
  static const double _trailOmega = 20;
  static const double _trailZeta = 0.8;

  Ticker? _ticker;
  Duration _clock = Duration.zero;
  double? _left;
  double? _right;
  double _leftVelocity = 0;
  double _rightVelocity = 0;
  double _toLeft = 0;
  double _toRight = 0;

  /// +1 while the bar travels towards larger x, −1 towards smaller x.
  double _direction = 1;

  bool get _animate =>
      _indicator.animate &&
      !WidgetsBinding
          .instance
          .platformDispatcher
          .accessibilityFeatures
          .disableAnimations;

  bool get _settled =>
      (_left! - _toLeft).abs() < 0.25 &&
      (_right! - _toRight).abs() < 0.25 &&
      _leftVelocity.abs() < 2 &&
      _rightVelocity.abs() < 2;

  void _snap() {
    _left = _toLeft;
    _right = _toRight;
    _leftVelocity = 0;
    _rightVelocity = 0;
  }

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    final dir = configuration.textDirection ?? TextDirection.ltr;
    final rect = _indicator.insets.resolve(dir).deflateRect(offset & size);
    final moved = (rect.left + rect.right) - (_toLeft + _toRight);
    if (moved.abs() > 0.01) _direction = moved.sign;
    _toLeft = rect.left;
    _toRight = rect.right;
    if (_left == null || !_animate) {
      _ticker?.stop();
      _snap();
    } else if (!_settled) {
      final ticker = _ticker ??= Ticker(_tick, debugLabel: 'AknTabIndicator');
      if (!ticker.isActive) {
        _clock = Duration.zero;
        unawaited(ticker.start());
      }
    }
    final h = _indicator.thickness;
    final left = _left!;
    final right = math.max(_right!, left + h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(left, rect.bottom - h, right, rect.bottom),
        Radius.circular(h / 2),
      ),
      Paint()..color = _indicator.color,
    );
  }

  void _tick(Duration elapsed) {
    // A ticker's first tick reports zero: step one 60 Hz frame so the bar
    // leaves with the controller instead of a frame late.
    final dt = elapsed == Duration.zero
        ? 1 / 60
        : ((elapsed - _clock).inMicroseconds / Duration.microsecondsPerSecond)
              .clamp(0.0, 0.5);
    _clock = elapsed;
    final leftLeads = _direction < 0;
    final lw = leftLeads ? _leadOmega : _trailOmega;
    final lz = leftLeads ? _leadZeta : _trailZeta;
    final rw = leftLeads ? _trailOmega : _leadOmega;
    final rz = leftLeads ? _trailZeta : _leadZeta;
    final steps = math.max(1, (dt * 240).ceil());
    final step = dt / steps;
    var l = _left!;
    var r = _right!;
    for (var i = 0; i < steps; i++) {
      _leftVelocity +=
          (-(lw * lw) * (l - _toLeft) - 2 * lz * lw * _leftVelocity) * step;
      l += _leftVelocity * step;
      _rightVelocity +=
          (-(rw * rw) * (r - _toRight) - 2 * rz * rw * _rightVelocity) * step;
      r += _rightVelocity * step;
    }
    _left = l;
    _right = r;
    if (_settled) {
      _snap();
      _ticker?.stop();
    }
    onChanged?.call();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}

/// Token access: `context.akn.brand`, `context.aknText.title`.
extension AknThemeContext on BuildContext {
  /// Active colour tokens (falls back to light outside an AkaryakıtNet theme).
  AknColors get akn => Theme.of(this).extension<AknColors>() ?? AknColors.light;

  /// Active text styles.
  AknTextStyles get aknText =>
      Theme.of(this).extension<AknTextStyles>() ?? AknTextStyles.from(akn);

  /// True under reduce motion (`MediaQuery.disableAnimations`).
  bool get reduceMotion => AknMotion.reduced(this);
}

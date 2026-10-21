import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'motion.dart';
import 'tokens.dart';
import 'typography.dart';

/// Light and dark [ThemeData] for AkaryakıtNet — design v2 "Turuncu Plaka".
///
/// ```dart
/// MaterialApp.router(
///   theme: AknTheme.light(),
///   darkTheme: AknTheme.dark(),
///   themeMode: themeMode, // Sistem / Açık / Koyu
/// )
/// ```
///
/// Stock Material widgets pick up the identity through the component themes
/// (white ledger page, flat white bars, the orange-gradient primary with a
/// white label, white inputs with a 1 px control border and a 2 px orange focus
/// border, Beton chips that turn ink when selected, flat sheets and dialogs,
/// no ripples, no tints, no purple); AkaryakıtNet widgets read tokens with
/// `context.akn` and `context.aknText`. Content on the plate is re-themed by
/// [AknTheme.onPlate].
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

  static bool _disabled(Set<WidgetState> s) => s.contains(WidgetState.disabled);
  static bool _pressed(Set<WidgetState> s) => s.contains(WidgetState.pressed);
  static bool _selected(Set<WidgetState> s) => s.contains(WidgetState.selected);
  static bool _focused(Set<WidgetState> s) => s.contains(WidgetState.focused);

  /// The primary label (owner decision G): `button` at 17/22 w700, white.
  static TextStyle primaryLabel(AknTextStyles t) => t.button.copyWith(
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w700,
  );

  /// The primary button (§6.5, owner decision G): the orange gradient
  /// [AknColors.buttonGradient] (#F7742F → #E8590C) with a WHITE 17 px w700
  /// label; pressed [AknColors.buttonGradientPressed]; disabled Beton with
  /// a faint label. No ripple, radius 12, 52 high. The gradient is painted
  /// by `backgroundBuilder`, so every `FilledButton` / `ElevatedButton`
  /// picks it up from the theme.
  static ButtonStyle primaryButtonStyle(AknColors c, AknTextStyles t) =>
      ButtonStyle(
        textStyle: WidgetStatePropertyAll<TextStyle>(primaryLabel(t)),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
        minimumSize: const WidgetStatePropertyAll<Size>(Size(64, 52)),
        iconSize: const WidgetStatePropertyAll<double>(22),
        elevation: const WidgetStatePropertyAll<double>(0),
        shadowColor: const WidgetStatePropertyAll<Color>(Color(0x00000000)),
        surfaceTintColor: const WidgetStatePropertyAll<Color>(
          Color(0x00000000),
        ),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: AknRadius.button),
        ),
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
                decoration: BoxDecoration(
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

  /// The secondary / outline button (§6.5): `surface` fill, ink label,
  /// 1.5 px `lineStrong` border inside; pressed Beton. [danger] paints the
  /// label in the danger tone (Reddet).
  static ButtonStyle secondaryButtonStyle(
    AknColors c,
    AknTextStyles t, {
    bool danger = false,
  }) => ButtonStyle(
    textStyle: WidgetStatePropertyAll<TextStyle>(t.button),
    padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    ),
    minimumSize: const WidgetStatePropertyAll<Size>(Size(64, 52)),
    iconSize: const WidgetStatePropertyAll<double>(22),
    elevation: const WidgetStatePropertyAll<double>(0),
    shadowColor: const WidgetStatePropertyAll<Color>(Color(0x00000000)),
    surfaceTintColor: const WidgetStatePropertyAll<Color>(Color(0x00000000)),
    shape: const WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(borderRadius: AknRadius.button),
    ),
    backgroundColor: WidgetStateProperty.resolveWith(
      (s) => _disabled(s) || _pressed(s) ? c.surfaceAlt : c.surface,
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
          : _disabled(s)
          ? const BorderSide(color: Color(0x00000000), width: 0)
          : BorderSide(color: c.lineStrong, width: 1.5),
    ),
    overlayColor: const WidgetStatePropertyAll<Color>(Color(0x00000000)),
    splashFactory: NoSplash.splashFactory,
    animationDuration: AknMotion.press,
  );

  /// The ghost (tertiary) button (§6.5): no fill, ink label 600; pressed
  /// Beton (r10). Never orange, never blue.
  static ButtonStyle ghostButtonStyle(AknColors c, AknTextStyles t) =>
      ButtonStyle(
        textStyle: WidgetStatePropertyAll<TextStyle>(t.button),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        minimumSize: const WidgetStatePropertyAll<Size>(Size(48, 44)),
        iconSize: const WidgetStatePropertyAll<double>(20),
        elevation: const WidgetStatePropertyAll<double>(0),
        shape: const WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: AknRadius.buttonSmall),
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

  /// The destructive confirm button of a sheet (§6.21): `dangerFill` with a
  /// white label; pressed 8 % darker.
  static ButtonStyle destructiveButtonStyle(AknColors c, AknTextStyles t) =>
      primaryButtonStyle(c, t).copyWith(
        textStyle: WidgetStatePropertyAll<TextStyle>(t.button),
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

    final scheme = ColorScheme(
      brightness: c.brightness,
      // Marks: focus, progress, selection handles. On orange, ink is black.
      primary: c.brand,
      onPrimary: c.onBrandFill,
      primaryContainer: c.brandSoft,
      onPrimaryContainer: c.brandInk,
      // Selection is ink (chips, checkboxes, segmented): never orange.
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

    // White inputs (§6.10): 1 px control border (3.14:1), 2 px orange focus,
    // 2 px danger error, Beton when disabled.
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: AknRadius.input,
      borderSide: BorderSide(color: color, width: width),
    );
    final inputs = InputDecorationThemeData(
      filled: true,
      fillColor: WidgetStateColor.resolveWith(
        (s) => _disabled(s) ? c.surfaceAlt : c.surface,
      ),
      hoverColor: transparent,
      focusColor: transparent,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: border(c.lineStrong, 1),
      enabledBorder: border(c.lineStrong, 1),
      disabledBorder: border(c.line, 1),
      focusedBorder: border(c.brand, 2),
      errorBorder: border(c.danger.fg, 2),
      focusedErrorBorder: border(c.danger.fg, 2),
      labelStyle: t.label.copyWith(color: c.ink),
      floatingLabelStyle: WidgetStateTextStyle.resolveWith((s) {
        if (s.contains(WidgetState.error)) {
          return t.label.copyWith(color: c.danger.fg);
        }
        if (_disabled(s)) return t.label.copyWith(color: c.faint);
        return t.label.copyWith(color: c.ink);
      }),
      hintStyle: t.body.copyWith(fontSize: 16, height: 22 / 16, color: c.dim),
      helperStyle: t.label.copyWith(color: c.dim, fontWeight: FontWeight.w400),
      helperMaxLines: 3,
      errorStyle: t.label.copyWith(color: c.danger.fg),
      errorMaxLines: 3,
      prefixIconColor: WidgetStateColor.resolveWith(
        (s) => _disabled(s) ? c.faint : c.dim,
      ),
      suffixIconColor: WidgetStateColor.resolveWith(
        (s) => _disabled(s) ? c.faint : c.dim,
      ),
      prefixStyle: t.body.copyWith(fontSize: 16, height: 22 / 16, color: c.dim),
      suffixStyle: t.bodyStrong.copyWith(
        fontSize: 16,
        height: 22 / 16,
        color: c.dim,
      ),
      counterStyle: t.caption,
      alignLabelWithHint: true,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: c.brightness,
      colorScheme: scheme,
      fontFamily: AknFonts.sans,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      cardColor: c.surface,
      dividerColor: c.line,
      disabledColor: c.faint,
      hintColor: c.dim,
      // Pressed = a flat Beton-like fill, never a ripple (§6.8, §8.2).
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
      // White bar on the page colour, ink title (pushed pages: headline
      // 17/22 600, 52 high). No orange, no shadow; `AppScaffold` draws the
      // hairline once content scrolls under it.
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
        color: dark ? c.surface : c.surfaceRaised,
        elevation: 0,
        surfaceTintColor: transparent,
        shadowColor: transparent,
      ),
      // `AknCard` is a flat group box: surface, 1 px line, r12, no shadow.
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: transparent,
        shadowColor: transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AknRadius.card,
          side: BorderSide(color: c.line),
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
      // Nothing floats over content in v2; a FAB, if any, is the flat
      // primary key.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.brandFill,
        foregroundColor: c.onBrandFill,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        disabledElevation: 0,
        splashColor: transparent,
        shape: const RoundedRectangleBorder(borderRadius: AknRadius.button),
        extendedTextStyle: t.button,
      ),
      inputDecorationTheme: inputs,
      // Chips (§6.11): Beton, r10, ink 14/18 600; selected = ink fill with a
      // bg-coloured label. No checkmark, no orange.
      chipTheme: ChipThemeData(
        color: WidgetStateProperty.resolveWith(
          (s) => _selected(s) && !_disabled(s) ? c.ink : c.surfaceAlt,
        ),
        backgroundColor: c.surfaceAlt,
        selectedColor: c.ink,
        disabledColor: c.surfaceAlt,
        checkmarkColor: c.bg,
        deleteIconColor: c.dim,
        labelStyle: t.label.copyWith(
          fontSize: 14,
          height: 18 / 14,
          fontWeight: FontWeight.w600,
          color: WidgetStateColor.resolveWith(
            (s) => _disabled(s)
                ? c.faint
                : _selected(s)
                ? c.bg
                : c.ink,
          ),
        ),
        secondaryLabelStyle: t.label.copyWith(
          fontSize: 14,
          height: 18 / 14,
          fontWeight: FontWeight.w600,
          color: c.bg,
        ),
        iconTheme: IconThemeData(color: c.ink, size: 18),
        side: const BorderSide(color: transparent, width: 0),
        shape: const RoundedRectangleBorder(
          borderRadius: AknRadius.chip,
          side: BorderSide(color: transparent, width: 0),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
        showCheckmark: false,
        elevation: 0,
        pressElevation: 0,
        shadowColor: transparent,
        selectedShadowColor: transparent,
        surfaceTintColor: transparent,
      ),
      // Sheets (§6.21): raised surface, top radius 20, 36×4 handle in the
      // control colour, scrim behind.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceRaised,
        modalBackgroundColor: c.surfaceRaised,
        surfaceTintColor: transparent,
        elevation: 0,
        modalElevation: 0,
        shadowColor: transparent,
        modalBarrierColor: c.scrim,
        showDragHandle: true,
        dragHandleColor: c.lineStrong,
        dragHandleSize: const Size(36, 4),
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(borderRadius: AknRadius.sheet),
      ),
      // Dialogs (r20) only for blocking errors and irreversible
      // confirmations.
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: transparent,
        shadowColor: transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AknRadius.dialog),
        titleTextStyle: t.title,
        contentTextStyle: t.body,
        barrierColor: c.scrim,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      ),
      // Toast (§6.22): inverse fill, white 15/20 500, r12, 12 above the
      // bottom bar; actions are white (the widget underlines them).
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
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        shape: const RoundedRectangleBorder(borderRadius: AknRadius.card),
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      // Ledger rows (§6.8): full bleed, 20 px gutters, headline title,
      // bodySmall second line, pressed = Beton.
      listTileTheme: ListTileThemeData(
        iconColor: c.dim,
        textColor: c.ink,
        titleTextStyle: t.headline,
        subtitleTextStyle: t.bodySmall,
        leadingAndTrailingTextStyle: t.bodySmall,
        selectedColor: c.ink,
        selectedTileColor: c.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: AknSpace.page),
        minVerticalPadding: 12,
        horizontalTitleGap: 16,
        minLeadingWidth: 24,
        shape: const RoundedRectangleBorder(),
      ),
      // Top tabs (§6.11): 16/20 600, selected ink, others dim; a 3 px logo
      // underline as wide as the label, top-rounded 2; 1 px divider.
      tabBarTheme: TabBarThemeData(
        labelColor: c.ink,
        unselectedLabelColor: c.dim,
        labelStyle: t.button,
        unselectedLabelStyle: t.button,
        labelPadding: const EdgeInsets.symmetric(horizontal: 14),
        indicatorSize: TabBarIndicatorSize.label,
        indicatorColor: c.logo,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: c.logo, width: 3),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
        ),
        dividerColor: c.line,
        dividerHeight: 1,
        overlayColor: const WidgetStatePropertyAll<Color>(transparent),
        splashFactory: NoSplash.splashFactory,
      ),
      // Switch: on = logo track + white thumb; off = control track.
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
      // Checkbox / radio: selected = ink fill, page-coloured check; border
      // 1.6 px control.
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => _selected(s) ? (_disabled(s) ? c.faint : c.ink) : transparent,
        ),
        checkColor: WidgetStatePropertyAll<Color>(c.bg),
        side: WidgetStateBorderSide.resolveWith(
          (s) => _selected(s)
              ? const BorderSide(color: transparent, width: 0)
              : BorderSide(
                  color: _disabled(s) ? c.line : c.lineStrong,
                  width: 1.6,
                ),
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AknRadius.xs)),
        ),
        overlayColor: const WidgetStatePropertyAll<Color>(transparent),
        splashRadius: 0,
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => _disabled(s)
              ? c.faint
              : _selected(s)
              ? c.ink
              : c.lineStrong,
        ),
        overlayColor: const WidgetStatePropertyAll<Color>(transparent),
        splashRadius: 0,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.logo,
        inactiveTrackColor: c.chartTrack,
        thumbColor: c.logo,
        overlayColor: c.brand.withValues(alpha: 0.12),
        valueIndicatorColor: c.inverse,
        valueIndicatorTextStyle: t.label.copyWith(color: c.onInverse),
      ),
      // Progress fills are logo orange (§6.23); spinners are ChevronSpinner.
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.logo,
        linearTrackColor: c.surfaceAlt,
        linearMinHeight: 2.5,
        circularTrackColor: transparent,
        refreshBackgroundColor: c.surfaceRaised,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.inverse,
          borderRadius: const BorderRadius.all(Radius.circular(AknRadius.sm)),
        ),
        textStyle: t.label.copyWith(color: c.onInverse),
        waitDuration: const Duration(milliseconds: 500),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceRaised,
        surfaceTintColor: transparent,
        elevation: 6,
        shadowColor: c.shadow,
        textStyle: t.body.copyWith(color: c.ink),
        labelTextStyle: WidgetStatePropertyAll<TextStyle>(
          t.body.copyWith(color: c.ink),
        ),
        iconColor: c.ink,
        shape: RoundedRectangleBorder(
          borderRadius: AknRadius.card,
          side: BorderSide(color: c.line),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll<Color>(c.surfaceRaised),
          surfaceTintColor: const WidgetStatePropertyAll<Color>(transparent),
          shadowColor: WidgetStatePropertyAll<Color>(c.shadow),
          elevation: const WidgetStatePropertyAll<double>(6),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: AknRadius.card,
              side: BorderSide(color: c.line),
            ),
          ),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: t.body.copyWith(fontSize: 16, height: 22 / 16),
        inputDecorationTheme: inputs,
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll<Color>(c.surfaceRaised),
          surfaceTintColor: const WidgetStatePropertyAll<Color>(transparent),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: AknRadius.card,
              side: BorderSide(color: c.line),
            ),
          ),
        ),
      ),
      // Search (§6.10): a Beton well, 44 high, r12; on focus it turns white
      // with a 2 px orange border (orange never sits on Beton).
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
        shape: const WidgetStatePropertyAll<OutlinedBorder>(
          RoundedRectangleBorder(borderRadius: AknRadius.input),
        ),
        padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
          EdgeInsets.symmetric(horizontal: 14),
        ),
        textStyle: WidgetStatePropertyAll<TextStyle>(
          t.body.copyWith(height: 20 / 15, color: c.ink),
        ),
        hintStyle: WidgetStatePropertyAll<TextStyle>(
          t.body.copyWith(height: 20 / 15, color: c.dim),
        ),
        constraints: const BoxConstraints(minHeight: 44, maxHeight: 44),
      ),
      // Date and time pickers: selection is ink (like chips), today is an
      // ink ring; no orange fills, no tints, never purple.
      datePickerTheme: DatePickerThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: transparent,
        shadowColor: transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AknRadius.dialog),
        headerBackgroundColor: c.surfaceRaised,
        headerForegroundColor: c.ink,
        headerHeadlineStyle: t.title,
        headerHelpStyle: t.label.copyWith(color: c.dim),
        weekdayStyle: t.captionStrong,
        dayStyle: t.body,
        yearStyle: t.body,
        dayForegroundColor: WidgetStateProperty.resolveWith(
          (s) => _selected(s)
              ? c.bg
              : _disabled(s)
              ? c.faint
              : c.ink,
        ),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (s) => _selected(s) ? c.ink : transparent,
        ),
        dayOverlayColor: WidgetStatePropertyAll<Color>(c.surfaceAlt),
        todayForegroundColor: WidgetStateProperty.resolveWith(
          (s) => _selected(s) ? c.bg : c.ink,
        ),
        todayBackgroundColor: WidgetStateProperty.resolveWith(
          (s) => _selected(s) ? c.ink : transparent,
        ),
        todayBorder: BorderSide(color: c.ink, width: 1.5),
        yearForegroundColor: WidgetStateProperty.resolveWith(
          (s) => _selected(s) ? c.bg : c.ink,
        ),
        yearBackgroundColor: WidgetStateProperty.resolveWith(
          (s) => _selected(s) ? c.ink : transparent,
        ),
        yearOverlayColor: WidgetStatePropertyAll<Color>(c.surfaceAlt),
        rangeSelectionBackgroundColor: c.surfaceAlt,
        rangePickerBackgroundColor: c.surfaceRaised,
        rangePickerHeaderBackgroundColor: c.surfaceRaised,
        rangePickerHeaderForegroundColor: c.ink,
        dividerColor: c.line,
        cancelButtonStyle: ghost,
        confirmButtonStyle: ghost,
        inputDecorationTheme: inputs,
      ),
      timePickerTheme: TimePickerThemeData(
        backgroundColor: c.surfaceRaised,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AknRadius.dialog),
        helpTextStyle: t.label.copyWith(color: c.dim),
        hourMinuteShape: const RoundedRectangleBorder(
          borderRadius: AknRadius.input,
        ),
        hourMinuteColor: WidgetStateColor.resolveWith(
          (s) => _selected(s) ? c.ink : c.surfaceAlt,
        ),
        hourMinuteTextColor: WidgetStateColor.resolveWith(
          (s) => _selected(s) ? c.bg : c.ink,
        ),
        hourMinuteTextStyle: t.numberLarge,
        dayPeriodShape: const RoundedRectangleBorder(
          borderRadius: AknRadius.input,
        ),
        dayPeriodColor: WidgetStateColor.resolveWith(
          (s) => _selected(s) ? c.ink : transparent,
        ),
        dayPeriodTextColor: WidgetStateColor.resolveWith(
          (s) => _selected(s) ? c.bg : c.ink,
        ),
        dayPeriodBorderSide: BorderSide(color: c.lineStrong),
        dialBackgroundColor: c.surfaceAlt,
        dialHandColor: c.ink,
        dialTextColor: WidgetStateColor.resolveWith(
          (s) => _selected(s) ? c.bg : c.ink,
        ),
        dialTextStyle: t.body,
        entryModeIconColor: c.dim,
        cancelButtonStyle: ghost,
        confirmButtonStyle: ghost,
        inputDecorationTheme: inputs,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.brand,
        selectionColor: c.brand.withValues(alpha: 0.24),
        selectionHandleColor: c.brand,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll<Color>(c.lineStrong),
        radius: const Radius.circular(4),
        thickness: const WidgetStatePropertyAll<double>(4),
      ),
      // Count badge (§6.3): an ink pill with page-coloured digits (red is
      // reserved for danger), 18 high, 11/18 700.
      badgeTheme: BadgeThemeData(
        backgroundColor: c.ink,
        textColor: c.bg,
        smallSize: 8,
        largeSize: 18,
        textStyle: t.captionStrong.copyWith(
          fontSize: 11,
          height: 18 / 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: c.bg,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 5),
      ),
      // Docked bottom bar (§6.4): raised surface (dark: surface), no pill
      // indicator; active = ink icon + label 600, inactive = navInactive.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? c.surface : c.surfaceRaised,
        surfaceTintColor: transparent,
        shadowColor: transparent,
        elevation: 0,
        height: 56,
        indicatorColor: transparent,
        indicatorShape: const RoundedRectangleBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        overlayColor: const WidgetStatePropertyAll<Color>(transparent),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: _selected(s) ? c.ink : c.navInactive,
            size: 24,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => t.navLabel.copyWith(
            color: _selected(s) ? c.ink : c.navInactive,
            fontWeight: _selected(s) ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: dark ? c.surface : c.surfaceRaised,
        elevation: 0,
        indicatorColor: transparent,
        selectedIconTheme: IconThemeData(color: c.ink, size: 24),
        unselectedIconTheme: IconThemeData(color: c.navInactive, size: 24),
        selectedLabelTextStyle: t.navLabel.copyWith(
          color: c.ink,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: t.navLabel,
      ),
      // Material's SegmentedButton, kept close to `AknSegmented` (§6.11):
      // Beton segments, the selected one white with an ink label.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll<TextStyle>(
            t.label.copyWith(
              fontSize: 14,
              height: 18 / 14,
              fontWeight: FontWeight.w600,
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
                ? c.ink
                : c.dim,
          ),
          side: WidgetStatePropertyAll<BorderSide>(BorderSide(color: c.line)),
          shape: const WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: AknRadius.input),
          ),
          overlayColor: const WidgetStatePropertyAll<Color>(transparent),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        iconColor: c.dim,
        collapsedIconColor: c.dim,
        textColor: c.ink,
        collapsedTextColor: c.ink,
        shape: const Border(),
        collapsedShape: const Border(),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: transparent,
        elevation: 0,
      ),
    );
  }

  /// Pushed-page app-bar title: `headline` 17/22 600 (§3.2, §6.1).
  static TextStyle appBarTitle(AknTextStyles t) => t.headline;

  /// Root tab-page app-bar title: `display` 30/36 600 (§6.1).
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
  /// secondary text white 92 %, quiet fills and hairlines white 22 %
  /// ([AknColors.navyRaised]), the page colour is the band's middle colour
  /// (so a count badge reads white with orange digits and an orange ring).
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

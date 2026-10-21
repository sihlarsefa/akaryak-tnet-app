import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'motion.dart';
import 'tokens.dart';
import 'typography.dart';

/// Light and dark [ThemeData] for AkaryakıtNet ("Turuncu & Beyaz").
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
/// (white app bar, orange filled buttons, filled inputs with an orange focus
/// ring, pill chips, white sheets and dialogs); AkaryakıtNet widgets read
/// tokens with `context.akn` and `context.aknText`.
abstract final class AknTheme {
  static ThemeData light() => build(AknColors.light);

  static ThemeData dark() => build(AknColors.dark);

  static ThemeData of(Brightness brightness) =>
      brightness == Brightness.dark ? dark() : light();

  /// System bars over content on `bg` / `surface`: dark icons on light pages
  /// (iOS `statusBarBrightness: light`), light icons in dark mode. The
  /// navigation bar stays transparent (edge-to-edge) so the white bottom bar
  /// or page shows through, with matching icons.
  static SystemUiOverlayStyle overlayFor(Brightness brightness) =>
      brightness == Brightness.dark
      ? const SystemUiOverlayStyle(
          statusBarColor: Color(0x00000000),
          statusBarBrightness: Brightness.dark,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Color(0x00000000),
          systemNavigationBarDividerColor: Color(0x00000000),
          systemNavigationBarIconBrightness: Brightness.light,
        )
      : const SystemUiOverlayStyle(
          statusBarColor: Color(0x00000000),
          statusBarBrightness: Brightness.light,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: Color(0x00000000),
          systemNavigationBarDividerColor: Color(0x00000000),
          systemNavigationBarIconBrightness: Brightness.dark,
        );

  /// Status bar over the orange hero (hero app bar, header strip): light
  /// icons in both themes. Never dark icons on orange.
  static const SystemUiOverlayStyle overlayOnHero = SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0x00000000),
    systemNavigationBarDividerColor: Color(0x00000000),
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  /// Deprecated alias of [overlayOnHero] (the navy header is gone).
  static const SystemUiOverlayStyle overlayOnNavy = overlayOnHero;

  static ThemeData build(AknColors c) {
    final t = AknTextStyles.from(c);
    final dark = c.isDark;
    const white = Color(0xFFFFFFFF);
    const transparent = Color(0x00000000);
    const charcoal = Color(0xFF0F1114);
    // Inverse surfaces (snackbar, tooltip): neutral charcoal, never navy.
    final inverse = dark ? const Color(0xFF343A42) : const Color(0xFF262A30);

    final scheme = ColorScheme(
      brightness: c.brightness,
      primary: c.brand,
      onPrimary: white,
      primaryContainer: c.brandSoft,
      onPrimaryContainer: c.brandInk,
      secondary: c.brandInk,
      onSecondary: dark ? charcoal : white,
      secondaryContainer: c.brandSoft,
      onSecondaryContainer: c.brandInk,
      tertiary: c.info.fg,
      onTertiary: dark ? charcoal : white,
      tertiaryContainer: c.info.bg,
      onTertiaryContainer: c.info.fg,
      error: c.danger.fg,
      onError: dark ? charcoal : white,
      errorContainer: c.danger.bg,
      onErrorContainer: c.danger.fg,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.dim,
      surfaceDim: c.bg,
      surfaceBright: c.surfaceRaised,
      surfaceContainerLowest: dark ? c.bg : white,
      surfaceContainerLow: dark ? c.surface : c.bg,
      surfaceContainer: c.surfaceAlt,
      surfaceContainerHigh: c.lineSoft,
      surfaceContainerHighest: c.line,
      outline: c.lineStrong,
      outlineVariant: c.line,
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      inverseSurface: inverse,
      onInverseSurface: white,
      inversePrimary: dark ? c.brandFill : const Color(0xFFFF8A4C),
      surfaceTint: transparent,
    );

    const radiusButton = RoundedRectangleBorder(borderRadius: AknRadius.button);
    const pill = StadiumBorder();
    final buttonText = WidgetStatePropertyAll<TextStyle>(t.button);
    const buttonPadding = WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    );
    const buttonMin = WidgetStatePropertyAll<Size>(Size(64, 52));

    bool disabled(Set<WidgetState> s) => s.contains(WidgetState.disabled);
    bool pressed(Set<WidgetState> s) => s.contains(WidgetState.pressed);
    bool selected(Set<WidgetState> s) => s.contains(WidgetState.selected);

    final filledStyle = ButtonStyle(
      textStyle: buttonText,
      padding: buttonPadding,
      minimumSize: buttonMin,
      elevation: const WidgetStatePropertyAll<double>(0),
      shape: const WidgetStatePropertyAll<OutlinedBorder>(radiusButton),
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => disabled(s)
            ? (dark ? c.surfaceAlt : c.lineSoft)
            : pressed(s)
            ? c.brandFillPressed
            : c.brandFill,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => disabled(s) ? c.faint : c.onBrandFill,
      ),
      overlayColor: const WidgetStatePropertyAll<Color>(Color(0x14FFFFFF)),
    );

    final outlinedStyle = ButtonStyle(
      textStyle: buttonText,
      padding: buttonPadding,
      minimumSize: buttonMin,
      elevation: const WidgetStatePropertyAll<double>(0),
      shape: const WidgetStatePropertyAll<OutlinedBorder>(radiusButton),
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => pressed(s) ? c.surfaceAlt : c.surface,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => disabled(s) ? c.faint : c.ink,
      ),
      side: WidgetStateProperty.resolveWith(
        (s) => BorderSide(color: disabled(s) ? c.line : c.lineStrong),
      ),
      overlayColor: WidgetStatePropertyAll<Color>(
        c.ink.withValues(alpha: 0.04),
      ),
    );

    final textStyle = ButtonStyle(
      textStyle: buttonText,
      padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      minimumSize: const WidgetStatePropertyAll<Size>(Size(48, 44)),
      shape: const WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(borderRadius: AknRadius.chip),
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => disabled(s) ? c.faint : c.brandInk,
      ),
      overlayColor: WidgetStatePropertyAll<Color>(c.brandSoft),
    );

    // Filled inputs: no border until focused (2 px orange ring).
    const noBorder = OutlineInputBorder(
      borderRadius: AknRadius.input,
      borderSide: BorderSide(color: transparent, width: 0),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: c.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      canvasColor: c.bg,
      cardColor: c.surface,
      dividerColor: c.lineSoft,
      disabledColor: c.faint,
      hintColor: c.dim,
      splashFactory: InkRipple.splashFactory,
      splashColor: c.ink.withValues(alpha: 0.06),
      highlightColor: c.ink.withValues(alpha: 0.04),
      hoverColor: c.ink.withValues(alpha: 0.04),
      focusColor: c.brand.withValues(alpha: 0.14),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
      textTheme: AknTextStyles.textTheme(c),
      iconTheme: IconThemeData(color: c.text, size: 22),
      primaryIconTheme: IconThemeData(color: c.ink, size: 22),
      extensions: <ThemeExtension<dynamic>>[c, t],
      cupertinoOverrideTheme: NoDefaultCupertinoThemeData(
        brightness: c.brightness,
        primaryColor: c.brand,
        scaffoldBackgroundColor: c.bg,
        barBackgroundColor: c.surface,
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
      // White app bar, ink title (left, w800); a hairline and soft shadow
      // appear only when content scrolls under it (AppScaffold draws them;
      // stock AppBars get the shadow from the elevation).
      appBarTheme: AppBarThemeData(
        backgroundColor: c.surface,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0.6,
        shadowColor: dark ? const Color(0xFF000000) : const Color(0x4D101828),
        surfaceTintColor: transparent,
        centerTitle: false,
        titleSpacing: 16,
        toolbarHeight: 56,
        titleTextStyle: AknTheme.appBarTitle(t),
        iconTheme: IconThemeData(color: c.ink, size: 24),
        actionsIconTheme: IconThemeData(color: c.ink, size: 24),
        systemOverlayStyle: overlayFor(c.brightness),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: transparent,
        shadowColor: c.shadow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AknRadius.card,
          side: BorderSide(color: dark ? c.line : c.lineSoft),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: filledStyle),
      elevatedButtonTheme: ElevatedButtonThemeData(style: filledStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(style: outlinedStyle),
      textButtonTheme: TextButtonThemeData(style: textStyle),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll<Size>(Size(48, 48)),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => disabled(s) ? c.faint : c.ink,
          ),
          overlayColor: WidgetStatePropertyAll<Color>(
            c.ink.withValues(alpha: 0.06),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.brandFill,
        foregroundColor: c.onBrandFill,
        elevation: 3,
        focusElevation: 3,
        hoverElevation: 4,
        highlightElevation: 2,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AknRadius.lg)),
        ),
        extendedTextStyle: t.button,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: c.surfaceAlt,
        // The label sits above the value inside the field (always floating).
        floatingLabelBehavior: FloatingLabelBehavior.always,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: noBorder,
        enabledBorder: noBorder,
        disabledBorder: noBorder,
        focusedBorder: noBorder.copyWith(
          borderSide: BorderSide(color: c.brand, width: 2),
        ),
        errorBorder: noBorder.copyWith(
          borderSide: BorderSide(color: c.danger.fg, width: 1.4),
        ),
        focusedErrorBorder: noBorder.copyWith(
          borderSide: BorderSide(color: c.danger.fg, width: 2),
        ),
        labelStyle: t.body.copyWith(color: c.dim),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith((s) {
          if (s.contains(WidgetState.error)) {
            return t.label.copyWith(color: c.danger.fg);
          }
          if (s.contains(WidgetState.focused)) {
            return t.label.copyWith(color: c.brandInk);
          }
          return t.label.copyWith(color: c.dim);
        }),
        hintStyle: t.body.copyWith(color: c.dim),
        helperStyle: t.caption,
        helperMaxLines: 3,
        errorStyle: t.caption.copyWith(
          color: c.danger.fg,
          fontWeight: FontWeight.w500,
        ),
        errorMaxLines: 3,
        prefixIconColor: c.dim,
        suffixIconColor: c.dim,
        alignLabelWithHint: true,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        selectedColor: c.brandFill,
        disabledColor: c.surfaceAlt,
        checkmarkColor: c.onBrandFill,
        deleteIconColor: c.dim,
        labelStyle: t.label.copyWith(color: c.text),
        secondaryLabelStyle: t.label.copyWith(color: c.onBrandFill),
        side: WidgetStateBorderSide.resolveWith(
          (s) => selected(s)
              ? const BorderSide(color: transparent)
              : BorderSide(color: c.line),
        ),
        shape: pill,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        showCheckmark: false,
        elevation: 0,
        pressElevation: 0,
        surfaceTintColor: transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceRaised,
        modalBackgroundColor: c.surfaceRaised,
        surfaceTintColor: transparent,
        elevation: 0,
        modalElevation: 0,
        modalBarrierColor: c.scrim,
        showDragHandle: true,
        dragHandleColor: c.lineStrong,
        dragHandleSize: const Size(40, 5),
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(borderRadius: AknRadius.sheet),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AknRadius.dialog),
        titleTextStyle: t.headline.copyWith(fontWeight: FontWeight.w800),
        contentTextStyle: t.body,
        barrierColor: c.scrim,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: inverse,
        contentTextStyle: t.body.copyWith(color: white),
        actionTextColor: const Color(0xFFFF8A4C),
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AknRadius.md)),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.lineSoft, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: c.dim,
        textColor: c.ink,
        titleTextStyle: t.bodyStrong,
        subtitleTextStyle: t.bodySmall,
        leadingAndTrailingTextStyle: t.caption,
        selectedColor: c.brandInk,
        selectedTileColor: c.brandSoft,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        minVerticalPadding: 10,
        shape: const RoundedRectangleBorder(borderRadius: AknRadius.input),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.ink,
        unselectedLabelColor: c.dim,
        labelStyle: t.label.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle: t.label.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: c.brandBright, width: 3),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        ),
        dividerColor: c.lineSoft,
        overlayColor: WidgetStatePropertyAll<Color>(
          c.ink.withValues(alpha: 0.04),
        ),
        splashFactory: InkRipple.splashFactory,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => selected(s) ? white : (dark ? c.text : white),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => disabled(s)
              ? c.lineSoft
              : selected(s)
              ? c.brandFill
              : c.lineStrong,
        ),
        trackOutlineColor: const WidgetStatePropertyAll<Color>(transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) =>
              selected(s) ? (disabled(s) ? c.faint : c.brandFill) : transparent,
        ),
        checkColor: const WidgetStatePropertyAll<Color>(white),
        side: BorderSide(color: c.lineStrong, width: 1.6),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => selected(s) ? c.brandFill : c.lineStrong,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.brandBright,
        inactiveTrackColor: c.isDark ? c.line : c.surfaceAlt,
        thumbColor: c.brandFill,
        overlayColor: c.brand.withValues(alpha: 0.14),
        valueIndicatorColor: inverse,
        valueIndicatorTextStyle: t.label.copyWith(color: white),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.brandBright,
        linearTrackColor: c.isDark ? c.line : c.surfaceAlt,
        circularTrackColor: transparent,
        refreshBackgroundColor: c.surfaceRaised,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: inverse,
          borderRadius: const BorderRadius.all(Radius.circular(AknRadius.sm)),
        ),
        textStyle: t.caption.copyWith(color: white),
        waitDuration: const Duration(milliseconds: 500),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceRaised,
        surfaceTintColor: transparent,
        elevation: 4,
        shadowColor: const Color(0x33101828),
        textStyle: t.body.copyWith(color: c.ink),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(AknRadius.md)),
          side: BorderSide(color: c.line),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll<Color>(c.surfaceRaised),
          surfaceTintColor: const WidgetStatePropertyAll<Color>(transparent),
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(
                Radius.circular(AknRadius.md),
              ),
              side: BorderSide(color: c.line),
            ),
          ),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AknRadius.dialog),
        headerBackgroundColor: c.surfaceRaised,
        headerForegroundColor: c.ink,
        headerHeadlineStyle: t.title,
        headerHelpStyle: t.label.copyWith(color: c.dim),
        weekdayStyle: t.captionStrong,
        dayStyle: t.body,
        dayForegroundColor: WidgetStateProperty.resolveWith(
          (s) => selected(s)
              ? white
              : disabled(s)
              ? c.faint
              : c.ink,
        ),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (s) => selected(s) ? c.brandFill : transparent,
        ),
        dayOverlayColor: WidgetStatePropertyAll<Color>(c.brandSoft),
        todayForegroundColor: WidgetStateProperty.resolveWith(
          (s) => selected(s) ? white : c.brandInk,
        ),
        todayBackgroundColor: WidgetStateProperty.resolveWith(
          (s) => selected(s) ? c.brandFill : transparent,
        ),
        todayBorder: BorderSide(color: c.brand, width: 1.4),
        yearForegroundColor: WidgetStateProperty.resolveWith(
          (s) => selected(s) ? white : c.ink,
        ),
        yearBackgroundColor: WidgetStateProperty.resolveWith(
          (s) => selected(s) ? c.brandFill : transparent,
        ),
        dividerColor: c.lineSoft,
        cancelButtonStyle: textStyle,
        confirmButtonStyle: textStyle,
        inputDecorationTheme: InputDecorationThemeData(
          filled: true,
          fillColor: c.surfaceAlt,
          border: noBorder,
          enabledBorder: noBorder,
          focusedBorder: noBorder.copyWith(
            borderSide: BorderSide(color: c.brand, width: 2),
          ),
        ),
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
          (s) => selected(s) ? c.brandSoft : c.surfaceAlt,
        ),
        hourMinuteTextColor: WidgetStateColor.resolveWith(
          (s) => selected(s) ? c.brandInk : c.ink,
        ),
        dayPeriodShape: const RoundedRectangleBorder(
          borderRadius: AknRadius.input,
        ),
        dayPeriodColor: WidgetStateColor.resolveWith(
          (s) => selected(s) ? c.brandSoft : transparent,
        ),
        dayPeriodTextColor: WidgetStateColor.resolveWith(
          (s) => selected(s) ? c.brandInk : c.text,
        ),
        dayPeriodBorderSide: BorderSide(color: c.lineStrong),
        dialBackgroundColor: c.surfaceAlt,
        dialHandColor: c.brandFill,
        dialTextColor: WidgetStateColor.resolveWith(
          (s) => selected(s) ? white : c.ink,
        ),
        entryModeIconColor: c.dim,
        cancelButtonStyle: textStyle,
        confirmButtonStyle: textStyle,
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
      badgeTheme: BadgeThemeData(
        backgroundColor: c.dangerFill,
        textColor: c.onDangerFill,
        smallSize: 8,
        largeSize: 18,
        textStyle: t.captionStrong.copyWith(
          color: c.onDangerFill,
          fontSize: 11,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 5),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: transparent,
        elevation: 0,
        indicatorColor: c.brandSoft,
        indicatorShape: pill,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: selected(s) ? c.brand : c.dim, size: 24),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => t.captionStrong.copyWith(
            color: selected(s) ? c.brandInk : c.dim,
            fontWeight: selected(s) ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll<TextStyle>(t.label),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => selected(s) ? c.brandSoft : c.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => selected(s) ? c.brandInk : c.text,
          ),
          side: WidgetStatePropertyAll<BorderSide>(BorderSide(color: c.line)),
          shape: const WidgetStatePropertyAll<OutlinedBorder>(pill),
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
    );
  }

  /// App bar title: 20/26 w800, tight tracking.
  static TextStyle appBarTitle(AknTextStyles t) => t.headline.copyWith(
    fontSize: 20,
    height: 26 / 20,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
  );
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

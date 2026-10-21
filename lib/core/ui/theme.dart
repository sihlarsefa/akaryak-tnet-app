import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'motion.dart';
import 'tokens.dart';
import 'typography.dart';

/// Light and dark [ThemeData] for AkaryakıtNet (spec C.5).
///
/// ```dart
/// MaterialApp.router(
///   theme: AknTheme.light(),
///   darkTheme: AknTheme.dark(),
///   themeMode: themeMode, // Sistem / Açık / Koyu
/// )
/// ```
///
/// Stock Material widgets pick up the identity through the component themes;
/// AkaryakıtNet widgets read tokens with `context.akn` and `context.aknText`.
abstract final class AknTheme {
  static ThemeData light() => build(AknColors.light);

  static ThemeData dark() => build(AknColors.dark);

  static ThemeData of(Brightness brightness) =>
      brightness == Brightness.dark ? dark() : light();

  /// Status bar icons for content on [bg] / [surface].
  static SystemUiOverlayStyle overlayFor(Brightness brightness) =>
      (brightness == Brightness.dark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark)
          .copyWith(
            statusBarColor: const Color(0x00000000),
            systemNavigationBarColor: const Color(0x00000000),
            systemNavigationBarDividerColor: const Color(0x00000000),
          );

  /// Status bar icons on navy headers and the splash (always light).
  static const SystemUiOverlayStyle overlayOnNavy = SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarBrightness: Brightness.dark,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0x00000000),
    systemNavigationBarIconBrightness: Brightness.light,
  );

  static ThemeData build(AknColors c) {
    final t = AknTextStyles.from(c);
    final dark = c.isDark;
    const white = Color(0xFFFFFFFF);
    const nearBlack = Color(0xFF0B1220);

    final scheme = ColorScheme(
      brightness: c.brightness,
      primary: c.brand,
      onPrimary: dark ? const Color(0xFF1A0D05) : white,
      primaryContainer: c.brandSoft,
      onPrimaryContainer: c.brandInk,
      secondary: dark ? const Color(0xFFCBD5E1) : c.navy,
      onSecondary: dark ? nearBlack : white,
      secondaryContainer: c.surfaceAlt,
      onSecondaryContainer: c.ink,
      tertiary: c.info.fg,
      onTertiary: dark ? nearBlack : white,
      tertiaryContainer: c.info.bg,
      onTertiaryContainer: c.info.fg,
      error: c.danger.fg,
      onError: dark ? nearBlack : white,
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
      inverseSurface: dark ? const Color(0xFFE2E8F0) : c.navy,
      onInverseSurface: dark ? const Color(0xFF0F172A) : white,
      inversePrimary: dark ? const Color(0xFFC94C0C) : const Color(0xFFF08A55),
      surfaceTint: const Color(0x00000000),
    );

    const radius12 = RoundedRectangleBorder(borderRadius: AknRadius.card);
    final buttonText = WidgetStatePropertyAll<TextStyle>(t.button);
    const buttonPadding = WidgetStatePropertyAll<EdgeInsetsGeometry>(
      EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    );
    const buttonMin = WidgetStatePropertyAll<Size>(Size(64, 48));

    bool disabled(Set<WidgetState> s) => s.contains(WidgetState.disabled);
    bool pressed(Set<WidgetState> s) => s.contains(WidgetState.pressed);

    final filledStyle = ButtonStyle(
      textStyle: buttonText,
      padding: buttonPadding,
      minimumSize: buttonMin,
      elevation: const WidgetStatePropertyAll<double>(0),
      shape: const WidgetStatePropertyAll<OutlinedBorder>(radius12),
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => disabled(s)
            ? c.lineSoft
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
      shape: const WidgetStatePropertyAll<OutlinedBorder>(radius12),
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => disabled(s)
            ? c.surface
            : pressed(s)
            ? c.surfaceAlt
            : c.surface,
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

    final inputBorder = OutlineInputBorder(
      borderRadius: AknRadius.input,
      borderSide: BorderSide(color: c.lineStrong),
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
      appBarTheme: AppBarThemeData(
        backgroundColor: WidgetStateColor.resolveWith(
          (s) => s.contains(WidgetState.scrolledUnder) ? c.surface : c.bg,
        ),
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: dark ? const Color(0xFF000000) : c.line,
        surfaceTintColor: const Color(0x00000000),
        centerTitle: false,
        titleSpacing: 16,
        toolbarHeight: 56,
        titleTextStyle: t.headline,
        iconTheme: IconThemeData(color: c.ink, size: 24),
        actionsIconTheme: IconThemeData(color: c.ink, size: 24),
        systemOverlayStyle: overlayFor(c.brightness),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: const Color(0x00000000),
        shadowColor: c.shadow,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: AknRadius.card,
          side: BorderSide(color: c.line),
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
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        highlightElevation: 3,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AknRadius.lg)),
        ),
        extendedTextStyle: t.button,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: dark ? c.surfaceAlt : c.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        disabledBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: c.line),
        ),
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: c.brand, width: 1.6),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: c.danger.fg),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: c.danger.fg, width: 1.6),
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
        selectedColor: c.brandSoft,
        disabledColor: c.surfaceAlt,
        checkmarkColor: c.brandInk,
        deleteIconColor: c.dim,
        labelStyle: t.label.copyWith(color: c.text),
        secondaryLabelStyle: t.label.copyWith(color: c.brandInk),
        side: BorderSide(color: c.lineStrong),
        shape: const RoundedRectangleBorder(borderRadius: AknRadius.chip),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        showCheckmark: false,
        elevation: 0,
        pressElevation: 0,
        surfaceTintColor: const Color(0x00000000),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceRaised,
        modalBackgroundColor: c.surfaceRaised,
        surfaceTintColor: const Color(0x00000000),
        elevation: 0,
        modalElevation: 0,
        modalBarrierColor: c.scrim,
        showDragHandle: true,
        dragHandleColor: c.lineStrong,
        dragHandleSize: const Size(36, 4),
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(borderRadius: AknRadius.sheet),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: const Color(0x00000000),
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AknRadius.dialog),
        titleTextStyle: t.headline,
        contentTextStyle: t.body,
        barrierColor: c.scrim,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? const Color(0xFF243043) : c.navy,
        contentTextStyle: t.body.copyWith(color: white),
        actionTextColor: const Color(0xFFF08A55),
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: const RoundedRectangleBorder(borderRadius: AknRadius.card),
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
        shape: const RoundedRectangleBorder(borderRadius: AknRadius.card),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.ink,
        unselectedLabelColor: c.dim,
        labelStyle: t.label.copyWith(fontSize: 14),
        unselectedLabelStyle: t.label.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        indicatorSize: TabBarIndicatorSize.label,
        indicator: UnderlineTabIndicator(
          borderSide: BorderSide(color: c.brand, width: 2.5),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
        ),
        dividerColor: c.lineSoft,
        overlayColor: WidgetStatePropertyAll<Color>(
          c.ink.withValues(alpha: 0.04),
        ),
        splashFactory: InkRipple.splashFactory,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? white : c.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => disabled(s)
              ? c.lineSoft
              : s.contains(WidgetState.selected)
              ? c.brandFill
              : c.lineStrong,
        ),
        trackOutlineColor: const WidgetStatePropertyAll<Color>(
          Color(0x00000000),
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? (disabled(s) ? c.faint : c.brandFill)
              : const Color(0x00000000),
        ),
        checkColor: const WidgetStatePropertyAll<Color>(white),
        side: BorderSide(color: c.lineStrong, width: 1.6),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(5)),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.brand : c.lineStrong,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.brand,
        linearTrackColor: c.lineSoft,
        circularTrackColor: const Color(0x00000000),
        refreshBackgroundColor: c.surfaceRaised,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF2B3747) : c.navy,
          borderRadius: AknRadius.chip,
        ),
        textStyle: t.caption.copyWith(color: white),
        waitDuration: const Duration(milliseconds: 500),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceRaised,
        surfaceTintColor: const Color(0x00000000),
        elevation: 3,
        shadowColor: const Color(0x33000000),
        textStyle: t.body.copyWith(color: c.ink),
        shape: RoundedRectangleBorder(
          borderRadius: AknRadius.card,
          side: BorderSide(color: c.line),
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: const Color(0x00000000),
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AknRadius.dialog),
        headerBackgroundColor: c.surfaceRaised,
        headerForegroundColor: c.ink,
        headerHeadlineStyle: t.title,
        headerHelpStyle: t.label.copyWith(color: c.dim),
        weekdayStyle: t.captionStrong,
        dayStyle: t.body,
        dayForegroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? white
              : disabled(s)
              ? c.faint
              : c.ink,
        ),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? c.brandFill
              : const Color(0x00000000),
        ),
        todayForegroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? white : c.brandInk,
        ),
        todayBackgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? c.brandFill
              : const Color(0x00000000),
        ),
        todayBorder: BorderSide(color: c.brand),
        yearForegroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? white : c.ink,
        ),
        yearBackgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? c.brandFill
              : const Color(0x00000000),
        ),
        dividerColor: c.lineSoft,
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
        backgroundColor: c.brandFill,
        textColor: white,
        smallSize: 8,
        largeSize: 18,
        textStyle: t.captionStrong.copyWith(color: white, fontSize: 11),
        padding: const EdgeInsets.symmetric(horizontal: 5),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll<TextStyle>(t.label),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.brandSoft : c.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.brandInk : c.text,
          ),
          side: WidgetStatePropertyAll<BorderSide>(
            BorderSide(color: c.lineStrong),
          ),
          shape: const WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(borderRadius: AknRadius.chip),
          ),
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

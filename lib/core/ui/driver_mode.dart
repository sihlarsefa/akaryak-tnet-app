import 'package:flutter/material.dart';

import 'theme.dart';
import 'tokens.dart';
import 'typography.dart';

/// Driver mode — design v3 (from v2 §6.30 and §3.4): the cab version of the
/// app for gloved hands, sunlight and a phone on a dashboard mount.
///
/// Applied by the driver shell (driver-only users) and by the driver flow
/// pages for anyone, through [AknDriverScope] (or [AknDriverMode.theme]):
///
/// * type one step larger: display 34/40, title 22/28, headline 20/26 (stop
///   name 24/30, [stopName]), body 17/24, bodySmall 15/20, label 15/20,
///   button 16/20 (the standard), navLabel 12/15, plateFigure 56/60, plateUnit 28, number
///   28/32 (plate readouts 28/32 with 15/20 labels);
/// * buttons at the app's standard size (owner, 2026-10-30: the 64 px cab
///   buttons were needlessly big): 48 high, superellipse radius 16, a 16/20
///   label and 20 px icons, a 48 dp touch target; other touch targets
///   (icon buttons, rows, chips) stay 64; bottom-bar items 64 with 26 px
///   icons; list rows at least 76 high; the TR plate badge 32 high;
/// * fields 64 high with 17/24 text (`AknTextField`; the money and litre
///   figures 26/32), chips 44 high in a 64 target, the segmented track 48.
///
/// "Cab night" (dark driver mode) uses the dark tokens as they are: the
/// primary keeps its orange gradient, white label and glow; nothing else
/// turns orange. The press, selection and loading motion is the same as
/// everywhere else (v3 §5), only bigger.
///
/// Widgets read the numbers with [AknDriverMode.maybeOf] /
/// `context.driverMode`; text styles arrive already enlarged through
/// `context.aknText`.
@immutable
class AknDriverMode extends ThemeExtension<AknDriverMode> {
  const AknDriverMode({
    this.minTap = AknSpace.driverTap,
    this.buttonHeight = 48,
    this.buttonRadius = 16,
    this.buttonIconSize = 20,
    this.fieldHeight = 64,
    this.navItemHeight = 64,
    this.navIconSize = 26,
    this.rowMinHeight = 76,
    this.plateBadgeHeight = 32,
  });

  /// The values of §6.30.
  static const AknDriverMode standard = AknDriverMode();

  /// Minimum touch target (64).
  final double minTap;

  /// Every regular button (primary, secondary, ghost) is this high (48, the
  /// app's standard; small buttons stay 40).
  final double buttonHeight;

  /// Button corner radius (16, as everywhere else).
  final double buttonRadius;

  /// Button icon size (20).
  final double buttonIconSize;

  /// Text field height (64: typing on a dashboard mount).
  final double fieldHeight;

  /// Bottom-bar item height (64).
  final double navItemHeight;

  /// Bottom-bar icon size (26).
  final double navIconSize;

  /// Minimum list-row height (76).
  final double rowMinHeight;

  /// TR licence-plate badge height (32; 28 elsewhere).
  final double plateBadgeHeight;

  /// The driver mode in effect at [context], or null outside it.
  static AknDriverMode? maybeOf(BuildContext context) =>
      Theme.of(context).extension<AknDriverMode>();

  /// True inside driver mode.
  static bool isOn(BuildContext context) => maybeOf(context) != null;

  /// The minimum touch target at [context]: 64 in driver mode, else 48.
  static double minTapOf(BuildContext context) =>
      maybeOf(context)?.minTap ?? AknSpace.minTap;

  /// The scale of §3.4: [t] one step larger (colours, families and weights
  /// kept). Applying it twice changes nothing more than applying it once.
  static AknTextStyles textStyles(AknTextStyles t) {
    TextStyle s(TextStyle base, double size, double line) =>
        base.copyWith(fontSize: size, height: line / size);
    return t.copyWith(
      display: s(t.display, 34, 40),
      title: s(t.title, 22, 28),
      headline: s(t.headline, 20, 26),
      body: s(t.body, 17, 24),
      bodyStrong: s(t.bodyStrong, 17, 24),
      bodySmall: s(t.bodySmall, 15, 20),
      label: s(t.label, 15, 20),
      caption: s(t.caption, 13, 18),
      captionStrong: s(t.captionStrong, 13, 18),
      overline: s(t.overline, 13, 18),
      amount: s(t.amount, 20, 26),
      amountLarge: s(t.amountLarge, 30, 34),
      number: s(t.number, 28, 32),
      numberLarge: s(t.numberLarge, 36, 40),
      button: s(t.button, 16, 20),
      plateFigure: s(t.plateFigure, 56, 60),
      plateUnit: s(t.plateUnit, 28, 32),
      figureWord: s(t.figureWord, 22, 26),
      readoutUnit: s(t.readoutUnit, 17, 32),
      navLabel: s(t.navLabel, 12, 15),
    );
  }

  /// The stop name on "Teslimatlarım": headline at 24/30 (§3.4, §7.11).
  static TextStyle stopName(AknTextStyles t) =>
      t.headline.copyWith(fontSize: 24, height: 30 / 24);

  /// [theme] in driver mode: the extension itself, the §3.4 text styles
  /// (also as the Material text theme), 48 px superellipse buttons with
  /// radius 16 ([buttonRadius]), a 16/20 w700 label and 20 px icons, 64 px
  /// icon buttons, 64 px inputs, 76 px list rows, 44 px chips and 64 px
  /// navigation items (the active one w700 on its soft orange pill).
  /// Colours, shadows and motion stay those of the v3 theme. Idempotent.
  static ThemeData theme(ThemeData theme, {AknDriverMode mode = standard}) {
    if (theme.extension<AknDriverMode>() != null) return theme;
    final c = theme.extension<AknColors>() ?? AknColors.light;
    final t = textStyles(
      theme.extension<AknTextStyles>() ?? AknTextStyles.from(c),
    );
    final radius = BorderRadius.all(Radius.circular(mode.buttonRadius));
    final shape = WidgetStatePropertyAll<OutlinedBorder>(
      RoundedSuperellipseBorder(borderRadius: radius),
    );
    // The primary's gradient is painted inside its shape: give it the
    // driver radius too.
    final gradient = AknTheme.primaryButtonStyle(
      c,
      t,
      radius: radius,
    ).backgroundBuilder;
    ButtonStyle big(ButtonStyle? s, {bool primary = false}) =>
        (s ?? const ButtonStyle()).copyWith(
          textStyle: WidgetStatePropertyAll<TextStyle>(t.button),
          minimumSize: WidgetStatePropertyAll<Size>(
            Size(64, mode.buttonHeight),
          ),
          iconSize: WidgetStatePropertyAll<double>(mode.buttonIconSize),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          shape: shape,
          backgroundBuilder: primary ? gradient : null,
        );
    final inputs = theme.inputDecorationTheme;
    return theme.copyWith(
      extensions: theme.extensions.values
          .where((e) => e is! AknTextStyles && e is! AknDriverMode)
          .followedBy([t, mode]),
      textTheme: t.toTextTheme(),
      filledButtonTheme: FilledButtonThemeData(
        style: big(theme.filledButtonTheme.style, primary: true),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: big(theme.elevatedButtonTheme.style, primary: true),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: big(theme.outlinedButtonTheme.style),
      ),
      textButtonTheme: TextButtonThemeData(
        style: big(theme.textButtonTheme.style),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: (theme.iconButtonTheme.style ?? const ButtonStyle()).copyWith(
          minimumSize: WidgetStatePropertyAll<Size>(
            Size(mode.minTap, mode.minTap),
          ),
          iconSize: const WidgetStatePropertyAll<double>(26),
        ),
      ),
      inputDecorationTheme: inputs.copyWith(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 20,
        ),
        hintStyle: inputs.hintStyle?.copyWith(fontSize: 17, height: 24 / 17),
        labelStyle: inputs.labelStyle?.copyWith(fontSize: 15, height: 20 / 15),
        errorStyle: inputs.errorStyle?.copyWith(fontSize: 15, height: 20 / 15),
        helperStyle: inputs.helperStyle?.copyWith(
          fontSize: 15,
          height: 20 / 15,
        ),
        suffixStyle: inputs.suffixStyle?.copyWith(
          fontSize: 17,
          height: 24 / 17,
        ),
      ),
      listTileTheme: theme.listTileTheme.copyWith(
        minTileHeight: mode.rowMinHeight,
        titleTextStyle: t.headline,
        subtitleTextStyle: t.bodySmall,
        leadingAndTrailingTextStyle: t.bodySmall,
      ),
      chipTheme: theme.chipTheme.copyWith(
        labelStyle: theme.chipTheme.labelStyle?.copyWith(
          fontSize: 15,
          height: 20 / 15,
        ),
        secondaryLabelStyle: theme.chipTheme.secondaryLabelStyle?.copyWith(
          fontSize: 15,
          height: 20 / 15,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      ),
      tabBarTheme: theme.tabBarTheme.copyWith(
        labelStyle: t.button,
        unselectedLabelStyle: t.button,
      ),
      navigationBarTheme: theme.navigationBarTheme.copyWith(
        height: mode.navItemHeight,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => t.navLabel.copyWith(
            color: s.contains(WidgetState.selected) ? c.ink : c.navInactive,
            fontWeight: s.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w600,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected) ? c.ink : c.navInactive,
            size: mode.navIconSize,
          ),
        ),
      ),
      snackBarTheme: theme.snackBarTheme.copyWith(
        contentTextStyle: theme.snackBarTheme.contentTextStyle?.copyWith(
          fontSize: 17,
          height: 24 / 17,
        ),
      ),
      dialogTheme: theme.dialogTheme.copyWith(
        titleTextStyle: t.title,
        contentTextStyle: t.body,
      ),
      appBarTheme: theme.appBarTheme.copyWith(
        titleTextStyle: t.headline,
        toolbarHeight: 60,
      ),
    );
  }

  @override
  AknDriverMode copyWith({
    double? minTap,
    double? buttonHeight,
    double? buttonRadius,
    double? buttonIconSize,
    double? fieldHeight,
    double? navItemHeight,
    double? navIconSize,
    double? rowMinHeight,
    double? plateBadgeHeight,
  }) => AknDriverMode(
    minTap: minTap ?? this.minTap,
    buttonHeight: buttonHeight ?? this.buttonHeight,
    buttonRadius: buttonRadius ?? this.buttonRadius,
    buttonIconSize: buttonIconSize ?? this.buttonIconSize,
    fieldHeight: fieldHeight ?? this.fieldHeight,
    navItemHeight: navItemHeight ?? this.navItemHeight,
    navIconSize: navIconSize ?? this.navIconSize,
    rowMinHeight: rowMinHeight ?? this.rowMinHeight,
    plateBadgeHeight: plateBadgeHeight ?? this.plateBadgeHeight,
  );

  @override
  AknDriverMode lerp(covariant ThemeExtension<AknDriverMode>? other, double t) {
    if (other is! AknDriverMode) return this;
    double l(double a, double b) => a + (b - a) * t;
    return AknDriverMode(
      minTap: l(minTap, other.minTap),
      buttonHeight: l(buttonHeight, other.buttonHeight),
      buttonRadius: l(buttonRadius, other.buttonRadius),
      buttonIconSize: l(buttonIconSize, other.buttonIconSize),
      fieldHeight: l(fieldHeight, other.fieldHeight),
      navItemHeight: l(navItemHeight, other.navItemHeight),
      navIconSize: l(navIconSize, other.navIconSize),
      rowMinHeight: l(rowMinHeight, other.rowMinHeight),
      plateBadgeHeight: l(plateBadgeHeight, other.plateBadgeHeight),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AknDriverMode &&
      other.minTap == minTap &&
      other.buttonHeight == buttonHeight &&
      other.buttonRadius == buttonRadius &&
      other.buttonIconSize == buttonIconSize &&
      other.fieldHeight == fieldHeight &&
      other.navItemHeight == navItemHeight &&
      other.navIconSize == navIconSize &&
      other.rowMinHeight == rowMinHeight &&
      other.plateBadgeHeight == plateBadgeHeight;

  @override
  int get hashCode => Object.hash(
    minTap,
    buttonHeight,
    buttonRadius,
    buttonIconSize,
    fieldHeight,
    navItemHeight,
    navIconSize,
    rowMinHeight,
    plateBadgeHeight,
  );
}

/// Puts its subtree in driver mode (§6.30). Nested scopes are harmless.
///
/// ```dart
/// AknDriverScope(child: DriverShell(...))
/// ```
class AknDriverScope extends StatelessWidget {
  const AknDriverScope({
    super.key,
    required this.child,
    this.enabled = true,
    this.mode = AknDriverMode.standard,
  });

  final Widget child;

  /// False renders [child] as it is (e.g. a driver page opened by an office
  /// user who turned the mode off).
  final bool enabled;
  final AknDriverMode mode;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final theme = Theme.of(context);
    if (theme.extension<AknDriverMode>() != null) return child;
    return Theme(
      data: AknDriverMode.theme(theme, mode: mode),
      child: child,
    );
  }
}

/// `context.driverMode` / `context.isDriverMode`.
extension AknDriverModeContext on BuildContext {
  /// The driver mode in effect, or null.
  AknDriverMode? get driverMode => AknDriverMode.maybeOf(this);

  /// True inside driver mode.
  bool get isDriverMode => AknDriverMode.maybeOf(this) != null;

  /// Minimum touch target here (64 in driver mode, else 48).
  double get minTap => AknDriverMode.minTapOf(this);
}

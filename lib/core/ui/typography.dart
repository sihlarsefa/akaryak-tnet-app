import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

/// Type scale (spec C.5) on the platform font (SF Pro / Roboto):
/// display 32/40 w700, title 22/28 w700, headline 18/24 w600,
/// body 15/22 w400, label 13/18 w600, caption 12/16.
///
/// Amounts use tabular figures so columns of numbers line up and counters do
/// not jitter. Read with `context.aknText`.
@immutable
class AknTextStyles extends ThemeExtension<AknTextStyles> {
  const AknTextStyles({
    required this.display,
    required this.title,
    required this.headline,
    required this.body,
    required this.bodyStrong,
    required this.bodySmall,
    required this.label,
    required this.caption,
    required this.captionStrong,
    required this.overline,
    required this.amount,
    required this.amountLarge,
    required this.button,
  });

  /// [platform] picks the platform font family (SF Pro display/text on iOS,
  /// Roboto elsewhere), so every style renders in the system face even where
  /// a widget replaces the inherited text style.
  factory AknTextStyles.from(AknColors c, {TargetPlatform? platform}) {
    final typo = Typography.material2021(
      platform: platform ?? defaultTargetPlatform,
    ).black;
    final displayFamily = typo.displaySmall?.fontFamily;
    final textFamily = typo.bodyMedium?.fontFamily;
    TextStyle d(TextStyle s) => s.copyWith(fontFamily: displayFamily);
    TextStyle x(TextStyle s) => s.copyWith(fontFamily: textFamily);
    final r = AknTextStyles._raw(c);
    return AknTextStyles(
      display: d(r.display),
      title: d(r.title),
      headline: x(r.headline),
      body: x(r.body),
      bodyStrong: x(r.bodyStrong),
      bodySmall: x(r.bodySmall),
      label: x(r.label),
      caption: x(r.caption),
      captionStrong: x(r.captionStrong),
      overline: x(r.overline),
      amount: x(r.amount),
      amountLarge: d(r.amountLarge),
      button: x(r.button),
    );
  }

  factory AknTextStyles._raw(AknColors c) {
    const tabular = [FontFeature.tabularFigures()];
    return AknTextStyles(
      display: TextStyle(
        fontSize: 32,
        height: 40 / 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        color: c.ink,
      ),
      title: TextStyle(
        fontSize: 22,
        height: 28 / 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: c.ink,
      ),
      headline: TextStyle(
        fontSize: 18,
        height: 24 / 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: c.ink,
      ),
      body: TextStyle(
        fontSize: 15,
        height: 22 / 15,
        fontWeight: FontWeight.w400,
        color: c.text,
      ),
      bodyStrong: TextStyle(
        fontSize: 15,
        height: 22 / 15,
        fontWeight: FontWeight.w600,
        color: c.ink,
      ),
      bodySmall: TextStyle(
        fontSize: 13,
        height: 18 / 13,
        fontWeight: FontWeight.w400,
        color: c.dim,
      ),
      label: TextStyle(
        fontSize: 13,
        height: 18 / 13,
        fontWeight: FontWeight.w600,
        color: c.text,
      ),
      caption: TextStyle(
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w400,
        color: c.dim,
      ),
      captionStrong: TextStyle(
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w600,
        color: c.dim,
      ),
      overline: TextStyle(
        fontSize: 11,
        height: 14 / 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: c.dim,
      ),
      amount: TextStyle(
        fontSize: 15,
        height: 22 / 15,
        fontWeight: FontWeight.w600,
        fontFeatures: tabular,
        color: c.ink,
      ),
      amountLarge: TextStyle(
        fontSize: 28,
        height: 34 / 28,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        fontFeatures: tabular,
        color: c.ink,
      ),
      button: const TextStyle(
        fontSize: 15,
        height: 20 / 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
    );
  }

  final TextStyle display;
  final TextStyle title;
  final TextStyle headline;
  final TextStyle body;
  final TextStyle bodyStrong;
  final TextStyle bodySmall;
  final TextStyle label;
  final TextStyle caption;
  final TextStyle captionStrong;

  /// Small section labels ("BUGÜN"). Write the text already in Turkish upper
  /// case (`TurkishText.upper` in `core/utils`), never `toUpperCase`.
  final TextStyle overline;

  /// Amounts and litres in lists (tabular figures).
  final TextStyle amount;

  /// Hero amounts and KPI values (tabular figures).
  final TextStyle amountLarge;
  final TextStyle button;

  /// Material [TextTheme] carrying the same scale, so stock widgets match.
  static TextTheme textTheme(AknColors c) {
    final s = AknTextStyles.from(c);
    return TextTheme(
      displayLarge: s.display.copyWith(fontSize: 40, height: 48 / 40),
      displayMedium: s.display.copyWith(fontSize: 36, height: 44 / 36),
      displaySmall: s.display,
      headlineLarge: s.title.copyWith(fontSize: 28, height: 36 / 28),
      headlineMedium: s.title.copyWith(fontSize: 24, height: 32 / 24),
      headlineSmall: s.title,
      titleLarge: s.title,
      titleMedium: s.headline,
      titleSmall: s.bodyStrong,
      bodyLarge: s.body.copyWith(fontSize: 16, height: 24 / 16, color: c.ink),
      bodyMedium: s.body,
      bodySmall: s.caption,
      labelLarge: s.button.copyWith(color: c.ink),
      labelMedium: s.label,
      labelSmall: s.captionStrong,
    );
  }

  @override
  AknTextStyles copyWith({
    TextStyle? display,
    TextStyle? title,
    TextStyle? headline,
    TextStyle? body,
    TextStyle? bodyStrong,
    TextStyle? bodySmall,
    TextStyle? label,
    TextStyle? caption,
    TextStyle? captionStrong,
    TextStyle? overline,
    TextStyle? amount,
    TextStyle? amountLarge,
    TextStyle? button,
  }) {
    return AknTextStyles(
      display: display ?? this.display,
      title: title ?? this.title,
      headline: headline ?? this.headline,
      body: body ?? this.body,
      bodyStrong: bodyStrong ?? this.bodyStrong,
      bodySmall: bodySmall ?? this.bodySmall,
      label: label ?? this.label,
      caption: caption ?? this.caption,
      captionStrong: captionStrong ?? this.captionStrong,
      overline: overline ?? this.overline,
      amount: amount ?? this.amount,
      amountLarge: amountLarge ?? this.amountLarge,
      button: button ?? this.button,
    );
  }

  @override
  AknTextStyles lerp(covariant ThemeExtension<AknTextStyles>? other, double t) {
    if (other is! AknTextStyles) return this;
    TextStyle l(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return AknTextStyles(
      display: l(display, other.display),
      title: l(title, other.title),
      headline: l(headline, other.headline),
      body: l(body, other.body),
      bodyStrong: l(bodyStrong, other.bodyStrong),
      bodySmall: l(bodySmall, other.bodySmall),
      label: l(label, other.label),
      caption: l(caption, other.caption),
      captionStrong: l(captionStrong, other.captionStrong),
      overline: l(overline, other.overline),
      amount: l(amount, other.amount),
      amountLarge: l(amountLarge, other.amountLarge),
      button: l(button, other.button),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// The two bundled faces (design v2 §3.1): Mona Sans v2.0.27 static TTFs,
/// SIL OFL 1.1, unmodified upstream files in `assets/fonts/mona/`.
abstract final class AknFonts {
  /// Ledger voice — words (400, 500, 600, 700).
  static const String sans = 'MonaSans';

  /// Counter voice — figures (Condensed 600, 700, 800).
  static const String condensed = 'MonaSansCondensed';

  /// Every style is shaped as Turkish (`locl`: İ/ı, Ş, Ğ …).
  static const Locale locale = Locale('tr', 'TR');

  /// The bundled licence text (SIL OFL 1.1, Reserved Font Name "Mona").
  static const String licenseAsset = 'assets/fonts/mona/OFL.txt';

  /// Registers the Mona Sans licence with [LicenseRegistry] so it shows on
  /// the "Lisanslar" page (§3.1). Call once in `main()`, before `runApp`;
  /// the text is read only when the licences are requested.
  static void registerLicense() {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(const [
        'Mona Sans',
      ], await rootBundle.loadString(licenseAsset));
    });
  }
}

/// Numerals (design v2 §3.3): proportional lining figures only — never
/// `tabularFigures` (Mona's `tnum` digits are code-styled). Things that tick
/// (countdowns, the counter roll) sit in a fixed-width box measured once
/// from the widest expected string and right-aligned inside it; units are a
/// smaller `TextSpan` in the same `Text.rich`, after a thin gap.
abstract final class AknNumerals {
  /// The widest countdown ("2 sa 57 dk kaldı" never grows past this).
  static const String countdownSample = '88 sa 88 dk kaldı';

  /// Gap between a plate figure and its `plateUnit`.
  static const double plateUnitGap = 6;

  /// Gap between a readout `number` and its `readoutUnit`.
  static const double readoutUnitGap = 3;

  /// Width of [sample] set in [style] at [textScaler]: the fixed box for a
  /// value that ticks. Measure once (e.g. in `didChangeDependencies`).
  static double fixedWidth(
    String sample,
    TextStyle style, {
    TextScaler textScaler = TextScaler.noScaling,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: sample, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width.ceilToDouble();
  }
}

/// Type scale on Mona Sans, two voices (design v2 §3.2):
///
/// * ledger voice (`MonaSans`) for words: display 30/36 600, title 20/26 600,
///   headline 17/22 600, body 15/22, bodySmall 14/20, label 13/18 500,
///   caption 12/16;
/// * counter voice (`MonaSansCondensed`) for figures: number 24/28 700,
///   amountLarge 28/32 700, numberLarge 34/38 800 and the plate's
///   `plateFigure` 58/58 800 + `plateUnit` 30/30 700.
///
/// **Proportional lining figures only**: no style enables tabular figures
/// (Mona's `tnum` digits are code-styled — dotted 0, slab 1). Columns align
/// by their right edge; things that tick sit in fixed-width boxes (§3.3).
///
/// Every style sets `leadingDistribution: even` (Mona's ascent is tall) and
/// the Turkish locale. Read with `context.aknText`.
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
    required this.number,
    required this.numberLarge,
    required this.button,
    required this.plateFigure,
    required this.plateUnit,
    required this.figureWord,
    required this.readoutUnit,
    required this.navLabel,
  });

  /// The scale coloured from [c]. Build it from `c.plateInk()` and every
  /// style prints black on the plate.
  ///
  /// [platform] is ignored (kept for API stability): v2 always uses the
  /// bundled Mona Sans, never the platform face.
  factory AknTextStyles.from(AknColors c, {TargetPlatform? platform}) {
    TextStyle sans(
      double size,
      double line,
      FontWeight weight, {
      double tracking = 0,
      Color? color,
    }) => TextStyle(
      fontFamily: AknFonts.sans,
      fontSize: size,
      height: line / size,
      fontWeight: weight,
      letterSpacing: tracking,
      color: color,
      leadingDistribution: TextLeadingDistribution.even,
      locale: AknFonts.locale,
    );
    TextStyle counter(
      double size,
      double line,
      FontWeight weight, {
      double tracking = 0,
      Color? color,
    }) => TextStyle(
      fontFamily: AknFonts.condensed,
      fontSize: size,
      height: line / size,
      fontWeight: weight,
      letterSpacing: tracking,
      color: color,
      leadingDistribution: TextLeadingDistribution.even,
      locale: AknFonts.locale,
    );

    final captionStrong = sans(
      12,
      16,
      FontWeight.w600,
      tracking: 0.1,
      color: c.dim,
    );
    return AknTextStyles(
      display: sans(30, 36, FontWeight.w600, tracking: -0.6, color: c.ink),
      title: sans(20, 26, FontWeight.w600, tracking: -0.2, color: c.ink),
      headline: sans(17, 22, FontWeight.w600, tracking: -0.1, color: c.ink),
      body: sans(15, 22, FontWeight.w400, color: c.text),
      bodyStrong: sans(15, 22, FontWeight.w600, color: c.ink),
      bodySmall: sans(14, 20, FontWeight.w400, color: c.dim),
      label: sans(13, 18, FontWeight.w500, color: c.ink),
      caption: sans(12, 16, FontWeight.w400, tracking: 0.1, color: c.dim),
      captionStrong: captionStrong,
      overline: captionStrong.copyWith(letterSpacing: 0),
      amount: sans(17, 22, FontWeight.w600, tracking: -0.1, color: c.ink),
      amountLarge: counter(
        28,
        32,
        FontWeight.w700,
        tracking: -0.3,
        color: c.ink,
      ),
      number: counter(24, 28, FontWeight.w700, tracking: -0.2, color: c.ink),
      numberLarge: counter(
        34,
        38,
        FontWeight.w800,
        tracking: -0.4,
        color: c.ink,
      ),
      button: sans(16, 20, FontWeight.w600),
      plateFigure: counter(
        58,
        58,
        FontWeight.w800,
        tracking: -0.8,
        color: c.ink,
      ),
      plateUnit: counter(30, 30, FontWeight.w700, tracking: -0.2, color: c.ink),
      figureWord: sans(20, 24, FontWeight.w600, tracking: -0.2, color: c.ink),
      readoutUnit: counter(16, 28, FontWeight.w700, color: c.ink),
      navLabel: sans(11, 14, FontWeight.w500, color: c.navInactive),
    );
  }

  /// Root page titles ("Siparişlerim") and object titles ("Motorin,
  /// 8.000 L"): 30/36 600, −0.6.
  final TextStyle display;

  /// Section, sheet and dialog titles: 20/26 600.
  final TextStyle title;

  /// Row titles, plate titles, pushed-page app-bar titles: 17/22 600.
  final TextStyle headline;

  /// Paragraphs: 15/22 400.
  final TextStyle body;
  final TextStyle bodyStrong;

  /// Second lines and meta: 14/20 dim.
  final TextStyle bodySmall;

  /// Form labels, chips, plate readout labels: 13/18 500 ink.
  final TextStyle label;

  /// Axis labels, timestamps: 12/16 dim.
  final TextStyle caption;
  final TextStyle captionStrong;

  /// Deprecated: = [captionStrong] with no tracking. Sentence case; never
  /// upper case (no eyebrow labels in v2).
  final TextStyle overline;

  /// Right-aligned money / litres in rows: 17/22 600 (proportional figures;
  /// one amount per row, aligned by the right edge).
  final TextStyle amount;

  /// Totals outside a plate: Condensed 28/32 700.
  final TextStyle amountLarge;

  /// Readouts, pipeline counts, Tüpraş prices: Condensed 24/28 700.
  final TextStyle number;

  /// Big numbers outside a plate: Condensed 34/38 800.
  final TextStyle numberLarge;

  /// Button labels: 16/20 600; the colour comes from the button.
  final TextStyle button;

  /// The plate's hero figure: Condensed 58/58 800, −0.8 (driver 64/62).
  final TextStyle plateFigure;

  /// ₺, L, ₺/L, ",00" after [plateFigure] (gap 6): Condensed 30/30 700
  /// (driver 34).
  final TextStyle plateUnit;

  /// A word after a plate figure ("dönüşüm", "teslimat"): 20/24 600.
  final TextStyle figureWord;

  /// Unit after a [number] readout (gap 3): Condensed 16/28 700.
  final TextStyle readoutUnit;

  /// Bottom-bar labels: 11/14 500 (600 when active; driver 12/15), clamped
  /// at 1.2× text scale by the bar.
  final TextStyle navLabel;

  /// The same scale re-coloured for [c], keeping every size and weight
  /// (driver-mode sizes survive). `OnHero` uses it with `c.plateInk()`.
  AknTextStyles recolor(AknColors c) => AknTextStyles(
    display: display.copyWith(color: c.ink),
    title: title.copyWith(color: c.ink),
    headline: headline.copyWith(color: c.ink),
    body: body.copyWith(color: c.text),
    bodyStrong: bodyStrong.copyWith(color: c.ink),
    bodySmall: bodySmall.copyWith(color: c.dim),
    label: label.copyWith(color: c.ink),
    caption: caption.copyWith(color: c.dim),
    captionStrong: captionStrong.copyWith(color: c.dim),
    overline: overline.copyWith(color: c.dim),
    amount: amount.copyWith(color: c.ink),
    amountLarge: amountLarge.copyWith(color: c.ink),
    number: number.copyWith(color: c.ink),
    numberLarge: numberLarge.copyWith(color: c.ink),
    button: button,
    plateFigure: plateFigure.copyWith(color: c.ink),
    plateUnit: plateUnit.copyWith(color: c.ink),
    figureWord: figureWord.copyWith(color: c.ink),
    readoutUnit: readoutUnit.copyWith(color: c.ink),
    navLabel: navLabel.copyWith(color: c.navInactive),
  );

  /// Material [TextTheme] carrying this scale, so stock widgets match
  /// (§3.2): display* = [display] at 40/36/30, headline* = [title] at
  /// 28/24/20, titleLarge = title, titleMedium = headline, titleSmall =
  /// bodyStrong, bodyLarge = body at 16/24, bodyMedium = body, bodySmall =
  /// caption, labelLarge = button, labelMedium = label, labelSmall =
  /// captionStrong.
  TextTheme toTextTheme() => TextTheme(
    displayLarge: display.copyWith(fontSize: 40, height: 46 / 40),
    displayMedium: display.copyWith(fontSize: 36, height: 42 / 36),
    displaySmall: display,
    headlineLarge: title.copyWith(fontSize: 28, height: 34 / 28),
    headlineMedium: title.copyWith(fontSize: 24, height: 30 / 24),
    headlineSmall: title,
    titleLarge: title,
    titleMedium: headline,
    titleSmall: bodyStrong,
    bodyLarge: body.copyWith(fontSize: 16, height: 24 / 16),
    bodyMedium: body,
    bodySmall: caption,
    labelLarge: button.copyWith(color: display.color),
    labelMedium: label,
    labelSmall: captionStrong,
  );

  /// Material [TextTheme] for the palette [c] (see [toTextTheme]).
  static TextTheme textTheme(AknColors c) =>
      AknTextStyles.from(c).toTextTheme();

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
    TextStyle? number,
    TextStyle? numberLarge,
    TextStyle? button,
    TextStyle? plateFigure,
    TextStyle? plateUnit,
    TextStyle? figureWord,
    TextStyle? readoutUnit,
    TextStyle? navLabel,
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
      number: number ?? this.number,
      numberLarge: numberLarge ?? this.numberLarge,
      button: button ?? this.button,
      plateFigure: plateFigure ?? this.plateFigure,
      plateUnit: plateUnit ?? this.plateUnit,
      figureWord: figureWord ?? this.figureWord,
      readoutUnit: readoutUnit ?? this.readoutUnit,
      navLabel: navLabel ?? this.navLabel,
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
      number: l(number, other.number),
      numberLarge: l(numberLarge, other.numberLarge),
      button: l(button, other.button),
      plateFigure: l(plateFigure, other.plateFigure),
      plateUnit: l(plateUnit, other.plateUnit),
      figureWord: l(figureWord, other.figureWord),
      readoutUnit: l(readoutUnit, other.readoutUnit),
      navLabel: l(navLabel, other.navLabel),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AknTextStyles &&
          other.display == display &&
          other.title == title &&
          other.headline == headline &&
          other.body == body &&
          other.bodyStrong == bodyStrong &&
          other.bodySmall == bodySmall &&
          other.label == label &&
          other.caption == caption &&
          other.captionStrong == captionStrong &&
          other.overline == overline &&
          other.amount == amount &&
          other.amountLarge == amountLarge &&
          other.number == number &&
          other.numberLarge == numberLarge &&
          other.button == button &&
          other.plateFigure == plateFigure &&
          other.plateUnit == plateUnit &&
          other.figureWord == figureWord &&
          other.readoutUnit == readoutUnit &&
          other.navLabel == navLabel;

  @override
  int get hashCode => Object.hashAll([
    display,
    title,
    headline,
    body,
    bodyStrong,
    bodySmall,
    label,
    caption,
    captionStrong,
    overline,
    amount,
    amountLarge,
    number,
    numberLarge,
    button,
    plateFigure,
    plateUnit,
    figureWord,
    readoutUnit,
    navLabel,
  ]);
}

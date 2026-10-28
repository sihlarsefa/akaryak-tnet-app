import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// The bundled face: Archivo 2.001 — the web panel's typeface, so the app
/// and the panel read as one product (2026-10-28). Static TTFs (400–800,
/// wdth 100, Latin + Latin Extended with ₺, every OpenType feature kept)
/// instanced from the google/fonts variable font, SIL OFL 1.1, in
/// `assets/fonts/archivo/` (recipe: `SOURCE.txt`). One family for words and
/// figures.
abstract final class AknFonts {
  /// Words and figures (400, 500, 600, 700, 800). The one place that names
  /// the family (with the pubspec `fonts:` entry): change both to switch.
  static const String sans = 'Archivo';

  /// Deprecated: v3 has no condensed face; figures use [sans] with tabular
  /// digits ([AknNumerals.tabular]). Kept for API stability.
  static const String condensed = sans;

  /// Every style is shaped as Turkish (`locl`: İ/ı, Ş, Ğ …).
  static const Locale locale = Locale('tr', 'TR');

  /// The family's name on the "Lisanslar" page.
  static const String licenseName = 'Archivo';

  /// The bundled licence text (SIL OFL 1.1, no Reserved Font Name).
  static const String licenseAsset = 'assets/fonts/archivo/OFL.txt';

  /// Registers the typeface's licence with [LicenseRegistry] so it shows on
  /// the "Lisanslar" page (§1). Call once in `main()`, before `runApp`; the
  /// text is read only when the licences are requested.
  static void registerLicense() {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks(const [
        licenseName,
      ], await rootBundle.loadString(licenseAsset));
    });
  }
}

/// Numerals (design v3 §1): every figure is a tabular lining figure
/// ([tabular]), so amounts align in columns and a value that ticks or counts
/// never changes width. Things that tick may still sit in a fixed-width box
/// measured once from the widest expected string ([fixedWidth]); units are a
/// smaller `TextSpan` in the same `Text.rich`, after a thin gap.
abstract final class AknNumerals {
  /// The `tnum` feature every numeric style carries.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

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

/// Type scale on Archivo (design v3 §1, panel tracking):
///
/// * words: display 28/34 800, title 20/26 700, headline 17/22 700, body
///   15/22 400, bodySmall 14/20, label 13/18 600, caption 12/16 500;
/// * figures, all with tabular digits ([AknNumerals.tabular]): amount 17/22
///   700, number 24/30 800, amountLarge 28/34 800, numberLarge 32/38 800 and
///   the hero card's `plateFigure` 46/52 800 + `plateUnit` 24/28 700.
///
/// Hierarchy comes from size and weight. Archivo sets tighter than a
/// geometric face, so tracking is the panel's: about −0.015 em on figures
/// and big titles, −0.005 em on headings, none on reading text. Every style
/// sets `leadingDistribution: even` and the Turkish locale. Read with
/// `context.aknText`.
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
  /// [platform] is ignored (kept for API stability): the app always uses the
  /// bundled Archivo, never the platform face.
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
    TextStyle figures(
      double size,
      double line,
      FontWeight weight, {
      double tracking = 0,
      Color? color,
    }) => sans(
      size,
      line,
      weight,
      tracking: tracking,
      color: color,
    ).copyWith(fontFeatures: AknNumerals.tabular);

    final captionStrong = sans(12, 16, FontWeight.w700, color: c.dim);
    return AknTextStyles(
      display: sans(28, 34, FontWeight.w800, tracking: -0.4, color: c.ink),
      title: sans(20, 26, FontWeight.w700, tracking: -0.2, color: c.ink),
      headline: sans(17, 22, FontWeight.w700, tracking: -0.1, color: c.ink),
      body: sans(15, 22, FontWeight.w400, color: c.text),
      bodyStrong: sans(15, 22, FontWeight.w600, color: c.ink),
      bodySmall: sans(14, 20, FontWeight.w400, color: c.dim),
      label: sans(13, 18, FontWeight.w600, color: c.ink),
      caption: sans(12, 16, FontWeight.w500, color: c.dim),
      captionStrong: captionStrong,
      overline: captionStrong,
      amount: figures(17, 22, FontWeight.w700, tracking: -0.15, color: c.ink),
      amountLarge: figures(
        28,
        34,
        FontWeight.w800,
        tracking: -0.4,
        color: c.ink,
      ),
      number: figures(24, 30, FontWeight.w800, tracking: -0.35, color: c.ink),
      numberLarge: figures(
        32,
        38,
        FontWeight.w800,
        tracking: -0.5,
        color: c.ink,
      ),
      button: sans(16, 20, FontWeight.w700),
      plateFigure: figures(
        46,
        52,
        FontWeight.w800,
        tracking: -0.7,
        color: c.ink,
      ),
      plateUnit: figures(24, 28, FontWeight.w700, tracking: -0.2, color: c.ink),
      figureWord: sans(20, 24, FontWeight.w700, tracking: -0.15, color: c.ink),
      readoutUnit: figures(14, 30, FontWeight.w700, color: c.ink),
      navLabel: sans(11, 14, FontWeight.w600, color: c.navInactive),
    );
  }

  /// Root page titles ("Siparişlerim") and object titles ("Motorin,
  /// 8.000 L"): 28/34 800, −0.4.
  final TextStyle display;

  /// Section, sheet and dialog titles: 20/26 700.
  final TextStyle title;

  /// Row titles, plate titles, pushed-page app-bar titles: 17/22 700.
  final TextStyle headline;

  /// Paragraphs: 15/22 400.
  final TextStyle body;
  final TextStyle bodyStrong;

  /// Second lines and meta: 14/20 dim.
  final TextStyle bodySmall;

  /// Form labels, chips, plate readout labels: 13/18 600 ink.
  final TextStyle label;

  /// Axis labels, timestamps: 12/16 500 dim.
  final TextStyle caption;
  final TextStyle captionStrong;

  /// Deprecated: = [captionStrong]. Sentence case; never upper case (no
  /// eyebrow labels).
  final TextStyle overline;

  /// Right-aligned money / litres in rows: 17/22 700, tabular figures.
  final TextStyle amount;

  /// Totals outside the hero card: 28/34 800, tabular.
  final TextStyle amountLarge;

  /// Readouts, pipeline counts, Tüpraş prices: 24/30 800, tabular.
  final TextStyle number;

  /// Big numbers outside the hero card: 32/38 800, tabular.
  final TextStyle numberLarge;

  /// Button labels: 16/20 700; the colour comes from the button.
  final TextStyle button;

  /// The hero card's figure: 46/52 800, −0.7, tabular (driver 56/60).
  final TextStyle plateFigure;

  /// ₺, L, ₺/L, ",00" after [plateFigure] (gap 6): 24/28 700 (driver 28).
  final TextStyle plateUnit;

  /// A word after a plate figure ("dönüşüm", "teslimat"): 20/24 700.
  final TextStyle figureWord;

  /// Unit after a [number] readout (gap 3): 14/30 700, tabular.
  final TextStyle readoutUnit;

  /// Bottom-bar labels: 11/14 600 (700 when active; driver 12/15), clamped
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

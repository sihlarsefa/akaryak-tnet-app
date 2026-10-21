import 'package:flutter/material.dart';

/// AkaryakıtNet design tokens — design language v2 "Turuncu Plaka"
/// (`work/akn-design-v2.md`, 2026-10-21).
///
/// The identity in one breath: a white ledger page, ink (Asfalt #1E2227) for
/// every word, and exactly one flat logo-orange **plate** per screen that
/// carries the screen's key number in black ink (like the ADR hazard plate on
/// a tanker). No gradients, no resting shadows, no pastel tints, never purple.
///
/// * `plate` (#FF5001, dark #E64800): the plate fill; everything on it is
///   `onPlate` (#000000, 6.40:1 / 5.29:1). Read a whole palette for plate
///   content with [AknColors.plateInk].
/// * `brand` / `logo` (#FF5001): marks only (rule 3 of the spec): the logo
///   tile, the active-tab needle, the Sipariş ver key, progress fills, the
///   focus ring, the "your move" lamp dot and the current chart bar.
/// * `brandFill` / `onBrandFill`: the primary button, orange with a BLACK
///   label (owner sign-off B, §2.5).
/// * `brandInk` (Pas #C2410C): orange TEXT, and only for "your move".
///
/// Read the active palette with `context.akn` (see `theme.dart`).

/// Semantic tone of a status, banner, badge or toast.
///
/// Status is never shown by colour alone: every tone is paired with a lamp
/// and a Turkish label (see `status.dart`).
enum AknTone { neutral, info, ok, warn, danger, brand }

/// The five colours of one tone.
///
/// v2: there are no pastel tints any more. Every [bg] is Beton (the quiet
/// well colour) and every [line] is the hairline; a banner is a Beton well
/// with a tone-coloured icon and ink text. Only `brandTone` keeps a soft
/// orange (`brandSoft`) — and only for the 4 px halo around a "your move"
/// dot.
@immutable
class ToneColors {
  const ToneColors({
    required this.fg,
    required this.bg,
    required this.line,
    required this.solid,
    required this.onSolid,
  });

  /// Text and icon colour (AA on `bg`, `surface` and Beton).
  final Color fg;

  /// Well background (Beton in v2; transparent on the plate).
  final Color bg;

  /// 1 px border of a well (the hairline).
  final Color line;

  /// Lamp dot and filled marks.
  final Color solid;

  /// Text and icon colour on [solid] (AA contrast).
  final Color onSolid;

  static ToneColors lerp(ToneColors a, ToneColors b, double t) => ToneColors(
    fg: Color.lerp(a.fg, b.fg, t)!,
    bg: Color.lerp(a.bg, b.bg, t)!,
    line: Color.lerp(a.line, b.line, t)!,
    solid: Color.lerp(a.solid, b.solid, t)!,
    onSolid: Color.lerp(a.onSolid, b.onSolid, t)!,
  );

  ToneColors copyWith({
    Color? fg,
    Color? bg,
    Color? line,
    Color? solid,
    Color? onSolid,
  }) => ToneColors(
    fg: fg ?? this.fg,
    bg: bg ?? this.bg,
    line: line ?? this.line,
    solid: solid ?? this.solid,
    onSolid: onSolid ?? this.onSolid,
  );

  @override
  bool operator ==(Object other) =>
      other is ToneColors &&
      other.fg == fg &&
      other.bg == bg &&
      other.line == line &&
      other.solid == solid &&
      other.onSolid == onSolid;

  @override
  int get hashCode => Object.hash(fg, bg, line, solid, onSolid);
}

/// Colour tokens as a [ThemeExtension] with light and dark values
/// (design v2 §2.2). Every field exists in both themes; dark mode is its own
/// token set (Gece asfaltı), not an inversion.
@immutable
class AknColors extends ThemeExtension<AknColors> {
  const AknColors({
    required this.brightness,
    required this.brand,
    required this.brandPressed,
    required this.brandInk,
    required this.brandSoft,
    required this.brandLine,
    required this.brandFill,
    required this.brandFillPressed,
    required this.onBrandFill,
    required this.brandBright,
    required this.logo,
    required this.heroStart,
    required this.heroEnd,
    required this.onHero,
    required this.onHeroDim,
    required this.navy,
    required this.navyRaised,
    required this.onNavy,
    required this.onNavyDim,
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceRaised,
    required this.ink,
    required this.text,
    required this.dim,
    required this.faint,
    required this.line,
    required this.lineSoft,
    required this.lineStrong,
    required this.ok,
    required this.warn,
    required this.danger,
    required this.info,
    required this.neutral,
    required this.brandTone,
    required this.dangerFill,
    required this.onDangerFill,
    required this.scrim,
    required this.shadow,
    required this.skeleton,
    required this.skeletonHighlight,
    required this.plate,
    required this.onPlate,
    required this.plateContext,
    required this.plateLine,
    required this.chartHighlight,
    required this.chartContext,
    required this.chartTrack,
    required this.navInactive,
    required this.inverse,
    required this.onInverse,
    this.link = _asfalt,
  });

  final Brightness brightness;

  /// Links are ink + underline (offset 3): never blue, never orange, so a
  /// link never reads as a primary action. #1E2227 light, #F1F2F4 dark,
  /// black on the plate.
  final Color link;

  /// Logo orange #FF5001 for marks: selected outlines, the focus ring
  /// (3 px, 2 px offset), switches, the input focus border and caret
  /// (3.28:1 on white, 5.37:1 on #16191D). Never text, never on Beton
  /// (2.98:1).
  final Color brand;

  /// Pressed state of [brand] marks (#E64800).
  final Color brandPressed;

  /// Pas: orange TEXT. It only ever means "your move" (countdowns,
  /// "Kararınızı bekliyor") or an urgent count. 5.18:1 on white, 4.71:1 on
  /// Beton; dark #FF7A3D (6.80:1).
  final Color brandInk;

  /// ONLY the 4 px halo around a "your move" dot or stop. Never a banner,
  /// chip or tile fill.
  final Color brandSoft;

  /// Rare soft orange border.
  final Color brandLine;

  /// Primary button fill: #FF5001 (dark #E64800) with a black label —
  /// "on orange, ink is black" (owner sign-off B, §2.5). Switching to
  /// option A (Asfalt / white) or C (#C94C0C / white) is this token pair.
  final Color brandFill;

  /// Pressed primary (#E64800, dark #D24300); the black label keeps ≥ 4.5
  /// (5.29 / 4.54).
  final Color brandFillPressed;

  /// Label on [brandFill]: black (6.40:1 light, 5.29:1 dark).
  final Color onBrandFill;

  /// The logo orange #FF5001: logo tile, active-tab needle, Sipariş ver
  /// key, current bar, lamp dot. Non-text only.
  final Color brandBright;

  /// Same as [brandBright] (the logo painters read this name).
  final Color logo;

  /// Deprecated: = [plate]. The hero is a flat plate now (no gradient
  /// anywhere); kept so old call sites compile.
  final Color heroStart;

  /// Deprecated: = [plate]. See [heroStart].
  final Color heroEnd;

  /// Deprecated: = [onPlate] (black). Ink on the plate.
  final Color onHero;

  /// Deprecated: = [onPlate] (black). There is no "dim" ink on orange;
  /// hierarchy on the plate is size and weight only.
  final Color onHeroDim;

  /// Deprecated: alias of [plate] (was the navy header colour).
  final Color navy;

  /// Deprecated: black 8 % (was raised navy). Do not use in new code.
  final Color navyRaised;

  /// Deprecated: alias of [onPlate] (black).
  final Color onNavy;

  /// Deprecated: alias of [onPlate] (black).
  final Color onNavyDim;

  /// Page (Kâğıt #FFFFFF; dark #16191D).
  final Color bg;

  /// Sheets, bars, deck back slips (#FFFFFF; dark #1F2328).
  final Color surface;

  /// Beton: quiet fills — search well, inactive chips, segmented track,
  /// skeleton, pressed rows (#F3F4F6; dark #23272D).
  final Color surfaceAlt;

  /// Sheets, menus, dialogs (#FFFFFF; dark #282C32). In dark the bottom bar
  /// uses [surface].
  final Color surfaceRaised;

  /// Asfalt: all ink on white — text, icons, filled chips, badges
  /// (15.99:1; dark #F1F2F4 15.74:1).
  final Color ink;

  /// Body text = [ink] (one ink; hierarchy by weight and size).
  final Color text;

  /// Çelik: secondary text (5.98:1 on white, 5.44:1 on Beton; dark #A3A9B2
  /// 6.68:1 on surface).
  final Color dim;

  /// Disabled text and pager dashes only; never informative text.
  final Color faint;

  /// Decorative hairlines (#E4E6E9; dark #2E333A).
  final Color line;
  final Color lineSoft;

  /// Control borders: inputs, outline buttons, checkbox, drag handle
  /// (Şerit #8B929B, 3.14:1; dark #6E757E, 3.39:1).
  final Color lineStrong;

  final ToneColors ok;

  /// Ochre, never orange.
  final ToneColors warn;
  final ToneColors danger;

  /// "In progress, someone else's move" = an ink lamp.
  final ToneColors info;

  /// Closed / cancelled (hollow ring + dim label).
  final ToneColors neutral;

  /// "Your move": Pas text, logo-orange dot, `brandSoft` halo.
  final ToneColors brandTone;

  /// Destructive confirm button only (white label, 5.94:1).
  final Color dangerFill;
  final Color onDangerFill;

  /// Modal scrim (Asfalt 48 %; dark black 60 %).
  final Color scrim;

  /// Shadow colour for lifted things only (§4.4).
  final Color shadow;
  final Color skeleton;
  final Color skeletonHighlight;

  /// The plate fill: #FF5001 (dark #E64800 — dimmed at night for glare).
  final Color plate;

  /// All ink on the plate: black.
  final Color onPlate;

  /// Context graphics on the plate: past-month bars, meter and ranked-bar
  /// tracks (white; 3.28:1 / 3.97:1 non-text).
  final Color plateContext;

  /// Hairlines between ledger lines on the plate (black 24 % / 26 %).
  final Color plateLine;

  /// The current / selected value on white charts (logo orange).
  final Color chartHighlight;

  /// Every other bar or dot on white charts (3.14:1 / 3.21:1).
  final Color chartContext;

  /// Meter and ranked-bar tracks on white.
  final Color chartTrack;

  /// Inactive bottom-bar icon and label (#6B727B, 4.86:1 on white; dark
  /// #A3A9B2). Active items are [ink] with the [logo] needle.
  final Color navInactive;

  /// Inverse surfaces: toasts, tooltips, the bar-value bubble (#1E2227;
  /// dark #3A3F46).
  final Color inverse;

  /// Text and icons on [inverse] (white).
  final Color onInverse;

  bool get isDark => brightness == Brightness.dark;

  ToneColors tone(AknTone tone) => switch (tone) {
    AknTone.neutral => neutral,
    AknTone.info => info,
    AknTone.ok => ok,
    AknTone.warn => warn,
    AknTone.danger => danger,
    AknTone.brand => brandTone,
  };

  /// The palette for content printed ON the plate (§2.2): every ink, mark
  /// and link is black, hairlines are [plateLine], every surface is the
  /// plate itself, tones lose their colour (black, no well) and charts draw
  /// black marks on white context. `OnHero.palette(base)` returns this, so
  /// anything inside a hero panel prints in plate ink automatically.
  ///
  /// Idempotent: `c.plateInk().plateInk() == c.plateInk()`.
  AknColors plateInk() {
    const black = Color(0xFF000000);
    const clear = Color(0x00000000);
    final toneOnPlate = ToneColors(
      fg: black,
      bg: clear,
      line: clear,
      solid: black,
      onSolid: plate,
    );
    return copyWith(
      ink: black,
      text: black,
      dim: black,
      faint: black,
      lineStrong: black,
      brand: black,
      brandInk: black,
      link: black,
      line: plateLine,
      lineSoft: plateLine,
      bg: plate,
      surface: plate,
      surfaceAlt: plate,
      surfaceRaised: plate,
      ok: toneOnPlate,
      warn: toneOnPlate,
      danger: toneOnPlate,
      info: toneOnPlate,
      neutral: toneOnPlate,
      brandTone: toneOnPlate,
      chartHighlight: black,
      chartContext: plateContext,
      chartTrack: plateContext,
      navInactive: black,
    );
  }

  // Named palette (§2.1).
  static const _white = Color(0xFFFFFFFF);
  static const _black = Color(0xFF000000);
  static const _plaka = Color(0xFFFF5001);
  static const _plakaNight = Color(0xFFE64800);
  static const _asfalt = Color(0xFF1E2227);
  static const _beton = Color(0xFFF3F4F6);
  static const _celik = Color(0xFF5D646D);
  static const _pas = Color(0xFFC2410C);
  static const _serit = Color(0xFF8B929B);
  static const _hairline = Color(0xFFE4E6E9);

  // Gece asfaltı (dark).
  static const _night = Color(0xFF16191D);
  static const _nightSurface = Color(0xFF1F2328);
  static const _nightBeton = Color(0xFF23272D);
  static const _nightRaised = Color(0xFF282C32);
  static const _nightInk = Color(0xFFF1F2F4);
  static const _nightDim = Color(0xFFA3A9B2);
  static const _nightHairline = Color(0xFF2E333A);

  static const AknColors light = AknColors(
    brightness: Brightness.light,
    brand: _plaka,
    brandPressed: _plakaNight,
    brandInk: _pas,
    brandSoft: Color(0xFFFFF3EC),
    brandLine: Color(0xFFFFD3BD),
    brandFill: _plaka,
    brandFillPressed: _plakaNight,
    onBrandFill: _black,
    brandBright: _plaka,
    logo: _plaka,
    heroStart: _plaka,
    heroEnd: _plaka,
    onHero: _black,
    onHeroDim: _black,
    navy: _plaka,
    navyRaised: Color(0x14000000),
    onNavy: _black,
    onNavyDim: _black,
    bg: _white,
    surface: _white,
    surfaceAlt: _beton,
    surfaceRaised: _white,
    ink: _asfalt,
    text: _asfalt,
    dim: _celik,
    faint: _serit,
    line: _hairline,
    lineSoft: Color(0xFFEEF0F2),
    lineStrong: _serit,
    ok: ToneColors(
      fg: Color(0xFF18794E),
      bg: _beton,
      line: _hairline,
      solid: Color(0xFF18794E),
      onSolid: _white,
    ),
    warn: ToneColors(
      fg: Color(0xFF8A5A00),
      bg: _beton,
      line: _hairline,
      solid: Color(0xFF8A5A00),
      onSolid: _white,
    ),
    danger: ToneColors(
      fg: Color(0xFFC0261C),
      bg: _beton,
      line: _hairline,
      solid: Color(0xFFC0261C),
      onSolid: _white,
    ),
    info: ToneColors(
      fg: _asfalt,
      bg: _beton,
      line: _hairline,
      solid: _asfalt,
      onSolid: _white,
    ),
    neutral: ToneColors(
      fg: _celik,
      bg: _beton,
      line: _hairline,
      solid: _celik,
      onSolid: _white,
    ),
    brandTone: ToneColors(
      fg: _pas,
      bg: Color(0xFFFFF3EC),
      line: Color(0xFFFFD3BD),
      solid: _plaka,
      onSolid: _black,
    ),
    dangerFill: Color(0xFFC0261C),
    onDangerFill: _white,
    scrim: Color(0x7A1E2227),
    shadow: Color(0x291E2227),
    skeleton: _beton,
    skeletonHighlight: Color(0xFFF9FAFB),
    plate: _plaka,
    onPlate: _black,
    plateContext: _white,
    plateLine: Color(0x3D000000),
    chartHighlight: _plaka,
    chartContext: _serit,
    chartTrack: Color(0xFFEEF0F2),
    navInactive: Color(0xFF6B727B),
    inverse: _asfalt,
    onInverse: _white,
    link: _asfalt,
  );

  static const AknColors dark = AknColors(
    brightness: Brightness.dark,
    brand: _plaka,
    brandPressed: _plakaNight,
    brandInk: Color(0xFFFF7A3D),
    brandSoft: Color(0xFF3A2116),
    brandLine: Color(0xFF5A2A12),
    brandFill: _plakaNight,
    brandFillPressed: Color(0xFFD24300),
    onBrandFill: _black,
    brandBright: _plaka,
    logo: _plaka,
    heroStart: _plakaNight,
    heroEnd: _plakaNight,
    onHero: _black,
    onHeroDim: _black,
    navy: _plakaNight,
    navyRaised: Color(0x14000000),
    onNavy: _black,
    onNavyDim: _black,
    bg: _night,
    surface: _nightSurface,
    surfaceAlt: _nightBeton,
    surfaceRaised: _nightRaised,
    ink: _nightInk,
    text: _nightInk,
    dim: _nightDim,
    faint: Color(0xFF7D848D),
    line: _nightHairline,
    lineSoft: Color(0xFF262A30),
    lineStrong: Color(0xFF6E757E),
    ok: ToneColors(
      fg: Color(0xFF5CC98A),
      bg: _nightBeton,
      line: _nightHairline,
      solid: Color(0xFF5CC98A),
      onSolid: _night,
    ),
    warn: ToneColors(
      fg: Color(0xFFF5B83D),
      bg: _nightBeton,
      line: _nightHairline,
      solid: Color(0xFFF5B83D),
      onSolid: _night,
    ),
    danger: ToneColors(
      fg: Color(0xFFFF7A70),
      bg: _nightBeton,
      line: _nightHairline,
      solid: Color(0xFFFF7A70),
      onSolid: _night,
    ),
    info: ToneColors(
      fg: _nightInk,
      bg: _nightBeton,
      line: _nightHairline,
      solid: _nightInk,
      onSolid: _night,
    ),
    neutral: ToneColors(
      fg: _nightDim,
      bg: _nightBeton,
      line: _nightHairline,
      solid: _nightDim,
      onSolid: _night,
    ),
    brandTone: ToneColors(
      fg: Color(0xFFFF7A3D),
      bg: Color(0xFF3A2116),
      line: Color(0xFF5A2A12),
      solid: _plaka,
      onSolid: _black,
    ),
    dangerFill: Color(0xFFC0261C),
    onDangerFill: _white,
    scrim: Color(0x99000000),
    shadow: Color(0x99000000),
    skeleton: _nightBeton,
    skeletonHighlight: Color(0xFF2A2F35),
    plate: _plakaNight,
    onPlate: _black,
    plateContext: _white,
    plateLine: Color(0x42000000),
    chartHighlight: _plaka,
    chartContext: Color(0xFF6B717B),
    chartTrack: Color(0xFF2A2F35),
    navInactive: _nightDim,
    inverse: Color(0xFF3A3F46),
    onInverse: _white,
    link: _nightInk,
  );

  @override
  AknColors copyWith({
    Brightness? brightness,
    Color? brand,
    Color? brandPressed,
    Color? brandInk,
    Color? brandSoft,
    Color? brandLine,
    Color? brandFill,
    Color? brandFillPressed,
    Color? onBrandFill,
    Color? brandBright,
    Color? logo,
    Color? heroStart,
    Color? heroEnd,
    Color? onHero,
    Color? onHeroDim,
    Color? navy,
    Color? navyRaised,
    Color? onNavy,
    Color? onNavyDim,
    Color? bg,
    Color? surface,
    Color? surfaceAlt,
    Color? surfaceRaised,
    Color? ink,
    Color? text,
    Color? dim,
    Color? faint,
    Color? line,
    Color? lineSoft,
    Color? lineStrong,
    ToneColors? ok,
    ToneColors? warn,
    ToneColors? danger,
    ToneColors? info,
    ToneColors? neutral,
    ToneColors? brandTone,
    Color? dangerFill,
    Color? onDangerFill,
    Color? scrim,
    Color? shadow,
    Color? skeleton,
    Color? skeletonHighlight,
    Color? plate,
    Color? onPlate,
    Color? plateContext,
    Color? plateLine,
    Color? chartHighlight,
    Color? chartContext,
    Color? chartTrack,
    Color? navInactive,
    Color? inverse,
    Color? onInverse,
    Color? link,
  }) {
    return AknColors(
      brightness: brightness ?? this.brightness,
      brand: brand ?? this.brand,
      brandPressed: brandPressed ?? this.brandPressed,
      brandInk: brandInk ?? this.brandInk,
      brandSoft: brandSoft ?? this.brandSoft,
      brandLine: brandLine ?? this.brandLine,
      brandFill: brandFill ?? this.brandFill,
      brandFillPressed: brandFillPressed ?? this.brandFillPressed,
      onBrandFill: onBrandFill ?? this.onBrandFill,
      brandBright: brandBright ?? this.brandBright,
      logo: logo ?? this.logo,
      heroStart: heroStart ?? this.heroStart,
      heroEnd: heroEnd ?? this.heroEnd,
      onHero: onHero ?? this.onHero,
      onHeroDim: onHeroDim ?? this.onHeroDim,
      navy: navy ?? this.navy,
      navyRaised: navyRaised ?? this.navyRaised,
      onNavy: onNavy ?? this.onNavy,
      onNavyDim: onNavyDim ?? this.onNavyDim,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      ink: ink ?? this.ink,
      text: text ?? this.text,
      dim: dim ?? this.dim,
      faint: faint ?? this.faint,
      line: line ?? this.line,
      lineSoft: lineSoft ?? this.lineSoft,
      lineStrong: lineStrong ?? this.lineStrong,
      ok: ok ?? this.ok,
      warn: warn ?? this.warn,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      neutral: neutral ?? this.neutral,
      brandTone: brandTone ?? this.brandTone,
      dangerFill: dangerFill ?? this.dangerFill,
      onDangerFill: onDangerFill ?? this.onDangerFill,
      scrim: scrim ?? this.scrim,
      shadow: shadow ?? this.shadow,
      skeleton: skeleton ?? this.skeleton,
      skeletonHighlight: skeletonHighlight ?? this.skeletonHighlight,
      plate: plate ?? this.plate,
      onPlate: onPlate ?? this.onPlate,
      plateContext: plateContext ?? this.plateContext,
      plateLine: plateLine ?? this.plateLine,
      chartHighlight: chartHighlight ?? this.chartHighlight,
      chartContext: chartContext ?? this.chartContext,
      chartTrack: chartTrack ?? this.chartTrack,
      navInactive: navInactive ?? this.navInactive,
      inverse: inverse ?? this.inverse,
      onInverse: onInverse ?? this.onInverse,
      link: link ?? this.link,
    );
  }

  @override
  AknColors lerp(covariant ThemeExtension<AknColors>? other, double t) {
    if (other is! AknColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    ToneColors tc(ToneColors a, ToneColors b) => ToneColors.lerp(a, b, t);
    return AknColors(
      brightness: t < 0.5 ? brightness : other.brightness,
      brand: c(brand, other.brand),
      brandPressed: c(brandPressed, other.brandPressed),
      brandInk: c(brandInk, other.brandInk),
      brandSoft: c(brandSoft, other.brandSoft),
      brandLine: c(brandLine, other.brandLine),
      brandFill: c(brandFill, other.brandFill),
      brandFillPressed: c(brandFillPressed, other.brandFillPressed),
      onBrandFill: c(onBrandFill, other.onBrandFill),
      brandBright: c(brandBright, other.brandBright),
      logo: c(logo, other.logo),
      heroStart: c(heroStart, other.heroStart),
      heroEnd: c(heroEnd, other.heroEnd),
      onHero: c(onHero, other.onHero),
      onHeroDim: c(onHeroDim, other.onHeroDim),
      navy: c(navy, other.navy),
      navyRaised: c(navyRaised, other.navyRaised),
      onNavy: c(onNavy, other.onNavy),
      onNavyDim: c(onNavyDim, other.onNavyDim),
      bg: c(bg, other.bg),
      surface: c(surface, other.surface),
      surfaceAlt: c(surfaceAlt, other.surfaceAlt),
      surfaceRaised: c(surfaceRaised, other.surfaceRaised),
      ink: c(ink, other.ink),
      text: c(text, other.text),
      dim: c(dim, other.dim),
      faint: c(faint, other.faint),
      line: c(line, other.line),
      lineSoft: c(lineSoft, other.lineSoft),
      lineStrong: c(lineStrong, other.lineStrong),
      ok: tc(ok, other.ok),
      warn: tc(warn, other.warn),
      danger: tc(danger, other.danger),
      info: tc(info, other.info),
      neutral: tc(neutral, other.neutral),
      brandTone: tc(brandTone, other.brandTone),
      dangerFill: c(dangerFill, other.dangerFill),
      onDangerFill: c(onDangerFill, other.onDangerFill),
      scrim: c(scrim, other.scrim),
      shadow: c(shadow, other.shadow),
      skeleton: c(skeleton, other.skeleton),
      skeletonHighlight: c(skeletonHighlight, other.skeletonHighlight),
      plate: c(plate, other.plate),
      onPlate: c(onPlate, other.onPlate),
      plateContext: c(plateContext, other.plateContext),
      plateLine: c(plateLine, other.plateLine),
      chartHighlight: c(chartHighlight, other.chartHighlight),
      chartContext: c(chartContext, other.chartContext),
      chartTrack: c(chartTrack, other.chartTrack),
      navInactive: c(navInactive, other.navInactive),
      inverse: c(inverse, other.inverse),
      onInverse: c(onInverse, other.onInverse),
      link: c(link, other.link),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AknColors &&
          other.brightness == brightness &&
          other.brand == brand &&
          other.brandPressed == brandPressed &&
          other.brandInk == brandInk &&
          other.brandSoft == brandSoft &&
          other.brandLine == brandLine &&
          other.brandFill == brandFill &&
          other.brandFillPressed == brandFillPressed &&
          other.onBrandFill == onBrandFill &&
          other.brandBright == brandBright &&
          other.logo == logo &&
          other.heroStart == heroStart &&
          other.heroEnd == heroEnd &&
          other.onHero == onHero &&
          other.onHeroDim == onHeroDim &&
          other.navy == navy &&
          other.navyRaised == navyRaised &&
          other.onNavy == onNavy &&
          other.onNavyDim == onNavyDim &&
          other.bg == bg &&
          other.surface == surface &&
          other.surfaceAlt == surfaceAlt &&
          other.surfaceRaised == surfaceRaised &&
          other.ink == ink &&
          other.text == text &&
          other.dim == dim &&
          other.faint == faint &&
          other.line == line &&
          other.lineSoft == lineSoft &&
          other.lineStrong == lineStrong &&
          other.ok == ok &&
          other.warn == warn &&
          other.danger == danger &&
          other.info == info &&
          other.neutral == neutral &&
          other.brandTone == brandTone &&
          other.dangerFill == dangerFill &&
          other.onDangerFill == onDangerFill &&
          other.scrim == scrim &&
          other.shadow == shadow &&
          other.skeleton == skeleton &&
          other.skeletonHighlight == skeletonHighlight &&
          other.plate == plate &&
          other.onPlate == onPlate &&
          other.plateContext == plateContext &&
          other.plateLine == plateLine &&
          other.chartHighlight == chartHighlight &&
          other.chartContext == chartContext &&
          other.chartTrack == chartTrack &&
          other.navInactive == navInactive &&
          other.inverse == inverse &&
          other.onInverse == onInverse &&
          other.link == link;

  @override
  int get hashCode => Object.hashAll([
    brightness,
    brand,
    brandPressed,
    brandInk,
    brandSoft,
    brandLine,
    brandFill,
    brandFillPressed,
    onBrandFill,
    brandBright,
    logo,
    heroStart,
    heroEnd,
    onHero,
    onHeroDim,
    navy,
    navyRaised,
    onNavy,
    onNavyDim,
    bg,
    surface,
    surfaceAlt,
    surfaceRaised,
    ink,
    text,
    dim,
    faint,
    line,
    lineSoft,
    lineStrong,
    ok,
    warn,
    danger,
    info,
    neutral,
    brandTone,
    dangerFill,
    onDangerFill,
    scrim,
    shadow,
    skeleton,
    skeletonHighlight,
    plate,
    onPlate,
    plateContext,
    plateLine,
    chartHighlight,
    chartContext,
    chartTrack,
    navInactive,
    inverse,
    onInverse,
    link,
  ]);
}

/// 4-pt spacing scale (§4.1).
///
/// Rhythm: section title → content 8; row → row 0 (hairline); plate → pager
/// 14; pager → next section 16; last content → bottom bar: list
/// padding-bottom = bar height + safe area + 16.
abstract final class AknSpace {
  static const double s2 = 2;
  static const double s4 = 4;
  static const double s6 = 6;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
  static const double s32 = 32;
  static const double s40 = 40;
  static const double s48 = 48;

  /// Horizontal page gutter: everything aligns on the 20 px edge.
  static const double page = 20;

  /// Gap above a section title.
  static const double section = 24;

  /// Minimum touch target (48; driver mode [driverTap]).
  static const double minTap = 48;

  /// Minimum touch target in driver mode (§6.30).
  static const double driverTap = 64;

  static const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: page);

  /// Group box (`AknCard`) padding.
  static const EdgeInsets cardPadding = EdgeInsets.all(s16);

  /// Inner padding of the plate (§5.1).
  static const EdgeInsets plate = EdgeInsets.fromLTRB(18, 16, 18, 14);

  /// A ledger row (§6.8): full bleed, 20 px gutters.
  static const EdgeInsets row = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 12,
  );

  /// A Beton well (callouts, search, offline line): 12 / 14.
  static const EdgeInsets well = EdgeInsets.symmetric(
    horizontal: 14,
    vertical: 12,
  );
}

/// Corner radii by size, never one value (§4.3): 6 tags and the delta chip,
/// 10 filter chips and small buttons, 12 buttons / inputs / wells / group
/// boxes, 20 the plate, deck cards, sheet tops and dialogs, pills for badges,
/// dots and avatars.
abstract final class AknRadius {
  /// Delta chip, tags (the TR plate uses 5).
  static const double xs = 6;

  /// Filter chips, small buttons, the Sipariş ver key.
  static const double sm = 10;

  /// Buttons, inputs, segmented track, wells, `AknCard`.
  static const double md = 12;

  /// Plate, deck cards, sheet top, dialogs.
  static const double lg = 20;

  /// Was 24; now = [lg].
  static const double xl = 20;

  /// Deprecated: there is no header strip any more (= [lg]).
  static const double xxl = 20;

  static const double pill = 999;

  /// Driver-mode buttons and the slide-to-confirm track (§6.5, §6.26).
  static const double driver = 14;

  /// Filter chips (r10).
  static const BorderRadius chip = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius button = BorderRadius.all(Radius.circular(md));

  /// Small (40 px) buttons and the ghost-button pressed fill.
  static const BorderRadius buttonSmall = BorderRadius.all(Radius.circular(sm));

  /// Driver (64 px) buttons.
  static const BorderRadius buttonDriver = BorderRadius.all(
    Radius.circular(driver),
  );
  static const BorderRadius input = BorderRadius.all(Radius.circular(md));

  /// Group box (`AknCard`), wells, choice cards: 12.
  static const BorderRadius card = BorderRadius.all(Radius.circular(md));

  /// Delta chip and tags: 6.
  static const BorderRadius tag = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius sheet = BorderRadius.vertical(
    top: Radius.circular(lg),
  );
  static const BorderRadius dialog = BorderRadius.all(Radius.circular(lg));

  /// The plate (and therefore every hero panel): 20.
  static const BorderRadius hero = BorderRadius.all(Radius.circular(lg));

  /// The plate: 20 (= [hero]).
  static const BorderRadius plate = hero;

  /// Deprecated: the orange header strip is gone (zero radius).
  static const BorderRadius header = BorderRadius.zero;
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Depth by role (§4.4).
///
/// * e0 flat: page, rows, sections, the plate, deck back slips, the bottom
///   bar, sticky action bars (a hairline on top only).
/// * e1 hairline: inputs, outline buttons, `AknCard`, deck slips (1 px
///   `line`) — a border, not a shadow.
/// * e2 lifted: only things in motion or floating — the dragged deck card,
///   sheets, menus, toasts, dialogs ([raised] / [dragged]).
abstract final class AknShadows {
  /// Resting cards are flat (no shadow in either theme).
  static List<BoxShadow> card(AknColors c) => const [];

  /// Pressed cards are flat.
  static List<BoxShadow> pressed(AknColors c) => const [];

  /// Sheets, menus, toasts, dialogs: `0 1 2` Asfalt 8 % + `0 16 32 −12`
  /// Asfalt 28 % (dark: `0 16 32 −12` black 60 %).
  static List<BoxShadow> raised(AknColors c) => c.isDark
      ? const [
          BoxShadow(
            color: Color(0x99000000),
            offset: Offset(0, 16),
            blurRadius: 32,
            spreadRadius: -12,
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x141E2227),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
          BoxShadow(
            color: Color(0x471E2227),
            offset: Offset(0, 16),
            blurRadius: 32,
            spreadRadius: -12,
          ),
        ];

  /// The deck card while it is dragged (= [raised]); at rest it is flat.
  static List<BoxShadow> dragged(AknColors c) => raised(c);

  /// Bottom bar and sticky action bars are flat (hairline on top).
  static List<BoxShadow> bar(AknColors c) => const [];

  /// The plate is flat.
  static List<BoxShadow> hero(AknColors c) => const [];

  /// No glows anywhere.
  static List<BoxShadow> glow(Color color) => const [];
}

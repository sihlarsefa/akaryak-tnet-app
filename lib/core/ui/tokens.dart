import 'package:flutter/material.dart';

/// AkaryakıtNet design tokens — design language v3 "Akış": a calm graphite
/// base, white cards floating on an off-white page, and orange kept for the
/// brand moments. Owner decisions stay: the orange header band with white
/// content on every home (decision G) and never blue, purple or navy
/// (decision 5).
///
/// * Band: `heroStart` → `heroMid` → `heroEnd` (135°, [AknColors.bandGradient])
///   lit by a soft `heroGlow`; content `onHero` (white) / `onHeroDim`
///   (white 92 %); the glass circles and squares on it are `navyRaised`
///   (white 20 %).
/// * Hero card (the "plate"): `plateTint` → `plate` (180°,
///   [AknColors.plateGradient]), 1 px `plateBorder`, radius 26
///   ([AknRadius.plate]), [AknShadows.plate]; ink is `onPlate` (= ink);
///   accents `plateAccent`, `plateIconFill`, `deltaFill` + `brandInk`; past
///   bars `plateContext`; hairline `plateLine`. Read a whole palette for card
///   content with [AknColors.plateInk].
/// * `brandFillStart` → `brandFill` / `onBrandFill` (white): the primary
///   button ([AknColors.buttonGradient]) with its warm glow
///   ([AknShadows.button]).
/// * `brand` / `logo` (#FF5001): marks (logo tile, focus ring, progress, the
///   selected tab, the "your move" dot); `brandSoft` the soft orange behind
///   selected things.
/// * `brandInk` (Pas #C2410C): orange TEXT ("your move", the delta chip).
/// * Tones carry soft tinted wells (`ToneColors.bg`) again.
///
/// Read the active palette with `context.akn` (see `theme.dart`).

/// Semantic tone of a status, banner, badge or toast.
///
/// Status is never shown by colour alone: every tone is paired with a lamp
/// and a Turkish label (see `status.dart`).
enum AknTone { neutral, info, ok, warn, danger, brand }

/// The five colours of one tone.
///
/// v3: every tone has a soft tinted well ([bg]) with a matching border
/// ([line]); status chips and banners use them so states scan at a glance.
/// `info` stays ink (no blue) and `brandTone` is the soft orange of "your
/// move".
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

  /// Soft tinted well background (status chips, banners).
  final Color bg;

  /// 1 px border of a well, a shade deeper than [bg].
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
/// (design v3 §2). Every field exists in both themes; dark mode is its own
/// token set (Gece grafiti), not an inversion.
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
    this.link = _graphite,
    this.heroMid = _bandMid,
    this.brandFillStart = _buttonStart,
    this.plateTint = _plateTint,
    this.plateBorder = _plateBorder,
    this.plateAccent = _accent,
    this.plateIconFill = _iconFill,
    this.deltaFill = _deltaFill,
    this.homeBg = _homeBg,
    this.heroGlow = _heroGlow,
  });

  final Brightness brightness;

  /// Links are ink + underline (offset 3): never blue, never orange, so a
  /// link never reads as a primary action. #15171A light, #F2F3F5 dark,
  /// ink on the hero card.
  final Color link;

  /// Logo orange #FF5001 for marks: selected outlines, the focus ring
  /// (3 px, 2 px offset), switches, the input focus border and caret, the
  /// active tab. Never body text.
  final Color brand;

  /// Pressed state of [brand] marks (#E64800).
  final Color brandPressed;

  /// Pas: orange TEXT. It means "your move" (countdowns, "Kararınızı
  /// bekliyor"), an urgent count or a delta. 5.18:1 on white; dark #FF7A3D.
  final Color brandInk;

  /// The soft orange behind selected things: the active bottom-bar pill, the
  /// "your move" halo and chip (#FFF1EA; dark #33201A).
  final Color brandSoft;

  /// Soft orange border (#FFD6C2; dark #5A2A12).
  final Color brandLine;

  /// Primary button: the END of the button gradient and its solid fallback
  /// (#E5530A) — [brandFillStart] → [brandFill] with a WHITE label
  /// ([buttonGradient], 3.75:1).
  final Color brandFill;

  /// Pressed primary (#CC4708; dark #C2410C).
  final Color brandFillPressed;

  /// Label on [brandFill]: white, 16 px w700.
  final Color onBrandFill;

  /// Start of the primary-button gradient (#FF7B35).
  final Color brandFillStart;

  /// The logo orange #FF5001: logo tile, Sipariş ver key mark, current bar,
  /// lamp dot. Non-text only.
  final Color brandBright;

  /// Same as [brandBright] (the logo painters read this name).
  final Color logo;

  /// Header band gradient start (#FF8A3D; dark #C2410C), 135°.
  final Color heroStart;

  /// Header band gradient end (#D9440A; dark #7A2A08).
  final Color heroEnd;

  /// Header band gradient middle stop at 50 % (#F2581A; dark #9F350A).
  final Color heroMid;

  /// Content on the band: white (avatar initial, greeting, icons).
  final Color onHero;

  /// Secondary content on the band: white 92 % (company line).
  final Color onHeroDim;

  /// Deprecated alias: the band's middle colour (was the navy header).
  final Color navy;

  /// White 20 %: the glass circles and squares on the band (bell,
  /// assistant, avatar).
  final Color navyRaised;

  /// Deprecated alias of [onHero] (white).
  final Color onNavy;

  /// Deprecated alias of [onHeroDim] (white 92 %).
  final Color onNavyDim;

  /// Page (#F5F6F7; dark #0E0F11). White cards float on it.
  final Color bg;

  /// Cards, sheets, bars (#FFFFFF; dark #17181B).
  final Color surface;

  /// Quiet wells — search, chips at rest, segmented track, skeleton, pressed
  /// rows (#EFF0F2; dark #1E2024).
  final Color surfaceAlt;

  /// Sheets, menus, dialogs, the bottom bar (#FFFFFF; dark #222429).
  final Color surfaceRaised;

  /// Graphite ink: all text and icons (#15171A, 17.96:1 on white; dark
  /// #F2F3F5).
  final Color ink;

  /// Body text = [ink] (one ink; hierarchy by weight and size).
  final Color text;

  /// Secondary text (#5F646C, 5.96:1 on white, 5.22:1 on [surfaceAlt]; dark
  /// #A2A7AF).
  final Color dim;

  /// Disabled text only; never informative text or marks.
  final Color faint;

  /// Decorative hairlines (#E6E8EB; dark #2A2D32).
  final Color line;
  final Color lineSoft;

  /// Control borders: inputs, outline buttons, checkbox, drag handle
  /// (#858B93, 3.44:1 on white, 3.18:1 on the page; dark #6C7179, 3.61:1).
  final Color lineStrong;

  final ToneColors ok;

  /// Ochre, never orange.
  final ToneColors warn;
  final ToneColors danger;

  /// "In progress, someone else's move" = an ink lamp (no blue).
  final ToneColors info;

  /// Closed / cancelled (hollow ring + dim label).
  final ToneColors neutral;

  /// "Your move": Pas text, logo-orange dot, [brandSoft] well.
  final ToneColors brandTone;

  /// Destructive confirm button only (white label, 5.94:1).
  final Color dangerFill;
  final Color onDangerFill;

  /// Modal scrim (ink 45 %; dark black 60 %).
  final Color scrim;

  /// Shadow colour for lifted things.
  final Color shadow;
  final Color skeleton;
  final Color skeletonHighlight;

  /// The hero card's base (white; dark #17181B): a white card whose top
  /// carries a warm wash ([plateTint] → [plate], [plateGradient]).
  final Color plate;

  /// All ink on the hero card (= [ink]).
  final Color onPlate;

  /// Past-month bars on the hero card: #FF5001 at 24 % (dark 40 %).
  final Color plateContext;

  /// The hero card's hairline divider (#F3E4DB; dark #3A2A21).
  final Color plateLine;

  /// Top colour of the hero card's wash (#FFF4EE; dark #2A1E18).
  final Color plateTint;

  /// The hero card's 1 px border (#F5E3D8; dark #3A2A21).
  final Color plateBorder;

  /// Orange accent on the hero card: the icon-tile glyph and the this-month
  /// bar (#E5530A; dark #FF7A3D).
  final Color plateAccent;

  /// The hero card's 40 × 40 icon tile (#FFEDE3; dark #3A2116); also the
  /// meter and ranked-bar track on it.
  final Color plateIconFill;

  /// The delta chip on the hero card (#FFF1EA; dark #3A2116) with
  /// [brandInk] text.
  final Color deltaFill;

  /// Home page background under the band (= [bg]).
  final Color homeBg;

  /// The soft light painted on the header band (#FFC59E; dark #FF8A4C):
  /// a radial glow at the top-left that makes the orange luminous.
  final Color heroGlow;

  /// The current / selected value on white charts (logo orange).
  final Color chartHighlight;

  /// Every other bar or dot on white charts (#858B93, 3.44:1; dark #7D838B).
  final Color chartContext;

  /// Meter and ranked-bar tracks on white.
  final Color chartTrack;

  /// Inactive bottom-bar icon and label (#6B7079, 4.98:1 on white; dark
  /// #A2A7AF). Active items are [ink] on the [brandSoft] pill.
  final Color navInactive;

  /// Inverse surfaces: toasts, tooltips, the bar-value bubble (#1B1D21;
  /// dark #2C2F35).
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

  /// True for the palette of content printed on the plate card
  /// ([plateInk]); `AknDeltaChip` and friends use it to pick their plate
  /// look.
  bool get isPlatePalette => chartContext == plateContext && surface == plate;

  /// True for the palette of content on the orange header band
  /// (`AknTheme.bandPalette`): the logo flips to its white tile there.
  bool get isBandPalette => surface == heroMid && ink == onHero;

  /// The header band: 135° [heroStart] → [heroMid] (50 %) → [heroEnd].
  LinearGradient get bandGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [heroStart, heroMid, heroEnd],
    stops: const [0, 0.5, 1],
  );

  /// The primary button: [brandFillStart] → [brandFill] (135°), settling
  /// into [brandFill] by the middle — so the centred white label always
  /// sits on ≥ 3:1 (bold large text, WCAG) while the light start stays
  /// visible at the leading edge.
  LinearGradient get buttonGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandFillStart, brandFill],
    stops: const [0, 0.5],
  );

  /// The pressed primary button: the gradient one step darker.
  LinearGradient get buttonGradientPressed => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [brandFill, brandFillPressed],
  );

  /// The plate card: 180° [plateTint] (0 %) → [plate] (55 %).
  LinearGradient get plateGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [plateTint, plate],
    stops: const [0, 0.55],
  );

  /// The hero card decoration (owner decision G): [plateGradient], 1 px
  /// [plateBorder], radius 26 ([AknRadius.plate]), [AknShadows.plate].
  /// [raised] false gives the lighter shadow of cards behind the top one.
  BoxDecoration plateDecoration({
    BorderRadius borderRadius = AknRadius.plate,
    bool raised = true,
  }) => BoxDecoration(
    gradient: plateGradient,
    borderRadius: borderRadius,
    border: Border.all(color: plateBorder),
    boxShadow: raised ? AknShadows.plate(this) : AknShadows.plateBehind(this),
  );

  /// The palette for content printed ON the plate card (owner decision G):
  /// ink stays ink ([onPlate]), hairlines are [plateLine], surfaces are the
  /// card ([plate]), quiet wells are [deltaFill], and the charts use the
  /// orange accent — past bars [plateContext], the current one
  /// [plateAccent], tracks [plateIconFill]. Tones keep their colours (the
  /// card is white). `OnHero.palette(base)` returns this.
  ///
  /// Idempotent: `c.plateInk().plateInk() == c.plateInk()`.
  AknColors plateInk() => copyWith(
    ink: onPlate,
    text: onPlate,
    line: plateLine,
    lineSoft: plateLine,
    bg: plate,
    surface: plate,
    surfaceAlt: deltaFill,
    surfaceRaised: plate,
    chartHighlight: plateAccent,
    chartContext: plateContext,
    chartTrack: plateIconFill,
  );

  // Named palette (v3 §2).
  static const _white = Color(0xFFFFFFFF);
  static const _black = Color(0xFF000000);
  static const _plaka = Color(0xFFFF5001);
  static const _plakaNight = Color(0xFFE64800);
  static const _graphite = Color(0xFF15171A);
  static const _page = Color(0xFFF5F6F7);
  static const _well = Color(0xFFEFF0F2);
  static const _slate = Color(0xFF5F646C);
  static const _pas = Color(0xFFC2410C);
  static const _rule = Color(0xFF858B93);
  static const _hairline = Color(0xFFE6E8EB);

  // The orange band, the primary button and the hero card (decision G).
  static const _bandStart = Color(0xFFFF8A3D);
  static const _bandMid = Color(0xFFF2581A);
  static const _bandEnd = Color(0xFFD9440A);
  static const _heroGlow = Color(0xFFFFC59E);
  static const _buttonStart = Color(0xFFFF7B35);
  static const _buttonEnd = Color(0xFFE5530A);
  static const _plateTint = Color(0xFFFFF4EE);
  static const _plateBorder = Color(0xFFF5E3D8);
  static const _accent = Color(0xFFE5530A);
  static const _iconFill = Color(0xFFFFEDE3);
  static const _deltaFill = Color(0xFFFFF1EA);
  static const _homeBg = _page;
  static const _white92 = Color(0xEBFFFFFF);
  static const _white20 = Color(0x33FFFFFF);

  // Gece grafiti (dark): graphite, never navy.
  static const _night = Color(0xFF0E0F11);
  static const _nightSurface = Color(0xFF17181B);
  static const _nightWell = Color(0xFF1E2024);
  static const _nightRaised = Color(0xFF222429);
  static const _nightInk = Color(0xFFF2F3F5);
  static const _nightDim = Color(0xFFA2A7AF);
  static const _nightHairline = Color(0xFF2A2D32);

  static const AknColors light = AknColors(
    brightness: Brightness.light,
    brand: _plaka,
    brandPressed: _plakaNight,
    brandInk: _pas,
    brandSoft: _deltaFill,
    brandLine: Color(0xFFFFD6C2),
    brandFill: _buttonEnd,
    brandFillPressed: Color(0xFFCC4708),
    onBrandFill: _white,
    brandBright: _plaka,
    logo: _plaka,
    heroStart: _bandStart,
    heroEnd: _bandEnd,
    onHero: _white,
    onHeroDim: _white92,
    navy: _bandMid,
    navyRaised: _white20,
    onNavy: _white,
    onNavyDim: _white92,
    bg: _page,
    surface: _white,
    surfaceAlt: _well,
    surfaceRaised: _white,
    ink: _graphite,
    text: _graphite,
    dim: _slate,
    faint: Color(0xFF9A9FA6),
    line: _hairline,
    lineSoft: Color(0xFFEEF0F2),
    lineStrong: _rule,
    ok: ToneColors(
      fg: Color(0xFF0F7A43),
      bg: Color(0xFFEAF7EF),
      line: Color(0xFFC3E8D1),
      solid: Color(0xFF15803D),
      onSolid: _white,
    ),
    warn: ToneColors(
      fg: Color(0xFF8A5A00),
      bg: Color(0xFFFDF5E3),
      line: Color(0xFFF1DDAE),
      solid: Color(0xFF9A6700),
      onSolid: _white,
    ),
    danger: ToneColors(
      fg: Color(0xFFC0261C),
      bg: Color(0xFFFDEFEE),
      line: Color(0xFFF6CBC7),
      solid: Color(0xFFD92D20),
      onSolid: _white,
    ),
    info: ToneColors(
      fg: _graphite,
      bg: _well,
      line: Color(0xFFE1E3E7),
      solid: _graphite,
      onSolid: _white,
    ),
    neutral: ToneColors(
      fg: _slate,
      bg: Color(0xFFF1F2F4),
      line: Color(0xFFE3E5E8),
      solid: _slate,
      onSolid: _white,
    ),
    brandTone: ToneColors(
      fg: _pas,
      bg: _deltaFill,
      line: Color(0xFFFFD6C2),
      solid: _plaka,
      onSolid: _black,
    ),
    dangerFill: Color(0xFFC0261C),
    onDangerFill: _white,
    scrim: Color(0x7315171A),
    shadow: Color(0x2915171A),
    skeleton: Color(0xFFECEEF0),
    skeletonHighlight: Color(0xFFF8F9FA),
    plate: _white,
    onPlate: _graphite,
    plateContext: Color(0x3DFF5001),
    plateLine: Color(0xFFF3E4DB),
    chartHighlight: _plaka,
    chartContext: _rule,
    chartTrack: Color(0xFFEEF0F2),
    navInactive: Color(0xFF6B7079),
    inverse: Color(0xFF1B1D21),
    onInverse: _white,
    link: _graphite,
  );

  static const AknColors dark = AknColors(
    brightness: Brightness.dark,
    brand: _plaka,
    brandPressed: _plakaNight,
    brandInk: Color(0xFFFF7A3D),
    brandSoft: Color(0xFF33201A),
    brandLine: Color(0xFF5A2A12),
    brandFill: _buttonEnd,
    brandFillPressed: _pas,
    onBrandFill: _white,
    brandBright: _plaka,
    logo: _plaka,
    heroStart: _pas,
    heroEnd: Color(0xFF7A2A08),
    onHero: _white,
    onHeroDim: _white92,
    navy: Color(0xFF9F350A),
    navyRaised: _white20,
    onNavy: _white,
    onNavyDim: _white92,
    bg: _night,
    surface: _nightSurface,
    surfaceAlt: _nightWell,
    surfaceRaised: _nightRaised,
    ink: _nightInk,
    text: _nightInk,
    dim: _nightDim,
    faint: Color(0xFF6F747C),
    line: _nightHairline,
    lineSoft: Color(0xFF212327),
    lineStrong: Color(0xFF6C7179),
    ok: ToneColors(
      fg: Color(0xFF4ADE80),
      bg: Color(0xFF13251B),
      line: Color(0xFF1F3B2A),
      solid: Color(0xFF4ADE80),
      onSolid: _night,
    ),
    warn: ToneColors(
      fg: Color(0xFFF5B83D),
      bg: Color(0xFF2A2111),
      line: Color(0xFF4A3A18),
      solid: Color(0xFFF5B83D),
      onSolid: _night,
    ),
    danger: ToneColors(
      fg: Color(0xFFFF7A70),
      bg: Color(0xFF2C1615),
      line: Color(0xFF4D2421),
      solid: Color(0xFFFF7A70),
      onSolid: _night,
    ),
    info: ToneColors(
      fg: _nightInk,
      bg: _nightWell,
      line: _nightHairline,
      solid: _nightInk,
      onSolid: _night,
    ),
    neutral: ToneColors(
      fg: _nightDim,
      bg: _nightWell,
      line: _nightHairline,
      solid: _nightDim,
      onSolid: _night,
    ),
    brandTone: ToneColors(
      fg: Color(0xFFFF7A3D),
      bg: Color(0xFF33201A),
      line: Color(0xFF5A2A12),
      solid: _plaka,
      onSolid: _black,
    ),
    dangerFill: Color(0xFFC0261C),
    onDangerFill: _white,
    scrim: Color(0x99000000),
    shadow: Color(0x99000000),
    skeleton: _nightWell,
    skeletonHighlight: Color(0xFF26292E),
    plate: _nightSurface,
    onPlate: _nightInk,
    plateContext: Color(0x66FF5001),
    plateLine: Color(0xFF3A2A21),
    chartHighlight: _plaka,
    chartContext: Color(0xFF7D838B),
    chartTrack: Color(0xFF26292E),
    navInactive: _nightDim,
    inverse: Color(0xFF2C2F35),
    onInverse: _white,
    link: _nightInk,
    heroMid: Color(0xFF9F350A),
    brandFillStart: _buttonStart,
    plateTint: Color(0xFF2A1E18),
    plateBorder: Color(0xFF3A2A21),
    plateAccent: Color(0xFFFF7A3D),
    plateIconFill: Color(0xFF3A2116),
    deltaFill: Color(0xFF3A2116),
    homeBg: _night,
    heroGlow: Color(0xFFFF8A4C),
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
    Color? heroMid,
    Color? brandFillStart,
    Color? plateTint,
    Color? plateBorder,
    Color? plateAccent,
    Color? plateIconFill,
    Color? deltaFill,
    Color? homeBg,
    Color? heroGlow,
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
      heroMid: heroMid ?? this.heroMid,
      brandFillStart: brandFillStart ?? this.brandFillStart,
      plateTint: plateTint ?? this.plateTint,
      plateBorder: plateBorder ?? this.plateBorder,
      plateAccent: plateAccent ?? this.plateAccent,
      plateIconFill: plateIconFill ?? this.plateIconFill,
      deltaFill: deltaFill ?? this.deltaFill,
      homeBg: homeBg ?? this.homeBg,
      heroGlow: heroGlow ?? this.heroGlow,
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
      heroMid: c(heroMid, other.heroMid),
      brandFillStart: c(brandFillStart, other.brandFillStart),
      plateTint: c(plateTint, other.plateTint),
      plateBorder: c(plateBorder, other.plateBorder),
      plateAccent: c(plateAccent, other.plateAccent),
      plateIconFill: c(plateIconFill, other.plateIconFill),
      deltaFill: c(deltaFill, other.deltaFill),
      homeBg: c(homeBg, other.homeBg),
      heroGlow: c(heroGlow, other.heroGlow),
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
          other.link == link &&
          other.heroMid == heroMid &&
          other.brandFillStart == brandFillStart &&
          other.plateTint == plateTint &&
          other.plateBorder == plateBorder &&
          other.plateAccent == plateAccent &&
          other.plateIconFill == plateIconFill &&
          other.deltaFill == deltaFill &&
          other.homeBg == homeBg &&
          other.heroGlow == heroGlow;

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
    heroMid,
    brandFillStart,
    plateTint,
    plateBorder,
    plateAccent,
    plateIconFill,
    deltaFill,
    homeBg,
    heroGlow,
  ]);
}

/// 4-pt spacing scale (v3 §3).
///
/// Rhythm: section title → content 12; rows inside a card → inset hairline;
/// hero card → pager 14; pager → next section 20; last content → bottom bar:
/// list padding-bottom = bar height + safe area + 16.
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

  /// Inner padding of the hero card (v3 §4).
  static const EdgeInsets plate = EdgeInsets.fromLTRB(20, 18, 20, 16);

  /// A row (§6.8): 20 px gutters.
  static const EdgeInsets row = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 12,
  );

  /// A quiet well (callouts, search, offline line): 12 / 14.
  static const EdgeInsets well = EdgeInsets.symmetric(
    horizontal: 14,
    vertical: 12,
  );
}

/// Corner radii by size, never one value (v3 §3): 8 tags and the delta
/// chip, 12 small buttons, 14 inputs and wells, 16 buttons, 20 cards and
/// group boxes, 22 home sections, 26 the hero card, 28 sheets and dialogs,
/// pills for chips, segmented tracks, badges, dots and avatars.
abstract final class AknRadius {
  /// Delta chip, tags (the TR plate uses 5).
  static const double xs = 8;

  /// Small buttons, the Sipariş ver key, icon tiles.
  static const double sm = 12;

  /// Inputs, wells, segmented thumbs.
  static const double md = 14;

  /// Deck cards and large tiles.
  static const double lg = 24;

  /// Sheets and dialogs.
  static const double xl = 28;

  /// Deprecated: there is no header strip any more (= [xl]).
  static const double xxl = 28;

  static const double pill = 999;

  /// Driver-mode buttons and the slide-to-confirm track (§6.5, §6.26).
  static const double driver = 18;

  /// Filter chips: pills.
  static const BorderRadius chip = BorderRadius.all(Radius.circular(pill));

  /// Buttons (52 high): 16.
  static const BorderRadius button = BorderRadius.all(Radius.circular(16));

  /// Small (40 px) buttons and the ghost-button pressed fill.
  static const BorderRadius buttonSmall = BorderRadius.all(Radius.circular(sm));

  /// Driver (64 px) buttons.
  static const BorderRadius buttonDriver = BorderRadius.all(
    Radius.circular(driver),
  );
  static const BorderRadius input = BorderRadius.all(Radius.circular(md));

  /// Cards, group boxes (`AknCard`), choice cards: 20.
  static const BorderRadius card = BorderRadius.all(Radius.circular(20));

  /// Delta chip and tags: 8.
  static const BorderRadius tag = BorderRadius.all(Radius.circular(xs));
  static const BorderRadius sheet = BorderRadius.vertical(
    top: Radius.circular(xl),
  );
  static const BorderRadius dialog = BorderRadius.all(Radius.circular(xl));

  /// The hero card (owner decision G): 26.
  static const double plateRadius = 26;

  /// The hero card (and therefore every hero panel): 26.
  static const BorderRadius hero = BorderRadius.all(
    Radius.circular(plateRadius),
  );

  /// The hero card: 26 (= [hero]).
  static const BorderRadius plate = hero;

  /// White section containers on the home under the band: 22.
  static const BorderRadius section = BorderRadius.all(Radius.circular(22));

  /// Deprecated: the orange header strip is gone (zero radius).
  static const BorderRadius header = BorderRadius.zero;
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Depth by role (v3 §3): cards float on the off-white page.
///
/// * [card]: resting cards, list cards, section boxes — a soft two-layer
///   shadow (dark: a short black one; dark cards also keep a 1 px `line`).
/// * [raised]: things that float above the page — sheets, menus, toasts,
///   dialogs, the dragged deck card.
/// * [plate] / [band] / [button]: the brand moments carry a warm tint in
///   their shadow (the hero card, the header band, the primary button glow).
abstract final class AknShadows {
  /// Resting cards: `0 1 2` ink 4 % + `0 8 24 −6` ink 8 % (dark: `0 1 2`
  /// black 40 %).
  static List<BoxShadow> card(AknColors c) => c.isDark
      ? const [
          BoxShadow(
            color: Color(0x66000000),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x0A15171A),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
          BoxShadow(
            color: Color(0x1415171A),
            offset: Offset(0, 8),
            blurRadius: 24,
            spreadRadius: -6,
          ),
        ];

  /// Pressed cards settle onto the page: only the contact shadow.
  static List<BoxShadow> pressed(AknColors c) => c.isDark
      ? const []
      : const [
          BoxShadow(
            color: Color(0x0A15171A),
            offset: Offset(0, 1),
            blurRadius: 2,
          ),
        ];

  /// Sheets, menus, toasts, dialogs: `0 2 6` ink 6 % + `0 24 48 −12` ink
  /// 24 % (dark: `0 24 48 −12` black 70 %).
  static List<BoxShadow> raised(AknColors c) => c.isDark
      ? const [
          BoxShadow(
            color: Color(0xB3000000),
            offset: Offset(0, 24),
            blurRadius: 48,
            spreadRadius: -12,
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x0F15171A),
            offset: Offset(0, 2),
            blurRadius: 6,
          ),
          BoxShadow(
            color: Color(0x3D15171A),
            offset: Offset(0, 24),
            blurRadius: 48,
            spreadRadius: -12,
          ),
        ];

  /// The deck card while it is dragged (= [raised]).
  static List<BoxShadow> dragged(AknColors c) => raised(c);

  /// The bottom bar lifts off the content: `0 −8 24` ink 6 % (dark black
  /// 35 %).
  static List<BoxShadow> bar(AknColors c) => [
    BoxShadow(
      color: c.isDark ? const Color(0x59000000) : const Color(0x0F15171A),
      offset: const Offset(0, -8),
      blurRadius: 24,
    ),
  ];

  /// The hero card: a warm contact shadow `0 2 6` #E5530A 6 % + `0 18 36 −10`
  /// ink 16 % (dark: `0 18 36 −10` black 60 %).
  static List<BoxShadow> plate(AknColors c) => c.isDark
      ? const [
          BoxShadow(
            color: Color(0x99000000),
            offset: Offset(0, 18),
            blurRadius: 36,
            spreadRadius: -10,
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x0FE5530A),
            offset: Offset(0, 2),
            blurRadius: 6,
          ),
          BoxShadow(
            color: Color(0x2915171A),
            offset: Offset(0, 18),
            blurRadius: 36,
            spreadRadius: -10,
          ),
        ];

  /// Cards behind the top deck card: a lighter `0 6 14 −6` shadow.
  static List<BoxShadow> plateBehind(AknColors c) => c.isDark
      ? const [
          BoxShadow(
            color: Color(0x59000000),
            offset: Offset(0, 6),
            blurRadius: 14,
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x1A15171A),
            offset: Offset(0, 6),
            blurRadius: 14,
            spreadRadius: -6,
          ),
        ];

  /// The header band: `0 12 28 −8` #D9440A 40 % (dark black 50 %).
  static List<BoxShadow> band(AknColors c) => [
    BoxShadow(
      color: c.isDark ? const Color(0x80000000) : const Color(0x66D9440A),
      offset: const Offset(0, 12),
      blurRadius: 28,
      spreadRadius: -8,
    ),
  ];

  /// The primary button's warm glow: `0 8 18 −6` #E5530A 55 % (dark 35 %).
  static List<BoxShadow> button(AknColors c) => [
    BoxShadow(
      color: c.isDark ? const Color(0x59E5530A) : const Color(0x8CE5530A),
      offset: const Offset(0, 8),
      blurRadius: 18,
      spreadRadius: -6,
    ),
  ];

  /// The hero card shadow (= [plate]).
  static List<BoxShadow> hero(AknColors c) => plate(c);

  /// A soft coloured halo around a mark (the active key, a live lamp):
  /// [color] at 35 %, 24 blur.
  static List<BoxShadow> glow(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.35),
      blurRadius: 24,
      spreadRadius: -4,
    ),
  ];
}

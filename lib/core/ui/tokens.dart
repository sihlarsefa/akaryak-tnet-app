import 'package:flutter/material.dart';

/// AkaryakıtNet design tokens — design language v2 "Turuncu Plaka" with the
/// owner's colour decision G "F2GO kart dili" (`work/akn-design-v2.md`,
/// 2026-10-21 20:20, FINAL).
///
/// The identity in one breath: an orange gradient **header band** on every
/// home (white content on it), and under it the screen's key number on a
/// **white card with a soft orange tint** (the "plate"): ink figures, orange
/// only as an accent (icon tile, delta chip, this-month bar). Primary
/// buttons are an orange gradient with a WHITE label. Never purple.
///
/// * Band: `heroStart` → `heroMid` → `heroEnd` (135°, [AknColors.bandGradient]),
///   content `onHero` (white) / `onHeroDim` (white 92 %); the bell squares
///   are `navyRaised` (white 22 %).
/// * Plate card: `plateTint` → `plate` (180°, [AknColors.plateGradient]),
///   1 px `plateBorder`, radius 22 ([AknRadius.plate]), [AknShadows.plate];
///   ink is `onPlate` (= ink); accents `plateAccent`, `plateIconFill`,
///   `deltaFill` + `brandInk`; past bars `plateContext`; hairline
///   `plateLine`. Read a whole palette for card content with
///   [AknColors.plateInk].
/// * `brandFillStart` → `brandFill` / `onBrandFill` (white): the primary
///   button ([AknColors.buttonGradient]).
/// * `brand` / `logo` (#FF5001): marks only (logo tile, needle, focus ring,
///   progress, the "your move" dot).
/// * `brandInk` (Pas #C2410C): orange TEXT ("your move", the delta chip).
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
    this.heroMid = _bandMid,
    this.brandFillStart = _buttonStart,
    this.plateTint = _plateTint,
    this.plateBorder = _plateBorder,
    this.plateAccent = _accent,
    this.plateIconFill = _iconFill,
    this.deltaFill = _deltaFill,
    this.homeBg = _homeBg,
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

  /// Primary button: the END of the button gradient and its solid fallback
  /// (#E8590C) — owner decision G: orange gradient [brandFillStart] →
  /// [brandFill] with a WHITE label ([buttonGradient]).
  final Color brandFill;

  /// Pressed primary (#CF4E0A; dark #C2410C).
  final Color brandFillPressed;

  /// Label on [brandFill]: white, 17 px w700 (owner decision G).
  final Color onBrandFill;

  /// Start of the primary-button gradient (#F7742F).
  final Color brandFillStart;

  /// The logo orange #FF5001: logo tile, active-tab needle, Sipariş ver
  /// key, current bar, lamp dot. Non-text only.
  final Color brandBright;

  /// Same as [brandBright] (the logo painters read this name).
  final Color logo;

  /// Header band gradient start (#FF8A47; dark #C2410C), 135°.
  final Color heroStart;

  /// Header band gradient end (#E2560E; dark #9A3A09).
  final Color heroEnd;

  /// Header band gradient middle stop at 50 % (#F26A21; dark #AE3D0B).
  final Color heroMid;

  /// Content on the band: white (avatar initial, greeting, icons).
  final Color onHero;

  /// Secondary content on the band: white 92 % (company line).
  final Color onHeroDim;

  /// Deprecated alias: the band's middle colour (was the navy header).
  final Color navy;

  /// White 22 %: the bell / assistant squares and the avatar fill on the
  /// band.
  final Color navyRaised;

  /// Deprecated alias of [onHero] (white).
  final Color onNavy;

  /// Deprecated alias of [onHeroDim] (white 92 %).
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

  /// The plate card's base (white; dark #1F2328). Owner decision G: the
  /// plate is a white card whose top carries a soft orange tint
  /// ([plateTint] → [plate] at 55 %, [plateGradient]).
  final Color plate;

  /// All ink on the plate card: ink #1E2227 (dark #F1F2F4).
  final Color onPlate;

  /// Past-month bars on the plate: #F05A12 at 30 % (dark 45 %).
  final Color plateContext;

  /// The plate's hairline divider (#F3D9C8; dark #3D2B22) — no heavy rule.
  final Color plateLine;

  /// Top colour of the plate card's tint (#FFEDE2; dark #332825 = 10 %
  /// orange over the dark card).
  final Color plateTint;

  /// The plate card's 1 px border (#F8DCCB; dark #432D23).
  final Color plateBorder;

  /// Orange accent on the plate: the icon-tile glyph and the this-month
  /// bar (#E8590C; dark #FF7A3D).
  final Color plateAccent;

  /// The plate's 38 × 38 icon tile (#FFE6D6; dark #3A2116); also the meter
  /// and ranked-bar track on the plate.
  final Color plateIconFill;

  /// The delta chip on the plate (#FFF1E8; dark #3A2116) with [brandInk]
  /// text.
  final Color deltaFill;

  /// Home page background under the band (#F9FAFB; dark = [bg]).
  final Color homeBg;

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

  /// The plate card decoration (owner decision G): [plateGradient], 1 px
  /// [plateBorder], radius 22 ([AknRadius.plate]), [AknShadows.plate].
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

  // Owner decision G "F2GO kart dili".
  static const _bandStart = Color(0xFFFF8A47);
  static const _bandMid = Color(0xFFF26A21);
  static const _bandEnd = Color(0xFFE2560E);
  static const _buttonStart = Color(0xFFF7742F);
  static const _buttonEnd = Color(0xFFE8590C);
  static const _plateTint = Color(0xFFFFEDE2);
  static const _plateBorder = Color(0xFFF8DCCB);
  static const _accent = Color(0xFFE8590C);
  static const _iconFill = Color(0xFFFFE6D6);
  static const _deltaFill = Color(0xFFFFF1E8);
  static const _homeBg = Color(0xFFF9FAFB);
  static const _white92 = Color(0xEBFFFFFF);
  static const _white22 = Color(0x38FFFFFF);

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
    brandFill: _buttonEnd,
    brandFillPressed: Color(0xFFCF4E0A),
    onBrandFill: _white,
    brandBright: _plaka,
    logo: _plaka,
    heroStart: _bandStart,
    heroEnd: _bandEnd,
    onHero: _white,
    onHeroDim: _white92,
    navy: _bandMid,
    navyRaised: _white22,
    onNavy: _white,
    onNavyDim: _white92,
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
    plate: _white,
    onPlate: _asfalt,
    plateContext: Color(0x4DF05A12),
    plateLine: Color(0xFFF3D9C8),
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
    brandFill: _buttonEnd,
    brandFillPressed: _pas,
    onBrandFill: _white,
    brandBright: _plaka,
    logo: _plaka,
    heroStart: _pas,
    heroEnd: Color(0xFF9A3A09),
    onHero: _white,
    onHeroDim: _white92,
    navy: Color(0xFFAE3D0B),
    navyRaised: _white22,
    onNavy: _white,
    onNavyDim: _white92,
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
    plate: _nightSurface,
    onPlate: _nightInk,
    plateContext: Color(0x73F05A12),
    plateLine: Color(0xFF3D2B22),
    chartHighlight: _plaka,
    chartContext: Color(0xFF6B717B),
    chartTrack: Color(0xFF2A2F35),
    navInactive: _nightDim,
    inverse: Color(0xFF3A3F46),
    onInverse: _white,
    link: _nightInk,
    heroMid: Color(0xFFAE3D0B),
    brandFillStart: _buttonStart,
    plateTint: Color(0xFF332825),
    plateBorder: Color(0xFF432D23),
    plateAccent: Color(0xFFFF7A3D),
    plateIconFill: Color(0xFF3A2116),
    deltaFill: Color(0xFF3A2116),
    homeBg: _night,
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
          other.homeBg == homeBg;

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

  /// The plate card (owner decision G): 22.
  static const double plateRadius = 22;

  /// The plate card (and therefore every hero panel): 22.
  static const BorderRadius hero = BorderRadius.all(
    Radius.circular(plateRadius),
  );

  /// The plate card: 22 (= [hero]).
  static const BorderRadius plate = hero;

  /// White section containers on the home under the band: 18.
  static const BorderRadius section = BorderRadius.all(Radius.circular(18));

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

  /// The plate card (owner decision G): `0 8 20` rgba(16,24,40,.09)
  /// (dark: black 40 %).
  static List<BoxShadow> plate(AknColors c) => c.isDark
      ? const [
          BoxShadow(
            color: Color(0x66000000),
            offset: Offset(0, 8),
            blurRadius: 20,
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x17101828),
            offset: Offset(0, 8),
            blurRadius: 20,
          ),
        ];

  /// Cards behind the top deck card: a lighter `0 4 10` shadow.
  static List<BoxShadow> plateBehind(AknColors c) => c.isDark
      ? const [
          BoxShadow(
            color: Color(0x33000000),
            offset: Offset(0, 4),
            blurRadius: 10,
          ),
        ]
      : const [
          BoxShadow(
            color: Color(0x0D101828),
            offset: Offset(0, 4),
            blurRadius: 10,
          ),
        ];

  /// The header band: `0 6 14` rgba(232,89,12,.22).
  static List<BoxShadow> band(AknColors c) => [
    BoxShadow(
      color: c.isDark ? const Color(0x59000000) : const Color(0x38E8590C),
      offset: const Offset(0, 6),
      blurRadius: 14,
    ),
  ];

  /// The primary button's soft orange lift.
  static List<BoxShadow> button(AknColors c) => [
    BoxShadow(
      color: c.isDark ? const Color(0x40000000) : const Color(0x33E8590C),
      offset: const Offset(0, 4),
      blurRadius: 10,
    ),
  ];

  /// The plate card shadow (= [plate]); was flat in v2.
  static List<BoxShadow> hero(AknColors c) => plate(c);

  /// No glows anywhere.
  static List<BoxShadow> glow(Color color) => const [];
}

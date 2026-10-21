import 'package:flutter/material.dart';

/// AkaryakıtNet design tokens — "Turuncu & Beyaz" (redesign R1, 2026-10-21).
///
/// Light-first: white surfaces on a cool off-white page, a warm vivid orange
/// as the hero colour, slate ink only as the text colour. Dark mode is a
/// neutral charcoal (never navy). Never purple.
///
/// * `brandBright` / `logo` (#FF5001): logo, icons, chart bars, progress,
///   active indicators — never text (3.3:1 on white).
/// * `brand` (#E8480A): accent glyphs, selected outlines, focus ring.
/// * `brandInk` (#C2410C): orange TEXT on light surfaces (≥ 4.5:1).
/// * `brandFill` (#D14408): filled buttons / FAB (white label 4.6:1).
/// * `heroStart` → `heroEnd`: the orange hero gradient (header strip and
///   hero panels); content on it uses `onHero` (white).
///
/// Read the active palette with `context.akn` (see `theme.dart`).

/// Semantic tone of a status, banner, badge or toast.
///
/// Status is never shown by colour alone: every tone is paired with an icon
/// and a Turkish label (see `status.dart`).
enum AknTone { neutral, info, ok, warn, danger, brand }

/// The five colours of one tone.
@immutable
class ToneColors {
  const ToneColors({
    required this.fg,
    required this.bg,
    required this.line,
    required this.solid,
    required this.onSolid,
  });

  /// Text and icon colour on [bg] (AA contrast).
  final Color fg;

  /// Soft tint background.
  final Color bg;

  /// 1 px border on [bg].
  final Color line;

  /// Filled background for "solid" chips (Completed, Converted).
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
/// (redesign spec §1.1 / §1.2).
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
    this.link = const Color(0xFF2B5C8A),
  });

  final Brightness brightness;

  /// Inline links ("Gizlilik · KVKK · Koşullar", "Haritada aç"): #2B5C8A on
  /// light surfaces (7:1), #93C5FD in dark, white on the hero. Not orange, so
  /// a link never reads as a primary action.
  final Color link;

  /// Accent for glyphs, selected outlines, focus rings and active states
  /// (≥ 3:1 on surfaces; not for small text — use [brandInk]).
  final Color brand;
  final Color brandPressed;

  /// Orange text (links, section actions, highlighted amounts): ≥ 4.5:1 on
  /// `bg`, `surface` and `brandSoft`.
  final Color brandInk;

  /// Tinted backgrounds (selected chip, icon tiles, info banners).
  final Color brandSoft;

  /// Tinted borders.
  final Color brandLine;

  /// Filled primary buttons and the FAB (white label, 4.6:1 in both themes).
  final Color brandFill;
  final Color brandFillPressed;
  final Color onBrandFill;

  /// The logo orange #FF5001: logo, icons, chart bars, progress, active tab
  /// indicator. Non-text only (3.3:1 on white).
  final Color brandBright;

  /// Same as [brandBright] (kept for the logo painters).
  final Color logo;

  /// Light end of the hero gradient (header strip, hero panels). White large
  /// text reaches 3:1 on it; small text never sits on it (the DS hero
  /// painters keep it at the text-free top-right / right edge).
  final Color heroStart;

  /// Main hero colour: white text reaches 4.5:1 on it.
  final Color heroEnd;

  /// Text and icons on the hero (white).
  final Color onHero;

  /// Secondary icons and large text on the hero (white 88 %). Small text on
  /// the hero uses [onHero]: white 88 % is below 4.5:1 on orange.
  final Color onHeroDim;

  /// Deprecated alias of [heroEnd] (was the navy header colour). Kept so old
  /// call-sites compile; new code uses the hero tokens.
  final Color navy;

  /// Deprecated alias: white 16 % over the hero (was raised navy).
  final Color navyRaised;

  /// Deprecated alias of [onHero].
  final Color onNavy;

  /// Deprecated alias of [onHeroDim].
  final Color onNavyDim;

  /// Page background.
  final Color bg;

  /// Cards, sheets, bars.
  final Color surface;

  /// Inputs, segmented track, skeleton base.
  final Color surfaceAlt;

  /// Sheets, dialogs, toasts and the bottom bar (lifted above [surface] in
  /// dark).
  final Color surfaceRaised;

  /// Headings and key values (the old panel navy survives only here).
  final Color ink;

  /// Body text.
  final Color text;

  /// Secondary text (AA on surface, bg and surfaceAlt).
  final Color dim;

  /// Placeholders and disabled only; never informative text.
  final Color faint;

  final Color line;
  final Color lineSoft;

  /// Input and control borders.
  final Color lineStrong;

  final ToneColors ok;
  final ToneColors warn;
  final ToneColors danger;
  final ToneColors info;
  final ToneColors neutral;

  /// Brand as a tone (InTransit, barem senior/exception): brandInk on
  /// brandSoft.
  final ToneColors brandTone;

  /// Filled destructive buttons and count badges (white label in both
  /// themes).
  final Color dangerFill;
  final Color onDangerFill;

  final Color scrim;

  /// Elevation shadow colour (#101828 at 6 % in light).
  final Color shadow;
  final Color skeleton;
  final Color skeletonHighlight;

  bool get isDark => brightness == Brightness.dark;

  ToneColors tone(AknTone tone) => switch (tone) {
    AknTone.neutral => neutral,
    AknTone.info => info,
    AknTone.ok => ok,
    AknTone.warn => warn,
    AknTone.danger => danger,
    AknTone.brand => brandTone,
  };

  static const _white = Color(0xFFFFFFFF);
  static const _charcoal = Color(0xFF0F1114);

  /// White 16 % (glass over the hero).
  static const _white16 = Color(0x29FFFFFF);

  /// White 88 % (secondary on the hero).
  static const _white88 = Color(0xE0FFFFFF);

  static const AknColors light = AknColors(
    brightness: Brightness.light,
    brand: Color(0xFFE8480A),
    brandPressed: Color(0xFFD14408),
    brandInk: Color(0xFFC2410C),
    brandSoft: Color(0xFFFFF3EC),
    brandLine: Color(0xFFFFD9C4),
    brandFill: Color(0xFFD14408),
    brandFillPressed: Color(0xFFB83C07),
    onBrandFill: _white,
    brandBright: Color(0xFFFF5001),
    logo: Color(0xFFFF5001),
    heroStart: Color(0xFFF5610F),
    heroEnd: Color(0xFFD14408),
    onHero: _white,
    onHeroDim: _white88,
    navy: Color(0xFFD14408),
    navyRaised: _white16,
    onNavy: _white,
    onNavyDim: _white88,
    bg: Color(0xFFF6F7F9),
    surface: Color(0xFFFFFFFF),
    // #F1F3F6 in the spec; one step lighter so `dim` keeps 4.5:1 on it
    // (input hints, segmented track).
    surfaceAlt: Color(0xFFF2F4F7),
    surfaceRaised: Color(0xFFFFFFFF),
    ink: Color(0xFF1F2A37),
    text: Color(0xFF344054),
    dim: Color(0xFF667085),
    faint: Color(0xFF98A2B3),
    line: Color(0xFFE7EAEE),
    lineSoft: Color(0xFFF0F2F5),
    lineStrong: Color(0xFFD0D5DD),
    ok: ToneColors(
      fg: Color(0xFF047857),
      bg: Color(0xFFECFDF5),
      line: Color(0xFFCDEBDC),
      solid: Color(0xFF047857),
      onSolid: _white,
    ),
    warn: ToneColors(
      fg: Color(0xFFB45309),
      bg: Color(0xFFFFFBEB),
      line: Color(0xFFF3E1B5),
      solid: Color(0xFFB45309),
      onSolid: _white,
    ),
    danger: ToneColors(
      fg: Color(0xFFB91C1C),
      bg: Color(0xFFFEF2F2),
      line: Color(0xFFF3D2D2),
      solid: Color(0xFFB91C1C),
      onSolid: _white,
    ),
    info: ToneColors(
      fg: Color(0xFF1D4ED8),
      bg: Color(0xFFEFF6FF),
      line: Color(0xFFD6E3F8),
      solid: Color(0xFF1D4ED8),
      onSolid: _white,
    ),
    neutral: ToneColors(
      fg: Color(0xFF475467),
      bg: Color(0xFFF2F4F7),
      line: Color(0xFFE4E7EC),
      solid: Color(0xFF475467),
      onSolid: _white,
    ),
    brandTone: ToneColors(
      fg: Color(0xFFC2410C),
      bg: Color(0xFFFFF3EC),
      line: Color(0xFFFFD9C4),
      solid: Color(0xFFD14408),
      onSolid: _white,
    ),
    dangerFill: Color(0xFFB91C1C),
    onDangerFill: _white,
    scrim: Color(0x73101828),
    shadow: Color(0x0F101828),
    skeleton: Color(0xFFEDEBE8),
    skeletonHighlight: Color(0xFFF8F7F5),
  );

  static const AknColors dark = AknColors(
    brightness: Brightness.dark,
    brand: Color(0xFFF26B21),
    brandPressed: Color(0xFFE25F17),
    brandInk: Color(0xFFFF8A4C),
    brandSoft: Color(0xFF2A1608),
    brandLine: Color(0xFF4A2410),
    brandFill: Color(0xFFD14408),
    brandFillPressed: Color(0xFFB83C07),
    onBrandFill: _white,
    brandBright: Color(0xFFFF5001),
    logo: Color(0xFFFF5001),
    heroStart: Color(0xFFC2410C),
    heroEnd: Color(0xFF8F3307),
    onHero: _white,
    onHeroDim: _white88,
    navy: Color(0xFF8F3307),
    navyRaised: _white16,
    onNavy: _white,
    onNavyDim: _white88,
    bg: Color(0xFF0F1114),
    surface: Color(0xFF16191D),
    surfaceAlt: Color(0xFF1D2126),
    surfaceRaised: Color(0xFF1B1F24),
    ink: Color(0xFFF4F5F7),
    text: Color(0xFFD0D5DD),
    dim: Color(0xFF98A2B3),
    faint: Color(0xFF667085),
    line: Color(0xFF2A2F36),
    lineSoft: Color(0xFF21252B),
    lineStrong: Color(0xFF3A4049),
    ok: ToneColors(
      fg: Color(0xFF34D399),
      bg: Color(0xFF0F2A22),
      line: Color(0xFF1C4A3A),
      solid: Color(0xFF34D399),
      onSolid: _charcoal,
    ),
    warn: ToneColors(
      fg: Color(0xFFFBBF24),
      bg: Color(0xFF2A210C),
      line: Color(0xFF4A3A12),
      solid: Color(0xFFFBBF24),
      onSolid: _charcoal,
    ),
    danger: ToneColors(
      fg: Color(0xFFF87171),
      bg: Color(0xFF2A1214),
      line: Color(0xFF4A1F22),
      solid: Color(0xFFF87171),
      onSolid: _charcoal,
    ),
    info: ToneColors(
      fg: Color(0xFF93C5FD),
      bg: Color(0xFF10203A),
      line: Color(0xFF1E3A5F),
      solid: Color(0xFF93C5FD),
      onSolid: _charcoal,
    ),
    neutral: ToneColors(
      fg: Color(0xFFD0D5DD),
      bg: Color(0xFF22262C),
      line: Color(0xFF333840),
      solid: Color(0xFFD0D5DD),
      onSolid: _charcoal,
    ),
    brandTone: ToneColors(
      fg: Color(0xFFFF8A4C),
      bg: Color(0xFF2A1608),
      line: Color(0xFF4A2410),
      solid: Color(0xFFD14408),
      onSolid: _white,
    ),
    dangerFill: Color(0xFFB91C1C),
    onDangerFill: _white,
    scrim: Color(0x99000000),
    shadow: Color(0x52000000),
    skeleton: Color(0xFF24272B),
    skeletonHighlight: Color(0xFF2F3338),
    link: Color(0xFF93C5FD),
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
      link: c(link, other.link),
    );
  }
}

/// 4-pt spacing scale.
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

  /// Horizontal page padding.
  static const double page = 16;

  /// Gap between page sections.
  static const double section = 24;

  /// Minimum touch target (spec C.7).
  static const double minTap = 48;

  static const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: page);
  static const EdgeInsets cardPadding = EdgeInsets.all(s16);
}

/// Corner radii — generous and soft: 10 small tiles, 14 buttons and inputs,
/// 20 cards, 24 hero panels / sheets / dialogs, 28 the home header strip,
/// pills for chips.
abstract final class AknRadius {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 28;
  static const double pill = 999;

  /// Small tiles, tags and badges (filter chips are pills).
  static const BorderRadius chip = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius button = BorderRadius.all(Radius.circular(md));
  static const BorderRadius input = BorderRadius.all(Radius.circular(md));
  static const BorderRadius card = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius sheet = BorderRadius.vertical(
    top: Radius.circular(xl),
  );
  static const BorderRadius dialog = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius hero = BorderRadius.all(Radius.circular(xl));

  /// Bottom edge of the orange home header strip (`AknHeroHeader`).
  static const BorderRadius header = BorderRadius.vertical(
    bottom: Radius.circular(xxl),
  );
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Elevation is a soft, diffuse shadow (no hard borders in light mode).
abstract final class AknShadows {
  /// Cards: `0 6 20` at 6 % of #101828 plus a 1 px contact shadow. Dark
  /// mode relies on the hairline instead.
  static List<BoxShadow> card(AknColors c) => c.isDark || c.shadow.a == 0
      ? const []
      : [
          BoxShadow(
            color: c.shadow,
            offset: const Offset(0, 6),
            blurRadius: 20,
          ),
          BoxShadow(
            color: c.shadow.withValues(alpha: c.shadow.a * 0.6),
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
        ];

  /// Pressed card: the shadow settles closer to the surface.
  static List<BoxShadow> pressed(AknColors c) => c.isDark || c.shadow.a == 0
      ? const []
      : [
          BoxShadow(
            color: c.shadow.withValues(alpha: c.shadow.a * 0.8),
            offset: const Offset(0, 2),
            blurRadius: 8,
          ),
        ];

  /// Toasts, menus, floating elements.
  static List<BoxShadow> raised(AknColors c) => [
    BoxShadow(
      color: c.isDark ? const Color(0x66000000) : const Color(0x1F101828),
      offset: const Offset(0, 10),
      blurRadius: 28,
      spreadRadius: -6,
    ),
    BoxShadow(
      color: c.isDark ? const Color(0x33000000) : const Color(0x0A101828),
      offset: const Offset(0, 1),
      blurRadius: 3,
    ),
  ];

  /// Bottom bar and action bar (soft, casts upwards).
  static List<BoxShadow> bar(AknColors c) => [
    BoxShadow(
      color: c.isDark ? const Color(0x59000000) : const Color(0x14101828),
      offset: const Offset(0, -2),
      blurRadius: 18,
    ),
  ];

  /// Warm glow under orange hero panels.
  static List<BoxShadow> hero(AknColors c) => c.isDark
      ? const [
          BoxShadow(
            color: Color(0x40000000),
            offset: Offset(0, 8),
            blurRadius: 20,
          ),
        ]
      : [
          BoxShadow(
            color: c.heroEnd.withValues(alpha: 0.24),
            offset: const Offset(0, 10),
            blurRadius: 24,
            spreadRadius: -6,
          ),
        ];

  /// Orange glow under the bottom bar's centre action and floating buttons.
  static List<BoxShadow> glow(Color color) => [
    BoxShadow(
      color: color.withValues(alpha: 0.38),
      offset: const Offset(0, 6),
      blurRadius: 16,
      spreadRadius: -2,
    ),
  ];
}

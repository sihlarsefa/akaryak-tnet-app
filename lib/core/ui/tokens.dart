import 'package:flutter/material.dart';

/// AkaryakıtNet design tokens: the web panel's calm corporate identity
/// (navy #1F2A37 + orange #C94C0C, slate greys, soft status tints).
///
/// Never purple. `logo` (#FF5001) is for the logo, illustrations and large
/// accents only; it is never used for text (3.3:1 on white).
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

/// Colour tokens as a [ThemeExtension] with light and dark values (spec C.5).
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
    required this.logo,
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
  /// light surfaces (7:1), #93C5FD in dark and on navy. Not orange, so a link
  /// never reads as a primary action.
  final Color link;

  /// Accent for icons, borders, indicators and active states.
  final Color brand;
  final Color brandPressed;

  /// Brand-coloured text (AA on surface and bg).
  final Color brandInk;
  final Color brandSoft;
  final Color brandLine;

  /// Filled primary buttons (white label, 4.6:1 in both themes).
  final Color brandFill;
  final Color brandFillPressed;
  final Color onBrandFill;

  /// Logo orange: logo, illustrations, large accents only. Never text.
  final Color logo;

  /// Headers and hero panels.
  final Color navy;

  /// Elements placed on [navy] (chips, buttons, rings).
  final Color navyRaised;
  final Color onNavy;
  final Color onNavyDim;

  final Color bg;
  final Color surface;
  final Color surfaceAlt;

  /// Sheets, dialogs, toasts and the bottom bar (lifted above [surface] in dark).
  final Color surfaceRaised;

  /// Headings and key values.
  final Color ink;

  /// Body text.
  final Color text;

  /// Secondary text (AA on surface and bg).
  final Color dim;

  /// Decorative and disabled only; never for readable text.
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

  /// Brand as a tone (InTransit, barem senior/exception).
  final ToneColors brandTone;

  /// Filled destructive buttons (white label in both themes).
  final Color dangerFill;
  final Color onDangerFill;

  final Color scrim;
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
  static const _darkInk = Color(0xFF0B1220);

  static const AknColors light = AknColors(
    brightness: Brightness.light,
    brand: Color(0xFFC94C0C),
    brandPressed: Color(0xFFB4470D),
    brandInk: Color(0xFFA8420C),
    brandSoft: Color(0xFFFDF5EF),
    brandLine: Color(0xFFF3DCCD),
    brandFill: Color(0xFFC94C0C),
    brandFillPressed: Color(0xFFB4470D),
    onBrandFill: _white,
    logo: Color(0xFFFF5001),
    navy: Color(0xFF1F2A37),
    navyRaised: Color(0xFF283443),
    onNavy: _white,
    onNavyDim: Color(0xFFC3CDD9),
    bg: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF1F5F9),
    surfaceRaised: Color(0xFFFFFFFF),
    ink: Color(0xFF0F172A),
    text: Color(0xFF334155),
    dim: Color(0xFF64748B),
    faint: Color(0xFF94A3B8),
    line: Color(0xFFE5E9F0),
    lineSoft: Color(0xFFEEF1F5),
    lineStrong: Color(0xFFCBD5E1),
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
      fg: Color(0xFF475569),
      bg: Color(0xFFF1F5F9),
      line: Color(0xFFE2E8F0),
      solid: Color(0xFF475569),
      onSolid: _white,
    ),
    brandTone: ToneColors(
      fg: Color(0xFFA8420C),
      bg: Color(0xFFFDF5EF),
      line: Color(0xFFF3DCCD),
      solid: Color(0xFFC94C0C),
      onSolid: _white,
    ),
    dangerFill: Color(0xFFB91C1C),
    onDangerFill: _white,
    scrim: Color(0x730F172A),
    shadow: Color(0x0F0F172A),
    skeleton: Color(0xFFEBEFF4),
    skeletonHighlight: Color(0xFFF8FAFC),
  );

  static const AknColors dark = AknColors(
    brightness: Brightness.dark,
    brand: Color(0xFFE8692B),
    brandPressed: Color(0xFFD95E22),
    brandInk: Color(0xFFF08A55),
    brandSoft: Color(0xFF2A1A10),
    brandLine: Color(0xFF4A2A18),
    brandFill: Color(0xFFC94C0C),
    brandFillPressed: Color(0xFFB4470D),
    onBrandFill: _white,
    logo: Color(0xFFFF5001),
    navy: Color(0xFF1F2A37),
    navyRaised: Color(0xFF2B3747),
    onNavy: _white,
    onNavyDim: Color(0xFFC3CDD9),
    bg: Color(0xFF0B1220),
    surface: Color(0xFF111A27),
    surfaceAlt: Color(0xFF172131),
    surfaceRaised: Color(0xFF182233),
    ink: Color(0xFFF1F5F9),
    text: Color(0xFFCBD5E1),
    dim: Color(0xFF94A3B8),
    faint: Color(0xFF64748B),
    line: Color(0xFF263244),
    lineSoft: Color(0xFF1D2836),
    lineStrong: Color(0xFF334155),
    ok: ToneColors(
      fg: Color(0xFF34D399),
      bg: Color(0xFF0F2A22),
      line: Color(0xFF1C4A3A),
      solid: Color(0xFF34D399),
      onSolid: _darkInk,
    ),
    warn: ToneColors(
      fg: Color(0xFFFBBF24),
      bg: Color(0xFF2A210C),
      line: Color(0xFF4A3A12),
      solid: Color(0xFFFBBF24),
      onSolid: _darkInk,
    ),
    danger: ToneColors(
      fg: Color(0xFFF87171),
      bg: Color(0xFF2A1214),
      line: Color(0xFF4A1F22),
      solid: Color(0xFFF87171),
      onSolid: _darkInk,
    ),
    info: ToneColors(
      fg: Color(0xFF93C5FD),
      bg: Color(0xFF10203A),
      line: Color(0xFF1E3A5F),
      solid: Color(0xFF93C5FD),
      onSolid: _darkInk,
    ),
    neutral: ToneColors(
      fg: Color(0xFFCBD5E1),
      bg: Color(0xFF1B2533),
      line: Color(0xFF2A3647),
      solid: Color(0xFFCBD5E1),
      onSolid: _darkInk,
    ),
    brandTone: ToneColors(
      fg: Color(0xFFF08A55),
      bg: Color(0xFF2A1A10),
      line: Color(0xFF4A2A18),
      solid: Color(0xFFC94C0C),
      onSolid: _white,
    ),
    dangerFill: Color(0xFFB91C1C),
    onDangerFill: _white,
    scrim: Color(0x99000000),
    shadow: Color(0x52000000),
    skeleton: Color(0xFF1A2432),
    skeletonHighlight: Color(0xFF243043),
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
    Color? logo,
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
      logo: logo ?? this.logo,
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
      logo: c(logo, other.logo),
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

/// 4-pt spacing scale (spec C.5).
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

/// Corner radii (spec C.5): 8 chips and inputs, 12 cards, 16 sheets,
/// 24 hero and bottom bar, pill.
abstract final class AknRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;

  static const BorderRadius chip = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius input = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius card = BorderRadius.all(Radius.circular(md));
  static const BorderRadius sheet = BorderRadius.vertical(
    top: Radius.circular(lg),
  );
  static const BorderRadius dialog = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius hero = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius pillAll = BorderRadius.all(Radius.circular(pill));
}

/// Elevation is a soft shadow plus a 1 px line, never a heavy drop shadow.
abstract final class AknShadows {
  /// Cards: `0 1 3 rgba(15,23,42,.06)`.
  static List<BoxShadow> card(AknColors c) => [
    BoxShadow(color: c.shadow, offset: const Offset(0, 1), blurRadius: 3),
  ];

  /// Toasts, menus, floating elements.
  static List<BoxShadow> raised(AknColors c) => [
    BoxShadow(
      color: c.isDark ? const Color(0x66000000) : const Color(0x1A0F172A),
      offset: const Offset(0, 8),
      blurRadius: 24,
      spreadRadius: -6,
    ),
    BoxShadow(color: c.shadow, offset: const Offset(0, 1), blurRadius: 3),
  ];

  /// Bottom bar (casts upwards).
  static List<BoxShadow> bar(AknColors c) => [
    BoxShadow(
      color: c.isDark ? const Color(0x4D000000) : const Color(0x0F0F172A),
      offset: const Offset(0, -2),
      blurRadius: 16,
    ),
  ];
}

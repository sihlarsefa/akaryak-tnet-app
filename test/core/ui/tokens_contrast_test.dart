// Token facts (design v3 "Akış" §0–§3 + owner colour decisions G and 5): exact light and dark
// values (graphite neutrals, the off-white page with white cards, Gece grafiti at night), the lit
// header band, the button and hero-card gradients, the white hero card with its warm wash, the
// plate palette (`plateInk()`), no purple, no blue, no navy, tinted tone wells, tone lookup, lerp /
// copyWith / equality keep every token (incl. `heroGlow`), spacing, radii and the soft shadows.
// WCAG pairs: contrast_test.dart.
import 'package:akaryakitnet/core/ui/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'foundation_helpers.dart';

List<(String, Color)> _allColors(AknColors c) => [
  ('brand', c.brand),
  ('brandPressed', c.brandPressed),
  ('brandInk', c.brandInk),
  ('brandSoft', c.brandSoft),
  ('brandLine', c.brandLine),
  ('brandFill', c.brandFill),
  ('brandFillPressed', c.brandFillPressed),
  ('onBrandFill', c.onBrandFill),
  ('brandBright', c.brandBright),
  ('logo', c.logo),
  ('heroStart', c.heroStart),
  ('heroEnd', c.heroEnd),
  ('onHero', c.onHero),
  ('onHeroDim', c.onHeroDim),
  ('navy', c.navy),
  ('navyRaised', c.navyRaised),
  ('onNavy', c.onNavy),
  ('onNavyDim', c.onNavyDim),
  ('bg', c.bg),
  ('surface', c.surface),
  ('surfaceAlt', c.surfaceAlt),
  ('surfaceRaised', c.surfaceRaised),
  ('ink', c.ink),
  ('text', c.text),
  ('dim', c.dim),
  ('faint', c.faint),
  ('line', c.line),
  ('lineSoft', c.lineSoft),
  ('lineStrong', c.lineStrong),
  for (final t in AknTone.values) ...[
    ('${t.name}.fg', c.tone(t).fg),
    ('${t.name}.bg', c.tone(t).bg),
    ('${t.name}.line', c.tone(t).line),
    ('${t.name}.solid', c.tone(t).solid),
    ('${t.name}.onSolid', c.tone(t).onSolid),
  ],
  ('dangerFill', c.dangerFill),
  ('onDangerFill', c.onDangerFill),
  ('scrim', c.scrim),
  ('shadow', c.shadow),
  ('skeleton', c.skeleton),
  ('skeletonHighlight', c.skeletonHighlight),
  ('link', c.link),
  ('plate', c.plate),
  ('onPlate', c.onPlate),
  ('plateContext', c.plateContext),
  ('plateLine', c.plateLine),
  ('chartHighlight', c.chartHighlight),
  ('chartContext', c.chartContext),
  ('chartTrack', c.chartTrack),
  ('navInactive', c.navInactive),
  ('inverse', c.inverse),
  ('onInverse', c.onInverse),
  ('heroMid', c.heroMid),
  ('brandFillStart', c.brandFillStart),
  ('plateTint', c.plateTint),
  ('plateBorder', c.plateBorder),
  ('plateAccent', c.plateAccent),
  ('plateIconFill', c.plateIconFill),
  ('deltaFill', c.deltaFill),
  ('homeBg', c.homeBg),
  ('heroGlow', c.heroGlow),
];

bool _purple(Color color) {
  final hsv = HSVColor.fromColor(color);
  return color.a > 0.2 &&
      hsv.saturation > 0.2 &&
      hsv.hue >= 250 &&
      hsv.hue <= 330;
}

/// A visible blue (the only blue allowed is the TR plate strip, not a token).
bool _blue(Color color) {
  final hsv = HSVColor.fromColor(color);
  return color.a > 0.2 &&
      hsv.saturation > 0.3 &&
      hsv.value > 0.3 &&
      hsv.hue >= 190 &&
      hsv.hue < 250;
}

/// Navy-ish: a saturated blue-slate dark surface (the old panel colour).
bool _navySurface(Color color) {
  final hsv = HSVColor.fromColor(color);
  return hsv.value < 0.35 && hsv.saturation > 0.3 && hsv.hue >= 200;
}

/// Distance between two hues on the colour wheel (0–180°).
double _hueGap(Color a, Color b) {
  final d = (HSVColor.fromColor(a).hue - HSVColor.fromColor(b).hue).abs();
  return d > 180 ? 360 - d : d;
}

/// The tinted tone wells of v3 §2: (bg, line) per tone and theme.
const _wells = {
  Brightness.light: {
    AknTone.ok: (Color(0xFFEAF7EF), Color(0xFFC3E8D1)),
    AknTone.warn: (Color(0xFFFDF5E3), Color(0xFFF1DDAE)),
    AknTone.danger: (Color(0xFFFDEFEE), Color(0xFFF6CBC7)),
    AknTone.info: (Color(0xFFEFF0F2), Color(0xFFE1E3E7)),
    AknTone.neutral: (Color(0xFFF1F2F4), Color(0xFFE3E5E8)),
    AknTone.brand: (Color(0xFFFFF1EA), Color(0xFFFFD6C2)),
  },
  Brightness.dark: {
    AknTone.ok: (Color(0xFF13251B), Color(0xFF1F3B2A)),
    AknTone.warn: (Color(0xFF2A2111), Color(0xFF4A3A18)),
    AknTone.danger: (Color(0xFF2C1615), Color(0xFF4D2421)),
    AknTone.info: (Color(0xFF1E2024), Color(0xFF2A2D32)),
    AknTone.neutral: (Color(0xFF1E2024), Color(0xFF2A2D32)),
    AknTone.brand: (Color(0xFF33201A), Color(0xFF5A2A12)),
  },
};

const _black = Color(0xFF000000);
const _white = Color(0xFFFFFFFF);
const _plaka = Color(0xFFFF5001);
const _plakaNight = Color(0xFFE64800);

void main() {
  for (final (name, c) in [
    ('light', AknColors.light),
    ('dark', AknColors.dark),
  ]) {
    group('$name palette', () {
      test('no purple and no blue anywhere (owner decision 5, v3 §0.1)', () {
        for (final (label, color) in [
          ..._allColors(c),
          for (final (l, col) in _allColors(c.plateInk())) ('plate $l', col),
        ]) {
          expect(_purple(color), isFalse, reason: '$label ($color) is purple');
          expect(_blue(color), isFalse, reason: '$label ($color) is blue');
        }
      });

      test('no navy surfaces: page, surfaces, the plate', () {
        for (final (label, color) in [
          ('bg', c.bg),
          ('surface', c.surface),
          ('surfaceAlt', c.surfaceAlt),
          ('surfaceRaised', c.surfaceRaised),
          ('plate', c.plate),
          ('heroEnd', c.heroEnd),
          ('navy (alias)', c.navy),
        ]) {
          expect(_navySurface(color), isFalse, reason: '$label ($color)');
        }
      });

      test('graphite neutrals (v3 §0.1): every grey has saturation < 0.2', () {
        for (final (label, color) in [
          ('bg', c.bg),
          ('homeBg', c.homeBg),
          ('surface', c.surface),
          ('surfaceAlt', c.surfaceAlt),
          ('surfaceRaised', c.surfaceRaised),
          ('ink', c.ink),
          ('dim', c.dim),
          ('faint', c.faint),
          ('line', c.line),
          ('lineSoft', c.lineSoft),
          ('lineStrong', c.lineStrong),
          ('navInactive', c.navInactive),
          ('chartContext', c.chartContext),
          ('chartTrack', c.chartTrack),
          ('skeleton', c.skeleton),
          ('skeletonHighlight', c.skeletonHighlight),
          ('inverse', c.inverse),
          ('info.bg', c.info.bg),
          ('info.line', c.info.line),
          ('neutral.bg', c.neutral.bg),
          ('neutral.line', c.neutral.line),
        ]) {
          expect(
            HSVColor.fromColor(color).saturation,
            lessThan(0.2),
            reason: '$label ($color)',
          );
        }
      });

      test(
        'the band tokens (decision G): white content on the lit band, white-20 % glass',
        () {
          // The hero / navy names carry the orange header band.
          expect(c.navy, c.heroMid);
          expect(c.onHero, _white);
          expect(c.onNavy, _white);
          expect(c.onHeroDim, const Color(0xEBFFFFFF));
          expect(c.onNavyDim, c.onHeroDim);
          expect(c.navyRaised, const Color(0x33FFFFFF));
          // The hero card prints in ink.
          expect(c.onPlate, c.ink);
          expect(c.logo, c.brandBright);
          expect(c.logo, _plaka);
          // 135°: heroStart → heroMid (50 %) → heroEnd.
          final band = c.bandGradient;
          expect(band.colors, [c.heroStart, c.heroMid, c.heroEnd]);
          expect(band.stops, const [0.0, 0.5, 1.0]);
          expect(band.begin, Alignment.topLeft);
          expect(band.end, Alignment.bottomRight);
          expect(c.buttonGradient.colors, [c.brandFillStart, c.brandFill]);
          // Settles into brandFill by the middle: the centred white label
          // always sits on ≥ 3:1.
          expect(c.buttonGradient.stops, const [0.0, 0.5]);
          expect(c.plateGradient.colors, [c.plateTint, c.plate]);
          expect(c.plateGradient.stops, const [0.0, 0.55]);
          expect(c.plateGradient.begin, Alignment.topCenter);
          final deco = c.plateDecoration();
          expect(deco.gradient, c.plateGradient);
          expect(deco.borderRadius, AknRadius.plate);
          expect(deco.border, Border.all(color: c.plateBorder));
          expect(deco.boxShadow, AknShadows.plate(c));
          expect(
            c.plateDecoration(raised: false).boxShadow,
            AknShadows.plateBehind(c),
          );
          expect(c.isPlatePalette, isFalse);
          expect(c.plateInk().isPlatePalette, isTrue);
          expect(c.isBandPalette, isFalse);
        },
      );

      test('tone() returns the matching ToneColors', () {
        expect(c.tone(AknTone.ok), c.ok);
        expect(c.tone(AknTone.warn), c.warn);
        expect(c.tone(AknTone.danger), c.danger);
        expect(c.tone(AknTone.info), c.info);
        expect(c.tone(AknTone.neutral), c.neutral);
        expect(c.tone(AknTone.brand), c.brandTone);
        // "Your move": Pas text, logo-orange dot, brandSoft well.
        expect(c.brandTone.fg, c.brandInk);
        expect(c.brandTone.bg, c.brandSoft);
        expect(c.brandTone.line, c.brandLine);
        expect(c.brandTone.solid, c.logo);
        expect(c.brandTone.onSolid, _black);
      });

      test(
        'tinted wells (v3 §2): every tone has a soft well and its border',
        () {
          for (final t in AknTone.values) {
            final (bg, line) = _wells[c.brightness]![t]!;
            expect(c.tone(t).bg, bg, reason: '${t.name}.bg');
            expect(c.tone(t).line, line, reason: '${t.name}.line');
            // The border is a shade deeper than its well, seen from the page.
            expect(
              wcag(line, c.bg),
              greaterThan(wcag(bg, c.bg)),
              reason: '${t.name}: border vs well',
            );
          }
          // Status wells carry their tone's hue: green, ochre, red, orange …
          for (final t in [
            AknTone.ok,
            AknTone.warn,
            AknTone.danger,
            AknTone.brand,
          ]) {
            for (final well in [c.tone(t).bg, c.tone(t).line]) {
              expect(
                _hueGap(well, c.tone(t).solid),
                lessThan(10),
                reason: '${t.name} well $well',
              );
            }
          }
          // … info is an ink lamp on the plain well (no blue); neutral is dim.
          expect(c.info.fg, c.ink);
          expect(c.info.solid, c.ink);
          expect(c.info.bg, c.surfaceAlt);
          expect(c.neutral.fg, c.dim);
        },
      );

      test('one ink: text = ink, links are ink, body never grey', () {
        expect(c.text, c.ink);
        expect(c.link, c.ink);
        expect(c.lineStrong, isNot(c.line));
      });

      test('the primary button: orange gradient, white label (decision G)', () {
        expect(c.brandFillStart, const Color(0xFFFF7B35));
        expect(c.brandFill, const Color(0xFFE5530A));
        expect(c.onBrandFill, _white);
        expect(c.buttonGradient.begin, Alignment.topLeft);
        expect(c.buttonGradient.end, Alignment.bottomRight);
        expect(c.buttonGradientPressed.colors, [
          c.brandFill,
          c.brandFillPressed,
        ]);
        expect(c.chartHighlight, _plaka);
      });
    });
  }

  test('light tokens are the spec values (v3 §2)', () {
    const l = AknColors.light;
    expect(l.brightness, Brightness.light);
    expect(l.brand, _plaka);
    expect(l.brandPressed, _plakaNight);
    expect(l.brandInk, const Color(0xFFC2410C));
    expect(l.brandSoft, const Color(0xFFFFF1EA));
    expect(l.brandLine, const Color(0xFFFFD6C2));
    expect(l.brandFill, const Color(0xFFE5530A));
    expect(l.brandFillStart, const Color(0xFFFF7B35));
    expect(l.brandFillPressed, const Color(0xFFCC4708));
    expect(l.onBrandFill, _white);
    expect(l.brandBright, _plaka);
    expect(l.logo, _plaka);
    // The header band (135°): #FF8A3D → #F2581A → #D9440A, lit by #FFC59E.
    expect(l.heroStart, const Color(0xFFFF8A3D));
    expect(l.heroMid, const Color(0xFFF2581A));
    expect(l.heroEnd, const Color(0xFFD9440A));
    expect(l.heroGlow, const Color(0xFFFFC59E));
    expect(l.onHero, _white);
    expect(l.onHeroDim, const Color(0xEBFFFFFF));
    // Off-white page, white cards, graphite wells.
    expect(l.bg, const Color(0xFFF5F6F7));
    expect(l.homeBg, const Color(0xFFF5F6F7));
    expect(l.surface, _white);
    expect(l.surfaceAlt, const Color(0xFFEFF0F2));
    expect(l.surfaceRaised, _white);
    expect(l.ink, const Color(0xFF15171A));
    expect(l.text, const Color(0xFF15171A));
    expect(l.link, const Color(0xFF15171A));
    expect(l.dim, const Color(0xFF5F646C));
    expect(l.faint, const Color(0xFF9A9FA6));
    expect(l.line, const Color(0xFFE6E8EB));
    expect(l.lineSoft, const Color(0xFFEEF0F2));
    expect(l.lineStrong, const Color(0xFF858B93));
    expect(l.navInactive, const Color(0xFF6B7079));
    // Tones: fg / bg / line / solid / onSolid.
    expect(
      l.ok,
      const ToneColors(
        fg: Color(0xFF0F7A43),
        bg: Color(0xFFEAF7EF),
        line: Color(0xFFC3E8D1),
        solid: Color(0xFF15803D),
        onSolid: _white,
      ),
    );
    expect(
      l.warn,
      const ToneColors(
        fg: Color(0xFF8A5A00),
        bg: Color(0xFFFDF5E3),
        line: Color(0xFFF1DDAE),
        solid: Color(0xFF9A6700),
        onSolid: _white,
      ),
    );
    expect(
      l.danger,
      const ToneColors(
        fg: Color(0xFFC0261C),
        bg: Color(0xFFFDEFEE),
        line: Color(0xFFF6CBC7),
        solid: Color(0xFFD92D20),
        onSolid: _white,
      ),
    );
    expect(
      l.info,
      const ToneColors(
        fg: Color(0xFF15171A),
        bg: Color(0xFFEFF0F2),
        line: Color(0xFFE1E3E7),
        solid: Color(0xFF15171A),
        onSolid: _white,
      ),
    );
    expect(
      l.neutral,
      const ToneColors(
        fg: Color(0xFF5F646C),
        bg: Color(0xFFF1F2F4),
        line: Color(0xFFE3E5E8),
        solid: Color(0xFF5F646C),
        onSolid: _white,
      ),
    );
    expect(
      l.brandTone,
      const ToneColors(
        fg: Color(0xFFC2410C),
        bg: Color(0xFFFFF1EA),
        line: Color(0xFFFFD6C2),
        solid: _plaka,
        onSolid: _black,
      ),
    );
    expect(l.dangerFill, const Color(0xFFC0261C));
    expect(l.onDangerFill, _white);
    // Scrim ink 45 %, shadow ink 16 %.
    expect(l.scrim, const Color(0x7315171A));
    expect(l.shadow, const Color(0x2915171A));
    expect(l.skeleton, const Color(0xFFECEEF0));
    expect(l.skeletonHighlight, const Color(0xFFF8F9FA));
    // The hero card (decision G): white with a warm wash at the top.
    expect(l.plate, _white);
    expect(l.onPlate, const Color(0xFF15171A));
    expect(l.plateTint, const Color(0xFFFFF4EE));
    expect(l.plateBorder, const Color(0xFFF5E3D8));
    expect(l.plateAccent, const Color(0xFFE5530A));
    expect(l.plateIconFill, const Color(0xFFFFEDE3));
    expect(l.deltaFill, const Color(0xFFFFF1EA));
    // Past bars: #FF5001 at 24 %.
    expect(l.plateContext, const Color(0x3DFF5001));
    expect(l.plateLine, const Color(0xFFF3E4DB));
    expect(l.chartHighlight, _plaka);
    expect(l.chartContext, const Color(0xFF858B93));
    expect(l.chartTrack, const Color(0xFFEEF0F2));
    expect(l.inverse, const Color(0xFF1B1D21));
    expect(l.onInverse, _white);
  });

  test('dark tokens are the spec values (v3 §2): Gece grafiti', () {
    const d = AknColors.dark;
    const night = Color(0xFF0E0F11);
    expect(d.brightness, Brightness.dark);
    expect(d.brand, _plaka);
    expect(d.brandPressed, _plakaNight);
    expect(d.brandInk, const Color(0xFFFF7A3D));
    expect(d.brandSoft, const Color(0xFF33201A));
    expect(d.brandLine, const Color(0xFF5A2A12));
    // The primary keeps its gradient with a white label; the band deepens.
    expect(d.brandFill, const Color(0xFFE5530A));
    expect(d.brandFillStart, const Color(0xFFFF7B35));
    expect(d.brandFillPressed, const Color(0xFFC2410C));
    expect(d.onBrandFill, _white);
    expect(d.brandBright, _plaka);
    expect(d.logo, _plaka);
    expect(d.heroStart, const Color(0xFFC2410C));
    expect(d.heroMid, const Color(0xFF9F350A));
    expect(d.heroEnd, const Color(0xFF7A2A08));
    expect(d.heroGlow, const Color(0xFFFF8A4C));
    expect(d.onHero, _white);
    expect(d.onHeroDim, const Color(0xEBFFFFFF));
    // Graphite, never navy.
    expect(d.bg, night);
    expect(d.homeBg, night);
    expect(d.surface, const Color(0xFF17181B));
    expect(d.surfaceAlt, const Color(0xFF1E2024));
    expect(d.surfaceRaised, const Color(0xFF222429));
    expect(d.ink, const Color(0xFFF2F3F5));
    expect(d.text, const Color(0xFFF2F3F5));
    expect(d.link, const Color(0xFFF2F3F5));
    expect(d.dim, const Color(0xFFA2A7AF));
    expect(d.faint, const Color(0xFF6F747C));
    expect(d.line, const Color(0xFF2A2D32));
    expect(d.lineSoft, const Color(0xFF212327));
    expect(d.lineStrong, const Color(0xFF6C7179));
    expect(d.navInactive, const Color(0xFFA2A7AF));
    expect(
      d.ok,
      const ToneColors(
        fg: Color(0xFF4ADE80),
        bg: Color(0xFF13251B),
        line: Color(0xFF1F3B2A),
        solid: Color(0xFF4ADE80),
        onSolid: night,
      ),
    );
    expect(
      d.warn,
      const ToneColors(
        fg: Color(0xFFF5B83D),
        bg: Color(0xFF2A2111),
        line: Color(0xFF4A3A18),
        solid: Color(0xFFF5B83D),
        onSolid: night,
      ),
    );
    expect(
      d.danger,
      const ToneColors(
        fg: Color(0xFFFF7A70),
        bg: Color(0xFF2C1615),
        line: Color(0xFF4D2421),
        solid: Color(0xFFFF7A70),
        onSolid: night,
      ),
    );
    expect(
      d.info,
      const ToneColors(
        fg: Color(0xFFF2F3F5),
        bg: Color(0xFF1E2024),
        line: Color(0xFF2A2D32),
        solid: Color(0xFFF2F3F5),
        onSolid: night,
      ),
    );
    expect(
      d.neutral,
      const ToneColors(
        fg: Color(0xFFA2A7AF),
        bg: Color(0xFF1E2024),
        line: Color(0xFF2A2D32),
        solid: Color(0xFFA2A7AF),
        onSolid: night,
      ),
    );
    expect(
      d.brandTone,
      const ToneColors(
        fg: Color(0xFFFF7A3D),
        bg: Color(0xFF33201A),
        line: Color(0xFF5A2A12),
        solid: _plaka,
        onSolid: _black,
      ),
    );
    expect(d.dangerFill, const Color(0xFFC0261C));
    expect(d.onDangerFill, _white);
    expect(d.scrim, const Color(0x99000000));
    expect(d.shadow, const Color(0x99000000));
    expect(d.skeleton, const Color(0xFF1E2024));
    expect(d.skeletonHighlight, const Color(0xFF26292E));
    // The dark hero card: #17181B with a warm wash at the top, white
    // figures.
    expect(d.plate, const Color(0xFF17181B));
    expect(d.onPlate, const Color(0xFFF2F3F5));
    expect(d.plateTint, const Color(0xFF2A1E18));
    expect(d.plateBorder, const Color(0xFF3A2A21));
    expect(d.plateAccent, const Color(0xFFFF7A3D));
    expect(d.plateIconFill, const Color(0xFF3A2116));
    expect(d.deltaFill, const Color(0xFF3A2116));
    // Past bars: #FF5001 at 40 %.
    expect(d.plateContext, const Color(0x66FF5001));
    expect(d.plateLine, const Color(0xFF3A2A21));
    expect(d.chartHighlight, _plaka);
    expect(d.chartContext, const Color(0xFF7D838B));
    expect(d.chartTrack, const Color(0xFF26292E));
    expect(d.inverse, const Color(0xFF2C2F35));
    expect(d.onInverse, _white);
  });

  group('plateInk(): the palette printed on the hero card (v3 §2)', () {
    for (final base in [AknColors.light, AknColors.dark]) {
      test(base.isDark ? 'dark' : 'light', () {
        final p = base.plateInk();
        // Ink stays ink on the white card (decision G).
        expect(p.ink, base.onPlate);
        expect(p.text, base.onPlate);
        expect(p.dim, base.dim);
        expect(p.faint, base.faint);
        expect(p.lineStrong, base.lineStrong);
        expect(p.brand, base.brand);
        expect(p.brandInk, base.brandInk);
        expect(p.link, base.link);
        expect(p.navInactive, base.navInactive);
        expect(p.line, base.plateLine);
        expect(p.lineSoft, base.plateLine);
        for (final s in [p.bg, p.surface, p.surfaceRaised]) {
          expect(s, base.plate);
        }
        // Quiet wells on the card are the soft orange of the delta chip.
        expect(p.surfaceAlt, base.deltaFill);
        // Tones keep their colours (the card is white).
        for (final t in AknTone.values) {
          expect(p.tone(t), base.tone(t), reason: t.name);
        }
        // Charts: the orange accent — past bars #FF5001 at 24 % (40 % at
        // night), this month plateAccent, tracks the icon-tile orange.
        expect(p.chartHighlight, base.plateAccent);
        expect(p.chartContext, base.plateContext);
        expect(p.chartTrack, base.plateIconFill);
        // The plate itself, its ink and the brightness are kept.
        expect(p.plate, base.plate);
        expect(p.onPlate, base.onPlate);
        expect(p.plateContext, base.plateContext);
        expect(p.brightness, base.brightness);
        expect(p.logo, base.logo);
        expect(p.heroGlow, base.heroGlow);
        // Idempotent: a plate inside a plate keeps the palette.
        expect(p.plateInk(), p);
      });
    }
  });

  test('lerp, copyWith and equality keep every token (incl. heroGlow)', () {
    const l = AknColors.light;
    const d = AknColors.dark;
    expect(l.lerp(d, 0), l);
    expect(l.lerp(d, 1), d);
    final mid = l.lerp(d, 0.5);
    expect(mid.plate, Color.lerp(l.plate, d.plate, 0.5));
    expect(mid.chartContext, Color.lerp(l.chartContext, d.chartContext, 0.5));
    expect(mid.navInactive, Color.lerp(l.navInactive, d.navInactive, 0.5));
    expect(mid.heroGlow, Color.lerp(l.heroGlow, d.heroGlow, 0.5));
    expect(l.lerp(null, 0.5), l);
    // The deck hand-off: paper → plate.
    final paper = l;
    final plate = l.plateInk();
    final handOff = paper.lerp(plate, 0.5);
    expect(handOff.surface, Color.lerp(paper.surface, plate.surface, 0.5));
    expect(handOff.ink, Color.lerp(paper.ink, plate.ink, 0.5));
    expect(mid.plateTint, Color.lerp(l.plateTint, d.plateTint, 0.5));
    expect(mid.heroMid, Color.lerp(l.heroMid, d.heroMid, 0.5));
    expect(paper.lerp(plate, 1), plate);

    expect(l.copyWith(), l);
    expect(l.copyWith().hashCode, l.hashCode);
    final changed = l.copyWith(
      brand: _black,
      plate: const Color(0xFF111111),
      chartTrack: const Color(0xFF222222),
      onInverse: const Color(0xFF333333),
    );
    expect(changed.brand, _black);
    expect(changed.plate, const Color(0xFF111111));
    expect(changed.chartTrack, const Color(0xFF222222));
    expect(changed.onInverse, const Color(0xFF333333));
    final g = l.copyWith(
      plateTint: _black,
      deltaFill: _black,
      homeBg: _black,
      brandFillStart: _black,
      heroGlow: _black,
    );
    expect(g.plateTint, _black);
    expect(g.deltaFill, _black);
    expect(g.homeBg, _black);
    expect(g.brandFillStart, _black);
    expect(g.heroGlow, _black);
    expect(g, isNot(l));
    expect(g.hashCode, isNot(l.hashCode));
    // The new field alone takes part in equality and the hash.
    final glow = l.copyWith(heroGlow: _black);
    expect(glow, isNot(l));
    expect(glow.hashCode, isNot(l.hashCode));
    expect(glow.copyWith(heroGlow: l.heroGlow), l);
    expect(changed.heroEnd, l.heroEnd);
    expect(changed.onHero, l.onHero);
    expect(changed.heroGlow, l.heroGlow);
    expect(changed, isNot(l));
    expect(
      const ToneColors(
        fg: _black,
        bg: _white,
        line: _white,
        solid: _black,
        onSolid: _white,
      ).copyWith(fg: _white).fg,
      _white,
    );
  });

  test(
    'spacing (v3 §3–4): 20 px gutter, hero-card and row insets, 64 driver tap',
    () {
      expect(AknSpace.page, 20);
      expect(AknSpace.pagePadding, const EdgeInsets.symmetric(horizontal: 20));
      expect(AknSpace.section, 24);
      expect(AknSpace.minTap, 48);
      expect(AknSpace.driverTap, 64);
      expect(AknSpace.plate, const EdgeInsets.fromLTRB(20, 18, 20, 16));
      expect(
        AknSpace.row,
        const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      );
      expect(
        AknSpace.well,
        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
      expect(AknSpace.cardPadding, const EdgeInsets.all(16));
      for (final (v, e) in [
        (AknSpace.s2, 2.0),
        (AknSpace.s4, 4.0),
        (AknSpace.s6, 6.0),
        (AknSpace.s8, 8.0),
        (AknSpace.s12, 12.0),
        (AknSpace.s16, 16.0),
        (AknSpace.s20, 20.0),
        (AknSpace.s24, 24.0),
        (AknSpace.s32, 32.0),
        (AknSpace.s40, 40.0),
        (AknSpace.s48, 48.0),
      ]) {
        expect(v, e);
      }
    },
  );

  test('radii by size (v3 §3)', () {
    expect(AknRadius.xs, 8);
    expect(AknRadius.sm, 12);
    expect(AknRadius.md, 14);
    expect(AknRadius.lg, 24);
    expect(AknRadius.xl, 28);
    expect(AknRadius.xxl, 28);
    expect(AknRadius.driver, 18);
    // Tags and the delta chip 8, small buttons 12, inputs 14, buttons 16,
    // cards 20.
    expect(AknRadius.tag, const BorderRadius.all(Radius.circular(8)));
    expect(AknRadius.buttonSmall, const BorderRadius.all(Radius.circular(12)));
    expect(AknRadius.input, const BorderRadius.all(Radius.circular(14)));
    expect(AknRadius.button, const BorderRadius.all(Radius.circular(16)));
    expect(AknRadius.buttonDriver, const BorderRadius.all(Radius.circular(18)));
    expect(AknRadius.card, const BorderRadius.all(Radius.circular(20)));
    // The hero card (decision G) 26; white home sections 22.
    expect(AknRadius.plateRadius, 26);
    expect(AknRadius.hero, const BorderRadius.all(Radius.circular(26)));
    expect(AknRadius.plate, AknRadius.hero);
    expect(AknRadius.section, const BorderRadius.all(Radius.circular(22)));
    // Sheets (top) and dialogs 28.
    expect(AknRadius.dialog, const BorderRadius.all(Radius.circular(28)));
    expect(AknRadius.sheet.topLeft, const Radius.circular(28));
    expect(AknRadius.sheet.topRight, const Radius.circular(28));
    expect(AknRadius.sheet.bottomLeft, Radius.zero);
    // Chips, segmented tracks, badges and avatars are pills.
    expect(AknRadius.chip, AknRadius.pillAll);
    expect(AknRadius.pillAll.topLeft.x, greaterThanOrEqualTo(999));
    // The orange header strip is gone.
    expect(AknRadius.header, BorderRadius.zero);
  });

  test('depth by role (v3 §3): cards float, brand moments glow warm', () {
    const l = AknColors.light;
    const d = AknColors.dark;
    // Resting cards: 0 1 2 ink 4 % + 0 8 24 −6 ink 8 % (dark: black 40 %).
    expect(AknShadows.card(l), const [
      BoxShadow(color: Color(0x0A15171A), offset: Offset(0, 1), blurRadius: 2),
      BoxShadow(
        color: Color(0x1415171A),
        offset: Offset(0, 8),
        blurRadius: 24,
        spreadRadius: -6,
      ),
    ]);
    expect(AknShadows.card(d), const [
      BoxShadow(color: Color(0x66000000), offset: Offset(0, 1), blurRadius: 2),
    ]);
    // Pressed cards settle onto the page: only the contact shadow.
    expect(AknShadows.pressed(l), [AknShadows.card(l).first]);
    expect(AknShadows.pressed(d), isEmpty);
    // Sheets, menus, toasts, dialogs: 0 2 6 ink 6 % + 0 24 48 −12 ink 24 %.
    expect(AknShadows.raised(l), const [
      BoxShadow(color: Color(0x0F15171A), offset: Offset(0, 2), blurRadius: 6),
      BoxShadow(
        color: Color(0x3D15171A),
        offset: Offset(0, 24),
        blurRadius: 48,
        spreadRadius: -12,
      ),
    ]);
    expect(AknShadows.raised(d), const [
      BoxShadow(
        color: Color(0xB3000000),
        offset: Offset(0, 24),
        blurRadius: 48,
        spreadRadius: -12,
      ),
    ]);
    // The hero card: a warm contact shadow + 0 18 36 −10 ink 16 %.
    expect(AknShadows.plate(l), const [
      BoxShadow(color: Color(0x0FE5530A), offset: Offset(0, 2), blurRadius: 6),
      BoxShadow(
        color: Color(0x2915171A),
        offset: Offset(0, 18),
        blurRadius: 36,
        spreadRadius: -10,
      ),
    ]);
    expect(AknShadows.plate(d), const [
      BoxShadow(
        color: Color(0x99000000),
        offset: Offset(0, 18),
        blurRadius: 36,
        spreadRadius: -10,
      ),
    ]);
    expect(AknShadows.plateBehind(l), const [
      BoxShadow(
        color: Color(0x1A15171A),
        offset: Offset(0, 6),
        blurRadius: 14,
        spreadRadius: -6,
      ),
    ]);
    // The header band: 0 12 28 −8 #D9440A 40 % (dark black 50 %).
    expect(AknShadows.band(l), const [
      BoxShadow(
        color: Color(0x66D9440A),
        offset: Offset(0, 12),
        blurRadius: 28,
        spreadRadius: -8,
      ),
    ]);
    expect(AknShadows.band(d).single.color, const Color(0x80000000));
    // The primary's warm glow: 0 8 18 −6 #E5530A 55 % (dark 35 %).
    expect(AknShadows.button(l), const [
      BoxShadow(
        color: Color(0x8CE5530A),
        offset: Offset(0, 8),
        blurRadius: 18,
        spreadRadius: -6,
      ),
    ]);
    expect(AknShadows.button(d).single.color, const Color(0x59E5530A));
    // The bottom bar lifts off the content: 0 −8 24 ink 6 % (dark black 35 %).
    expect(AknShadows.bar(l), const [
      BoxShadow(
        color: Color(0x0F15171A),
        offset: Offset(0, -8),
        blurRadius: 24,
      ),
    ]);
    expect(AknShadows.bar(d).single.color, const Color(0x59000000));
    for (final c in [l, d]) {
      expect(AknShadows.dragged(c), AknShadows.raised(c));
      expect(AknShadows.hero(c), AknShadows.plate(c));
      // Every shadow falls downwards (the bar's lifts upwards), none is
      // flat any more.
      for (final s in [
        ...AknShadows.card(c),
        ...AknShadows.raised(c),
        ...AknShadows.plate(c),
        ...AknShadows.plateBehind(c),
        ...AknShadows.band(c),
        ...AknShadows.button(c),
      ]) {
        expect(s.offset.dy, greaterThan(0));
        expect(s.blurRadius, greaterThan(0));
      }
    }
    // A soft halo around a mark: the colour at 35 %, 24 blur.
    expect(AknShadows.glow(_plaka), [
      BoxShadow(
        color: _plaka.withValues(alpha: 0.35),
        blurRadius: 24,
        spreadRadius: -4,
      ),
    ]);
  });
}

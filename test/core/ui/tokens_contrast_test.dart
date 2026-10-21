// Token facts (design v2 "Turuncu Plaka" §2, §4 + owner colour decision G "F2GO kart dili",
// 2026-10-21): exact light and dark values, the header band and button gradients, the white plate
// card with its soft orange tint, the plate palette (`plateInk()`), no purple, no blue, tone lookup,
// lerp / copyWith / equality keep every token, spacing, radii and shadows. WCAG pairs:
// contrast_test.dart.
import 'package:akaryakitnet/core/ui/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
      test('no purple and no blue anywhere (owner decision 5, §2.1)', () {
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

      test(
        'the band tokens (decision G): white content, white-22 % squares',
        () {
          // The hero / navy names now carry the orange header band.
          expect(c.navy, c.heroMid);
          expect(c.onHero, _white);
          expect(c.onNavy, _white);
          expect(c.onHeroDim, const Color(0xEBFFFFFF));
          expect(c.onNavyDim, c.onHeroDim);
          expect(c.navyRaised, const Color(0x38FFFFFF));
          // The plate card prints in ink.
          expect(c.onPlate, c.ink);
          expect(c.logo, c.brandBright);
          expect(c.logo, _plaka);
          final band = c.bandGradient;
          expect(band.colors, [c.heroStart, c.heroMid, c.heroEnd]);
          expect(band.stops, const [0.0, 0.5, 1.0]);
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
        // "Your move": Pas text, logo-orange dot, brandSoft halo.
        expect(c.brandTone.fg, c.brandInk);
        expect(c.brandTone.bg, c.brandSoft);
        expect(c.brandTone.solid, c.logo);
        expect(c.brandTone.onSolid, _black);
      });

      test('no pastel tints: every tone well is Beton with the hairline', () {
        for (final t in AknTone.values.where((t) => t != AknTone.brand)) {
          expect(c.tone(t).bg, c.surfaceAlt, reason: t.name);
          expect(c.tone(t).line, c.line, reason: t.name);
        }
        // Info is an ink lamp; neutral is dim.
        expect(c.info.fg, c.ink);
        expect(c.info.solid, c.ink);
        expect(c.neutral.fg, c.dim);
      });

      test('one ink: text = ink, links are ink, body never grey', () {
        expect(c.text, c.ink);
        expect(c.link, c.ink);
        expect(c.lineStrong, isNot(c.line));
      });

      test('the primary button: orange gradient, white label (decision G)', () {
        expect(c.brandFillStart, const Color(0xFFF7742F));
        expect(c.brandFill, const Color(0xFFE8590C));
        expect(c.onBrandFill, _white);
        expect(c.buttonGradientPressed.colors, [
          c.brandFill,
          c.brandFillPressed,
        ]);
        expect(c.chartHighlight, _plaka);
      });
    });
  }

  test('light tokens are the spec values (§2.2)', () {
    const l = AknColors.light;
    expect(l.brightness, Brightness.light);
    expect(l.brand, _plaka);
    expect(l.brandPressed, _plakaNight);
    expect(l.brandInk, const Color(0xFFC2410C));
    expect(l.brandSoft, const Color(0xFFFFF3EC));
    expect(l.brandLine, const Color(0xFFFFD3BD));
    expect(l.brandFill, const Color(0xFFE8590C));
    expect(l.brandFillStart, const Color(0xFFF7742F));
    expect(l.brandFillPressed, const Color(0xFFCF4E0A));
    expect(l.onBrandFill, _white);
    expect(l.brandBright, _plaka);
    expect(l.logo, _plaka);
    // The header band (135°): #FF8A47 → #F26A21 → #E2560E.
    expect(l.heroStart, const Color(0xFFFF8A47));
    expect(l.heroMid, const Color(0xFFF26A21));
    expect(l.heroEnd, const Color(0xFFE2560E));
    expect(l.bg, _white);
    expect(l.surface, _white);
    expect(l.surfaceAlt, const Color(0xFFF3F4F6));
    expect(l.surfaceRaised, _white);
    expect(l.ink, const Color(0xFF1E2227));
    expect(l.text, const Color(0xFF1E2227));
    expect(l.dim, const Color(0xFF5D646D));
    expect(l.faint, const Color(0xFF8B929B));
    expect(l.line, const Color(0xFFE4E6E9));
    expect(l.lineSoft, const Color(0xFFEEF0F2));
    expect(l.lineStrong, const Color(0xFF8B929B));
    expect(l.ok.fg, const Color(0xFF18794E));
    expect(l.ok.solid, const Color(0xFF18794E));
    expect(l.ok.onSolid, _white);
    expect(l.warn.fg, const Color(0xFF8A5A00));
    expect(l.warn.solid, const Color(0xFF8A5A00));
    expect(l.danger.fg, const Color(0xFFC0261C));
    expect(l.danger.solid, const Color(0xFFC0261C));
    expect(l.info.fg, const Color(0xFF1E2227));
    expect(l.neutral.fg, const Color(0xFF5D646D));
    expect(l.brandTone.fg, const Color(0xFFC2410C));
    expect(l.brandTone.bg, const Color(0xFFFFF3EC));
    expect(l.brandTone.line, const Color(0xFFFFD3BD));
    expect(l.brandTone.solid, _plaka);
    expect(l.dangerFill, const Color(0xFFC0261C));
    expect(l.onDangerFill, _white);
    expect(l.scrim, const Color(0x7A1E2227));
    expect(l.shadow, const Color(0x291E2227));
    expect(l.skeleton, const Color(0xFFF3F4F6));
    expect(l.skeletonHighlight, const Color(0xFFF9FAFB));
    expect(l.link, const Color(0xFF1E2227));
    // The plate card (decision G).
    expect(l.plate, _white);
    expect(l.onPlate, const Color(0xFF1E2227));
    expect(l.plateTint, const Color(0xFFFFEDE2));
    expect(l.plateBorder, const Color(0xFFF8DCCB));
    expect(l.plateAccent, const Color(0xFFE8590C));
    expect(l.plateIconFill, const Color(0xFFFFE6D6));
    expect(l.deltaFill, const Color(0xFFFFF1E8));
    expect(l.plateContext, const Color(0x4DF05A12));
    expect(l.plateLine, const Color(0xFFF3D9C8));
    expect(l.homeBg, const Color(0xFFF9FAFB));
    expect(l.chartHighlight, _plaka);
    expect(l.chartContext, const Color(0xFF8B929B));
    expect(l.chartTrack, const Color(0xFFEEF0F2));
    expect(l.navInactive, const Color(0xFF6B727B));
    expect(l.inverse, const Color(0xFF1E2227));
    expect(l.onInverse, _white);
  });

  test('dark tokens are the spec values (§2.2): gece asfaltı', () {
    const d = AknColors.dark;
    expect(d.brightness, Brightness.dark);
    expect(d.brand, _plaka);
    expect(d.brandPressed, _plakaNight);
    expect(d.brandInk, const Color(0xFFFF7A3D));
    expect(d.brandSoft, const Color(0xFF3A2116));
    expect(d.brandLine, const Color(0xFF5A2A12));
    // The primary keeps its gradient with a white label; the band deepens.
    expect(d.brandFill, const Color(0xFFE8590C));
    expect(d.brandFillStart, const Color(0xFFF7742F));
    expect(d.brandFillPressed, const Color(0xFFC2410C));
    expect(d.onBrandFill, _white);
    expect(d.brandBright, _plaka);
    expect(d.logo, _plaka);
    expect(d.heroStart, const Color(0xFFC2410C));
    expect(d.heroEnd, const Color(0xFF9A3A09));
    expect(d.bg, const Color(0xFF16191D));
    expect(d.surface, const Color(0xFF1F2328));
    expect(d.surfaceAlt, const Color(0xFF23272D));
    expect(d.surfaceRaised, const Color(0xFF282C32));
    expect(d.ink, const Color(0xFFF1F2F4));
    expect(d.text, const Color(0xFFF1F2F4));
    expect(d.dim, const Color(0xFFA3A9B2));
    expect(d.faint, const Color(0xFF7D848D));
    expect(d.line, const Color(0xFF2E333A));
    expect(d.lineSoft, const Color(0xFF262A30));
    expect(d.lineStrong, const Color(0xFF6E757E));
    expect(d.ok.fg, const Color(0xFF5CC98A));
    expect(d.ok.onSolid, const Color(0xFF16191D));
    expect(d.warn.fg, const Color(0xFFF5B83D));
    expect(d.danger.fg, const Color(0xFFFF7A70));
    expect(d.info.fg, const Color(0xFFF1F2F4));
    expect(d.neutral.fg, const Color(0xFFA3A9B2));
    expect(d.brandTone.fg, const Color(0xFFFF7A3D));
    expect(d.brandTone.bg, const Color(0xFF3A2116));
    expect(d.brandTone.solid, _plaka);
    expect(d.dangerFill, const Color(0xFFC0261C));
    expect(d.scrim, const Color(0x99000000));
    expect(d.shadow, const Color(0x99000000));
    expect(d.skeleton, const Color(0xFF23272D));
    expect(d.skeletonHighlight, const Color(0xFF2A2F35));
    expect(d.link, const Color(0xFFF1F2F4));
    // The dark card: #1F2328 with a 10 % orange tint at the top, white
    // figures.
    expect(d.plate, const Color(0xFF1F2328));
    expect(d.onPlate, const Color(0xFFF1F2F4));
    expect(d.plateTint, const Color(0xFF332825));
    expect(d.plateBorder, const Color(0xFF432D23));
    expect(d.plateAccent, const Color(0xFFFF7A3D));
    expect(d.plateIconFill, const Color(0xFF3A2116));
    expect(d.deltaFill, const Color(0xFF3A2116));
    expect(d.plateContext, const Color(0x73F05A12));
    expect(d.plateLine, const Color(0xFF3D2B22));
    expect(d.homeBg, d.bg);
    expect(d.chartHighlight, _plaka);
    expect(d.chartContext, const Color(0xFF6B717B));
    expect(d.chartTrack, const Color(0xFF2A2F35));
    expect(d.navInactive, const Color(0xFFA3A9B2));
    expect(d.inverse, const Color(0xFF3A3F46));
    expect(d.onInverse, _white);
  });

  group('plateInk(): the palette printed on the plate (§2.2)', () {
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
        // Charts: orange accent — past bars #F05A12 30 %, this month
        // #E8590C, tracks the icon-tile orange.
        expect(p.chartHighlight, base.plateAccent);
        expect(p.chartContext, base.plateContext);
        expect(p.chartTrack, base.plateIconFill);
        // The plate itself, its ink and the brightness are kept.
        expect(p.plate, base.plate);
        expect(p.onPlate, base.onPlate);
        expect(p.plateContext, base.plateContext);
        expect(p.brightness, base.brightness);
        expect(p.logo, base.logo);
        // Idempotent: a plate inside a plate keeps the palette.
        expect(p.plateInk(), p);
      });
    }
  });

  test('lerp, copyWith and equality keep every token (incl. new ones)', () {
    const l = AknColors.light;
    const d = AknColors.dark;
    expect(l.lerp(d, 0), l);
    expect(l.lerp(d, 1), d);
    final mid = l.lerp(d, 0.5);
    expect(mid.plate, Color.lerp(l.plate, d.plate, 0.5));
    expect(mid.chartContext, Color.lerp(l.chartContext, d.chartContext, 0.5));
    expect(mid.navInactive, Color.lerp(l.navInactive, d.navInactive, 0.5));
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
    );
    expect(g.plateTint, _black);
    expect(g.deltaFill, _black);
    expect(g.homeBg, _black);
    expect(g.brandFillStart, _black);
    expect(g, isNot(l));
    expect(g.hashCode, isNot(l.hashCode));
    expect(changed.heroEnd, l.heroEnd);
    expect(changed.onHero, l.onHero);
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

  test('spacing (§4.1): 20 px gutter, plate and row insets, 64 driver tap', () {
    expect(AknSpace.page, 20);
    expect(AknSpace.pagePadding, const EdgeInsets.symmetric(horizontal: 20));
    expect(AknSpace.section, 24);
    expect(AknSpace.minTap, 48);
    expect(AknSpace.driverTap, 64);
    expect(AknSpace.plate, const EdgeInsets.fromLTRB(18, 16, 18, 14));
    expect(
      AknSpace.row,
      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    );
    expect(AknSpace.cardPadding, const EdgeInsets.all(16));
    for (final (v, e) in [
      (AknSpace.s2, 2.0),
      (AknSpace.s4, 4.0),
      (AknSpace.s8, 8.0),
      (AknSpace.s12, 12.0),
      (AknSpace.s16, 16.0),
      (AknSpace.s24, 24.0),
      (AknSpace.s48, 48.0),
    ]) {
      expect(v, e);
    }
  });

  test('radii by size (§4.3)', () {
    expect(AknRadius.xs, 6);
    expect(AknRadius.sm, 10);
    expect(AknRadius.md, 12);
    expect(AknRadius.lg, 20);
    expect(AknRadius.xl, 20);
    expect(AknRadius.driver, 14);
    expect(AknRadius.card, const BorderRadius.all(Radius.circular(12)));
    expect(AknRadius.button, const BorderRadius.all(Radius.circular(12)));
    expect(AknRadius.input, const BorderRadius.all(Radius.circular(12)));
    expect(AknRadius.chip, const BorderRadius.all(Radius.circular(10)));
    expect(AknRadius.tag, const BorderRadius.all(Radius.circular(6)));
    expect(AknRadius.buttonSmall, const BorderRadius.all(Radius.circular(10)));
    expect(AknRadius.buttonDriver, const BorderRadius.all(Radius.circular(14)));
    // The plate card (decision G): 22; white home sections 18.
    expect(AknRadius.plateRadius, 22);
    expect(AknRadius.hero, const BorderRadius.all(Radius.circular(22)));
    expect(AknRadius.plate, AknRadius.hero);
    expect(AknRadius.section, const BorderRadius.all(Radius.circular(18)));
    expect(AknRadius.dialog, const BorderRadius.all(Radius.circular(20)));
    expect(AknRadius.sheet.topLeft, const Radius.circular(20));
    expect(AknRadius.sheet.bottomLeft, Radius.zero);
    // The orange header strip is gone.
    expect(AknRadius.header, BorderRadius.zero);
    expect(AknRadius.pillAll.topLeft.x, greaterThanOrEqualTo(999));
  });

  test('depth by role (§4.4): flat at rest, lifted only when floating', () {
    for (final c in [AknColors.light, AknColors.dark]) {
      expect(AknShadows.card(c), isEmpty);
      expect(AknShadows.pressed(c), isEmpty);
      expect(AknShadows.bar(c), isEmpty);
      expect(AknShadows.dragged(c), AknShadows.raised(c));
      // The plate card rests on a soft shadow (decision G); the cards
      // behind it a lighter one; the band casts an orange one.
      expect(AknShadows.hero(c), AknShadows.plate(c));
      expect(AknShadows.plate(c), hasLength(1));
      expect(AknShadows.plate(c).single.offset, const Offset(0, 8));
      expect(AknShadows.plate(c).single.blurRadius, 20);
      expect(AknShadows.plateBehind(c).single.blurRadius, 10);
      expect(AknShadows.band(c).single.offset, const Offset(0, 6));
      expect(AknShadows.band(c).single.blurRadius, 14);
    }
    expect(
      AknShadows.plate(AknColors.light).single.color,
      const Color(0x17101828),
    );
    expect(
      AknShadows.band(AknColors.light).single.color,
      const Color(0x38E8590C),
    );
    expect(AknShadows.glow(_plaka), isEmpty);
    final light = AknShadows.raised(AknColors.light);
    expect(light, hasLength(2));
    expect(light[0].color, const Color(0x141E2227));
    expect(light[0].offset, const Offset(0, 1));
    expect(light[0].blurRadius, 2);
    expect(light[1].color, const Color(0x471E2227));
    expect(light[1].offset, const Offset(0, 16));
    expect(light[1].blurRadius, 32);
    expect(light[1].spreadRadius, -12);
    final dark = AknShadows.raised(AknColors.dark);
    expect(dark, hasLength(1));
    expect(dark.single.color, const Color(0x99000000));
    expect(dark.single.offset, const Offset(0, 16));
    expect(dark.single.spreadRadius, -12);
  });
}

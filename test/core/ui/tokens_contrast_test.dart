// Token facts (redesign spec §1): exact values, deprecated navy aliases re-pointed to the hero,
// no purple anywhere, tone lookup, lerp / copyWith keep every token. WCAG pairs: contrast_test.dart.
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test_helpers.dart';

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
  ('skeleton', c.skeleton),
  ('skeletonHighlight', c.skeletonHighlight),
  ('link', c.link),
];

bool _purple(Color color) {
  final hsv = HSVColor.fromColor(color);
  return color.a > 0.2 &&
      hsv.saturation > 0.2 &&
      hsv.hue >= 250 &&
      hsv.hue <= 330;
}

/// Navy-ish: a saturated blue-slate dark surface (the old panel colour).
bool _navySurface(Color color) {
  final hsv = HSVColor.fromColor(color);
  return hsv.value < 0.35 && hsv.saturation > 0.3 && hsv.hue >= 200;
}

void main() {
  for (final (name, c) in [
    ('light', AknColors.light),
    ('dark', AknColors.dark),
  ]) {
    group('$name palette', () {
      test('no purple anywhere (owner decision 5)', () {
        for (final (label, color) in [
          ..._allColors(c),
          for (final (l, col) in _allColors(OnHero.palette(c)))
            ('hero $l', col),
        ]) {
          expect(_purple(color), isFalse, reason: '$label ($color) is purple');
        }
      });

      test('no navy surfaces: page, cards, bars and the hero', () {
        for (final (label, color) in [
          ('bg', c.bg),
          ('surface', c.surface),
          ('surfaceAlt', c.surfaceAlt),
          ('surfaceRaised', c.surfaceRaised),
          ('heroStart', c.heroStart),
          ('heroEnd', c.heroEnd),
          ('navy (alias)', c.navy),
        ]) {
          expect(_navySurface(color), isFalse, reason: '$label ($color)');
        }
      });

      test('deprecated navy aliases point at the hero', () {
        expect(c.navy, c.heroEnd);
        expect(c.onNavy, c.onHero);
        expect(c.onNavyDim, c.onHeroDim);
        expect(c.onHero, const Color(0xFFFFFFFF));
        // White 88 % / 16 %.
        expect(c.onHeroDim, const Color(0xE0FFFFFF));
        expect(c.navyRaised, const Color(0x29FFFFFF));
        expect(c.logo, c.brandBright);
      });

      test('tone() returns the matching ToneColors', () {
        expect(c.tone(AknTone.ok), c.ok);
        expect(c.tone(AknTone.warn), c.warn);
        expect(c.tone(AknTone.danger), c.danger);
        expect(c.tone(AknTone.info), c.info);
        expect(c.tone(AknTone.neutral), c.neutral);
        expect(c.tone(AknTone.brand), c.brandTone);
        // Brand tone = brandInk on brandSoft.
        expect(c.brandTone.fg, c.brandInk);
        expect(c.brandTone.bg, c.brandSoft);
      });
    });
  }

  test('light tokens are the spec values (§1.1)', () {
    const l = AknColors.light;
    expect(l.brandBright, const Color(0xFFFF5001));
    expect(l.logo, const Color(0xFFFF5001));
    expect(l.brand, const Color(0xFFE8480A));
    expect(l.brandInk, const Color(0xFFC2410C));
    expect(l.brandFill, const Color(0xFFD14408));
    expect(l.brandFillPressed, const Color(0xFFB83C07));
    expect(l.brandSoft, const Color(0xFFFFF3EC));
    expect(l.brandLine, const Color(0xFFFFD9C4));
    expect(l.heroStart, const Color(0xFFF5610F));
    expect(l.heroEnd, const Color(0xFFD14408));
    expect(l.bg, const Color(0xFFF6F7F9));
    expect(l.surface, const Color(0xFFFFFFFF));
    expect(l.surfaceRaised, const Color(0xFFFFFFFF));
    // #F1F3F6 fine-tuned one step so `dim` keeps 4.5:1 on it.
    expect(l.surfaceAlt, const Color(0xFFF2F4F7));
    expect(l.ink, const Color(0xFF1F2A37));
    expect(l.text, const Color(0xFF344054));
    expect(l.dim, const Color(0xFF667085));
    expect(l.faint, const Color(0xFF98A2B3));
    expect(l.line, const Color(0xFFE7EAEE));
    expect(l.lineSoft, const Color(0xFFF0F2F5));
    expect(l.lineStrong, const Color(0xFFD0D5DD));
  });

  test('dark tokens are the spec values (§1.2): neutral charcoal', () {
    const d = AknColors.dark;
    expect(d.bg, const Color(0xFF0F1114));
    expect(d.surface, const Color(0xFF16191D));
    expect(d.surfaceAlt, const Color(0xFF1D2126));
    expect(d.surfaceRaised, const Color(0xFF1B1F24));
    expect(d.line, const Color(0xFF2A2F36));
    expect(d.ink, const Color(0xFFF4F5F7));
    expect(d.text, const Color(0xFFD0D5DD));
    expect(d.dim, const Color(0xFF98A2B3));
    expect(d.brandInk, const Color(0xFFFF8A4C));
    expect(d.brandFill, const Color(0xFFD14408));
    expect(d.brandSoft, const Color(0xFF2A1608));
    expect(d.brandLine, const Color(0xFF4A2410));
    expect(d.heroStart, const Color(0xFFC2410C));
    expect(d.heroEnd, const Color(0xFF8F3307));
  });

  test('lerp and copyWith keep every token (incl. the hero tokens)', () {
    final mid = AknColors.light.lerp(AknColors.dark, 0.5);
    expect(mid, isA<AknColors>());
    expect(AknColors.light.lerp(AknColors.dark, 0).bg, AknColors.light.bg);
    expect(AknColors.light.lerp(AknColors.dark, 1).brand, AknColors.dark.brand);
    expect(
      AknColors.light.lerp(AknColors.dark, 1).heroEnd,
      AknColors.dark.heroEnd,
    );
    expect(
      AknColors.light.lerp(AknColors.dark, 0).brandBright,
      AknColors.light.brandBright,
    );
    final changed = AknColors.light.copyWith(
      brand: const Color(0xFF000000),
      heroStart: const Color(0xFF111111),
    );
    expect(changed.brand, const Color(0xFF000000));
    expect(changed.heroStart, const Color(0xFF111111));
    expect(changed.heroEnd, AknColors.light.heroEnd);
    expect(changed.onHero, AknColors.light.onHero);
    expect(changed.navy, AknColors.light.navy);
  });

  test('on-hero palette: white text, dark glass, hero tokens kept', () {
    for (final base in [AknColors.light, AknColors.dark]) {
      final p = OnHero.palette(base);
      for (final col in [p.ink, p.text, p.dim, p.brandInk, p.link]) {
        expect(col, const Color(0xFFFFFFFF));
      }
      expect(p.heroStart, base.heroStart);
      expect(p.heroEnd, base.heroEnd);
      expect(p.bg, base.heroEnd);
      // Dark glass (never white glass under text).
      expect(HSVColor.fromColor(p.surface).value, 0);
      expect(p.brandFill, const Color(0xFFFFFFFF));
      expect(contrast(p.onBrandFill, p.brandFill), greaterThanOrEqualTo(4.5));
      // Idempotent: a hero inside a hero keeps the palette.
      expect(OnHero.palette(p).ink, p.ink);
      expect(OnHero.palette(p).surface, p.surface);
      // OnNavy is the old name.
      expect(OnNavy.palette(base).surface, p.surface);
    }
  });

  test('radii and shadows (generous, soft)', () {
    expect(AknRadius.card, const BorderRadius.all(Radius.circular(20)));
    expect(AknRadius.button, const BorderRadius.all(Radius.circular(14)));
    expect(AknRadius.input, const BorderRadius.all(Radius.circular(14)));
    expect(AknRadius.hero, const BorderRadius.all(Radius.circular(24)));
    expect(AknRadius.header.bottomLeft, const Radius.circular(28));
    final card = AknShadows.card(AknColors.light).first;
    expect(card.offset, const Offset(0, 6));
    expect(card.blurRadius, 20);
    expect(card.color.a, closeTo(0.06, 0.01));
    expect(AknShadows.card(AknColors.dark), isEmpty);
  });
}

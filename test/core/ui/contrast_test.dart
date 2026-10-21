// WCAG 2.x contrast of the "Turuncu & Beyaz" token pairs (redesign spec §1.1 / §1.2), light and dark:
// body text ≥ 4.5:1, orange text ≥ 4.5:1, white on the orange fills ≥ 4.5:1, white large text on the
// light end of the hero ≥ 3:1, non-text accents ≥ 3:1. Plus the on-hero palette and the hero
// gradient's text zone (where small white text may sit).
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test_helpers.dart';

const _white = Color(0xFFFFFFFF);

void _expectAll(List<(String, Color, Color)> pairs, double min) {
  for (final (label, fg, bg) in pairs) {
    final ratio = contrast(over(fg, bg), bg);
    expect(
      ratio,
      greaterThanOrEqualTo(min),
      reason: '$label is ${ratio.toStringAsFixed(2)}:1 (needs $min)',
    );
  }
}

/// The colour of [g] at position [t] (0..1) along its axis.
Color _at(LinearGradient g, double t) {
  final stops =
      g.stops ??
      [for (var i = 0; i < g.colors.length; i++) i / (g.colors.length - 1)];
  if (t <= stops.first) return g.colors.first;
  for (var i = 1; i < stops.length; i++) {
    if (t <= stops[i]) {
      final local = (t - stops[i - 1]) / (stops[i] - stops[i - 1]);
      return Color.lerp(g.colors[i - 1], g.colors[i], local)!;
    }
  }
  return g.colors.last;
}

void main() {
  for (final (name, c) in [
    ('light', AknColors.light),
    ('dark', AknColors.dark),
  ]) {
    group(name, () {
      test('ink / text / dim on bg and surfaces ≥ 4.5', () {
        _expectAll([
          for (final (fn, fg) in [
            ('ink', c.ink),
            ('text', c.text),
            ('dim', c.dim),
          ])
            for (final (bn, bg) in [
              ('bg', c.bg),
              ('surface', c.surface),
              ('surfaceRaised', c.surfaceRaised),
              // Input fill and segmented track (hints, labels).
              ('surfaceAlt', c.surfaceAlt),
            ])
              ('$fn/$bn', fg, bg),
        ], 4.5);
      });

      test('orange text: brandInk on bg / surface / brandSoft ≥ 4.5', () {
        _expectAll([
          ('brandInk/bg', c.brandInk, c.bg),
          ('brandInk/surface', c.brandInk, c.surface),
          ('brandInk/surfaceRaised', c.brandInk, c.surfaceRaised),
          ('brandInk/brandSoft', c.brandInk, c.brandSoft),
          ('brandTone fg/bg', c.brandTone.fg, c.brandTone.bg),
        ], 4.5);
      });

      test('white on the orange fills and on heroEnd ≥ 4.5', () {
        _expectAll([
          ('onBrandFill/brandFill', c.onBrandFill, c.brandFill),
          ('onBrandFill/brandFillPressed', c.onBrandFill, c.brandFillPressed),
          ('white/brandFill', _white, c.brandFill),
          ('white/heroEnd', _white, c.heroEnd),
          ('onHero/heroEnd', c.onHero, c.heroEnd),
          ('onNavy/navy (alias)', c.onNavy, c.navy),
          ('onDangerFill/dangerFill', c.onDangerFill, c.dangerFill),
        ], 4.5);
      });

      test('white large text on heroStart ≥ 3.0', () {
        _expectAll([
          ('white/heroStart', _white, c.heroStart),
          ('onHero/heroStart', c.onHero, c.heroStart),
          // Large text / icons only (white 88 %).
          ('onHeroDim/heroEnd', c.onHeroDim, c.heroEnd),
        ], 3);
      });

      test('non-text accents ≥ 3.0 (logo orange, accents, controls)', () {
        _expectAll([
          ('brandBright/surface', c.brandBright, c.surface),
          ('brandBright/bg', c.brandBright, c.bg),
          ('logo/surface', c.logo, c.surface),
          ('brand/surface', c.brand, c.surface),
          ('brand/bg', c.brand, c.bg),
          ('brand/brandSoft (active tab pill)', c.brand, c.brandSoft),
          ('brandFill/bg', c.brandFill, c.bg),
        ], 3);
      });

      test('status tones and links stay AA', () {
        _expectAll([
          for (final tone in AknTone.values) ...[
            ('${tone.name} fg/bg', c.tone(tone).fg, c.tone(tone).bg),
            ('${tone.name} fg/surface', c.tone(tone).fg, c.surface),
            (
              '${tone.name} onSolid/solid',
              c.tone(tone).onSolid,
              c.tone(tone).solid,
            ),
          ],
          ('link/surface', c.link, c.surface),
          ('link/bg', c.link, c.bg),
        ], 4.5);
      });

      test('on-hero palette: small white text on hero surfaces ≥ 4.5', () {
        final p = OnHero.palette(c);
        final deep = AknHeroGradient.deep(c);
        _expectAll([
          for (final (bn, bg) in [
            ('heroEnd', c.heroEnd),
            ('deep', deep),
            ('glass/heroEnd', over(p.surface, c.heroEnd)),
            ('glassStrong/heroEnd', over(p.surfaceAlt, c.heroEnd)),
            ('brandSoft/heroEnd', over(p.brandSoft, c.heroEnd)),
          ]) ...[
            ('ink/$bn', p.ink, bg),
            ('text/$bn', p.text, bg),
            ('dim/$bn', p.dim, bg),
            ('brandInk/$bn', p.brandInk, bg),
            ('link/$bn', p.link, bg),
          ],
          // Hero pills hold small text anywhere on the gradient.
          (
            'chip text/glassStrong over heroStart',
            _white,
            over(OnHero.glassStrong, c.heroStart),
          ),
          // White buttons on the hero: orange label.
          ('onBrandFill/brandFill', p.onBrandFill, p.brandFill),
          ('onBrandFill/brandFillPressed', p.onBrandFill, p.brandFillPressed),
        ], 4.5);
      });

      test('hero gradient: white ≥ 4.5 wherever text starts', () {
        for (final style in AknHeroStyle.values) {
          final g = AknHeroGradient.of(c, style: style);
          // Light mode keeps the vivid heroStart in the first third (the
          // text-free corner / right edge); dark is safe end to end.
          final from = c.isDark ? 0.0 : g.stops![1];
          for (var t = from; t <= 1.0001; t += 0.05) {
            final col = _at(g, t.clamp(0, 1));
            expect(
              contrast(_white, col),
              greaterThanOrEqualTo(4.5),
              reason: '${style.name} at $t: $col',
            );
          }
          // The light end still clears 3:1 for large text.
          expect(contrast(_white, g.colors.first), greaterThanOrEqualTo(3));
        }
      });
    });
  }

  test(
    'spec values (§1.1): text 14.5:1, dim 4.97:1, brandInk 5.18:1 on white',
    () {
      const white = Color(0xFFFFFFFF);
      final l = AknColors.light;
      expect(contrast(l.ink, white), closeTo(14.5, 0.1));
      expect(contrast(l.dim, white), closeTo(4.97, 0.02));
      expect(contrast(l.brandInk, white), closeTo(5.18, 0.02));
      expect(contrast(white, l.brandFill), closeTo(4.62, 0.02));
      // #FF5001 is never text (3.3:1 on white).
      expect(contrast(l.brandBright, white), lessThan(4.5));
      // faint is placeholder / disabled only.
      expect(contrast(l.faint, white), lessThan(4.5));
    },
  );
}

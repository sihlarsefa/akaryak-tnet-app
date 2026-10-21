// WCAG 2.x contrast of the "Turuncu Plaka" token pairs (design v2 §2.3, §12), light and dark:
// text ≥ 4.5:1 (body, Pas, status, links, nav labels, black on the plate and on the primary),
// control borders, chart marks and plate context graphics ≥ 3:1 (non-text), and the published
// ratios of the spec table. `faint` is never asserted as text.
import 'package:akaryakitnet/core/ui/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'foundation_helpers.dart';

const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF000000);

void _expectAll(List<(String, Color, Color)> pairs, double min) {
  for (final (label, fg, bg) in pairs) {
    final ratio = wcag(blend(fg, bg), bg);
    expect(
      ratio,
      greaterThanOrEqualTo(min),
      reason: '$label is ${ratio.toStringAsFixed(2)}:1 (needs $min)',
    );
  }
}

void main() {
  for (final (name, c) in [
    ('light', AknColors.light),
    ('dark', AknColors.dark),
  ]) {
    group(name, () {
      test('ink / text / dim on the page, surfaces and Beton ≥ 4.5', () {
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
              // Wells, chips, segmented track, pressed rows.
              ('surfaceAlt', c.surfaceAlt),
            ])
              ('$fn/$bn', fg, bg),
        ], 4.5);
      });

      test('Pas ("your move" text) on the page and on Beton ≥ 4.5', () {
        _expectAll([
          ('brandInk/bg', c.brandInk, c.bg),
          ('brandInk/surface', c.brandInk, c.surface),
          ('brandInk/surfaceRaised', c.brandInk, c.surfaceRaised),
          ('brandInk/surfaceAlt', c.brandInk, c.surfaceAlt),
          ('brandTone fg/bg', c.brandTone.fg, c.brandTone.bg),
        ], 4.5);
      });

      test('on orange, ink is black: primary and plate ≥ 4.5', () {
        _expectAll([
          ('onBrandFill/brandFill', c.onBrandFill, c.brandFill),
          ('onBrandFill/brandFillPressed', c.onBrandFill, c.brandFillPressed),
          ('onPlate/plate', c.onPlate, c.plate),
          ('onHero/heroEnd (alias)', c.onHero, c.heroEnd),
          ('onNavy/navy (alias)', c.onNavy, c.navy),
          ('brandTone onSolid/solid', c.brandTone.onSolid, c.brandTone.solid),
          ('onDangerFill/dangerFill', c.onDangerFill, c.dangerFill),
          ('onInverse/inverse', c.onInverse, c.inverse),
        ], 4.5);
        // The primary's black label is 6.40:1 by day (§2.5).
        expect(
          wcag(c.onBrandFill, AknColors.light.brandFill),
          closeTo(6.40, 0.02),
        );
      });

      test('white text never sits on orange (3.28 / 3.97 < 4.5)', () {
        expect(wcag(_white, c.plate), lessThan(4.5));
        expect(wcag(_white, c.brandFill), lessThan(4.5));
        expect(c.onPlate, _black);
        expect(c.onBrandFill, _black);
      });

      test(
        'non-text ≥ 3.0: marks, control borders, chart and plate graphics',
        () {
          _expectAll([
            ('logo/bg', c.logo, c.bg),
            ('logo/surface', c.logo, c.surface),
            ('brand (focus ring)/bg', c.brand, c.bg),
            ('brand (focus ring)/surface', c.brand, c.surface),
            ('lineStrong (control border)/bg', c.lineStrong, c.bg),
            ('lineStrong (control border)/surface', c.lineStrong, c.surface),
            ('chartContext/surface', c.chartContext, c.surface),
            ('chartContext/bg', c.chartContext, c.bg),
            ('chartHighlight/surface', c.chartHighlight, c.surface),
            ('plateContext/plate (past bars, tracks)', c.plateContext, c.plate),
            ('ok.solid (lamp)/surface', c.ok.solid, c.surface),
            ('warn.solid (lamp)/surface', c.warn.solid, c.surface),
            ('danger.solid (lamp)/surface', c.danger.solid, c.surface),
            ('brandTone.solid (lamp)/surface', c.brandTone.solid, c.surface),
            ('faint (pager dash)/bg', c.faint, c.bg),
          ], 3);
        },
      );

      test('status tones, links and nav labels stay AA', () {
        _expectAll([
          for (final tone in AknTone.values) ...[
            ('${tone.name} fg/bg', c.tone(tone).fg, c.tone(tone).bg),
            ('${tone.name} fg/surface', c.tone(tone).fg, c.surface),
            ('${tone.name} fg/page', c.tone(tone).fg, c.bg),
            (
              '${tone.name} onSolid/solid',
              c.tone(tone).onSolid,
              c.tone(tone).solid,
            ),
          ],
          ('link/surface', c.link, c.surface),
          ('link/bg', c.link, c.bg),
          (
            'navInactive/bar',
            c.navInactive,
            c.isDark ? c.surface : c.surfaceRaised,
          ),
          ('navInactive/bg', c.navInactive, c.bg),
          ('ink badge digits', c.bg, c.ink),
        ], 4.5);
      });

      test('the plate palette prints AA on the plate', () {
        final p = c.plateInk();
        _expectAll([
          for (final (fn, fg) in [
            ('ink', p.ink),
            ('text', p.text),
            ('dim', p.dim),
            ('brandInk', p.brandInk),
            ('link', p.link),
            for (final t in AknTone.values) ('${t.name}.fg', p.tone(t).fg),
          ])
            ('$fn/plate', fg, p.surface),
          // Delta chip: plate-coloured text on a black chip.
          ('delta chip text', p.brandTone.onSolid, p.brandTone.solid),
        ], 4.5);
        _expectAll([
          ('chartHighlight (black mark)/plate', p.chartHighlight, p.surface),
          ('chartContext (white bars)/plate', p.chartContext, p.surface),
        ], 3);
      });
    });
  }

  test('published ratios (§2.3)', () {
    const l = AknColors.light;
    const d = AknColors.dark;
    void ratio(Color fg, Color bg, double expected) =>
        expect(wcag(fg, bg), closeTo(expected, 0.015), reason: '$fg on $bg');
    ratio(l.ink, _white, 15.99);
    ratio(l.dim, _white, 5.98);
    ratio(l.dim, l.surfaceAlt, 5.44);
    ratio(l.brandInk, _white, 5.18);
    ratio(l.brandInk, l.surfaceAlt, 4.71);
    ratio(l.navInactive, _white, 4.86);
    ratio(l.lineStrong, _white, 3.14);
    ratio(l.ok.fg, _white, 5.41);
    ratio(l.warn.fg, _white, 5.93);
    ratio(l.danger.fg, _white, 5.94);
    ratio(_white, l.dangerFill, 5.94);
    ratio(_white, const Color(0xFF1D4AB4), 7.80); // TR plate strip
    ratio(_black, l.plate, 6.40);
    ratio(_black, d.plate, 5.29);
    ratio(_black, d.brandFillPressed, 4.54);
    ratio(l.plateContext, l.plate, 3.28);
    ratio(d.plateContext, d.plate, 3.97);
    ratio(l.logo, _white, 3.28);
    ratio(d.ink, d.bg, 15.74);
    ratio(d.dim, d.surface, 6.68);
    ratio(d.brandInk, d.bg, 6.80);
    ratio(d.chartContext, d.surface, 3.21);
    ratio(d.lineStrong, d.surface, 3.39);
    ratio(d.brand, d.bg, 5.37);
    // Orange marks never sit on Beton (2.98:1).
    expect(wcag(l.logo, l.surfaceAlt), lessThan(3));
    // Orange is never text (3.28:1 on white).
    expect(wcag(l.brandBright, _white), lessThan(4.5));
    // faint is disabled text and dashes only.
    expect(wcag(l.faint, _white), lessThan(4.5));
  });
}

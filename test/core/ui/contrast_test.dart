// WCAG 2.x contrast of the token pairs (design v2 §2.3, §12 + owner colour decision G "F2GO kart
// dili", 2026-10-21), light and dark: text ≥ 4.5:1 (body, Pas, status, links, nav labels, ink on
// the white plate card and its orange tint, the delta chip), control borders, chart marks and the
// this-month bar ≥ 3:1 (non-text), the owner-accepted white labels on the orange gradients (the
// 17 px w700 primary label ≥ 3.5:1 on its end colour, like F2GO), and the published ratios.
// `faint` is never asserted as text.
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

      test('ink on the plate card and fills ≥ 4.5', () {
        _expectAll([
          ('onPlate/plate', c.onPlate, c.plate),
          ('onPlate/plateTint (card top)', c.onPlate, c.plateTint),
          ('dim/plateTint (card top)', c.dim, c.plateTint),
          ('brandInk/deltaFill (delta chip)', c.brandInk, c.deltaFill),
          ('brandTone onSolid/solid', c.brandTone.onSolid, c.brandTone.solid),
          ('onDangerFill/dangerFill', c.onDangerFill, c.dangerFill),
          ('onInverse/inverse', c.onInverse, c.inverse),
        ], 4.5);
        // Black still prints on the logo orange (the ADR plate, the lamp).
        expect(wcag(_black, AknColors.light.logo), closeTo(6.40, 0.02));
      });

      test('white on the orange gradients (owner decision G)', () {
        // The band and the primary carry white content.
        expect(c.onHero, _white);
        expect(c.onNavy, _white);
        expect(c.onBrandFill, _white);
        // The 17 px w700 primary label: ≥ 3.5 on the gradient's end colour
        // (3.58) and ≥ 3 across its middle.
        expect(wcag(_white, c.brandFill), greaterThanOrEqualTo(3.5));
        final mid = Color.lerp(c.brandFillStart, c.brandFill, 0.5)!;
        expect(wcag(_white, mid), greaterThanOrEqualTo(3.0));
        // The band's deep end ≥ 3.5 (light 3.77, dark 7.04).
        expect(wcag(_white, c.heroEnd), greaterThanOrEqualTo(3.5));
        expect(wcag(_white, c.heroMid), greaterThanOrEqualTo(3.0));
        // Never black on the band or the primary any more.
        expect(c.onPlate, isNot(_black));
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
            ('plateAccent (this-month bar)/plate', c.plateAccent, c.plate),
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
          ]) ...[
            ('$fn/plate', fg, p.surface),
            ('$fn/plateTint', fg, p.plateTint),
          ],
          // Delta chip: Pas on the soft orange chip.
          ('delta chip text', p.brandInk, p.deltaFill),
        ], 4.5);
        _expectAll([
          (
            'chartHighlight (this-month bar)/plate',
            p.chartHighlight,
            p.surface,
          ),
        ], 3);
        // Past months are context: the orange at 30 % (45 % at night).
        expect(p.chartContext, c.plateContext);
        expect(p.chartContext.a, lessThan(0.5));
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
    ratio(_black, l.logo, 6.40);
    ratio(_black, d.brandPressed, 5.29);
    // Decision G pairs.
    ratio(_white, l.brandFill, 3.58);
    ratio(_white, l.heroEnd, 3.77);
    ratio(_white, d.heroStart, 5.18);
    ratio(_white, d.heroEnd, 7.04);
    ratio(l.brandInk, l.deltaFill, 4.69);
    ratio(d.brandInk, d.deltaFill, 5.75);
    ratio(l.onPlate, l.plateTint, 14.06);
    ratio(l.dim, l.plateTint, 5.26);
    ratio(d.onPlate, d.plateTint, 12.74);
    ratio(l.plateAccent, l.plate, 3.58);
    ratio(d.plateAccent, d.plate, 6.10);
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

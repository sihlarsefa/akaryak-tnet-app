// WCAG 2.x contrast of the token pairs (design v3 "Akış" §0.4, §2, §4 + owner colour decision G),
// light and dark: text ≥ 4.5:1 (body, Pas, status, links, nav labels, count-badge figures, ink on the
// white hero card and its warm wash, the delta chip), non-text ≥ 3:1 (control borders, marks,
// lamps, chart marks, the this-month bar, pager dots), the owner-accepted white labels on the
// orange gradients (the 16 px w700 primary label ≥ 3.5:1 on its end colour) and the published
// ratios. `faint` is disabled only (WCAG exempts inactive components), so it is never asserted.
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
      test('ink / text / dim on the page, surfaces and wells ≥ 4.5', () {
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
              // Wells, chips at rest, segmented track, pressed rows.
              ('surfaceAlt', c.surfaceAlt),
            ])
              ('$fn/$bn', fg, bg),
        ], 4.5);
      });

      test('Pas ("your move" text) on the page and on the wells ≥ 4.5', () {
        _expectAll([
          ('brandInk/bg', c.brandInk, c.bg),
          ('brandInk/surface', c.brandInk, c.surface),
          ('brandInk/surfaceRaised', c.brandInk, c.surfaceRaised),
          ('brandInk/surfaceAlt', c.brandInk, c.surfaceAlt),
          ('brandTone fg/bg', c.brandTone.fg, c.brandTone.bg),
        ], 4.5);
      });

      test('ink on the hero card and fills ≥ 4.5', () {
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
        // The 16 px w700 primary label: ≥ 3.5 on the gradient's end colour
        // (3.77) and ≥ 3 across its middle (3.12).
        expect(wcag(_white, c.brandFill), greaterThanOrEqualTo(3.5));
        final mid = Color.lerp(c.brandFillStart, c.brandFill, 0.5)!;
        expect(wcag(_white, mid), greaterThanOrEqualTo(3.0));
        // The band's deep end ≥ 3.5 (light 4.39, dark 9.71), its middle ≥ 3
        // (light 3.39, dark 7.03).
        expect(wcag(_white, c.heroEnd), greaterThanOrEqualTo(3.5));
        expect(wcag(_white, c.heroMid), greaterThanOrEqualTo(3.0));
        // Never black on the band or the primary.
        expect(c.onPlate, isNot(_black));
      });

      test(
        'non-text ≥ 3.0: marks, control borders, lamps, chart and plate graphics',
        () {
          _expectAll([
            ('logo/bg', c.logo, c.bg),
            ('logo/surface', c.logo, c.surface),
            ('brand (focus ring, checkbox, radio)/bg', c.brand, c.bg),
            ('brand (focus ring, checkbox, radio)/surface', c.brand, c.surface),
            // Inputs, checkbox and radio at rest, the switch track.
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
          ], 3);
        },
      );

      test('pager dots ≥ 3.0 on the page (v3 §4 "Pager dots")', () {
        // LanePager: the active lane is a logo-orange capsule, the others
        // are dots in `lineStrong` — the dots are the strip's tap targets and
        // the only mark of the other lanes, so they need 3:1.
        _expectAll([
          ('active capsule (logo)/bg', c.logo, c.bg),
          ('inactive dot (lineStrong)/bg', c.lineStrong, c.bg),
        ], 3);
      });

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
        ], 4.5);
      });

      test('count-badge figures stay AA (v3 §4 "Badges")', () {
        // The figures are text (10 px w800): 4.5:1 on every badge fill.
        _expectAll([
          // AknCountBadge, the Material badge theme and the bottom bar: white
          // on the deep-orange pill (never on the logo orange: 3.28:1).
          (
            'badge figures: white on brandFillPressed',
            c.onBrandFill,
            c.brandFillPressed,
          ),
          // On the header band the badge flips to a white pill with
          // deep-orange figures.
          (
            'band badge figures: brandFillPressed on white',
            c.brandFillPressed,
            c.onHero,
          ),
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
        // Past months are context: the orange at 24 % (40 % at night).
        expect(p.chartContext, c.plateContext);
        expect(p.chartContext.a, lessThan(0.5));
      });
    });
  }

  test('published ratios (v3 §2)', () {
    const l = AknColors.light;
    const d = AknColors.dark;
    void ratio(Color fg, Color bg, double expected) =>
        expect(wcag(fg, bg), closeTo(expected, 0.015), reason: '$fg on $bg');
    ratio(l.ink, _white, 17.96);
    ratio(l.ink, l.bg, 16.60);
    ratio(l.dim, _white, 5.96);
    ratio(l.dim, l.bg, 5.50);
    ratio(l.dim, l.surfaceAlt, 5.22);
    ratio(l.brandInk, _white, 5.18);
    ratio(l.brandInk, l.surfaceAlt, 4.54);
    ratio(l.navInactive, _white, 4.98);
    ratio(l.navInactive, l.bg, 4.60);
    ratio(l.lineStrong, _white, 3.44);
    ratio(l.lineStrong, l.bg, 3.18);
    ratio(l.ok.fg, _white, 5.41);
    ratio(l.warn.fg, _white, 5.93);
    ratio(l.danger.fg, _white, 5.94);
    ratio(_white, l.dangerFill, 5.94);
    ratio(_white, const Color(0xFF1D4AB4), 7.80); // TR plate strip
    ratio(_black, l.logo, 6.40);
    ratio(_black, d.brandPressed, 5.29);
    ratio(_white, l.brandFillPressed, 4.70);
    // Decision G pairs.
    ratio(_white, l.brandFill, 3.77);
    ratio(_white, l.heroEnd, 4.39);
    ratio(_white, l.heroMid, 3.39);
    ratio(_white, d.heroStart, 5.18);
    ratio(_white, d.heroEnd, 9.71);
    ratio(l.brandInk, l.deltaFill, 4.69);
    ratio(d.brandInk, d.deltaFill, 5.75);
    ratio(l.onPlate, l.plateTint, 16.61);
    ratio(l.dim, l.plateTint, 5.51);
    ratio(d.onPlate, d.plateTint, 14.58);
    ratio(l.plateAccent, l.plate, 3.77);
    ratio(d.plateAccent, d.plate, 6.85);
    ratio(l.logo, _white, 3.28);
    ratio(l.logo, l.bg, 3.03);
    ratio(d.ink, d.bg, 17.27);
    ratio(d.dim, d.surface, 7.34);
    ratio(d.brandInk, d.bg, 7.40);
    ratio(d.chartContext, d.surface, 4.64);
    ratio(d.lineStrong, d.surface, 3.61);
    ratio(d.lineStrong, d.bg, 3.90);
    ratio(d.brand, d.bg, 5.84);
    // Orange marks never sit on the wells (2.88:1).
    expect(wcag(l.logo, l.surfaceAlt), lessThan(3));
    // Orange is never text (3.28:1 on white).
    expect(wcag(l.brandBright, _white), lessThan(4.5));
    // faint is disabled text only (2.66:1 on white, 2.46:1 on the page).
    expect(wcag(l.faint, _white), lessThan(4.5));
  });
}

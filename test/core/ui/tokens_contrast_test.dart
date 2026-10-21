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
  ('logo', c.logo),
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
];

void main() {
  for (final (name, c) in [
    ('light', AknColors.light),
    ('dark', AknColors.dark),
  ]) {
    group('$name palette', () {
      test('body text pairs reach WCAG AA (4.5:1)', () {
        final pairs = <(String, Color, Color)>[
          ('ink/bg', c.ink, c.bg),
          ('ink/surface', c.ink, c.surface),
          ('ink/surfaceRaised', c.ink, c.surfaceRaised),
          ('text/bg', c.text, c.bg),
          ('text/surface', c.text, c.surface),
          ('dim/bg', c.dim, c.bg),
          ('dim/surface', c.dim, c.surface),
          ('brandInk/bg', c.brandInk, c.bg),
          ('brandInk/surface', c.brandInk, c.surface),
          ('brandInk/brandSoft', c.brandInk, c.brandSoft),
          ('onBrandFill/brandFill', c.onBrandFill, c.brandFill),
          ('onBrandFill/brandFillPressed', c.onBrandFill, c.brandFillPressed),
          ('onDangerFill/dangerFill', c.onDangerFill, c.dangerFill),
          ('onNavy/navy', c.onNavy, c.navy),
          ('onNavyDim/navy', c.onNavyDim, c.navy),
          for (final t in AknTone.values) ...[
            ('${t.name} fg/bg', c.tone(t).fg, c.tone(t).bg),
            ('${t.name} fg/surface', c.tone(t).fg, c.surface),
            ('${t.name} onSolid/solid', c.tone(t).onSolid, c.tone(t).solid),
          ],
        ];
        for (final (label, fg, bg) in pairs) {
          expect(
            contrast(fg, bg),
            greaterThanOrEqualTo(4.5),
            reason: '$label is ${contrast(fg, bg).toStringAsFixed(2)}:1',
          );
        }
      });

      test('controls and accents reach 3:1 against their background', () {
        final pairs = <(String, Color, Color)>[
          ('brand/surface', c.brand, c.surface),
          ('brand/bg', c.brand, c.bg),
          ('brandFill/bg', c.brandFill, c.bg),
          ('brand/brandSoft (active tab)', c.brand, c.brandSoft),
          ('logo/navy (splash)', c.logo, c.navy),
        ];
        for (final (label, fg, bg) in pairs) {
          expect(
            contrast(fg, bg),
            greaterThanOrEqualTo(3),
            reason: '$label is ${contrast(fg, bg).toStringAsFixed(2)}:1',
          );
        }
      });

      test('no purple anywhere (owner decision 5)', () {
        for (final (label, color) in _allColors(c)) {
          final hsv = HSVColor.fromColor(color);
          final purple =
              hsv.saturation > 0.2 && hsv.hue >= 255 && hsv.hue <= 320;
          expect(purple, isFalse, reason: '$label ($color) is purple');
        }
      });

      test('tone() returns the matching ToneColors', () {
        expect(c.tone(AknTone.ok), c.ok);
        expect(c.tone(AknTone.warn), c.warn);
        expect(c.tone(AknTone.danger), c.danger);
        expect(c.tone(AknTone.info), c.info);
        expect(c.tone(AknTone.neutral), c.neutral);
        expect(c.tone(AknTone.brand), c.brandTone);
      });
    });
  }

  test('spec facts: #C94C0C on white is AA, #FF5001 is not (never text)', () {
    const white = Color(0xFFFFFFFF);
    expect(contrast(const Color(0xFFC94C0C), white), greaterThan(4.5));
    expect(contrast(const Color(0xFFFF5001), white), lessThan(4.5));
    expect(AknColors.light.brand, const Color(0xFFC94C0C));
    expect(AknColors.light.navy, const Color(0xFF1F2A37));
    expect(AknColors.light.logo, const Color(0xFFFF5001));
    expect(AknColors.dark.brand, const Color(0xFFE8692B));
  });

  test('lerp and copyWith keep every token', () {
    final mid = AknColors.light.lerp(AknColors.dark, 0.5);
    expect(mid, isA<AknColors>());
    expect(AknColors.light.lerp(AknColors.dark, 0).bg, AknColors.light.bg);
    expect(AknColors.light.lerp(AknColors.dark, 1).brand, AknColors.dark.brand);
    final changed = AknColors.light.copyWith(brand: const Color(0xFF000000));
    expect(changed.brand, const Color(0xFF000000));
    expect(changed.navy, AknColors.light.navy);
  });

  test('on-navy palette (hero panels) keeps text at AA on navy', () {
    for (final base in [AknColors.light, AknColors.dark]) {
      final n = OnNavy.palette(base);
      for (final (label, fg) in [
        ('ink', n.ink),
        ('text', n.text),
        ('dim', n.dim),
        ('brandInk', n.brandInk),
      ]) {
        expect(
          contrast(fg, base.navy),
          greaterThanOrEqualTo(4.5),
          reason: '$label on navy',
        );
      }
      // Raised navy surfaces (cards inside the hero) still read well.
      expect(contrast(n.ink, n.surface), greaterThanOrEqualTo(4.5));
      expect(contrast(n.dim, n.surface), greaterThanOrEqualTo(4.5));
    }
  });
}

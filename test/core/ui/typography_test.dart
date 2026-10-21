// Typography v2 (§3): Mona Sans in two voices, the 15 mapped fields and the 5 new ones, the
// Material text theme mapping, proportional figures (no `tnum`), the bundled upstream font files,
// their pubspec registration, the licence entry and real-glyph rendering.
import 'dart:io';

import 'package:akaryakitnet/core/ui/tokens.dart';
import 'package:akaryakitnet/core/ui/typography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';

const _sans = 'MonaSans';
const _counter = 'MonaSansCondensed';

void main() {
  group('AknTextStyles (§3.2)', () {
    final t = AknTextStyles.from(AknColors.light);
    const c = AknColors.light;

    void spec(
      String name,
      TextStyle s, {
      required String family,
      required double size,
      required double line,
      required FontWeight weight,
      double tracking = 0,
      Color? color,
    }) {
      expect(s.fontFamily, family, reason: name);
      expect(s.fontSize, size, reason: name);
      expect(s.height! * size, closeTo(line, 1e-9), reason: name);
      expect(s.fontWeight, weight, reason: name);
      expect(s.letterSpacing ?? 0, closeTo(tracking, 1e-9), reason: name);
      if (color != null) expect(s.color, color, reason: name);
      expect(s.leadingDistribution, TextLeadingDistribution.even, reason: name);
      expect(s.locale, const Locale('tr', 'TR'), reason: name);
      expect(s.fontFeatures ?? const [], isEmpty, reason: '$name: no tnum');
    }

    test('the 15 existing fields', () {
      spec(
        'display',
        t.display,
        family: _sans,
        size: 30,
        line: 36,
        weight: FontWeight.w600,
        tracking: -0.6,
        color: c.ink,
      );
      spec(
        'title',
        t.title,
        family: _sans,
        size: 20,
        line: 26,
        weight: FontWeight.w600,
        tracking: -0.2,
        color: c.ink,
      );
      spec(
        'headline',
        t.headline,
        family: _sans,
        size: 17,
        line: 22,
        weight: FontWeight.w600,
        tracking: -0.1,
        color: c.ink,
      );
      spec(
        'body',
        t.body,
        family: _sans,
        size: 15,
        line: 22,
        weight: FontWeight.w400,
        color: c.text,
      );
      spec(
        'bodyStrong',
        t.bodyStrong,
        family: _sans,
        size: 15,
        line: 22,
        weight: FontWeight.w600,
        color: c.ink,
      );
      spec(
        'bodySmall',
        t.bodySmall,
        family: _sans,
        size: 14,
        line: 20,
        weight: FontWeight.w400,
        color: c.dim,
      );
      spec(
        'label',
        t.label,
        family: _sans,
        size: 13,
        line: 18,
        weight: FontWeight.w500,
        color: c.ink,
      );
      spec(
        'caption',
        t.caption,
        family: _sans,
        size: 12,
        line: 16,
        weight: FontWeight.w400,
        tracking: 0.1,
        color: c.dim,
      );
      spec(
        'captionStrong',
        t.captionStrong,
        family: _sans,
        size: 12,
        line: 16,
        weight: FontWeight.w600,
        tracking: 0.1,
        color: c.dim,
      );
      // Deprecated overline = captionStrong without tracking (sentence case).
      spec(
        'overline',
        t.overline,
        family: _sans,
        size: 12,
        line: 16,
        weight: FontWeight.w600,
        color: c.dim,
      );
      spec(
        'amount',
        t.amount,
        family: _sans,
        size: 17,
        line: 22,
        weight: FontWeight.w600,
        tracking: -0.1,
        color: c.ink,
      );
      spec(
        'amountLarge',
        t.amountLarge,
        family: _counter,
        size: 28,
        line: 32,
        weight: FontWeight.w700,
        tracking: -0.3,
        color: c.ink,
      );
      spec(
        'number',
        t.number,
        family: _counter,
        size: 24,
        line: 28,
        weight: FontWeight.w700,
        tracking: -0.2,
        color: c.ink,
      );
      spec(
        'numberLarge',
        t.numberLarge,
        family: _counter,
        size: 34,
        line: 38,
        weight: FontWeight.w800,
        tracking: -0.4,
        color: c.ink,
      );
      spec(
        'button',
        t.button,
        family: _sans,
        size: 16,
        line: 20,
        weight: FontWeight.w600,
      );
      // The button label takes its colour from the button.
      expect(t.button.color, isNull);
    });

    test('the new fields', () {
      spec(
        'plateFigure',
        t.plateFigure,
        family: _counter,
        size: 58,
        line: 58,
        weight: FontWeight.w800,
        tracking: -0.8,
        color: c.ink,
      );
      spec(
        'plateUnit',
        t.plateUnit,
        family: _counter,
        size: 30,
        line: 30,
        weight: FontWeight.w700,
        tracking: -0.2,
        color: c.ink,
      );
      spec(
        'figureWord',
        t.figureWord,
        family: _sans,
        size: 20,
        line: 24,
        weight: FontWeight.w600,
        tracking: -0.2,
        color: c.ink,
      );
      spec(
        'readoutUnit',
        t.readoutUnit,
        family: _counter,
        size: 16,
        line: 28,
        weight: FontWeight.w700,
        color: c.ink,
      );
      spec(
        'navLabel',
        t.navLabel,
        family: _sans,
        size: 11,
        line: 14,
        weight: FontWeight.w500,
        color: c.navInactive,
      );
    });

    test('built from the plate palette, every style prints black', () {
      final p = AknTextStyles.from(AknColors.dark.plateInk());
      for (final s in [
        p.display,
        p.body,
        p.bodySmall,
        p.caption,
        p.plateFigure,
        p.plateUnit,
        p.figureWord,
        p.number,
        p.readoutUnit,
      ]) {
        expect(s.color, const Color(0xFF000000));
      }
    });

    test('platform no longer picks the face', () {
      for (final platform in TargetPlatform.values) {
        expect(
          AknTextStyles.from(c, platform: platform),
          AknTextStyles.from(c),
        );
      }
    });

    test('recolor keeps sizes and weights, swaps colours', () {
      final big = t.copyWith(display: t.display.copyWith(fontSize: 34));
      final r = big.recolor(AknColors.dark);
      expect(r.display.fontSize, 34);
      expect(r.display.color, AknColors.dark.ink);
      expect(r.bodySmall.color, AknColors.dark.dim);
      expect(r.navLabel.color, AknColors.dark.navInactive);
      expect(r.button, big.button);
      expect(t.recolor(c), t);
    });

    test('copyWith, lerp and equality cover every field', () {
      final d = AknTextStyles.from(AknColors.dark);
      expect(t.copyWith(), t);
      expect(t.copyWith().hashCode, t.hashCode);
      expect(t.lerp(d, 1).plateFigure.color, d.plateFigure.color);
      expect(t.lerp(d, 0).navLabel.color, t.navLabel.color);
      expect(t.lerp(null, 0.5), t);
      final changed = t.copyWith(
        plateUnit: t.plateUnit.copyWith(fontSize: 34),
        navLabel: t.navLabel.copyWith(fontSize: 12),
      );
      expect(changed.plateUnit.fontSize, 34);
      expect(changed.navLabel.fontSize, 12);
      expect(changed, isNot(t));
    });

    test('Material text theme mapping', () {
      final m = AknTextStyles.textTheme(c);
      expect(m.displayLarge!.fontSize, 40);
      expect(m.displayMedium!.fontSize, 36);
      expect(m.displaySmall, t.display);
      expect(m.headlineLarge!.fontSize, 28);
      expect(m.headlineMedium!.fontSize, 24);
      expect(m.headlineSmall, t.title);
      expect(m.titleLarge, t.title);
      expect(m.titleMedium, t.headline);
      expect(m.titleSmall, t.bodyStrong);
      expect(m.bodyLarge!.fontSize, 16);
      expect(m.bodyLarge!.height! * 16, closeTo(24, 1e-9));
      expect(m.bodyMedium, t.body);
      expect(m.bodySmall, t.caption);
      expect(m.labelLarge!.fontSize, t.button.fontSize);
      expect(m.labelLarge!.color, c.ink);
      expect(m.labelMedium, t.label);
      expect(m.labelSmall, t.captionStrong);
      for (final s in [
        m.displayLarge,
        m.headlineLarge,
        m.bodyLarge,
        m.labelLarge,
      ]) {
        expect(s!.fontFamily, _sans);
      }
    });
  });

  group('Mona Sans assets (§3.1)', () {
    // Unmodified upstream v2.0.27 statics: exact byte sizes of the published files.
    const files = {
      'MonaSans-Regular.ttf': 140880,
      'MonaSans-Medium.ttf': 140856,
      'MonaSans-SemiBold.ttf': 142900,
      'MonaSans-Bold.ttf': 143920,
      'MonaSansCondensed-SemiBold.ttf': 142960,
      'MonaSansCondensed-Bold.ttf': 143360,
      'MonaSansCondensed-ExtraBold.ttf': 145004,
    };

    test('the seven upstream statics and the OFL are bundled', () {
      files.forEach((name, size) {
        final f = File('assets/fonts/mona/$name');
        expect(f.existsSync(), isTrue, reason: name);
        expect(f.lengthSync(), size, reason: '$name was modified');
      });
      final ofl = File('assets/fonts/mona/OFL.txt').readAsStringSync();
      expect(ofl, contains('SIL OPEN FONT LICENSE Version 1.1'));
      expect(ofl, contains('Reserved Font Name "Mona"'));
    });

    test('pubspec declares both families with their weights', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('family: MonaSans\n'));
      expect(pubspec, contains('family: MonaSansCondensed\n'));
      expect(pubspec, contains('- assets/fonts/mona/OFL.txt'));
      for (final (file, weight) in [
        ('MonaSans-Regular.ttf', 400),
        ('MonaSans-Medium.ttf', 500),
        ('MonaSans-SemiBold.ttf', 600),
        ('MonaSans-Bold.ttf', 700),
        ('MonaSansCondensed-SemiBold.ttf', 600),
        ('MonaSansCondensed-Bold.ttf', 700),
        ('MonaSansCondensed-ExtraBold.ttf', 800),
      ]) {
        expect(
          pubspec,
          contains(
            '- asset: assets/fonts/mona/$file\n          weight: $weight',
          ),
          reason: file,
        );
      }
      // Native splash: white by day, gece asfaltı at night (§7.1).
      expect(pubspec, contains('color_dark: "#16191D"'));
      expect(pubspec, isNot(contains('#0F1114')));
    });

    test('the licence is registered for the "Lisanslar" page', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      AknFonts.registerLicense();
      final entries = await LicenseRegistry.licenses.toList();
      final mona = entries.where((e) => e.packages.contains('Mona Sans'));
      expect(mona, isNotEmpty);
      final text = mona.first.paragraphs.map((p) => p.text).join('\n');
      expect(text, contains('SIL OPEN FONT LICENSE'));
    });
  });

  group('real glyphs', () {
    setUpAll(loadMonaSans);
    final t = AknTextStyles.from(AknColors.light);

    double width(String text, TextStyle style) {
      final p = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final w = p.width;
      p.dispose();
      return w;
    }

    test(
      'figures are proportional (no code-styled tnum digits)',
      () {
        for (final s in [t.number, t.plateFigure, t.amount, t.body]) {
          expect(
            width('1111', s),
            lessThan(width('0000', s)),
            reason: '${s.fontFamily} ${s.fontWeight}: 1 is narrower than 0',
          );
        }
      },
      skip: monaSansAvailable() ? false : 'Mona Sans bulunamadı',
    );

    test(
      'weights map to distinct faces; Condensed is narrower',
      () {
        const word = 'Siparişlerim';
        final regular = width(word, t.body.copyWith(fontSize: 20));
        final bold = width(
          word,
          t.body.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
        );
        expect(bold, greaterThan(regular));
        final condensed = width(
          word,
          t.body.copyWith(
            fontSize: 20,
            fontFamily: _counter,
            fontWeight: FontWeight.w700,
          ),
        );
        expect(condensed, lessThan(bold));
        // Not the 1-em test squares: a real face is much narrower.
        expect(regular, lessThan(word.length * 20 * 0.75));
      },
      skip: monaSansAvailable() ? false : 'Mona Sans bulunamadı',
    );

    test(
      'Turkish letters and ₺ come from the face',
      () {
        const turkish = 'İıĞğŞşÇçÖöÜü₺';
        final w = width(turkish, t.body.copyWith(fontSize: 20));
        // The test font draws every glyph as a 1 em square (20 px each).
        expect(w, lessThan(turkish.length * 20 * 0.8));
        expect(w, greaterThan(0));
      },
      skip: monaSansAvailable() ? false : 'Mona Sans bulunamadı',
    );

    test(
      'ticking values get a fixed box from the widest sample (§3.3)',
      () {
        final style = t.bodySmall;
        final box = AknNumerals.fixedWidth(AknNumerals.countdownSample, style);
        for (final v in [
          '2 sa 57 dk kaldı',
          '41 dk kaldı',
          '9 sa 1 dk kaldı',
        ]) {
          expect(
            AknNumerals.fixedWidth(v, style),
            lessThanOrEqualTo(box),
            reason: v,
          );
        }
        expect(
          AknNumerals.fixedWidth(
            AknNumerals.countdownSample,
            style,
            textScaler: const TextScaler.linear(2),
          ),
          greaterThan(box * 1.8),
        );
        expect(AknNumerals.plateUnitGap, 6);
        expect(AknNumerals.readoutUnitGap, 3);
      },
      skip: monaSansAvailable() ? false : 'Mona Sans bulunamadı',
    );
  });
}

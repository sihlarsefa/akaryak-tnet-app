// Typography (v3 §1, aligned with the web panel 2026-10-28): Archivo — the panel's face — one family
// for words and figures; the type scale (sizes, line heights, weights, the panel's tracking, colours);
// tabular figures (`tnum`) on every numeric style and none on words; the Material text theme mapping;
// the bundled static instances of Archivo 2.001 (400–800), their pubspec registration, the OFL
// licence (no Reserved Font Name) and its "Lisanslar" entry; and real-glyph rendering (tabular
// digits, five distinct weights, Turkish and ₺).
import 'dart:io';

import 'package:akaryakitnet/core/ui/tokens.dart';
import 'package:akaryakitnet/core/ui/typography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';

const _sans = 'Archivo';
const _tnum = [FontFeature.tabularFigures()];

/// The few OpenType facts the asset test reads from a TTF: the family (name
/// 16, else 1), the version string (name 5) and the OS/2 weight class.
class _OpenType {
  _OpenType(Uint8List bytes) : _data = ByteData.sublistView(bytes);

  final ByteData _data;

  /// Offset of the table [tag] in the file.
  int _table(String tag) {
    for (var i = 0; i < _data.getUint16(4); i++) {
      final record = 12 + 16 * i;
      final name = String.fromCharCodes([
        for (var k = 0; k < 4; k++) _data.getUint8(record + k),
      ]);
      if (name == tag) return _data.getUint32(record + 8);
    }
    throw StateError('no $tag table');
  }

  /// The Windows (platform 3, en-US) name record [id], UTF-16BE.
  String? _name(int id) {
    final table = _table('name');
    final strings = table + _data.getUint16(table + 4);
    for (var i = 0; i < _data.getUint16(table + 2); i++) {
      final r = table + 6 + 12 * i;
      if (_data.getUint16(r) != 3 ||
          _data.getUint16(r + 4) != 0x409 ||
          _data.getUint16(r + 6) != id) {
        continue;
      }
      final start = strings + _data.getUint16(r + 10);
      return String.fromCharCodes([
        for (var k = 0; k < _data.getUint16(r + 8); k += 2)
          _data.getUint16(start + k),
      ]);
    }
    return null;
  }

  String? get family => _name(16) ?? _name(1);
  String? get version => _name(5);
  int get weight => _data.getUint16(_table('OS/2') + 4);
}

void main() {
  test(
    'one family: Archivo (the web panel\'s face), Turkish, tabular figures',
    () {
      expect(AknFonts.sans, _sans);
      // Deprecated: there is no condensed face any more.
      expect(AknFonts.condensed, AknFonts.sans);
      expect(AknFonts.locale, const Locale('tr', 'TR'));
      expect(AknNumerals.tabular, _tnum);
    },
  );

  group('AknTextStyles (v3 §1)', () {
    final t = AknTextStyles.from(AknColors.light);
    const c = AknColors.light;

    void spec(
      String name,
      TextStyle s, {
      required double size,
      required double line,
      required FontWeight weight,
      double tracking = 0,
      Color? color,
      bool figures = false,
    }) {
      expect(s.fontFamily, _sans, reason: name);
      expect(s.fontSize, size, reason: name);
      expect(s.height! * size, closeTo(line, 1e-9), reason: name);
      expect(s.fontWeight, weight, reason: name);
      expect(s.letterSpacing ?? 0, closeTo(tracking, 1e-9), reason: name);
      if (color != null) expect(s.color, color, reason: name);
      expect(s.leadingDistribution, TextLeadingDistribution.even, reason: name);
      expect(s.locale, const Locale('tr', 'TR'), reason: name);
      if (figures) {
        expect(s.fontFeatures, _tnum, reason: '$name: tabular figures');
      } else {
        expect(s.fontFeatures ?? const [], isEmpty, reason: '$name: words');
      }
    }

    test('the 15 existing fields', () {
      spec(
        'display',
        t.display,
        size: 28,
        line: 34,
        weight: FontWeight.w800,
        tracking: -0.4,
        color: c.ink,
      );
      spec(
        'title',
        t.title,
        size: 20,
        line: 26,
        weight: FontWeight.w700,
        tracking: -0.2,
        color: c.ink,
      );
      spec(
        'headline',
        t.headline,
        size: 17,
        line: 22,
        weight: FontWeight.w700,
        tracking: -0.1,
        color: c.ink,
      );
      spec(
        'body',
        t.body,
        size: 15,
        line: 22,
        weight: FontWeight.w400,
        color: c.text,
      );
      spec(
        'bodyStrong',
        t.bodyStrong,
        size: 15,
        line: 22,
        weight: FontWeight.w600,
        color: c.ink,
      );
      spec(
        'bodySmall',
        t.bodySmall,
        size: 14,
        line: 20,
        weight: FontWeight.w400,
        color: c.dim,
      );
      spec(
        'label',
        t.label,
        size: 13,
        line: 18,
        weight: FontWeight.w600,
        color: c.ink,
      );
      spec(
        'caption',
        t.caption,
        size: 12,
        line: 16,
        weight: FontWeight.w500,
        color: c.dim,
      );
      spec(
        'captionStrong',
        t.captionStrong,
        size: 12,
        line: 16,
        weight: FontWeight.w700,
        color: c.dim,
      );
      // Deprecated overline = captionStrong (sentence case, no tracking).
      expect(t.overline, t.captionStrong);
      spec(
        'amount',
        t.amount,
        size: 17,
        line: 22,
        weight: FontWeight.w700,
        tracking: -0.15,
        color: c.ink,
        figures: true,
      );
      spec(
        'amountLarge',
        t.amountLarge,
        size: 28,
        line: 34,
        weight: FontWeight.w800,
        tracking: -0.4,
        color: c.ink,
        figures: true,
      );
      spec(
        'number',
        t.number,
        size: 24,
        line: 30,
        weight: FontWeight.w800,
        tracking: -0.35,
        color: c.ink,
        figures: true,
      );
      spec(
        'numberLarge',
        t.numberLarge,
        size: 32,
        line: 38,
        weight: FontWeight.w800,
        tracking: -0.5,
        color: c.ink,
        figures: true,
      );
      spec('button', t.button, size: 16, line: 20, weight: FontWeight.w700);
      // The button label takes its colour from the button.
      expect(t.button.color, isNull);
    });

    test('the new fields', () {
      spec(
        'plateFigure',
        t.plateFigure,
        size: 46,
        line: 52,
        weight: FontWeight.w800,
        tracking: -0.7,
        color: c.ink,
        figures: true,
      );
      spec(
        'plateUnit',
        t.plateUnit,
        size: 24,
        line: 28,
        weight: FontWeight.w700,
        tracking: -0.2,
        color: c.ink,
        figures: true,
      );
      spec(
        'figureWord',
        t.figureWord,
        size: 20,
        line: 24,
        weight: FontWeight.w700,
        tracking: -0.15,
        color: c.ink,
      );
      spec(
        'readoutUnit',
        t.readoutUnit,
        size: 14,
        line: 30,
        weight: FontWeight.w700,
        color: c.ink,
        figures: true,
      );
      spec(
        'navLabel',
        t.navLabel,
        size: 11,
        line: 14,
        weight: FontWeight.w600,
        color: c.navInactive,
      );
    });

    test('built from the plate palette, every style prints the plate ink', () {
      final p = AknTextStyles.from(AknColors.dark.plateInk());
      for (final s in [
        p.display,
        p.body,
        p.plateFigure,
        p.plateUnit,
        p.figureWord,
        p.number,
        p.readoutUnit,
      ]) {
        // Decision G: the plate is a card; its figures print in ink
        // (white at night).
        expect(s.color, AknColors.dark.onPlate);
      }
      // Secondary text stays dim on the card.
      for (final s in [p.bodySmall, p.caption]) {
        expect(s.color, AknColors.dark.dim);
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

    test('recolor keeps sizes, weights and figures, swaps colours', () {
      final big = t.copyWith(display: t.display.copyWith(fontSize: 34));
      final r = big.recolor(AknColors.dark);
      expect(r.display.fontSize, 34);
      expect(r.display.color, AknColors.dark.ink);
      expect(r.bodySmall.color, AknColors.dark.dim);
      expect(r.navLabel.color, AknColors.dark.navInactive);
      expect(r.number.fontFeatures, _tnum);
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
        expect(s.fontFeatures ?? const [], isEmpty);
      }
    });
  });

  group('Archivo assets', () {
    // Static instances of Archivo 2.001 (wdth 100) built from the google/fonts
    // variable font (assets/fonts/archivo/SOURCE.txt): the weight each file
    // declares; Latin + Latin Extended keep them near 110 KB.
    const files = {
      'Archivo-Regular.ttf': 400,
      'Archivo-Medium.ttf': 500,
      'Archivo-SemiBold.ttf': 600,
      'Archivo-Bold.ttf': 700,
      'Archivo-ExtraBold.ttf': 800,
    };

    test('the five static instances and the OFL are bundled', () {
      files.forEach((name, weight) {
        final f = File('assets/fonts/archivo/$name');
        expect(f.existsSync(), isTrue, reason: name);
        expect(f.lengthSync(), inInclusiveRange(80000, 160000), reason: name);
        final font = _OpenType(f.readAsBytesSync());
        expect(font.family, 'Archivo', reason: name);
        expect(font.version, startsWith('Version 2.001'), reason: name);
        expect(font.weight, weight, reason: name);
      });
      final ofl = File('assets/fonts/archivo/OFL.txt').readAsStringSync();
      expect(ofl, startsWith('Copyright 2020 The Archivo Project Authors'));
      expect(ofl, contains('SIL OPEN FONT LICENSE Version 1.1'));
      // No Reserved Font Name: the copyright statement reserves none (the
      // licence body only defines the term), so the instances keep the name.
      final statement = ofl.substring(
        0,
        ofl.indexOf('SIL OPEN FONT LICENSE Version 1.1'),
      );
      expect(statement, isNot(contains('Reserved Font Name')));
      // The build recipe travels with the files.
      expect(
        File('assets/fonts/archivo/SOURCE.txt').readAsStringSync(),
        contains('Archivo[wdth,wght].ttf'),
      );
    });

    test('pubspec declares the family with its five weights', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('family: $_sans\n'));
      expect(pubspec, contains('- assets/fonts/archivo/OFL.txt'));
      files.forEach((file, weight) {
        expect(
          pubspec,
          contains(
            '- asset: assets/fonts/archivo/$file\n          weight: $weight',
          ),
          reason: file,
        );
      });
      // Plus Jakarta Sans (v3) and Mona Sans (v2) are gone.
      expect(pubspec, isNot(contains('PlusJakartaSans')));
      expect(pubspec, isNot(contains('assets/fonts/jakarta')));
      expect(Directory('assets/fonts/jakarta').existsSync(), isFalse);
      expect(pubspec, isNot(contains('MonaSans')));
      expect(pubspec, isNot(contains('assets/fonts/mona')));
      // Native splash at night: the dark page, Gece grafiti (also on
      // Android 12+).
      expect(AknColors.dark.bg, const Color(0xFF0E0F11));
      expect('color_dark: "#0E0F11"'.allMatches(pubspec), hasLength(2));
    });

    test('the licence is registered for the "Lisanslar" page', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      expect(AknFonts.licenseAsset, 'assets/fonts/archivo/OFL.txt');
      expect(AknFonts.licenseName, 'Archivo');
      AknFonts.registerLicense();
      final entries = await LicenseRegistry.licenses.toList();
      final archivo = entries.where((e) => e.packages.contains('Archivo'));
      expect(archivo, isNotEmpty);
      final text = archivo.first.paragraphs.map((p) => p.text).join('\n');
      expect(text, contains('SIL OPEN FONT LICENSE'));
      expect(text, contains('Archivo Project Authors'));
    });
  });

  group('real glyphs', () {
    setUpAll(loadUiFont);
    final t = AknTextStyles.from(AknColors.light);
    final skip = uiFontAvailable() ? false : 'Archivo bulunamadı';

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
      'numeric styles set tabular figures; words keep proportional ones',
      () {
        for (final (name, s) in [
          ('amount', t.amount),
          ('amountLarge', t.amountLarge),
          ('number', t.number),
          ('numberLarge', t.numberLarge),
          ('plateFigure', t.plateFigure),
          ('plateUnit', t.plateUnit),
          ('readoutUnit', t.readoutUnit),
        ]) {
          final zeros = width('0000', s);
          for (final v in ['1111', '4747']) {
            expect(
              width(v, s),
              closeTo(zeros, 0.01),
              reason: '$name: "$v" is as wide as "0000"',
            );
          }
        }
        // The face's own figures are proportional (1 is narrower than 0):
        // tnum is what keeps amounts in columns and ticking values still.
        expect(width('1111', t.body), lessThan(width('0000', t.body)));
      },
      skip: skip,
    );

    test('the five weights map to five faces; condensed is the same face', () {
      const word = 'Siparişlerim';
      double at(FontWeight weight, {String family = _sans}) => width(
        word,
        t.body.copyWith(fontSize: 20, fontWeight: weight, fontFamily: family),
      );
      const weights = [
        FontWeight.w400,
        FontWeight.w500,
        FontWeight.w600,
        FontWeight.w700,
        FontWeight.w800,
      ];
      final widths = [for (final w in weights) at(w)];
      for (var i = 1; i < weights.length; i++) {
        expect(widths[i], greaterThan(widths[i - 1]), reason: '${weights[i]}');
      }
      // The deprecated condensed alias draws the same face.
      expect(
        at(FontWeight.w700, family: AknFonts.condensed),
        closeTo(widths[3], 0.01),
      );
      // Not the 1-em test squares: a real face is much narrower.
      expect(widths.first, lessThan(word.length * 20 * 0.75));
    }, skip: skip);

    test('Turkish letters and ₺ come from the face', () {
      const turkish = 'İıĞğŞşÇçÖöÜü₺';
      final w = width(turkish, t.body.copyWith(fontSize: 20));
      // The test font draws every glyph as a 1 em square (20 px each).
      expect(w, lessThan(turkish.length * 20 * 0.8));
      expect(w, greaterThan(0));
    }, skip: skip);

    test('ticking values get a fixed box from the widest sample', () {
      final style = t.bodySmall;
      final box = AknNumerals.fixedWidth(AknNumerals.countdownSample, style);
      for (final v in ['2 sa 57 dk kaldı', '41 dk kaldı', '9 sa 1 dk kaldı']) {
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
    }, skip: skip);
  });
}

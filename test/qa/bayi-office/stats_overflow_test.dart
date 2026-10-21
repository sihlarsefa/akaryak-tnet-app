// QA "bayi-office": /stats (yönetici istatistikleri) 360×640 telefonda 1,0× açık ve 2,0× koyu temada
// taşmasız açılmalı; ana sayfadaki yönetici destesi de. Her yerleşim hatası ayrı ayrı toplanır (hangi
// dosya / satır) ve tek iddiada yazılır.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/a11y.dart';
import 'office_support.dart';

const _qaOut = String.fromEnvironment('QA_OUT');

Future<List<String>> _collect(
  WidgetTester tester,
  String persona,
  A11yVariant v,
  String route,
) async {
  final errors = <String>[];
  final old = FlutterError.onError;
  FlutterError.onError = (d) {
    final s = d.toString();
    final m = RegExp(r'file://[^\s:]+/lib/([^\s]+?):(\d+):(\d+)').firstMatch(s);
    final head = d.exceptionAsString().split('\n').first;
    errors.add(
      '$head @ ${m == null ? '?' : 'lib/${m.group(1)}:${m.group(2)}'}',
    );
  };
  try {
    final app = await OfficeApp.start(tester, persona, variant: v);
    app.router.go(route);
    await app.settle(rounds: 10);
    // Kaydırarak tüm bölümleri kur.
    final scrollables = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    );
    for (var i = 0; i < 12 && scrollables.evaluate().isNotEmpty; i++) {
      await tester.drag(scrollables.first, const Offset(0, -500));
      await app.settle(rounds: 2);
    }
    await app.finish();
  } finally {
    FlutterError.onError = old;
  }
  return errors;
}

/// Bugün kırmızı olan durumlar (entegratörler düzeltince kaldırır):
/// - QA BO-01: 1,0×'te ekip sıralama satırı (mix_chart.dart:182) taşıyor (ekip bölümü olanlar).
/// - QA BO-02: 2,0×'te PlateReadouts (plate.dart:611) ve PlateFunnel (plate.dart:1665) taşıyor.
/// Her ikisi düzeltildi (mix_chart.dart ve plate.dart); liste boş kalır.
String? _skip(String persona, String route, String tag) => null;

void main() {
  const cases = [
    ('sahip', '/stats'),
    ('mudur', '/stats'),
    ('satis', '/stats'),
    ('finans', '/stats'),
    ('muhasebe', '/stats'),
    ('izleyici', '/stats'),
    ('ozelrol', '/stats'),
    ('sahip', '/home'),
    ('finans', '/home'),
  ];
  for (final (persona, route) in cases) {
    for (final (tag, v) in const [
      ('1x', A11yVariant(1, Brightness.light)),
      ('2x', A11yVariant.largeDark),
    ]) {
      testWidgets(
        '$persona $route $tag: yerleşim hatası yok',
        (tester) async {
          final errors = await _collect(tester, persona, v, route);
          final unique = errors.toSet().toList();
          if (_qaOut.isNotEmpty) {
            File(
                '$_qaOut/stats_${persona}_${route.replaceAll('/', '')}_$tag.txt',
              )
              ..createSync(recursive: true)
              ..writeAsStringSync(unique.isEmpty ? 'OK\n' : unique.join('\n'));
          }
          expect(unique, isEmpty, reason: unique.join('\n'));
        },
        skip: _skip(persona, route, tag) != null,
      );
    }
  }
}

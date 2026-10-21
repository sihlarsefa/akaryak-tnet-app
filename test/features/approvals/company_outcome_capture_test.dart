// Şirket içi talep onayı sonucu (tasarım v2 §7.13, müşteri tarafı) görüntüsü: onaylayan kişi talebi
// onaylar, "Talep sonucu" bölümü (özet cümlesi, satır lambaları, "Başarısız satırları yeni siparişe
// aktar") görünür. Altın test değildir; normal çalışmada atlanır:
//
//   flutter test test/features/approvals/company_outcome_capture_test.dart \
//     --dart-define=AKN_SCREENS_DIR=/tam/yol
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
import 'a5_test_kit.dart';

const _outDir = String.fromEnvironment('AKN_SCREENS_DIR');

Future<void> _shot(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(a5RootKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_outDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    if (_outDir.isNotEmpty) await loadRealFonts();
  });

  for (final (tag, brightness) in const [
    ('acik-1x', Brightness.light),
    ('koyu-1x', Brightness.dark),
  ]) {
    testWidgets('şirket içi talep sonucu $tag', (tester) async {
      await pumpA5(
        tester,
        persona: 'onay',
        location: '/approvals/9003',
        brightness: brightness,
        size: const Size(390, 844),
        reduceMotion: true,
      );
      await _shot(tester, '$tag/onay_1_talep');
      final approve = find.text('Onayla');
      if (approve.evaluate().isNotEmpty) {
        await tapText(tester, 'Onayla', first: true);
        if (find.text('Onayla').evaluate().length > 1) {
          await tapText(tester, 'Onayla', last: true);
        }
        await pumpFor(tester);
      }
      final result = find.text('Talep sonucu');
      if (result.evaluate().isNotEmpty) {
        await tester.ensureVisible(result);
        await pumpFor(tester, const Duration(milliseconds: 300));
      }
      await _shot(tester, '$tag/onay_2_sonuc');
      await finish(tester);
    }, skip: _outDir.isEmpty);
  }
}

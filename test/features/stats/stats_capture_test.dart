// İstatistik ekran görüntüleri (görsel kontrol; altın karşılaştırma değildir). Normal çalışmada atlanır:
//
//   flutter test test/features/stats/stats_capture_test.dart --dart-define=AKN_STATS_SHOTS=/tam/yol
//
// Deste (her kart), saha temsilcisi ve müşteri desteleri, istatistik sayfası; açık 1,0× ve koyu 1,0× /
// 1,6×. Gerçek Roboto ve Material simgeleriyle çizilir.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
import 'support/stats_app.dart';

const _outDir = String.fromEnvironment('AKN_STATS_SHOTS');

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_outDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<void> _longSettle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 4)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(() async {
    if (_outDir.isNotEmpty) await loadRealFonts();
  });

  const variants = [
    ('acik', Brightness.light, 1.0),
    ('koyu', Brightness.dark, 1.0),
    ('buyuk', Brightness.light, 1.6),
  ];

  for (final persona in ['sahip', 'saha', 'musteri']) {
    for (final (tag, brightness, scale) in variants) {
      testWidgets('$persona $tag deste', (tester) async {
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = true);
        final key = GlobalKey();
        final app = await StatsTestApp.start(
          tester,
          persona: persona,
          brightness: brightness,
          textScale: scale,
          reduceMotion: false,
          size: Size(380, scale > 1 ? 900 : 640),
          boundaryKey: key,
        );
        await _longSettle(tester);
        final next = find.byKey(const ValueKey('deck-next'));
        final count = next.evaluate().isEmpty ? 1 : 8;
        for (var i = 0; i < count; i++) {
          await _capture(
            tester,
            key,
            '$persona/${persona}_${tag}_kart${i + 1}',
          );
          if (next.evaluate().isEmpty) break;
          await tester.tap(next);
          await _longSettle(tester);
        }
        await app.finish(tester);
        debugDisableShadows = true;
      }, skip: _outDir.isEmpty);
    }

    for (final (tag, brightness, scale) in variants.take(2)) {
      testWidgets('$persona $tag sayfa', (tester) async {
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = true);
        final key = GlobalKey();
        final app = await StatsTestApp.start(
          tester,
          persona: persona,
          location: '/stats',
          brightness: brightness,
          textScale: scale,
          reduceMotion: false,
          size: const Size(380, 760),
          boundaryKey: key,
        );
        await _longSettle(tester);
        for (var i = 0; i < 6; i++) {
          await _capture(
            tester,
            key,
            '$persona/${persona}_${tag}_sayfa${i + 1}',
          );
          await tester.drag(verticalScrollable, const Offset(0, -560));
          await _longSettle(tester);
        }
        await app.finish(tester);
        debugDisableShadows = true;
      }, skip: _outDir.isEmpty);
    }
  }
}

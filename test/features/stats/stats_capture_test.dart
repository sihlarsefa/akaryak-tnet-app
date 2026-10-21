// İstatistik ekran görüntüleri (görsel kontrol; altın karşılaştırma değildir). Normal çalışmada atlanır:
//
//   flutter test test/features/stats/stats_capture_test.dart --dart-define=AKN_SCREENS_DIR=/tam/yol
//
// (eski ad `AKN_STATS_SHOTS` de geçerli). Deste (her kart, devir anı, ilk açılışın sayaç kareleri),
// saha temsilcisi ve müşteri desteleri, `/stats` sayfası; açık / koyu, 1,0× / 1,3× / 2,0×.
// Mona Sans ve Material simgeleriyle çizilir; tasarım panosuyla (work/design-v2) karşılaştırın.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
import 'support/stats_app.dart';

const _screens = String.fromEnvironment('AKN_SCREENS_DIR');
const _legacy = String.fromEnvironment('AKN_STATS_SHOTS');
const _outDir = _screens == '' ? _legacy : _screens;

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

Future<void> _longSettle(WidgetTester tester, {int rounds = 30}) async {
  for (var i = 0; i < rounds; i++) {
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
    ('orta', Brightness.light, 1.3),
    ('buyuk', Brightness.light, 2.0),
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
          size: Size(390, scale > 1 ? 640 : 520),
          boundaryKey: key,
        );
        await _longSettle(tester);
        final count = deckPositionText.evaluate().isEmpty
            ? 1
            : deckPosition(tester).$2;
        final cards = scale > 1.0 && tag != 'orta' ? 2 : count;
        for (var i = 0; i < cards; i++) {
          await _capture(
            tester,
            key,
            '$persona/${persona}_${tag}_kart${i + 1}',
          );
          if (deckPositionText.evaluate().isEmpty) break;
          await tapDeckNext(tester);
          await _longSettle(tester, rounds: 8);
        }
        await app.finish(tester);
        debugDisableShadows = true;
      }, skip: _outDir.isEmpty);
    }

    for (final (tag, brightness, scale) in [
      ('acik', Brightness.light, 1.0),
      ('koyu', Brightness.dark, 1.0),
      ('buyuk', Brightness.dark, 2.0),
    ]) {
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
          size: const Size(390, 844),
          boundaryKey: key,
        );
        await _longSettle(tester);
        for (var i = 0; i < 5; i++) {
          await _capture(
            tester,
            key,
            '$persona/${persona}_${tag}_sayfa${i + 1}',
          );
          await tester.drag(verticalScrollable, const Offset(0, -640));
          await _longSettle(tester, rounds: 8);
        }
        await app.finish(tester);
        debugDisableShadows = true;
      }, skip: _outDir.isEmpty);
    }
  }

  testWidgets('yükleniyor ve hata kâğıtları', (tester) async {
    final key = GlobalKey();
    var app = await StatsTestApp.start(
      tester,
      persona: 'sahip',
      size: const Size(390, 520),
      boundaryKey: key,
      setup: (s) => s
        ..latencyEnabled = true
        ..minLatency = const Duration(seconds: 30)
        ..maxLatency = const Duration(seconds: 31),
    );
    await _capture(tester, key, 'sahip/sahip_yukleniyor');
    await tester.pump(const Duration(seconds: 32));
    await _longSettle(tester, rounds: 6);
    await app.finish(tester);
    app = await StatsTestApp.start(
      tester,
      persona: 'sahip',
      size: const Size(390, 520),
      boundaryKey: key,
      probe: StatsProbe(fail: FakeResponse.server),
    );
    await _capture(tester, key, 'sahip/sahip_hata');
    await app.finish(tester);
  }, skip: _outDir.isEmpty);

  testWidgets('sahip devir ve sayaç kareleri', (tester) async {
    debugDisableShadows = false;
    addTearDown(() => debugDisableShadows = true);
    final key = GlobalKey();
    final app = await StatsTestApp.start(
      tester,
      persona: 'sahip',
      reduceMotion: false,
      size: const Size(390, 520),
      boundaryKey: key,
      settleRounds: 4,
    );
    // İlk açılış: plaka yanar, rakam döner, çubuklar yükselir.
    for (final (i, ms) in [(1, 60), (2, 240), (3, 300), (4, 400), (5, 600)]) {
      await tester.pump(Duration(milliseconds: ms));
      await _capture(tester, key, 'sahip/sahip_sayac$i');
    }
    await _longSettle(tester);
    // Sürüklerken plaka hemen arkadaki kâğıda geçer.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(LanePager)) - const Offset(0, 200),
    );
    await gesture.moveBy(const Offset(-40, 0));
    await gesture.moveBy(const Offset(-50, 0));
    await tester.pump();
    await _capture(tester, key, 'sahip/sahip_devir');
    await gesture.up();
    await _longSettle(tester, rounds: 10);
    await app.finish(tester);
    debugDisableShadows = true;
  }, skip: _outDir.isEmpty);
}

// Onaylarım ekran görüntüleri (tasarım v2 "Turuncu Plaka" karşılaştırması): liste ve ayrıntılar.
// Normal test çalışmasında atlanır; görüntü almak için:
//
//   flutter test test/features/approvals/approvals_capture_test.dart --dart-define=AKN_SCREENS_DIR=/tam/yol
//
// 390×844 dp, 2× piksel; açık 1,0×, koyu 1,0× ve açık 2,0× yazı. Altın (golden) karşılaştırma değildir.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
import 'a5_test_kit.dart';

const _outDir = String.fromEnvironment('AKN_SCREENS_DIR');
const _only = String.fromEnvironment('AKN_ONLY');

Future<void> _shot(WidgetTester tester, String name) async {
  final ro =
      tester.renderObject(find.byKey(a5RootKey)) as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await ro.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_outDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

typedef _Variant = ({String tag, Brightness b, double scale});

const List<_Variant> _variants = [
  (tag: 'light', b: Brightness.light, scale: 1),
  (tag: 'dark', b: Brightness.dark, scale: 1),
  (tag: 'light-2x', b: Brightness.light, scale: 2),
];

void _capture(
  String name, {
  required String persona,
  required String location,
  bool scrolled = false,
}) {
  for (final v in _variants) {
    testWidgets('$name ${v.tag}', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      await pumpA5(
        tester,
        persona: persona,
        location: location,
        size: const Size(390, 844),
        brightness: v.b,
        textScale: v.scale,
        reduceMotion: true,
      );
      await pumpFor(tester);
      await _shot(tester, '$name-${v.tag}');
      if (scrolled) {
        await scrollThrough(tester, maxSteps: 1);
        await _shot(tester, '$name-${v.tag}-b');
      }
      await finish(tester);
    }, skip: _outDir.isEmpty || (_only.isNotEmpty && !name.startsWith(_only)));
  }
}

void main() {
  setUpAll(() async {
    if (_outDir.isNotEmpty) await loadRealFonts();
  });

  _capture('12-approvals', persona: 'finans', location: '/approvals');
  _capture(
    '13-approval-finance',
    persona: 'finans',
    location: '/approvals/9001',
    scrolled: true,
  );
  _capture(
    '14-approval-form',
    persona: 'satis',
    location: '/approvals/9002',
    scrolled: true,
  );
}

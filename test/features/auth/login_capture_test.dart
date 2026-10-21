// Giriş ekranı ekran görüntüleri (G renk dili + demo hesapları, sahip kararları 2026-10-21). Normal test
// çalışmasında atlanır; görüntü almak için:
//
//   flutter test test/features/auth/login_capture_test.dart --dart-define=AKN_SCREENS_DIR=/tam/yol
//
// 390×844 (ilk ekran) ve 360 dp genişlikte sayfanın tamamı; açık, koyu ve 2,0× yazı. 2× piksel PNG.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/auth/presentation/widgets/demo_accounts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_test_support.dart';

const _outDir = String.fromEnvironment('AKN_SCREENS_DIR');

void _view(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
  debugDisableShadows = false;
  addTearDown(tester.view.reset);
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump();
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(Offset.zero & view.size, pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_outDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<void> _end(WidgetTester tester) async {
  AppToast.dismiss();
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  debugDisableShadows = true;
}

const _variants = [
  ('acik-1x', 1.0, Brightness.light),
  ('koyu-1x', 1.0, Brightness.dark),
  ('acik-2x', 2.0, Brightness.light),
  ('koyu-2x', 2.0, Brightness.dark),
];

void main() {
  final skip = _outDir.isEmpty;

  for (final (tag, scale, b) in _variants) {
    testWidgets('giriş ilk ekran 390 $tag', (tester) async {
      _view(tester, const Size(390, 844));
      await pumpAuthRoute(tester, '/login', textScale: scale, brightness: b);
      await pumpFor(tester, const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await _shot(tester, 'giris-390-$tag');
      await _end(tester);
    }, skip: skip);

    testWidgets('giriş tam boy 360 $tag', (tester) async {
      _view(tester, Size(360, scale > 1 ? 3000 : 1700));
      await pumpAuthRoute(tester, '/login', textScale: scale, brightness: b);
      await pumpFor(tester, const Duration(seconds: 1));
      expect(tester.takeException(), isNull);
      await _shot(tester, 'giris-360-tam-$tag');
      await _end(tester);
    }, skip: skip);
  }

  testWidgets('giriş: Bayi satırı kaydırılmış + "Tümünü gör" sayfası', (
    tester,
  ) async {
    _view(tester, const Size(390, 844));
    await pumpAuthRoute(tester, '/login');
    await pumpFor(tester, const Duration(seconds: 1));
    // En yakın kaydırma alanı: Bayi satırı (sayfanın kendisi de kayar).
    final bayiRow = find
        .ancestor(
          of: find.text('Mehmet Demir'),
          matching: find.byType(SingleChildScrollView),
        )
        .first;
    await tester.drag(bayiRow, const Offset(-600, 0));
    await pumpFor(tester, const Duration(seconds: 1));
    await _shot(tester, 'giris-390-bayi-kaydirma');
    await tester.tap(find.text('Tümünü gör'));
    await pumpFor(tester, const Duration(seconds: 1));
    await _shot(tester, 'giris-390-tumunu-gor');
    await _end(tester);
  }, skip: skip);

  testWidgets('giriş: canlı derleme (demo yok)', (tester) async {
    _view(tester, const Size(390, 844));
    await pumpAuthRoute(
      tester,
      '/login',
      overrides: [demoLoginsEnabledProvider.overrideWithValue(false)],
    );
    await pumpFor(tester, const Duration(seconds: 1));
    await _shot(tester, 'giris-390-canli');
    await _end(tester);
  }, skip: skip);
}

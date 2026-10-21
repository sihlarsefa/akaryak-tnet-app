import 'package:akaryakitnet/core/ui/gallery/gallery_route.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test_helpers.dart';

void main() {
  tearDown(AppToast.dismiss);

  testWidgets('gallery route path', (tester) async {
    expect(kDesignGalleryPath, '/dev/gallery');
    expect(designGalleryRoute().path, '/dev/gallery');
  });

  testBothThemes('every gallery tab renders without errors', (tester, b) async {
    await pumpUi(
      tester,
      const DesignGalleryPage(),
      brightness: b,
      scaffold: false,
      size: const Size(400, 860),
    );
    await tester.pump(const Duration(milliseconds: 500));
    const tabs = [
      'Renkler',
      'Yazı',
      'Butonlar',
      'Kartlar',
      'Durumlar',
      'Formlar',
      'Akış',
      'Geri bildirim',
      'Hareket',
      'Gezinme',
    ];
    for (final tab in tabs) {
      await tester.ensureVisible(find.widgetWithText(Tab, tab));
      await tester.pump();
      await tester.tap(find.widgetWithText(Tab, tab));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull, reason: tab);
      // Scroll through the tab to build every section.
      final list = find.byType(Scrollable).last;
      await tester.drag(list, const Offset(0, -2000));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull, reason: '$tab (scrolled)');
    }
  });

  testWidgets('gallery toggles theme, text size and motion', (tester) async {
    await pumpUi(
      tester,
      const DesignGalleryPage(),
      scaffold: false,
      size: const Size(400, 860),
    );
    await tester.tap(find.bySemanticsLabel('Koyu temaya geç'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.bySemanticsLabel('Açık temaya geç'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp('Yazı boyutu')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.bySemanticsLabel('Hareketi azalt'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.bySemanticsLabel('Hareketi aç'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

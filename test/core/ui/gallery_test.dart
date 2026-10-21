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
      'Kahraman',
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

  testBothThemes('hero page preview opens (hero app bar + header)', (
    tester,
    b,
  ) async {
    await pumpUi(
      tester,
      const DesignGalleryPage(),
      brightness: b,
      scaffold: false,
      size: const Size(400, 860),
    );
    await tester.tap(find.widgetWithText(Tab, 'Kahraman'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final open = find.text('Kahraman sayfasını aç');
    await tester.ensureVisible(open);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(open);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(AknHeroHeader), findsOneWidget);
    expect(find.text('Günaydın, Ayşe'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Scroll: the header slides under the pinned orange bar.
    await tester.drag(find.byType(ListView).last, const Offset(0, -400));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
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

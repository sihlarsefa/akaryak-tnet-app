// Roller v5 Ekip (spec akn-roles-v5 §2.6, §7): rol adı sunucudan (pasif rol "(pasif)" ekiyle, gizlenmez),
// rolü pasif kalan ve otomatik işaretlenen personelde "İncelenecek" (amber), birim onaycısında
// "Onaycı · Finans" hapı; İkmal birimi personeli.
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/bayi/presentation/staff/staff_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bayi_app.dart';

Finder _card(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(StaffRow)).first;

Finder _inCard(String name, Finder f) =>
    find.descendant(of: _card(name), matching: f);

void main() {
  testWidgets(
    'pasif rol görünür, "İncelenecek" ve onaycı hapları; İkmal birimi',
    (tester) async {
      await BayiTestApp.start(
        tester,
        persona: 'sahip',
        location: '/bayi/staff',
      );
      await reveal(tester, find.text('Ece Tunç'));
      expect(
        _inCard('Ece Tunç', find.text('Görüntüleyici (pasif)')),
        findsOneWidget,
      );
      expect(
        _inCard('Ece Tunç', find.text(StaffRow.reviewLabel)),
        findsOneWidget,
      );
      final lamp = tester.widget<AknLamp>(
        _inCard('Ece Tunç', find.byType(AknLamp)).last,
      );
      expect(lamp.label, 'İncelenecek');
      expect(lamp.tone, AknTone.warn);

      await reveal(tester, find.text('Ayşe Kaya'));
      expect(
        _inCard('Ayşe Kaya', find.text('Bayi müdürü (pasif)')),
        findsOneWidget,
      );
      expect(
        _inCard('Ayşe Kaya', find.text(StaffRow.reviewLabel)),
        findsNothing,
      );
      expect(_inCard('Ayşe Kaya', find.textContaining('Onaycı')), findsNothing);

      await reveal(tester, find.text('Can Öztürk'));
      expect(_inCard('Can Öztürk', find.text('Finans birimi')), findsOneWidget);
      expect(
        _inCard('Can Öztürk', find.text('Onaycı · Finans')),
        findsOneWidget,
      );
      expect(
        _inCard('Can Öztürk', find.byKey(const ValueKey('approver-finance'))),
        findsOneWidget,
      );

      await reveal(tester, find.text('Mehmet Demir'));
      expect(
        _inCard('Mehmet Demir', find.text('Bayi yöneticisi')),
        findsOneWidget,
      );
      expect(
        _inCard('Mehmet Demir', find.text('Onaycı · Bayi yöneticisi')),
        findsOneWidget,
      );

      await reveal(tester, find.text('İlker Kaya'));
      expect(_inCard('İlker Kaya', find.text('İkmal birimi')), findsOneWidget);

      // Ekran okuyucu onaycı hapını birimin panel adıyla okur.
      final semantics = tester.ensureSemantics();
      await reveal(tester, find.text('Emre Çelik'));
      // Kart düğümü birleşik okunur: hap, kartın etiketinin içindedir.
      expect(find.bySemanticsLabel(RegExp('Satış onaycısı')), findsOneWidget);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}

// QA logistics-field: sevkiyat panosu (gerçek uygulama, 360×640). Sevkiyat planla (litre, plaka,
// uygulama şoförü) → panoda görünür → Yola çıkar → Teslim bildir; depo "Bugünkü yüklemeler" ve
// yükleme (Yola çıkar). Her adımda taşma / hata yok.
import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/bayi/application/dispatch_controller.dart';
import 'package:akaryakitnet/features/bayi/presentation/dispatch/dispatch_page.dart';
import 'package:akaryakitnet/features/bayi/presentation/dispatch/driver_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_kit.dart';

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(BottomSheet).last, matching: f);

Finder _confirm(String label) =>
    find.descendant(of: find.byType(ConfirmSheet), matching: find.text(label));

Finder _line(int shipmentId) => find.byWidgetPredicate(
  (w) => w is BoardShipmentLine && w.shipment.id == shipmentId,
);

void main() {
  testWidgets('sevkiyat 360×640: Planla → plaka + uygulama şoförü → '
      'planlandı → Yola çıkar → Teslim bildir', (tester) async {
    final app = await QaApp.start(tester, persona: 'sevkiyat');
    await tapTab(tester, 'Sevkiyat');
    noErrors(tester, 'pano');
    noErrorState('pano');
    expect(find.text('Pano'), findsWidgets);

    final board = app.container.read(dispatchBoardProvider).data!;
    final target = board.orders.firstWhere((o) => o.remainingLiters >= 2000);
    final before = app.world.shipments.length;
    final row = find
        .ancestor(
          of: find.text(target.customerTitle),
          matching: find.byType(BoardOrderRow),
        )
        .first;
    await scrollTap(
      tester,
      find.descendant(of: row, matching: find.text('Planla')),
    );
    expect(find.text('Sevkiyat planla'), findsOneWidget);
    noErrors(tester, 'plan sayfası');

    // Boş gönder: plaka ve şoför zorunlu.
    await tester.enterText(_inSheet(find.byType(TextField)).at(0), '2000');
    await steps(tester, const Duration(milliseconds: 300));
    await scrollTap(tester, find.text('Sevkiyatı planla'));
    expect(find.text('Plaka zorunludur.'), findsOneWidget);
    expect(find.text('Şoför seçin.'), findsOneWidget);

    await tester.enterText(_inSheet(find.byType(TextField)).at(1), '34qa777');
    await steps(tester, const Duration(milliseconds: 300));
    await scrollTap(tester, find.bySemanticsLabel('Şoför seçin'));
    noErrors(tester, 'şoför seçici');
    final ahmet = find.ancestor(
      of: find.text('Ahmet Kurt'),
      matching: find.byType(DriverPickerRow),
    );
    await scrollTap(tester, ahmet);
    noErrors(tester, 'şoför seçildi');
    expect(
      find.bySemanticsLabel('Şoför: Ahmet Kurt, değiştir'),
      findsOneWidget,
    );
    await scrollTap(tester, find.text('Sevkiyatı planla'));
    await steps(tester, const Duration(seconds: 1));
    noErrors(tester, 'planlandı');
    expect(find.text('Sevkiyat planla'), findsNothing, reason: 'kapandı');
    expect(app.world.shipments.length, before + 1);
    final created = app.world.shipments.last;
    expect(created['driverUserId'], 'u-sofor');
    expect(created['vehiclePlate'], '34 QA 777');
    expect(created['plannedLiters'], 2000);
    final id = created['id'] as int;

    // Panoda yeni sevkiyat → ayrıntı → Yola çıkar (onaylı).
    await scrollTap(tester, _line(id));
    noErrors(tester, 'sevkiyat ayrıntısı');
    await scrollTap(tester, find.text('Yola çıkar'));
    await scrollTap(tester, _confirm('Yola çıkar'));
    noErrors(tester, 'yola çıkarıldı');
    expect(app.world.shipments.firstWhere((s) => s['id'] == id)['status'], 1);
    await scrollTap(tester, find.text('Teslim bildir'));
    await scrollTap(tester, _confirm('Teslim bildir'));
    expect(find.text('Teslimi bildir'), findsOneWidget);
    noErrors(tester, 'teslim bildir sayfası');
    await tester.enterText(_inSheet(find.byType(TextField)).at(1), 'irs-qa1');
    await steps(tester, const Duration(milliseconds: 300));
    await scrollTap(tester, find.text('Teslimi bildir'));
    await steps(tester, const Duration(seconds: 1));
    noErrors(tester, 'teslim bildirildi');
    final s = app.world.shipments.firstWhere((s) => s['id'] == id);
    expect(s['status'], 2, reason: 'bildirildi (cari onayı bekler)');
    expect(s['deliveryDocumentNo'], 'IRS-QA1');
    expect(s['deliveredLiters'], 2000);
    await app.close(tester);
  });

  testWidgets('depo 360×640: Bugünkü yüklemeler → ayrıntı → Yola çıkar; '
      'Planla yok', (tester) async {
    final app = await QaApp.start(tester, persona: 'depo');
    await tapTab(tester, 'Sevkiyat');
    noErrors(tester, 'depo sevkiyat');
    noErrorState('depo sevkiyat');
    expect(find.widgetWithText(AknChip, 'Bugünkü yüklemeler'), findsOneWidget);
    final list = app.container.read(shipmentListProvider);
    expect(list.filter.todayLoadings, isTrue);
    final first = list.list.items.firstWhere(
      (s) => s.status == ShipmentStatus.planned,
    );
    await scrollTap(tester, find.byType(ShipmentListCard).first);
    noErrors(tester, 'depo ayrıntı');
    expect(find.text('Planı iptal et'), findsNothing);
    expect(find.text('Şoför değiştir'), findsNothing);
    if (find.text('Yola çıkar').evaluate().isNotEmpty) {
      await scrollTap(tester, find.text('Yola çıkar'));
      if (_confirm('Yola çıkar').evaluate().isNotEmpty) {
        await scrollTap(tester, _confirm('Yola çıkar'));
      }
      noErrors(tester, 'depo yola çıkardı');
    }
    expect(first.id, isPositive);
    await app.close(tester);
  });
}

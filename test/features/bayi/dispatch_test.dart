// Sevkiyat: plan sayfası (litre ≤ kalan, plaka, şoför seçimi: telefon + "uygulamada"), uygulama şoförü
// onayı, Yola çıkar → Teslim bildir, Şoför değiştir, İptal; itirazlı sevkiyat ayrıntısı; depo
// (planlamaz ama yola çıkarır, listeyi "Bugünkü yüklemeler" ile açar) ve sipariş masası / görüntüleyici
// (salt okunur).
import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/core/utils/format.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:akaryakitnet/features/bayi/application/dispatch_controller.dart';
import 'package:akaryakitnet/features/bayi/data/dispatch_models.dart';
import 'package:akaryakitnet/features/bayi/presentation/dispatch/dispatch_page.dart';
import 'package:akaryakitnet/features/bayi/presentation/dispatch/driver_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bayi_app.dart';

/// En üstteki alt sayfanın içi.
Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(BottomSheet).last, matching: f);

/// Onay sayfasındaki düğme.
Finder _confirm(String label) =>
    find.descendant(of: find.byType(ConfirmSheet), matching: find.text(label));

Finder _boardCard(String customer) => find
    .ancestor(of: find.text(customer), matching: find.byType(BoardOrderRow))
    .first;

Finder _line(int shipmentId) => find.byWidgetPredicate(
  (w) => w is BoardShipmentLine && w.shipment.id == shipmentId,
);

Finder _driverCard(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(DriverPickerRow));

ShipmentBoard _board(BayiTestApp app) =>
    app.container.read(dispatchBoardProvider).data!;

ShipmentDetail? _detail(BayiTestApp app, int id) =>
    app.container.read(shipmentDetailProvider(id)).data;

void main() {
  testWidgets(
    'plan: litre kalanı aşamaz; plaka ve şoför zorunlu; şoför seçici telefon ve '
    '"uygulamada" gösterir',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'sevkiyat',
        location: '/dispatch',
        // Çekirdek PlateField önizlemesi azaltılmış harekette sıfır süreli AnimatedSize kullanır.
        reduceMotion: false,
      );
      final target = _board(
        app,
      ).orders.firstWhere((o) => o.bucket == BoardBucket.today);
      await scrollTap(
        tester,
        find.descendant(
          of: _boardCard(target.customerTitle),
          matching: find.text('Planla'),
        ),
      );
      expect(find.text('Sevkiyat planla'), findsOneWidget);

      final litres = _inSheet(find.byType(TextField)).at(0);
      await tester.enterText(litres, Fmt.number(target.remainingLiters + 500));
      await BayiTestApp.settle(tester);
      await scrollTap(tester, find.text('Sevkiyatı planla'));
      expect(
        find.text(
          'En fazla ${Fmt.liters(target.remainingLiters)} girilebilir.',
        ),
        findsOneWidget,
      );
      expect(find.text('Plaka zorunludur.'), findsOneWidget);
      expect(find.text('Şoför seçin.'), findsOneWidget);
      expect(
        find.text('Sevkiyat planla'),
        findsOneWidget,
        reason: 'gönderilmedi',
      );

      await tester.enterText(litres, '6000');
      await tester.enterText(
        _inSheet(find.byType(TextField)).at(1),
        '34abc123',
      );
      await BayiTestApp.settle(tester);
      expect(find.byType(PlateBadge), findsWidgets, reason: 'plaka önizlemesi');

      await scrollTap(tester, find.bySemanticsLabel('Şoför seçin'));
      expect(
        find.text('Şoför seçin'),
        findsOneWidget,
        reason: 'şoför seçici açıldı',
      );
      final ahmet = _driverCard('Ahmet Kurt');
      expect(
        find.descendant(of: ahmet, matching: find.text('uygulamada')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: ahmet,
          matching: find.textContaining('0532 000 02 09'),
        ),
        findsOneWidget,
      );
      final mustafa = _driverCard('Mustafa Er');
      expect(
        find.descendant(of: mustafa, matching: find.text('uygulamada')),
        findsNothing,
      );
      expect(
        find.descendant(of: mustafa, matching: find.text('Şoför')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _driverCard('Ayşe Kaya'),
          matching: find.text('Personel'),
        ),
        findsOneWidget,
      );
      expect(
        find.text('Bu adla devam et'),
        findsOneWidget,
        reason: 'planlamada hesapsız şoför',
      );
      await scrollTap(tester, _driverCard('Serdar Çınar'));
      expect(
        find.bySemanticsLabel('Şoför: Serdar Çınar, değiştir'),
        findsOneWidget,
      );

      await scrollTap(tester, find.text('Sevkiyatı planla'));
      expect(
        find.text('Sevkiyat planla'),
        findsNothing,
        reason: 'planlandı, sayfa kapandı',
      );
      final after = _board(app);
      final order = after.orders.where((o) => o.orderId == target.orderId);
      expect(order.single.remainingLiters, target.remainingLiters - 6000);
      final planned = after.shipments.where(
        (s) =>
            s.orderId == target.orderId && s.status == ShipmentStatus.planned,
      );
      expect(planned.single.driverName, 'Serdar Çınar');
      expect(planned.single.isAppDriver, isTrue);
      expect(planned.single.vehiclePlate, '34 ABC 123');
      expect(tester.takeException(), isNull);
      await app.finish(tester);
    },
  );

  testWidgets(
    'uygulama şoförü: her işlemden önce onay; Yola çıkar → Teslim bildir',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'sevkiyat',
        location: '/dispatch',
      );
      final ship = _board(app).shipments.firstWhere(
        (s) => s.status == ShipmentStatus.planned && s.isAppDriver,
      );
      await scrollTap(tester, _line(ship.id));
      expect(find.text(ship.code), findsWidgets);
      expect(find.text('uygulamada'), findsWidgets);
      expect(find.text('Şoför değiştir'), findsOneWidget);
      expect(find.text('Planı iptal et'), findsOneWidget);

      await scrollTap(tester, find.text('Yola çıkar'));
      expect(
        find.text('${ship.driverName} uygulamayı kullanıyor'),
        findsOneWidget,
      );
      await scrollTap(
        tester,
        find.descendant(
          of: find.byType(ConfirmSheet),
          matching: find.text('Vazgeç'),
        ),
      );
      expect(
        _detail(app, ship.id)!.status,
        ShipmentStatus.planned,
        reason: 'vazgeçildi',
      );

      await scrollTap(tester, find.text('Yola çıkar'));
      await scrollTap(tester, _confirm('Yola çıkar'));
      expect(_detail(app, ship.id)!.status, ShipmentStatus.inTransit);
      expect(find.text('Yola çıkar'), findsNothing);
      expect(_inSheet(find.byType(TruckRoute)), findsOneWidget);

      await scrollTap(tester, find.text('Teslim bildir'));
      await scrollTap(tester, _confirm('Teslim bildir'));
      expect(
        find.text('Teslimi bildir'),
        findsOneWidget,
        reason: 'bildirim sayfası',
      );
      await tester.enterText(_inSheet(find.byType(TextField)).at(1), 'irs-778');
      await BayiTestApp.settle(tester);
      await scrollTap(tester, find.text('Teslimi bildir'));
      expect(find.text('Teslimi bildir'), findsNothing);
      final d = _detail(app, ship.id)!;
      expect(d.status, ShipmentStatus.reported);
      expect(d.deliveryDocumentNo, 'IRS-778');
      expect(d.deliveredLiters, ship.plannedLiters);
      expect(find.text('IRS-778'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await app.finish(tester);
    },
  );

  testWidgets(
    'hesapsız şoför: onay sorulmadan şoför değişir; iptal her zaman onaylı',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'sevkiyat',
        location: '/dispatch',
      );
      final ship = _board(app).shipments.firstWhere(
        (s) => s.status == ShipmentStatus.planned && !s.isAppDriver,
      );
      await scrollTap(tester, _line(ship.id));
      expect(find.text('Atanmamış (uygulamada görünmez)'), findsNothing);

      await scrollTap(tester, find.text('Şoför değiştir'));
      expect(
        find.byType(ConfirmSheet),
        findsNothing,
        reason: 'uygulama şoförü değil',
      );
      expect(find.text('Yeni şoför'), findsOneWidget);
      expect(
        find.text('Bu adla devam et'),
        findsNothing,
        reason: 'atamada yalnızca hesaplar',
      );
      await scrollTap(tester, _driverCard('Serdar Çınar'));
      var d = _detail(app, ship.id)!;
      expect(d.driverUserId, 'u-sofor3');
      expect(d.isAppDriver, isTrue);

      await scrollTap(tester, find.text('Planı iptal et'));
      expect(find.text('Sevkiyat planı iptal edilsin mi?'), findsOneWidget);
      expect(
        find.textContaining('Serdar Çınar uygulamasındaki teslimat da kalkar'),
        findsOneWidget,
      );
      await scrollTap(tester, _confirm('Planı iptal et'));
      d = _detail(app, ship.id)!;
      expect(d.status, ShipmentStatus.cancelled);
      expect(find.text('Planı iptal et'), findsNothing);
      await app.finish(tester);
    },
  );

  testWidgets(
    'itirazlı sevkiyat: itiraz notu, fotoğraflar ve "Teslimatı düzelt"',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'sevkiyat',
        location: '/dispatch',
      );
      await scrollTap(tester, find.text('Sevkiyatlar'));
      await scrollTap(tester, find.widgetWithText(AknChip, 'İtirazlı'));
      final items = app.container.read(shipmentListProvider).list.items;
      expect(items, isNotEmpty);
      expect(items.every((s) => s.status == ShipmentStatus.disputed), isTrue);
      await scrollTap(tester, find.byType(ShipmentListCard).first);
      expect(find.text('Carinin itirazı'), findsOneWidget);
      expect(find.text('İtiraz fotoğrafları'), findsOneWidget);
      expect(find.text('Teslimatı düzelt'), findsOneWidget);
      expect(find.text('Yola çıkar'), findsNothing);
      await app.finish(tester);
    },
  );

  testWidgets(
    'depo: liste "Bugünkü yüklemeler" ile açılır; Planla yok, Yola çıkar var',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'depo',
        location: '/dispatch',
      );
      final chip = tester.widget<AknChip>(
        find.widgetWithText(AknChip, 'Bugünkü yüklemeler'),
      );
      expect(chip.selected, isTrue);
      final list = app.container.read(shipmentListProvider);
      expect(list.filter.todayLoadings, isTrue);
      expect(list.list.items, isNotEmpty);
      final today = TrTime.todayStart();
      for (final s in list.list.items) {
        expect(
          s.status,
          anyOf(ShipmentStatus.planned, ShipmentStatus.inTransit),
        );
        expect(TrTime.startOfDay(s.scheduledAt!), today);
      }
      expect(find.textContaining('yükleme sırasıyla'), findsOneWidget);

      await scrollTap(tester, find.text('Pano'));
      expect(find.textContaining('Planlanacak siparişler'), findsOneWidget);
      expect(find.text('Planla'), findsNothing);
      expect(find.textContaining('Planlama yetkiniz yok'), findsOneWidget);

      final ship = _board(app).shipments.firstWhere(
        (s) => s.status == ShipmentStatus.planned && s.isAppDriver,
      );
      await scrollTap(tester, _line(ship.id));
      expect(find.text('Yola çıkar'), findsOneWidget);
      expect(find.text('Şoför değiştir'), findsNothing);
      expect(find.text('Planı iptal et'), findsNothing);
      await scrollTap(tester, find.text('Yola çıkar'));
      await scrollTap(tester, _confirm('Yola çıkar'));
      expect(_detail(app, ship.id)!.status, ShipmentStatus.inTransit);
      expect(find.text('Teslim bildir'), findsOneWidget);
      await app.finish(tester);
    },
  );

  for (final persona in const ['siparis', 'izleyici']) {
    testWidgets('$persona: pano ve ayrıntı salt okunur', (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: persona,
        location: '/dispatch',
      );
      expect(find.textContaining('Planlanacak siparişler'), findsOneWidget);
      expect(find.text('Planla'), findsNothing);
      expect(find.textContaining('değişiklik yetkiniz yok'), findsOneWidget);
      final ship = _board(
        app,
      ).shipments.firstWhere((s) => s.status == ShipmentStatus.planned);
      await scrollTap(tester, _line(ship.id));
      expect(find.text(ship.code), findsWidgets);
      for (final label in const [
        'Yola çıkar',
        'Teslim bildir',
        'Şoför değiştir',
        'Planı iptal et',
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
      await app.finish(tester);
    });
  }
}

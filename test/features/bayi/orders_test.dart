// Siparişler (v4 §5 06): "Tümü" + segment çipleri `bayi/orders/counts`tan (sıfır olanlar gizli) ve
// listeyi süzer; `?segment=` derin bağlantısı; Filtre sayfası (durum, cari seçici) ve özet satırı; ayrıntı eylemleri yetkiye göre (spec A.1): sipariş masası
// Teklif ver, sevkiyat Sevkiyat planla, depo / görüntüleyici hiçbiri; teklif → cari kararı ya da finans
// onayı; tüm litre teslim alınınca Tamamla.
import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/bayi/application/orders_controller.dart';
import 'package:akaryakitnet/features/bayi/copy.dart';
import 'package:akaryakitnet/features/bayi/data/order_models.dart';
import 'package:akaryakitnet/features/bayi/fake/seed.dart';
import 'package:akaryakitnet/features/bayi/presentation/orders/orders_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bayi_app.dart';

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(BottomSheet).last, matching: f);

Finder _segChip(String label) => find.descendant(
  of: find.byType(FilterChips<BayiOrderSegment?>),
  matching: find.text(label),
);

Finder _card(int id) =>
    find.byWidgetPredicate((w) => w is BayiOrderCard && w.row.id == id);

BayiOrderRow _row(BayiTestApp app, bool Function(BayiOrderRow r) test) =>
    app.container.read(bayiOrdersProvider).list.items.firstWhere(test);

bool _awaitingK95(BayiOrderRow r) =>
    r.status == OrderStatus.awaitingQuote &&
    r.financeStatus == OrderFinanceStatus.notRequired &&
    r.customerId == 101 &&
    r.quantityLiters == 4000;

bool _awaitingMarmara(BayiOrderRow r) =>
    r.status == OrderStatus.awaitingQuote &&
    r.financeStatus == OrderFinanceStatus.notRequired &&
    r.customerId == 102 &&
    r.quantityLiters == 18000;

bool _toPlan(BayiOrderRow r) =>
    r.status == OrderStatus.approved && r.remainingLiters > 0;

/// Listeden siparişi açar (ayrıntı sayfası).
Future<int> _open(
  WidgetTester tester,
  BayiTestApp app,
  bool Function(BayiOrderRow r) test,
) async {
  final id = _row(app, test).id;
  await scrollTap(tester, _card(id));
  expect(find.byType(BayiOrderCard), findsNothing, reason: 'ayrıntı açıldı');
  return id;
}

/// "Kabul bekleyen" sevkiyatları cari kabul etmiş gibi işaretler (sipariş litresinin tamamı).
void _acceptReported(FakeWorld w) {
  for (final s in w.shipments.where((s) => s['status'] == 2).toList()) {
    final o = w.order(s['orderId'] as int)!;
    s['status'] = 3;
    s['deliveredLiters'] = (o['quantityLiters'] as num).toDouble();
  }
}

void main() {
  testWidgets(
    'segment çipleri sayılardan gelir, sıfır olan gizlidir; çip listeyi süzer',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'sahip',
        location: '/bayi/orders',
        // Çekirdek FilterChips seçim ikonu azaltılmış harekette sıfır süreli AnimatedSize kullanır.
        reduceMotion: false,
      );
      final counts = app.container.read(bayiOrdersProvider).counts!;
      for (final seg in BayiOrderSegment.values) {
        final n = counts.of(seg);
        expect(
          _segChip(seg.label),
          n > 0 ? findsOneWidget : findsNothing,
          reason: seg.label,
        );
        if (n > 0) {
          expect(find.bySemanticsLabel('${seg.label}, $n'), findsOneWidget);
        }
      }
      await scrollTap(tester, _segChip(BayiOrderSegment.toPlan.label));
      final s = app.container.read(bayiOrdersProvider);
      expect(s.filter.segment, BayiOrderSegment.toPlan);
      expect(s.list.totalCount, counts.of(BayiOrderSegment.toPlan));
      expect(s.list.items.every(_toPlan), isTrue);
      expect(find.byType(BayiOrderCard), findsNWidgets(s.list.items.length));

      await scrollTap(tester, _segChip(BayiOrderSegment.awaitingQuote.label));
      final q = app.container.read(bayiOrdersProvider);
      expect(q.filter.segment, BayiOrderSegment.awaitingQuote);
      expect(
        q.list.items.every((r) => r.status == OrderStatus.awaitingQuote),
        isTrue,
      );
      expect(q.list.totalCount, counts.of(BayiOrderSegment.awaitingQuote));
      await app.finish(tester);
    },
  );

  testWidgets('süzgeç sayfası: durum + cari seçici, özet satırı ve temizle', (
    tester,
  ) async {
    final app = await BayiTestApp.start(
      tester,
      persona: 'sahip',
      location: '/bayi/orders',
    );
    await scrollTap(tester, find.bySemanticsLabel('Filtre'));
    await scrollTap(
      tester,
      _inSheet(find.widgetWithText(FilterChip, OrderStatus.approved.label)),
    );
    await scrollTap(tester, _inSheet(find.text('Tüm cariler')));
    expect(find.text('Cari seçin'), findsOneWidget);
    await scrollTap(
      tester,
      _inSheet(find.text('Marmara İnşaat Taahhüt Ltd. Şti.')),
    );
    expect(find.text('Cari seçin'), findsNothing);
    expect(
      _inSheet(find.text('Marmara İnşaat Taahhüt Ltd. Şti.')),
      findsOneWidget,
    );
    await scrollTap(tester, _inSheet(find.text('Uygula')));

    final s = app.container.read(bayiOrdersProvider);
    expect(s.filter.customerId, 102);
    expect(s.filter.statuses, {OrderStatus.approved});
    expect(s.filter.advancedCount, 2);
    expect(s.list.items, isNotEmpty);
    expect(
      s.list.items.every(
        (r) => r.customerId == 102 && r.status == OrderStatus.approved,
      ),
      isTrue,
    );
    expect(find.bySemanticsLabel(RegExp(r'^Filtre, 2 etkin')), findsOneWidget);
    expect(find.textContaining('Onaylandı, Marmara İnşaat'), findsOneWidget);
    await scrollTap(tester, find.text(BayiCopy.clearFilters));
    expect(app.container.read(bayiOrdersProvider).filter.advancedCount, 0);
    await app.finish(tester);
  });

  testWidgets(
    'sipariş masası: teklif bekleyende Teklif ver; onaylıda Sevkiyat planla yok',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'siparis',
        location: '/bayi/orders',
      );
      await _open(tester, app, _awaitingK95);
      expect(find.text('Teklif ver'), findsOneWidget);
      expect(find.text('Sevkiyat planla'), findsNothing);
      expect(find.text('Tamamla'), findsNothing);
      await scrollTap(tester, find.byType(BackButton));
      await _open(tester, app, _toPlan);
      expect(find.text('Teklif ver'), findsNothing);
      expect(
        find.text('Sevkiyat planla'),
        findsNothing,
        reason: 'StationShipments:Ekler yok',
      );
      await app.finish(tester);
    },
  );

  testWidgets('sevkiyat: onaylıda Sevkiyat planla açılır; teklif yok', (
    tester,
  ) async {
    final app = await BayiTestApp.start(
      tester,
      persona: 'sevkiyat',
      location: '/bayi/orders',
    );
    final id = _row(app, _toPlan).id;
    await _open(tester, app, _toPlan);
    expect(find.text('Teklif ver'), findsNothing);
    await scrollTap(tester, find.text('Sevkiyat planla'));
    expect(
      find.text('Sevkiyatı planla'),
      findsOneWidget,
      reason: 'plan sayfası açıldı',
    );
    expect(find.textContaining('SIP-'), findsWidgets);
    expect(id, isPositive);
    await app.finish(tester);
  });

  for (final persona in const ['depo', 'izleyici']) {
    testWidgets('$persona: ayrıntıda hiçbir eylem yok', (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: persona,
        location: '/bayi/orders',
      );
      await _open(tester, app, _toPlan);
      for (final label in const ['Teklif ver', 'Sevkiyat planla', 'Tamamla']) {
        expect(find.text(label), findsNothing, reason: label);
      }
      await app.finish(tester);
    });
  }

  testWidgets(
    'teklif ver: cari kararına gider; limit aşımı finans onayına gider',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'siparis',
        location: '/bayi/orders',
      );
      final marmara = _row(app, _awaitingMarmara).id;
      final id = await _open(tester, app, _awaitingK95);
      await scrollTap(tester, find.text('Teklif ver'));
      expect(find.text('Teklifi gönder'), findsOneWidget);
      await tester.enterText(_inSheet(find.byType(TextField)).first, '44,25');
      await BayiTestApp.settle(tester);
      expect(_inSheet(find.text('Tahmini tutar')), findsOneWidget);
      await scrollTap(tester, find.text('Teklifi gönder'));
      expect(find.text('Teklifi gönder'), findsNothing);
      final o = app.container.read(bayiOrderProvider(id)).data!.order;
      expect(o.status, OrderStatus.awaitingApproval);
      expect(o.currentQuote!.unitPriceTry, 44.25);
      expect(find.text('Birim fiyat'), findsOneWidget);
      expect(
        find.text('Teklif ver'),
        findsNothing,
        reason: 'cari kararı bekleniyor',
      );

      await scrollTap(tester, find.byType(BackButton));
      await scrollTap(tester, _card(marmara));
      await scrollTap(tester, find.text('Teklif ver'));
      await tester.enterText(_inSheet(find.byType(TextField)).first, '41,9');
      await BayiTestApp.settle(tester);
      await scrollTap(tester, find.text('Teklifi gönder'));
      // Sunucu siparişi finansa alıp 400 iş kuralı döner: hata değil, sonuç (uyarı, sayfa kapanır,
      // sipariş ve masa tazelenir).
      expect(
        find.text('Teklifi gönder'),
        findsNothing,
        reason: 'sayfa kapandı',
      );
      expect(
        find.textContaining('kaydedilmedi; sipariş finans onayına gönderildi'),
        findsOneWidget,
      );
      final held = app.container.read(bayiOrderProvider(marmara)).data!.order;
      expect(held.financeStatus.isAwaitingDecision, isTrue);
      expect(held.currentQuote, isNull, reason: 'teklif kaydedilmedi');
      expect(find.text('Teklif ver'), findsNothing);
      await scrollTap(tester, find.text('Onay talebini aç'));
      expect(find.textContaining('stub:/approvals/'), findsOneWidget);
      await app.finish(tester);
    },
  );

  testWidgets('Tamamla: tüm litre teslim alınınca, onaylı', (tester) async {
    final app = await BayiTestApp.start(
      tester,
      persona: 'siparis',
      location: '/bayi/orders',
      setup: (h) => _acceptReported(h.world),
    );
    final id = await _open(
      tester,
      app,
      (r) =>
          r.status == OrderStatus.approved &&
          r.acceptedLiters >= r.quantityLiters,
    );
    await scrollTap(tester, find.text('Tamamla'));
    expect(find.text('Sipariş tamamlansın mı?'), findsOneWidget);
    await scrollTap(
      tester,
      find.descendant(
        of: find.byType(ConfirmSheet),
        matching: find.text('Tamamla'),
      ),
    );
    expect(
      app.container.read(bayiOrderProvider(id)).data!.order.status,
      OrderStatus.completed,
    );
    expect(find.text('Tamamla'), findsNothing);
    await app.finish(tester);
  });

  // Canlı sandbox senaryosu (sipariş 8271): 6.000 L'nin 5.950 L'si kabul edildi, kalan 50 L'lik plan
  // iptal edildi; sipariş "Onaylandı"da kalır ve sunucu teslim toleransı (%1) içinde "Tamamla"ya izin
  // verir (`completionHint`).
  testWidgets(
    'Tamamla: teslim toleransı içinde eksik teslim, kalan plan iptal (sunucunun çağrısı)',
    (tester) async {
      late int id;
      final app = await BayiTestApp.start(
        tester,
        persona: 'siparis',
        location: '/bayi/orders',
        setup: (h) => id = _partialDelivery(h.world, acceptedRatio: 0.995),
      );
      await app.push(tester, '/bayi/orders/$id');
      final b = app.container.read(bayiOrderProvider(id)).data!;
      expect(b.order.status, OrderStatus.approved);
      expect(b.completion, BayiCompletion.withinTolerance);
      expect(find.text('Sipariş henüz tamamlanmadı'), findsOneWidget);
      expect(
        find.textContaining('"Tamamla" ile kapatabilirsiniz'),
        findsOneWidget,
      );
      await scrollTap(tester, find.text('Tamamla'));
      expect(find.text('Sipariş tamamlansın mı?'), findsOneWidget);
      expect(find.textContaining('teslim toleransı içinde'), findsWidgets);
      await scrollTap(
        tester,
        find.descendant(
          of: find.byType(ConfirmSheet),
          matching: find.text('Tamamla'),
        ),
      );
      expect(
        app.container.read(bayiOrderProvider(id)).data!.order.status,
        OrderStatus.completed,
      );
      expect(find.text('Tamamla'), findsNothing);
      expect(find.text('Sipariş henüz tamamlanmadı'), findsNothing);
      await app.finish(tester);
    },
  );

  testWidgets(
    'tolerans dışı eksik teslim: Tamamla yok, sunucunun engeli gösterilir',
    (tester) async {
      late int id;
      final app = await BayiTestApp.start(
        tester,
        persona: 'siparis',
        location: '/bayi/orders',
        setup: (h) => id = _partialDelivery(h.world, acceptedRatio: 0.9),
      );
      await app.push(tester, '/bayi/orders/$id');
      final b = app.container.read(bayiOrderProvider(id)).data!;
      expect(b.completion, isNull);
      expect(find.text('Sipariş henüz tamamlanmadı'), findsOneWidget);
      expect(find.textContaining('teslim toleransını (%1'), findsOneWidget);
      expect(find.text('Tamamla'), findsNothing);
      await app.finish(tester);
    },
  );

  testWidgets('depo: tolerans içinde de Tamamla ve "Tamamla" çağrısı yok', (
    tester,
  ) async {
    late int id;
    final app = await BayiTestApp.start(
      tester,
      persona: 'depo',
      location: '/bayi/orders',
      setup: (h) => id = _partialDelivery(h.world, acceptedRatio: 0.995),
    );
    await app.push(tester, '/bayi/orders/$id');
    expect(
      app.container.read(bayiOrderProvider(id)).data!.completion,
      BayiCompletion.withinTolerance,
      reason: 'sipariş kapatılabilir; yetki yok',
    );
    expect(find.text('Tamamla'), findsNothing);
    expect(find.text('Sipariş henüz tamamlanmadı'), findsNothing);
    await app.finish(tester);
  });

  testWidgets(
    'v4: Tümü önce ve açılış; satırda hap ve sipariş no yok; Tümü\'de akış satırı; ?segment=',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'sahip',
        location: '/bayi/orders',
        size: const Size(390, 844),
      );
      final s = app.container.read(bayiOrdersProvider);
      expect(s.filter.segment, isNull, reason: 'Teklifler alt menüde: Tümü');
      expect(_segChip('Tümü'), findsOneWidget);
      // Çiplerle aynı sayılar; 390 dp'de revize de sığsın diye kısa söz (v4 tur 2 B6).
      expect(
        find.textContaining(
          RegExp(r'teklifinizi bekliyor|teklif · \d+ revize sizi bekliyor'),
          findRichText: true,
        ),
        findsOneWidget,
      );
      final rows = find.byType(BayiOrderCard);
      expect(rows, findsWidgets);
      // P4: hap ve sipariş no yok; Tümü'de » akış satırı.
      expect(
        find.descendant(of: rows, matching: find.byType(AknLamp)),
        findsNothing,
      );
      expect(
        find.descendant(of: rows, matching: find.textContaining('SIP-')),
        findsNothing,
      );
      expect(
        find.descendant(of: rows, matching: find.byType(AknFlowPips)),
        findsWidgets,
      );
      // Ekranda en az 6 satır başlar (alt çubuk 746'da).
      var visible = 0;
      for (var i = 0; i < rows.evaluate().length; i++) {
        if (tester.getRect(rows.at(i)).top < 746) visible++;
      }
      expect(visible, greaterThanOrEqualTo(6));
      // Bir segmentte akış satırı yok (çip durumu zaten söylüyor).
      await scrollTap(tester, _segChip(BayiOrderSegment.awaitingQuote.label));
      expect(
        find.descendant(
          of: find.byType(BayiOrderCard),
          matching: find.byType(AknFlowPips),
        ),
        findsNothing,
      );
      // Derin bağlantı: ?segment=awaitingCustomer.
      await app.push(tester, '/bayi/orders?segment=awaitingCustomer');
      expect(
        app.container.read(bayiOrdersProvider).filter.segment,
        BayiOrderSegment.awaitingCustomer,
      );
      expect(_segChip('Müşteri kararında'), findsWidgets);
      await app.finish(tester);
    },
  );

  testWidgets(
    'v4 ayrıntı: "Sipariş" başlığı, müşteri üst satırı, » 4 durak, tek "Teklif ver"',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'sahip',
        location: '/bayi/orders',
        size: const Size(390, 844),
      );
      await _open(tester, app, _awaitingK95);
      expect(find.text('Sipariş'), findsWidgets);
      expect(find.byType(AknObjectHeader), findsOneWidget);
      final line = tester.widget<AknFlowLine>(find.byType(AknFlowLine));
      expect(line.flow.stops, AknFlow.bayiStops);
      expect(line.flow.current, 0);
      expect(find.textContaining('Aşama'), findsNothing);
      // "Teklif ver(in)" en çok iki kez: StageNow + alt çubuk.
      expect(find.text('Teklif verin'), findsOneWidget);
      expect(find.text('Teklif ver'), findsOneWidget);
      // Teklif yokken 46 dp tahmini tutar plakası yok: tahmin bir olgu satırı.
      expect(find.byType(AknPlate), findsNothing);
      expect(find.text('Liste fiyatıyla tahmin'), findsOneWidget);
      await app.finish(tester);
    },
  );
}

/// Bayi 1'in teklifli, onaylı ilk siparişinin sevkiyatlarını değiştirir: sipariş litresinin
/// [acceptedRatio] kadarı kabul edilmiş tek sevkiyat ve kalanın iptal edilmiş planı. Sipariş kimliği.
int _partialDelivery(FakeWorld w, {required double acceptedRatio}) {
  ensureBayiSeed(w);
  final o = w
      .ordersOfStation(1)
      .firstWhere((o) => o['status'] == 3 && (o['quotes'] as List).isNotEmpty);
  final id = o['id'] as int;
  w.shipments.removeWhere((s) => s['orderId'] == id);
  final qty = (o['quantityLiters'] as num).toDouble();
  final accepted = (qty * acceptedRatio).roundToDouble();
  w.shipments.addAll([
    w.newShipment(
      id: 77001,
      orderId: id,
      plannedLiters: accepted,
      status: 3,
      scheduledAt: DateTime.now().subtract(const Duration(hours: 6)),
      deliveredLiters: accepted,
      deliveryDocumentNo: 'IRS-TOL-1',
    ),
    w.newShipment(
      id: 77002,
      orderId: id,
      plannedLiters: qty - accepted,
      status: 5,
      scheduledAt: DateTime.now().add(const Duration(hours: 20)),
    ),
  ]);
  return id;
}

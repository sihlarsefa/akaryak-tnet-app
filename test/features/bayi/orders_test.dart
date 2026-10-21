// Siparişler: segment çipleri `bayi/orders/counts`tan (sıfır olanlar gizli) ve listeyi süzer; süzgeç
// sayfası (durum, cari seçici) ve özet satırı; ayrıntı eylemleri yetkiye göre (spec A.1): sipariş masası
// Teklif ver, sevkiyat Sevkiyat planla, depo / görüntüleyici hiçbiri; teklif → cari kararı ya da finans
// onayı; tüm litre teslim alınınca Tamamla.
import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/bayi/application/orders_controller.dart';
import 'package:akaryakitnet/features/bayi/copy.dart';
import 'package:akaryakitnet/features/bayi/data/order_models.dart';
import 'package:akaryakitnet/features/bayi/presentation/orders/orders_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bayi_app.dart';

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(BottomSheet).last, matching: f);

Finder _segChip(String label) => find.descendant(
  of: find.byType(FilterChips<BayiOrderSegment>),
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
    await scrollTap(tester, find.bySemanticsLabel('Süzgeçler'));
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
    expect(find.bySemanticsLabel('Süzgeçler, 2 süzgeç açık'), findsOneWidget);
    expect(find.textContaining('Onaylandı · Marmara İnşaat'), findsOneWidget);
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
}

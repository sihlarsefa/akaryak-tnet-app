// Siparişi "Tamamla" ile kapatma (sunucu `OrderCompletionRules`, `orders/{id}/complete`) ve
// `shipments/order/{id}` → `completionHint`: canlı sandbox yanıtlarıyla (test/contract/fixtures) uygulama
// kuralı ve sahte sunucunun aynı metinleri.
//
// - 8271: 6.000 L'nin 5.950 L'si kabul edildi, kalan 50 L planı iptal → tolerans (%1) içinde, sunucu
//   "Tamamla"ya çağırır ve tamamlamayı kabul eder.
// - 8284: 5.400 / 6.000 L, kalan 600 L planı iptal → tolerans dışı; bayiye engel, müşteriye kalan
//   litrenin bayinin yeni sevkiyatıyla geleceği; `orders/8284/complete` 400 aynı gerekçeyle.
import 'dart:convert';
import 'dart:io';

import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/network/fake/fake_completion.dart';
import 'package:akaryakitnet/features/bayi/data/order_models.dart';
import 'package:akaryakitnet/features/customer_orders/application/order_view_controller.dart';
import 'package:akaryakitnet/features/customer_orders/data/order_models.dart';
import 'package:flutter_test/flutter_test.dart';

Object? _fixture(String name) =>
    jsonDecode(File('test/contract/fixtures/$name.json').readAsStringSync());

OrderDetail _order({
  OrderStatus status = OrderStatus.approved,
  double liters = 6000,
  bool quoted = true,
}) => OrderDetail(
  id: 1,
  orderNumber: 'SIP-1',
  status: status,
  quantityLiters: liters,
  customerId: 1,
  stationId: 1,
  productId: 1,
  deliveryPointId: 1,
  quotes: [
    if (quoted)
      const Quote(
        id: 1,
        version: 1,
        unitPriceTry: 41.4,
        totalAmountTry: 248400,
        isSelected: true,
      ),
  ],
);

Shipment _ship(int id, ShipmentStatus status, double planned, [double? got]) =>
    Shipment(
      id: id,
      plannedLiters: planned,
      deliveredLiters: got,
      status: status,
    );

Fulfillment _fulfillment(
  List<Shipment> shipments, {
  double ordered = 6000,
  bool canManage = true,
  String? hint,
}) => Fulfillment(
  orderId: 1,
  orderNumber: 'SIP-1',
  orderedLiters: ordered,
  acceptedLiters: shipments
      .where((s) => s.status == ShipmentStatus.accepted)
      .fold<double>(0, (sum, s) => sum + (s.deliveredLiters ?? 0)),
  canManage: canManage,
  isOpen: true,
  completionHint: hint,
  shipments: shipments,
);

void main() {
  group('canlı: tolerans içinde eksik teslim (8271)', () {
    final order = OrderDetail.fromJson(
      _fixture('order-detail.bayi.within-tolerance'),
    );

    test('bayi: sunucu "Tamamla"ya çağırır; uygulama düğmeyi gösterir', () {
      final f = Fulfillment.fromJson(_fixture('fulfillment.within-tolerance'));
      expect(order.status, OrderStatus.approved);
      expect(f.canManage, isTrue);
      expect(f.hasOpenShipments, isFalse);
      expect(f.completionHint, FakeCompletion.invitation);
      expect(f.invitesCompletion, isTrue);
      final b = BayiOrderBundle(order: order, fulfillment: f);
      expect(b.completion, BayiCompletion.withinTolerance);
      expect(b.remainingLiters, 50, reason: 'kalan 50 L yine planlanabilir');
    });

    test('müşteri: tolerans içinde not ve çağrı yok', () {
      final f = Fulfillment.fromJson(
        _fixture('fulfillment.within-tolerance.customer'),
      );
      expect(f.canManage, isFalse);
      expect(f.completionHint, isNull);
      expect(f.invitesCompletion, isFalse);
    });
  });

  group('canlı: tolerans dışı eksik teslim (8284)', () {
    final order = OrderDetail.fromJson(
      _fixture('order-detail.bayi.short-delivery'),
    );

    test(
      'bayi: engel gösterilir, Tamamla yok; sahte sunucu aynı metni üretir',
      () {
        final f = Fulfillment.fromJson(_fixture('fulfillment.short-delivery'));
        expect(
          f.completionHint,
          contains('teslim toleransını (%1; en az 5.940 L) aşıyor'),
        );
        expect(f.invitesCompletion, isFalse);
        expect(
          BayiOrderBundle(order: order, fulfillment: f).completion,
          isNull,
        );
        final shipments = [
          for (final s in f.shipments)
            {
              'status': s.status.code,
              'plannedLiters': s.plannedLiters,
              'deliveredLiters': s.deliveredLiters,
            },
        ];
        expect(
          FakeCompletion.hint(
            status: 3,
            hasAcceptedQuote: true,
            ordered: f.orderedLiters,
            shipments: shipments,
            canManage: true,
          ),
          f.completionHint,
        );
        // `orders/8284/complete` → 400 aynı gerekçe.
        final problem =
            (_fixture('problem.complete-short-delivery')! as Map)['detail'];
        expect(
          FakeCompletion.blockReason(
            status: 3,
            hasAcceptedQuote: true,
            ordered: f.orderedLiters,
            shipments: shipments,
          ),
          problem,
        );
      },
    );

    test('müşteri: takip notu ister; not sahte sunucuyla aynı', () {
      final tracking = OrderTracking.fromJson(
        _fixture('order-tracking.short-delivery'),
      );
      expect(
        OrderView.needsCompletionHint(
          OrderDetail.fromJson(_fixture('order-detail.bayi.short-delivery')),
          tracking,
        ),
        isTrue,
      );
      final f = Fulfillment.fromJson(
        _fixture('fulfillment.short-delivery.customer'),
      );
      expect(f.canManage, isFalse);
      expect(f.invitesCompletion, isFalse);
      expect(
        f.completionHint,
        FakeCompletion.hint(
          status: 3,
          hasAcceptedQuote: true,
          ordered: 6000,
          shipments: [
            {'status': 3, 'plannedLiters': 5400, 'deliveredLiters': 5400},
            {'status': 5, 'plannedLiters': 600},
          ],
          canManage: false,
        ),
      );
    });
  });

  group('kural (sunucu OrderCompletionRules)', () {
    test('tüm litre teslim alındı', () {
      final b = BayiOrderBundle(
        order: _order(),
        fulfillment: _fulfillment([
          _ship(1, ShipmentStatus.accepted, 6000, 6000),
        ]),
      );
      expect(b.completion, BayiCompletion.fullyAccepted);
    });

    test('açık sevkiyat varken tolerans içi kabul tamamlatmaz', () {
      final b = BayiOrderBundle(
        order: _order(),
        fulfillment: _fulfillment(
          [
            _ship(1, ShipmentStatus.accepted, 5950, 5950),
            _ship(2, ShipmentStatus.planned, 50),
          ],
          // Sunucu açık sevkiyatta not göndermez; uygulama yine de çağrıya güvenmez.
          hint: FakeCompletion.invitation,
        ),
      );
      expect(b.fulfillment!.hasOpenShipments, isTrue);
      expect(b.completion, isNull);
    });

    test('müşteriye giden not "Tamamla" çağrısı sayılmaz', () {
      final f = _fulfillment(
        [
          _ship(1, ShipmentStatus.accepted, 5950, 5950),
          _ship(2, ShipmentStatus.cancelled, 50),
        ],
        canManage: false,
        hint: FakeCompletion.invitation,
      );
      expect(f.invitesCompletion, isFalse);
    });

    test(
      'sevkiyatsız eski sipariş: teklifsizse tamamlanır, teklifliyse web',
      () {
        expect(
          BayiOrderBundle(
            order: _order(quoted: false),
            fulfillment: _fulfillment(const []),
          ).completion,
          BayiCompletion.noShipments,
        );
        expect(
          BayiOrderBundle(
            order: _order(),
            fulfillment: _fulfillment(const []),
          ).completion,
          isNull,
        );
      },
    );

    test('onaylı olmayan ya da teslimat özeti yüklenemeyen sipariş', () {
      expect(
        BayiOrderBundle(
          order: _order(status: OrderStatus.completed),
          fulfillment: _fulfillment([
            _ship(1, ShipmentStatus.accepted, 6000, 6000),
          ]),
        ).completion,
        isNull,
      );
      expect(BayiOrderBundle(order: _order()).completion, isNull);
    });

    test(
      'sahte sunucu: kabulle kendiliğinden tamamlanma ve elle tamamlama',
      () {
        JsonMap s(int status, double planned, [double? got]) => {
          'status': status,
          'plannedLiters': planned,
          'deliveredLiters': got,
        };
        // Tolerans içinde ve açık sevkiyat yok → tamamlanmış sayılır.
        expect(
          FakeCompletion.isFulfilled(6000, [s(3, 5950, 5950), s(5, 50)]),
          isTrue,
        );
        // Kalan plan açıkken → sayılmaz.
        expect(
          FakeCompletion.isFulfilled(6000, [s(3, 5950, 5950), s(0, 50)]),
          isFalse,
        );
        // %1 sınırı: 5.940 L tamam, 5.939 L değil.
        expect(FakeCompletion.isFulfilled(6000, [s(3, 5940, 5940)]), isTrue);
        expect(FakeCompletion.isFulfilled(6000, [s(3, 5939, 5939)]), isFalse);
        expect(
          FakeCompletion.blockReason(
            status: 3,
            hasAcceptedQuote: true,
            ordered: 6000,
            shipments: [s(3, 5950, 5950), s(0, 50)],
          ),
          FakeCompletion.openShipments,
        );
        expect(
          FakeCompletion.blockReason(
            status: 3,
            hasAcceptedQuote: false,
            ordered: 6000,
            shipments: const [],
          ),
          isNull,
        );
        expect(
          FakeCompletion.blockReason(
            status: 2,
            hasAcceptedQuote: true,
            ordered: 6000,
            shipments: const [],
          ),
          FakeCompletion.notApproved,
        );
      },
    );
  });
}

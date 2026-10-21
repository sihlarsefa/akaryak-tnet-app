import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/offline/outbox_op.dart';
import 'package:akaryakitnet/features/driver/application/driver_ops.dart';
import 'package:akaryakitnet/features/driver/application/route_plan.dart';
import 'package:akaryakitnet/features/driver/data/driver_models.dart';
import 'package:akaryakitnet/features/driver/data/driver_outbox.dart';
import 'package:flutter_test/flutter_test.dart';

DriverShipmentRow _row(
  int id,
  ShipmentStatus status, {
  required int hour,
  double liters = 10000,
}) => DriverShipmentRow(
  id: id,
  code: DriverShipmentRow.shipmentCode(id),
  orderId: id,
  orderNumber: 'SIP-$id',
  status: status,
  plannedLiters: liters,
  scheduledAt: DateTime.utc(2026, 10, 21, hour - 3),
);

OutboxOp _deliverOp(int shipmentId, OutboxStatus status) => OutboxOp(
  id: 'op-$shipmentId',
  userId: 'u-sofor',
  type: DriverOutbox.deliver,
  payload: {'shipmentId': shipmentId},
  idempotencyKey: 'k-$shipmentId',
  status: status,
  createdAt: DateTime.utc(2026, 10, 21, 8),
  updatedAt: DateTime.utc(2026, 10, 21, 8),
);

void main() {
  final now = DateTime.utc(2026, 10, 21, 7); // 10:00 TR

  group('DriverRoutePlan (§7.11 sıra ve yük)', () {
    test('yoldaki durak sıradaki; numara güzergâh sırası; yük açık duraklar', () {
      final plan = DriverRoutePlan.of([
        _row(3, ShipmentStatus.planned, hour: 15, liters: 6000),
        _row(1, ShipmentStatus.accepted, hour: 8, liters: 5000),
        _row(2, ShipmentStatus.inTransit, hour: 11, liters: 10000),
        _row(4, ShipmentStatus.planned, hour: 13, liters: 8000),
        _row(9, ShipmentStatus.disputed, hour: 9, liters: 7000),
      ], now);
      expect(plan.next?.id, 2);
      // Yoldaki önce, sonra plan saati: 2 (yolda), 1 (08:00), 4 (13:00), 3 (15:00).
      expect(plan.stops.map((s) => s.row.id), [2, 1, 4, 3]);
      expect(plan.nextNumber, 1);
      expect(plan.total, 4);
      expect(plan.upcoming.map((s) => s.row.id), [4, 3]);
      expect(plan.done.map((s) => s.row.id), [1]);
      // İtirazlı (düzeltme) ve tamamlanan tanka sayılmaz.
      expect(plan.remainingLiters, 24000);
    });

    test(
      'teslimi telefonda bekleyen durak tamamlanmış sayılır, sıradaki kayar',
      () {
        final rows = [
          _row(2, ShipmentStatus.inTransit, hour: 11, liters: 10000),
          _row(4, ShipmentStatus.planned, hour: 13, liters: 8000),
        ];
        final ops = groupDriverOps([_deliverOp(2, OutboxStatus.pending)]);
        final plan = DriverRoutePlan.of(rows, now, ops: ops);
        expect(plan.next?.id, 4);
        expect(plan.nextNumber, 2);
        expect(
          plan.stops.firstWhere((s) => s.row.id == 2).state,
          StopState.done,
        );
        expect(plan.remainingLiters, 8000);
      },
    );

    test('boş gün: sıradaki yok', () {
      final plan = DriverRoutePlan.of(const [], now);
      expect(plan.next, isNull);
      expect(plan.nextNumber, isNull);
      expect(plan.remainingLiters, 0);
    });
  });

  group('DriverProximity (birincil iş tırı izler)', () {
    const lat = 40.9119;
    const lng = 29.3014;
    DriverPosition at(double la, double ln, {double accuracy = 8}) =>
        DriverPosition(
          latitude: la,
          longitude: ln,
          accuracyMeters: accuracy,
          capturedAt: DateTime.now().toUtc(),
        );

    test('kuş uçuşu uzaklık (haversine)', () {
      // Pendik Lojistik Merkezi → Ataşehir ~17 km.
      final d = distanceMeters(lat, lng, 40.9923, 29.1244);
      expect(d, inInclusiveRange(16500, 18500));
      expect(distanceMeters(lat, lng, lat, lng), 0);
    });

    test('300 m içinde "Teslim et", uzakta "Yol tarifi"', () {
      bool primary(
        DriverPosition? p, {
        bool unavailable = false,
        Duration unknown = Duration.zero,
      }) => DriverProximity.deliverIsPrimary(
        position: p,
        lat: lat,
        lng: lng,
        unavailable: unavailable,
        unknownFor: unknown,
      );
      expect(primary(at(40.9120, 29.3016)), isTrue, reason: 'noktada');
      expect(primary(at(40.9923, 29.1244)), isFalse, reason: '17 km');
      // Konum alınamayacak (izin yok): hemen "Teslim et".
      expect(primary(null, unavailable: true), isTrue);
      // Konum bekleniyor: 30 sn dolana kadar "Yol tarifi", sonra "Teslim et".
      expect(primary(null, unknown: const Duration(seconds: 10)), isFalse);
      expect(primary(null, unknown: const Duration(seconds: 30)), isTrue);
      // 100 m'den kötü hassasiyet bilinmiyor sayılır.
      expect(
        primary(
          at(40.9923, 29.1244, accuracy: 400),
          unknown: const Duration(seconds: 31),
        ),
        isTrue,
      );
      // Nokta koordinatı yoksa "Teslim et" (yol tarifi adresle yine açılır).
      expect(
        DriverProximity.deliverIsPrimary(
          position: at(40.9923, 29.1244),
          lat: null,
          lng: null,
          unavailable: false,
          unknownFor: Duration.zero,
        ),
        isTrue,
      );
    });
  });
}

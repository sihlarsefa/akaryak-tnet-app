import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:akaryakitnet/features/driver/data/driver_models.dart';
import 'package:akaryakitnet/features/driver/data/driver_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DriverShipmentRow / DriverShipmentDetail (sözleşme anahtarları)', () {
    final json = <String, dynamic>{
      'id': 5002,
      'code': 'SVK-00005002',
      'orderId': 12007,
      'orderNumber': 'SIP-20261021-12007',
      'status': 1,
      'statusLabel': 'Yolda',
      'customerTitle': 'Marmara İnşaat',
      'productName': 'Motorin',
      'plannedLiters': 8000,
      'deliveredLiters': null,
      'scheduledAt': '2026-10-21T14:00:00+03:00',
      'deliveryPointName': 'İzmit Şantiye',
      'city': 'Kocaeli',
      'district': 'İzmit',
      'hasCoordinates': true,
      'vehiclePlate': '41 DMR 102',
      'windowStart': '08:00',
      'windowEnd': '17:00:00',
      'disputeNote': null,
      'address': 'Kozluk Mah. Şehit Cad. No:21',
      'latitude': 40.7654,
      'longitude': 29.9408,
      'contactName': 'Serkan Polat',
      'contactPhone': '5343334455',
      'accessNotes': 'Baret zorunlu',
      'tankCapacityLiters': 40000,
      'deliveryDocumentNo': null,
      'recipientName': null,
      'deliveryNote': null,
      'signatureWaiverLabel': null,
      'dispatchedAt': '2026-10-21T09:20:00+03:00',
      'deliveredAt': null,
      'attachments': [
        {
          'publicId': '00000000-0000-4000-8000-000000000001',
          'ownerType': 10,
          'ownerId': 5002,
          'kind': 30,
          'kindLabel': 'Teslimat fotoğrafı',
          'fileName': 'teslimat-1.jpg',
          'contentType': 'image/jpeg',
          'isActive': true,
          'createdAt': '2026-10-21T08:00:00+00:00',
        },
        {
          'publicId': '00000000-0000-4000-8000-000000000002',
          'ownerType': 10,
          'ownerId': 5002,
          'kind': 31,
          'fileName': 'imza.png',
          'contentType': 'image/png',
          'isActive': true,
        },
      ],
      'requirements': {'photo': true, 'signature': true, 'gps': false},
      'actions': {'canStart': false, 'canDeliver': true},
    };

    test('ayrıntı tüm alanlarıyla okunur', () {
      final d = DriverShipmentDetail.fromJson(json);
      expect(d.id, 5002);
      expect(d.code, 'SVK-00005002');
      expect(d.status, ShipmentStatus.inTransit);
      expect(d.row.statusLabel, 'Yolda');
      expect(d.row.plannedLiters, 8000);
      expect(d.row.scheduledAt, DateTime.utc(2026, 10, 21, 11));
      expect(d.row.windowLabel, '08:00–17:00');
      expect(d.row.placeLine, 'İzmit / Kocaeli');
      expect(d.hasCoordinates, isTrue);
      expect(d.tankCapacityLiters, 40000);
      expect(d.dispatchedAt, DateTime.utc(2026, 10, 21, 6, 20));
      expect(d.deliveryPhotos.single.kind, AttachmentKind.deliveryPhoto);
      expect(d.signature?.kind, AttachmentKind.deliverySignature);
      expect(d.requirements.photo, isTrue);
      expect(d.requirements.signature, isTrue);
      expect(d.requirements.gps, isFalse);
      expect(d.actions.canDeliver, isTrue);
      expect(d.actions.canStart, isFalse);
      expect(d.fullAddress, 'Kozluk Mah. Şehit Cad. No:21, İzmit / Kocaeli');
    });

    test('eksik / bilinmeyen alanlar güvenli varsayılana düşer', () {
      final d = DriverShipmentDetail.fromJson({'id': 7, 'status': 42});
      expect(d.code, 'SVK-00000007');
      expect(d.status, ShipmentStatus.unknown);
      expect(d.requirements.photo, isFalse);
      expect(d.actions.canStart, isFalse);
      expect(d.attachments, isEmpty);
      expect(d.row.windowLabel, isNull);
    });

    test('pencere tek uçlu ve 24:00 (TimeSpan 1.00:00:00)', () {
      final a = DriverShipmentRow.fromJson(
        JsonReader({'id': 1, 'windowStart': '6:30'}),
      );
      expect(a.windowLabel, 'En erken 06:30');
      final b = DriverShipmentRow.fromJson(
        JsonReader({'id': 1, 'windowEnd': '1.00:00:00'}),
      );
      expect(b.windowLabel, 'En geç 24:00');
    });

    test('gecikmiş: plan günü geçti ve hâlâ planlı', () {
      final now = DateTime.utc(2026, 10, 21, 9);
      final late = DriverShipmentRow.fromJson(
        JsonReader({
          'id': 1,
          'status': 0,
          'scheduledAt': '2026-10-20T14:00:00+03:00',
        }),
      );
      final today = DriverShipmentRow.fromJson(
        JsonReader({
          'id': 2,
          'status': 0,
          'scheduledAt': '2026-10-21T08:00:00+03:00',
        }),
      );
      expect(late.isOverdue(now), isTrue);
      expect(today.isOverdue(now), isFalse);
    });
  });

  group('Bugün sırası', () {
    test('itirazlı → yolda → gecikmiş → plan (saat) → tamamlanan', () {
      final now = DateTime.utc(2026, 10, 21, 9);
      DriverShipmentRow r(int id, int status, String at) =>
          DriverShipmentRow.fromJson(
            JsonReader({'id': id, 'status': status, 'scheduledAt': at}),
          );
      final rows = [
        r(1, 2, '2026-10-21T08:00:00+03:00'),
        r(2, 0, '2026-10-21T15:00:00+03:00'),
        r(3, 1, '2026-10-21T10:00:00+03:00'),
        r(4, 0, '2026-10-20T10:00:00+03:00'),
        r(5, 4, '2026-10-19T10:00:00+03:00'),
        r(6, 0, '2026-10-21T09:30:00+03:00'),
      ];
      final sorted = DriverRepository.sortToday(rows, now);
      expect([for (final s in sorted) s.id], [5, 3, 4, 6, 2, 1]);
    });
  });

  group('SignatureWaiver', () {
    test('Diğer için en az 3 karakter açıklama gerekir', () {
      expect(
        const SignatureWaiver(SignatureWaiverReason.other).validate(),
        isNotNull,
      );
      expect(
        const SignatureWaiver(SignatureWaiverReason.other, 'ab').validate(),
        isNotNull,
      );
      expect(
        const SignatureWaiver(SignatureWaiverReason.other, 'acil').validate(),
        isNull,
      );
      expect(
        const SignatureWaiver(SignatureWaiverReason.refused).validate(),
        isNull,
      );
    });

    test('istek gövdesi ve metin', () {
      const w = SignatureWaiver(SignatureWaiverReason.noRecipient, ' tanka ');
      expect(w.toJson(), {'reason': 1, 'note': 'tanka'});
      expect(w.text, 'Alıcı yok / tanka teslim – tanka');
      expect(const SignatureWaiver(SignatureWaiverReason.refused).toJson(), {
        'reason': 2,
      });
      expect(SignatureWaiverReason.fromCode(3), SignatureWaiverReason.other);
      expect(SignatureWaiverReason.fromCode(9), isNull);
    });
  });

  group('DriverPosition', () {
    test('sunucu hassasiyetine yuvarlanır; düşük hassasiyet uyarısı', () {
      final p = DriverPosition(
        latitude: 40.91191234,
        longitude: 29.30141789,
        accuracyMeters: 12.3456,
        capturedAt: DateTime.utc(2026, 10, 21, 9),
      );
      expect(p.toRequest(), {
        'latitude': 40.911912,
        'longitude': 29.301418,
        'accuracyMeters': 12.35,
      });
      expect(p.isLowAccuracy, isFalse);
      expect(p.accuracyLabel, '±12 m');
      final far = DriverPosition(
        latitude: 1,
        longitude: 1,
        accuracyMeters: 120,
        capturedAt: TrTime.now(),
      );
      expect(far.isLowAccuracy, isTrue);
      expect(far.isFresh(TrTime.now()), isTrue);
    });
  });
}

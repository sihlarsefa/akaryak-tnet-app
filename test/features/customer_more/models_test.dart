import 'package:akaryakitnet/core/models/enums.dart';
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:akaryakitnet/features/customer_more/data/company.dart';
import 'package:akaryakitnet/features/customer_more/data/customer_more_repository.dart';
import 'package:akaryakitnet/features/customer_more/data/delivery_point.dart';
import 'package:akaryakitnet/features/customer_more/data/documents.dart';
import 'package:akaryakitnet/features/customer_more/data/finance_info.dart';
import 'package:akaryakitnet/features/customer_more/data/spending.dart';
import 'package:akaryakitnet/features/customer_more/data/turkey_locations.dart';
import 'package:akaryakitnet/features/customer_more/data/window_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WindowTime (.NET TimeSpan JSON)', () {
    test('HH:mm:ss, HH:mm ve kesirli saniye okunur', () {
      expect(WindowTime.tryParse('08:00:00')!.label, '08:00');
      expect(WindowTime.tryParse('7:30')!.label, '07:30');
      expect(WindowTime.tryParse('16:45:00.0000000')!.label, '16:45');
      expect(WindowTime.tryParse(null), isNull);
      expect(WindowTime.tryParse(''), isNull);
      expect(WindowTime.tryParse('25:00:00'), isNull);
      expect(WindowTime.tryParse('08:61:00'), isNull);
    });

    test('24:00 = "1.00:00:00"; sunucunun 23:59:59 karşılığı gün sonu', () {
      final end = WindowTime.tryParse('1.00:00:00')!;
      expect(end.isEndOfDay, isTrue);
      expect(end.label, '24:00');
      expect(end.toJson(), '1.00:00:00');
      expect(WindowTime.tryParse('23:59:59')!.isEndOfDay, isTrue);
      expect(WindowTime.tryParse('24:00')!.isEndOfDay, isTrue);
      expect(WindowTime.tryParse('23:59:00')!.isEndOfDay, isFalse);
      expect(WindowTime.tryParse('2.00:00:00'), isNull);
      expect(const WindowTime(8 * 60).toJson(), '08:00:00');
      expect(WindowTime.hm(7, 5).toJson(), '07:05:00');
    });

    test('pencere etiketi', () {
      expect(
        windowLabel(const WindowTime(480), const WindowTime(1080)),
        '08:00–18:00',
      );
      expect(
        windowLabel(WindowTime.startOfDay, WindowTime.endOfDay),
        'Gün boyu (00:00–24:00)',
      );
      expect(windowLabel(null, WindowTime.endOfDay), isNull);
    });
  });

  group('Teslimat noktası', () {
    test('DTO okunur; kayıt isteği sunucu biçiminde', () {
      final p = DeliveryPoint.fromJson(
        JsonReader({
          'id': 7,
          'customerId': 101,
          'name': 'Tuzla Şantiye',
          'city': 'İstanbul',
          'district': 'Tuzla',
          'address': 'Aydınlı Mah.',
          'isActive': true,
          'latitude': 40.8355,
          'longitude': 29.329,
          'contactName': 'Kemal Uçar',
          'contactPhone': '5332223344',
          'deliveryWindowStart': '07:30:00',
          'deliveryWindowEnd': '23:59:59',
          'tankCapacityLiters': 15000,
          'accessNotes': 'Baret zorunlu.',
        }),
      );
      expect(p.window, '07:30–24:00');
      expect(p.cityDistrict, 'Tuzla / İstanbul');
      final body = DeliveryPointDraft.of(p).toJson();
      expect(body['deliveryWindowStart'], '07:30:00');
      expect(body['deliveryWindowEnd'], '1.00:00:00');
      expect(body['tankCapacityLiters'], 15000.0);
      expect(body['latitude'], 40.8355);
    });

    test('kurallar sunucuyla aynı', () {
      const ok = DeliveryPointDraft(
        name: 'Merkez',
        city: 'Kocaeli',
        district: 'Gebze',
        address: 'OSB',
      );
      expect(ok.validate(), isNull);
      expect(
        const DeliveryPointDraft(
          city: 'A',
          district: 'B',
          address: 'C',
        ).validate(),
        'Teslimat noktası adı zorunlu.',
      );
      expect(
        ok.copyWith(district: '').validate(),
        'İl, ilçe ve açık adres zorunlu.',
      );
      expect(
        ok.copyWith(latitude: 40).validate(),
        'Konum için enlem ve boylamı birlikte girin.',
      );
      expect(
        ok
            .copyWith(
              windowStart: const WindowTime(600),
              windowEnd: const WindowTime(540),
            )
            .validate(),
        'Teslim saat aralığında başlangıç bitişten önce olmalı.',
      );
      expect(
        ok.copyWith(windowStart: const WindowTime(600)).validate(),
        contains('birlikte'),
      );
      expect(
        ok.copyWith(tankCapacityLiters: 0).validate(),
        'Tank kapasitesi sıfırdan büyük olmalı.',
      );
      expect(
        ok
            .copyWith(
              windowStart: WindowTime.startOfDay,
              windowEnd: WindowTime.endOfDay,
            )
            .validate(),
        isNull,
      );
    });

    test('il / ilçe listesi: 81 il, 973 ilçe, Türkçe yazım', () {
      expect(turkeyProvinces, hasLength(81));
      final total = turkeyDistrictsByProvince.values.fold<int>(
        0,
        (s, l) => s + l.length,
      );
      expect(total, 973);
      expect(turkeyDistrictsByProvince['İstanbul'], contains('Ataşehir'));
      expect(turkeyDistrictsByProvince['Kocaeli'], contains('Gebze'));
      expect(turkeyDistrictsByProvince['Nevşehir'], contains('Acıgöl'));
      expect(turkeyProvinces.first, 'Adana');
      expect(turkeyProvinces.last, 'Zonguldak');
    });
  });

  group('Harcamalar', () {
    test('aralık en çok 36 ay; ters ve ileri tarih düzelir', () {
      final now = TrTime.fromWall(2026, 10, 21, 12);
      final r = SpendingRange(
        from: TrTime.fromWall(2020, 1, 1),
        to: TrTime.fromWall(2026, 12, 31),
      ).normalized(now: now);
      expect(TrTime.isoDate(r.to), '2026-10-21');
      expect(TrTime.isoDate(r.from), '2023-11-01');
      final swapped = SpendingRange(
        from: TrTime.fromWall(2026, 5, 1),
        to: TrTime.fromWall(2026, 2, 1),
      ).normalized(now: now);
      expect(TrTime.isoDate(swapped.from), '2026-02-01');
      final last12 = SpendingRange.lastMonths(12, now: now);
      expect(TrTime.isoDate(last12.from), '2025-11-01');
      expect(last12.toQuery(), {
        'fromDate': '2025-11-01',
        'toDate': '2026-10-21',
      });
    });

    test('en fazla 5 kırılım + "Diğer" (sunucu değerlerinin toplamı)', () {
      final all = [
        for (var i = 0; i < 8; i++)
          SpendingBucket(
            id: i + 1,
            name: 'N$i',
            orderCount: 1,
            liters: 1000,
            amount: 40000,
            amountShare: 12.5,
          ),
      ];
      final top = topBuckets(all);
      expect(top, hasLength(6));
      expect(top.last.name, 'Diğer');
      expect(top.last.amount, 120000);
      expect(top.last.liters, 3000);
      expect(top.last.amountShare, 37.5);
      expect(top.last.avgUnitPrice, 40);
      expect(topBuckets(all.take(6).toList()), hasLength(6));
    });
  });

  group('Diğer modeller', () {
    test('arşiv satırı: sunucu bayrağı yoksa aynı kural uygulanır', () {
      final row = DocumentArchiveRow.fromJson(
        JsonReader({
          'orderId': 1,
          'orderNumber': 'SIP-1',
          'status': 3,
          'activeShipmentCount': 1,
          'shipmentId': 12,
          'shipmentStatus': 5,
          'quoteVersion': 2,
        }),
      );
      expect(row.canReconcile, isTrue);
      expect(row.canReceipt, isFalse, reason: 'iptal edilen sevkiyat');
      expect(row.canWaybill, isTrue);
      expect(row.shipmentCode, 'SVK-00000012');
      expect(row.receiptCode, isNull);
      expect(row.hasQuote, isTrue);
    });

    test('finans bilgisi: {links, orders} ve eski dizi biçimi', () {
      final info = FinanceInfo.fromJson({
        'links': [
          {
            'stationId': 2,
            'stationTitle': 'Kuzey',
            'status': {'canOrder': false, 'infoRequested': true},
            'requestId': 9010,
            'requestStatus': 4,
            'requiredKind': 10,
            'canReply': true,
          },
        ],
        'orders': [
          {'orderId': 5, 'orderNumber': 'SIP-5', 'requestId': 77},
        ],
      });
      expect(info.links.single.needsReply, isTrue);
      expect(info.links.single.kindLabel, 'Vergi levhası');
      expect(info.orders.single.requestId, 77);
      expect(info.pendingReplies, 2);
      final legacy = FinanceInfo.fromJson([
        {'stationId': 1, 'stationTitle': 'Demir'},
      ]);
      expect(legacy.links.single.stationTitle, 'Demir');
      expect(legacy.orders, isEmpty);
    });

    test('şirket kullanıcısı: tarihler UTC, rol etiketi', () {
      final u = CompanyUser.fromJson(
        JsonReader({
          'userId': 'u1',
          'displayName': 'Ali',
          'email': 'ali@x.com',
          'role': 2,
          'roleLabel': 'Onaylayan',
          'lastLoginAt': '2026-10-20T08:00:00',
          'invitationPending': true,
        }),
      );
      expect(u.role, CustomerUserRole.approver);
      expect(u.lastLoginAt, DateTime.utc(2026, 10, 20, 8));
      expect(u.invitationPending, isTrue);
      expect(
        ApprovalThresholds.validate(-1, null),
        'Litre eşiği negatif olamaz.',
      );
      expect(ApprovalThresholds.validate(0, null), isNull);
      expect(
        ApprovalThresholds.validate(null, 0),
        'Tutar eşiği sıfırdan büyük olmalı.',
      );
    });

    test('teslimat sorgusu: tekrarlanan durum anahtarları', () {
      const q = ShipmentQuery(
        statuses: [ShipmentStatus.reported, ShipmentStatus.disputed],
        search: 'SVK',
        sort: 1,
      );
      expect(q.toQuery(page: 2, pageSize: 25), {
        'page': 2,
        'pageSize': 25,
        'statuses': [2, 4],
        'search': 'SVK',
        'sort': 1,
      });
      final doc = const DocumentArchiveQuery().toQuery(skip: 25, take: 25);
      expect(doc['skip'], 25);
      expect(doc.containsKey('fromDate'), isFalse);
    });
  });
}

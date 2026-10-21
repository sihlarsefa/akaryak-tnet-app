import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('JsonReader', () {
    test('metin, sayı ve mantıksal alanlar hoşgörülü okunur', () {
      final r = JsonReader({
        'name': 'Motorin',
        'count': '12',
        'liters': 12500.5,
        'priceText': '42.1255',
        'active': 'true',
        'flag': 1,
        'Pascal': 'büyük harf',
        'blank': '   ',
      });
      expect(r.str('name'), 'Motorin');
      expect(r.integer('count'), 12);
      expect(r.dec('liters'), 12500.5);
      expect(r.dec('priceText'), closeTo(42.1255, 1e-9));
      expect(r.boolean('active'), isTrue);
      expect(r.boolean('flag'), isTrue);
      expect(r.str('pascal'), 'büyük harf', reason: 'PascalCase yedeği');
      expect(r.nonEmpty('blank'), isNull);
      expect(r.str('missing', 'yok'), 'yok');
      expect(r.intOrNull('name'), isNull);
      expect(r.decOrNull('missing'), isNull);
    });

    test('yanlış tipler varsayılana düşer, istisna fırlatmaz', () {
      final r = JsonReader({
        'list': 'x',
        'obj': 5,
        'num': {'a': 1},
      });
      expect(r.list('list', (e) => e.str('a')), isEmpty);
      expect(r.obj('obj').raw, isEmpty);
      expect(r.objOrNull('obj'), isNull);
      expect(r.integer('num', 7), 7);
      expect(JsonReader.of('not a map').raw, isEmpty);
      expect(JsonReader.parseList({'a': 1}, (e) => e), isEmpty);
    });

    test('iç içe nesneler ve diziler', () {
      final r = JsonReader({
        'items': [
          {'id': 1},
          'bozuk',
          {'id': 2},
        ],
        'ids': [1, '2', 'x', 3.0],
        'tags': ['a', 1],
      });
      expect(r.list('items', (e) => e.integer('id')), [1, 2]);
      expect(r.ints('ids'), [1, 2, 3]);
      expect(r.strings('tags'), ['a', '1']);
    });

    test('Türkiye yerel tarih (ofsetsiz) ve UTC tarih', () {
      final r = JsonReader({
        'local': '2026-10-21T14:20:00',
        'utc': '2026-10-21T11:20:00',
        'z': '2026-10-21T11:20:00Z',
        'offset': '2026-10-21T14:20:00+03:00',
        'net7': '2026-10-21T14:20:00.1234567',
        'date': '2026-10-22',
        'bad': 'yarın',
      });
      final expected = DateTime.utc(2026, 10, 21, 11, 20);
      expect(r.dateTr('local'), expected);
      expect(r.dateUtc('utc'), expected);
      expect(r.dateTr('z'), expected, reason: 'Z her durumda kesin an');
      expect(r.dateUtc('offset'), expected);
      expect(
        r
            .dateTr('net7')!
            .isAtSameMomentAs(
              expected.add(const Duration(microseconds: 123456)),
            ),
        isTrue,
      );
      expect(r.date('date'), TrTime.fromWall(2026, 10, 22));
      expect(r.dateTr('bad'), isNull);
      expect(r.dateTr('missing'), isNull);
    });

    test('bilinmeyen enum kodu unknown olur', () {
      final r = JsonReader({'status': 3, 'other': 42, 'text': 'x'});
      expect(r.enumOf('status', OrderStatus.fromCode), OrderStatus.approved);
      expect(r.enumOf('other', OrderStatus.fromCode), OrderStatus.unknown);
      expect(r.enumOf('text', OrderStatus.fromCode), OrderStatus.unknown);
      expect(
        r.enumOf('missing', ShipmentStatus.fromCode),
        ShipmentStatus.unknown,
      );
    });
  });

  group('Paylaşılan modeller', () {
    test('PagedResult sayfalar ve ekler', () {
      final first = PagedResult.fromJson({
        'items': [
          {'id': 1},
          {'id': 2},
        ],
        'totalCount': 3,
        'pageNumber': 1,
        'pageSize': 2,
        'totalPages': 2,
      }, (r) => r.integer('id'));
      expect(first.items, [1, 2]);
      expect(first.hasMore, isTrue);
      final second = PagedResult.fromJson({
        'items': [
          {'id': 3},
        ],
        'totalCount': 3,
        'pageNumber': 2,
        'pageSize': 2,
      }, (r) => r.integer('id'));
      expect(second.totalPages, 2, reason: 'totalPages yoksa hesaplanır');
      final all = first.append(second);
      expect(all.items, [1, 2, 3]);
      expect(all.hasMore, isFalse);
    });

    test('MeAccess gidiş-dönüş', () {
      final json = {
        'userId': 'u-1',
        'userName': 'sahip',
        'displayName': 'Mehmet Demir',
        'persona': 'bayi',
        'roles': ['Station'],
        'stationId': 1,
        'stationTitle': 'Demir Petrol',
        'customerUserRole': null,
        'bayiRoleCodes': ['owner'],
        'bayiRoleNames': ['Bayi sahibi'],
        'pages': ['StationOrders:Gorur', 'StationOrders:Ekler'],
        'capabilities': [
          {'code': 'approve.finance.order', 'limit': 1000000},
          {'code': 'costs.view', 'limit': null},
        ],
        'delegations': [
          {
            'fromUserName': 'Ayşe',
            'approvalType': 4,
            'validTo': '2026-12-31T00:00:00Z',
          },
        ],
        'accessVersion': 7,
      };
      final a = MeAccess.fromJson(json);
      expect(a.persona, Persona.bayi);
      expect(a.pages, contains('StationOrders:Ekler'));
      expect(a.capabilities.first.limit, 1000000);
      expect(a.delegations.single.approvalType, ApprovalType.orderFinance);
      expect(a.accessVersion, '7');
      expect(
        a.customerUserRole,
        CustomerUserRole.admin,
        reason: 'null = Yönetici',
      );
      final again = MeAccess.fromJson(a.toJson());
      expect(again.layoutKey, a.layoutKey);
    });

    test('OrderDetail geçerli teklifi seçer', () {
      final d = OrderDetail.fromJson({
        'id': 12,
        'orderNumber': 'SIP-1',
        'status': 2,
        'quantityLiters': 8000,
        'paymentStatus': 1,
        'financeStatus': 2,
        'quotes': [
          {
            'id': 1,
            'version': 1,
            'unitPriceTry': 42.1,
            'totalAmountTry': 336800,
            'isSelected': false,
          },
          {
            'id': 2,
            'version': 2,
            'unitPriceTry': 41.9,
            'totalAmountTry': 335200,
            'isSelected': false,
          },
        ],
      });
      expect(d.status, OrderStatus.awaitingApproval);
      expect(d.paymentStatus, PaymentStatus.pending);
      expect(d.financeStatus, OrderFinanceStatus.approved);
      expect(d.currentQuote?.version, 2);
    });

    test('ProblemDetails eski gövdeleri de okur', () {
      expect(
        Problem.tryParse({'message': 'Hata oluştu'})?.detail,
        'Hata oluştu',
      );
      expect(Problem.tryParse('metin'), isNull);
      expect(Problem.tryParse(<String, dynamic>{}), isNull);
      final p = Problem.tryParse({
        'code': 'validation',
        'errors': {
          'Lines[0].QuantityLiters': ['Litre sıfırdan büyük olmalı.'],
          'Note': 'tek mesaj',
        },
      })!;
      expect(p.firstError, 'Litre sıfırdan büyük olmalı.');
      expect(p.errors['Note'], ['tek mesaj']);
    });
  });
}

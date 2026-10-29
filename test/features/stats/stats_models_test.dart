// İstatistik modelleri: sözleşme örneklerinin (spec R1 §4) tam okunması ve hoşgörülü okuma (eksik / null
// bölümler, bilinmeyen anahtarlar, metin sayılar, PascalCase).
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/features/stats/data/stats_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Spec R1 §4.1 örneği (kısaltılmamış alanlar).
final Map<String, dynamic> bayiSample = {
  'stationId': 1,
  'stationTitle': 'Demo Petrol',
  'scope': 'station',
  'generatedAt': '2026-10-21T10:00:00Z',
  'period': {
    'key': 'month',
    'label': 'Bu ay',
    'from': '2026-10-01',
    'to': '2026-10-21',
    'compareLabel': 'Geçen ayın aynı dönemi',
    'compareFrom': '2026-09-01',
    'compareTo': '2026-09-21',
  },
  'sales': {
    'orders': 42,
    'liters': 512000.0,
    'amount': 21500000.00,
    'prevOrders': 38,
    'prevLiters': 470000.0,
    'prevAmount': 19800000.00,
    'avgUnitPrice': 41.99,
    'prevAvgUnitPrice': 42.13,
    'activeCustomers': 17,
    'newCustomers': 2,
  },
  'months': [
    {
      'year': 2026,
      'month': 5,
      'label': 'May',
      'orders': 30,
      'liters': 400000.0,
      'amount': 16000000.00,
    },
  ],
  'products': [
    {
      'productId': 1,
      'name': 'Motorin',
      'liters': 400000.0,
      'amount': 17000000.00,
      'share': 0.78,
    },
  ],
  'topCustomers': [
    {
      'customerId': 5,
      'title': 'Anadolu Nakliyat',
      'orders': 8,
      'liters': 120000.0,
      'amount': 5100000.00,
      'share': 0.23,
    },
  ],
  'funnel': {
    'requests': 60,
    'quoted': 52,
    'accepted': 41,
    'rejected': 6,
    'expired': 5,
    'conversionRate': 0.788,
    'avgFirstQuoteMinutes': 34,
  },
  'deliveries': {
    'delivered': 39,
    'deliveredLiters': 498000.0,
    'onTimeRate': 0.92,
    'inTransit': 3,
    'planned': 7,
    'disputes': 1,
  },
  'collections': {
    'collectedAmount': 15200000.00,
    'collectedCount': 33,
    'overdueAmount': 820000.00,
    'overdueCount': 4,
    'dueSoonAmount': 1300000.00,
    'dueSoonCount': 6,
    'dueSoonDays': 7,
  },
  'team': [
    {
      'userId': 12,
      'name': 'Ahmet Yılmaz',
      'forms': 9,
      'converted': 6,
      'liters': 90000.0,
    },
  ],
  'risk': {
    'nearLimitCount': 3,
    'nearLimit': [
      {'customerId': 7, 'title': 'Ege Lojistik', 'usageRate': 0.93},
    ],
  },
  'failedSections': <String>[],
};

/// Spec R1 §4.2 örneği.
final Map<String, dynamic> customerSample = {
  'customerId': 5,
  'customerTitle': 'Anadolu Nakliyat A.Ş.',
  'generatedAt': '2026-10-21T10:00:00Z',
  'period': {
    'key': 'month',
    'label': 'Bu ay',
    'from': '2026-10-01',
    'to': '2026-10-21',
    'compareLabel': 'Geçen ayın aynı dönemi',
    'compareFrom': '2026-09-01',
    'compareTo': '2026-09-21',
  },
  'spending': {
    'orders': 8,
    'liters': 120000.0,
    'amount': 5100000.00,
    'prevOrders': 7,
    'prevLiters': 100000.0,
    'prevAmount': 4300000.00,
    'avgUnitPrice': 42.50,
    'prevAvgUnitPrice': 43.00,
  },
  'months': [
    {
      'year': 2026,
      'month': 10,
      'label': 'Eki',
      'orders': 8,
      'liters': 120000.0,
      'amount': 5100000.0,
    },
  ],
  'products': [
    {
      'productId': 1,
      'name': 'Motorin',
      'liters': 120000.0,
      'amount': 5100000.0,
      'share': 1.0,
    },
  ],
  'stations': [
    {
      'stationId': 1,
      'title': 'Demo Petrol',
      'liters': 0.0,
      'amount': 0.00,
      'share': 0.0,
    },
  ],
  'deliveryPoints': [
    {
      'deliveryPointId': 3,
      'name': 'Gebze Depo',
      'city': 'Kocaeli',
      'liters': 0.0,
      'amount': 0.00,
      'share': 0.0,
    },
  ],
  'orders': {
    'awaitingQuote': 1,
    'awaitingDecision': 2,
    'awaitingCompanyApproval': 1,
    'inTransit': 1,
    'delivered': 7,
    'disputed': 0,
  },
  'limits': [
    {
      'stationId': 1,
      'stationTitle': 'Demo Petrol',
      'limit': 10000000.00,
      'used': 7300000.00,
      'available': 2700000.00,
      'usageRate': 0.73,
    },
  ],
  'failedSections': <String>[],
};

void main() {
  group('BayiStats', () {
    test('sözleşme örneği eksiksiz okunur', () {
      final s = BayiStats.fromJson(bayiSample);
      expect(s.stationId, 1);
      expect(s.stationTitle, 'Demo Petrol');
      expect(s.scope, 'station');
      expect(s.isOwn, isFalse);
      expect(s.generatedAt, DateTime.utc(2026, 10, 21, 10));
      expect(s.period.key, StatsPeriod.month);
      expect(s.period.title, 'Bu ay');
      expect(s.period.compareLabel, 'Geçen ayın aynı dönemi');
      expect(s.period.from, isNotNull);
      final sales = s.sales!;
      expect(sales.orders, 42);
      expect(sales.liters, 512000);
      expect(sales.amount, 21500000);
      expect(sales.prevAmount, 19800000);
      expect(sales.unitPrice, 41.99);
      expect(sales.prevUnitPrice, 42.13);
      expect(sales.activeCustomers, 17);
      expect(sales.newCustomers, 2);
      expect(s.months.single.shortLabel, 'May');
      expect(s.months.single.longLabel, 'Mayıs 2026');
      expect(s.products.single.share, 0.78);
      expect(s.topCustomers.single.title, 'Anadolu Nakliyat');
      expect(s.funnel!.conversion, 0.788);
      expect(s.funnel!.avgFirstQuoteMinutes, 34);
      expect(s.deliveries!.onTimeRate, 0.92);
      expect(s.collections!.overdueCount, 4);
      expect(s.collections!.dueSoonDays, 7);
      expect(s.team.single.userId, '12', reason: 'sayı kimlik metne çevrilir');
      expect(s.team.single.conversion, closeTo(6 / 9, 1e-9));
      expect(s.risk!.nearLimitCount, 3);
      expect(s.risk!.nearLimit.single.usageRate, 0.93);
      expect(s.failedSections, isEmpty);
      expect(s.isBlank, isFalse);
    });

    test(
      'eksik ve null bölümler null / boş olur, bilinmeyen anahtarlar yok sayılır',
      () {
        final s = BayiStats.fromJson({
          'stationId': 1,
          'scope': 'own',
          'sales': null,
          'funnel': null,
          'collections': null,
          'risk': null,
          'team': null,
          'someFutureSection': {'x': 1},
          'failedSections': ['funnel', 'deliveries'],
        }, period: StatsPeriod.quarter);
        expect(s.isOwn, isTrue);
        expect(s.sales, isNull);
        expect(s.funnel, isNull);
        expect(s.deliveries, isNull);
        expect(s.collections, isNull);
        expect(s.risk, isNull);
        expect(s.team, isEmpty);
        expect(s.months, isEmpty);
        expect(s.products, isEmpty);
        expect(s.topCustomers, isEmpty);
        expect(s.failedSections, {'funnel', 'deliveries'});
        expect(
          s.period.key,
          StatsPeriod.quarter,
          reason: 'dönem yoksa istenen',
        );
        expect(s.isBlank, isTrue);
      },
    );

    test('metin sayılar, PascalCase anahtarlar ve bozuk gövde', () {
      final s = BayiStats.fromJson({
        'Sales': {'Orders': '7', 'Liters': '12500.5', 'Amount': '525000.75'},
        'Months': [
          {'Year': '2026', 'Month': '13', 'Amount': 'x'},
        ],
      });
      expect(s.sales!.orders, 7);
      expect(s.sales!.liters, 12500.5);
      expect(s.sales!.amount, 525000.75);
      expect(s.sales!.avgUnitPrice, isNull);
      expect(s.sales!.unitPrice, closeTo(525000.75 / 12500.5, 1e-9));
      expect(s.months.single.month, 12, reason: 'ay 1..12 aralığına çekilir');
      expect(s.months.single.amount, 0);
      expect(BayiStats.fromJson('bozuk').isBlank, isTrue);
      expect(BayiStats.fromJson(null).scope, 'station');
    });

    test('dönem anahtarları', () {
      expect(StatsPeriod.fromKey('lastMonth'), StatsPeriod.lastMonth);
      expect(StatsPeriod.fromKey('year'), StatsPeriod.year);
      expect(StatsPeriod.fromKey('bilinmiyor'), StatsPeriod.month);
      expect(StatsPeriod.fromKey(null), StatsPeriod.month);
      // Karşılaştırma cümleleri (tasarım v2 §10.4).
      expect(StatsPeriod.month.compareShort, 'geçen ayın aynı günlerine göre');
      expect(StatsPeriod.lastMonth.compareShort, 'önceki aya göre');
      expect(StatsPeriod.quarter.compareShort, 'önceki 3 aya göre');
      expect(StatsPeriod.year.compareShort, 'geçen yılın aynı dönemine göre');
      // Plakanın dönem satırındaki kısa adlar (v4 tur 2 A11: "1–29 Ekim · geçen aya göre").
      expect(StatsPeriod.month.compareBrief, 'geçen aya göre');
      expect(StatsPeriod.lastMonth.compareBrief, 'önceki aya göre');
      expect(StatsPeriod.quarter.compareBrief, 'önceki 3 aya göre');
      expect(StatsPeriod.year.compareBrief, 'geçen yıla göre');
      expect(
        [for (final p in StatsPeriod.values) p.key],
        ['month', 'lastMonth', 'quarter', 'year'],
      );
    });

    test('dönüşüm sunucudan gelmezse onay / talep; talep yoksa null', () {
      expect(
        StatsFunnel.fromJson(
          JsonReader.of({'requests': 10, 'accepted': 4}),
        ).conversion,
        0.4,
      );
      expect(
        StatsFunnel.fromJson(JsonReader.of({'requests': 0})).conversion,
        isNull,
      );
    });
  });

  group('CustomerStats', () {
    test('sözleşme örneği eksiksiz okunur', () {
      final s = CustomerStats.fromJson(customerSample);
      expect(s.customerId, 5);
      expect(s.customerTitle, 'Anadolu Nakliyat A.Ş.');
      expect(s.spending!.amount, 5100000);
      expect(s.spending!.unitPrice, 42.5);
      expect(s.spending!.prevUnitPrice, 43.0);
      expect(s.months.single.shortLabel, 'Eki');
      expect(s.products.single.name, 'Motorin');
      expect(s.stations.single.title, 'Demo Petrol');
      expect(s.deliveryPoints.single.city, 'Kocaeli');
      expect(s.orders!.open, 1 + 2 + 1 + 1);
      expect(s.orders!.delivered, 7);
      final l = s.limits.single;
      expect(l.isUnlimited, isFalse);
      expect(l.available, 2700000);
      expect(l.usageRate, 0.73);
      expect(s.isBlank, isFalse);
    });

    test('limitsiz bayi ve eksik alanlar', () {
      final s = CustomerStats.fromJson({
        'spending': {'orders': 0},
        'limits': [
          {'stationId': 2, 'stationTitle': 'Kuzey', 'limit': null, 'used': 0},
          {'stationId': 1, 'stationTitle': 'Demir', 'limit': 100, 'used': 80},
          {
            'stationId': 3,
            'stationTitle': 'Litre',
            'limit': 300000,
            'used': 120000,
            'unit': 'L',
          },
        ],
        'orders': null,
      });
      expect(s.limits[0].isUnlimited, isTrue);
      expect(s.limits[0].available, isNull);
      expect(s.limits[0].usageRate, isNull);
      expect(s.limits[1].available, 20, reason: 'gelmezse limit − kullanılan');
      expect(s.limits[1].usageRate, 0.8);
      expect(s.limits[2].isLiters, isTrue);
      expect(s.orders, isNull);
      expect(s.spending!.isEmpty, isTrue);
      expect(s.stations, isEmpty);
    });
  });
}

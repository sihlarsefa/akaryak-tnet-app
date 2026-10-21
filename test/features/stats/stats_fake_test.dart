// İstatistik sahteleri (spec R1 §4 sözleşmesi): kapsam, yetki (403), dönem doğrulaması (400), dönem
// hesabı (Türkiye ay sınırları), paylar ve deterministiklik.
import 'package:akaryakitnet/core/network/fake/core_fakes.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:akaryakitnet/features/stats/data/stats_models.dart';
import 'package:akaryakitnet/features/stats/stats_fake.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sabit "şimdi": 21 Ekim 2026 14:00 (Türkiye).
final _now = TrTime.fromWall(2026, 10, 21, 14);

Map<String, dynamic> _bayi(
  String persona, [
  StatsPeriod p = StatsPeriod.month,
  DateTime? now,
]) {
  final at = now ?? _now;
  return StatsFake.bayi(
    FakeWorld.seeded(now: at),
    findFakePersona(persona)!,
    p,
    now: at,
  );
}

Map<String, dynamic> _customer(
  String persona, [
  StatsPeriod p = StatsPeriod.month,
  DateTime? now,
]) {
  final at = now ?? _now;
  return StatsFake.customer(
    FakeWorld.seeded(now: at),
    findFakePersona(persona)!,
    p,
    now: at,
  );
}

double _shareSum(List<dynamic> rows) =>
    rows.fold<double>(0, (s, r) => s + ((r as Map)['share'] as num));

void main() {
  group('bayi', () {
    test('sahip: bayi geneli, tüm bölümler, sözleşme şekli', () {
      final j = _bayi('sahip');
      expect(j['scope'], 'station');
      expect(j['stationId'], 1);
      expect(j['stationTitle'], isNotEmpty);
      final s = BayiStats.fromJson(j);
      expect(s.months, hasLength(6));
      expect(s.months.last.month, 10, reason: 'son ay bu ay');
      expect(s.months.first.month, 5);
      expect(s.sales!.orders, greaterThan(0));
      expect(s.sales!.amount, greaterThan(0));
      expect(s.sales!.prevAmount, greaterThan(0));
      expect(s.sales!.activeCustomers, inInclusiveRange(1, 4));
      expect(s.products, isNotEmpty);
      expect(s.products.length, lessThanOrEqualTo(6));
      expect(_shareSum(j['products'] as List), closeTo(1, 0.001));
      expect(s.topCustomers.length, inInclusiveRange(1, 5));
      for (var i = 1; i < s.topCustomers.length; i++) {
        expect(
          s.topCustomers[i - 1].amount,
          greaterThanOrEqualTo(s.topCustomers[i].amount),
        );
      }
      final f = s.funnel!;
      expect(f.requests, greaterThanOrEqualTo(f.quoted));
      expect(f.quoted, greaterThanOrEqualTo(f.accepted));
      expect(f.conversionRate, closeTo(f.accepted / f.requests, 0.0001));
      expect(f.avgFirstQuoteMinutes, isNotNull);
      expect(s.deliveries!.onTimeRate, inInclusiveRange(0, 1));
      expect(s.collections, isNotNull, reason: 'ödemeleri görebilir');
      expect(s.team.map((m) => m.userId), containsAll(['u-saha', 'u-murat']));
      expect(s.risk!.nearLimitCount, 1, reason: 'Marmara İnşaat %94');
      expect(s.risk!.nearLimit.single.customerId, 102);
      expect(s.failedSections, isEmpty);
      // Maliyet / kâr alanı yok.
      final text = '$j'.toLowerCase();
      for (final banned in ['cost', 'margin', 'purchase', 'profit']) {
        expect(text.contains(banned), isFalse, reason: banned);
      }
    });

    test('saha temsilcisi: yalnızca portföyü, yalnızca kendi satırı', () {
      final s = BayiStats.fromJson(_bayi('saha'));
      expect(s.scope, 'own');
      expect(s.isOwn, isTrue);
      expect(
        s.topCustomers.map((c) => c.customerId).toSet().difference({103, 104}),
        isEmpty,
        reason: 'portföy: Ege Tarım ve Körfez Nakliyat',
      );
      expect(s.team.single.userId, 'u-saha');
      expect(s.team.single.name, 'Deniz Koç');
      expect(s.collections, isNull);
      expect(s.risk, isNull);
      final all = BayiStats.fromJson(_bayi('sahip'));
      expect(s.sales!.amount, lessThan(all.sales!.amount));
    });

    test('rol bölümleri: ekip, tahsilat ve risk yetkiyle gelir', () {
      final satis = BayiStats.fromJson(_bayi('satis'));
      expect(satis.team, isNotEmpty, reason: 'satış müdürü');
      expect(satis.collections, isNull, reason: 'ödeme yetkisi yok');
      expect(satis.risk, isNotNull);

      final finans = BayiStats.fromJson(_bayi('finans'));
      expect(finans.team, isEmpty);
      expect(finans.collections, isNotNull);

      final muhasebe = BayiStats.fromJson(_bayi('muhasebe'));
      expect(muhasebe.collections, isNotNull);
      expect(muhasebe.team, isEmpty);

      final izleyici = BayiStats.fromJson(_bayi('izleyici'));
      expect(izleyici.collections, isNull);
      expect(izleyici.risk, isNotNull);
      expect(izleyici.team, isEmpty);
    });

    test('deterministik: aynı an aynı gövde', () {
      final a = _bayi('sahip')..remove('generatedAt');
      final b = _bayi('sahip')..remove('generatedAt');
      expect(a, b);
    });

    test('ayın verisi sentetik geçmiş + dünyadaki onaylı siparişler', () {
      final w = FakeWorld.seeded(now: _now);
      final p = findFakePersona('sahip')!;
      final before = BayiStats.fromJson(
        StatsFake.bayi(w, p, StatsPeriod.month, now: _now),
      );
      // Dünyaya bu ay onaylanan bir sipariş eklenince satış artar.
      w.orders.add(
        w.newOrder(
          id: 99001,
          customerId: 101,
          stationId: 1,
          deliveryPointId: 1001,
          productId: 1,
          liters: 10000,
          status: 3,
          createdAt: _now.subtract(const Duration(hours: 3)),
          expiresAt: _now,
          requestedDeliveryDate: _now,
          quotes: [
            w.newQuote(
              id: 99002,
              version: 1,
              unitPrice: 42,
              liters: 10000,
              deliveryDate: _now,
              createdAt: _now.subtract(const Duration(hours: 2)),
              selected: true,
            ),
          ],
        ),
      );
      final after = BayiStats.fromJson(
        StatsFake.bayi(w, p, StatsPeriod.month, now: _now),
      );
      expect(after.sales!.orders, before.sales!.orders + 1);
      expect(after.sales!.amount, closeTo(before.sales!.amount + 420000, 0.01));
    });
  });

  group('müşteri', () {
    test('yönetici: harcama, bayiler, noktalar, durum, limitler', () {
      final j = _customer('musteri');
      final s = CustomerStats.fromJson(j);
      expect(s.customerId, 101);
      expect(s.spending!.amount, greaterThan(0));
      expect(s.spending!.unitPrice, isNotNull);
      expect(s.months, hasLength(6));
      expect(s.stations.map((x) => x.stationId), contains(1));
      expect(_shareSum(j['stations'] as List), closeTo(1, 0.001));
      expect(
        s.deliveryPoints.map((x) => x.deliveryPointId).toSet().difference({
          1001,
          1002,
        }),
        isEmpty,
      );
      expect(s.orders!.awaitingCompanyApproval, 1);
      expect(s.limits, hasLength(2));
      expect(s.limits.where((l) => l.isUnlimited), hasLength(1));
      final limited = s.limits.firstWhere((l) => !l.isUnlimited);
      expect(limited.usageRate, closeTo(1180000 / 2500000, 0.0001));
    });

    test('bayi ve müşteri aynı defteri görür', () {
      final bayi = BayiStats.fromJson(_bayi('sahip'));
      final cust = CustomerStats.fromJson(_customer('musteri'));
      final anadolu = bayi.topCustomers.firstWhere((c) => c.customerId == 101);
      final fromStation1 = cust.stations.firstWhere((x) => x.stationId == 1);
      expect(fromStation1.amount, closeTo(anadolu.amount, 0.01));
    });

    test('yıl: 12 ay', () {
      final s = CustomerStats.fromJson(_customer('onay', StatsPeriod.year));
      expect(s.months, hasLength(12));
      expect(s.period.key, StatsPeriod.year);
    });
  });

  group('dönem hesabı (Türkiye takvimi)', () {
    Map<String, dynamic> period(StatsPeriod p, DateTime now) =>
        StatsWindow.of(p, now).toJson();

    test('bu ay: 1\'i → şimdi, önceki ayın aynı uzunluğu', () {
      expect(period(StatsPeriod.month, _now), {
        'key': 'month',
        'label': 'Bu ay',
        'from': '2026-10-01',
        'to': '2026-10-21',
        'compareLabel': 'Geçen ayın aynı dönemi',
        'compareFrom': '2026-09-01',
        'compareTo': '2026-09-21',
      });
    });

    test('ayın son günü: karşılaştırma önceki ayın sonunda kesilir', () {
      final j = period(StatsPeriod.month, TrTime.fromWall(2026, 3, 31, 18));
      expect(j['from'], '2026-03-01');
      expect(j['compareFrom'], '2026-02-01');
      expect(j['compareTo'], '2026-02-28');
    });

    test('ayın ilk dakikaları (UTC hâlâ önceki gün)', () {
      final now = TrTime.fromWall(2026, 11, 1, 0, 30);
      expect(now.toUtc().day, 31, reason: 'UTC tarafında 31 Ekim');
      final j = period(StatsPeriod.month, now);
      expect(j['from'], '2026-11-01');
      expect(j['to'], '2026-11-01');
      expect(j['compareFrom'], '2026-10-01');
    });

    test('geçen ay: tüm ay; ocakta aralık', () {
      expect(
        period(StatsPeriod.lastMonth, _now),
        containsPair('to', '2026-09-30'),
      );
      final jan = period(StatsPeriod.lastMonth, TrTime.fromWall(2027, 1, 5, 9));
      expect(jan['from'], '2026-12-01');
      expect(jan['to'], '2026-12-31');
      expect(jan['compareFrom'], '2026-11-01');
      expect(jan['compareTo'], '2026-11-30');
    });

    test('son 3 ay: bugün − 89 gün ve önceki 90 gün', () {
      final j = period(StatsPeriod.quarter, _now);
      expect(j['from'], '2026-07-24');
      expect(j['to'], '2026-10-21');
      expect(j['compareFrom'], '2026-04-25');
      expect(j['compareTo'], '2026-07-23');
    });

    test('bu yıl: 1 Ocak → şimdi, geçen yılın aynı dönemi', () {
      final j = period(StatsPeriod.year, _now);
      expect(j['from'], '2026-01-01');
      expect(j['compareFrom'], '2025-01-01');
      expect(j['compareTo'], '2025-10-21');
    });
  });

  group('HTTP (sahte sunucu)', () {
    late FakeServer server;

    setUp(() async {
      server = FakeServer.forTests();
      registerCoreFakes(server);
      registerStatsFakes(server);
      await Future<void>.delayed(Duration.zero);
    });

    Future<FakeResponse> get(String path, String persona) async {
      final token =
          server.auth.issueTokens(
                findFakePersona(persona)!,
                deviceId: 'test-device',
              )['accessToken']
              as String;
      return server.handle(
        method: 'GET',
        path: path.split('?').first,
        uri: Uri.parse('https://test/api/v1/$path'),
        headers: {'authorization': 'Bearer $token'},
      );
    }

    test('kitle 200, diğerleri 403 forbidden', () async {
      for (final p in [
        'sahip',
        'mudur',
        'finans',
        'muhasebe',
        'satis',
        'izleyici',
        'saha',
      ]) {
        expect((await get('stats/bayi', p)).status, 200, reason: p);
      }
      for (final p in [
        'musteri',
        'talep',
        'onay',
        'sevkiyat',
        'sofor',
        'depo',
        'merkez',
      ]) {
        final r = await get('stats/bayi', p);
        expect(r.status, 403, reason: p);
        expect((r.body as Map)['code'], 'forbidden');
      }
      for (final p in ['musteri', 'onay']) {
        expect((await get('stats/customer', p)).status, 200, reason: p);
      }
      for (final p in ['talep', 'sahip', 'saha', 'merkez']) {
        expect((await get('stats/customer', p)).status, 403, reason: p);
      }
    });

    test(
      'geçersiz dönem 400 validation; dönem büyük/küçük harf duyarsız',
      () async {
        final bad = await get('stats/bayi?period=week', 'sahip');
        expect(bad.status, 400);
        expect((bad.body as Map)['code'], 'validation');
        final ok = await get('stats/bayi?period=LASTMONTH', 'sahip');
        expect(ok.status, 200);
        expect(((ok.body as Map)['period'] as Map)['key'], 'lastMonth');
      },
    );
  });
}

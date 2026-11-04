// Sahip kararı 04.11.2026: "admin onayı olmaz, bayi onayları olur"; "teklif verilip müşteri onaylarsa ondan
// sonra finans onayına gitmesi lazım"; "limit onayı ilk etapta gerek yok". Sahte sunucuya doğrudan istek
// atılır; sunucu tarafının sınaması `FirstStageApprovalsTests` (C#).
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/network/fake/core_fakes.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:akaryakitnet/features/approvals/approvals_fake.dart';
import 'package:akaryakitnet/features/approvals/fake/a5_fake_store.dart';
import 'package:akaryakitnet/features/bayi/bayi_fake.dart';
import 'package:akaryakitnet/features/customer_orders/customer_orders_fake.dart';
import 'package:flutter_test/flutter_test.dart';

class _Direct {
  _Direct(this.server);

  final FakeServer server;
  final Map<String, String> _tokens = {};

  String _token(String key) => _tokens.putIfAbsent(
    key,
    () =>
        server.auth.issueTokens(
              findFakePersona(key)!,
              deviceId: 'qa-$key',
            )['accessToken']
            as String,
  );

  Future<FakeResponse> send(
    String key,
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) => server.handle(
    method: method,
    path: path,
    uri: Uri(
      scheme: 'https',
      host: 'fake.local',
      path: '/api/v1/$path',
      queryParameters: query,
    ),
    body: body,
    headers: {'authorization': 'Bearer ${_token(key)}'},
  );

  Future<JsonReader> ok(
    String key,
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final r = await send(key, method, path, query: query, body: body);
    expect(
      r.status,
      inInclusiveRange(200, 299),
      reason: '$key $method $path → ${r.status} ${r.body}',
    );
    return JsonReader.of(r.body);
  }
}

void main() {
  late FakeWorld w;
  late _Direct api;

  setUp(() {
    w = FakeWorld.seeded();
    final s = FakeServer.forTests(world: w);
    registerCoreFakes(s);
    registerApprovalsFakes(s);
    registerBayiFakes(s);
    registerCustomerOrdersFakes(s);
    api = _Direct(s);
  });

  /// Müşterinin teklif bekleyen, finansa düşmemiş siparişine bayi teklif verir; sipariş kimliği.
  Future<int> quotedOrder() async {
    final customerId = findFakePersona('musteri')!.customerId;
    final o = w.orders.firstWhere(
      (o) =>
          o['customerId'] == customerId &&
          o['status'] == 1 &&
          ((o['financeStatus'] as int?) ?? 0) == 0,
    );
    final id = o['id'] as int;
    await api.ok(
      'sahip',
      'POST',
      'orders/$id/quote',
      body: {
        'unitPriceTry': 41.5,
        'deliveryDate': TrTime.isoDate(TrTime.addDays(TrTime.todayStart(), 2)),
      },
    );
    expect(w.order(id)!['status'], 2);
    return id;
  }

  Future<JsonMap> approveQuote(int id) async {
    await api.ok('musteri', 'POST', 'orders/$id/approve', body: const {});
    return w.order(id)!;
  }

  int financeApprovalOf(JsonMap order) =>
      order['financeApprovalRequestId'] as int;

  Future<void> decide(
    String key,
    int approvalId,
    int decision, {
    String? note,
  }) async {
    final d = await api.ok(key, 'GET', 'approvals/$approvalId');
    await api.ok(
      key,
      'POST',
      'approvals/$approvalId/decide',
      body: {
        'decision': decision,
        'concurrencyToken': d.str('concurrencyToken'),
        'note': ?note,
      },
    );
  }

  group('sipariş: finans müşteri onayından sonra', () {
    test(
      'müşteri onayı siparişi finansa gönderir, karar kapanır, "Onaylandı" olmaz',
      () async {
        final id = await quotedOrder();
        final o = await approveQuote(id);

        expect(
          o['status'],
          2,
          reason: 'finans kararına kadar "Onay bekleniyor"',
        );
        expect(o['financeStatus'], 1);
        expect(o['acceptedQuoteId'], isNotNull);
        expect(w.approval(financeApprovalOf(o)), isNotNull);

        final detail = await api.ok('musteri', 'GET', 'orders/$id');
        expect(detail.boolean('canDecideQuote'), isFalse);

        final again = await api.send(
          'musteri',
          'POST',
          'orders/$id/reject',
          body: const {},
        );
        expect(again.status, 400, reason: 'karar geri alınamaz');
      },
    );

    test('kabul edilen sipariş "Karar" değil "Aktif" bölmesinde', () async {
      final id = await quotedOrder();
      await approveQuote(id);

      Future<List<int>> ids(String segment) async => (await api.ok(
        'musteri',
        'GET',
        'customers/me/orders',
        query: {'segment': segment, 'pageSize': '100'},
      )).list('items', (r) => r.integer('id'));

      expect(await ids('decision'), isNot(contains(id)));
      expect(await ids('active'), contains(id));
    });

    test('finans onayı siparişi "Onaylandı" yapar', () async {
      final id = await quotedOrder();
      final o = await approveQuote(id);
      await decide('finans', financeApprovalOf(o), 1);

      expect(w.order(id)!['status'], 3);
      expect(w.order(id)!['financeStatus'], 2);
    });

    test('finans reddi siparişi kapatır', () async {
      final id = await quotedOrder();
      final o = await approveQuote(id);
      await decide(
        'finans',
        financeApprovalOf(o),
        4,
        note: 'Teminat yetersiz, sipariş kapatıldı.',
      );

      expect(w.order(id)!['status'], 4);
      expect(w.order(id)!['financeStatus'], 5);
    });

    test(
      'yeni sipariş oluşurken finansa düşmez, limit aşımı teklifi durdurmaz',
      () async {
        final id = await quotedOrder();
        expect(
          w.order(id)!['financeStatus'],
          0,
          reason: 'teklif finans kararı beklemez',
        );
      },
    );
  });

  group('merkez karar vermez', () {
    test(
      'sipariş finansına merkez karar veremez, ipucu nedeni söyler',
      () async {
        final id = await quotedOrder();
        final o = await approveQuote(id);
        final approvalId = financeApprovalOf(o);

        final d = await api.ok('merkez', 'GET', 'approvals/$approvalId');
        expect(
          d.strOrNull('decisionHint'),
          'Bu talebe bayi karar verir; merkez yalnızca izler.',
        );
        final r = await api.send(
          'merkez',
          'POST',
          'approvals/$approvalId/decide',
          body: {'decision': 1, 'concurrencyToken': d.str('concurrencyToken')},
        );
        expect(r.status, greaterThanOrEqualTo(400));
        expect(w.order(id)!['status'], 2);
      },
    );

    test('şirket içi talep dışındaki her tür bayide karara bağlanır', () {
      final store = A5FakeStore.of(w);
      for (final type in [1, 2, 4, 5, 6, 7]) {
        expect(store.isBayiDecided(type), isTrue, reason: 'tür $type');
      }
      expect(store.isBayiDecided(3), isFalse);
    });

    test('ön kayıt merkeze iletilemez', () {
      expect(
        () => A5FakeStore.of(w).forwardLead(findFakePersona('finans')!, 8003),
        throwsA(isA<FakeResponse>()),
      );
    });
  });

  group('Bayi yöneticisi her şeyi onaylar', () {
    test(
      'birim onaycısı seçiliyken sipariş finansını onaylar; imza kümesi süzülmez',
      () async {
        final id = await quotedOrder();
        final o = await approveQuote(id);
        await decide('sahip', financeApprovalOf(o), 1);
        expect(w.order(id)!['status'], 3);
      },
    );

    test('sıradan kullanıcı onaycı süzgecine takılır, karar veremez', () async {
      final id = await quotedOrder();
      final o = await approveQuote(id);
      final d = await api.ok(
        'muhasebe',
        'GET',
        'approvals/${financeApprovalOf(o)}',
      );
      final r = await api.send(
        'muhasebe',
        'POST',
        'approvals/${financeApprovalOf(o)}/decide',
        body: {'decision': 1, 'concurrencyToken': d.str('concurrencyToken')},
      );
      expect(r.status, greaterThanOrEqualTo(400));
    });
  });

  group('Satış müdürü tam yetkili', () {
    test(
      'sipariş finansını onaylar, limit değiştirir, tüm sayfaları açar',
      () async {
        final id = await quotedOrder();
        final o = await approveQuote(id);
        await decide('satis', financeApprovalOf(o), 1);
        expect(w.order(id)!['status'], 3);
        await api.ok(
          'satis',
          'POST',
          'stations/me/customers/101/limit-requests',
          body: {
            'limitPeriod': 'Aylık',
            'limitType': 'Tutar',
            'limitAmount': 444000,
            'reason': 'Alım hacmi arttı',
          },
        );
        final summary = await api.ok(
          'satis',
          'GET',
          'bayi/customers/101/summary',
        );
        expect(summary.obj('limit').decOrNull('amount'), 444000);
        final satis = findFakePersona('satis')!;
        final sahip = findFakePersona('sahip')!;
        expect(satis.pages.toSet(), sahip.pages.toSet());
        for (final code in sahip.capabilities.keys) {
          expect(satis.capabilities.containsKey(code), isTrue, reason: code);
        }
      },
    );
  });

  group('yalnızca sipariş finans onayı', () {
    test('limit ve yeni cari onayı listede görünmez', () {
      final store = A5FakeStore.of(w);
      final p = findFakePersona('finans')!;
      for (final a in w.approvals) {
        if (const {2, 5, 6}.contains(a['type'])) {
          expect(store.visible(p, a), isFalse, reason: 'talep ${a['id']}');
        }
      }
    });
  });

  group('limit değişikliği onaysız', () {
    Map<String, Object?> body(double amount) => {
      'limitPeriod': 'Aylık',
      'limitType': 'Tutar',
      'limitAmount': amount,
      'reason': 'Alım hacmi arttı',
    };

    test(
      'Finans birimi limiti hemen değiştirir; onay talebi açılmaz',
      () async {
        final before = w.approvals.where((a) => a['type'] == 2).length;
        await api.ok(
          'finans',
          'POST',
          'stations/me/customers/101/limit-requests',
          body: body(777000),
        );

        final summary = await api.ok(
          'finans',
          'GET',
          'bayi/customers/101/summary',
        );
        expect(summary.obj('limit').decOrNull('amount'), 777000);
        expect(summary.objOrNull('pendingLimitRequest'), isNull);
        expect(w.approvals.where((a) => a['type'] == 2).length, before);
        expect(summary.obj('actions').boolean('limitChangeDirect'), isTrue);
      },
    );

    test('Bayi yöneticisi (ana hesap) değiştirebilir', () async {
      await api.ok(
        'sahip',
        'POST',
        'stations/me/customers/101/limit-requests',
        body: body(555000),
      );
      final summary = await api.ok(
        'sahip',
        'GET',
        'bayi/customers/101/summary',
      );
      expect(summary.obj('limit').decOrNull('amount'), 555000);
    });

    test('yetkisi olmayan değiştiremez, düğme de açılmaz', () async {
      final r = await api.send(
        'muhasebe',
        'POST',
        'stations/me/customers/101/limit-requests',
        body: body(999000),
      );
      expect(r.status, greaterThanOrEqualTo(400));
      final summary = await api.ok(
        'muhasebe',
        'GET',
        'bayi/customers/101/summary',
      );
      expect(summary.obj('actions').boolean('canRequestLimit'), isFalse);
    });
  });
}

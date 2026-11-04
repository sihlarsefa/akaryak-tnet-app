// Sahip kararı 02.11.2026 ("cari onayını sadece bayi tarafı yapsın, admin'e gerek yok"; "limiti de aynı
// şekilde"): limit talebi (tür 2) ve yeni cari finans onayı (tür 6) bayide karara bağlanır, merkez
// yalnızca izler. Uygulama tarafı: yetkinlik kataloğu (`approve.finance.limit`, finans birimi), sahte
// dünyada yönlendirme (Finans birimi ve Bayi yöneticisi; birim onaycısı varsa yalnızca o), Onaylar'da
// görünme, açılma ve karar, kararın cari kartına geçmesi; bu türlerde bayi kullanıcısına "merkez" sözü
// yok. Sahte sunucuya doğrudan istek atılır (uygulamanın ağ katmanı yalnızca ekran testlerinde).
import 'package:akaryakitnet/core/auth/permissions.dart';
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/network/fake/core_fakes.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/features/approvals/approvals_fake.dart';
import 'package:akaryakitnet/features/bayi/bayi_fake.dart';
import 'package:akaryakitnet/features/bayi/fake/customers_fake.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/approvals/a5_test_kit.dart';

/// Sahte sunucuya doğrudan istek: persona başına belirteç (merkezin SMS kodu gerekmez).
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

  Future<JsonReader> detail(String key, int id) =>
      ok(key, 'GET', 'approvals/$id');

  /// Bende (kararı ya da yanıtı beklenen talepler).
  Future<List<int>> bende(String key) async => (await ok(
    key,
    'GET',
    'approvals',
    query: const {'scope': '0', 'pageSize': '100'},
  )).list('items', (r) => r.integer('id'));

  Future<JsonReader> requestLimit(
    String key,
    int customerId,
    Map<String, Object?> body,
  ) => ok(
    key,
    'POST',
    'stations/me/customers/$customerId/limit-requests',
    body: body,
  );
}

FakeServer _server({bool v5 = true}) {
  final s = FakeServer.forTests(world: FakeWorld.seeded(v5Station: v5));
  registerCoreFakes(s);
  registerApprovalsFakes(s);
  registerBayiFakes(s);
  return s;
}

/// Son açılan limit talebi onayının kimliği.
int _lastLimitApproval(FakeWorld w) =>
    w.approvals.lastWhere((a) => a['type'] == 2)['id'] as int;

/// JSON'daki bütün metinler ("merkez" taraması için).
Iterable<String> _texts(Object? v) sync* {
  if (v is String) yield v;
  if (v is Map) {
    for (final x in v.values) {
      yield* _texts(x);
    }
  }
  if (v is List) {
    for (final x in v) {
      yield* _texts(x);
    }
  }
}

Iterable<String> _mentionsHq(JsonReader r) =>
    _texts(r.raw).where((t) => t.toLowerCase().contains('merkez'));

Map<String, String> _facts(JsonReader detail) => {
  for (final f in detail.obj('summary').list('facts', (r) => r))
    f.str('label'): f.str('value'),
};

const _hint = 'Kendi talebinizi onaylayamazsınız.';
const _designee = 'Bu birimin onaycısı Can Öztürk; talebi o onaylar.';

void main() {
  // Eski onay akışı (finans teklifden önce, limit talebi onayda): `FakeWorld.firstStageApprovals` kapalı.
  setUpAll(() => FakeWorld.defaultFirstStageApprovals = false);

  group('katalog: approve.finance.limit (Limit talebi onayı)', () {
    test(
      'bayiye verilebilir, finans biriminin kodu; eski merkez kodu birimsiz',
      () {
        expect(Caps.approveFinanceLimit, 'approve.finance.limit');
        expect(Caps.bayiAssignable, contains(Caps.approveFinanceLimit));
        expect(Caps.all, contains(Caps.approveFinanceLimit));
        expect(
          ApproverUnits.unitOf(Caps.approveFinanceLimit),
          ApproverUnits.finance,
        );
        expect(
          ApproverUnits.capabilitiesOf(ApproverUnits.finance),
          contains(Caps.approveFinanceLimit),
        );
        expect(ApproverUnits.unitOf(Caps.approveLimitHq), isNull);
        expect(
          FakeWorld.approvalCapability(const {'type': 2}),
          Caps.approveFinanceLimit,
        );
      },
    );

    test(
      'Finans birimi ve Bayi yöneticisi taşır; pasif şablonlar dondurulmuş',
      () {
        final t = FakeRoleTemplates.capabilities;
        expect(
          t[BayiRoleCodes.financeManager],
          containsPair(Caps.approveFinanceLimit, null),
        );
        expect(
          t[BayiRoleCodes.owner],
          containsPair(Caps.approveFinanceLimit, null),
        );
        for (final code in [
          BayiRoleCodes.manager,
          BayiRoleCodes.financeSpecialist,
        ]) {
          expect(
            t[code]!.containsKey(Caps.approveFinanceLimit),
            isFalse,
            reason: code,
          );
        }
        bool holds(String key) => findFakePersona(
          key,
        )!.capabilities.containsKey(Caps.approveFinanceLimit);
        expect(holds('finans'), isTrue);
        expect(holds('sahip'), isTrue);
        expect(holds('mudur'), isFalse);
        expect(holds('finansuzman'), isFalse);
      },
    );

    test('birim onaycısı varsa yalnızca o imzalar; yoksa taşıyan herkes', () {
      final sahip = findFakePersona('sahip')!;
      final finans = findFakePersona('finans')!;
      final v5 = FakeWorld.seeded();
      expect(v5.signsStep(finans, Caps.approveFinanceLimit), isTrue);
      expect(v5.signsStep(sahip, Caps.approveFinanceLimit), isFalse);
      expect(
        v5.blockingApprover(sahip, Caps.approveFinanceLimit)?.key,
        'finans',
      );
      List<String> signing(String key) => [
        for (final c
            in (v5.meAccess(findFakePersona(key)!)['signingCapabilities']
                as List))
          (c as Map)['code'] as String,
      ];
      expect(signing('finans'), contains(Caps.approveFinanceLimit));
      expect(signing('sahip'), isNot(contains(Caps.approveFinanceLimit)));
      final legacy = FakeWorld.seeded(v5Station: false);
      expect(legacy.signsStep(sahip, Caps.approveFinanceLimit), isTrue);
    });
  });

  group('sahte dünya: limit talebi bayinin Finans biriminde', () {
    test(
      'Bayi yöneticisi ister → Finans birimi Bende\'de görür, açar, onaylar → limit cari kartına geçer',
      () async {
        final s = _server();
        final api = _Direct(s);
        final created = await api.requestLimit('sahip', 101, {
          'limitPeriod': 'Aylık',
          'limitType': 'Tutar',
          'limitAmount': 3000000,
          'reason': 'Kış dönemi tüketim artışı',
        });
        expect(created.decOrNull('requestedLimitAmount'), 3000000);
        final id = _lastLimitApproval(s.world);
        expect(id, greaterThan(9013), reason: 'seed kimlikleriyle çakışmaz');
        final a = s.world.approval(id)!;
        expect(a['customerId'], 101);
        expect(a['requestedByUserId'], 'u-sahip');
        expect(a['eligibleUserIds'], containsAll(['u-finans', 'u-sahip']));
        expect(a['eligibleUserIds'], isNot(contains('u-merkez')));

        // Finans birimi: Bende'de, karar çubuğu Onayla / Reddet, ayrıntı, bildirim.
        expect(await api.bende('finans'), contains(id));
        final d = await api.detail('finans', id);
        expect(d.ints('modes'), [1, 4]);
        expect(d.strOrNull('decisionHint'), isNull);
        expect(
          d.list('steps', (r) => (r.str('name'), r.str('capabilityCode'))),
          [('Finans birimi', Caps.approveFinanceLimit)],
        );
        expect(
          d.obj('summary').str('subline'),
          'Limit değişikliği talebi · bayi Finans birimi onayı',
        );
        final facts = _facts(d);
        expect(facts['Cari'], 'Anadolu Lojistik A.Ş.');
        expect(facts['Mevcut limit'], 'Aylık 2.500.000 ₺');
        expect(facts['Talep edilen limit'], 'Aylık 3.000.000 ₺');
        expect(
          facts['Geçerli dönem kullanımı'],
          '1.180.000 ₺ / 2.500.000 ₺ · %47 · Aylık',
        );
        expect(facts['Gerekçe'], 'Kış dönemi tüketim artışı');
        expect(facts['Talep eden'], 'Mehmet Demir');
        expect(
          d.obj('summary').obj('links').intOrNull('stationCustomerId'),
          501,
        );
        expect(_mentionsHq(d), isEmpty);
        bool notified(String user) => s.world.notifications.any(
          (n) => n['userId'] == user && n['route'] == '/approvals/$id',
        );
        expect(notified('u-finans'), isTrue);
        expect(notified('u-sahip'), isFalse, reason: 'talep eden');
        expect(notified('u-merkez'), isFalse);

        // Talep eden kendi talebini onaylamaz; merkez karar veremez (yalnızca izler).
        final own = await api.detail('sahip', id);
        expect(own.ints('modes'), isEmpty);
        expect(own.str('decisionHint'), _hint);
        expect(_mentionsHq(own), isEmpty);
        expect(await api.bende('sahip'), isNot(contains(id)));
        final hq = await api.detail('merkez', id);
        expect(hq.ints('modes'), isEmpty);
        final hqTry = await api.send(
          'merkez',
          'POST',
          'approvals/$id/decide',
          body: {'decision': 1, 'concurrencyToken': hq.str('concurrencyToken')},
        );
        expect(hqTry.status, greaterThanOrEqualTo(400));

        // Finans onaylar: talep kapanır, limit cari kartına geçer, yeni talep açılabilir.
        final r = await api.ok(
          'finans',
          'POST',
          'approvals/$id/decide',
          body: {'decision': 1, 'concurrencyToken': d.str('concurrencyToken')},
        );
        expect(r.boolean('isFinal'), isTrue);
        final card = await api.ok('sahip', 'GET', 'bayi/customers/101/summary');
        expect(card.obj('limit').decOrNull('amount'), 3000000);
        expect(card.objOrNull('pendingLimitRequest'), isNull);
        expect(card.obj('actions').boolean('canRequestLimit'), isTrue);
        final list = await api.ok('sahip', 'GET', 'bayi/customers');
        final row = list
            .list('items', (r) => r)
            .firstWhere((r) => r.integer('customerId') == 101);
        expect(row.decOrNull('limitUsagePct'), closeTo(39.3, 0.1));
      },
    );

    test(
      'ret: gerekçe zorunlu; limit değişmez, bekleyen talep kalkar',
      () async {
        final s = _server();
        final api = _Direct(s);
        await api.requestLimit('sahip', 103, {
          'limitPeriod': 'Aylık',
          'limitType': 'Litre',
          'limitAmount': 400000,
          'reason': 'Hasat dönemi',
        });
        final id = _lastLimitApproval(s.world);
        expect(s.world.approval(id)!['liters'], 400000);
        final d = await api.detail('finans', id);
        final facts = _facts(d);
        expect(facts['Mevcut limit'], 'Aylık 300.000 L');
        expect(facts['Talep edilen limit'], 'Aylık 400.000 L');
        final noNote = await api.send(
          'finans',
          'POST',
          'approvals/$id/decide',
          body: {'decision': 4, 'concurrencyToken': d.str('concurrencyToken')},
        );
        expect(noNote.status, greaterThanOrEqualTo(400));
        await api.ok(
          'finans',
          'POST',
          'approvals/$id/decide',
          body: {
            'decision': 4,
            'note': 'Hasat verisi yetersiz.',
            'concurrencyToken': d.str('concurrencyToken'),
          },
        );
        final card = await api.ok('sahip', 'GET', 'bayi/customers/103/summary');
        expect(card.obj('limit').decOrNull('amount'), 300000);
        expect(card.objOrNull('pendingLimitRequest'), isNull);
      },
    );

    test(
      'birim onaycısı: başkasının talebinde Bayi yöneticisi değil Finans birimi imzalar',
      () async {
        final s = _server();
        final api = _Direct(s);
        await api.requestLimit('mudur', 104, {
          'limitPeriod': 'Aylık',
          'limitType': 'Tutar',
          'limitAmount': 900000,
          'reason': 'Filo büyüdü',
        });
        final id = _lastLimitApproval(s.world);
        expect((await api.detail('finans', id)).ints('modes'), [1, 4]);
        expect((await api.detail('sahip', id)).ints('modes'), isEmpty);
        expect(await api.bende('sahip'), isNot(contains(id)));
        bool notified(String user) => s.world.notifications.any(
          (n) => n['userId'] == user && n['route'] == '/approvals/$id',
        );
        expect(notified('u-finans'), isTrue);
        expect(notified('u-sahip'), isFalse, reason: 'onaycı finans');
      },
    );

    test(
      'birim onaycısı olmayan bayide Finans birimi ve Bayi yöneticisi karar verir',
      () async {
        final s = _server(v5: false);
        final api = _Direct(s);
        await api.requestLimit('mudur', 104, {
          'limitPeriod': 'Aylık',
          'limitType': 'Tutar',
          'limitAmount': 900000,
          'reason': 'Filo büyüdü',
        });
        final id = _lastLimitApproval(s.world);
        for (final key in ['finans', 'sahip']) {
          expect((await api.detail(key, id)).ints('modes'), [
            1,
            4,
          ], reason: key);
          expect(await api.bende(key), contains(id), reason: key);
        }
        expect((await api.detail('merkez', id)).ints('modes'), isEmpty);
      },
    );

    test(
      'tohum: Marmara İnşaat\'ın bekleyen talebi 9010\'a bağlı; karar cari kartına geçer',
      () async {
        final s = _server();
        final api = _Direct(s);
        final before = await api.ok(
          'sahip',
          'GET',
          'bayi/customers/102/summary',
        );
        expect(before.obj('pendingLimitRequest').decOrNull('amount'), 1500000);
        await api.ok('finans', 'GET', 'approvals/badge'); // A5 deposu: 9010
        final a = s.world.approval(9010)!;
        expect((a['type'], a['customerId'], a['amount']), (2, 102, 1500000));
        // 9010 bayinin Finans birimindedir: Bende'de görünür, talep eden (sahip) imzalamaz, merkez
        // yalnızca izler (merkezin açması günlüğe "Görüntülendi" yazar: "merkez" taramasından sonra).
        expect(await api.bende('finans'), contains(9010));
        expect(await api.bende('sahip'), isNot(contains(9010)));
        expect(_mentionsHq(await api.detail('finans', 9010)), isEmpty);
        expect((await api.detail('merkez', 9010)).ints('modes'), isEmpty);
        final d = await api.detail('finans', 9010);
        expect(d.ints('modes'), [1, 4]);
        final r = await api.ok(
          'finans',
          'POST',
          'approvals/9010/decide',
          body: {'decision': 1, 'concurrencyToken': d.str('concurrencyToken')},
        );
        expect(r.boolean('isFinal'), isTrue);
        final after = await api.ok(
          'sahip',
          'GET',
          'bayi/customers/102/summary',
        );
        expect(after.obj('limit').decOrNull('amount'), 1500000);
        expect(after.objOrNull('pendingLimitRequest'), isNull);
      },
    );
  });

  group('sahte dünya: yeni cari onayı bayide', () {
    test(
      'Finans birimi Bende\'de görür ve karar verir; Bayi yöneticisine onaycı ipucu; merkez izler',
      () async {
        final s = _server();
        final api = _Direct(s);
        expect(await api.bende('finans'), contains(9007));
        final d = await api.detail('finans', 9007);
        expect(d.ints('modes'), [1, 2, 3, 4]);
        expect(
          d.obj('conditionForm').list('fields', (r) => r.str('key')),
          contains('limitAmount'),
        );
        expect(_mentionsHq(d), isEmpty);
        expect(await api.bende('sahip'), isNot(contains(9007)));
        final owner = await api.detail('sahip', 9007);
        expect(owner.ints('modes'), isEmpty);
        expect(owner.str('decisionHint'), _designee);
        expect((await api.detail('merkez', 9007)).ints('modes'), isEmpty);
        final r = await api.ok(
          'finans',
          'POST',
          'approvals/9007/decide',
          body: {'decision': 1, 'concurrencyToken': d.str('concurrencyToken')},
        );
        expect(r.boolean('isFinal'), isTrue);
      },
    );

    test(
      'birim onaycısı olmayan bayide Bayi yöneticisi de karar verir',
      () async {
        final s = _server(v5: false);
        final api = _Direct(s);
        expect(await api.bende('sahip'), contains(9007));
        final d = await api.detail('sahip', 9007);
        expect(d.ints('modes'), [1, 2, 3, 4]);
        expect(_mentionsHq(d), isEmpty);
      },
    );
  });

  group('Onaylar ekranı', () {
    const tall = Size(412, 1600);

    testWidgets(
      'finans: yeni cari Bende\'de, açılır, karar çubuğu, onaylanır; "merkez" yok',
      (tester) async {
        final app = await pumpA5(
          tester,
          persona: 'finans',
          location: '/approvals',
          size: tall,
        );
        expect(find.text('Doğu Marmara Gıda San. A.Ş.'), findsOneWidget);
        expect(find.textContaining('erkez'), findsNothing);
        await tapText(tester, 'Doğu Marmara Gıda San. A.Ş.');
        expect(find.text('Onayla'), findsOneWidget);
        expect(find.text('Reddet'), findsOneWidget);
        // Koşullu onay ve ek bilgi: rıhtımda ya da "Diğer kararlar"da (yerleşim yazı boyutuna göre).
        final inline = find.text('Koşullu onayla').evaluate().isNotEmpty;
        expect(
          inline ? find.text('Ek bilgi iste') : find.text('Diğer'),
          findsOneWidget,
        );
        expect(find.textContaining('erkez'), findsNothing);
        await tapText(tester, 'Onayla');
        await tapText(tester, 'Onayla', last: true);
        expect(find.text('Talep onaylandı.'), findsOneWidget);
        final req = app.log.last('POST', 'approvals/9007/decide')!;
        expect((req.data as Map)['decision'], 1);
        await finish(tester);
      },
    );

    testWidgets(
      'finans: Bayi yöneticisinin limit talebi Bende\'de; ayrıntı, Onayla / Reddet; reddedilir',
      (tester) async {
        final app = await pumpA5(
          tester,
          persona: 'finans',
          location: '/home',
          size: tall,
        );
        registerBayiCustomerFakes(app.server);
        final api = _Direct(app.server);
        await tester.runAsync(
          () => api.requestLimit('sahip', 101, {
            'limitPeriod': 'Aylık',
            'limitType': 'Tutar',
            'limitAmount': 3000000,
            'reason': 'Kış dönemi tüketim artışı',
          }),
        );
        final id = _lastLimitApproval(app.server.world);
        app.router.go('/approvals');
        await pumpFor(tester);
        expect(find.text('Anadolu Lojistik A.Ş.'), findsOneWidget);
        expect(find.textContaining('Limit talebi'), findsWidgets);
        expect(find.textContaining('erkez'), findsNothing);
        await tapText(tester, 'Anadolu Lojistik A.Ş.');
        for (final label in [
          'Mevcut limit',
          'Geçerli dönem kullanımı',
          'Gerekçe',
          'Talep eden',
        ]) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
        expect(find.text('Talep edilen limit'), findsWidgets);
        expect(find.text('Kış dönemi tüketim artışı'), findsWidgets);
        expect(find.text('Onayla'), findsOneWidget);
        expect(find.text('Reddet'), findsOneWidget);
        expect(find.text('Diğer'), findsNothing, reason: 'yalnızca iki karar');
        expect(find.textContaining('erkez'), findsNothing);
        await tapText(tester, 'Reddet');
        await typeInto(tester, 'Ret gerekçesi', 'Teminat yetersiz.');
        await tapText(tester, 'Reddet', last: true);
        expect(find.text('Talep reddedildi.'), findsOneWidget);
        final req = app.log.last('POST', 'approvals/$id/decide')!;
        expect((req.data as Map)['decision'], 4);
        expect(app.server.world.approval(id)!['status'], 2);
        await finish(tester);
      },
    );

    testWidgets('sahip: kendi limit talebinde karar çubuğu yok, neden yazılı', (
      tester,
    ) async {
      final app = await pumpA5(
        tester,
        persona: 'sahip',
        location: '/home',
        size: tall,
      );
      registerBayiCustomerFakes(app.server);
      final api = _Direct(app.server);
      await tester.runAsync(
        () => api.requestLimit('sahip', 101, {
          'limitPeriod': 'Limitsiz',
          'reason': 'Kurumsal sözleşme',
        }),
      );
      app.router.go('/approvals/${_lastLimitApproval(app.server.world)}');
      await pumpFor(tester);
      expect(find.text(_hint), findsOneWidget);
      expect(find.text('Onayla'), findsNothing);
      expect(find.text('Reddet'), findsNothing);
      expect(find.textContaining('erkez'), findsNothing);
      await finish(tester);
    });

    testWidgets('sahip: yeni cari onayında onaycı ipucu, karar çubuğu yok', (
      tester,
    ) async {
      await pumpA5(
        tester,
        persona: 'sahip',
        location: '/approvals/9007',
        size: tall,
      );
      expect(find.text(_designee), findsOneWidget);
      expect(find.text('Onayla'), findsNothing);
      expect(find.textContaining('erkez'), findsNothing);
      await finish(tester);
    });

    testWidgets('merkez: yeni cari onayını izler, karar çubuğu yok', (
      tester,
    ) async {
      await pumpA5(
        tester,
        persona: 'merkez',
        location: '/approvals/9007',
        size: tall,
      );
      expect(find.text('Doğu Marmara Gıda San. A.Ş.'), findsWidgets);
      expect(find.text('Onayla'), findsNothing);
      expect(find.text('Reddet'), findsNothing);
      await finish(tester);
    });
  });
}

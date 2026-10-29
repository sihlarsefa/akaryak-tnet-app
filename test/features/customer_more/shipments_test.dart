import 'package:akaryakitnet/core/auth/permissions.dart';
import 'package:akaryakitnet/core/models/enums.dart';
import 'package:akaryakitnet/core/network/fake/fake_parity.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/offline/connectivity.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/core/utils/format.dart';
import 'package:akaryakitnet/features/customer_more/copy.dart';
import 'package:akaryakitnet/features/customer_more/data/customer_more_repository.dart';
import 'package:akaryakitnet/features/customer_more/presentation/shipments/shipment_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cm_test_utils.dart';

void main() {
  /// Tohumdaki "Kabul bekliyor" sevkiyatı (müşteri 101, 11.950 / 12.000 L, IRS-778812).
  int reportedId(CmEnv env) =>
      env.world.shipments.firstWhere((s) => s['status'] == 2)['id'] as int;

  test(
    'liste müşterinin teslimatlarını ve durum sayaçlarını getirir',
    () async {
      final env = await CmEnv.create();
      addTearDown(env.dispose);
      final repo = env.container.read(customerMoreRepositoryProvider);
      final page = await repo.shipments(const ShipmentQuery());
      expect(page.items, isNotEmpty);
      expect(page.items.every((s) => s.customerId == 101), isTrue);
      expect(page.items.every((s) => s.driverUserId == null), isTrue);
      expect(page.counts.reported, 1);
      final reported = await repo.shipments(
        const ShipmentQuery(statuses: [ShipmentStatus.reported]),
      );
      expect(reported.items.single.deliveryDocumentNo, 'IRS-778812');
      expect(page.counts.all, page.totalFiltered);
    },
  );

  testWidgets(
    'teslim kanıtı kartı: litre, irsaliye no, teslim alan, fotoğraf ve imza',
    (tester) async {
      final env = (await tester.runAsync(CmEnv.create))!;
      addTearDown(env.dispose);
      final id = reportedId(env);
      await pumpCmApp(tester, env, location: '/shipments/$id');
      await pumpFor(tester, const Duration(seconds: 1));

      expect(find.text(CmCopy.proofTitle), findsOneWidget);
      expect(find.byType(ProofCard), findsOneWidget);
      // Teslim edilen litre plakada (tek plaka), sipariş ve fark okumalarda.
      expect(find.byType(DeliveredPlate), findsOneWidget);
      expect(find.byType(AknPlate), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          RegExp(
            '^Teslim edilen ${Fmt.liters(11950)}, '
            'sipariş ${Fmt.liters(12000)}, fark eksi ${Fmt.liters(50)}',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('IRS-778812'), findsOneWidget);
      expect(find.text('Kemal Uçar'), findsOneWidget);
      expect(find.text('Teslimat fotoğrafları'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Teslimat fotoğrafı')),
        findsNWidgets(2),
      );
      expect(find.bySemanticsLabel('Teslim imzası'), findsOneWidget);
      expect(find.text('Teslimatı onayla'), findsOneWidget);
      expect(find.text('İtiraz et'), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets('kabul: onay sayfası, Idempotency-Key, durum "Teslim alındı"', (
    tester,
  ) async {
    final env = (await tester.runAsync(CmEnv.create))!;
    addTearDown(env.dispose);
    final id = reportedId(env);
    await pumpCmApp(tester, env, location: '/shipments/$id');
    await pumpFor(tester, const Duration(seconds: 1));

    await tester.tap(find.text('Teslimatı onayla'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text(CmCopy.acceptConfirmTitle), findsOneWidget);
    await tester.tap(find.widgetWithText(AknButton, 'Onayla').last);
    await pumpFor(tester, const Duration(seconds: 2));

    final accept = env.requests.singleWhere(
      (r) => r.method == 'POST' && r.path == 'shipments/$id/accept',
    );
    expect(accept.idempotencyKey, isNotNull);
    expect(RegExp(r'^[0-9a-f-]{36}$').hasMatch(accept.idempotencyKey!), isTrue);
    expect(env.world.shipment(id)!['status'], 3);
    expect(find.text(CmCopy.accepted), findsOneWidget);
    expect(find.text('Teslimatı onayla'), findsNothing);
    await finish(tester);
  });

  testWidgets(
    'kabul zaman aşımına uğrasa da sunucu işlediyse başarı (yeniden okuma)',
    (tester) async {
      final env = (await tester.runAsync(CmEnv.create))!;
      addTearDown(env.dispose);
      final id = reportedId(env);
      // İstek sunucuda işlenir ama yanıt kaybolur (zaman aşımı).
      env.harness.server.post('shipments/{id:int}/accept', (req) {
        env.world.shipment(id)!['status'] = 3;
        throw FakeResponse.problem(500, 'server_error', 'zaman aşımı');
      });
      await pumpCmApp(tester, env, location: '/shipments/$id');
      await pumpFor(tester, const Duration(seconds: 1));
      await tester.tap(find.text('Teslimatı onayla'));
      await pumpFor(tester, const Duration(milliseconds: 600));
      await tester.tap(find.widgetWithText(AknButton, 'Onayla').last);
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.text(CmCopy.accepted), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets(
    'itiraz: önce itiraz fotoğrafı yüklenir, sonra itiraz gönderilir, sonuç mesajı',
    (tester) async {
      final env = (await tester.runAsync(CmEnv.create))!;
      addTearDown(env.dispose);
      final id = reportedId(env);
      await pumpCmApp(tester, env, location: '/shipments/$id');
      await pumpFor(tester, const Duration(seconds: 1));

      await tester.tap(find.text('İtiraz et'));
      await pumpFor(tester, const Duration(milliseconds: 800));
      expect(find.text('Teslimata itiraz et'), findsOneWidget);

      await tester.tap(find.text('Galeriden seç'));
      await pumpFor(tester, const Duration(milliseconds: 800));
      await tester.enterText(
        find.byType(TextField).last,
        'Eksik miktar: sayaç 11.900 L gösteriyor.',
      );
      await pumpFor(tester, const Duration(milliseconds: 300));
      await tester.tap(find.text('İtirazı gönder'));
      await pumpFor(tester, const Duration(seconds: 2));

      final upload = env.requests.indexWhere(
        (r) => r.method == 'POST' && r.path == 'attachments',
      );
      final dispute = env.requests.indexWhere(
        (r) => r.method == 'POST' && r.path == 'shipments/$id/dispute',
      );
      expect(upload, greaterThanOrEqualTo(0));
      expect(dispute, greaterThan(upload), reason: 'fotoğraf önce yüklenir');
      expect(env.requests[upload].idempotencyKey, isNotNull);
      expect(env.requests[dispute].idempotencyKey, isNotNull);

      final photos = env.world.attachments.where(
        (a) => a['ownerType'] == 10 && a['ownerId'] == id && a['kind'] == 32,
      );
      expect(photos, hasLength(1));
      expect(env.world.shipment(id)!['status'], 4);
      expect(env.world.shipment(id)!['disputeNote'], contains('Eksik miktar'));
      expect(find.text(CmCopy.disputeSent), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets('çevrimdışıyken kabul ve itiraz kapalı', (tester) async {
    final env = (await tester.runAsync(
      () =>
          CmEnv.create(overrides: [isOnlineProvider.overrideWithValue(false)]),
    ))!;
    addTearDown(env.dispose);
    final id = reportedId(env);
    await pumpCmApp(tester, env, location: '/shipments/$id');
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text(CmCopy.offlineAction), findsOneWidget);
    final accept = tester.widget<AknButton>(
      find.widgetWithText(AknButton, 'Teslimatı onayla'),
    );
    expect(accept.onPressed, isNull);
    final dispute = tester.widget<AknButton>(
      find.widgetWithText(AknButton, 'İtiraz et'),
    );
    expect(dispute.onPressed, isNull);
    await finish(tester);
  });

  // Panel eşitliği (web müşteri sipariş ayrıntısı): teslimatı kabul eden şirket rolü değil Sevkiyatlar
  // "Düzenler" yetkisidir. Talep eden de kabul eder (bant ve satır sıra sizde); yetkisi olmayanın bandı
  // "onay bekliyor" der. Sunucunun `canAcceptDelivery` değeri olsa da olmasa da (eski API) aynı.
  for (final fields in [true, false]) {
    final api = fields ? 'yeni API' : 'eski API, alanlar yok';

    testWidgets(
      'talep ($api): bant ve satır "Teslimatı onaylayın" sıra sizde',
      (tester) async {
        final env = (await tester.runAsync(
          () => CmEnv.create(persona: 'talep'),
        ))!;
        addTearDown(env.dispose);
        FakeParity.set(env.world, value: fields);
        await pumpCmApp(tester, env, location: '/shipments');
        await pumpFor(tester, const Duration(seconds: 1));
        expect(find.text('1 ${CmCopy.awaitingBanner}'), findsOneWidget);
        expect(find.text('Teslimatı onaylayın'), findsOneWidget);
        await finish(tester);
      },
    );

    testWidgets(
      'talep, Sevkiyatlar "Düzenler" yok ($api): bant "onay bekliyor"; satırda sıra sizde yok',
      (tester) async {
        final p = findFakePersona('talep')!;
        const grant = '${Pg.customerShipments}:${Perm.edit}';
        final had = p.pages.remove(grant);
        addTearDown(() {
          if (had) p.pages.add(grant);
        });
        final env = (await tester.runAsync(
          () => CmEnv.create(persona: 'talep'),
        ))!;
        addTearDown(env.dispose);
        FakeParity.set(env.world, value: fields);
        await pumpCmApp(tester, env, location: '/shipments');
        await pumpFor(tester, const Duration(seconds: 1));
        expect(find.text('1 teslimat onay bekliyor'), findsOneWidget);
        expect(find.text('Teslimatı onaylayın'), findsNothing);
        await finish(tester);
      },
    );
  }
}

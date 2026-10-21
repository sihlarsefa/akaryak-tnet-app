import 'dart:io';

import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/offline/outbox_op.dart';
import 'package:akaryakitnet/core/offline/outbox_providers.dart';
import 'package:akaryakitnet/core/offline/outbox_store.dart';
import 'package:akaryakitnet/features/driver/application/driver_lists.dart';
import 'package:akaryakitnet/features/driver/application/driver_ops.dart';
import 'package:akaryakitnet/features/driver/data/deliver_draft.dart';
import 'package:akaryakitnet/features/driver/data/driver_models.dart';
import 'package:akaryakitnet/features/driver/data/driver_outbox.dart';
import 'package:akaryakitnet/features/driver/data/driver_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/driver_harness.dart';

/// İşlem [id] bitene (done / needsAttention / failed) kadar bekler.
Future<OutboxOp> waitOp(
  ProviderContainer c,
  String id, {
  Set<OutboxStatus> until = const {
    OutboxStatus.done,
    OutboxStatus.needsAttention,
    OutboxStatus.failed,
  },
}) async {
  final store = c.read(outboxStoreProvider);
  for (var i = 0; i < 400; i++) {
    final op = await store.get(id);
    if (op != null && until.contains(op.status)) return op;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  return (await store.get(id))!;
}

/// İlk teslim yanıtını sunucu işledikten sonra "zaman aşımı"na çevirir (yanıt kayboldu).
class _LoseFirstDeliverResponse extends Interceptor {
  int lost = 0;
  final keys = <String?>[];
  final replays = <String?>[];

  @override
  void onRequest(RequestOptions o, RequestInterceptorHandler h) {
    if (o.path.endsWith('/deliver')) {
      keys.add('${o.headers['Idempotency-Key']}');
    }
    h.next(o);
  }

  @override
  void onResponse(Response<dynamic> r, ResponseInterceptorHandler h) {
    if (r.requestOptions.path.endsWith('/deliver')) {
      replays.add(r.headers.value('idempotent-replay'));
      if (lost == 0) {
        lost++;
        h.reject(
          DioException.receiveTimeout(
            timeout: const Duration(seconds: 30),
            requestOptions: r.requestOptions,
          ),
        );
        return;
      }
    }
    h.next(r);
  }
}

void main() {
  late DriverHarness h;
  late ProviderContainer c;

  setUp(() async {
    h = await DriverHarness.create();
    c = h.container();
    await DriverHarness.login(c, 'sofor');
  });

  tearDown(() {
    c.dispose();
    h.dispose();
  });

  String photoFile(String name) {
    final f = File('${h.dir.path}/$name');
    f.writeAsBytesSync(sampleJpeg);
    return f.path;
  }

  Map<String, dynamic> shipment(int id) =>
      h.world.shipments.firstWhere((s) => s['id'] == id);

  int plannedTodayId() =>
      h.world.shipments.firstWhere(
            (s) => s['status'] == 0 && s['driverUserId'] == 'u-sofor',
          )['id']
          as int;

  int inTransitId() =>
      h.world.shipments.firstWhere(
            (s) => s['status'] == 1 && s['driverUserId'] == 'u-sofor',
          )['id']
          as int;

  DeliverDraft draft(
    int id, {
    String doc = 'IRS-1001',
    List<String> photos = const [],
    String? signature,
    SignatureWaiver? waiver,
  }) => DeliverDraft(
    shipmentId: id,
    code: DriverShipmentRow.shipmentCode(id),
    litersText: '7950',
    documentNo: doc,
    recipientName: 'Murat Kaya',
    note: 'Arka avlu tankı',
    photos: [for (final p in photos) DraftPhoto(path: p)],
    signaturePath: signature,
    waiver: waiver,
    savedAt: DateTime.now().toUtc(),
  );

  DriverPosition here() => DriverPosition(
    latitude: 40.7654,
    longitude: 29.9408,
    accuracyMeters: 9.5,
    capturedAt: DateTime.now().toUtc(),
  );

  group('Listeler (kapsamlar)', () {
    test(
      'Bugün: itirazlı en üstte, sonra yolda, sonra plan; kimse kaybolmaz',
      () async {
        final repo = c.read(driverRepositoryProvider);
        final today = await repo.fetchTab('u-sofor', DriverTab.today);
        final statuses = [for (final r in today.items) r.status];
        expect(statuses.first, ShipmentStatus.disputed);
        expect(statuses[1], ShipmentStatus.inTransit);
        expect(statuses, contains(ShipmentStatus.planned));
        expect(today.items.first.disputeNote, contains('5.650 L'));

        final upcoming = await repo.fetchTab('u-sofor', DriverTab.upcoming);
        expect(upcoming.items, isNotEmpty);
        expect(
          upcoming.items.every((r) => r.status == ShipmentStatus.planned),
          isTrue,
        );
        final history = await repo.fetchTab('u-sofor', DriverTab.history);
        final times = [for (final r in history.items) r.scheduledAt!];
        expect(
          times,
          orderedEquals([...times]..sort((a, b) => b.compareTo(a))),
        );
        expect(
          history.items.map((r) => r.status),
          everyElement(
            isIn([
              ShipmentStatus.reported,
              ShipmentStatus.accepted,
              ShipmentStatus.cancelled,
            ]),
          ),
        );
      },
    );

    test('Bugün, active kapsamındaki gecikmiş planları da gösterir', () async {
      final id = plannedTodayId();
      final s = shipment(id);
      // Plan dün olsun, hâlâ yola çıkılmamış.
      s['scheduledAt'] = s['scheduledAt'].toString().replaceFirstMapped(
        RegExp(r'^(\d{4})-(\d{2})-(\d{2})'),
        (m) {
          final d = DateTime.utc(
            int.parse(m[1]!),
            int.parse(m[2]!),
            int.parse(m[3]!),
          ).subtract(const Duration(days: 1));
          return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        },
      );
      final today = await c
          .read(driverRepositoryProvider)
          .fetchTab('u-sofor', DriverTab.today);
      final row = today.items.firstWhere((r) => r.id == id);
      expect(row.isOverdue(DateTime.now().toUtc()), isTrue);
    });

    test(
      'çevrimdışı: önbellekteki liste gösterilir (Son güncelleme)',
      () async {
        await c.read(driverListProvider(DriverTab.today).future);
        final c2 = h.container();
        addTearDown(c2.dispose);
        await DriverHarness.login(c2, 'sofor');
        h.server.failureMode = FakeFailureMode.offline;
        final s = await c2.read(driverListProvider(DriverTab.today).future);
        expect(s.items, isNotEmpty);
        expect(s.fromCache, isTrue);
        await c2.read(driverListProvider(DriverTab.today).notifier).refresh();
        final after = c2.read(driverListProvider(DriverTab.today)).value!;
        expect(after.items, isNotEmpty, reason: 'veri korunur');
        expect(after.refreshError, isNotNull);
      },
    );

    test(
      'bugünün açık teslimat ayrıntıları önbelleğe alınır; çevrimdışı açılır',
      () async {
        final today = await c.read(driverListProvider(DriverTab.today).future);
        final open = [
          for (final r in today.items)
            if (r.isOpen) r.id,
        ];
        expect(open, isNotEmpty);
        final repo = c.read(driverRepositoryProvider);
        for (var i = 0; i < 200; i++) {
          final all = await Future.wait(
            open.map((id) => repo.readDetail('u-sofor', id)),
          );
          if (all.every((d) => d != null)) break;
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        for (final id in open) {
          expect(
            await repo.readDetail('u-sofor', id),
            isNotNull,
            reason: '$id',
          );
        }
        h.server.failureMode = FakeFailureMode.offline;
        final s = await c.read(driverShipmentProvider(open.first).future);
        expect(s.detail.id, open.first);
        expect(s.cachedAt, isNotNull);
      },
    );

    test('başka şoförün sevkiyatı 404; sahibi kendine atananı görür', () async {
      final mine = plannedTodayId();
      final c2 = h.container(freshDevice: true);
      addTearDown(c2.dispose);
      await DriverHarness.login(c2, 'sahip');
      final repo = c2.read(driverRepositoryProvider);
      final active = await repo.fetchScope(DriverScope.active);
      expect(active.items, hasLength(1));
      expect(active.items.single.status, ShipmentStatus.planned);
      await expectLater(
        repo.fetchDetail('u-sahip', mine),
        throwsA(isA<Exception>()),
      );
      expect(await c2.read(driverAssignedCountProvider.future), 1);
    });
  });

  group('Yola çıkış ve teslim (bekleyen işlem)', () {
    test('çevrimiçi: yola çık → teslim (fotoğraf + imza yüklenir)', () async {
      final id = plannedTodayId();
      final commands = c.read(driverCommandsProvider);
      final start = await commands.start(
        shipmentId: id,
        code: DriverShipmentRow.shipmentCode(id),
        position: here(),
      );
      final s1 = await waitOp(c, start.id);
      expect(s1.status, OutboxStatus.done);
      expect(shipment(id)['status'], 1);
      expect(shipment(id)['dispatchLatitude'], 40.7654);

      final d = draft(
        id,
        photos: [photoFile('a.jpg'), photoFile('b.jpg')],
        signature: photoFile('s.png'),
      );
      final op = await commands.deliver(
        draft: d,
        liters: 7950,
        position: here(),
      );
      expect(op.files, hasLength(3));
      final done = await waitOp(c, op.id);
      expect(done.status, OutboxStatus.done, reason: done.lastError);
      final s = shipment(id);
      expect(s['status'], 2);
      expect(s['deliveredLiters'], 7950);
      expect(s['deliveryDocumentNo'], 'IRS-1001');
      expect(s['recipientName'], 'Murat Kaya');
      expect(s['timeSource'], 'device');
      final evidence = h.world.attachments
          .where((a) => a['ownerType'] == 10 && a['ownerId'] == id)
          .toList();
      expect(evidence.where((a) => a['kind'] == 30), hasLength(2));
      expect(evidence.where((a) => a['kind'] == 31), hasLength(1));
      // Dosyalar işlem bitince silinir.
      for (final f in op.files) {
        expect(File(f).existsSync(), isFalse);
      }
      // Ayrıntı önbelleği güncel.
      final cached = await c
          .read(driverRepositoryProvider)
          .readDetail('u-sofor', id);
      expect(cached?.detail.status, ShipmentStatus.reported);
    });

    test(
      'çevrimdışı → kuyrukta kalır; bağlantı gelince aynı anahtarla gider',
      () async {
        final id = inTransitId();
        h.server.failureMode = FakeFailureMode.offline;
        final op = await c
            .read(driverCommandsProvider)
            .deliver(
              draft: draft(
                id,
                photos: [photoFile('c.jpg')],
                signature: photoFile('c.png'),
              ),
              liters: 7950,
              position: here(),
            );
        final queued = await waitOp(c, op.id);
        expect(queued.status, OutboxStatus.failed);
        expect(queued.lastError, contains('İnternet bağlantısı yok'));
        expect(shipment(id)['status'], 1);

        h.server.failureMode = FakeFailureMode.none;
        await c.read(driverCommandsProvider).retry(op.id);
        final done = await waitOp(c, op.id);
        expect(done.status, OutboxStatus.done, reason: done.lastError);
        expect(done.idempotencyKey, op.idempotencyKey);
        expect(shipment(id)['status'], 2);
      },
    );

    test(
      'yanıt kaybolursa tekrar deneme sunucuda ikinci kez işlemez (idempotent)',
      () async {
        final id = inTransitId();
        final spy = _LoseFirstDeliverResponse();
        c.read(dioProvider).interceptors.add(spy);
        final before = h.world.notifications.length;
        final op = await c
            .read(driverCommandsProvider)
            .deliver(
              draft: draft(
                id,
                photos: [photoFile('d.jpg')],
                signature: photoFile('d.png'),
              ),
              liters: 7950,
              position: here(),
            );
        final first = await waitOp(c, op.id);
        expect(first.status, OutboxStatus.failed, reason: 'zaman aşımı geçici');
        expect(shipment(id)['status'], 2, reason: 'sunucu işledi');
        final notified = h.world.notifications.length;
        expect(notified, greaterThan(before));

        await c.read(driverCommandsProvider).retry(op.id);
        final done = await waitOp(c, op.id);
        expect(done.status, OutboxStatus.done);
        expect(spy.keys, hasLength(2));
        expect(spy.keys.toSet(), hasLength(1), reason: 'aynı Idempotency-Key');
        expect(spy.replays.last, 'true');
        expect(
          h.world.notifications.length,
          notified,
          reason: 'ikinci kez işlenmedi',
        );
        final photos = h.world.attachments.where(
          (a) => a['ownerType'] == 10 && a['ownerId'] == id && a['kind'] == 30,
        );
        expect(photos, hasLength(1), reason: 'fotoğraf yeniden yüklenmedi');
      },
    );

    test('teslim bekleyen yola çıkışa bağlanır ve sırayla gider', () async {
      final id = plannedTodayId();
      final commands = c.read(driverCommandsProvider);
      h.server.failureMode = FakeFailureMode.offline;
      final start = await commands.start(
        shipmentId: id,
        code: DriverShipmentRow.shipmentCode(id),
      );
      await waitOp(c, start.id);
      final deliver = await commands.deliver(
        draft: draft(
          id,
          photos: [photoFile('e.jpg')],
          signature: photoFile('f.png'),
        ),
        liters: 7950,
        position: here(),
      );
      expect(deliver.dependsOn, start.id);

      h.server.failureMode = FakeFailureMode.none;
      await commands.retry(start.id);
      await waitOp(c, start.id, until: const {OutboxStatus.done});
      await c.read(outboxRunnerProvider).runOnce();
      final done = await waitOp(c, deliver.id);
      expect(done.status, OutboxStatus.done, reason: done.lastError);
      expect(shipment(id)['status'], 2);
    });

    test(
      'imza alınamadı: konum yoksa sunucu reddeder (Düzelt); konumla gider',
      () async {
        final id = inTransitId();
        final commands = c.read(driverCommandsProvider);
        final noGps = await commands.deliver(
          draft: draft(
            id,
            photos: [photoFile('g.jpg')],
            waiver: const SignatureWaiver(SignatureWaiverReason.noRecipient),
          ),
          liters: 7950,
        );
        final rejected = await waitOp(c, noGps.id);
        expect(rejected.status, OutboxStatus.needsAttention);
        expect(
          rejected.lastError,
          'İmza alınamadığında en az bir teslim fotoğrafı ve teslim konumu gerekir.',
        );

        // "Düzelt": aynı değerlerle taslak; konum eklenip yeniden gönderilir, eski işlem kalkar.
        final fix = await commands.draftForFix(noGps.id);
        expect(fix, isNotNull);
        expect(fix!.fixOpId, noGps.id);
        expect(fix.waiver?.reason, SignatureWaiverReason.noRecipient);
        expect(
          fix.photos.single.publicId,
          isNotNull,
          reason: 'yüklenen fotoğraf korunur',
        );
        final again = await commands.deliver(
          draft: fix,
          liters: 7950,
          position: here(),
        );
        final done = await waitOp(c, again.id);
        expect(done.status, OutboxStatus.done, reason: done.lastError);
        expect(await c.read(outboxStoreProvider).get(noGps.id), isNull);
        final s = shipment(id);
        expect(s['signatureWaiverLabel'], 'Alıcı yok / tanka teslim');
        expect(
          s['deliveryNote'],
          startsWith('[İmza alınamadı: Alıcı yok / tanka teslim]'),
        );
        final photos = h.world.attachments.where(
          (a) => a['ownerType'] == 10 && a['ownerId'] == id && a['kind'] == 30,
        );
        expect(photos, hasLength(1));
      },
    );

    test(
      'farklı bilgilerle tekrar bildirim: already_reported (sunucu mesajı)',
      () async {
        final id = inTransitId();
        final commands = c.read(driverCommandsProvider);
        final first = await commands.deliver(
          draft: draft(
            id,
            photos: [photoFile('h.jpg')],
            signature: photoFile('i.png'),
          ),
          liters: 7950,
        );
        expect((await waitOp(c, first.id)).status, OutboxStatus.done);
        final second = await commands.deliver(
          draft: draft(
            id,
            doc: 'IRS-9999',
            photos: [photoFile('j.jpg')],
            signature: photoFile('k.png'),
          ),
          liters: 7000,
        );
        final r = await waitOp(c, second.id);
        expect(r.status, OutboxStatus.needsAttention);
        expect(
          r.lastError,
          'Bu teslimat farklı litre ya da irsaliye numarasıyla zaten bildirilmiş.',
        );
      },
    );

    test('zorunluluk: imza ya da neden yoksa reddedilir', () async {
      final id = inTransitId();
      final op = await c
          .read(driverCommandsProvider)
          .deliver(
            draft: draft(id, photos: [photoFile('l.jpg')]),
            liters: 7950,
          );
      final r = await waitOp(c, op.id);
      expect(r.status, OutboxStatus.needsAttention);
      expect(
        r.lastError,
        'Teslim alanın imzasını alın ya da imza alınamama nedenini seçin.',
      );
    });

    test('bekleyen yola çıkış tekrar kuyruğa yazılmaz', () async {
      final id = plannedTodayId();
      h.server.failureMode = FakeFailureMode.offline;
      final commands = c.read(driverCommandsProvider);
      final a = await commands.start(shipmentId: id, code: 'x');
      await waitOp(c, a.id);
      final b = await commands.start(shipmentId: id, code: 'x');
      expect(b.id, a.id);
      final ops = c.read(driverOpsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(ops, isA<Map<int, DriverShipmentOps>>());
    });

    test('vazgeç: yola çıkış silinince bağlı teslim serbest kalır', () async {
      final id = plannedTodayId();
      final commands = c.read(driverCommandsProvider);
      h.server.failureMode = FakeFailureMode.offline;
      final start = await commands.start(shipmentId: id, code: 'x');
      await waitOp(c, start.id);
      final d = await commands.deliver(
        draft: draft(id, photos: [photoFile('m.jpg')]),
        liters: 7950,
      );
      await commands.discard(start.id);
      final after = await c.read(outboxStoreProvider).get(d.id);
      expect(after?.dependsOn, isNull);
    });
  });

  group('Düzeltme taslağı', () {
    test('reddedilen işlemin gövdesinden taslak kurulur', () {
      final op = OutboxOp(
        id: 'op-1',
        userId: 'u-sofor',
        type: DriverOutbox.deliver,
        idempotencyKey: 'k',
        payload: DriverOutbox.deliverPayload(
          draft: draft(5001, photos: ['/x/a.jpg'], signature: '/x/s.png'),
          liters: 7950.5,
          deviceTime: DateTime.utc(2026, 10, 21, 9),
        ),
        createdAt: DateTime.utc(2026, 10, 21, 9),
        updatedAt: DateTime.utc(2026, 10, 21, 9),
      );
      final body = JsonReader(op.payload).obj('body');
      expect(body.dec('deliveredLiters'), 7950.5);
      expect(body.str('deviceTime'), '2026-10-21T09:00:00.000Z');
      final d = DriverOutbox.draftFromDeliverOp(op);
      expect(d.litersText, '7950,5');
      expect(d.documentNo, 'IRS-1001');
      expect(d.recipientName, 'Murat Kaya');
      expect(d.note, 'Arka avlu tankı');
      expect(d.photos.single.path, '/x/a.jpg');
      expect(d.signaturePath, '/x/s.png');
      expect(d.step, DeliverStep.summary);
      expect(d.fixOpId, 'op-1');
    });
  });
}

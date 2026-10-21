import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/network/api_client.dart';
import 'package:akaryakitnet/core/network/app_failure.dart';
import 'package:akaryakitnet/core/offline/backoff.dart';
import 'package:akaryakitnet/core/offline/outbox_op.dart';
import 'package:akaryakitnet/core/offline/outbox_runner.dart';
import 'package:akaryakitnet/core/offline/outbox_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _Clock {
  DateTime now = DateTime.utc(2026, 10, 21, 9);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

void main() {
  group('Geri çekilme', () {
    test('5 sn / 15 sn / 1 dk / 5 dk / 15 dk, sonra 15 dk', () {
      expect(
        [for (var i = 1; i <= 7; i++) OutboxBackoff.after(i)],
        const [
          Duration(seconds: 5),
          Duration(seconds: 15),
          Duration(minutes: 1),
          Duration(minutes: 5),
          Duration(minutes: 15),
          Duration(minutes: 15),
          Duration(minutes: 15),
        ],
      );
      expect(OutboxBackoff.after(0), Duration.zero);
    });

    test('Retry-After daha uzunsa o kullanılır', () {
      expect(
        OutboxBackoff.withRetryAfter(1, const Duration(seconds: 30)),
        const Duration(seconds: 30),
      );
      expect(
        OutboxBackoff.withRetryAfter(3, const Duration(seconds: 30)),
        const Duration(minutes: 1),
      );
    });
  });

  group('OutboxRunner', () {
    late MemoryOutboxStore store;
    late _Clock clock;
    late List<Object> script;
    late List<String> calls;
    var online = true;

    OutboxRunner runner({
      Map<String, OutboxHandler>? handlers,
      String? user = 'u-1',
    }) => OutboxRunner(
      store: store,
      api: ApiClient(Dio()),
      clock: clock.call,
      isOnline: () => online,
      currentUserId: () => user,
      handlers:
          handlers ??
          {
            'driver.deliver': (op, ctx) async {
              calls.add('${op.type}:${op.idempotencyKey}');
              final next = script.isEmpty
                  ? <String, dynamic>{'ok': true}
                  : script.removeAt(0);
              if (next is AppFailure) throw next;
              return next as JsonMap;
            },
          },
    );

    setUp(() {
      store = MemoryOutboxStore();
      clock = _Clock();
      script = [];
      calls = [];
      online = true;
    });

    test(
      'geçici hatalarda aynı anahtarla, artan aralıklarla yeniden dener',
      () async {
        final r = runner();
        script = [
          const OfflineFailure(),
          const TimeoutFailure(),
          const ServerFailure(statusCode: 500),
          <String, dynamic>{'shipmentId': 5002},
        ];
        final op = await r.enqueue(
          type: 'driver.deliver',
          payload: {'liters': 8000},
          runNow: false,
        );

        await r.runOnce();
        var s = (await store.get(op.id))!;
        expect(s.status, OutboxStatus.failed);
        expect(s.attempts, 1);
        expect(s.nextAttemptAt, clock.now.add(const Duration(seconds: 5)));
        expect(s.lastError, contains('İnternet'));

        await r.runOnce();
        expect(calls, hasLength(1), reason: 'vadesi gelmeden denenmez');

        clock.advance(const Duration(seconds: 5));
        await r.runOnce();
        s = (await store.get(op.id))!;
        expect(s.attempts, 2);
        expect(s.nextAttemptAt, clock.now.add(const Duration(seconds: 15)));

        clock.advance(const Duration(seconds: 15));
        await r.runOnce();
        s = (await store.get(op.id))!;
        expect(s.attempts, 3);
        expect(s.nextAttemptAt, clock.now.add(const Duration(minutes: 1)));

        clock.advance(const Duration(minutes: 1));
        await r.runOnce();
        s = (await store.get(op.id))!;
        expect(s.status, OutboxStatus.done);
        expect(s.result, {'shipmentId': 5002});
        expect(calls.toSet(), {
          'driver.deliver:${op.idempotencyKey}',
        }, reason: 'her deneme aynı Idempotency-Key');
        expect(await r.waitingCount(), 0);
      },
    );

    test(
      '400/409 → ilgilenilmesi gerekiyor + sunucu mesajı; yeniden dene ve vazgeç',
      () async {
        final r = runner();
        script = [
          const BusinessFailure(
            'Teslim edilen litre planlanandan fazla olamaz.',
          ),
        ];
        final op = await r.enqueue(
          type: 'driver.deliver',
          payload: const {},
          runNow: false,
        );
        await r.runOnce();
        var s = (await store.get(op.id))!;
        expect(s.status, OutboxStatus.needsAttention);
        expect(s.lastError, 'Teslim edilen litre planlanandan fazla olamaz.');

        await r.retry(op.id);
        s = (await store.get(op.id))!;
        expect(s.status, OutboxStatus.done);

        final other = await r.enqueue(
          type: 'driver.deliver',
          payload: const {},
          runNow: false,
        );
        await r.discard(other.id);
        expect(await store.get(other.id), isNull);
      },
    );

    test(
      'çakışma (concurrency) ilgilenilmesi gereken, işlem sürüyor geçicidir',
      () async {
        final r = runner();
        script = [
          ConflictFailure('idempotency_in_progress'),
          ConflictFailure('already_reported'),
        ];
        final op = await r.enqueue(
          type: 'driver.deliver',
          payload: const {},
          runNow: false,
        );
        await r.runOnce();
        expect((await store.get(op.id))!.status, OutboxStatus.failed);
        clock.advance(const Duration(seconds: 5));
        await r.runOnce();
        expect((await store.get(op.id))!.status, OutboxStatus.needsAttention);
      },
    );

    test(
      '401 ve çevrimdışı turu durdurur; çevrimdışıyken hiç denenmez',
      () async {
        final r = runner();
        script = [const UnauthorizedFailure('unauthorized')];
        final a = await r.enqueue(
          type: 'driver.deliver',
          payload: const {},
          runNow: false,
        );
        final b = await r.enqueue(
          type: 'driver.deliver',
          payload: const {},
          runNow: false,
        );
        await r.runOnce();
        expect((await store.get(a.id))!.status, OutboxStatus.pending);
        expect(
          (await store.get(b.id))!.status,
          OutboxStatus.pending,
          reason: 'tur durdu',
        );
        expect(calls, hasLength(1));

        online = false;
        await r.runOnce();
        expect(calls, hasLength(1));
        online = true;
        await r.runOnce();
        expect((await store.get(a.id))!.status, OutboxStatus.done);
        expect((await store.get(b.id))!.status, OutboxStatus.done);
      },
    );

    test(
      'bağımlı işlem öncekinin sonucunu okur; önceki bitmeden çalışmaz',
      () async {
        final seen = <JsonMap?>[];
        var saveFails = true;
        final r = runner(
          handlers: {
            'lead.saveDraft': (op, ctx) async {
              if (saveFails) throw const OfflineFailure();
              return {'leadId': 8012};
            },
            'lead.upload': (op, ctx) async {
              seen.add(ctx.dependencyResult);
              final k1 = await ctx.subKey('file-0');
              final k2 = await ctx.subKey('file-0');
              expect(k1, k2, reason: 'alt anahtar kalıcı');
              return null;
            },
          },
        );
        final save = await r.enqueue(
          type: 'lead.saveDraft',
          payload: const {},
          runNow: false,
        );
        final upload = await r.enqueue(
          type: 'lead.upload',
          payload: const {},
          dependsOn: save.id,
          runNow: false,
        );
        await r.runOnce();
        expect((await store.get(upload.id))!.status, OutboxStatus.pending);
        expect(seen, isEmpty);

        saveFails = false;
        clock.advance(const Duration(seconds: 5));
        await r.runOnce();
        expect((await store.get(save.id))!.status, OutboxStatus.done);
        expect((await store.get(upload.id))!.status, OutboxStatus.done);
        expect(seen.single, {'leadId': 8012});
        expect(
          (await store.get(upload.id))!.payload['_keys'],
          isA<Map<String, dynamic>>(),
        );
      },
    );

    test(
      'bilinmeyen tür ve kayıp bağımlılık ilgilenilmesi gereken olur',
      () async {
        final r = runner(handlers: const {});
        final op = await r.enqueue(
          type: 'eski.tur',
          payload: const {},
          runNow: false,
        );
        final orphan = await r.enqueue(
          type: 'eski.tur',
          payload: const {},
          dependsOn: 'yok',
          runNow: false,
        );
        await r.runOnce();
        expect((await store.get(op.id))!.status, OutboxStatus.needsAttention);
        expect(
          (await store.get(orphan.id))!.lastError,
          'Bağlı olduğu işlem bulunamadı.',
        );
      },
    );

    test('kullanıcıya özeldir; oturum yokken eklenemez', () async {
      final r = runner(user: null);
      await expectLater(
        r.enqueue(type: 'driver.deliver', payload: const {}),
        throwsA(isA<UnauthorizedFailure>()),
      );
    });

    test('SQLite satırı gidiş-dönüş', () {
      final now = DateTime.utc(2026, 10, 21, 9);
      final op = OutboxOp(
        id: 'a',
        userId: 'u',
        type: 'driver.deliver',
        payload: const {
          'liters': 8000.5,
          'photos': ['p1'],
        },
        idempotencyKey: 'k',
        files: const ['/tmp/a.jpg'],
        label: 'SVK-1',
        status: OutboxStatus.failed,
        attempts: 2,
        nextAttemptAt: now,
        lastError: 'x',
        result: const {'id': 1},
        createdAt: now,
        updatedAt: now,
      );
      final back = OutboxOp.fromRow(op.toRow());
      expect(back.payload, op.payload);
      expect(back.files, op.files);
      expect(back.status, OutboxStatus.failed);
      expect(back.nextAttemptAt, now);
      expect(back.result, {'id': 1});
    });
  });
}

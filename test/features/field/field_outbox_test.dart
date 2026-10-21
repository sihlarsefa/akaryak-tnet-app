// Saha bekleyen işlemleri (spec C.4a): çevrimdışı taslak, aynı Idempotency-Key ile tekrar, zincirli
// düzenleme, zaman aşımı sonrası uzlaştırma, ön kayda bağlı belge yüklemesi, "Vazgeç".
import 'package:akaryakitnet/core/models/enums.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/offline/outbox_op.dart';
import 'package:akaryakitnet/core/offline/outbox_providers.dart';
import 'package:akaryakitnet/core/offline/outbox_store.dart';
import 'package:akaryakitnet/features/field/data/field_outbox.dart';
import 'package:akaryakitnet/features/field/data/field_repository.dart';
import 'package:akaryakitnet/features/field/fake/field_fake_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'field_test_kit.dart';

/// İlk yanıtı sunucu işledikten sonra "zaman aşımı"na çevirir (yanıt kayboldu).
class _LoseFirstResponse extends Interceptor {
  _LoseFirstResponse(this.method, this.pathEnd);

  final String method;
  final String pathEnd;
  int lost = 0;
  final replays = <String?>[];

  bool _matches(RequestOptions o) =>
      o.method.toUpperCase() == method && o.uri.path.endsWith(pathEnd);

  @override
  void onResponse(Response<dynamic> r, ResponseInterceptorHandler h) {
    if (_matches(r.requestOptions)) {
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

const _settled = {
  OutboxStatus.done,
  OutboxStatus.needsAttention,
  OutboxStatus.failed,
};

void main() {
  late FieldHarness h;
  late ProviderContainer c;
  late RequestLog log;

  FieldOutbox outbox() => c.read(fieldOutboxProvider);
  Future<List<OutboxOp>> ops() => c.read(outboxStoreProvider).list('u-saha');

  setUp(() async {
    h = await FieldHarness.create();
    c = h.container();
    log = RequestLog()..attach(c);
    await loginAs(c, 'saha');
  });

  tearDown(() {
    c.dispose();
    h.dispose();
  });

  test(
    'çevrimdışı taslak bekler; bağlantı gelince aynı anahtarla bir kez gider',
    () async {
      c.read(onlineProvider.notifier).state = false;
      final op = await outbox().queueFormSave(
        request: formRequest(),
        idempotencyKey: 'q-1',
        customerTitle: 'Ege Tarım Kooperatifi',
        liters: 8000,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        (await c.read(outboxStoreProvider).get(op.id))!.status,
        OutboxStatus.pending,
      );
      expect(log.exact('POST', 'field-orders'), isEmpty);
      final item = groupFieldOps(await ops()).single;
      expect(item.isForm, isTrue);
      expect(item.customerTitle, 'Ege Tarım Kooperatifi');
      expect(item.liters, 8000);

      c.read(onlineProvider.notifier).state = true;
      await c.read(outboxRunnerProvider).runOnce();
      final done = await waitOp(c, op.id);
      expect(done.status, OutboxStatus.done);
      final id = done.result!['formId'] as int;
      expect(done.result!['formNumber'], startsWith('SSF-'));
      final posts = log.exact('POST', 'field-orders');
      expect(posts, hasLength(1));
      expect(idempotencyKeyOf(posts.single), 'q-1');
      expect(h.state.forms.where((f) => f['id'] == id), hasLength(1));
    },
  );

  test(
    'yanıtı kaybolan kayıt aynı anahtarla tekrarlanır; ikinci form açılmaz',
    () async {
      final lose = _LoseFirstResponse('POST', '/field-orders');
      c.read(dioProvider).interceptors.add(lose);
      final before = h.state.forms.length;
      final op = await outbox().queueFormSave(
        request: formRequest(),
        idempotencyKey: 'q-2',
      );
      var now = await waitOp(c, op.id, until: _settled);
      expect(now.status, OutboxStatus.failed);
      expect(h.state.forms.length, before + 1); // sunucu işledi, yanıt kayboldu
      await outbox().retry(op.id);
      now = await waitOp(c, op.id);
      expect(now.status, OutboxStatus.done);
      expect(h.state.forms.length, before + 1);
      expect(lose.replays.last, 'true');
      final keys = log
          .exact('POST', 'field-orders')
          .map(idempotencyKeyOf)
          .toSet();
      expect(keys, {'q-2'});
    },
  );

  test(
    'kuyruktaki taslağın düzenlemesi zincirlenir: önce POST, sonra PUT',
    () async {
      c.read(onlineProvider.notifier).state = false;
      final first = await outbox().queueFormSave(
        request: formRequest(),
        idempotencyKey: 'q-3',
      );
      final second = await outbox().queueFormSave(
        request: formRequest(liters: 9500),
        idempotencyKey: 'q-4',
        chainAfter: first.id,
      );
      final items = groupFieldOps(await ops());
      expect(items, hasLength(1));
      expect(items.single.chain.map((o) => o.id), [first.id, second.id]);
      expect(items.single.formRequest!['lines'][0]['quantityLiters'], 9500);

      c.read(onlineProvider.notifier).state = true;
      await c.read(outboxRunnerProvider).runOnce();
      final a = await waitOp(c, first.id);
      final b = await waitOp(c, second.id);
      expect(a.status, OutboxStatus.done);
      expect(b.status, OutboxStatus.done);
      final id = a.result!['formId'] as int;
      expect(b.result!['formId'], id);
      expect(log.exact('PUT', 'field-orders/$id'), hasLength(1));
      final form = h.state.forms.firstWhere((f) => f['id'] == id);
      expect(form['totalLiters'], 9500);
    },
  );

  test(
    'zaman aşımından sonra güncelleme tekrarı: içerik aynıysa tamam sayılır',
    () async {
      final form = await c
          .read(fieldRepositoryProvider)
          .createForm(formRequest());
      final lose = _LoseFirstResponse('PUT', '/field-orders/${form.id}');
      c.read(dioProvider).interceptors.add(lose);
      final op = await outbox().queueFormSave(
        request: {
          ...formRequest(liters: 8800),
          'concurrencyToken': form.concurrencyToken,
        },
        idempotencyKey: 'q-5',
        formId: form.id,
      );
      var now = await waitOp(c, op.id, until: _settled);
      expect(now.status, OutboxStatus.failed);
      await outbox().retry(op.id);
      now = await waitOp(c, op.id);
      // İkinci PUT eski belirteçle "değiştirildi" alır; form gönderilenle aynı olduğu için tamam.
      expect(now.status, OutboxStatus.done);
      expect(log.exact('GET', 'field-orders/${form.id}'), isNotEmpty);
      expect(
        h.state.forms.firstWhere((f) => f['id'] == form.id)['totalLiters'],
        8800,
      );
    },
  );

  test('sunucunun reddettiği taslak "İlgilenmeniz gerekiyor" olur', () async {
    final op = await outbox().queueFormSave(
      request: formRequest(customerId: 101, pointId: 1001),
      idempotencyKey: 'q-6',
    );
    final now = await waitOp(c, op.id);
    expect(now.status, OutboxStatus.needsAttention);
    expect(now.lastError, 'Bu cari portföyünüzde değil.');
    final item = groupFieldOps(await ops()).single;
    expect(item.status, OutboxStatus.needsAttention);
    expect(item.lastError, 'Bu cari portföyünüzde değil.');
  });

  test(
    'ön kayıt ve vergi levhası: belge, kayda bağlı olarak yüklenir',
    () async {
      c.read(onlineProvider.notifier).state = false;
      final save = await outbox().queueLeadSave(
        body: {
          'id': 0,
          'companyTitle': 'Kuyruk Ltd. Şti.',
          'taxNumber': FieldFakeState.vkn('111222333'),
          'contacts': const <Object>[],
          'products': const <Object>[],
        },
        idempotencyKey: 'l-q1',
        companyTitle: 'Kuyruk Ltd. Şti.',
      );
      final path = await h.files.persist(h.writePng());
      final upload = await outbox().queueLeadUpload(
        kind: AttachmentKind.taxPlate,
        filePath: path,
        fileName: 'levha.png',
        contentType: 'image/png',
        dependsOn: save.id,
        companyTitle: 'Kuyruk Ltd. Şti.',
      );
      final items = groupFieldOps(await ops());
      expect(items.map((i) => i.type).toSet(), {
        FieldOps.leadSaveDraft,
        FieldOps.leadUpload,
      });
      expect(
        items.firstWhere((i) => i.isUpload).uploadKindLabel,
        'Vergi levhası',
      );

      c.read(onlineProvider.notifier).state = true;
      await c.read(outboxRunnerProvider).runOnce();
      final s = await waitOp(c, save.id);
      final u = await waitOp(c, upload.id);
      expect(s.status, OutboxStatus.done);
      expect(u.status, OutboxStatus.done);
      final leadId = s.result!['leadId'] as int;
      expect(
        h.server.world.attachments.where(
          (a) =>
              a['ownerType'] == AttachmentOwnerType.customerLead.code &&
              a['ownerId'] == leadId &&
              a['kind'] == AttachmentKind.taxPlate.code,
        ),
        hasLength(1),
      );
      expect(idempotencyKeyOf(log.exact('POST', 'leads').single), 'l-q1');
    },
  );

  test(
    '"Vazgeç": kayıt zincirinin tüm halkaları ve bağlı belgeler silinir',
    () async {
      c.read(onlineProvider.notifier).state = false;
      final save = await outbox().queueLeadSave(
        body: {'id': 0, 'companyTitle': 'Vazgeç A.Ş.'},
        idempotencyKey: 'l-q2',
      );
      final edit = await outbox().queueLeadSave(
        body: {'id': 0, 'companyTitle': 'Vazgeç A.Ş. (düzeltildi)'},
        idempotencyKey: 'l-q3',
        chainAfter: save.id,
      );
      final path = await h.files.persist(h.writePng('belge.png'));
      final upload = await outbox().queueLeadUpload(
        kind: AttachmentKind.signatureCircular,
        filePath: path,
        fileName: 'belge.png',
        contentType: 'image/png',
        dependsOn: save.id,
      );
      expect(fieldChainIds(await ops(), upload.id), {upload.id});
      await outbox().discardChain(edit.id);
      expect(await ops(), isEmpty);
    },
  );
}

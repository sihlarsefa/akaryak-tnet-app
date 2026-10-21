// Teklif kararı (spec A.4 + C.4a): her karar için tek Idempotency-Key, expectedQuoteId,
// zaman aşımı / 400 / 409 sonrası siparişi yeniden okuyup hedef duruma ulaştıysa başarı sayma.
import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/network/api_client.dart';
import 'package:akaryakitnet/core/network/app_failure.dart';
import 'package:akaryakitnet/core/network/idempotency.dart';
import 'package:akaryakitnet/features/customer_orders/application/quote_decision.dart';
import 'package:akaryakitnet/features/customer_orders/data/customer_orders_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _DecideRepo extends CustomerOrdersRepository {
  _DecideRepo() : super(ApiClient(Dio()));

  final List<Object?> script = [];
  final List<
    ({int orderId, QuoteAction action, String? note, int? quote, String key})
  >
  calls = [];

  @override
  Future<void> decide(
    int orderId,
    QuoteAction action, {
    String? note,
    int? expectedQuoteId,
    required String idempotencyKey,
  }) async {
    calls.add((
      orderId: orderId,
      action: action,
      note: note,
      quote: expectedQuoteId,
      key: idempotencyKey,
    ));
    final next = script.isEmpty ? null : script.removeAt(0);
    if (next is AppFailure) throw next;
  }
}

void main() {
  late _DecideRepo repo;
  late List<Duration> waits;
  late QuoteDecisionExecutor exec;
  late List<OrderStatus?> statuses;

  setUp(() {
    repo = _DecideRepo();
    waits = [];
    statuses = [];
    exec = QuoteDecisionExecutor(
      repository: repo,
      ledger: IdempotencyLedger(),
      wait: (d) async => waits.add(d),
    );
  });

  Future<OrderStatus?> refetch() async =>
      statuses.isEmpty ? OrderStatus.awaitingApproval : statuses.removeAt(0);

  test('onay: expectedQuoteId ve anahtar gider', () async {
    final out = await exec.decide(
      orderId: 12002,
      action: QuoteAction.approve,
      expectedQuoteId: 30001,
      refetchStatus: refetch,
    );
    expect(out, isA<DecisionDone>());
    expect(repo.calls.single.quote, 30001);
    expect(isValidIdempotencyKey(repo.calls.single.key), isTrue);
  });

  test(
    'zaman aşımı: sipariş onaylanmış görünüyorsa başarı (yeniden göndermeden)',
    () async {
      repo.script.add(const TimeoutFailure());
      statuses.add(OrderStatus.approved);
      final out = await exec.decide(
        orderId: 1,
        action: QuoteAction.approve,
        expectedQuoteId: 9,
        refetchStatus: refetch,
      );
      expect(out, isA<DecisionDone>());
      expect((out as DecisionDone).confirmedByRefetch, isTrue);
      expect(repo.calls, hasLength(1));
    },
  );

  test(
    'zaman aşımı + henüz işlenmemiş: aynı anahtarla tekrar ("kontrol ediliyor")',
    () async {
      repo.script.addAll([const TimeoutFailure(), null]);
      var checking = 0;
      final out = await exec.decide(
        orderId: 1,
        action: QuoteAction.reject,
        expectedQuoteId: 9,
        note: 'Fiyat uygun değil',
        refetchStatus: refetch,
        onChecking: () => checking++,
      );
      expect(out, isA<DecisionDone>());
      expect(repo.calls, hasLength(2));
      expect(repo.calls[0].key, repo.calls[1].key);
      expect(checking, 1);
      expect(waits, [const Duration(seconds: 2)]);
      expect(repo.calls.last.note, 'Fiyat uygun değil');
    },
  );

  test(
    'bağlantı hiç gelmezse "doğrulanamadı"; sonraki deneme aynı anahtar',
    () async {
      for (var i = 0; i < 6; i++) {
        repo.script.add(const OfflineFailure());
      }
      final out = await exec.decide(
        orderId: 1,
        action: QuoteAction.approve,
        expectedQuoteId: 9,
        refetchStatus: () async => null,
      );
      expect(out, isA<DecisionUncertain>());
      final key = repo.calls.first.key;
      expect(repo.calls.every((c) => c.key == key), isTrue);
      await exec.decide(
        orderId: 1,
        action: QuoteAction.approve,
        expectedQuoteId: 9,
        refetchStatus: refetch,
      );
      expect(
        repo.calls.last.key,
        key,
        reason: 'niyet kesinleşmedi, anahtar korunur',
      );
    },
  );

  test(
    '409 teklif değişti: yeniden okunur, kararsız → çakışma mesajı',
    () async {
      repo.script.add(
        ConflictFailure(
          'concurrency_conflict',
          message:
              'Teklif güncellendi; güncel teklifi görüp yeniden karar verin.',
        ),
      );
      final out = await exec.decide(
        orderId: 1,
        action: QuoteAction.approve,
        expectedQuoteId: 9,
        refetchStatus: refetch,
      );
      expect(out, isA<DecisionConflict>());
      expect(
        (out as DecisionConflict).message,
        'Teklif güncellendi; güncel teklifi görüp yeniden karar verin.',
      );
    },
  );

  test(
    '400 ama sipariş zaten reddedilmiş (önceki istek işlenmiş) → başarı',
    () async {
      repo.script.add(
        const BusinessFailure(
          'Sipariş onay/red/revize için uygun durumda değil.',
        ),
      );
      statuses.add(OrderStatus.rejected);
      final out = await exec.decide(
        orderId: 1,
        action: QuoteAction.reject,
        expectedQuoteId: 9,
        refetchStatus: refetch,
      );
      expect(out, isA<DecisionDone>());
    },
  );

  test(
    '400 ve durum değişmemiş → sunucu mesajı; yeni karar yeni anahtar',
    () async {
      repo.script.add(
        const BusinessFailure('Çek görseli yüklenmeden teklif onaylanamaz.'),
      );
      final out = await exec.decide(
        orderId: 1,
        action: QuoteAction.approve,
        expectedQuoteId: 9,
        refetchStatus: refetch,
      );
      expect(out, isA<DecisionFailed>());
      expect(
        (out as DecisionFailed).failure.message,
        'Çek görseli yüklenmeden teklif onaylanamaz.',
      );
      final first = repo.calls.single.key;
      await exec.decide(
        orderId: 1,
        action: QuoteAction.approve,
        expectedQuoteId: 9,
        refetchStatus: refetch,
      );
      expect(repo.calls.last.key, isNot(first));
    },
  );

  test('farklı kararlar farklı anahtar', () async {
    await exec.decide(
      orderId: 1,
      action: QuoteAction.revise,
      expectedQuoteId: 9,
      note: 'x',
      refetchStatus: refetch,
    );
    await exec.decide(
      orderId: 2,
      action: QuoteAction.revise,
      expectedQuoteId: 9,
      note: 'x',
      refetchStatus: refetch,
    );
    expect(repo.calls[0].key, isNot(repo.calls[1].key));
  });

  test('hedef durumlar', () {
    expect(QuoteAction.approve.reached(OrderStatus.approved), isTrue);
    expect(QuoteAction.approve.reached(OrderStatus.completed), isTrue);
    expect(QuoteAction.revise.reached(OrderStatus.revisionRequested), isTrue);
    expect(QuoteAction.reject.reached(OrderStatus.awaitingApproval), isFalse);
  });
}

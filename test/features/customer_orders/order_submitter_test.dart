// Sipariş gönderimi (spec C.4a): taslak + Idempotency-Key kullanıcı başına saklanır; zaman aşımı /
// bağlantı / 5xx'te aynı anahtarla 2–4–8–16 sn (en çok 60 sn); işlem sürüyorsa yoklama;
// idempotency_unknown → Siparişlerim ile doğrulama, bulunamazsa onayla yeni anahtar; kısmi hata →
// kalan satırlar yeni anahtar + ödeme grubu; uygulama kapanıp açılınca aynı anahtarla devam.
import 'dart:async';

import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/network/api_client.dart';
import 'package:akaryakitnet/core/network/app_failure.dart';
import 'package:akaryakitnet/core/network/idempotency.dart';
import 'package:akaryakitnet/core/offline/cache_store.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:akaryakitnet/features/customer_orders/application/order_submitter.dart';
import 'package:akaryakitnet/features/customer_orders/application/retry_policy.dart';
import 'package:akaryakitnet/features/customer_orders/application/wizard_models.dart';
import 'package:akaryakitnet/features/customer_orders/application/wizard_store.dart';
import 'package:akaryakitnet/features/customer_orders/data/customer_orders_repository.dart';
import 'package:akaryakitnet/features/customer_orders/data/form_models.dart';
import 'package:akaryakitnet/features/customer_orders/data/order_models.dart';
import 'package:akaryakitnet/features/customer_orders/data/payment_models.dart';
import 'package:akaryakitnet/features/customer_orders/data/place_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sıralı yanıtlarla çalışan depo (ağ yok).
class ScriptedRepo extends CustomerOrdersRepository {
  ScriptedRepo() : super(ApiClient(Dio()));

  /// Sıradaki `place` yanıtları: [PlaceOrderResult], [AppFailure] ya da [Completer].
  final List<Object> placeScript = [];
  final List<({String key, PlaceOrderRequest request})> placeCalls = [];
  List<CustomerOrderRow> rows = const [];
  List<OrderRequestSnapshot> requests = const [];

  @override
  Future<PlaceOrderResult> place(
    PlaceOrderRequest request, {
    required String idempotencyKey,
  }) async {
    placeCalls.add((key: idempotencyKey, request: request));
    if (placeScript.isEmpty) throw StateError('beklenmeyen place');
    final next = placeScript.removeAt(0);
    if (next is Completer<PlaceOrderResult>) return next.future;
    if (next is AppFailure) throw next;
    return next as PlaceOrderResult;
  }

  @override
  Future<Object?> homeRaw() async => const <String, dynamic>{};

  @override
  Future<Object?> orderFormRaw() async => {
    'customerId': 101,
    'products': [
      {'id': 1, 'name': 'Motorin'},
      {'id': 2, 'name': 'Kurşunsuz Benzin 95'},
    ],
    'deliveryPoints': [
      {'id': 1001, 'name': 'Pendik Lojistik Merkezi'},
    ],
  };

  @override
  Future<PagedResult<CustomerOrderRow>> orders({
    required OrderSegment segment,
    String? q,
    int page = 1,
    int pageSize = 25,
  }) async => PagedResult(
    items: segment == OrderSegment.active ? rows : const [],
    totalCount: rows.length,
    pageNumber: 1,
    pageSize: 50,
    totalPages: 1,
  );

  @override
  Future<OrderDetail> order(int id) async => OrderDetail.fromJson({
    'id': id,
    'orderNumber': 'SIP-$id',
    'status': 1,
    'paymentGroupKey': 'g-found',
  });

  @override
  Future<PaymentUploadTarget?> documentTarget({
    String? methodCode,
    String? groupKey,
    Iterable<int> orderIds = const [],
  }) async => null;

  @override
  Future<List<OrderRequestSnapshot>> recentOrderRequests({
    int take = 10,
  }) async => requests;
}

class _FixedSession extends SessionController {
  _FixedSession(this.me);
  final MeAccess me;

  @override
  SessionState build() => SessionAuthenticated(me);
}

MeAccess _me({int role = 3}) => MeAccess.fromJson({
  'userId': 'u-musteri',
  'userName': 'musteri',
  'displayName': 'Selin Aydın',
  'persona': 'customer',
  'roles': ['Customer'],
  'customerId': 101,
  'customerUserRole': role,
  'pages': ['CustomerCreateOrder:Ekler', 'CustomerOrders:Gorur'],
});

PlaceOrderResult _ok({int id = 13001, String? group}) => PlaceOrderResult(
  orders: [
    CreateOrderResult(
      orderId: id,
      orderNumber: 'SIP-$id',
      paymentGroupKey: group,
    ),
  ],
  paymentGroupKey: group,
  message: 'Sipariş oluşturuldu: SIP-$id',
);

void main() {
  late ScriptedRepo repo;
  late MemoryCacheStore cache;
  late List<Duration> waits;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    repo = ScriptedRepo();
    cache = MemoryCacheStore();
    waits = [];
  });

  ProviderContainer container({int role = 3, ScriptedRepo? using}) {
    final c = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWithValue('u-musteri'),
        sessionControllerProvider.overrideWith(
          () => _FixedSession(_me(role: role)),
        ),
        cacheStoreProvider.overrideWithValue(cache),
        prefsStoreProvider.overrideWithValue(PrefsStore(prefs)),
        customerOrdersRepositoryProvider.overrideWithValue(using ?? repo),
        a2WaitProvider.overrideWithValue((d) async => waits.add(d)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  final tomorrow = TrTime.addDays(TrTime.todayStart(), 1);

  OrderDraft draft({int lines = 1}) => OrderDraft(
    stationId: 1,
    pointId: 1001,
    date: tomorrow,
    lines: [
      for (var i = 0; i < lines; i++)
        DraftLine.create(productId: i == 0 ? 1 : 2, liters: 1000.0 * (i + 1)),
    ],
    payment: const DraftPayment(methodCode: 'HAVALE', termDays: 0),
    dirty: true,
  );

  PlaceOrderRequest requestOf(OrderDraft d) => PlaceOrderRequest(
    stationId: 1,
    deliveryPointId: 1001,
    requestedDeliveryDate: tomorrow,
    lines: [
      for (final l in d.lines)
        PlaceOrderLine(productId: l.productId!, quantityLiters: l.liters!),
    ],
    payment: const PaymentSelection(methodCode: 'HAVALE', termDays: 0),
    paymentGroupKey: d.paymentGroupKey,
  );

  Future<WizardSnapshot?> snapshot() =>
      WizardDraftStore(cache, 'u-musteri').load();

  test('başarı: tek istek, geçerli anahtar, taslak silinir', () async {
    final c = container();
    repo.placeScript.add(_ok());
    final d = draft();
    await c.read(orderSubmitProvider.notifier).submit(d, requestOf(d));
    final s = c.read(orderSubmitProvider);
    expect(s.phase, SubmitPhase.success);
    expect(s.created.single.orderNumber, 'SIP-13001');
    expect(repo.placeCalls, hasLength(1));
    expect(isValidIdempotencyKey(repo.placeCalls.single.key), isTrue);
    expect(await snapshot(), isNull);
    expect(s.firstOrder, isTrue, reason: 'ilk sipariş: bildirim ön sayfası');
  });

  test(
    'zaman aşımı sonrası aynı anahtarla tekrar (2 sn) → sunucunun kaydı',
    () async {
      final c = container();
      repo.placeScript.addAll([const TimeoutFailure(), _ok()]);
      final d = draft();
      await c.read(orderSubmitProvider.notifier).submit(d, requestOf(d));
      expect(c.read(orderSubmitProvider).phase, SubmitPhase.success);
      expect(repo.placeCalls, hasLength(2));
      expect(repo.placeCalls[0].key, repo.placeCalls[1].key);
      expect(waits, [const Duration(seconds: 2)]);
    },
  );

  test(
    '5xx sürerse 2,4,8,16,16 sn sonra "doğrulanamadı"; anahtar saklanır; elle tekrar aynı anahtar',
    () async {
      final c = container();
      for (var i = 0; i < 6; i++) {
        repo.placeScript.add(const ServerFailure(statusCode: 503));
      }
      final d = draft();
      await c.read(orderSubmitProvider.notifier).submit(d, requestOf(d));
      expect(c.read(orderSubmitProvider).phase, SubmitPhase.uncertain);
      expect(waits, const [
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
        Duration(seconds: 16),
        Duration(seconds: 16),
      ]);
      expect(
        waits.fold(Duration.zero, (a, b) => a + b) <=
            const Duration(seconds: 60),
        isTrue,
      );
      final keys = repo.placeCalls.map((x) => x.key).toSet();
      expect(keys, hasLength(1), reason: 'hep aynı anahtar');
      final snap = await snapshot();
      expect(snap?.pending?.key, keys.single);

      repo.placeScript.add(_ok());
      await c.read(orderSubmitProvider.notifier).retrySameKey();
      expect(c.read(orderSubmitProvider).phase, SubmitPhase.success);
      expect(repo.placeCalls.last.key, keys.single);
    },
  );

  test('çevrimdışı da belirsiz: aynı anahtar', () async {
    final c = container();
    repo.placeScript.addAll([
      const OfflineFailure(),
      const OfflineFailure(),
      _ok(),
    ]);
    final d = draft();
    await c.read(orderSubmitProvider.notifier).submit(d, requestOf(d));
    expect(c.read(orderSubmitProvider).phase, SubmitPhase.success);
    expect(repo.placeCalls.map((x) => x.key).toSet(), hasLength(1));
  });

  test('idempotency_in_progress alındıkça yoklanır (aynı anahtar)', () async {
    final c = container();
    for (var i = 0; i < 3; i++) {
      repo.placeScript.add(ConflictFailure('idempotency_in_progress'));
    }
    repo.placeScript.add(_ok());
    final d = draft();
    await c.read(orderSubmitProvider.notifier).submit(d, requestOf(d));
    expect(c.read(orderSubmitProvider).phase, SubmitPhase.success);
    expect(repo.placeCalls.map((x) => x.key).toSet(), hasLength(1));
    expect(waits, hasLength(3));
  });

  test(
    'idempotency_unknown: Siparişlerim ile doğrulanır, yeniden gönderilmez',
    () async {
      final c = container();
      repo.placeScript.add(ConflictFailure('idempotency_unknown'));
      repo.rows = [
        CustomerOrderRow.fromJson(
          JsonReader.of({
            'id': 13050,
            'orderNumber': 'SIP-13050',
            'status': 1,
            'stationId': 1,
            'productName': 'Motorin',
            'quantityLiters': 1000,
            'deliveryPointName': 'Pendik Lojistik Merkezi',
            'createdAt': DateTime.now().toUtc().toIso8601String(),
          }),
        ),
      ];
      final d = draft();
      await c.read(orderSubmitProvider.notifier).submit(d, requestOf(d));
      final s = c.read(orderSubmitProvider);
      expect(s.phase, SubmitPhase.success);
      expect(s.reconciled, isTrue);
      expect(s.created.single.orderId, 13050);
      expect(
        repo.placeCalls,
        hasLength(1),
        reason: 'yeni anahtarla tekrar yok',
      );
    },
  );

  test(
    'idempotency_unknown ve kayıt yok: kullanıcı onayıyla yeni anahtar',
    () async {
      final c = container();
      repo.placeScript.add(ConflictFailure('idempotency_unknown'));
      final d = draft();
      await c.read(orderSubmitProvider.notifier).submit(d, requestOf(d));
      expect(c.read(orderSubmitProvider).phase, SubmitPhase.askNewKey);
      final first = repo.placeCalls.single.key;
      repo.placeScript.add(_ok());
      await c.read(orderSubmitProvider.notifier).confirmNewKey();
      expect(c.read(orderSubmitProvider).phase, SubmitPhase.success);
      expect(repo.placeCalls, hasLength(2));
      expect(repo.placeCalls.last.key, isNot(first));
    },
  );

  test('Talep eden: doğrulamada şirket içi talep bulunur', () async {
    final c = container(role: 1);
    repo.placeScript.add(ConflictFailure('idempotency_unknown'));
    repo.requests = [
      OrderRequestSnapshot.fromJson(
        JsonReader.of({
          'id': 3109,
          'status': 0,
          'totalLiters': 1000,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        }),
      ),
    ];
    final d = draft();
    await c.read(orderSubmitProvider.notifier).submit(d, requestOf(d));
    final s = c.read(orderSubmitProvider);
    expect(s.phase, SubmitPhase.success);
    expect(s.result?.isCompanyRequest, isTrue);
    expect(s.result?.companyRequest?.id, 3109);
  });

  test(
    'kısmi sonuç: kalan satırlar yeni anahtar + aynı ödeme grubuyla',
    () async {
      final c = container();
      repo.placeScript.add(
        const PlaceOrderResult(
          orders: [
            CreateOrderResult(
              orderId: 13101,
              orderNumber: 'SIP-13101',
              paymentGroupKey: 'g-7',
            ),
          ],
          paymentGroupKey: 'g-7',
          partialError: 'Satır 2: Bayinin bu ürün için tanımlı fiyatı yok.',
          failedLineIndex: 1,
          message:
              '1 sipariş oluşturuldu (SIP-13101); kalan 2 satır gönderilmedi.',
        ),
      );
      final d = draft(lines: 3);
      await c.read(orderSubmitProvider.notifier).submit(d, requestOf(d));
      final s = c.read(orderSubmitProvider);
      expect(s.phase, SubmitPhase.partial);
      expect(s.remainingLines, 2);
      final snap = await snapshot();
      expect(snap?.pending, isNull, reason: 'kalanlar yeni niyet');
      expect(snap?.draft.lines, hasLength(2));
      expect(snap?.draft.paymentGroupKey, 'g-7');
      expect(snap?.draft.origin, DraftOrigin.partial);
      expect(snap?.created.single.orderNumber, 'SIP-13101');

      repo.placeScript.add(_ok(id: 13102, group: 'g-7'));
      final rest = requestOf(snap!.draft);
      await c.read(orderSubmitProvider.notifier).sendRemaining(rest);
      expect(c.read(orderSubmitProvider).phase, SubmitPhase.success);
      expect(repo.placeCalls, hasLength(2));
      expect(repo.placeCalls[1].key, isNot(repo.placeCalls[0].key));
      expect(repo.placeCalls[1].request.paymentGroupKey, 'g-7');
      expect(repo.placeCalls[1].request.lines, hasLength(2));
      expect(c.read(orderSubmitProvider).created.map((o) => o.orderId), [
        13101,
        13102,
      ]);
    },
  );

  test(
    'kesin ret (400): anahtar bırakılır, yeni gönderim yeni anahtar',
    () async {
      final c = container();
      repo.placeScript.add(
        const BusinessFailure('Bu bayide şu an sipariş veremezsiniz.'),
      );
      final d = draft();
      await c.read(orderSubmitProvider.notifier).submit(d, requestOf(d));
      final s = c.read(orderSubmitProvider);
      expect(s.phase, SubmitPhase.failed);
      expect(s.failure?.message, 'Bu bayide şu an sipariş veremezsiniz.');
      expect((await snapshot())?.pending, isNull);
      expect(
        (await snapshot())?.draft.lines,
        hasLength(1),
        reason: 'taslak kalır',
      );
      await c.read(orderSubmitProvider.notifier).backToEditing();
      repo.placeScript.add(_ok());
      await c.read(orderSubmitProvider.notifier).submit(d, requestOf(d));
      expect(repo.placeCalls[1].key, isNot(repo.placeCalls[0].key));
    },
  );

  test('aynı gövde yeniden gönderilirse bekleyen anahtar kullanılır', () async {
    final c = container();
    for (var i = 0; i < 6; i++) {
      repo.placeScript.add(const TimeoutFailure());
    }
    final d = draft();
    await c.read(orderSubmitProvider.notifier).submit(d, requestOf(d));
    expect(c.read(orderSubmitProvider).phase, SubmitPhase.uncertain);
    final key = repo.placeCalls.first.key;
    c.read(orderSubmitProvider.notifier).acknowledge();
    repo.placeScript.add(_ok());
    await c.read(orderSubmitProvider.notifier).submit(d, requestOf(d));
    expect(repo.placeCalls.last.key, key);
  });

  test(
    'uygulama kapanıp açılınca (yeni kapsayıcı) aynı anahtarla sürer',
    () async {
      final hang = Completer<PlaceOrderResult>();
      repo.placeScript.add(hang);
      final first = container();
      final d = draft(lines: 2);
      unawaited(
        first.read(orderSubmitProvider.notifier).submit(d, requestOf(d)),
      );
      await settle(() => repo.placeCalls.isNotEmpty);
      final key = repo.placeCalls.single.key;
      expect(
        (await snapshot())?.pending?.key,
        key,
        reason: 'göndermeden önce saklandı',
      );
      first.dispose();

      final relaunched = ScriptedRepo()..placeScript.add(_ok(id: 13200));
      final second = container(using: relaunched);
      expect(await second.read(draftSummaryProvider.future), isNotNull);
      final resumed = await second
          .read(orderSubmitProvider.notifier)
          .resumeIfPending();
      expect(resumed, isTrue);
      expect(relaunched.placeCalls.single.key, key);
      expect(relaunched.placeCalls.single.request.lines, hasLength(2));
      expect(second.read(orderSubmitProvider).phase, SubmitPhase.success);
      expect(await snapshot(), isNull);
      hang.complete(_ok());
    },
  );

  test('yeniden deneme planı', () {
    const p = RetryPolicy();
    expect(p.delayFor(0), const Duration(seconds: 2));
    expect(p.delayFor(3), const Duration(seconds: 16));
    expect(p.delayFor(9), const Duration(seconds: 16));
    expect(p.allows(0, Duration.zero), isTrue);
    expect(p.allows(5, const Duration(seconds: 46)), isFalse);
    expect(p.allows(5, const Duration(seconds: 46), inProgress: true), isTrue);
    expect(isRetryableFailure(const TimeoutFailure()), isTrue);
    expect(isRetryableFailure(const BusinessFailure('x')), isFalse);
    expect(isRetryableFailure(const UnknownFailure.cancelled()), isFalse);
    expect(
      isRetryableFailure(ConflictFailure('idempotency_in_progress')),
      isTrue,
    );
    expect(
      isRetryableFailure(ConflictFailure('concurrency_conflict')),
      isFalse,
    );
  });
}

Future<void> settle(bool Function() condition) async {
  for (var i = 0; i < 400 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

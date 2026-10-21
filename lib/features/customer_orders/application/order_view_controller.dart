import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/models/models.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/network/network_providers.dart';
import '../../../core/offline/cache_store.dart';
import '../../../core/push/push_providers.dart';
import '../../../core/utils/log.dart';
import '../data/customer_orders_repository.dart';
import '../data/order_models.dart';
import '../data/payment_models.dart';
import 'loadable.dart';

/// Sipariş ayrıntı ekranının verisi: ayrıntı + takip + ödeme belgesi durumu.
@immutable
class OrderView {
  const OrderView({
    required this.detail,
    this.tracking,
    this.documentTarget,
    this.documents = const [],
    this.advanceBalance,
  });

  final OrderDetail detail;
  final OrderTracking? tracking;

  /// Ödeme belgesi hedefi (çek / senet görseli, havale dekontu); belge gerekmiyorsa null.
  final PaymentUploadTarget? documentTarget;

  /// Hedefe ve siparişe yüklenmiş etkin belgeler.
  final List<Attachment> documents;

  /// AVANS ile ödenen ve karar bekleyen siparişte kullanılabilir bakiye.
  final double? advanceBalance;

  /// Kararın verileceği teklif: en yüksek sürüm (sunucu `expectedQuoteId` bunu bekler).
  Quote? get latestQuote {
    if (detail.quotes.isEmpty) return null;
    return detail.quotes.reduce((a, b) => a.version >= b.version ? a : b);
  }

  /// Sürümler (yeni önce).
  List<Quote> get quoteVersions =>
      [...detail.quotes]..sort((a, b) => b.version.compareTo(a.version));

  /// Ödeme belgesi türünde etkin belge var mı.
  bool get hasPaymentDocument {
    final t = documentTarget;
    if (t == null) return false;
    return documents.any((a) => a.isActive && a.kind == t.kind);
  }

  /// Zorunlu belge (çek / senet görseli) eksik: teklif onaylanamaz (sunucu kuralının yaklaşığı).
  bool get paymentDocumentMissing {
    final t = documentTarget;
    if (t == null || !t.required) return false;
    if (detail.paymentStatus != PaymentStatus.pending) return false;
    return !hasPaymentDocument;
  }

  /// AVANS bakiyesi teklif toplamını karşılamıyor.
  bool get advanceInsufficient {
    final bal = advanceBalance;
    final q = latestQuote;
    if (bal == null || q == null) return false;
    return detail.paymentMethodCode == PaymentCodes.advance &&
        bal < q.totalAmountTry;
  }

  JsonMap toCache({
    required Object? detailRaw,
    required Object? trackingRaw,
    required Object? documentsRaw,
  }) => {
    'detail': detailRaw,
    'tracking': trackingRaw,
    'target': documentTarget?.toJson(),
    'documents': documentsRaw,
    'advanceBalance': advanceBalance,
  };

  static OrderView fromCache(Object? json) {
    final r = JsonReader.of(json);
    final tracking = r['tracking'];
    return OrderView(
      detail: OrderDetail.fromJson(r['detail']),
      tracking: tracking is Map ? OrderTracking.fromJson(tracking) : null,
      documentTarget: PaymentUploadTarget.tryParse(r['target']),
      documents: JsonReader.parseList(r['documents'], Attachment.fromJson),
      advanceBalance: r.decOrNull('advanceBalance'),
    );
  }

  OrderView withDocuments(List<Attachment> docs) => OrderView(
    detail: detail,
    tracking: tracking,
    documentTarget: documentTarget,
    documents: docs,
    advanceBalance: advanceBalance,
  );
}

/// Teklif / takip yoklamasının açık olduğu durumlar (spec A.4: 30 sn).
bool shouldPollOrder(OrderView v) {
  final s = v.detail.status;
  if (s == OrderStatus.awaitingQuote ||
      s == OrderStatus.revisionRequested ||
      s == OrderStatus.created) {
    return true;
  }
  final t = v.tracking;
  if (t == null) return false;
  return t.shipments.any(
    (x) =>
        x.status == ShipmentStatus.inTransit ||
        x.status == ShipmentStatus.reported,
  );
}

/// `orders/{id}` + `orders/{id}/tracking` (+ belge hedefi ve ekler). Son açılan 20 sipariş
/// çevrimdışı için saklanır.
final orderViewProvider = NotifierProvider.autoDispose
    .family<OrderViewController, Loadable<OrderView>, int>(
      OrderViewController.new,
    );

class OrderViewController
    extends AutoDisposeFamilyNotifier<Loadable<OrderView>, int> {
  int _epoch = 0;
  bool _alive = true;
  Future<void>? _inFlight;

  @override
  Loadable<OrderView> build(int orderId) {
    _alive = true;
    ref.onDispose(() => _alive = false);
    final uid = ref.watch(currentUserIdProvider);
    final epoch = ++_epoch;
    ref.listen(pushEventsProvider, (_, next) {
      final p = next.valueOrNull?.payload;
      if (p == null) return;
      final mine =
          (p.entityType == 'Order' && p.entityId == orderId) ||
          p.entityType == 'Shipment' ||
          (p.route?.contains('/orders/$orderId') ?? false);
      if (mine) unawaited(refresh());
    });
    // Müşteri verisi başka bir sayfada değişti (sevkiyat kabul / itiraz, ödeme belgesi): açık
    // sipariş ayrıntısı da tazelenir (QA C-03).
    ref.listen(a2DataRevisionProvider, (_, _) => unawaited(refresh()));
    if (uid == null) return const Loadable();
    Future.microtask(() => _start(uid, epoch));
    return const Loadable.initial();
  }

  Future<void> _start(String uid, int epoch) async {
    if (!_alive) return;
    final cached = await ref
        .read(cacheStoreProvider)
        .read(A2Keys.order(uid, arg));
    if (!_alive || epoch != _epoch) return;
    if (cached != null && state.data == null) {
      try {
        state = Loadable(
          data: OrderView.fromCache(cached.value),
          loading: true,
          updatedAt: cached.storedAt,
          fromCache: true,
        );
      } catch (e) {
        AppLog.warn('Sipariş önbelleği okunamadı', error: e);
      }
    }
    await refresh();
  }

  /// Sunucudan tazeler; içerik kalır. Eşzamanlı çağrılar birleşir.
  Future<void> refresh() {
    final running = _inFlight;
    if (running != null) return running;
    final f = _load();
    _inFlight = f;
    return f.whenComplete(() => _inFlight = null);
  }

  /// Sunucunun en güncel hâlini döndürür (belirsiz karar sonrası doğrulama).
  Future<OrderView?> reload() async {
    await refresh();
    return state.data;
  }

  Future<void> _load() async {
    if (!_alive) return;
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final epoch = _epoch;
    final repo = ref.read(customerOrdersRepositoryProvider);
    final api = ref.read(apiClientProvider);
    final cache = ref.read(cacheStoreProvider);
    state = state.copyWith(loading: true);
    try {
      final results = await Future.wait<Object?>([
        repo.orderRaw(arg),
        repo.trackingRaw(arg).then<Object?>((v) => v, onError: (_) => null),
      ]);
      final detailRaw = results[0];
      final trackingRaw = results[1];
      final detail = OrderDetail.fromJson(detailRaw);
      final tracking = trackingRaw is Map
          ? OrderTracking.fromJson(trackingRaw)
          : null;

      PaymentUploadTarget? target;
      Object? docsRaw;
      var docs = const <Attachment>[];
      final method = detail.paymentMethodCode;
      if (method == PaymentCodes.cheque ||
          method == PaymentCodes.promissoryNote ||
          method == PaymentCodes.transfer) {
        try {
          target = await repo.documentTarget(
            methodCode: method,
            groupKey: detail.paymentGroupKey,
            orderIds: [arg],
          );
          final owners = <(AttachmentOwnerType, int)>{
            if (target != null && target.ownerId > 0)
              (target.ownerType, target.ownerId),
            (AttachmentOwnerType.order, arg),
          };
          final all = <Object?>[];
          for (final (type, id) in owners) {
            final raw = await api.get<Object?>(
              'attachments',
              query: {'ownerType': type.code, 'ownerId': id},
              parse: (j) => j,
            );
            if (raw is List) all.addAll(raw);
          }
          docsRaw = all;
          docs = JsonReader.parseList(all, Attachment.fromJson);
        } on AppFailure catch (f) {
          AppLog.debug('Ödeme belgesi durumu alınamadı: $f');
        }
      }

      double? advance;
      if (method == PaymentCodes.advance &&
          detail.status == OrderStatus.awaitingApproval) {
        try {
          final o = await repo.paymentOptions(
            stationId: detail.stationId,
            productIds: [detail.productId],
          );
          advance = o.options.advanceBalance;
        } on AppFailure catch (f) {
          AppLog.debug('Avans bakiyesi alınamadı: $f');
        }
      }

      if (!_alive || epoch != _epoch) return;
      final view = OrderView(
        detail: detail,
        tracking: tracking,
        documentTarget: target,
        documents: docs,
        advanceBalance: advance,
      );
      state = Loadable(data: view, updatedAt: DateTime.now().toUtc());
      await cache.write(
        A2Keys.order(uid, arg),
        view.toCache(
          detailRaw: detailRaw,
          trackingRaw: trackingRaw,
          documentsRaw: docsRaw,
        ),
        userId: uid,
      );
      await rememberRecentOrder(cache, uid, arg);
    } on AppFailure catch (f) {
      if (!_alive || epoch != _epoch) return;
      state = state.copyWith(loading: false, error: f);
    }
  }
}

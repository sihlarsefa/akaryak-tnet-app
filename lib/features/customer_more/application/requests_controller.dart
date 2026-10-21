import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/media/image_capture.dart';
import '../../../core/models/enums.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/utils/turkish_text.dart';
import '../data/customer_more_repository.dart';
import '../data/order_requests.dart';
import 'cm_common.dart';
import 'paged.dart';

/// Talepler bölümü.
enum RequestSegment {
  pending('Bekleyen', [CustomerOrderRequestStatus.pending]),
  all('Tümü', []);

  const RequestSegment(this.label, this.statuses);
  final String label;
  final List<CustomerOrderRequestStatus> statuses;
}

@immutable
class RequestsState {
  const RequestsState({
    this.segment = RequestSegment.all,
    this.page = const PagedState(),
  });

  final RequestSegment segment;
  final PagedState<OrderRequest> page;

  RequestsState copyWith({
    RequestSegment? segment,
    PagedState<OrderRequest>? page,
  }) =>
      RequestsState(segment: segment ?? this.segment, page: page ?? this.page);
}

/// Şirket içi sipariş talepleri (`customers/me/order-requests?skip&take`; Talep eden yalnızca kendi
/// taleplerini görür — sunucu kuralı).
final requestsControllerProvider =
    NotifierProvider.autoDispose<RequestsController, RequestsState>(
      RequestsController.new,
    );

class RequestsController extends AutoDisposeNotifier<RequestsState> {
  static const take = 25;
  int _epoch = 0;
  bool _disposed = false;

  @override
  RequestsState build() {
    ref.watch(currentUserIdProvider);
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _epoch++;
    });
    Future.microtask(load);
    return const RequestsState();
  }

  CustomerMoreRepository get _repo => ref.read(customerMoreRepositoryProvider);

  Future<void> load({bool refresh = false}) async {
    if (_disposed) return;
    final epoch = ++_epoch;
    final s = state;
    state = s.copyWith(
      page: refresh && s.page.items.isNotEmpty
          ? s.page.copyWith(refreshing: true, clearError: true)
          : PagedState<OrderRequest>(items: s.page.items),
    );
    try {
      final res = await _repo.orderRequests(
        take: take,
        statuses: s.segment.statuses,
      );
      if (epoch != _epoch) return;
      state = state.copyWith(
        page: PagedState(
          items: res.items,
          total: res.totalCount,
          hasMore: res.items.length < res.totalCount,
          loading: false,
        ),
      );
    } catch (e) {
      if (epoch != _epoch) return;
      state = state.copyWith(
        page: state.page.copyWith(
          loading: false,
          refreshing: false,
          error: AppFailure.from(e),
        ),
      );
    }
  }

  Future<void> loadMore() async {
    final s = state;
    final p = s.page;
    if (_disposed || !p.hasMore || p.loadingMore || p.loading) return;
    final epoch = _epoch;
    state = s.copyWith(
      page: p.copyWith(loadingMore: true, clearLoadMoreError: true),
    );
    try {
      final res = await _repo.orderRequests(
        skip: p.items.length,
        take: take,
        statuses: s.segment.statuses,
      );
      if (epoch != _epoch) return;
      final known = {for (final r in state.page.items) r.id};
      final items = [
        ...state.page.items,
        ...res.items.where((r) => !known.contains(r.id)),
      ];
      state = state.copyWith(
        page: state.page.copyWith(
          items: items,
          total: res.totalCount,
          hasMore: res.items.isNotEmpty && items.length < res.totalCount,
          loadingMore: false,
        ),
      );
    } catch (e) {
      if (epoch != _epoch) return;
      state = state.copyWith(
        page: state.page.copyWith(
          loadingMore: false,
          loadMoreError: AppFailure.from(e),
        ),
      );
    }
  }

  void setSegment(RequestSegment segment) {
    if (segment == state.segment) return;
    state = state.copyWith(segment: segment);
    unawaited(load());
  }
}

/// Talep ayrıntısı.
final orderRequestProvider = FutureProvider.autoDispose
    .family<OrderRequest, int>((ref, id) {
      ref.watch(currentUserIdProvider);
      return ref.read(customerMoreRepositoryProvider).orderRequest(id);
    });

/// Siparişler oluştuktan sonra ödeme belgesinin durumu (çek / senet görseli, dekont).
/// Hedef sunucudan (`orders/payment-document-target`) okunur; uç eski sunucuda yoksa yöntem kodundan
/// çıkarılır. Belge gerekmiyorsa null.
final requestPaymentDocProvider = FutureProvider.autoDispose
    .family<PaymentDocumentState?, int>((ref, requestId) async {
      ref.watch(currentUserIdProvider);
      final request = await ref.watch(orderRequestProvider(requestId).future);
      return ref.read(requestCommandsProvider).paymentDocState(request);
    });

final requestCommandsProvider = Provider<RequestCommands>(
  (ref) => RequestCommands(ref),
);

class RequestCommands {
  RequestCommands(this.ref);

  final Ref ref;

  CustomerMoreRepository get _repo => ref.read(customerMoreRepositoryProvider);

  /// Bekleyen kendi talebini geri çeker; sunucu mesajını döndürür.
  Future<String> cancel(int id) async {
    final message = await _repo.cancelOrderRequest(id);
    ref.invalidate(orderRequestProvider(id));
    return message ?? 'Talep iptal edildi.';
  }

  /// Yöntem kodundan belge hedefi (sunucu ucu yoksa).
  static PaymentUploadTarget? fallbackTarget(OrderRequest r) {
    if (!r.hasOrders) return null;
    final kind = switch (TurkishText.upper(r.paymentMethodCode ?? '')) {
      'CEK' => AttachmentKind.chequeImage,
      'SENET' => AttachmentKind.promissoryNoteImage,
      'HAVALE' => AttachmentKind.transferReceipt,
      _ => null,
    };
    if (kind == null) return null;
    return PaymentUploadTarget(
      ownerType: AttachmentOwnerType.order,
      ownerId: r.createdOrderIds.first,
      kind: kind,
      required: kind != AttachmentKind.transferReceipt,
      canUpload: true,
      orderId: r.createdOrderIds.first,
    );
  }

  Future<PaymentDocumentState?> paymentDocState(OrderRequest r) async {
    if (!r.hasOrders) return null;
    PaymentUploadTarget? target;
    var fallback = false;
    try {
      target = await _repo.paymentDocumentTarget(
        orderIds: r.createdOrderIds,
        methodCode: r.paymentMethodCode,
      );
    } on NotFoundFailure {
      target = fallbackTarget(r);
      fallback = true;
    }
    if (target == null) return null;
    final list = await _repo.attachmentsOf(target.ownerType, target.ownerId);
    final uploaded = list.any((a) => a.isActive && a.kind == target!.kind);
    return PaymentDocumentState(
      target: target,
      uploaded: uploaded,
      fromFallback: fallback,
    );
  }

  /// Ödeme belgesini yükler (Idempotency-Key; tekrar denemede aynı anahtar).
  Future<void> uploadPaymentDoc(
    int requestId,
    PaymentUploadTarget target,
    CapturedImage image, {
    void Function(double progress)? onProgress,
  }) async {
    final ledger = ref.read(cmLedgerProvider);
    final intent =
        'request.paymentDoc:$requestId:${target.ownerType.code}:${target.ownerId}:${image.fileName}';
    final key = ledger.keyFor(intent);
    try {
      await _repo.uploadPaymentDocument(
        ownerType: target.ownerType,
        ownerId: target.ownerId,
        kind: target.kind,
        bytes: image.bytes,
        fileName: image.fileName,
        contentType: image.contentType,
        idempotencyKey: key,
        onProgress: onProgress,
      );
      ledger.settle(intent);
    } catch (e) {
      ledger.settle(intent, error: e);
      throw AppFailure.from(e);
    }
    ref.invalidate(requestPaymentDocProvider(requestId));
  }
}

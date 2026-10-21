import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/media/image_capture.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/shipment.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/network/idempotency.dart';
import '../data/customer_more_repository.dart';
import '../data/shipments.dart';
import 'cm_common.dart';
import 'paged.dart';

/// Teslimatlar listesinin bölümü.
enum ShipmentSegment {
  active('Aktif', [
    ShipmentStatus.reported,
    ShipmentStatus.inTransit,
    ShipmentStatus.planned,
    ShipmentStatus.disputed,
  ], 1),
  history('Geçmiş', [ShipmentStatus.accepted, ShipmentStatus.cancelled], 3);

  const ShipmentSegment(this.label, this.statuses, this.sort);
  final String label;
  final List<ShipmentStatus> statuses;

  /// `ShipmentSort`: aktifte plan tarihi (eski → yeni), geçmişte teslim (yeni → eski).
  final int sort;
}

@immutable
class ShipmentsState {
  const ShipmentsState({
    this.segment = ShipmentSegment.active,
    this.status,
    this.search = '',
    this.page = const PagedState(),
    this.counts = const ShipmentCounts(),
  });

  final ShipmentSegment segment;

  /// Bölüm içinde tek durum çipi (null = bölümün tümü).
  final ShipmentStatus? status;
  final String search;
  final PagedState<ShipmentListItem> page;

  /// Sunucu sayaçları (arama ölçütüyle, durumdan bağımsız).
  final ShipmentCounts counts;

  int segmentCount(ShipmentSegment s) =>
      s.statuses.fold(0, (sum, x) => sum + counts.of(x));

  bool get filtered => status != null || search.trim().isNotEmpty;

  ShipmentsState copyWith({
    ShipmentSegment? segment,
    ShipmentStatus? status,
    bool clearStatus = false,
    String? search,
    PagedState<ShipmentListItem>? page,
    ShipmentCounts? counts,
  }) => ShipmentsState(
    segment: segment ?? this.segment,
    status: clearStatus ? null : (status ?? this.status),
    search: search ?? this.search,
    page: page ?? this.page,
    counts: counts ?? this.counts,
  );
}

/// `GET shipments` (müşteri: kendi carisinin teslimatları). Ölçüt değişince ilk sayfa yeniden okunur;
/// eski yanıtlar sürüm koruması ile yok sayılır.
final shipmentsControllerProvider =
    NotifierProvider.autoDispose<ShipmentsController, ShipmentsState>(
      ShipmentsController.new,
    );

class ShipmentsController extends AutoDisposeNotifier<ShipmentsState> {
  static const pageSize = 25;
  int _epoch = 0;
  bool _disposed = false;

  @override
  ShipmentsState build() {
    ref.watch(currentUserIdProvider);
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _epoch++;
    });
    Future.microtask(load);
    return const ShipmentsState();
  }

  CustomerMoreRepository get _repo => ref.read(customerMoreRepositoryProvider);

  ShipmentQuery _query(ShipmentsState s) => ShipmentQuery(
    statuses: s.status == null ? s.segment.statuses : [s.status!],
    search: s.search.trim().isEmpty ? null : s.search.trim(),
    sort: s.segment.sort,
  );

  /// İlk sayfa. [refresh]: içerik korunur, üstte ince çubuk.
  Future<void> load({bool refresh = false}) async {
    if (_disposed) return;
    final epoch = ++_epoch;
    final s = state;
    state = s.copyWith(
      page: refresh && s.page.items.isNotEmpty
          ? s.page.copyWith(refreshing: true, clearError: true)
          : PagedState<ShipmentListItem>(loading: true, items: s.page.items),
    );
    try {
      final res = await _repo.shipments(_query(s), pageSize: pageSize);
      if (epoch != _epoch) return;
      state = state.copyWith(
        counts: res.counts,
        page: PagedState(
          items: res.items,
          total: res.totalFiltered,
          hasMore: res.hasMore,
          loading: false,
        ),
      );
    } catch (e) {
      if (epoch != _epoch) return;
      final f = AppFailure.from(e);
      state = state.copyWith(
        page: state.page.copyWith(loading: false, refreshing: false, error: f),
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
    final next = p.items.length ~/ pageSize + 1;
    try {
      final res = await _repo.shipments(
        _query(s),
        page: next,
        pageSize: pageSize,
      );
      if (epoch != _epoch) return;
      final known = {for (final i in state.page.items) i.id};
      state = state.copyWith(
        page: state.page.copyWith(
          items: [
            ...state.page.items,
            ...res.items.where((i) => !known.contains(i.id)),
          ],
          total: res.totalFiltered,
          hasMore: res.hasMore,
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

  void setSegment(ShipmentSegment segment) {
    if (segment == state.segment) return;
    state = state.copyWith(segment: segment, clearStatus: true);
    unawaited(load());
  }

  void setStatus(ShipmentStatus? status) {
    if (status == state.status) return;
    state = status == null
        ? state.copyWith(clearStatus: true)
        : state.copyWith(status: status);
    unawaited(load());
  }

  void setSearch(String q) {
    if (q.trim() == state.search.trim()) return;
    state = state.copyWith(search: q);
    unawaited(load());
  }

  void clearFilters() {
    state = state.copyWith(clearStatus: true, search: '');
    unawaited(load());
  }
}

/// `GET shipments/{id}/detail`.
final shipmentDetailProvider = FutureProvider.autoDispose
    .family<ShipmentDetail, int>((ref, id) {
      ref.watch(currentUserIdProvider);
      return ref.read(customerMoreRepositoryProvider).shipmentDetail(id);
    });

/// İtiraz için seçilen fotoğraf (önce yüklenir, sonra itiraz gönderilir).
@immutable
class DisputePhoto {
  const DisputePhoto({
    required this.localId,
    required this.image,
    this.progress = 0,
    this.uploadedPublicId,
    this.error,
  });

  final String localId;
  final CapturedImage image;
  final double progress;
  final String? uploadedPublicId;
  final String? error;

  bool get uploaded => uploadedPublicId != null;
  bool get failed => error != null && !uploaded;

  DisputePhoto copyWith({
    double? progress,
    String? uploadedPublicId,
    String? error,
    bool clearError = false,
  }) => DisputePhoto(
    localId: localId,
    image: image,
    progress: progress ?? this.progress,
    uploadedPublicId: uploadedPublicId ?? this.uploadedPublicId,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Kabul ve itiraz eylemleri (Idempotency-Key + belirsiz sonuçta yeniden okuma).
final shipmentCommandsProvider = Provider<ShipmentCommands>(
  (ref) => ShipmentCommands(ref),
);

class ShipmentCommands {
  ShipmentCommands(this.ref);

  final Ref ref;

  CustomerMoreRepository get _repo => ref.read(customerMoreRepositoryProvider);
  IdempotencyLedger get _ledger => ref.read(cmLedgerProvider);

  Future<bool> _reached(int id, ShipmentStatus target) async {
    final d = await _repo.shipmentDetail(id);
    return d.status == target;
  }

  /// Teslimatı kabul eder. Belirsiz sonuçta sunucudaki durum "Teslim alındı" ise başarıdır.
  Future<void> accept(int id, {VoidCallback? onChecking}) async {
    await runIdempotent(
      ledger: _ledger,
      intent: 'shipment.accept:$id',
      call: (key) => _repo.acceptShipment(id, idempotencyKey: key),
      reachedTarget: () => _reached(id, ShipmentStatus.accepted),
      retryDelays: ref.read(cmRetryDelaysProvider),
      onChecking: onChecking,
    );
    ref.invalidate(shipmentDetailProvider(id));
  }

  /// İtiraz fotoğrafını yükler (fotoğraf başına bir anahtar; tekrar denemede aynı anahtar).
  Future<String> uploadPhoto(
    int shipmentId,
    DisputePhoto photo, {
    void Function(double progress)? onProgress,
  }) async {
    final intent = 'shipment.disputePhoto:$shipmentId:${photo.localId}';
    final key = _ledger.keyFor(intent);
    try {
      final res = await _repo.uploadDisputePhoto(
        shipmentId: shipmentId,
        bytes: photo.image.bytes,
        fileName: photo.image.fileName,
        idempotencyKey: key,
        onProgress: onProgress,
      );
      _ledger.settle(intent);
      return res.attachment.publicId;
    } catch (e) {
      _ledger.settle(intent, error: e);
      throw AppFailure.from(e);
    }
  }

  /// İtirazı gönderir (fotoğraflar önceden yüklenmiş olmalı). Not değişirse yeni niyet (yeni anahtar).
  Future<void> dispute(int id, String note, {VoidCallback? onChecking}) async {
    final clean = note.trim();
    await runIdempotent(
      ledger: _ledger,
      intent: 'shipment.dispute:$id:${clean.hashCode}',
      call: (key) => _repo.disputeShipment(id, clean, idempotencyKey: key),
      reachedTarget: () => _reached(id, ShipmentStatus.disputed),
      retryDelays: ref.read(cmRetryDelaysProvider),
      onChecking: onChecking,
    );
    ref.invalidate(shipmentDetailProvider(id));
  }

  /// Yüklenmiş itiraz fotoğrafını kaldırır (yalnızca kabul bekleyen sevkiyatta, yükleyen).
  Future<void> removePhoto(String publicId) => _repo.deleteAttachment(publicId);

  /// Benzersiz yerel fotoğraf kimliği.
  static String newLocalId() => newIdempotencyKey();
}

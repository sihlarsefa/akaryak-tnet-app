import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/push/push_providers.dart';
import '../data/driver_models.dart';
import '../data/driver_repository.dart';
import 'driver_ops.dart';

/// Bir sekmenin durumu: satırlar, sayfalama, önbellek bilgisi, arka plan yenilemesi.
@immutable
class DriverListState {
  const DriverListState({
    this.items = const [],
    this.totalCount = 0,
    this.page = 1,
    this.totalPages = 1,
    this.updatedAt,
    this.fromCache = false,
    this.refreshing = false,
    this.loadingMore = false,
    this.refreshError,
    this.loadMoreError,
  });

  factory DriverListState.fromData(DriverListData d) => DriverListState(
    items: d.items,
    totalCount: d.totalCount,
    page: d.page,
    totalPages: d.totalPages,
    updatedAt: d.storedAt ?? DateTime.now().toUtc(),
    fromCache: d.storedAt != null,
  );

  final List<DriverShipmentRow> items;
  final int totalCount;
  final int page;
  final int totalPages;

  /// Verinin sunucudan alındığı an (önbellekte saklanma anı).
  final DateTime? updatedAt;

  /// Önbellekten gösteriliyor (henüz sunucudan tazelenmedi ya da tazelenemedi).
  final bool fromCache;
  final bool refreshing;
  final bool loadingMore;

  /// Veri varken başarısız yenileme (ör. çevrimdışı): veri kalır, şerit gösterilir.
  final AppFailure? refreshError;
  final AppFailure? loadMoreError;

  bool get hasMore => page < totalPages;
  bool get isEmpty => items.isEmpty;

  /// Bugün sekmesinde açık (sıradaki) teslimatlar.
  List<DriverShipmentRow> get open => [
    for (final r in items)
      if (r.isOpen) r,
  ];

  List<DriverShipmentRow> get closed => [
    for (final r in items)
      if (!r.isOpen) r,
  ];

  DriverListState copyWith({
    List<DriverShipmentRow>? items,
    int? totalCount,
    int? page,
    int? totalPages,
    bool? refreshing,
    bool? loadingMore,
    AppFailure? refreshError,
    bool clearRefreshError = false,
    AppFailure? loadMoreError,
    bool clearLoadMoreError = false,
    bool? fromCache,
  }) => DriverListState(
    items: items ?? this.items,
    totalCount: totalCount ?? this.totalCount,
    page: page ?? this.page,
    totalPages: totalPages ?? this.totalPages,
    updatedAt: updatedAt,
    fromCache: fromCache ?? this.fromCache,
    refreshing: refreshing ?? this.refreshing,
    loadingMore: loadingMore ?? this.loadingMore,
    refreshError: clearRefreshError
        ? null
        : (refreshError ?? this.refreshError),
    loadMoreError: clearLoadMoreError
        ? null
        : (loadMoreError ?? this.loadMoreError),
  );

  /// Sonsuz kaydırma: sonraki sayfa eklenir (aynı kimlik tekrar eklenmez).
  DriverListState append(DriverListData next) {
    final seen = {for (final r in items) r.id};
    return DriverListState(
      items: List.unmodifiable([
        ...items,
        for (final r in next.items)
          if (!seen.contains(r.id)) r,
      ]),
      totalCount: next.totalCount,
      page: next.page,
      totalPages: next.totalPages,
      updatedAt: updatedAt,
      fromCache: fromCache,
    );
  }
}

/// Sekme listeleri. Önce önbellek (çevrimdışı açılış), sonra sunucu; yola çıkış / teslim onaylanınca
/// ve sevkiyat push'u gelince yenilenir. Kullanıcı değişince sıfırlanır.
final driverListProvider =
    AsyncNotifierProvider.family<
      DriverListController,
      DriverListState,
      DriverTab
    >(DriverListController.new);

class DriverListController
    extends FamilyAsyncNotifier<DriverListState, DriverTab> {
  int _epoch = 0;
  Future<void>? _inflight;

  @override
  Future<DriverListState> build(DriverTab tab) async {
    final uid = ref.watch(currentUserIdProvider);
    final epoch = ++_epoch;
    _inflight = null;
    if (uid == null) return const DriverListState();
    ref.listen(driverChangesProvider, (_, _) => unawaited(refresh()));
    ref.listen(pushEventsProvider, (_, next) {
      final p = next.valueOrNull?.payload;
      if (p == null) return;
      if (p.category == 'shipments' || p.isFor('shipment.')) {
        unawaited(refresh());
      }
    });

    final repo = ref.read(driverRepositoryProvider);
    final cached = await repo.readTab(uid, tab);
    if (epoch != _epoch) return const DriverListState();
    if (cached != null) {
      unawaited(Future.microtask(refresh));
      return DriverListState.fromData(cached);
    }
    final fresh = await repo.fetchTab(uid, tab);
    _afterSuccess(uid, fresh);
    return DriverListState.fromData(fresh);
  }

  /// Arka planda yeniler: veri varsa korunur (üstte ince ilerleme çubuğu), hata şeride düşer.
  /// Aynı anda tek yenileme çalışır.
  Future<void> refresh() =>
      _inflight ??= _refresh().whenComplete(() => _inflight = null);

  Future<void> _refresh() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final epoch = _epoch;
    DriverListState? current;
    try {
      current = await future;
    } catch (_) {
      current = null;
    }
    if (epoch != _epoch) return;
    if (current != null) {
      state = AsyncData(
        current.copyWith(refreshing: true, clearRefreshError: true),
      );
    } else {
      state = const AsyncLoading<DriverListState>();
    }
    try {
      final fresh = await ref.read(driverRepositoryProvider).fetchTab(uid, arg);
      if (epoch != _epoch) return;
      state = AsyncData(DriverListState.fromData(fresh));
      _afterSuccess(uid, fresh);
    } catch (e, st) {
      if (epoch != _epoch) return;
      final f = AppFailure.from(e);
      final keep = current;
      if (keep != null && f is! NotFoundFailure && f is! ForbiddenFailure) {
        state = AsyncData(keep.copyWith(refreshing: false, refreshError: f));
      } else {
        state = AsyncError<DriverListState>(f, st);
      }
    }
  }

  /// Sonraki sayfa (Yaklaşan / Geçmiş).
  Future<void> loadMore() async {
    final uid = ref.read(currentUserIdProvider);
    final current = state.valueOrNull;
    if (uid == null || current == null) return;
    if (!current.hasMore || current.loadingMore || current.refreshing) return;
    final epoch = _epoch;
    state = AsyncData(
      current.copyWith(loadingMore: true, clearLoadMoreError: true),
    );
    try {
      final next = await ref
          .read(driverRepositoryProvider)
          .fetchTab(uid, arg, page: current.page + 1);
      if (epoch != _epoch) return;
      state = AsyncData(current.append(next));
    } catch (e) {
      if (epoch != _epoch) return;
      state = AsyncData(
        current.copyWith(loadingMore: false, loadMoreError: AppFailure.from(e)),
      );
    }
  }

  /// Başarılı yenilemeden sonra: ertelenmiş işlemleri hemen dene (bağlantı var) ve bugünün açık
  /// teslimatlarının ayrıntılarını önbelleğe al (teslim noktasında bağlantı olmasa da ayrıntı ve
  /// teslim zorunlulukları açılsın).
  void _afterSuccess(String uid, DriverListData data) {
    unawaited(ref.read(driverCommandsProvider).nudge().catchError((_) {}));
    if (arg == DriverTab.today) {
      unawaited(
        ref.read(driverRepositoryProvider).prefetchDetails(uid, [
          for (final r in data.items)
            if (r.isOpen) r.id,
        ]),
      );
    }
  }
}

/// Ayrıntı ekranının durumu.
@immutable
class DriverDetailState {
  const DriverDetailState(
    this.detail, {
    this.cachedAt,
    this.refreshing = false,
    this.refreshError,
  });

  final DriverShipmentDetail detail;

  /// Önbellekten gösteriliyorsa saklanma anı.
  final DateTime? cachedAt;
  final bool refreshing;
  final AppFailure? refreshError;

  DriverDetailState copyWith({bool? refreshing, AppFailure? refreshError}) =>
      DriverDetailState(
        detail,
        cachedAt: cachedAt,
        refreshing: refreshing ?? this.refreshing,
        refreshError: refreshError,
      );
}

/// Sevkiyat ayrıntısı (`GET driver/shipments/{id}`): önce önbellek, sonra sunucu. 404/403'te kayıt
/// artık bu şoföre ait değildir; önbellek gösterilmez.
final driverShipmentProvider = AsyncNotifierProvider.autoDispose
    .family<DriverShipmentController, DriverDetailState, int>(
      DriverShipmentController.new,
    );

class DriverShipmentController
    extends AutoDisposeFamilyAsyncNotifier<DriverDetailState, int> {
  int _epoch = 0;
  Future<void>? _inflight;

  @override
  Future<DriverDetailState> build(int id) async {
    final uid = ref.watch(currentUserIdProvider);
    final epoch = ++_epoch;
    _inflight = null;
    if (uid == null) throw const UnauthorizedFailure('unauthorized');
    ref.listen(driverChangesProvider, (_, next) {
      if (next.shipmentId == null || next.shipmentId == id) {
        unawaited(refresh());
      }
    });
    ref.listen(pushEventsProvider, (_, next) {
      final p = next.valueOrNull?.payload;
      if (p != null && p.entityType == 'Shipment' && p.entityId == id) {
        unawaited(refresh());
      }
    });
    final repo = ref.read(driverRepositoryProvider);
    final cached = await repo.readDetail(uid, id);
    if (epoch != _epoch) throw const UnknownFailure.cancelled();
    if (cached != null) {
      unawaited(Future.microtask(refresh));
      return DriverDetailState(cached.detail, cachedAt: cached.storedAt);
    }
    return DriverDetailState(await repo.fetchDetail(uid, id));
  }

  Future<void> refresh() =>
      _inflight ??= _refresh().whenComplete(() => _inflight = null);

  Future<void> _refresh() async {
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final epoch = _epoch;
    DriverDetailState? current;
    try {
      current = await future;
    } catch (_) {
      current = null;
    }
    if (epoch != _epoch) return;
    if (current != null) state = AsyncData(current.copyWith(refreshing: true));
    try {
      final d = await ref.read(driverRepositoryProvider).fetchDetail(uid, arg);
      if (epoch != _epoch) return;
      state = AsyncData(DriverDetailState(d));
    } catch (e, st) {
      if (epoch != _epoch) return;
      final f = AppFailure.from(e);
      final keep = current;
      if (keep != null && f is! NotFoundFailure && f is! ForbiddenFailure) {
        state = AsyncData(keep.copyWith(refreshing: false, refreshError: f));
      } else {
        state = AsyncError<DriverDetailState>(f, st);
      }
    }
  }
}

/// Sıradaki teslimat: yoldaki, yoksa gecikmiş plan, yoksa bugünkü ilk plan.
DriverShipmentRow? pickNextStop(List<DriverShipmentRow> today, DateTime now) {
  for (final r in today) {
    if (r.isInTransit) return r;
  }
  for (final r in today) {
    if (r.isOverdue(now)) return r;
  }
  for (final r in today) {
    if (r.isPlanned) return r;
  }
  return null;
}

/// Kullanıcıya atanmış açık teslimat sayısı (sahibi kendisi teslim eden bayi personeli için
/// "Size atanmış teslimatlar" kartı). Hata ya da yetki yoksa 0.
final driverAssignedCountProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return 0;
  ref.watch(driverChangesProvider);
  try {
    final page = await ref
        .read(driverRepositoryProvider)
        .fetchScope(DriverScope.active, pageSize: 1);
    return page.totalCount;
  } catch (_) {
    return 0;
  }
});

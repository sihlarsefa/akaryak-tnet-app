import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/cache_store.dart';
import '../data/customer_more_repository.dart';
import '../data/delivery_point.dart';
import 'cm_common.dart';

@immutable
class DeliveryPointsState {
  const DeliveryPointsState({
    this.points = const [],
    this.loading = true,
    this.refreshing = false,
    this.error,
    this.includeInactive = false,
    this.fromCache = false,
    this.storedAt,
  });

  final List<DeliveryPoint> points;
  final bool loading;
  final bool refreshing;
  final AppFailure? error;
  final bool includeInactive;
  final bool fromCache;
  final DateTime? storedAt;

  List<DeliveryPoint> get active => points.where((p) => p.isActive).toList();
  List<DeliveryPoint> get inactive => points.where((p) => !p.isActive).toList();

  DeliveryPointsState copyWith({
    List<DeliveryPoint>? points,
    bool? loading,
    bool? refreshing,
    AppFailure? error,
    bool clearError = false,
    bool? includeInactive,
    bool? fromCache,
    DateTime? storedAt,
    bool clearStoredAt = false,
  }) => DeliveryPointsState(
    points: points ?? this.points,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    error: clearError ? null : (error ?? this.error),
    includeInactive: includeInactive ?? this.includeInactive,
    fromCache: fromCache ?? this.fromCache,
    storedAt: clearStoredAt ? null : (storedAt ?? this.storedAt),
  );
}

/// Teslimat noktaları (`customers/me/delivery-points`). Etkin liste çevrimdışı için önbelleğe yazılır.
final deliveryPointsControllerProvider =
    NotifierProvider.autoDispose<DeliveryPointsController, DeliveryPointsState>(
      DeliveryPointsController.new,
    );

class DeliveryPointsController
    extends AutoDisposeNotifier<DeliveryPointsState> {
  int _epoch = 0;
  bool _disposed = false;

  @override
  DeliveryPointsState build() {
    ref.watch(currentUserIdProvider);
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _epoch++;
    });
    Future.microtask(load);
    return const DeliveryPointsState();
  }

  CustomerMoreRepository get _repo => ref.read(customerMoreRepositoryProvider);

  Future<void> load({bool refresh = false}) async {
    if (_disposed) return;
    final epoch = ++_epoch;
    final s = state;
    state = s.copyWith(
      loading: s.points.isEmpty,
      refreshing: s.points.isNotEmpty,
      clearError: true,
    );
    try {
      final loaded = await loadWithCache(
        cache: ref.read(cacheStoreProvider),
        userId: ref.read(currentUserIdProvider),
        name: CmCacheKeys.deliveryPoints,
        writeCache: !s.includeInactive,
        fetch: () =>
            _repo.deliveryPointsJson(includeInactive: s.includeInactive),
        parse: CustomerMoreRepository.parseDeliveryPoints,
      );
      if (epoch != _epoch) return;
      state = state.copyWith(
        points: loaded.value,
        loading: false,
        refreshing: false,
        fromCache: loaded.fromCache,
        storedAt: loaded.storedAt,
        clearStoredAt: loaded.storedAt == null,
      );
    } catch (e) {
      if (epoch != _epoch) return;
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: AppFailure.from(e),
      );
    }
  }

  void setIncludeInactive(bool v) {
    if (v == state.includeInactive) return;
    state = state.copyWith(includeInactive: v);
    unawaited(load(refresh: true));
  }

  /// Kaydeder ve listeyi yeniler → kimlik.
  Future<int> save(DeliveryPointDraft draft) async {
    final error = draft.validate();
    if (error != null) throw BusinessFailure(error);
    final id = await _repo.saveDeliveryPoint(draft);
    unawaited(load(refresh: true));
    return id;
  }

  /// Pasifleştirir; sunucu mesajını döndürür.
  Future<String> deactivate(int id) async {
    final message = await _repo.deactivateDeliveryPoint(id);
    if (!_disposed) {
      state = state.copyWith(
        points: [
          for (final p in state.points)
            if (p.id != id || state.includeInactive) p,
        ],
      );
    }
    unawaited(load(refresh: true));
    return message ?? 'Teslimat noktası pasifleştirildi.';
  }
}

/// Tek nokta (düzenleme sayfası; listede yoksa sunucudan okunur).
final deliveryPointProvider = FutureProvider.autoDispose
    .family<DeliveryPoint, int>((ref, id) async {
      ref.watch(currentUserIdProvider);
      return ref.read(customerMoreRepositoryProvider).deliveryPoint(id);
    });

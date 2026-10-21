import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/models/models.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/cache_store.dart';
import '../../../core/push/push_providers.dart';
import '../data/customer_orders_repository.dart';
import '../data/order_models.dart';
import 'loadable.dart';

/// Siparişlerim listesi durumu (bölüm başına).
@immutable
class OrdersListState {
  const OrdersListState({
    this.items = const [],
    this.page = 0,
    this.totalPages = 0,
    this.totalCount = 0,
    this.query = '',
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.updatedAt,
    this.fromCache = false,
    this.loaded = false,
  });

  final List<CustomerOrderRow> items;
  final int page;
  final int totalPages;
  final int totalCount;
  final String query;
  final bool loading;
  final bool loadingMore;
  final AppFailure? error;
  final DateTime? updatedAt;
  final bool fromCache;

  /// En az bir kez sunucudan ya da önbellekten veri geldi.
  final bool loaded;

  bool get hasMore => page < totalPages;
  bool get isFirstLoad => loading && !loaded;
  bool get showError => error != null && !loaded;

  OrdersListState copyWith({
    List<CustomerOrderRow>? items,
    int? page,
    int? totalPages,
    int? totalCount,
    String? query,
    bool? loading,
    bool? loadingMore,
    AppFailure? error,
    bool clearError = false,
    DateTime? updatedAt,
    bool? fromCache,
    bool? loaded,
  }) => OrdersListState(
    items: items ?? this.items,
    page: page ?? this.page,
    totalPages: totalPages ?? this.totalPages,
    totalCount: totalCount ?? this.totalCount,
    query: query ?? this.query,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: clearError ? null : (error ?? this.error),
    updatedAt: updatedAt ?? this.updatedAt,
    fromCache: fromCache ?? this.fromCache,
    loaded: loaded ?? this.loaded,
  );
}

/// `GET customers/me/orders?segment&q&page` (sayfalı). Aramasız ilk sayfa çevrimdışı için
/// önbelleklenir; push gelince tazelenir.
final ordersListProvider =
    NotifierProvider.family<
      OrdersListController,
      OrdersListState,
      OrderSegment
    >(OrdersListController.new);

class OrdersListController
    extends FamilyNotifier<OrdersListState, OrderSegment> {
  static const pageSize = 25;
  int _epoch = 0;
  bool _alive = true;

  @override
  OrdersListState build(OrderSegment segment) {
    _alive = true;
    ref.onDispose(() => _alive = false);
    final uid = ref.watch(currentUserIdProvider);
    ref.listen(a2DataRevisionProvider, (_, _) => unawaited(refresh()));
    ref.listen(pushEventsProvider, (_, next) {
      final p = next.valueOrNull?.payload;
      if (p == null) return;
      unawaited(refresh());
    });
    final epoch = ++_epoch;
    if (uid == null) return const OrdersListState();
    Future.microtask(() => _start(uid, epoch));
    return const OrdersListState(loading: true);
  }

  Future<void> _start(String uid, int epoch) async {
    if (!_alive) return;
    final cached = await ref
        .read(cacheStoreProvider)
        .read(A2Keys.ordersPage(uid, arg.code));
    if (!_alive || epoch != _epoch) return;
    if (cached != null && !state.loaded) {
      final page = PagedResult.fromJson(
        cached.value,
        CustomerOrderRow.fromJson,
      );
      state = state.copyWith(
        items: page.items,
        page: page.pageNumber,
        totalPages: page.totalPages,
        totalCount: page.totalCount,
        updatedAt: cached.storedAt,
        fromCache: true,
        loaded: true,
      );
    }
    await _fetch(page: 1, epoch: epoch);
  }

  /// İlk sayfayı yeniden yükler (içerik kalır).
  Future<void> refresh() => _fetch(page: 1, epoch: _epoch);

  /// Arama (300 ms gecikmeli alan çağırır).
  Future<void> search(String q) async {
    final query = q.trim();
    if (query == state.query) return;
    final epoch = ++_epoch;
    state = state.copyWith(query: query, loading: true, clearError: true);
    await _fetch(page: 1, epoch: epoch);
  }

  /// Sonsuz kaydırma: sıradaki sayfa.
  Future<void> loadMore() async {
    if (!state.hasMore || state.loadingMore || state.loading) return;
    state = state.copyWith(loadingMore: true);
    await _fetch(page: state.page + 1, epoch: _epoch);
  }

  Future<void> _fetch({required int page, required int epoch}) async {
    if (!_alive) return;
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    if (page == 1) state = state.copyWith(loading: true);
    final query = state.query;
    try {
      final raw = await ref
          .read(customerOrdersRepositoryProvider)
          .ordersRaw(
            segment: arg,
            q: query.isEmpty ? null : query,
            page: page,
            pageSize: pageSize,
          );
      if (!_alive || epoch != _epoch || query != state.query) return;
      final result = PagedResult.fromJson(raw, CustomerOrderRow.fromJson);
      state = state.copyWith(
        items: page == 1 ? result.items : [...state.items, ...result.items],
        page: result.pageNumber,
        totalPages: result.totalPages,
        totalCount: result.totalCount,
        loading: false,
        loadingMore: false,
        clearError: true,
        updatedAt: DateTime.now().toUtc(),
        fromCache: false,
        loaded: true,
      );
      if (page == 1 && query.isEmpty) {
        await ref
            .read(cacheStoreProvider)
            .write(A2Keys.ordersPage(uid, arg.code), raw, userId: uid);
      }
    } on AppFailure catch (f) {
      if (!_alive || epoch != _epoch) return;
      state = state.copyWith(loading: false, loadingMore: false, error: f);
    }
  }
}

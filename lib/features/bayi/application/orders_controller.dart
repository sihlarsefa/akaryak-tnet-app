import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/network/app_failure.dart';
import '../data/bayi_repository.dart';
import '../data/order_models.dart';
import 'bayi_runtime.dart';
import 'paged_loading.dart';

/// Siparişler listesi durumu.
@immutable
class BayiOrdersState {
  const BayiOrdersState({
    this.filter = const BayiOrdersFilter(),
    this.list = const PagedList.initial(),
    this.counts,
  });

  final BayiOrdersFilter filter;
  final PagedList<BayiOrderRow> list;

  /// Segment çiplerinin sayıları (yüklenemezse null: çipler sayısız gösterilir).
  final BayiOrderCounts? counts;

  BayiOrdersState copyWith({
    BayiOrdersFilter? filter,
    PagedList<BayiOrderRow>? list,
    Object? counts = _keep,
  }) => BayiOrdersState(
    filter: filter ?? this.filter,
    list: list ?? this.list,
    counts: counts == _keep ? this.counts : counts as BayiOrderCounts?,
  );
}

const Object _keep = Object();

/// `GET bayi/orders` + `GET bayi/orders/counts`: segment çipleri, arama, durum / ödeme / finans / cari /
/// tarih süzgeçleri ve sonsuz kaydırma.
final bayiOrdersProvider =
    NotifierProvider<BayiOrdersController, BayiOrdersState>(
      BayiOrdersController.new,
    );

class BayiOrdersController extends Notifier<BayiOrdersState>
    with PagedLoading<BayiOrderRow, BayiOrdersState> {
  BayiRepository get _repo => ref.read(bayiRepositoryProvider);

  @override
  BayiOrdersState build() {
    final user = ref.watch(currentUserIdProvider);
    final sub = ref.read(bayiChangesProvider).stream.listen((c) {
      if (c == BayiChange.orders ||
          c == BayiChange.quotes ||
          c == BayiChange.shipments) {
        unawaited(refresh(silent: true));
      }
    });
    ref.onDispose(sub.cancel);
    if (user == null) return const BayiOrdersState(list: PagedList());
    Future.microtask(refresh);
    return const BayiOrdersState();
  }

  @override
  PagedList<BayiOrderRow> get list => state.list;

  @override
  BayiOrdersState withList(PagedList<BayiOrderRow> next) =>
      state.copyWith(list: next);

  @override
  Object? identityOf(BayiOrderRow item) => item.id;

  @override
  Future<PagedChunk<BayiOrderRow>> fetchPage(int page) async {
    final r = await _repo.orders(state.filter, page: page);
    return (items: r.items, hasMore: r.hasMore, total: r.totalCount);
  }

  /// Liste ve sayılar.
  Future<void> refresh({bool silent = false}) async {
    await Future.wait([reload(silent: silent), loadCounts()]);
  }

  Future<void> loadCounts() async {
    try {
      final c = await _repo.orderCounts();
      state = state.copyWith(counts: c);
    } on AppFailure {
      // Sayılar yüklenemezse çipler sayısız kalır; liste etkilenmez.
    }
  }

  void setFilter(BayiOrdersFilter next) {
    if (next == state.filter) return;
    state = state.copyWith(filter: next);
    unawaited(reload());
  }

  void setSegment(BayiOrderSegment? s) =>
      setFilter(state.filter.copyWith(segment: s));

  void setQuery(String q) => setFilter(state.filter.copyWith(q: q));

  /// Tüm süzgeçleri temizler (arama dahil).
  void clearAll() => setFilter(const BayiOrdersFilter());
}

/// Sipariş ayrıntısı (`orders/{id}` + zaman çizelgesi + sevkiyatlar).
final bayiOrderProvider = NotifierProvider.autoDispose
    .family<BayiOrderController, Loadable<BayiOrderBundle>, int>(
      BayiOrderController.new,
    );

class BayiOrderController
    extends AutoDisposeFamilyNotifier<Loadable<BayiOrderBundle>, int> {
  int _epoch = 0;

  @override
  Loadable<BayiOrderBundle> build(int arg) {
    ref.watch(currentUserIdProvider);
    final sub = ref.read(bayiChangesProvider).stream.listen((c) {
      if (c == BayiChange.orders ||
          c == BayiChange.quotes ||
          c == BayiChange.shipments) {
        unawaited(refresh());
      }
    });
    ref.onDispose(sub.cancel);
    Future.microtask(refresh);
    return const Loadable.loading();
  }

  Future<void> refresh() async {
    final epoch = ++_epoch;
    if (state.hasData) state = state.copyWith(refreshing: true, error: null);
    final repo = ref.read(bayiRepositoryProvider);
    try {
      final orderF = repo.order(arg);
      final timelineF = _soft(repo.orderTimeline(arg));
      final fulfillmentF = _soft(repo.fulfillment(arg));
      final order = await orderF;
      final timeline = await timelineF;
      final fulfillment = await fulfillmentF;
      if (epoch != _epoch) return;
      state = Loadable(
        data: BayiOrderBundle(
          order: order,
          timeline: timeline.value ?? const [],
          fulfillment: fulfillment.value,
          timelineFailed: timeline.failed,
          fulfillmentFailed: fulfillment.failed,
        ),
        updatedAt: DateTime.now().toUtc(),
      );
    } catch (e) {
      if (epoch != _epoch) return;
      final f = AppFailure.from(e);
      state = state.hasData
          ? state.copyWith(refreshing: false, error: f)
          : Loadable(error: f);
    }
  }

  static Future<({T? value, bool failed})> _soft<T>(Future<T> f) async {
    try {
      return (value: await f, failed: false);
    } catch (_) {
      return (value: null, failed: true);
    }
  }
}

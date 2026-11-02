import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/access_policy.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/models/models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/revalidate.dart';
import '../data/bayi_repository.dart';
import '../data/dispatch_models.dart';
import 'bayi_runtime.dart';
import 'paged_loading.dart';

/// Sevkiyat panosu (`GET shipments/board?days=7`): planlanacak siparişler (kovalar) ve açık sevkiyatlar.
final dispatchBoardProvider =
    NotifierProvider<DispatchBoardController, Loadable<ShipmentBoard>>(
      DispatchBoardController.new,
    );

class DispatchBoardController extends Notifier<Loadable<ShipmentBoard>> {
  int _epoch = 0;

  @override
  Loadable<ShipmentBoard> build() {
    final user = ref.watch(currentUserIdProvider);
    final sub = ref.read(bayiChangesProvider).stream.listen((c) {
      if (c == BayiChange.shipments || c == BayiChange.orders) {
        unawaited(refresh());
      }
    });
    ref.onDispose(sub.cancel);
    ref.listen(revalidateProvider, (_, e) {
      if (e != null &&
          !state.loading &&
          !state.refreshing &&
          Freshness.isStale(state.updatedAt, Freshness.list)) {
        unawaited(refresh());
      }
    });
    if (user == null) return const Loadable();
    Future.microtask(_start);
    return const Loadable.loading();
  }

  /// Önce önbellekteki pano, sonra sunucu.
  Future<void> _start() async {
    final epoch = _epoch;
    try {
      final hit = await ref.read(bayiRepositoryProvider).peekBoard();
      if (hit != null && epoch == _epoch && !state.hasData) {
        state = Loadable(
          data: hit.value,
          refreshing: true,
          updatedAt: hit.storedAt,
          fromCache: true,
        );
      }
    } catch (_) {}
    await refresh();
  }

  Future<void> refresh() async {
    final epoch = ++_epoch;
    state = state.hasData
        ? state.copyWith(refreshing: true, error: null)
        : const Loadable.loading();
    try {
      final b = await ref.read(bayiRepositoryProvider).board();
      if (epoch != _epoch) return;
      state = Loadable(data: b, updatedAt: DateTime.now().toUtc());
    } catch (e) {
      if (epoch != _epoch) return;
      final f = AppFailure.from(e);
      state = state.hasData
          ? state.copyWith(refreshing: false, error: f)
          : Loadable(error: f);
    }
  }
}

/// Son kullanılan plakalar (son sürücüsüyle) ve sürücüler.
final boardSuggestionsProvider = FutureProvider.autoDispose<BoardSuggestions>((
  ref,
) async {
  ref.watch(currentUserIdProvider);
  try {
    return await ref.read(bayiRepositoryProvider).boardSuggestions();
  } on AppFailure {
    return BoardSuggestions.empty;
  }
});

/// Atanabilir şoförler (`stations/me/drivers`): önce Şoför rolü, sonra sevkiyat düzenleyen personel.
final stationDriversProvider = FutureProvider.autoDispose<List<StationDriver>>((
  ref,
) {
  ref.watch(currentUserIdProvider);
  return ref.read(bayiRepositoryProvider).drivers();
});

/// Sevkiyatlar listesi durumu.
@immutable
class ShipmentListState {
  const ShipmentListState({
    this.filter = const ShipmentListFilter(),
    this.list = const PagedList.initial(),
    this.counts,
  });

  final ShipmentListFilter filter;
  final PagedList<ShipmentListItem> list;

  /// Son yanıtın durum sayıları (çiplerde).
  final ShipmentListPage? counts;

  ShipmentListState copyWith({
    ShipmentListFilter? filter,
    PagedList<ShipmentListItem>? list,
    ShipmentListPage? counts,
  }) => ShipmentListState(
    filter: filter ?? this.filter,
    list: list ?? this.list,
    counts: counts ?? this.counts,
  );
}

/// Sevkiyat ekranı "Bugünkü yüklemeler" ile açılır mı (depo / dolum işi): yükleme kaydı yetkinliği
/// (`loading.record`) var, şoför atama (`shipment.assign`) yok. Roller v5: rol koduna (`depot`) değil
/// yetkinliğe bakılır; ikisini birden tutan İkmal birimi panoyla açar.
bool opensWithLoadings(AccessPolicy p) =>
    p.isBayi && p.hasCap(Caps.loadingRecord) && !p.hasCap(Caps.shipmentAssign);

/// "Sevkiyatlar" listesi (`GET shipments?statuses&hasDispute&scheduledFrom/To&page&pageSize`). Depo
/// personeli "Bugünkü yüklemeler" ile açar ([opensWithLoadings]).
final shipmentListProvider =
    NotifierProvider<ShipmentListController, ShipmentListState>(
      ShipmentListController.new,
    );

class ShipmentListController extends Notifier<ShipmentListState>
    with PagedLoading<ShipmentListItem, ShipmentListState> {
  @override
  ShipmentListState build() {
    final user = ref.watch(currentUserIdProvider);
    final sub = ref.read(bayiChangesProvider).stream.listen((c) {
      if (c == BayiChange.shipments) unawaited(reload(silent: true));
    });
    ref.onDispose(sub.cancel);
    ref.listen(revalidateProvider, (_, e) {
      if (e != null) unawaited(refreshIfStale(Freshness.list));
    });
    if (user == null) return const ShipmentListState(list: PagedList());
    final depot = opensWithLoadings(ref.read(accessPolicyProvider));
    final initial = ShipmentListState(
      filter: depot
          ? ShipmentListFilter.todayLoadingsFilter()
          : const ShipmentListFilter(),
    );
    Future.microtask(reload);
    return initial;
  }

  @override
  PagedList<ShipmentListItem> get list => state.list;

  @override
  ShipmentListState withList(PagedList<ShipmentListItem> next) =>
      state.copyWith(list: next);

  @override
  Object? identityOf(ShipmentListItem item) => item.id;

  @override
  Future<PagedChunk<ShipmentListItem>> fetchPage(int page) async {
    final r = await ref
        .read(bayiRepositoryProvider)
        .shipments(state.filter, page: page);
    if (page == 1) state = state.copyWith(counts: r);
    return (items: r.items, hasMore: r.hasMore, total: r.totalFiltered);
  }

  @override
  Future<CachedResponse<PagedChunk<ShipmentListItem>>?> peekFirstPage() async {
    final hit = await ref
        .read(bayiRepositoryProvider)
        .peekShipments(state.filter);
    if (hit == null) return null;
    final r = hit.value;
    state = state.copyWith(counts: r);
    return CachedResponse(
      (items: r.items, hasMore: r.hasMore, total: r.totalFiltered),
      storedAt: hit.storedAt,
    );
  }

  void setFilter(ShipmentListFilter next) {
    if (next == state.filter) return;
    state = state.copyWith(filter: next);
    unawaited(reload());
  }

  /// Durum çipi: tek seçim (aynı çipe dokunmak temizler); "Bugünkü yüklemeler" ve "İtirazlı" kapanır.
  void toggleStatus(ShipmentStatus s) {
    final f = state.filter;
    final next = f.statuses.contains(s) && f.statuses.length == 1
        ? <ShipmentStatus>{}
        : {s};
    setFilter(
      f.copyWith(statuses: next, todayLoadings: false, hasDispute: false),
    );
  }

  void toggleTodayLoadings() {
    final f = state.filter;
    setFilter(
      f.todayLoadings
          ? const ShipmentListFilter()
          : f.copyWith(
              todayLoadings: true,
              statuses: const {},
              hasDispute: false,
              scheduledFrom: null,
              scheduledTo: null,
            ),
    );
  }

  void toggleDisputes() {
    final f = state.filter;
    setFilter(
      f.copyWith(
        hasDispute: !f.hasDispute,
        todayLoadings: false,
        statuses: const {},
      ),
    );
  }

  void setSearch(String q) =>
      setFilter(state.filter.copyWith(search: q.trim()));

  void setRange(DateTime? from, DateTime? to) => setFilter(
    state.filter.copyWith(
      scheduledFrom: from,
      scheduledTo: to,
      todayLoadings: false,
    ),
  );

  void clear() => setFilter(const ShipmentListFilter());
}

/// Sevkiyat ayrıntısı ve teslim kanıtı (`shipments/{id}/detail`).
final shipmentDetailProvider = NotifierProvider.autoDispose
    .family<ShipmentDetailController, Loadable<ShipmentDetail>, int>(
      ShipmentDetailController.new,
    );

class ShipmentDetailController
    extends AutoDisposeFamilyNotifier<Loadable<ShipmentDetail>, int> {
  int _epoch = 0;

  @override
  Loadable<ShipmentDetail> build(int arg) {
    ref.watch(currentUserIdProvider);
    Future.microtask(_start);
    return const Loadable.loading();
  }

  /// Önce önbellekteki ayrıntı, sonra sunucu.
  Future<void> _start() async {
    final epoch = _epoch;
    try {
      final hit = await ref
          .read(bayiRepositoryProvider)
          .peekShipmentDetail(arg);
      if (hit != null && epoch == _epoch && !state.hasData) {
        state = Loadable(
          data: hit.value,
          refreshing: true,
          updatedAt: hit.storedAt,
          fromCache: true,
        );
      }
    } catch (_) {}
    await refresh();
  }

  /// Yeniden okur; dönen değer güncel ayrıntı (hata durumunda null).
  Future<ShipmentDetail?> refresh() async {
    final epoch = ++_epoch;
    if (state.hasData) state = state.copyWith(refreshing: true, error: null);
    try {
      final d = await ref.read(bayiRepositoryProvider).shipmentDetail(arg);
      if (epoch != _epoch) return d;
      state = Loadable(data: d, updatedAt: DateTime.now().toUtc());
      return d;
    } catch (e) {
      if (epoch != _epoch) return null;
      final f = AppFailure.from(e);
      state = state.hasData
          ? state.copyWith(refreshing: false, error: f)
          : Loadable(error: f);
      return null;
    }
  }
}

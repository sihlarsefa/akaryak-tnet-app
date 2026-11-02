import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/revalidate.dart';
import '../data/bayi_repository.dart';
import '../data/customer_models.dart';
import 'bayi_runtime.dart';
import 'paged_loading.dart';

/// Cariler listesi durumu.
@immutable
class BayiCustomersState {
  const BayiCustomersState({
    this.query = '',
    this.list = const PagedList.initial(),
  });

  final String query;
  final PagedList<BayiCustomerRow> list;

  BayiCustomersState copyWith({
    String? query,
    PagedList<BayiCustomerRow>? list,
  }) => BayiCustomersState(query: query ?? this.query, list: list ?? this.list);
}

/// `GET bayi/customers?q`: StationCustomers Görür → bayinin tüm carileri; saha satış → kendi portföyü.
final bayiCustomersProvider =
    NotifierProvider<BayiCustomersController, BayiCustomersState>(
      BayiCustomersController.new,
    );

class BayiCustomersController extends Notifier<BayiCustomersState>
    with PagedLoading<BayiCustomerRow, BayiCustomersState> {
  @override
  BayiCustomersState build() {
    final user = ref.watch(currentUserIdProvider);
    ref.listen(revalidateProvider, (_, e) {
      if (e != null) unawaited(refreshIfStale(Freshness.list));
    });
    if (user == null) return const BayiCustomersState(list: PagedList());
    Future.microtask(reload);
    return const BayiCustomersState();
  }

  @override
  PagedList<BayiCustomerRow> get list => state.list;

  @override
  BayiCustomersState withList(PagedList<BayiCustomerRow> next) =>
      state.copyWith(list: next);

  @override
  Object? identityOf(BayiCustomerRow item) => item.customerId;

  @override
  Future<PagedChunk<BayiCustomerRow>> fetchPage(int page) async {
    final r = await ref
        .read(bayiRepositoryProvider)
        .customers(q: state.query, page: page);
    return (items: r.items, hasMore: r.hasMore, total: r.totalCount);
  }

  @override
  Future<CachedResponse<PagedChunk<BayiCustomerRow>>?> peekFirstPage() async {
    if (state.query.isNotEmpty) return null;
    final hit = await ref.read(bayiRepositoryProvider).peekCustomers();
    if (hit == null) return null;
    final r = hit.value;
    return CachedResponse(
      (items: r.items, hasMore: r.hasMore, total: r.totalCount),
      storedAt: hit.storedAt,
    );
  }

  void setQuery(String q) {
    final next = q.trim();
    if (next == state.query) return;
    state = state.copyWith(query: next);
    unawaited(reload());
  }
}

/// Cari 360-lite kartı (`bayi/customers/{id}/summary`).
final customerSummaryProvider = NotifierProvider.autoDispose
    .family<CustomerSummaryController, Loadable<CustomerSummary>, int>(
      CustomerSummaryController.new,
    );

class CustomerSummaryController
    extends AutoDisposeFamilyNotifier<Loadable<CustomerSummary>, int> {
  int _epoch = 0;

  @override
  Loadable<CustomerSummary> build(int arg) {
    ref.watch(currentUserIdProvider);
    final sub = ref.read(bayiChangesProvider).stream.listen((c) {
      if (c == BayiChange.customer) unawaited(refresh());
    });
    ref.onDispose(sub.cancel);
    Future.microtask(_start);
    return const Loadable.loading();
  }

  /// Önce önbellekteki kart, sonra sunucu.
  Future<void> _start() async {
    final epoch = _epoch;
    try {
      final hit = await ref
          .read(bayiRepositoryProvider)
          .peekCustomerSummary(arg);
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
    if (state.hasData) state = state.copyWith(refreshing: true, error: null);
    try {
      final s = await ref.read(bayiRepositoryProvider).customerSummary(arg);
      if (epoch != _epoch) return;
      state = Loadable(data: s, updatedAt: DateTime.now().toUtc());
    } catch (e) {
      if (epoch != _epoch) return;
      final f = AppFailure.from(e);
      state = state.hasData
          ? state.copyWith(refreshing: false, error: f)
          : Loadable(error: f);
    }
  }

  /// Not eklenince kart tazelenmeden notlar güncellenir (sunucu yanıtı en üste).
  void prependNote(CustomerNote note) {
    final s = state.data;
    if (s == null) return;
    state = state.copyWith(data: s.withNotes([note, ...s.notes]));
  }

  void removeNote(int noteId) {
    final s = state.data;
    if (s == null) return;
    state = state.copyWith(
      data: s.withNotes([
        for (final n in s.notes)
          if (n.id != noteId) n,
      ]),
    );
  }
}

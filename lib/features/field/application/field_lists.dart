import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/cache_store.dart';
import '../../../core/offline/outbox_op.dart';
import '../../../core/offline/outbox_providers.dart';
import '../data/field_models.dart';
import '../data/field_outbox.dart';
import '../data/field_repository.dart';
import '../data/lead_models.dart';

/// Sayfalı liste durumu (skip/take ya da page/pageSize).
@immutable
class PagedListState<T> {
  const PagedListState({
    this.items = const [],
    this.total = 0,
    this.firstLoading = true,
    this.refreshing = false,
    this.loadingMore = false,
    this.error,
    this.moreError,
    this.cachedAt,
  });

  final List<T> items;
  final int total;

  /// İlk yükleme (iskelet gösterilir).
  final bool firstLoading;

  /// Arka planda yenileme (içerik kalır, üstte ince çubuk).
  final bool refreshing;
  final bool loadingMore;
  final AppFailure? error;
  final AppFailure? moreError;

  /// Gösterilen veri önbellekten (çevrimdışı açılış): "Son güncelleme hh:mm".
  final DateTime? cachedAt;

  bool get hasMore => items.length < total;
  bool get isEmpty => !firstLoading && items.isEmpty;

  static const _unset = Object();

  PagedListState<T> copyWith({
    List<T>? items,
    int? total,
    bool? firstLoading,
    bool? refreshing,
    bool? loadingMore,
    Object? error = _unset,
    Object? moreError = _unset,
    Object? cachedAt = _unset,
  }) => PagedListState<T>(
    items: items ?? this.items,
    total: total ?? this.total,
    firstLoading: firstLoading ?? this.firstLoading,
    refreshing: refreshing ?? this.refreshing,
    loadingMore: loadingMore ?? this.loadingMore,
    error: identical(error, _unset) ? this.error : error as AppFailure?,
    moreError: identical(moreError, _unset)
        ? this.moreError
        : moreError as AppFailure?,
    cachedAt: identical(cachedAt, _unset)
        ? this.cachedAt
        : cachedAt as DateTime?,
  );
}

/// Saha listelerini (formlar, ön kayıtlar, portföy) yenilemek için tık: kuyruktaki bir saha işlemi
/// sunucuya ulaşınca ya da ekranlarda kayıt / gönderim / iptal yapılınca artar.
final fieldSyncTickProvider = NotifierProvider<FieldSyncTick, int>(
  FieldSyncTick.new,
);

class FieldSyncTick extends Notifier<int> {
  final Set<String> _done = {};

  @override
  int build() {
    ref.listen<AsyncValue<List<OutboxOp>>>(outboxOpsProvider, (prev, next) {
      final ops = next.valueOrNull ?? const <OutboxOp>[];
      var changed = false;
      for (final o in ops) {
        if (FieldOps.all.contains(o.type) &&
            o.status == OutboxStatus.done &&
            _done.add(o.id)) {
          changed = true;
        }
      }
      if (changed) state++;
    });
    return 0;
  }

  void bump() => state++;
}

/// Ortak sayfalı liste denetleyicisi: ilk yükleme (önbellek → sunucu), yenileme, sonsuz kaydırma.
/// Her yükleme bir "dönem" taşır; eski dönemin sonucu yok sayılır (filtre değişince yarış olmaz).
abstract class PagedListController<T, Q>
    extends AutoDisposeFamilyNotifier<PagedListState<T>, Q> {
  int _epoch = 0;

  int get pageSize => FieldRepository.pageSize;

  FieldRepository get repo => ref.read(fieldRepositoryProvider);

  /// [offset] satırdan itibaren [limit] satır. `raw` ilk sayfanın önbellek içeriğidir.
  Future<({List<T> items, int total, Object? raw})> fetch(
    Q query,
    int offset,
    int limit,
  );

  /// İlk sayfanın önbellek anahtarı (yalnızca kullanıcıya özel, filtresiz listeler; null = önbellek yok).
  String? cacheKey(Q query) => null;

  /// Önbellekteki ham JSON'dan satırlar.
  ({List<T> items, int total})? parseRaw(Object? raw) => null;

  @override
  PagedListState<T> build(Q arg) {
    ref.listen<int>(fieldSyncTickProvider, (_, _) => unawaited(refresh()));
    ref.watch(currentUserIdProvider);
    Future.microtask(_initial);
    return PagedListState<T>();
  }

  String? _userKey(Q query) {
    final uid = ref.read(currentUserIdProvider);
    final k = cacheKey(query);
    if (uid == null || k == null) return null;
    return CacheKeys.user(uid, k);
  }

  Future<void> _initial() async {
    final key = _userKey(arg);
    if (key != null) {
      final cached = await ref.read(cacheStoreProvider).read(key);
      final parsed = cached == null ? null : parseRaw(cached.value);
      if (parsed != null && state.firstLoading) {
        state = state.copyWith(
          items: parsed.items,
          total: parsed.total,
          firstLoading: false,
          cachedAt: cached!.storedAt,
        );
      }
    }
    await refresh();
  }

  /// Baştan yükler (içerik kalır).
  Future<void> refresh() async {
    final epoch = ++_epoch;
    state = state.copyWith(refreshing: !state.firstLoading, error: null);
    try {
      final page = await fetch(arg, 0, pageSize);
      if (epoch != _epoch) return;
      state = PagedListState<T>(
        items: page.items,
        total: page.total,
        firstLoading: false,
      );
      final key = _userKey(arg);
      if (key != null && page.raw != null) {
        await ref
            .read(cacheStoreProvider)
            .write(
              key,
              page.raw,
              userId: ref.read(currentUserIdProvider),
              ttl: const Duration(days: 7),
            );
      }
    } catch (e) {
      if (epoch != _epoch) return;
      final f = AppFailure.from(e);
      if (f is UnknownFailure && f.cancelled) return;
      state = state.copyWith(firstLoading: false, refreshing: false, error: f);
    }
  }

  /// Sonraki sayfa.
  Future<void> loadMore() async {
    final s = state;
    if (s.loadingMore || !s.hasMore || s.firstLoading) return;
    final epoch = _epoch;
    state = s.copyWith(loadingMore: true, moreError: null);
    try {
      final page = await fetch(arg, s.items.length, pageSize);
      if (epoch != _epoch) return;
      state = state.copyWith(
        items: [...state.items, ...page.items],
        total: page.total,
        loadingMore: false,
      );
    } catch (e) {
      if (epoch != _epoch) return;
      state = state.copyWith(loadingMore: false, moreError: AppFailure.from(e));
    }
  }
}

// ═══════════════════════════════════════════════════════════════════ Saha formları

class FieldFormsController
    extends PagedListController<FieldFormRow, FieldFormsQuery> {
  @override
  Future<({List<FieldFormRow> items, int total, Object? raw})> fetch(
    FieldFormsQuery query,
    int offset,
    int limit,
  ) async {
    final raw = await repo.formsJson(query, skip: offset, take: limit);
    final page = FieldFormsPage.fromJson(raw);
    return (items: page.items, total: page.totalCount, raw: raw);
  }

  /// Aramasız görünümlerin ilk sayfası saklanır (sahada çevrimdışı açılış).
  @override
  String? cacheKey(FieldFormsQuery query) =>
      (query.search ?? '').isEmpty ? 'field.forms.${query.key}' : null;

  @override
  ({List<FieldFormRow> items, int total})? parseRaw(Object? raw) {
    final page = FieldFormsPage.fromJson(raw);
    return (items: page.items, total: page.totalCount);
  }
}

final fieldFormsProvider = NotifierProvider.autoDispose
    .family<
      FieldFormsController,
      PagedListState<FieldFormRow>,
      FieldFormsQuery
    >(FieldFormsController.new);

// ═══════════════════════════════════════════════════════════════════ Ön kayıtlar

class FieldLeadsController extends PagedListController<LeadRow, LeadsQuery> {
  @override
  Future<({List<LeadRow> items, int total, Object? raw})> fetch(
    LeadsQuery query,
    int offset,
    int limit,
  ) async {
    final page = offset ~/ limit + 1;
    final raw = await repo.leadsJson(query, page: page, size: limit);
    final parsed = FieldRepository.parseLeads(raw);
    return (items: parsed.items, total: parsed.totalCount, raw: raw);
  }

  @override
  String? cacheKey(LeadsQuery query) =>
      (query.search ?? '').isEmpty ? 'field.leads.${query.key}' : null;

  @override
  ({List<LeadRow> items, int total})? parseRaw(Object? raw) {
    final p = FieldRepository.parseLeads(raw);
    return (items: p.items, total: p.totalCount);
  }
}

final fieldLeadsProvider = NotifierProvider.autoDispose
    .family<FieldLeadsController, PagedListState<LeadRow>, LeadsQuery>(
      FieldLeadsController.new,
    );

// ═══════════════════════════════════════════════════════════════════ Portföy

class FieldPortfolioController
    extends PagedListController<PortfolioRow, String> {
  @override
  Future<({List<PortfolioRow> items, int total, Object? raw})> fetch(
    String search,
    int offset,
    int limit,
  ) async {
    final raw = await repo.portfolioJson(
      search: search.isEmpty ? null : search,
      skip: offset,
      take: limit,
    );
    final page = SkipTakePage.fromJson(raw, PortfolioRow.fromJson);
    return (items: page.items, total: page.totalCount, raw: raw);
  }

  /// Portföyün ilk sayfası çevrimdışı açılış için saklanır (spec C.4a).
  @override
  String? cacheKey(String search) =>
      search.isEmpty ? CacheKeys.fieldPortfolio : null;

  @override
  ({List<PortfolioRow> items, int total})? parseRaw(Object? raw) {
    final page = SkipTakePage.fromJson(raw, PortfolioRow.fromJson);
    return (items: page.items, total: page.totalCount);
  }
}

/// Arama metnine göre portföy (boş = tümü).
final fieldPortfolioProvider = NotifierProvider.autoDispose
    .family<FieldPortfolioController, PagedListState<PortfolioRow>, String>(
      FieldPortfolioController.new,
    );

/// Bayinin satış temsilcileri (Saha ekibi süzgeci).
final fieldRepsProvider = FutureProvider.autoDispose<List<IdName>>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(fieldRepositoryProvider).reps();
});

/// A5 ortak sayfalı liste durumu ve denetleyicisi (Onaylarım, Finans, Tahsilat listeleri).
///
/// Desen (spec C.8, F2GO cüzdan): açık durum sınıfı, dönem (epoch) koruması, aynı anda tek yenileme.
/// - İlk yüklemede iskelet; yenilemede içerik kalır ([PagedState.refreshing] → üst ilerleme çubuğu).
/// - Sorgu (aile anahtarı) ya da kullanıcı değişince dönem artar; eski isteklerin yanıtı uygulanmaz.
/// - Sonraki sayfa hatası listeyi silmez ([PagedState.moreError]).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/models/paged_result.dart';
import '../../../core/network/app_failure.dart';

/// Sayfalı liste durumu.
@immutable
class PagedState<T> {
  const PagedState({
    this.items = const [],
    this.totalCount = 0,
    this.page = 0,
    this.totalPages = 0,
    this.loading = false,
    this.refreshing = false,
    this.loadingMore = false,
    this.error,
    this.moreError,
    this.loadedAt,
  });

  /// İlk yükleme sürüyor (iskelet).
  const PagedState.loading() : this(loading: true);

  final List<T> items;
  final int totalCount;

  /// Yüklenen son sayfa (0 = henüz yok).
  final int page;
  final int totalPages;
  final bool loading;
  final bool refreshing;
  final bool loadingMore;

  /// İlk yükleme ya da yenileme hatası.
  final AppFailure? error;

  /// Sonraki sayfa hatası (liste korunur).
  final AppFailure? moreError;

  /// Son başarılı yükleme (UTC).
  final DateTime? loadedAt;

  bool get hasMore => page < totalPages;
  bool get hasData => loadedAt != null;

  /// İlk yükleme: iskelet gösterilir.
  bool get isFirstLoad => loading && loadedAt == null;

  /// Yüklendi ve boş.
  bool get isEmpty => hasData && items.isEmpty;

  PagedState<T> copyWith({
    List<T>? items,
    int? totalCount,
    int? page,
    int? totalPages,
    bool? loading,
    bool? refreshing,
    bool? loadingMore,
    AppFailure? Function()? error,
    AppFailure? Function()? moreError,
    DateTime? loadedAt,
  }) => PagedState<T>(
    items: items ?? this.items,
    totalCount: totalCount ?? this.totalCount,
    page: page ?? this.page,
    totalPages: totalPages ?? this.totalPages,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    loadingMore: loadingMore ?? this.loadingMore,
    error: error == null ? this.error : error(),
    moreError: moreError == null ? this.moreError : moreError(),
    loadedAt: loadedAt ?? this.loadedAt,
  );
}

/// Sayfalı liste denetleyicisi tabanı. Alt sınıf yalnızca [fetchPage] yazar.
///
/// ```dart
/// final p = NotifierProvider.autoDispose.family<XList, PagedState<X>, XQuery>(XList.new);
/// class XList extends PagedNotifier<X, XQuery> {
///   @override
///   Future<PagedResult<X>> fetchPage(XQuery q, int page) => ref.read(repo).list(q, page: page);
/// }
/// ```
abstract class PagedNotifier<T, Q>
    extends AutoDisposeFamilyNotifier<PagedState<T>, Q> {
  int _epoch = 0;
  bool _disposed = false;
  Future<void>? _refreshing;
  Future<void>? _more;

  /// Sayfa boyutu (sunucu en çok 100).
  int get pageSize => 25;

  /// [page] 1'den başlar.
  Future<PagedResult<T>> fetchPage(Q query, int page);

  @override
  PagedState<T> build(Q arg) {
    // Kullanıcı değişince liste baştan okunur (önceki kullanıcının verisi görünmez).
    ref.watch(currentUserIdProvider);
    final epoch = ++_epoch;
    _refreshing = null;
    _more = null;
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    Future.microtask(() => _loadFirst(epoch));
    return PagedState<T>.loading();
  }

  bool _alive(int epoch) => !_disposed && epoch == _epoch;

  Future<void> _loadFirst(int epoch) async {
    if (!_alive(epoch)) return;
    try {
      final r = await fetchPage(arg, 1);
      if (!_alive(epoch)) return;
      state = PagedState<T>(
        items: r.items,
        totalCount: r.totalCount,
        page: r.pageNumber <= 0 ? 1 : r.pageNumber,
        totalPages: r.totalPages,
        loadedAt: DateTime.now().toUtc(),
      );
    } catch (e) {
      if (!_alive(epoch)) return;
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: () => AppFailure.from(e),
      );
    }
  }

  /// Baştan yükler; içerik varsa korunur (üst ilerleme çubuğu). Eşzamanlı çağrılar birleşir.
  Future<void> refresh() {
    final running = _refreshing;
    if (running != null) return running;
    final epoch = ++_epoch;
    _more = null;
    state = state.copyWith(
      loading: !state.hasData,
      refreshing: state.hasData,
      loadingMore: false,
      error: () => null,
      moreError: () => null,
    );
    final f = _refresh(epoch);
    _refreshing = f;
    return f.whenComplete(() {
      if (identical(_refreshing, f)) _refreshing = null;
    });
  }

  Future<void> _refresh(int epoch) async {
    try {
      final r = await fetchPage(arg, 1);
      if (!_alive(epoch)) return;
      state = PagedState<T>(
        items: r.items,
        totalCount: r.totalCount,
        page: r.pageNumber <= 0 ? 1 : r.pageNumber,
        totalPages: r.totalPages,
        loadedAt: DateTime.now().toUtc(),
      );
    } catch (e) {
      if (!_alive(epoch)) return;
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: () => AppFailure.from(e),
      );
    }
  }

  /// Sonraki sayfayı ekler (sonsuz kaydırma). Yükleme ya da yenileme sürerken yok sayılır.
  Future<void> loadMore() {
    final s = state;
    if (!s.hasData || !s.hasMore || s.loading || s.refreshing) {
      return Future.value();
    }
    final running = _more;
    if (running != null) return running;
    final epoch = _epoch;
    state = s.copyWith(loadingMore: true, moreError: () => null);
    final f = _loadMore(epoch, s.page + 1);
    _more = f;
    return f.whenComplete(() {
      if (identical(_more, f)) _more = null;
    });
  }

  Future<void> _loadMore(int epoch, int page) async {
    try {
      final r = await fetchPage(arg, page);
      if (!_alive(epoch)) return;
      final seen = <Object?>{for (final i in state.items) keyOf(i)};
      state = state.copyWith(
        items: List.unmodifiable([
          ...state.items,
          ...r.items.where((i) => !seen.contains(keyOf(i))),
        ]),
        totalCount: r.totalCount,
        page: r.pageNumber <= 0 ? page : r.pageNumber,
        totalPages: r.totalPages,
        loadingMore: false,
      );
    } catch (e) {
      if (!_alive(epoch)) return;
      state = state.copyWith(
        loadingMore: false,
        moreError: () => AppFailure.from(e),
      );
    }
  }

  /// Sayfalar arası tekrarları ayıklamak için kimlik (varsayılan: öğenin kendisi).
  Object? keyOf(T item) => item;

  /// Yerel düzeltme (ör. karar sonrası satırı kaldırma) — sunucu yenilemesi beklenmeden.
  void removeWhere(bool Function(T item) test) {
    final items = state.items.where((i) => !test(i)).toList();
    final removed = state.items.length - items.length;
    if (removed == 0) return;
    state = state.copyWith(
      items: List.unmodifiable(items),
      totalCount: (state.totalCount - removed).clamp(0, 1 << 30),
    );
  }

  /// Yerel değiştirme (ör. durum değişen satır).
  void replaceWhere(bool Function(T item) test, T Function(T item) update) {
    var changed = false;
    final items = [
      for (final i in state.items)
        if (test(i))
          () {
            changed = true;
            return update(i);
          }()
        else
          i,
    ];
    if (changed) state = state.copyWith(items: List.unmodifiable(items));
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/models/json.dart';
import '../../../core/models/paged_result.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/cache_store.dart';
import '../../../core/push/push_providers.dart';
import '../../../core/push/unread_count_provider.dart';
import '../../../core/utils/log.dart';
import '../data/notification_models.dart';
import '../data/notifications_repository.dart';

/// Gelen kutusunun durumu.
@immutable
class InboxState {
  const InboxState({
    this.items = const [],
    this.page = 0,
    this.totalPages = 0,
    this.totalCount = 0,
    this.unreadOnly = false,
    this.loading = true,
    this.refreshing = false,
    this.loadingMore = false,
    this.error,
    this.moreError,
    this.loadedAt,
    this.fromCache = false,
  });

  final List<UserNotification> items;

  /// Son yüklenen sayfa (0 = hiçbiri).
  final int page;
  final int totalPages;
  final int totalCount;
  final bool unreadOnly;

  /// İlk yükleme (iskelet).
  final bool loading;

  /// Arka planda yenileme (içerik kalır, üstte ince çubuk).
  final bool refreshing;
  final bool loadingMore;

  /// İlk sayfa yüklenemedi (içerik yoksa hata ekranı).
  final AppFailure? error;
  final AppFailure? moreError;
  final DateTime? loadedAt;

  /// Çevrimdışı: son kaydedilen ilk sayfa gösteriliyor.
  final bool fromCache;

  bool get hasMore => page < totalPages;
  int get unreadCount => items.where((n) => !n.isRead).length;

  InboxState copyWith({
    List<UserNotification>? items,
    int? page,
    int? totalPages,
    int? totalCount,
    bool? unreadOnly,
    bool? loading,
    bool? refreshing,
    bool? loadingMore,
    AppFailure? Function()? error,
    AppFailure? Function()? moreError,
    DateTime? loadedAt,
    bool? fromCache,
  }) => InboxState(
    items: items ?? this.items,
    page: page ?? this.page,
    totalPages: totalPages ?? this.totalPages,
    totalCount: totalCount ?? this.totalCount,
    unreadOnly: unreadOnly ?? this.unreadOnly,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    loadingMore: loadingMore ?? this.loadingMore,
    error: error == null ? this.error : error(),
    moreError: moreError == null ? this.moreError : moreError(),
    loadedAt: loadedAt ?? this.loadedAt,
    fromCache: fromCache ?? this.fromCache,
  );
}

/// Bildirimler ekranı (spec A.4 A8): sayfalı liste, "Okunmamış" süzgeci, okundu işaretleme
/// (iyimser; rozet hemen düşer), tümünü okundu say, push gelince sessiz yenileme, çevrimdışıyken son
/// kaydedilen ilk sayfa.
final inboxControllerProvider =
    NotifierProvider.autoDispose<InboxController, InboxState>(
      InboxController.new,
    );

class InboxController extends AutoDisposeNotifier<InboxState> {
  int _epoch = 0;
  bool _disposed = false;
  Future<void>? _refreshing;

  NotificationsRepository get _repo =>
      ref.read(notificationsRepositoryProvider);

  String? get _userId => ref.read(currentUserIdProvider);

  @override
  InboxState build() {
    ref.watch(currentUserIdProvider);
    _disposed = false;
    _refreshing = null;
    ref.onDispose(() => _disposed = true);
    // Push geldiğinde ve okunmamış sayısı arttığında ilk sayfa sessizce tazelenir.
    ref.listen(pushEventsProvider, (_, _) => unawaited(refresh()));
    ref.listen<int>(unreadCountProvider.select((u) => u.notifications), (
      prev,
      next,
    ) {
      if (prev != null && next > prev && next > state.unreadCount) {
        unawaited(refresh());
      }
    });
    final epoch = ++_epoch;
    Future.microtask(() => _loadFirst(epoch, unreadOnly: false));
    return const InboxState();
  }

  bool _alive(int epoch) => !_disposed && epoch == _epoch;

  String? get _cacheKey {
    final uid = _userId;
    return uid == null ? null : CacheKeys.user(uid, 'notifications.inbox');
  }

  Future<void> _loadFirst(int epoch, {required bool unreadOnly}) async {
    try {
      final p = await _repo.list(unreadOnly: unreadOnly);
      if (!_alive(epoch)) return;
      state = state.copyWith(
        items: p.items,
        page: p.pageNumber,
        totalPages: p.totalPages,
        totalCount: p.totalCount,
        unreadOnly: unreadOnly,
        loading: false,
        refreshing: false,
        loadingMore: false,
        error: () => null,
        moreError: () => null,
        loadedAt: DateTime.now().toUtc(),
        fromCache: false,
      );
      if (!unreadOnly) unawaited(_writeCache(p));
    } catch (e) {
      if (!_alive(epoch)) return;
      final f = AppFailure.from(e);
      if (state.items.isEmpty && !unreadOnly && f is OfflineFailure) {
        final cached = await _readCache();
        if (!_alive(epoch)) return;
        if (cached != null) {
          state = state.copyWith(
            items: cached.items,
            page: cached.page,
            totalPages: cached.page,
            totalCount: cached.items.length,
            loading: false,
            refreshing: false,
            error: () => null,
            loadedAt: cached.storedAt,
            fromCache: true,
          );
          return;
        }
      }
      state = state.copyWith(loading: false, refreshing: false, error: () => f);
    }
  }

  /// İlk sayfayı yeniden okur (içerik kalır). Eşzamanlı çağrılar birleşir.
  Future<void> refresh() {
    final running = _refreshing;
    if (running != null) return running;
    final epoch = ++_epoch;
    final hasContent = state.items.isNotEmpty;
    state = state.copyWith(
      loading: !hasContent,
      refreshing: hasContent,
      error: hasContent ? null : () => null,
    );
    final f = _loadFirst(epoch, unreadOnly: state.unreadOnly);
    _refreshing = f;
    unawaited(ref.read(unreadCountProvider.notifier).refresh());
    return f.whenComplete(() => _refreshing = null);
  }

  /// "Tümü" / "Okunmamış".
  Future<void> setUnreadOnly(bool unreadOnly) {
    if (unreadOnly == state.unreadOnly && state.error == null) {
      return Future.value();
    }
    final epoch = ++_epoch;
    _refreshing = null;
    state = InboxState(unreadOnly: unreadOnly);
    return _loadFirst(epoch, unreadOnly: unreadOnly);
  }

  /// Sonsuz kaydırma: sonraki sayfa.
  Future<void> loadMore() async {
    final s = state;
    if (!s.hasMore || s.loadingMore || s.loading || s.fromCache) return;
    final epoch = _epoch;
    state = s.copyWith(loadingMore: true, moreError: () => null);
    try {
      final p = await _repo.list(page: s.page + 1, unreadOnly: s.unreadOnly);
      if (!_alive(epoch)) return;
      final known = {for (final n in state.items) n.id};
      state = state.copyWith(
        items: [
          ...state.items,
          for (final n in p.items)
            if (!known.contains(n.id)) n,
        ],
        page: p.pageNumber,
        totalPages: p.totalPages,
        totalCount: p.totalCount,
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

  /// Okundu işaretle (iyimser). Hata olursa geri alınır ve hata döner.
  Future<AppFailure?> markRead(int id) async {
    final index = state.items.indexWhere((n) => n.id == id);
    if (index < 0 || state.items[index].isRead) return null;
    final before = state.items[index];
    _replace(before.markedRead(DateTime.now().toUtc()));
    ref.read(unreadCountProvider.notifier).adjust(notifications: -1);
    try {
      await _repo.markRead(id);
      return null;
    } catch (e) {
      final f = AppFailure.from(e);
      if (f is NotFoundFailure) {
        // Bildirim artık yok: listeden çıkar.
        if (!_disposed) {
          state = state.copyWith(
            items: [
              for (final n in state.items)
                if (n.id != id) n,
            ],
          );
        }
        unawaited(ref.read(unreadCountProvider.notifier).refresh());
        return null;
      }
      if (!_disposed) _replace(before);
      ref.read(unreadCountProvider.notifier).adjust(notifications: 1);
      return f;
    }
  }

  /// Tümünü okundu say (iyimser).
  Future<AppFailure?> markAllRead() async {
    final before = state.items;
    final now = DateTime.now().toUtc();
    state = state.copyWith(items: [for (final n in before) n.markedRead(now)]);
    final badge = ref.read(unreadCountProvider).notifications;
    ref.read(unreadCountProvider.notifier).adjust(notifications: -badge);
    try {
      await _repo.markAllRead();
      unawaited(ref.read(unreadCountProvider.notifier).refresh());
      return null;
    } catch (e) {
      if (!_disposed) state = state.copyWith(items: before);
      ref.read(unreadCountProvider.notifier).adjust(notifications: badge);
      return AppFailure.from(e);
    }
  }

  void _replace(UserNotification n) {
    if (_disposed) return;
    state = state.copyWith(
      items: [for (final x in state.items) x.id == n.id ? n : x],
    );
  }

  // ------------------------------------------------------------------ Önbellek

  Future<void> _writeCache(PagedResult<UserNotification> p) async {
    final key = _cacheKey;
    if (key == null) return;
    try {
      await ref.read(cacheStoreProvider).write(key, {
        'items': [for (final n in p.items) n.toJson()],
        'page': p.pageNumber,
      }, userId: _userId);
    } catch (e) {
      AppLog.debug('Bildirim önbelleği yazılamadı: $e');
    }
  }

  Future<({List<UserNotification> items, int page, DateTime storedAt})?>
  _readCache() async {
    final key = _cacheKey;
    if (key == null) return null;
    final entry = await ref.read(cacheStoreProvider).read(key);
    if (entry == null) return null;
    final r = JsonReader.of(entry.value);
    return (
      items: r.list('items', UserNotification.fromJson),
      page: r.integer('page', 1),
      storedAt: entry.storedAt,
    );
  }
}

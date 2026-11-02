import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/revalidate.dart';
import 'bayi_runtime.dart';

/// Bir sayfanın sonucu.
typedef PagedChunk<T> = ({List<T> items, bool hasMore, int total});

/// Sayfalı liste yükleme davranışı (ilk yükleme, sessiz tazeleme, sonsuz kaydırma). Dönem sayacı
/// ([_epoch]) eski isteklerin sonucunu yok sayar: süzgeç değişince yarışan yanıt listeyi bozmaz.
///
/// Önce önbellek (2026-11-02): [peekFirstPage] veren liste, iskelet yerine son ilk sayfayı hemen gösterir
/// (üstte ince "güncelleniyor" çubuğu) ve sunucudan tazeler; tazeleme başarısızsa içerik kalır.
/// [refreshIfStale] sekme dönüşünde ve öne gelmede yalnızca eskiyen listeyi tazeler.
mixin PagedLoading<T, S> on Notifier<S> {
  int _epoch = 0;

  /// Durumdaki liste.
  PagedList<T> get list;

  /// Listeyi değiştirilmiş yeni durum.
  S withList(PagedList<T> next);

  /// [page] (1 tabanlı) sayfasını getirir.
  Future<PagedChunk<T>> fetchPage(int page);

  /// Geçerli süzgecin önbellekteki ilk sayfası (yoksa null; varsayılan: önbellek yok).
  Future<CachedResponse<PagedChunk<T>>?> peekFirstPage() async => null;

  /// İlk sayfadan yeniden yükler. [silent] true ise içerik kalır, üstte ince çubuk görünür. Sessiz
  /// değilse (açılış, süzgeç değişimi) önce önbellekteki ilk sayfa denenir.
  Future<void> reload({bool silent = false}) async {
    final epoch = ++_epoch;
    final current = list;
    var keep = silent && current.items.isNotEmpty;
    if (!keep) {
      CachedResponse<PagedChunk<T>>? hit;
      try {
        hit = await peekFirstPage();
      } catch (_) {
        hit = null;
      }
      if (epoch != _epoch) return;
      if (hit != null) {
        final chunk = hit.value;
        state = withList(
          PagedList<T>(
            items: List.unmodifiable(chunk.items),
            page: 1,
            hasMore: chunk.hasMore,
            totalCount: chunk.total,
            updatedAt: hit.storedAt,
          ),
        );
        keep = true;
      }
    }
    state = withList(
      keep
          ? list.copyWith(refreshing: true, error: null, moreError: null)
          : const PagedList(loading: true),
    );
    try {
      final chunk = await fetchPage(1);
      if (epoch != _epoch) return;
      state = withList(
        PagedList<T>(
          items: List.unmodifiable(chunk.items),
          page: 1,
          hasMore: chunk.hasMore,
          totalCount: chunk.total,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    } catch (e) {
      if (epoch != _epoch) return;
      final f = AppFailure.from(e);
      state = withList(
        keep
            ? list.copyWith(refreshing: false, loading: false, error: f)
            : PagedList<T>(error: f),
      );
    }
  }

  /// Liste [ttl]'den eskiyse sessizce tazeler (yüklenirken ya da tazeyken bir şey yapmaz).
  Future<void> refreshIfStale(Duration ttl) async {
    final l = list;
    if (l.loading || l.refreshing || l.loadingMore) return;
    if (!Freshness.isStale(l.updatedAt, ttl)) return;
    await reload(silent: true);
  }

  /// Sonraki sayfa (liste sonuna yaklaşınca).
  Future<void> loadMore() async {
    final current = list;
    if (!current.hasMore ||
        current.loadingMore ||
        current.loading ||
        current.refreshing) {
      return;
    }
    final epoch = _epoch;
    state = withList(current.copyWith(loadingMore: true, moreError: null));
    try {
      final chunk = await fetchPage(current.page + 1);
      if (epoch != _epoch) return;
      final seen = <Object?>{};
      final merged = <T>[
        for (final i in [...list.items, ...chunk.items])
          if (seen.add(identityOf(i))) i,
      ];
      state = withList(
        list.copyWith(
          items: List.unmodifiable(merged),
          page: current.page + 1,
          hasMore: chunk.hasMore,
          totalCount: chunk.total,
          loadingMore: false,
        ),
      );
    } catch (e) {
      if (epoch != _epoch) return;
      state = withList(
        list.copyWith(loadingMore: false, moreError: AppFailure.from(e)),
      );
    }
  }

  /// Tekrarları ayıklamak için satır kimliği (sayfalar arasında kayan satırlar).
  Object? identityOf(T item) => item;

  /// Bekleyen yükleme sonuçlarını geçersiz kılar (süzgeç değişti).
  void cancelPending() => _epoch++;
}

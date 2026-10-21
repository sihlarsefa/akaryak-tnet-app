import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/app_failure.dart';
import '../../../core/network/idempotency.dart';

/// Sayfalı liste durumu (ilk yükleme iskelet, yenilemede içerik kalır, sonsuz kaydırma).
@immutable
class PagedState<T> {
  const PagedState({
    this.items = const [],
    this.total = 0,
    this.hasMore = false,
    this.loading = true,
    this.refreshing = false,
    this.loadingMore = false,
    this.error,
    this.loadMoreError,
    this.fromCache = false,
    this.storedAt,
  });

  final List<T> items;
  final int total;
  final bool hasMore;

  /// İlk yükleme (iskelet gösterilir).
  final bool loading;

  /// Arka planda yenileme (içerik kalır, üstte ince çubuk).
  final bool refreshing;
  final bool loadingMore;

  /// İlk yükleme hatası (liste boşken).
  final AppFailure? error;

  /// Sonraki sayfa hatası (alt bilgide "Tekrar dene").
  final AppFailure? loadMoreError;

  /// Çevrimdışı: son kayıtlı ilk sayfa gösteriliyor.
  final bool fromCache;
  final DateTime? storedAt;

  bool get isEmpty => items.isEmpty;
  bool get showSkeleton => loading && items.isEmpty;

  PagedState<T> copyWith({
    List<T>? items,
    int? total,
    bool? hasMore,
    bool? loading,
    bool? refreshing,
    bool? loadingMore,
    AppFailure? error,
    bool clearError = false,
    AppFailure? loadMoreError,
    bool clearLoadMoreError = false,
    bool? fromCache,
    DateTime? storedAt,
  }) => PagedState<T>(
    items: items ?? this.items,
    total: total ?? this.total,
    hasMore: hasMore ?? this.hasMore,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    loadingMore: loadingMore ?? this.loadingMore,
    error: clearError ? null : (error ?? this.error),
    loadMoreError: clearLoadMoreError
        ? null
        : (loadMoreError ?? this.loadMoreError),
    fromCache: fromCache ?? this.fromCache,
    storedAt: storedAt ?? this.storedAt,
  );
}

/// Sonucu belirsiz eylemlerde aynı anahtarla yeniden deneme aralıkları (spec C.4a: 2, 4, 8, 16 s).
/// Testler sıfır gecikme verir.
final cmRetryDelaysProvider = Provider<List<Duration>>(
  (ref) => const [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
  ],
);

/// Niyet başına tek Idempotency-Key ile durum geçişi (spec C.4a):
/// - belirsiz sonuçta (zaman aşımı, 5xx, işlem sürüyor) önce hedef duruma ulaşılmış mı bakılır, sonra
///   aynı anahtarla yeniden denenir;
/// - 400 / 409 sonrası varlık yeniden okunur; hedef duruma ulaşıldıysa başarı sayılır;
/// - kesin yanıtta anahtar bırakılır, belirsiz kalırsa saklanır (sonraki deneme aynı anahtarı kullanır).
///
/// [onChecking] "… kontrol ediliyor" metnini gösterir.
Future<bool> runIdempotent({
  required IdempotencyLedger ledger,
  required String intent,
  required Future<void> Function(String key) call,
  required Future<bool> Function() reachedTarget,
  List<Duration> retryDelays = const [],
  VoidCallback? onChecking,
}) async {
  var attempt = 0;
  while (true) {
    final key = ledger.keyFor(intent);
    try {
      await call(key);
      ledger.settle(intent);
      return true;
    } catch (e) {
      final f = AppFailure.from(e);
      if (f is UnknownFailure && f.cancelled) rethrow;
      final reconcilable =
          f.isUncertain ||
          f is ConflictFailure ||
          f is BusinessFailure ||
          f is ValidationFailure;
      if (reconcilable) {
        onChecking?.call();
        try {
          if (await reachedTarget()) {
            ledger.settle(intent);
            return true;
          }
        } catch (_) {
          // Okunamadı: aşağıdaki kurala göre devam.
        }
      }
      final retryable =
          (f.isUncertain && f is! OfflineFailure) ||
          (f is ConflictFailure && f.isInProgress);
      if (retryable && attempt < retryDelays.length) {
        onChecking?.call();
        final delay = retryDelays[attempt++];
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        continue;
      }
      ledger.settle(intent, error: f);
      throw f;
    }
  }
}

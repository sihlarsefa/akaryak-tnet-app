import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/network/idempotency.dart';

/// Bayi özelliğinin çalışma zamanı yardımcıları: tek niyet = tek Idempotency-Key, belirsiz sonuçta
/// aynı anahtarla tekrar, durum geçişlerinde mutabakat (spec C.4a) ve ekranlar arası "değişti" olayları.

/// Kullanıcı başına niyet → anahtar defteri (kullanıcı değişince sıfırlanır).
final bayiIdempotencyProvider = Provider<IdempotencyLedger>((ref) {
  ref.watch(currentUserIdProvider);
  return IdempotencyLedger(lifetime: const Duration(hours: 24));
});

/// Belirsiz sonuçta (zaman aşımı, bağlantı, 5xx, işlem sürüyor) aynı anahtarla bekleme aralıkları
/// (spec C.4a: 2, 4, 8 s …). Testler sıfırla geçersiz kılar.
final bayiRetryDelaysProvider = Provider<List<Duration>>(
  (ref) => const [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
  ],
);

/// Hangi veri değişti (ilgili listeler sessizce tazelenir).
enum BayiChange { quotes, orders, shipments, customer, staff }

/// Ekranlar arası değişiklik yayını.
class BayiChanges {
  final _controller = StreamController<BayiChange>.broadcast();

  Stream<BayiChange> get stream => _controller.stream;

  void emit(Iterable<BayiChange> changes) {
    if (_controller.isClosed) return;
    for (final c in changes.toSet()) {
      _controller.add(c);
    }
  }

  Future<void> dispose() => _controller.close();
}

final bayiChangesProvider = Provider<BayiChanges>((ref) {
  final c = BayiChanges();
  ref.onDispose(c.dispose);
  return c;
});

/// İşlemin sonucu: sunucu onayladı ya da yeniden okumada hedef duruma ulaşıldığı görüldü.
enum BayiOutcome { confirmed, reconciled }

/// İdempotent çalıştırıcı (spec C.4a).
///
/// - [intent] için defterden anahtar alınır (bekleyen anahtar varsa o: tekrar deneme).
/// - Belirsiz hatada (zaman aşımı, bağlantı, 5xx, `idempotency_in_progress`) [delays] aralıklarıyla aynı
///   anahtarla tekrar denenir; [onChecking] "… kontrol ediliyor" göstermek içindir.
/// - Hâlâ belirsizse ya da 400 / 409 dönerse [reconcile] çağrılır: hedef duruma ulaşıldıysa başarı sayılır.
/// - Kesin hata anahtarı bırakır; kullanıcı yeniden denerse bu yeni bir niyettir.
Future<BayiOutcome> runIdempotent({
  required IdempotencyLedger ledger,
  required String intent,
  required Future<void> Function(String key) call,
  Future<bool> Function()? reconcile,
  List<Duration> delays = const [],
  VoidCallback? onChecking,
}) async {
  var attempt = 0;
  while (true) {
    final key = ledger.keyFor(intent);
    try {
      await call(key);
      ledger.settle(intent);
      return BayiOutcome.confirmed;
    } catch (e) {
      final f = AppFailure.from(e);
      if (f.isUncertain && attempt < delays.length) {
        onChecking?.call();
        await Future<void>.delayed(delays[attempt++]);
        continue;
      }
      if (reconcile != null && _shouldReconcile(f)) {
        bool reached = false;
        try {
          reached = await reconcile();
        } catch (_) {
          reached = false;
        }
        if (reached) {
          ledger.settle(intent);
          return BayiOutcome.reconciled;
        }
      }
      ledger.settle(intent, error: f);
      throw f;
    }
  }
}

/// Durum geçişi (anahtarsız uçlar: yola çıkar, teslim bildir, iptal, tamamla): belirsiz sonuçta ya da
/// 400 / 409'da [reconcile] ile yeniden okunur; hedefe ulaşıldıysa başarı.
Future<BayiOutcome> runTransition({
  required Future<void> Function() call,
  required Future<bool> Function() reconcile,
}) async {
  try {
    await call();
    return BayiOutcome.confirmed;
  } catch (e) {
    final f = AppFailure.from(e);
    if (_shouldReconcile(f)) {
      bool reached = false;
      try {
        reached = await reconcile();
      } catch (_) {
        reached = false;
      }
      if (reached) return BayiOutcome.reconciled;
    }
    throw f;
  }
}

bool _shouldReconcile(AppFailure f) =>
    f.isUncertain ||
    f is ConflictFailure ||
    f is BusinessFailure ||
    f is ValidationFailure;

/// Liste / ayrıntı ekranlarının ortak yükleme durumu: veri, ilk yükleme, arka plan tazeleme, hata ve
/// önbellek bilgisi ("Son güncelleme hh:mm").
@immutable
class Loadable<T> {
  const Loadable({
    this.data,
    this.loading = false,
    this.refreshing = false,
    this.error,
    this.updatedAt,
    this.fromCache = false,
  });

  const Loadable.loading() : this(loading: true);

  final T? data;

  /// İlk yükleme (iskelet gösterilir).
  final bool loading;

  /// Arka planda tazeleniyor (içerik kalır, üstte ince çubuk).
  final bool refreshing;
  final AppFailure? error;
  final DateTime? updatedAt;

  /// Veri çevrimdışı önbellekten.
  final bool fromCache;

  bool get hasData => data != null;

  Loadable<T> copyWith({
    T? data,
    bool? loading,
    bool? refreshing,
    Object? error = _keep,
    DateTime? updatedAt,
    bool? fromCache,
  }) => Loadable<T>(
    data: data ?? this.data,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    error: error == _keep ? this.error : error as AppFailure?,
    updatedAt: updatedAt ?? this.updatedAt,
    fromCache: fromCache ?? this.fromCache,
  );
}

/// Sayfalı liste durumu (sonsuz kaydırma).
@immutable
class PagedList<T> {
  const PagedList({
    this.items = const [],
    this.page = 0,
    this.hasMore = false,
    this.totalCount = 0,
    this.loading = false,
    this.refreshing = false,
    this.loadingMore = false,
    this.error,
    this.moreError,
    this.updatedAt,
  });

  const PagedList.initial() : this(loading: true);

  final List<T> items;

  /// Son yüklenen sayfa (0 = hiç).
  final int page;
  final bool hasMore;
  final int totalCount;
  final bool loading;
  final bool refreshing;
  final bool loadingMore;

  /// İlk sayfa hatası.
  final AppFailure? error;

  /// Sonraki sayfa hatası (liste altında "Tekrar dene").
  final AppFailure? moreError;
  final DateTime? updatedAt;

  bool get isEmpty => items.isEmpty;

  PagedList<T> copyWith({
    List<T>? items,
    int? page,
    bool? hasMore,
    int? totalCount,
    bool? loading,
    bool? refreshing,
    bool? loadingMore,
    Object? error = _keep,
    Object? moreError = _keep,
    DateTime? updatedAt,
  }) => PagedList<T>(
    items: items ?? this.items,
    page: page ?? this.page,
    hasMore: hasMore ?? this.hasMore,
    totalCount: totalCount ?? this.totalCount,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    loadingMore: loadingMore ?? this.loadingMore,
    error: error == _keep ? this.error : error as AppFailure?,
    moreError: moreError == _keep ? this.moreError : moreError as AppFailure?,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

const Object _keep = Object();

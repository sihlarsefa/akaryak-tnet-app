import '../../../core/network/app_failure.dart';

/// Belirsiz sonuçlu durum geçişleri (spec C.4a): zaman aşımı, 5xx ya da "işlem sürüyor" yanıtında aynı
/// Idempotency-Key ile 2, 4, 8, 16 sn arayla (toplam en çok [maxTotal]) yeniden dener. Kesin olmayan bir
/// 400/409 ya da süre dolunca [reconcile] çağrılır: kayıt hedef duruma ulaşmışsa başarı sayılır.
///
/// Çevrimdışı hata hemen fırlatılır (bekletmek anlamsız; anahtar çağıranda saklanır, sonraki deneme aynı
/// anahtarla gider).
Future<T> retryUncertain<T>(
  Future<T> Function() call, {
  Future<T?> Function()? reconcile,
  void Function(int attempt)? onRetry,
  Duration maxTotal = const Duration(seconds: 60),
  Future<void> Function(Duration wait)? delay,
}) async {
  final sleep = delay ?? (d) => Future<void>.delayed(d);
  var wait = const Duration(seconds: 2);
  var elapsed = Duration.zero;
  var attempt = 0;
  var hadUncertain = false;
  while (true) {
    attempt++;
    try {
      return await call();
    } on AppFailure catch (f) {
      if (f is OfflineFailure) rethrow;
      final inProgress = f is ConflictFailure && f.isInProgress;
      final uncertain = f.isUncertain || inProgress;
      if (!uncertain) {
        // Önceki deneme sunucuda işlenmiş olabilir: kesin hata (ör. "yalnızca taslak gönderilebilir")
        // hedef duruma ulaşıldığı için de gelebilir.
        if (hadUncertain && reconcile != null) {
          final r = await reconcile();
          if (r != null) return r;
        }
        rethrow;
      }
      hadUncertain = true;
      if (elapsed + wait > maxTotal) {
        if (reconcile != null) {
          final r = await reconcile();
          if (r != null) return r;
        }
        rethrow;
      }
      onRetry?.call(attempt);
      await sleep(wait);
      elapsed += wait;
      wait *= 2;
      if (wait > const Duration(seconds: 16)) {
        wait = const Duration(seconds: 16);
      }
    }
  }
}

/// Bekleyen işlem yeniden deneme aralıkları (spec C.4): 5 sn / 15 sn / 1 dk / 5 dk / 15 dk, sonra 15 dk.
abstract final class OutboxBackoff {
  static const steps = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  /// [attempt]. başarısız denemeden sonra beklenecek süre (1 tabanlı).
  static Duration after(int attempt) {
    if (attempt <= 0) return Duration.zero;
    return steps[(attempt - 1).clamp(0, steps.length - 1)];
  }

  /// Sunucu `Retry-After` verdiyse büyük olanı kullanılır.
  static Duration withRetryAfter(int attempt, Duration? retryAfter) {
    final base = after(attempt);
    if (retryAfter == null) return base;
    return retryAfter > base ? retryAfter : base;
  }
}

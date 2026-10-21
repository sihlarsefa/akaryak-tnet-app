import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/app_failure.dart';

/// Belirsiz sonuç için yeniden deneme planı (spec C.4a): aynı anahtarla 2, 4, 8, 16 sn
/// aralıklarla, toplam bekleme 60 sn'yi geçmeyecek şekilde. `idempotency_in_progress` alındıkça
/// sunucudaki ilk istek sürüyor demektir: daha uzun (3 dk) yoklanır.
class RetryPolicy {
  const RetryPolicy({
    this.steps = const [
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
      Duration(seconds: 16),
    ],
    this.budget = const Duration(seconds: 60),
    this.inProgressBudget = const Duration(minutes: 3),
  });

  final List<Duration> steps;
  final Duration budget;
  final Duration inProgressBudget;

  /// [attempt]. tekrar için bekleme (0'dan); son adım tekrarlanır.
  Duration delayFor(int attempt) =>
      steps[attempt < steps.length ? attempt : steps.length - 1];

  /// [waited] kadar beklendikten sonra [attempt]. tekrar bütçeye sığar mı.
  bool allows(int attempt, Duration waited, {bool inProgress = false}) {
    final limit = inProgress ? inProgressBudget : budget;
    return waited + delayFor(attempt) <= limit;
  }
}

/// Aynı anahtarla tekrar denenmesi gereken (sonucu belirsiz ya da geçici) hata mı.
bool isRetryableFailure(AppFailure f) {
  if (f is UnknownFailure && f.cancelled) return false;
  if (f is RateLimitedFailure) return true;
  return f.isUncertain;
}

/// Bekleme işlevi; testler anında dönen bir sürümle geçersiz kılar.
final a2WaitProvider = Provider<Future<void> Function(Duration)>(
  (ref) =>
      (d) => Future<void>.delayed(d),
);

final a2RetryPolicyProvider = Provider<RetryPolicy>(
  (ref) => const RetryPolicy(),
);

/// Belirsiz sonuçlu durum geçişleri için ortak kurallar (spec C.4a):
/// - Bir niyet için bir Idempotency-Key; zaman aşımı, bağlantı kopması, 5xx ve "işlem sürüyor"
///   sonrasında aynı anahtarla 2, 4, 8, 16 … sn arayla (toplam ~60 sn) tekrar denenir.
/// - Kesin olmayan sonuç kalırsa kayıt yeniden okunur; hedef duruma ulaşılmışsa başarı sayılır.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/network/idempotency.dart';

/// Tekrar deneme aralıkları (testlerde kısaltılır).
final a5RetryScheduleProvider = Provider<List<Duration>>(
  (ref) => const [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
    Duration(seconds: 30),
  ],
);

/// Kullanıcı niyeti başına Idempotency-Key defteri (kullanıcı değişince temizlenir).
final a5IdempotencyLedgerProvider = Provider<IdempotencyLedger>((ref) {
  ref.watch(currentUserIdProvider);
  return IdempotencyLedger(lifetime: const Duration(hours: 24));
});

/// Aynı anahtarla tekrar denenebilir mi (sonuç belirsiz ya da işlem sürüyor).
bool isRetryable(AppFailure f) {
  if (f is UnknownFailure && f.cancelled) return false;
  if (f is ConflictFailure) return f.isInProgress;
  return f.isUncertain;
}

/// [run]'ı belirsiz hatalarda [schedule] aralıklarıyla tekrar dener; son hatayı fırlatır.
/// [onRetry] her tekrardan önce çağrılır ("Kararınız kontrol ediliyor…").
Future<T> runWithRetry<T>(
  Future<T> Function() run, {
  required List<Duration> schedule,
  void Function(int attempt)? onRetry,
  bool Function()? keepGoing,
}) async {
  var attempt = 0;
  while (true) {
    try {
      return await run();
    } on AppFailure catch (f) {
      if (!isRetryable(f) || attempt >= schedule.length) rethrow;
      if (keepGoing != null && !keepGoing()) rethrow;
      final wait = schedule[attempt];
      attempt++;
      onRetry?.call(attempt);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
  }
}

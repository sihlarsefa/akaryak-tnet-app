import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/network/idempotency.dart';
import '../data/customer_orders_repository.dart';
import 'retry_policy.dart';

/// Teklif kararının sonucu.
@immutable
sealed class DecisionOutcome {
  const DecisionOutcome();
}

/// Karar işlendi (ya da doğrulamada siparişin hedef duruma ulaştığı görüldü).
final class DecisionDone extends DecisionOutcome {
  const DecisionDone(this.action, {this.confirmedByRefetch = false});
  final QuoteAction action;
  final bool confirmedByRefetch;
}

/// Teklif siz bakarken değişti (409); güncel teklif yüklendi.
final class DecisionConflict extends DecisionOutcome {
  const DecisionConflict(this.message);
  final String message;
}

/// Kesin ret (iş kuralı, yetki …): sunucu mesajı gösterilir.
final class DecisionFailed extends DecisionOutcome {
  const DecisionFailed(this.failure);
  final AppFailure failure;
}

/// Sonuç doğrulanamadı (bağlantı yok / zaman aşımı sürdü); aynı anahtarla tekrar denenebilir.
final class DecisionUncertain extends DecisionOutcome {
  const DecisionUncertain(this.failure);
  final AppFailure failure;
}

/// Teklif kararı gönderici (spec A.4 + C.4a):
/// - her karar niyeti için tek Idempotency-Key ([IdempotencyLedger]: aynı karar, aynı teklif),
/// - `expectedQuoteId` ile ekranda görülen teklif,
/// - zaman aşımı / bağlantı / 5xx'te aynı anahtarla 2–4–8–16 sn (en çok 60 sn),
/// - zaman aşımı, 400 ya da 409 sonrası sipariş yeniden okunur: hedef duruma ulaştıysa başarı.
class QuoteDecisionExecutor {
  QuoteDecisionExecutor({
    required this.repository,
    required this.ledger,
    required this.wait,
    this.policy = const RetryPolicy(),
  });

  final CustomerOrdersRepository repository;
  final IdempotencyLedger ledger;
  final Future<void> Function(Duration) wait;
  final RetryPolicy policy;

  static String intentKey(int orderId, QuoteAction action, int? quoteId) =>
      'order:$orderId:${action.path}:${quoteId ?? 0}';

  /// Kararı gönderir. [refetchStatus] siparişi sunucudan yeniden okuyup durumunu döndürür;
  /// [onChecking] belirsiz sonuçta ("Kararınız kontrol ediliyor") bir kez çağrılır.
  Future<DecisionOutcome> decide({
    required int orderId,
    required QuoteAction action,
    required int? expectedQuoteId,
    String? note,
    required Future<OrderStatus?> Function() refetchStatus,
    VoidCallback? onChecking,
  }) async {
    final intent = intentKey(orderId, action, expectedQuoteId);
    final key = ledger.keyFor(intent);
    var attempt = 0;
    var waited = Duration.zero;
    var announced = false;
    while (true) {
      try {
        await repository.decide(
          orderId,
          action,
          note: note,
          expectedQuoteId: expectedQuoteId,
          idempotencyKey: key,
        );
        ledger.settle(intent);
        return DecisionDone(action);
      } on AppFailure catch (f) {
        // Sunucu işlemiş olabilir: önce siparişi oku.
        final needsCheck =
            isRetryableFailure(f) ||
            f is ValidationFailure ||
            f is BusinessFailure ||
            f is ConflictFailure;
        if (needsCheck) {
          final status = await _safeStatus(refetchStatus);
          if (status != null && action.reached(status)) {
            ledger.settle(intent);
            return DecisionDone(action, confirmedByRefetch: true);
          }
        }
        if (isRetryableFailure(f)) {
          final inProgress = f is ConflictFailure && f.isInProgress;
          if (!policy.allows(attempt, waited, inProgress: inProgress)) {
            return DecisionUncertain(f);
          }
          if (!announced) {
            announced = true;
            onChecking?.call();
          }
          final d = f is RateLimitedFailure && f.retryAfter != null
              ? f.retryAfter!
              : policy.delayFor(attempt);
          await wait(d);
          waited += d;
          attempt++;
          continue;
        }
        ledger.settle(intent, error: f);
        if (f is ConflictFailure && f.isConcurrency) {
          return DecisionConflict(f.message);
        }
        return DecisionFailed(f);
      }
    }
  }

  static Future<OrderStatus?> _safeStatus(
    Future<OrderStatus?> Function() read,
  ) async {
    try {
      return await read();
    } catch (_) {
      return null;
    }
  }
}

/// Uygulama ömrü boyunca tek defter: aynı karar tekrarında aynı anahtar (sunucu 72 sa tutar).
final quoteDecisionLedgerProvider = Provider<IdempotencyLedger>(
  (ref) => IdempotencyLedger(lifetime: const Duration(hours: 24)),
);

final quoteDecisionExecutorProvider = Provider<QuoteDecisionExecutor>(
  (ref) => QuoteDecisionExecutor(
    repository: ref.watch(customerOrdersRepositoryProvider),
    ledger: ref.watch(quoteDecisionLedgerProvider),
    wait: ref.watch(a2WaitProvider),
    policy: ref.watch(a2RetryPolicyProvider),
  ),
);

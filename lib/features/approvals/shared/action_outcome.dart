/// A5 işlem sonuçları (karar, ek bilgi, tahsilat durumu): ekran satır içi hata, çakışma bandı ya da
/// doğrulanamayan sonuç için "Tekrar dene" gösterir.
library;

import '../../../core/network/app_failure.dart';
import 'failure_view.dart';

/// Bir işlemin sonucu (sayfa satır içi hata / çakışma bandı gösterir).
sealed class ActionOutcome {
  const ActionOutcome();
}

/// Sunucu işlemi kaydetti.
final class ActionDone extends ActionOutcome {
  const ActionDone(this.message, {this.result});
  final String message;

  /// Uç noktanın yanıtı (ör. `ApprovalDecisionResult`).
  final Object? result;
}

/// Kayıt sizden sonra değişti (409): "Yenile" ile güncel hâl okunur, yazılanlar korunur.
final class ActionConflict extends ActionOutcome {
  const ActionConflict(this.message);
  final String message;
}

/// Alan hataları (400 validation): anahtar → mesaj (`note`, `conditions.termDays` …).
final class ActionInvalid extends ActionOutcome {
  const ActionInvalid(this.message, this.fieldErrors);
  final String message;
  final Map<String, String> fieldErrors;
}

/// Kesin hata (iş kuralı, yetki, bulunamadı …).
final class ActionFailed extends ActionOutcome {
  const ActionFailed(this.failure);
  final AppFailure failure;
  String get message => failureText(failure);
}

/// Sonuç doğrulanamadı (bağlantı): aynı anahtarla tekrar denenebilir; ikinci kez kaydedilmez.
final class ActionUnverified extends ActionOutcome {
  const ActionUnverified(this.message);
  final String message;
}

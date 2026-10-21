import 'dart:math' as math;

import 'app_failure.dart';

/// Hata metinleri tablosu (spec C.7, D.7). Ekranlar bir [AppFailure]'ı kullanıcıya bu tabloyla
/// anlatır; ham yanıt asla gösterilmez:
///
/// | Hata | Başlık | Metin / ek |
/// |---|---|---|
/// | çevrimdışı | İnternet bağlantısı yok | + Tekrar dene |
/// | zaman aşımı | Sunucu zamanında yanıt vermedi | + Tekrar dene |
/// | sunucu (5xx) | İşlem tamamlanamadı | "Destek kodu: {traceId'nin ilk 8'i}" (dokununca kopyalanır) |
/// | 429 | Çok fazla deneme | "{n} sn sonra tekrar deneyin" + sayan düğme |
/// | iş kuralı (400) | — | sunucunun Türkçe metni olduğu gibi |
/// | doğrulama (400) | — | alan hataları camelCase anahtarla alanların altında |
/// | çakışma (409) | Bu kayıt sizden sonra güncellendi | + Yenile; yazılanlar korunur |
/// | 403 | Bu işlem için yetkiniz yok. | yetkiler yeniden okunur |
/// | 404 | Bu kayıt artık görüntülenemiyor | |
abstract final class FailureCopy {
  static const offlineTitle = 'İnternet bağlantısı yok';
  static const offlineMessage =
      'Bağlantınızı kontrol edip tekrar deneyin. Kaydettiğiniz işlemler bekleyen işlemlerde durur.';
  static const timeoutTitle = 'Sunucu zamanında yanıt vermedi';
  static const timeoutMessage = 'Birkaç saniye sonra tekrar deneyin.';
  static const serverTitle = 'İşlem tamamlanamadı';
  static const serverMessage =
      'Sunucuda geçici bir sorun var. Birkaç dakika sonra tekrar deneyin; sürerse destek koduyla bize ulaşın.';
  static const rateLimitedTitle = 'Çok fazla deneme';
  static const conflictTitle = 'Bu kayıt sizden sonra güncellendi';
  static const conflictMessage =
      'Güncel hâli yüklendi. Yazdıklarınız korunuyor; kontrol edip yeniden gönderin.';
  static const forbidden = 'Bu işlem için yetkiniz yok.';
  static const notFoundTitle = 'Bu kayıt artık görüntülenemiyor';
  static const retry = 'Tekrar dene';
  static const refresh = 'Yenile';
  static const supportCodeCopied = 'Destek kodu kopyalandı.';

  /// "Çok fazla deneme. 30 sn sonra tekrar deneyin."
  static String rateLimited(Duration? wait) => wait == null
      ? 'Çok fazla deneme. Biraz sonra tekrar deneyin.'
      : 'Çok fazla deneme. ${wait.inSeconds} sn sonra tekrar deneyin.';

  /// İz kimliğinin ilk 8 karakteri (destek ekibi sunucu günlüğünde bu kodla bulur).
  static String? supportCode(String? traceId) {
    final t = traceId?.trim();
    if (t == null || t.isEmpty) return null;
    final plain = t.startsWith('fake-') ? t.substring(5) : t;
    return plain.substring(0, math.min(8, plain.length));
  }

  /// "Destek kodu: 1a2b3c4d".
  static String supportLine(String code) => 'Destek kodu: $code';

  /// Ekranda gösterilecek başlık.
  static String title(AppFailure f) => switch (f) {
    OfflineFailure() => offlineTitle,
    TimeoutFailure() => timeoutTitle,
    RateLimitedFailure() => rateLimitedTitle,
    ConflictFailure(isConcurrency: true) => conflictTitle,
    ForbiddenFailure() => forbidden,
    NotFoundFailure() => notFoundTitle,
    ServerFailure() || UnknownFailure() => serverTitle,
    _ => serverTitle,
  };

  /// Ekranda gösterilecek açıklama (iş kuralı ve doğrulamada sunucunun metni).
  static String message(AppFailure f) => switch (f) {
    OfflineFailure() => offlineMessage,
    TimeoutFailure() => timeoutMessage,
    RateLimitedFailure(:final retryAfter) => rateLimited(retryAfter),
    ConflictFailure(isConcurrency: true) => conflictMessage,
    // 503 gibi durumlarda sunucunun Türkçe açıklaması; yoksa genel metin.
    ServerFailure() => f.problem?.detail ?? serverMessage,
    _ => f.message,
  };

  /// Sunucu hatasında destek kodu (yoksa null).
  static String? supportCodeOf(AppFailure f) =>
      f is ServerFailure || f is UnknownFailure ? supportCode(f.traceId) : null;
}

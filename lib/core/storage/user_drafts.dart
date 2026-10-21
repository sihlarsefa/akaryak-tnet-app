import '../offline/cache_store.dart';
import 'prefs_store.dart';

/// Kullanıcının yarım işleri (spec C.4a, D.7). İstem dışı çıkışta — oturum süresi doldu ya da
/// sunucuda kapatıldı, kilit ekranından şifreyle giriş, şifre / telefon değişikliği — silinmez; aynı
/// kullanıcı yeniden girince kaldığı yerden sürer (24 saatlik süreleri geçerlidir). Kullanıcı
/// "Çıkış yap" derse ya da cihazda başka bir kullanıcı girerse silinir.
///
/// Belirteçler, yetkiler (`me/access`), ekran önbellekleri, görseller, bildirimler ve rozet her
/// çıkışta silinir; bekleyen işlemler (outbox) zaten kalır.
abstract final class UserDrafts {
  /// Şoförün "Teslim et" taslakları: litre, irsaliye no, fotoğraflar, imza (tercih, `akn.u.<id>.…`).
  static const deliverDrafts = 'driver.deliverDrafts';

  /// Sipariş sihirbazının taslağı ve sonucu belirsiz gönderimin Idempotency-Key'i (önbellek).
  static const orderWizard = 'a2.wizard';

  /// Saha formu ve ön kayıt sihirbazlarının taslakları (önbellek adı öneki).
  static const fieldWizardPrefix = 'field.wizard.';

  /// Korunan tercih adları ([PrefKeys.user] içindeki ad).
  static const prefNames = {deliverDrafts};

  /// Korunan önbellek adı önekleri ([CacheKeys.user] içindeki ad).
  static const cacheNamePrefixes = {orderWizard, fieldWizardPrefix};

  /// [userId] kullanıcısının korunan önbellek anahtarı önekleri.
  static Set<String> cacheKeyPrefixes(String userId) => {
    for (final n in cacheNamePrefixes) CacheKeys.user(userId, n),
  };

  /// [userId] kullanıcısının korunan tercih anahtarları.
  static Set<String> prefKeys(String userId) => {
    for (final n in prefNames) PrefKeys.user(userId, n),
  };
}

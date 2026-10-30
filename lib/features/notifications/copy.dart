/// Bildirimler metinleri (spec C.5/C.7: "siz" dili, cümle düzeni; düğmeler ≤ 22 karakter).
abstract final class NotificationsCopy {
  static const title = 'Bildirimler';
  static const today = 'Bugün';
  static const yesterday = 'Dün';
  static const all = 'Tümü';
  static const unread = 'Okunmamış';
  static const markAll = 'Tümünü okundu say';
  static const markAllDone = 'Tüm bildirimler okundu olarak işaretlendi.';
  static const settings = 'Bildirim ayarları';
  static const markRead = 'Okundu işaretle';
  static const markedRead = 'Okundu';
  static const unreadPrefix = 'Okunmadı';
  static const routeUnavailable =
      'Bu bildirimin sayfası hesabınızda açık değil.';
  static const loadMoreFailed = 'Devamı yüklenemedi.';
  static const loadMore = 'Daha fazla göster';
  static const retry = 'Tekrar dene';
  static const lastUpdated = 'Son güncelleme';

  // ------------------------------------------------------------------ Bant (v4 §3.2)
  /// Bandın durum satırı: "3 okunmamış".
  static String unreadStatus(int n) => '$n okunmamış';

  /// Okunmamış yokken.
  static const calmStatus = 'Yeni bildiriminiz yok';

  /// Çevrimdışı, son kaydedilen liste: "Son güncelleme 09:58".
  static String cachedAt(String time) => '$lastUpdated $time';

  // ------------------------------------------------------------------ Boş / hata
  static const emptyTitle = 'Henüz bildiriminiz yok';
  static const emptyMessage =
      'Teklif hazır olduğunda, siparişiniz ilerlediğinde ya da onayınız beklendiğinde burada görürsünüz.';
  static const emptyUnreadTitle = 'Okunmamış bildiriminiz yok';
  static const emptyUnreadMessage = 'Tüm bildirimlerinizi okudunuz.';
  static const showAll = 'Tümünü göster';
  static const offlineTitle = 'Çevrimdışısınız';
  static const offlineMessage =
      'Bu ekran için kayıtlı veri yok. Bağlantı gelince otomatik yenilenir.';
  static const errorTitle = 'Bildirimler yüklenemedi';

  // ------------------------------------------------------------------ Ayarlar
  static const settingsTitle = 'Bildirim ayarları';
  static const categoriesTitle = 'Kategoriler';
  static const categoriesHint =
      'Kapalı kategoriler anlık bildirim göndermez; bildirim kutunuzda yine görünür.';
  static const prefsError = 'Tercihler yüklenemedi';
  static const prefsSaveFailed =
      'Tercih kaydedilemedi. Bağlantınızı kontrol edip tekrar deneyin.';
  static const deviceTitle = 'Bu cihaz';
  static const pushOffTitle = 'Anlık bildirimler kapalı';
  static const pushOffMessage =
      'Bildirimleriniz bu ekranda ve zil simgesinde görünür. Uygulama açıkken yenileri kendiliğinden gelir.';

  // "Anlık bildirimler" ana anahtarı (sahip isteği 2026-10-30).
  static const masterTitle = 'Anlık bildirimler';
  static const masterSubtitle = 'Bildirimler telefonuma gelsin';
  static const masterOnHint =
      'Teklif, teslimat ve onay gelişmelerini anında öğrenirsiniz.';
  static const masterOffHint =
      'Bu telefona anlık bildirim gelmez. Bildirimleriniz bu ekranda ve zil simgesinde görünmeye devam eder.';
  static const masterAskHint = 'Açtığınızda telefonunuz bildirim izni ister.';
  static const masterDeniedHint =
      'Telefonunuzun ayarlarında AkaryakıtNet bildirimleri kapalı.';
  static const categoriesOffHint =
      'Kategoriler, anlık bildirimler açıkken geçerlidir.';

  /// İzin reddedilmişken anahtar açılınca çıkan sayfa.
  static const deniedSheetTitle =
      'Telefon ayarlarından bildirimlere izin verin';
  static const deniedSheetMessage =
      'Açılan sayfada "Bildirimler"e dokunun ve "Bildirimlere İzin Ver"i açın. Uygulamaya döndüğünüzde anahtar kendiliğinden açılır.';
  static const openSettings = 'Ayarları aç';
  static const notNow = 'Vazgeç';
  static const testTitle = 'Deneme';
  static const testTile = 'Test bildirimi gönder';
  static const testHint =
      'Cihazlarınıza bir deneme bildirimi gönderir; bildirim kutunuza da eklenir.';
  static const testSend = 'Gönder';
  static String testSent(int sent) => 'Test bildirimi $sent cihaza gönderildi.';
  static const testInboxOnly =
      'Test bildirimi bildirim kutunuza eklendi. Bu cihazda anlık bildirim açık değil.';

  // ------------------------------------------------------------------ Duyurular (merkez push'u)
  // Türlerin adları paneldeki "Bildirim tipi" listesiyle aynıdır (Yönetim > Push bildirimleri).
  static const kindGeneral = 'Genel';
  static const kindNotice = 'Duyuru';
  static const kindCampaign = 'Kampanya';
  static const kindMaintenance = 'Bakım / Kesinti';
  static const kindPrice = 'Fiyat güncellemesi';

  /// Duyurunun tam metnini kapatan düğme.
  static const announcementDone = 'Tamam';
}

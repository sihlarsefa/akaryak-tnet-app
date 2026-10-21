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
  static const offlineCached =
      'Çevrimdışısınız; son kaydedilen bildirimler gösteriliyor.';

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
  static const prefsSaveFailed = 'Tercih kaydedilemedi. Lütfen tekrar deneyin.';
  static const deviceTitle = 'Bu cihaz';
  static const pushOffTitle = 'Anlık bildirimler kapalı';
  static const pushOffMessage =
      'Bildirimleriniz bu ekranda ve zil simgesinde görünür. Uygulama açıkken yenileri kendiliğinden gelir.';
  static const pushOnTitle = 'Bildirimler açık';
  static const pushOnMessage =
      'Teklif, teslimat ve onay gelişmelerini anında öğrenirsiniz.';
  static const pushAskTitle = 'Bildirimlere izin verin';
  static const pushAskMessage =
      'Teklifiniz hazır olduğunda, aracınız yola çıktığında ve onayınız beklendiğinde haber verelim.';
  static const pushAsk = 'İzin ver';
  static const pushDeniedTitle = 'Bildirim izni kapalı';
  static const pushDeniedMessage =
      'Telefonunuzun ayarlarından AkaryakıtNet için bildirimlere izin verebilirsiniz.';
  static const openSettings = 'Ayarları aç';
  static const testTitle = 'Deneme';
  static const testTile = 'Test bildirimi gönder';
  static const testHint =
      'Cihazlarınıza bir deneme bildirimi gönderir; bildirim kutunuza da eklenir.';
  static const testSend = 'Gönder';
  static String testSent(int sent) => 'Test bildirimi $sent cihaza gönderildi.';
  static const testInboxOnly =
      'Test bildirimi bildirim kutunuza eklendi. Bu cihazda anlık bildirim açık değil.';
}

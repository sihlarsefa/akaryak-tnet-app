/// Bayi ekranlarının Türkçe metinleri (spec C.5: her özellik boş / hata metinlerini burada tutar).
/// Cümle düzeni, "siz" dili; büyük harf başlık yok.
abstract final class BayiCopy {
  // Ortak durumlar
  static const offlineNoData =
      'Çevrimdışısınız; bu ekran için kayıtlı veri yok.';
  static const offlineTitle = 'İnternet bağlantısı yok';
  static const forbiddenTitle = 'Bu ekran için yetkiniz yok';
  static const forbiddenMessage =
      'Yetkiniz değiştiyse yöneticinize başvurun. Uygulama yetkilerinizi kısa süre içinde yeniler.';
  static const notFoundTitle = 'Bu kayıt artık görüntülenemiyor';
  static const notFoundMessage =
      'Kayıt kaldırılmış ya da başka bir bayiye ait olabilir.';
  static const filteredEmptyTitle = 'Filtreye uyan kayıt yok';
  static const filteredEmptyMessage = 'Süzgeçleri değiştirip yeniden deneyin.';
  static const clearFilters = 'Filtreleri temizle';
  static const retry = 'Tekrar dene';
  static const loadMoreFailed = 'Devamı yüklenemedi.';
  static const sectionFailed = 'Bu bölüm yüklenemedi';
  static const sectionFailedMessage = 'Sayfayı aşağı çekerek yenileyin.';
  static const conflict = 'Bu kayıt sizden sonra güncellendi.';
  static const refresh = 'Yenile';
  static const forbiddenAction = 'Bu işlem için yetkiniz yok.';
  static const checking = 'Sonuç kontrol ediliyor…';

  // Ana sayfa
  static const homeEmptyTitle = 'Gösterilecek bölüm yok';
  static const homeEmptyMessage =
      'Hesabınıza bu ana sayfada özetlenecek bir yetki tanımlanmamış. Yöneticinizle görüşebilirsiniz.';

  // Teklif masası
  static const deskEmptyTitle = 'Teklif bekleyen sipariş yok';
  static const deskEmptyMessage =
      'Yeni sipariş geldiğinde burada görünür ve bildirim alırsınız.';
  static const deskSubmitHint = 'Fiyat yazdığınız satırlar seçilir.';
  static const deskOffline = 'Çevrimdışıyken teklif gönderilemez.';

  // Siparişler
  static const ordersEmptyTitle = 'Henüz sipariş yok';
  static const ordersEmptyMessage =
      'Carilerinizin siparişleri burada listelenir.';

  // Cariler
  static const customersEmptyTitle = 'Cari bulunamadı';
  static const customersEmptyMessage =
      'Bayinize bağlı cariler burada listelenir.';
  static const portfolioEmptyMessage = 'Portföyünüze atanmış cari yok.';

  // Sevkiyat
  static const boardEmptyTitle = 'Planlanacak sipariş yok';
  static const boardEmptyMessage =
      'Onaylanan siparişler planlanmayı beklerken burada görünür.';
  static const shipmentsEmptyTitle = 'Sevkiyat yok';
  static const shipmentsEmptyMessage =
      'Planlanan sevkiyatlar burada listelenir.';
  static const todayLoadingsEmpty = 'Bugün yüklenecek sevkiyat yok.';

  // Ekip
  static const staffEmptyTitle = 'Personel bulunamadı';
  static const staffEmptyMessage = 'Bayinizin personeli burada listelenir.';
}

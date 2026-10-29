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
  static const filteredEmptyMessage =
      'Yazımı kontrol edin ya da filtreleri temizleyin.';
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
  static const homeEmptyTitle = 'Hesabınıza henüz rol atanmadı';
  static const homeEmptyMessage =
      'Bayi yöneticiniz rol atayınca ana sayfanız dolar.';

  // Teklif masası
  static const deskEmptyTitle = 'Teklif bekleyen sipariş yok';
  static const deskEmptyMessage =
      'Yeni sipariş geldiğinde burada görünür ve bildirim alırsınız.';
  static const deskSubmitHint = 'Fiyat yazdığınız satırlar seçilir.';

  /// Alt çubuğun notu, hiçbir satıra fiyat yazılmamışken (v4 B10).
  static const deskStartHint =
      'Fiyat yazın ya da Öneri\'ye dokunun; Gönder düğmesi açılır.';
  static const deskOffline = 'Çevrimdışıyken teklif gönderilemez.';

  // Siparişler
  static const ordersEmptyTitle = 'Henüz sipariş yok';
  static const ordersEmptyMessage =
      'Carilerinizin siparişleri burada listelenir.';

  /// Finans kararı izleyenin sırası (talep Onaylar › Bende'de; v4 B7): satır ve ayrıntı aynı söz.
  static const financeYourMove = 'Finans onayınızı bekliyor';

  /// Ayrıntının alt çubuğu: finans talebini açar (karar orada). Düğme sözü yalın emirdir ("Teklif
  /// ver", "Sevkiyat planla" gibi; finans kartının ve müşterinin "Karar ver"iyle aynı biçim).
  static const financeDecide = 'Finans kararını ver';

  /// Finans ek bilgi istedi: kimin yapacağı (v4 B16).
  static const financeInfoFromCustomer = 'Müşteriden bilgi bekleniyor';

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
  static const todayLoadingsEmptyMessage =
      'Bugüne planlanan sevkiyatlar burada listelenir.';

  // Ekip
  static const staffEmptyTitle = 'Personel bulunamadı';
  static const staffEmptyMessage = 'Bayinizin personeli burada listelenir.';
}

/// Saatin yönelme eki, okunuşuna göre: "21:00'e", "09:17'ye", "10:30'a", "16:50'ye" (dakika sıfırsa
/// saat okunur: "10:00'a").
String timeDative(String time) {
  final m = RegExp(r'(\d{1,2})[:.](\d{2})$').firstMatch(time.trim());
  if (m == null) return "$time'e";
  final hour = int.parse(m[1]!);
  final minute = int.parse(m[2]!);
  final word = _numberWord(minute == 0 ? hour : minute);
  const vowels = 'aeıioöuü';
  var last = 'e';
  for (var i = word.length - 1; i >= 0; i--) {
    if (vowels.contains(word[i])) {
      last = word[i];
      break;
    }
  }
  final back = 'aıou'.contains(last);
  final y = vowels.contains(word[word.length - 1]) ? 'y' : '';
  return "$time'$y${back ? 'a' : 'e'}";
}

/// Sayının okunuşunun son kelimesi (ek uyumu için).
String _numberWord(int n) {
  const ones = [
    'sıfır',
    'bir',
    'iki',
    'üç',
    'dört',
    'beş',
    'altı',
    'yedi',
    'sekiz',
    'dokuz',
  ];
  const tens = ['', 'on', 'yirmi', 'otuz', 'kırk', 'elli'];
  if (n < 10) return ones[n];
  final unit = n % 10;
  if (unit != 0) return ones[unit];
  return tens[(n ~/ 10).clamp(0, 5)];
}

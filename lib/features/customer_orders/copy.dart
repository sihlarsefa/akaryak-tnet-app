/// Müşteri sipariş ekranlarının Türkçe metinleri (spec C.5: her özellik boş / hata metnini burada
/// tutar; C.7 sözlüğü: "siz" dili, cümle düzeni, Bayi, Teklif, Teslimat).
library;

import '../../core/network/app_failure.dart';

abstract final class OrdersCopy {
  // ------------------------------------------------------------------ Başlıklar
  /// Sayfa başlığı = sekmenin kelimesi (v4 §3.2).
  static const myOrders = 'Siparişler';
  static const newOrder = 'Sipariş ver';
  static const templates = 'Şablonlar';
  static const orderDetail = 'Sipariş';
  static const wizardTitle = 'Yeni sipariş';

  // ------------------------------------------------------------------ Liste
  static const searchHint = 'Ürün, kişi ya da sipariş ara';
  static const emptyDecisionTitle = 'Onay bekleyen teklif yok';
  static const emptyDecisionMessage =
      'Bayiniz teklif verdiğinde burada görünür; size ayrıca haber veririz.';
  static const emptyActiveTitle = 'Aktif siparişiniz yok';
  static const emptyActiveMessage =
      'Yeni sipariş için Sipariş ver’e dokunun; teklif ve teslimat burada izlenir.';
  static const emptyActiveMessageNoCreate =
      'Şirketinizin siparişleri teklif ve teslimat boyunca burada izlenir.';
  static const emptyHistoryTitle = 'Henüz kapanan sipariş yok';
  static const emptyHistoryMessage =
      'Teslim alınan, reddedilen ve süresi dolan siparişler burada.';
  static const emptyFiltered = 'Aramaya uyan sipariş yok';
  static const emptyFilteredMessage =
      'Yazımı kontrol edin ya da filtreleri temizleyin.';

  /// "'tuzla' için sonuç yok" (v4 §3.6).
  static String noResults(String query) => '‘$query’ için sonuç yok';

  /// Band durum satırı (v4 §3.2): "1 teklif onayınızı bekliyor".
  static String decisionsWaiting(int n, {required bool yours}) =>
      yours ? '$n teklif onayınızı bekliyor' : '$n teklif onay bekliyor';

  /// Sakin durum satırı: "2 sipariş sürüyor".
  static String ordersRunning(int n) =>
      n == 0 ? 'Süren sipariş yok' : '$n sipariş sürüyor';
  static const clearFilters = 'Filtreleri temizle';
  static const offlineNoData =
      'Çevrimdışısınız; bu ekran için kayıtlı veri yok';
  static const forbidden = 'Bu ekran için yetkiniz yok';
  static const forbiddenMessage =
      'Hesabınızın yetkileri bu bilgiyi göstermiyor. Şirket yöneticinize başvurun.';
  static const notFound = 'Bu kayıt artık görüntülenemiyor';
  static const notFoundMessage =
      'Sipariş kaldırılmış ya da erişiminiz değişmiş olabilir.';
  static const lastUpdate = 'Son güncelleme';

  // ------------------------------------------------------------------ Hata metinleri (C.7)
  static const offline = 'Bağlantı yok';
  static const timeout = 'Sunucu zamanında yanıt vermedi';
  static const server = 'Sunucuya şu an ulaşılamıyor';
  static const conflict = 'Bu kayıt siz bakarken değişti';
  static const refresh = 'Yenile';
  static const retry = 'Tekrar dene';

  /// Hata başlığı (C.7 tablosu).
  static String failureTitle(AppFailure f) => switch (f) {
    OfflineFailure() => offline,
    TimeoutFailure() => timeout,
    ServerFailure() => server,
    RateLimitedFailure(:final retryAfter) =>
      retryAfter == null
          ? 'Çok fazla deneme. Biraz sonra tekrar deneyin.'
          : 'Çok fazla deneme. ${retryAfter.inSeconds} sn sonra tekrar deneyin.',
    ForbiddenFailure() => forbidden,
    NotFoundFailure() => notFound,
    ConflictFailure() => conflict,
    _ => 'İşlem tamamlanamadı',
  };

  /// Hata ayrıntısı: iş kuralı ve doğrulamada sunucu mesajı aynen.
  static String failureMessage(AppFailure f) => switch (f) {
    OfflineFailure() => 'Bağlantınızı kontrol edip tekrar deneyin.',
    TimeoutFailure() =>
      'Bağlantınız yavaş olabilir. Birkaç saniye sonra tekrar deneyin.',
    ServerFailure() => 'Birkaç dakika sonra tekrar deneyin.',
    _ => f.message,
  };

  /// "Destek kodu: abcd1234" (sunucu hatasında).
  static String? supportCode(AppFailure f) {
    final t = f.traceId;
    if (f is! ServerFailure || t == null || t.isEmpty) return null;
    return t.length <= 8 ? t : t.substring(0, 8);
  }

  // ------------------------------------------------------------------ Sihirbaz
  static const exitTitle = 'Girdiğiniz bilgiler kaydedilmedi';
  static const exitMessage =
      'Taslak olarak saklarsanız ana sayfadan kaldığınız yerden devam edebilirsiniz.';
  static const keepDraft = 'Taslak olarak sakla';
  static const discard = 'Çık';
  static const stay = 'Devam et';
  static const fromTemplate = 'Şablondan başla';
  static const saveAsTemplate = 'Şablon olarak kaydet';
  static const templateName = 'Şablon adı';
  static const addLine = 'Satır ekle';
  static const differentPointDate = 'Farklı nokta/tarih';
  static const noteForApprover = 'Onaylayana not';
  static const send = 'Siparişi gönder';
  static const sendForApproval = 'Onaya gönder';
  static const estimateNote =
      'Tahmini tutar güncel liste fiyatınızla hesaplanır; kesin tutar bayinin teklifiyle belirlenir.';
  static const priceUnknown = 'Fiyat bilinmiyor';
  static const noPayment =
      'Seçilmezse ödeme belirtilmeden gönderilir; bayi ödeme koşullarını teklifte belirtir.';
  static const noMethods =
      'Bu bayide kullanılabilir ödeme yöntemi tanımlı değil; sipariş ödeme belirtilmeden gönderilir.';
  static const financeHint =
      'Bu ödeme yönteminde sipariş önce bayinin finans onayına gider; onaylanınca bayi teklif verir.';
  static const instrumentPhotoLater =
      'Görseli sipariş oluşunca çekip yükleyeceksiniz (kılavuz çerçeveyle).';
  static const oneInstrumentPerGroup =
      'Birden çok satırda tek belge: tüm siparişlerin toplamı.';
  static const transferReceiptOptional = 'Dekont (isteğe bağlı)';

  // ------------------------------------------------------------------ Gönderim (C.4a)
  static const sending = 'Siparişiniz gönderiliyor';
  static const checking = 'Siparişiniz kontrol ediliyor';
  static const checkingMessage =
      'Bağlantı yavaş ya da koptu. Siparişiniz iki kez oluşmasın diye aynı işlemi güvenle yeniden deniyoruz.';
  static const uncertainTitle = 'Sonuç henüz doğrulanamadı';
  // v4 §3.2: yerin adı alt menüdeki sözcüktür ("Siparişler"; "Siparişlerim" değil).
  static const uncertainMessage =
      'Siparişiniz oluşmuş olabilir. Aynı işlemi güvenle yeniden deneyebilir ya da Siparişler listesiyle karşılaştırabilirsiniz.';
  static const reconciling = 'Siparişleriniz kontrol ediliyor';
  static const reconcilingMessage =
      'Siparişler listesiyle karşılaştırıyoruz; biraz sürebilir.';
  static const reconciledNote =
      'Sonuç Siparişler listesinden doğrulandı; sipariş tekrar gönderilmedi.';
  static const askNewKeyTitle = 'Siparişiniz oluşmamış görünüyor';
  static const askNewKeyMessage =
      'Siparişler listesinde bu gönderime uyan bir kayıt bulamadık. Yeniden gönderilsin mi?';
  static const resend = 'Yeniden gönder';
  static const checkOrders = 'Siparişleri kontrol et';
  static const edit = 'Düzenle';
  static const successTitle = 'Siparişiniz bayiye gönderildi';
  static const companyRequestTitle = 'Şirket içi onaya gönderildi';
  static const partialTitle = 'Siparişin bir kısmı oluşturuldu';
  static const sendRemaining = 'Kalan satırları gönder';
  static const editRemaining = 'Kalan satırları düzenle';
  static const viewOrder = 'Siparişi aç';
  static const viewOrders = 'Siparişlere git';
  static const backHome = 'Ana sayfaya dön';
  static const instrumentHint = 'Bilgiler hatalıysa bayinize bildirin';
  static const pushPrimerTitle = 'Teklifiniz hazır olunca haber verelim mi?';
  static const pushPrimerMessage =
      'Teklif geldiğinde, süresi dolmak üzereyken ve aracınız yola çıktığında bildirim gönderelim. Ayarlardan istediğiniz zaman değiştirebilirsiniz.';

  // ------------------------------------------------------------------ Teklif kararı
  static const approve = 'Teklifi onayla';
  static const revise = 'Revize iste';
  static const reject = 'Reddet';
  static const rejectQuote = 'Teklifi reddet';
  static const reorder = 'Siparişi tekrarla';
  static const makeTemplate = 'Şablon olarak kaydet';
  static const previousPurchases = 'Önceki alımlarınız';
  static const versions = 'Teklif sürümleri';
  static const deliveryDiffers = 'Talepten farklı';
  static const decisionChecking = 'Kararınız kontrol ediliyor';
  static const decisionOffline = 'Çevrimdışıyken karar verilemez';

  /// Talep edenin eşik üstü teklifinde onay kapalı (panel eşitliği): panelin kilitli onay notu ve
  /// sunucunun onay denemesine verdiği metin (`OrderService.RequesterQuoteApprovalMessage`; web, API
  /// ve mobil aynı metin). Değiştirmeyin: uygulama sunucunun reddini bu metinle tanır.
  static const requesterApproveBlocked =
      'Bu tutardaki teklifi yalnızca Onaylayan veya Yönetici onaylayabilir.';

  /// Talep edenin eşik üstü teklifinde aşama cümlesi: sıra onaylayanın (revize ve red ondadır).
  static const approverDecides = 'Onaylayanın kararı bekleniyor';

  /// Teklifler "Düzenler" yetkisi olmayan (panelin uyarısıyla aynı söz).
  static const noDecisionRight =
      'Karar yetkiniz yok; yetkili kullanıcıya iletin.';

  /// Sevkiyatlar "Düzenler" yetkisi olmayan, kabul bekleyen teslimatta (panelin uyarısıyla aynı söz).
  static const noAcceptRight =
      'Teslim kabulü sevkiyat yetkisi olan cari kullanıcısı tarafından yapılır.';
  static const awaitingQuoteHint =
      'Teklif gelince reddedebilir ya da bayinizi arayabilirsiniz';
  static const reviseHint = 'Bayinize ne değişmesini istediğinizi yazın.';
  static const rejectHint =
      'Neden reddettiğinizi bayinizle paylaşın (isteğe bağlı).';
  static const reasonLabel = 'Açıklama';

  // ------------------------------------------------------------------ Takip
  static const tracking = 'Sipariş akışı';

  /// Ayrıntıdaki akış çizelgesi satırı ve sayfası (v4 §5 ekran 05).
  static const history = 'Sipariş geçmişi';
  static const inTransitCaption = 'Araç yolda; canlı konum değildir';
  static const openMap = 'Haritada aç';
  static const callStation = 'Bayiyi ara';
  static const whatsapp = 'WhatsApp';
  static const estimatedDelivery = 'Tahmini teslim';
  static const confirmDelivery = 'Teslimatı onayla';
}

/// Teklif karar ön ayarları — web `Models/OrderTrackingViewModels.cs` `QuoteDecisionPresets`
/// ile birebir aynı (değiştirmeyin).
abstract final class QuoteDecisionPresets {
  static const revisionReasons = [
    'Fiyat yüksek, indirim rica ederiz',
    'Önceki alım fiyatımızın üzerinde',
    'Teslim tarihi uygun değil',
    'Miktarı değiştirmek istiyoruz',
    'Vade / ödeme koşulunu görüşelim',
  ];

  static const rejectReasons = [
    'Fiyat uygun değil',
    'İhtiyaç ortadan kalktı',
    'Başka tedarikçiden temin edildi',
  ];

  static const disputeReasons = [
    'Eksik litre teslim edildi',
    'İrsaliye bilgisi hatalı',
    'Yanlış ürün teslim edildi',
    'Teslimat noktası farklı',
  ];
}

/// Türkçe yönelme hâli eki: saat metnine (`17:30` → `17:30'a`, `18:00` → `18:00'e`).
/// Saat okunuşunun son sözcüğüne göre ünlü uyumu ve kaynaştırma harfi seçilir.
String withDative(String time) {
  final m = RegExp(r'(\d{1,2}):(\d{2})$').firstMatch(time.trim());
  if (m == null) return "$time'e";
  final hour = int.parse(m[1]!);
  final minute = int.parse(m[2]!);
  final n = minute == 0 ? hour : minute;
  final word = _lastNumberWord(n);
  const back = 'aıou';
  final vowels = word.split('').where((c) => 'aeıioöuü'.contains(c)).toList();
  final last = vowels.isEmpty ? 'e' : vowels.last;
  final isBack = back.contains(last);
  final endsWithVowel = 'aeıioöuü'.contains(word[word.length - 1]);
  final suffix = '${endsWithVowel ? 'y' : ''}${isBack ? 'a' : 'e'}';
  return "$time'$suffix";
}

String _lastNumberWord(int n) {
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

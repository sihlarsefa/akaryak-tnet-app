/// İstatistik metinleri (Türkçe; spec R1 §3, tasarım v2 §10). Cümle düzeni, "siz", ünlem ve " · " yok;
/// ay adları cümle içinde küçük harf.
abstract final class StatsCopy {
  // Sayfa
  static const pageTitle = 'İstatistikler';
  static const periodSemantics = 'Dönem';
  static const monthlyTitle = 'Aylık gelişim';
  static const metricAmount = 'Tutar';
  static const metricLiters = 'Litre';
  static const metricOrders = 'Sipariş';
  static const metricSemantics = 'Grafik ölçüsü';
  static const mixTitle = 'Ürün dağılımı';
  static const mixSubtitle = 'satılan litreye göre';
  static const mixSubtitleCustomer = 'alınan litreye göre';
  static const funnelTitle = 'Sipariş hunisi';
  static const deliveriesTitle = 'Sevkiyat';
  static const collectionsTitle = 'Tahsilat';
  static const topCustomersTitle = 'En çok alan cariler';
  static const topCustomersOwnTitle = 'En çok alan carilerim';
  static const teamTitle = 'Saha ekibi';
  static const riskTitle = 'Limit riski';
  static const unitPriceTitle = 'Ortalama birim fiyat';
  static const stationsTitle = 'Bayiler';
  static const pointsTitle = 'Teslimat noktaları';
  static const orderStatusTitle = 'Sipariş durumu';
  static const limitsTitle = 'Limit durumu';
  static const spendingReport = 'Detaylı harcama raporu';
  static const spendingReportHint =
      'Teslimat noktası, ürün ve bayiye göre süzün; PDF olarak paylaşın.';
  static const partialFailure =
      'Bazı bölümler şu an yüklenemedi; diğerleri güncel. Aşağı çekerek yenileyin.';
  static const methodology =
      'Tutarlar onaylanan ve tamamlanan siparişlerin kabul edilen teklif tutarlarıdır; '
      'maliyet ve kâr bilgisi içermez.';
  static const emptyPeriod = 'Bu dönemde henüz sipariş yok';
  static const emptyPeriodMessage =
      'Sipariş geldikçe satış, litre ve dağılımlar burada görünür.';
  static const emptyPeriodCustomer = 'Bu dönemde henüz alım yok';
  static const share = 'İstatistikleri paylaş';
  static const shareFailed =
      'Belge hazırlanamadı. Birkaç saniye sonra tekrar deneyin.';
  static const tableShow = 'Tablo olarak göster';
  static const chartShow = 'Grafik olarak göster';

  /// v4 §5 12: kartın altındaki hayalet düğmeler (ekran okuyucuda [tableShow] / [chartShow]).
  static const tableShort = 'Tablo';
  static const chartShort = 'Grafik';

  /// v4 §5 12: "Ay sonu tahmini 8,89 mn ₺" (kartın altında; grafikte tahmin etiketi yok).
  static String projectionFooter(String value) => 'Ay sonu tahmini $value';

  /// v4 §5 12: sayfanın sonundaki not ("Güncellendi 01:37").
  static String updatedAt(String time) => 'Güncellendi $time';
  static const thisMonth = 'bu ay';
  static const lastSixMonths = 'son 6 ay';
  static const lastTwelveMonths = 'son 12 ay';
  static const byAmount = 'tutara göre';
  static const byLiters = 'litreye göre';
  static String projectionLegend(String value) => 'ay sonu tahmini $value';
  static String updated(String range, String time) =>
      '$range, güncellendi $time';
  static String lastUpdate(String time, String relative) =>
      'Son güncelleme $time, $relative';
  static String notRefreshed(String relative) =>
      'Yenilenemedi, son güncelleme $relative';
  static String computed(String relative) => 'Hesaplandı $relative';
  static String monthSpoken(String month, String value) => '$month, $value';

  // Plaka ve okumalar
  static const kpiSales = 'Satış';
  static const kpiSpending = 'Harcama';
  static const kpiLiters = 'Satılan yakıt';
  static const kpiLitersCustomer = 'Alınan yakıt';
  static const kpiOrders = 'Sipariş';
  static const kpiActiveCustomers = 'Aktif cari';
  static const kpiUnitPrice = 'Ortalama birim fiyat';
  static const readoutAverage = 'Ortalama';
  static const readoutProjection = 'Ay sonu tahmini';
  static const readoutUsed = 'Kullanılan';
  static const readoutLimit = 'Limit';
  static const readoutConverted = 'Siparişe dönüşen';

  // Deste
  static const deckDetails = 'Detaylı istatistikler';
  static const deckStatsLink = 'İstatistikler';
  static const deckNext = 'Sonraki kart';
  static const deckPrevious = 'Önceki kart';
  static const deckMenu = 'Kart seçenekleri';
  static const deckRefresh = 'Yenile';
  static const deckHowTo = 'Nasıl hesaplanır?';
  static const deckLoading = 'İstatistikler yükleniyor';
  static const deckFailedTitle = 'İstatistikler şu an yüklenemedi';
  static const deckFailedHint = 'Birkaç saniye sonra tekrar deneyin.';
  static const deckOfflineTitle = 'İstatistikler bağlantı gelince burada';
  static const deckOfflineHint = 'Bağlantı gelince kendiliğinden yenilenir.';
  static const retry = 'Tekrar dene';
  static const now = 'şu an';

  static String deckPosition(int index, int count) => '$index / $count';

  /// "8 karttan 1. kart: Satış, 8.426.350 lira, yüzde 9,4 artış. Kaydırarak ya da …"
  static String deckCardSemantics(
    int index,
    int count,
    String title, [
    String? summary,
  ]) =>
      '$count karttan $index. kart: $title'
      '${summary == null || summary.isEmpty ? '' : ', $summary'}. '
      'Kaydırarak ya da "$deckNext" ile diğer kartlara geçin.';

  // Kart başlıkları (testler sabitler; ay dönemde yazar: "1–21 Ekim")
  static const cardSales = 'Satış';
  static const cardSalesOwn = 'Portföyümde satış';
  static const cardFuel = 'Satılan yakıt';
  static const cardFunnel = 'Sipariş hunisi';
  static const cardCollections = 'Tahsilat';
  static const cardDeliveries = 'Sevkiyat';
  static const cardTopCustomers = 'En çok alan cariler';
  static const cardTopCustomersOwn = 'En çok alan carilerim';
  static const cardTeam = 'Saha ekibi';
  static const cardOwnForms = 'Saha formlarım';
  static const cardRisk = 'Limit riski';
  static const cardSpend = 'Bu ay harcama';
  static const cardPurchase = 'Yakıt alımı';
  static const cardUnitPrice = 'Ortalama birim fiyat';
  static const cardLimits = 'Limit durumu';
  static const cardPoints = 'Teslimat noktaları';
  static const cardOrderStatus = 'Sipariş durumu';

  // Boş durumlar
  static const noSales = 'Bu dönem henüz satış yok';
  static const noSpend = 'Bu dönem henüz alım yok';
  static const noProducts = 'Ürün dağılımı ilk siparişle oluşur';
  static const noPrice = 'Birim fiyat ilk alımla oluşur';

  // Etiketler
  static const funnelRequests = 'Talep';
  static const funnelQuoted = 'Teklif';
  static const funnelAccepted = 'Onay';
  static const rejected = 'Reddedilen';
  static const expired = 'Süresi dolan';
  static const conversion = 'dönüşüm';
  static const onTime = 'zamanında';
  static const onTimeTarget = 'hedef %90';

  /// Zamanında teslim hedefi (plaka ölçerindeki ince çizgi).
  static const onTimeGoal = 0.9;
  static const warnThreshold = 'uyarı sınırı %80';

  /// Limit riski eşiği (ölçerdeki çizgi).
  static const warnLevel = 0.8;
  static const inTransit = 'Yolda';
  static const planned = 'Planlı';
  static const disputes = 'İtirazlı';
  static const delivered = 'teslimat';
  static const collected = 'tahsil edildi';
  static const overdue = 'Vadesi geçen';
  static const noOverdue = 'Vadesi geçen ödeme yok';
  static const collectedRow = 'Tahsil edilen';
  static const forms = 'form';
  static const converted = 'siparişe dönüştü';
  static const available = 'kullanılabilir';
  static const unlimited = 'Limitsiz';
  static const openOrders = 'açık sipariş';
  static const other = 'Diğer';
  static const drafts = 'Taslak';
  static const pendingApproval = 'Onay bekliyor';
  static const rejectedForms = 'Reddedildi';
  static const convertedForms = 'Dönüştü';
  static const awaitingQuote = 'Teklif bekleniyor';
  static const awaitingDecision = 'Kararınızı bekliyor';
  static const awaitingCompanyApproval = 'Şirket onayında';
  static const deliveredStatus = 'Teslim edildi';
  static const disputedStatus = 'İtirazlı';
  static const nearLimitWord = 'cari limitine yakın';
  static const pointsWord = 'teslimat noktası';
  static const legendConverted = 'siparişe dönüşen';
  static const legendForms = 'form';
  static const firstQuoteLine = 'İlk teklif süresi, ortalama';
  static const limitNear = 'Limitine yakın';
  static const limitCritical = 'Limit dolmak üzere';
  static const limitOver = 'Limit aşıldı';
  static const yourMove = 'Sıra sizde';
  static const cheaper = 'daha ucuz';
  static const pricier = 'daha pahalı';
  static const samePrice = 'aynı';

  static String dueSoon(int days) => '$days gün içinde vadesi gelecek';
  static String dueSoonLine(int days, int count) =>
      '$days gün içinde, ${paymentsCount(count)}';
  static String overdueLine(int count) =>
      count > 0 ? '$overdue, ${paymentsCount(count)}' : noOverdue;
  static String overdueLate(int count) => '${paymentsCount(count)} gecikmede';
  static String collectedSentence(int count) =>
      '${paymentsCount(count)} $collected';
  static String firstQuote(String duration) => 'İlk teklif ortalama $duration';
  static String nearLimit(int count) => nearLimitWord;
  static String topShare(int count, String rate) => 'İlk $count cari: $rate';
  static String topShareWord(int count, {required bool all}) =>
      all ? '$count cari' : 'ilk $count cari';
  static String ordersCount(int n) => '$n sipariş';
  static String paymentsCount(int n) => '$n ödeme';
  static String deliveriesCount(int n) => '$n teslimat';
  static String formsSummary(int forms, int converted) =>
      '$forms form, $converted sipariş';
  static String formsWord(int converted) => 'form, $converted sipariş';
  static String conversionSentence(String rate) => '$rate siparişe dönüştü';
  static String funnelSentence(int requests, int accepted) =>
      '$requests talepten $accepted sipariş onaylandı';
  static String onTimeSentence(String rate) => '$rate zamanında teslim';
  static String decisionsWaiting(int n) => '$n teklif kararınızı bekliyor';
  static String availableAt(int stations) =>
      stations > 1 ? '$available, $stations bayide' : available;
  static String unlimitedAt(int stations) => 'bayide limitsiz';
  static String limitCaption(String available, String limit) =>
      'Kullanılabilir $available, limit $limit';

  /// Büyük yazı düzeninde kısa hâli: "daha ucuz", "daha pahalı", "aynı".
  static String priceShort({required bool? cheaper}) => cheaper == null
      ? samePrice
      : cheaper
      ? StatsCopy.cheaper
      : pricier;
  static String priceSentence(String compare, {required bool? cheaper}) =>
      cheaper == null
      ? compare
      : '$compare ${cheaper ? StatsCopy.cheaper : pricier}';

  // Nasıl hesaplanır?
  static const howSales =
      'Dönemde onaylanan ve tamamlanan siparişlerin kabul edilen teklif tutarlarının toplamı. '
      'Karşılaştırma, önceki dönemin aynı uzunluktaki bölümüyledir. Çubuklar son 6 ayı gösterir; '
      'bir aya dokunarak değerini görün. Kesikli çerçeve, bu ayın bugünkü hızla süreceği varsayılan '
      'ay sonu tahminidir.';
  static const howSalesOwn =
      'Yalnızca portföyünüzdeki carilerin onaylanan ve tamamlanan siparişleri sayılır.';
  static const howFuel =
      'Onaylanan ve tamamlanan siparişlerin litre toplamı. Çubuklar, ürünlerin litre payını gösterir.';
  static const howFunnel =
      'Talep: dönemde oluşturulan siparişler. Teklif: en az bir teklif verilenler. Onay: müşterinin '
      'kabul ettiği siparişler. Dönüşüm = onay / talep. İlk teklif süresi, siparişin oluşmasından ilk '
      'teklife kadar geçen ortalama süredir.';
  static const howCollections =
      'Dönemde tahsil edilen ödemeler, vadesi geçmiş açık ödemeler ve önümüzdeki günlerde vadesi '
      'gelecek çek ve senetler.';
  static const howDeliveries =
      'Dönemde teslim edilen sevkiyatlar. Zamanında: planlanan günün sonuna kadar teslim edilenlerin '
      'oranı; ince çizgi %90 hedefidir. Yolda, planlı ve itirazlı sayıları şu anki durumdur.';
  static const howTopCustomers =
      'Dönemde en çok tutarda alım yapan cariler; çubuk, ilk sıradakine göre büyüklüğü gösterir.';
  static const howTeam =
      'Saha temsilcilerinin dönemde açtığı formlar (beyaz) ve siparişe dönüşenler (siyah).';
  static const howRisk =
      'Limitinin %80 ve üzerini kullanan cariler. Yeni siparişleri finans onayına düşebilir.';
  static const howSpend =
      'Dönemde onaylanan ve tamamlanan siparişlerinizin kabul ettiğiniz teklif tutarları. '
      'Çubuklar son 6 ayı gösterir; kesikli çerçeve ay sonu tahminidir.';
  static const howPurchase =
      'Onaylanan ve tamamlanan siparişlerinizin litre toplamı ve ürün payları.';
  static const howUnitPrice =
      'Tutar / litre. Fiyatın düşmesi sizin için iyidir; kartın cümlesi bunu söyler.';
  static const howLimits =
      'Bayilerdeki limitlerinizin toplamı: kullanılan ve kullanılabilir tutar. İnce çizgi %80 uyarı '
      'sınırıdır; kullanım bunu geçince yeni siparişler finans onayına düşebilir.';
  static const howPoints =
      'Teslimat noktalarınıza dönemde teslim edilen yakıt (litre) ve payları.';
  static const howOrderStatus =
      'Açık siparişlerinizin şu anki durumu; teslim edilenler dönemliktir.';
  static const howOwnForms =
      'Dönemde açtığınız saha formları ve siparişe dönüşenler.';
}

/// İstatistik metinleri (Türkçe; spec R1 §3).
abstract final class StatsCopy {
  // Sayfa
  static const pageTitle = 'İstatistikler';
  static const periodSemantics = 'Dönem';
  static const monthlyTitle = 'Aylık gelişim';
  static const metricAmount = 'Tutar';
  static const metricLiters = 'Litre';
  static const metricOrders = 'Sipariş';
  static const mixTitle = 'Ürün dağılımı';
  static const mixSubtitle = 'Satılan litreye göre';
  static const mixSubtitleCustomer = 'Alınan litreye göre';
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
      'Teslimat noktası, ürün ve bayi süzgeçleri; PDF olarak paylaşın.';
  static const partialFailure =
      'Bazı bölümler şu an yüklenemedi; diğerleri güncel.';
  static const methodology =
      'Tutarlar onaylanan ve tamamlanan siparişlerin kabul edilen teklif tutarlarıdır; '
      'maliyet ve kâr bilgisi içermez.';
  static const emptyPeriod = 'Bu dönemde henüz sipariş yok';
  static const emptyPeriodMessage =
      'Sipariş geldikçe satış, litre ve dağılımlar burada görünür.';
  static const emptyPeriodCustomer = 'Bu dönemde henüz alım yok';

  // KPI
  static const kpiSales = 'Satış';
  static const kpiSpending = 'Harcama';
  static const kpiLiters = 'Satılan yakıt';
  static const kpiLitersCustomer = 'Yakıt alımı';
  static const kpiOrders = 'Sipariş';
  static const kpiActiveCustomers = 'Aktif cari';
  static const kpiUnitPrice = 'Ortalama birim fiyat';

  // Deste
  static const deckDetails = 'Detaylı istatistikler';
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

  static String deckPosition(int index, int count) => '$index / $count';
  static String deckCardSemantics(int index, int count, String title) =>
      '$count karttan $index. kart: $title. Kaydırarak ya da '
      '"$deckNext" ile diğer kartlara geçin.';

  // Kart başlıkları
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

  // Boş durumlar (grafik üstü)
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
  static const inTransit = 'Yolda';
  static const planned = 'Planlı';
  static const disputes = 'İtirazlı';
  static const delivered = 'teslimat';
  static const collected = 'tahsil edildi';
  static const overdue = 'Vadesi geçen';
  static const noOverdue = 'Gecikmiş ödeme yok';
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

  static String dueSoon(int days) => '$days gün içinde vadesi gelecek';
  static String firstQuote(String duration) => 'İlk teklif ortalama $duration';
  static String nearLimit(int count) => 'cari limitine yakın';
  static String topShare(int count, String rate) => 'İlk $count cari: $rate';
  static String ordersCount(int n) => '$n sipariş';
  static String paymentsCount(int n) => '$n ödeme';
  static String formsSummary(int forms, int converted) =>
      '$forms form · $converted sipariş';

  // Nasıl hesaplanır?
  static const howSales =
      'Dönemde onaylanan ve tamamlanan siparişlerin kabul edilen teklif tutarlarının toplamı. '
      'Karşılaştırma, önceki dönemin aynı uzunluktaki bölümüyledir. Grafik son 6 ayı gösterir; '
      'bir aya dokunarak değerini görün.';
  static const howSalesOwn =
      'Yalnızca portföyünüzdeki carilerin onaylanan ve tamamlanan siparişleri sayılır.';
  static const howFuel =
      'Onaylanan ve tamamlanan siparişlerin litre toplamı. Çubuk, ürünlerin litre payını gösterir.';
  static const howFunnel =
      'Talep: dönemde oluşturulan siparişler. Teklif: en az bir teklif verilenler. Onay: müşterinin '
      'kabul ettiği siparişler. Dönüşüm = onay / talep. İlk teklif süresi, siparişin oluşmasından ilk '
      'teklife kadar geçen ortalama süredir.';
  static const howCollections =
      'Dönemde tahsil edilen ödemeler, vadesi geçmiş açık ödemeler ve önümüzdeki günlerde vadesi '
      'gelecek çek / senetler.';
  static const howDeliveries =
      'Dönemde teslim edilen sevkiyatlar. Zamanında: planlanan günün sonuna kadar teslim edilenlerin '
      'oranı. Yolda, planlı ve itirazlı sayıları şu anki durumdur.';
  static const howTopCustomers =
      'Dönemde en çok tutarda alım yapan cariler; çubuk, toplam satıştaki payı gösterir.';
  static const howTeam =
      'Saha temsilcilerinin dönemde açtığı formlar ve siparişe dönüşenler.';
  static const howRisk =
      'Limitinin %80 ve üzerini kullanan cariler. Yeni siparişleri finans onayına düşebilir.';
  static const howSpend =
      'Dönemde onaylanan ve tamamlanan siparişlerinizin kabul ettiğiniz teklif tutarları. '
      'Grafik son 6 ayı gösterir.';
  static const howPurchase =
      'Onaylanan ve tamamlanan siparişlerinizin litre toplamı ve ürün payları.';
  static const howUnitPrice =
      'Tutar / litre. Fiyatın düşmesi sizin için iyidir; fark çipi buna göre renklenir.';
  static const howLimits =
      'Her bayideki limitiniz, kullanılan ve kullanılabilir tutar. %80 üzerinde sarı, aşımda kırmızı.';
  static const howPoints =
      'Teslimat noktalarınıza dönemde teslim edilen yakıt (litre) ve payları.';
  static const howOrderStatus =
      'Açık siparişlerinizin şu anki durumu; teslim edilenler dönemliktir.';
  static const howOwnForms =
      'Dönemde açtığınız saha formları ve siparişe dönüşenler.';
}

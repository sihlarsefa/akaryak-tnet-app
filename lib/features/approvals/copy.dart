/// Onaylarım Türkçe metinleri (spec C.5: her özellik boş / hata metnini kendi copy.dart'ında tutar).
library;

import 'dart:convert';

import '../../core/models/enums.dart';
import '../../core/utils/format.dart';
import '../../core/utils/tr_time.dart';
import 'data/approval_models.dart';

abstract final class ApprovalsCopy {
  /// Sayfa başlığı = alt menü sözcüğü (v4 §3.2).
  static const title = 'Onaylar';

  /// İtilmiş ayrıntının başlığı: nesnenin türü (v4 §3.2).
  static const detailTitle = 'Onay talebi';
  static const searchHint = 'Cari, numara ya da başlık ara';
  static const customerSearchHint = 'Ürün, kişi ya da sipariş ara';

  // ---------------------------------------------------------------- v4 bant durumu (§3.2)

  /// Bayi / merkez: "9 talep kararınızı bekliyor"; gecikme sözüyle ya da dar bantta kısa ("9 talep
  /// bekliyor"), ikisi birden "9 talep" (bant durumu tek satırdır, kesilmez).
  static String bayiWaiting(int n, {bool short = false, bool bare = false}) =>
      bare
      ? '$n talep'
      : (short ? '$n talep bekliyor' : '$n talep kararınızı bekliyor');
  static const bayiCalm = 'Kararınızı bekleyen talep yok';

  /// Cari: "3 iş sizi bekliyor".
  static String customerWaiting(int n) => '$n iş sizi bekliyor';
  static const customerCalm = 'Bekleyen işiniz yok';

  // ---------------------------------------------------------------- v4 gruplar (§5 08)
  static const groupOverdue = 'Gecikmiş';
  static const groupToday = 'Bugün';
  static const groupYesterday = 'Dün';
  static const groupEarlier = 'Daha önce';
  static const groupWaiting = 'Yanıt bekleniyor';

  /// Bende: son tarihi yaklaşan talepler (sunucunun SLA durumu "süresi doluyor"); gecikmişlerin
  /// hemen ardından, gün gruplarından önce.
  static const groupDueSoon = 'Süresi yaklaşan';

  /// Bende'nin gün grupları talebin GELDİĞİ güne göredir; "Bugün" yalnız başına "bugün bitmeli"
  /// diye okunuyordu (satırda "1 g 19 sa" yazarken; v4 B16).
  static const groupArrivedToday = 'Bugün gelenler';
  static const groupArrivedYesterday = 'Dün gelenler';
  static const groupArrivedEarlier = 'Daha önce gelenler';

  // ---------------------------------------------------------------- v4 süzgeç (Filtre sayfası)
  static const filterType = 'Tür';
  static const filterScope = 'Kapsam';
  static const scopeMineAndToMe = 'Bende ve taleplerim';
  static const scopeAll = 'Tüm talepler';
  static const allTypes = 'Tümü';

  /// Satırın ve süzgecin tür adı (v4 §3.2 bayi sözcükleri: "Saha finans" → "Saha formu finansı").
  static String typeName(ApprovalType t) => switch (t) {
    ApprovalType.fieldOrderProfit => 'Saha formu kârlılığı',
    ApprovalType.limitChange => 'Limit talebi',
    ApprovalType.companyOrderRequest => 'Sipariş talebi',
    ApprovalType.orderFinance => 'Sipariş finansı',
    ApprovalType.fieldFormFinance => 'Saha formu finansı',
    ApprovalType.customerOnboarding => 'Yeni cari',
    ApprovalType.leadFinance => 'Ön kayıt',
    ApprovalType.unknown => 'Onay talebi',
  };

  /// Sonuç sözcüğü (Taleplerim, Kararlarım; küçük harfle, tür adının ardından).
  static String outcome(ApprovalStatus s) => switch (s) {
    ApprovalStatus.pending => 'onay bekleniyor',
    ApprovalStatus.infoRequested => 'ek bilgi istendi',
    ApprovalStatus.approved => 'onaylandı',
    ApprovalStatus.rejected => 'reddedildi',
    ApprovalStatus.cancelled => 'iptal edildi',
    ApprovalStatus.unknown => 'durum bilinmiyor',
  };

  /// Cari görünümündeki sonuç (bayinin iç süreci tek söz; v4 §3.2 müşteri sözcükleri).
  static String customerOutcome(
    ApprovalType type,
    ApprovalStatus s, {
    bool canReply = false,
  }) {
    final company = type == ApprovalType.companyOrderRequest;
    return switch (s) {
      ApprovalStatus.pending =>
        company ? 'Şirket onayında' : 'Bayinizde inceleniyor',
      ApprovalStatus.infoRequested =>
        company
            ? 'Bilgi istendi'
            : (canReply ? 'Bayiniz bilgi istiyor' : 'Bilgi bekleniyor'),
      ApprovalStatus.approved => 'Onaylandı',
      ApprovalStatus.rejected => 'Reddedildi',
      ApprovalStatus.cancelled => 'İptal edildi',
      ApprovalStatus.unknown => 'Durum bilinmiyor',
    };
  }

  /// "Yanıt bekleniyor" satırı: bilgi, talebin karşı tarafı olan müşteriden istendi.
  static const askedCustomer = 'Müşteriden ek bilgi istendi';

  /// Sıra izleyicide: satırın fiil satırı (v4 AknListTile.next).
  static const replyNext = 'Bilgi gönderin';
  static const decideNext = 'Karar verin';

  // ---------------------------------------------------------------- v4 ayrıntı rıhtımı
  static const sendInfo = 'Bilgi gönder';
  static const infoReceived = 'Bilgi alındı';
  static const infoReceivedCaption =
      'İstenen bilgi başka yoldan geldiyse talebi incelemeye alın.';

  static String emptyTitle(ApprovalScope scope) => switch (scope) {
    ApprovalScope.toMe => 'Kararınızı bekleyen talep yok',
    ApprovalScope.mine => 'Henüz bir talebiniz yok',
    ApprovalScope.decidedByMe => 'Henüz karar vermediniz',
    ApprovalScope.all => 'Talep yok',
  };

  static String emptyMessage(ApprovalScope scope) => switch (scope) {
    ApprovalScope.toMe =>
      'Yeni bir talep geldiğinde burada görürsünüz; bildirim de alırsınız.',
    ApprovalScope.mine =>
      'Açtığınız onay talepleri ve sonuçları burada listelenir.',
    ApprovalScope.decidedByMe =>
      'Onayladığınız ya da reddettiğiniz talepler burada birikir.',
    ApprovalScope.all => 'Bu bayide henüz onay talebi açılmadı.',
  };

  /// Cari Bende boş (v4 §3.6).
  static const customerEmptyTitle = 'Bekleyen işiniz yok';
  static const customerEmptyMessage =
      'Teklif geldiğinde, teslimat yapıldığında ya da bir talep onayınıza düştüğünde burada görünür.';
  static const goToOrders = 'Siparişlere git';

  /// Arama ya da süzgeç sonuçsuz (v4 §3.6).
  static String noResultTitle(String query) =>
      query.isEmpty ? filteredTitle : "'$query' için sonuç yok";
  static const noResultMessage =
      'Yazımı kontrol edin ya da filtreleri temizleyin.';

  static const filteredTitle = 'Filtreye uyan kayıt yok';
  static const filteredMessage =
      'Arama ya da filtreleri değiştirerek yeniden deneyin.';
  static const clearFilters = 'Filtreleri temizle';
  static const showMine = 'Taleplerimi göster';

  /// Onaylayan Bende'si boşken: verdiği kararlar ve müşteriden yanıt bekleyenler Kararlarım'da.
  static const showDecided = 'Kararlarımı göster';
  static const approverEmptyMessage =
      'Yeni bir talep geldiğinde burada görürsünüz; bildirim de alırsınız. Müşteriden yanıt bekleyen talepler Kararlarım\'da.';

  /// Bende, Sipariş finansı süzgeciyle boş (ana sayfanın Finans durağından gelindi).
  static const financeEmptyTitle = 'Finans onayınızı bekleyen sipariş yok';
  static const financeEmptyMessage =
      'Yeni sipariş finans onayına düştüğünde burada görürsünüz; bildirim de alırsınız.';
  static const showAllTypes = 'Tüm talepleri göster';

  static const notFoundTitle = 'Bu talep artık görüntülenemiyor';
  static const notFoundMessage =
      'Talep sonuçlanmış, kaldırılmış ya da erişiminiz değişmiş olabilir.';

  static const offlineDecision =
      'Çevrimdışısınız; karar vermek için bağlantı gerekli.';

  static const behalfNote =
      'adına vekâletle karar veriyorsunuz; kayıtta iki isim de görünür.';

  /// Cari görünümündeki durum (kademe / onaylayan bilgisi yok; web CustomerStatusText).
  static String customerStatus(ApprovalDetail d) => switch (d.status) {
    ApprovalStatus.pending =>
      d.type.isFinance
          ? 'Bayinin finans değerlendirmesinde'
          : 'Bayinin değerlendirmesinde',
    ApprovalStatus.infoRequested =>
      d.isCustomerAddressed && d.canProvideInfo
          ? 'Sizden ek bilgi bekleniyor'
          : 'Bayi ek bilgi bekliyor',
    ApprovalStatus.approved =>
      d.isConditionallyApproved ? 'Koşullu onaylandı' : 'Onaylandı',
    ApprovalStatus.rejected => 'Reddedildi',
    _ => 'Talep kapatıldı',
  };

  /// Koşullu onayın cariye açıklaması (web ConditionalText).
  static String conditionalText(ApprovalType type) => switch (type) {
    ApprovalType.orderFinance =>
      'Ödeme koşulları finans kararına göre güncellendi; güncel ödeme bilgisi siparişinizde.',
    ApprovalType.customerOnboarding =>
      'Cari hesabınız onaylandı; siparişleriniz bir süre bayinin finans incelemesinden geçebilir.',
    _ => 'Onay koşullu verildi.',
  };

  /// "Ek bilgi iste"de istenebilecek belge türleri (teslimat / itiraz kanıtı hariç; spec B.5).
  static const requestableKinds = [
    AttachmentKind.taxPlate,
    AttachmentKind.signatureCircular,
    AttachmentKind.tradeRegistryGazette,
    AttachmentKind.activityCertificate,
    AttachmentKind.chequeImage,
    AttachmentKind.promissoryNoteImage,
    AttachmentKind.transferReceipt,
    AttachmentKind.posSlip,
    AttachmentKind.letterOfGuarantee,
    AttachmentKind.dbsContract,
    AttachmentKind.other,
  ];

  /// "Ek bilgi iste"nin belge türleri, türe göre: sipariş finansında önce ödeme belgeleri.
  static List<AttachmentKind> requestableKindsFor(ApprovalType t) =>
      t == ApprovalType.orderFinance
      ? const [
          AttachmentKind.chequeImage,
          AttachmentKind.promissoryNoteImage,
          AttachmentKind.transferReceipt,
          AttachmentKind.posSlip,
          AttachmentKind.letterOfGuarantee,
          AttachmentKind.dbsContract,
          AttachmentKind.taxPlate,
          AttachmentKind.signatureCircular,
          AttachmentKind.tradeRegistryGazette,
          AttachmentKind.activityCertificate,
          AttachmentKind.other,
        ]
      : requestableKinds;

  // ---------------------------------------------------------------- Sipariş finansı (finans birimi)

  /// Plakanın başlığı: teklif öncesi tutar tahmindir (panelde "Tahmini tutar").
  static const estimatedAmount = 'Tahmini tutar';
  static const quotedAmount = 'Teklif tutarı';
  static const orderAmount = 'Sipariş tutarı';

  /// Ayrıntının "Siparişi aç" satırı (plakanın altında).
  static const openOrder = 'Siparişi aç';

  /// Onaylayan ek bilgi istedi; sıra müşteride (başlığın cümlesi; turuncu değil).
  static const waitingCustomer = 'Müşteriden yanıt bekleniyor';

  /// Sonuç bandının ve bekleme kartının bağlantısı: Bende'deki sıradaki talebi açar.
  static const nextRequest = 'Sıradaki talep';

  static const financeReviewTitle = 'Finans incelemesi';
  static const financeCardTitle = 'Cari finans durumu';
  static const financeCardOpen = 'Finans kartı';
  static const financeHistoryTitle = 'Geçmiş';
  static const paymentGroupTitle = 'Aynı ödemedeki siparişler';
  static const paymentGroupSubtitle = 'Her siparişin kendi finans onayı var.';
  static const orderFactsTitle = 'Sipariş';
  static const reasonsCaption = 'Gerekçe';
  static const paymentCaption = 'Ödeme';
  static const limitCaption = 'Limit';
  static const noReasons = 'Gerekçe belirtilmedi.';
  static const routineReason =
      'Başka bir finans gerekçesi yok; sipariş genel kural gereği incelemede.';
  static const none = 'Yok';
  static const firstOrder = 'İlk sipariş';
  static const cashShort = 'Peşin';
  static const limitUnknown = 'Limit bilgisi bu talepte yok.';
  static const noLimit = 'Tanımlanmadı';
  static const usageAfter = 'Bu siparişle kullanım';
  static const usageNow = 'Kullanım';
  static const methodNotAllowed = 'Yöntem finans kartında izinli değil';

  /// Eski sunucunun kullanım satırı ekranda ok işaretsiz (yazım kuralı): "%92 → %131" → "%92, bu
  /// siparişle %131".
  static String usageText(String text) {
    final m = RegExp(r'^%(\d+)\s*→\s*%(\d+)$').firstMatch(text.trim());
    if (m == null) return text.replaceAll('→', ',');
    return '%${m[1]}, bu siparişle %${m[2]}';
  }

  static String termExceedsCard(int max) =>
      'Vade kartın en uzun vadesini ($max gün) aşıyor';

  static String unpricedOthers(String amount) =>
      'Teklifi bekleyen diğer siparişler ≈ $amount; teklif verilince kullanıma girer.';

  static String orderCountLine(int n, int completed) =>
      completed > 0 ? '$n sipariş, $completed tamamlandı' : '$n sipariş';

  static String overdueCollectionsLine(OrderFinanceHistory h) => [
    '${h.overdueCount} sipariş',
    Fmt.moneyWhole(h.overdueAmount),
    if (h.maxOverdueDays != null) 'en uzun ${h.maxOverdueDays} gün',
  ].join(', ');

  /// "Çek, 60 gün vade" / "Havale / EFT, peşin" / "Belirtilmemiş".
  static String paymentLine(OrderFinancePayment p) {
    final name = p.methodName.trim();
    if (name.isEmpty || p.methodCode == null && name == 'Belirtilmemiş') {
      return 'Belirtilmemiş';
    }
    final term = p.termDays ?? 0;
    return [
      name,
      term > 0 ? '$term gün vade' : 'peşin',
      if ((p.installments ?? 0) > 1) '${p.installments} taksit',
    ].join(', ');
  }

  static String riskReportLine(OrderFinanceRiskReport? r) {
    if (r == null) return 'Çekilmedi';
    if (!r.success) {
      return r.errorMessage == null
          ? 'Alınamadı'
          : 'Alınamadı: ${r.errorMessage}';
    }
    final risk = switch (r.riskClass) {
      RiskClass.a => 'A',
      RiskClass.b => 'B',
      RiskClass.c => 'C',
      RiskClass.d => 'D',
      _ => null,
    };
    return [
      if (risk != null) 'Sınıf $risk',
      if (r.score != null) 'skor ${r.score}',
      if ((r.bouncedChequeCount ?? 0) > 0)
        'karşılıksız çek ${r.bouncedChequeCount}',
      if ((r.overdueAmount ?? 0) > 0)
        'bankada gecikmiş ${Fmt.moneyWhole(r.overdueAmount)}',
      if (r.requestedAt != null) Fmt.date(r.requestedAt),
      if (r.isMock) 'deneme verisi',
    ].join(', ');
  }

  static String collateralLine(OrderFinanceCard c) {
    final ratio = Fmt.percent(c.collateralRatioPercent, maxFraction: 0);
    final suggested = c.suggestedCollateralRatioPercent;
    final rate = suggested != null && suggested != c.collateralRatioPercent
        ? 'oran $ratio (öneri ${Fmt.percent(suggested, maxFraction: 0)})'
        : 'oran $ratio';
    return [
      c.activeCollateralCount == 0
          ? 'Geçerli teminat yok'
          : '${c.activeCollateralCount} adet, ${Fmt.moneyWhole(c.activeCollateralAmount)}',
      rate,
    ].join(', ');
  }

  /// Ödeme yöntemi kodunun kısa adı (finans kartı ve koşullar).
  static String methodName(String code) => switch (code.trim()) {
    'NAKIT' => 'Nakit',
    'HAVALE' => 'Havale / EFT',
    'KART' => 'Kredi / banka kartı',
    'DBS' => 'DBS',
    'CEK' => 'Çek',
    'SENET' => 'Senet',
    'ACIK_HESAP' => 'Açık hesap',
    'TEMINAT' => 'Teminat mektubu',
    'UTTS' => 'Taşıt tanıma (UTTS)',
    'AVANS' => 'Ön ödemeli bakiye',
    _ => code,
  };

  /// "Aylık" → "aylık" (limit satırında).
  static String periodLower(String p) => switch (p) {
    'Aylık' => 'aylık',
    'Haftalık' => 'haftalık',
    'Günlük' => 'günlük',
    _ => p,
  };

  /// Koşullu onayın koşulları (sunucu olayın notuna koşul JSON'unu yazar:
  /// `{"methodCode":"HAVALE","termDays":"30"}`, yalnızca not verildiyse `{"text":"…"}`): okunur
  /// özet ("Ödeme yöntemi: Havale / EFT, Vade: 30 gün"). JSON değilse metin olduğu gibi.
  static String? conditionsText(String? note) {
    final n = note?.trim();
    if (n == null || n.isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(n);
    } on FormatException {
      return n;
    }
    if (decoded is! Map) return n;
    final parts = <String>[];
    decoded.forEach((k, v) {
      final value = v is List ? v.join(',') : '$v';
      final text = switch ('$k') {
        'methodCode' => 'Ödeme yöntemi: ${methodName(value)}',
        'termDays' => value == '0' ? 'Vade: peşin' : 'Vade: $value gün',
        'limitAmount' => 'Limit: ${Fmt.moneyWhole(double.tryParse(value))}',
        'limitPeriod' => 'Limit dönemi: ${periodLower(value)}',
        'maxTermDays' => 'En uzun vade: $value gün',
        'allowedMethodCodes' =>
          'İzinli yöntemler: ${value.split(',').map(methodName).join(', ')}',
        'riskClass' =>
          'Risk sınıfı: ${RiskClass.fromCode(int.tryParse(value)).label}',
        'collateralRatioPercent' =>
          'Teminat oranı: ${Fmt.percent(double.tryParse(value))}',
        'nextReviewDate' =>
          'Gözden geçirme: ${Fmt.date(TrTime.parseDate(value))}',
        'text' || 'note' => value.trim().isEmpty ? null : value.trim(),
        _ => null,
      };
      if (text != null) parts.add(text);
    });
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// Karar sayfasının alt başlığı: sipariş finansında kararın sonucu söylenir (panelin ipucu:
  /// "sipariş kapanır, ayrılan limit serbest kalır").
  static String? decisionSubtitle(ApprovalDecision d, {ApprovalType? type}) {
    final order = type == ApprovalType.orderFinance;
    return switch (d) {
      ApprovalDecision.approve =>
        order
            ? 'Onaylayınca sipariş teklif aşamasına geçer. Karar kaydı geri alınamaz.'
            : 'Karar kaydı geri alınamaz.',
      ApprovalDecision.conditionalApprove =>
        'Yalnızca değiştirmek istediğiniz koşulları doldurun.',
      ApprovalDecision.requestInfo =>
        order
            ? 'Müşteri yanıtlayana kadar sipariş bekler.'
            : 'Talep eden yanıtlayana kadar talep bekler.',
      ApprovalDecision.reject =>
        order
            ? 'Sipariş kapanır, ayrılan limit serbest kalır. Gerekçe müşteriye iletilir.'
            : 'Gerekçe talep edene iletilir.',
      ApprovalDecision.unknown => null,
    };
  }

  /// Sonuç bandının son satırı (sipariş finansı): kararın sipariş için anlamı.
  static String? financeOutcome(ApprovalType t, ApprovalStatus s) {
    if (t != ApprovalType.orderFinance) return null;
    return switch (s) {
      ApprovalStatus.approved => 'Sipariş teklif aşamasına geçti.',
      ApprovalStatus.rejected => 'Sipariş kapandı.',
      _ => null,
    };
  }

  static String decisionDone(ApprovalDecision d) => switch (d) {
    ApprovalDecision.approve => 'Talep onaylandı.',
    ApprovalDecision.conditionalApprove => 'Talep koşullu onaylandı.',
    ApprovalDecision.requestInfo => 'Ek bilgi istendi.',
    ApprovalDecision.reject => 'Talep reddedildi.',
    ApprovalDecision.unknown => 'Kararınız kaydedildi.',
  };
}

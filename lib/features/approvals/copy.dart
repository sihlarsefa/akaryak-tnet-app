/// Onaylarım Türkçe metinleri (spec C.5: her özellik boş / hata metnini kendi copy.dart'ında tutar).
library;

import '../../core/models/enums.dart';
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

  static String decisionDone(ApprovalDecision d) => switch (d) {
    ApprovalDecision.approve => 'Talep onaylandı.',
    ApprovalDecision.conditionalApprove => 'Talep koşullu onaylandı.',
    ApprovalDecision.requestInfo => 'Ek bilgi istendi.',
    ApprovalDecision.reject => 'Talep reddedildi.',
    ApprovalDecision.unknown => 'Kararınız kaydedildi.',
  };
}

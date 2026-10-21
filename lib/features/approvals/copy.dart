/// Onaylarım Türkçe metinleri (spec C.5: her özellik boş / hata metnini kendi copy.dart'ında tutar).
library;

import '../../core/models/enums.dart';
import 'data/approval_models.dart';

abstract final class ApprovalsCopy {
  static const title = 'Onaylarım';
  static const searchHint = 'Numara, başlık ya da cari ara';

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

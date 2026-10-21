/// Sunucu enum'ları (sayısal kodlar korunur), Türkçe etiketleri ve `unknown` yedekleri (spec C.4).
///
/// Etiketler sunucudaki `*Labels` sınıflarıyla aynıdır (`AkaryakitNet.Core/Enums`). Sunucu bir
/// `*Label` alanı gönderiyorsa ekranda o tercih edilir; bu etiketler yedek ve filtre içindir.
/// Renk, ikon ve ton eşlemesi `core/ui/status.dart` (M0b) içindedir.
library;

/// Kodlu enum ortak arayüzü.
abstract interface class CodedEnum {
  int get code;
  String get label;
  bool get isUnknown;
}

T _fromCode<T extends CodedEnum>(List<T> values, int? code, T unknown) {
  if (code == null) return unknown;
  for (final v in values) {
    if (v.code == code && !v.isUnknown) return v;
  }
  return unknown;
}

/// Sipariş durumu (Order.Status).
enum OrderStatus implements CodedEnum {
  created(0, 'Oluşturuldu'),
  awaitingQuote(1, 'Teklif bekleniyor'),
  awaitingApproval(2, 'Onay bekleniyor'),
  approved(3, 'Onaylandı'),
  rejected(4, 'Reddedildi'),
  revisionRequested(5, 'Revize istendi'),
  expired(6, 'Süresi doldu'),
  completed(7, 'Tamamlandı'),
  unknown(-1, 'Bilinmiyor');

  const OrderStatus(this.code, this.label);
  @override
  final int code;
  @override
  final String label;
  @override
  bool get isUnknown => this == unknown;

  static OrderStatus fromCode(int? code) => _fromCode(values, code, unknown);

  /// Karar ya da teklif bekleyen açık durumlar.
  bool get isOpen =>
      this == created ||
      this == awaitingQuote ||
      this == awaitingApproval ||
      this == revisionRequested;

  /// Son durumlar.
  bool get isFinal => this == rejected || this == expired || this == completed;
}

/// Sevkiyat durumu (Shipment.Status).
enum ShipmentStatus implements CodedEnum {
  planned(0, 'Planlandı'),
  inTransit(1, 'Yolda'),
  reported(2, 'Kabul bekliyor'),
  accepted(3, 'Teslim alındı'),
  disputed(4, 'İtirazlı'),
  cancelled(5, 'İptal'),
  unknown(-1, 'Bilinmiyor');

  const ShipmentStatus(this.code, this.label);
  @override
  final int code;
  @override
  final String label;
  @override
  bool get isUnknown => this == unknown;

  static ShipmentStatus fromCode(int? code) => _fromCode(values, code, unknown);

  /// Açık (kapanmamış) sevkiyat: Planlandı, Yolda, Kabul bekliyor, İtirazlı.
  bool get isOpen =>
      this == planned ||
      this == inTransit ||
      this == reported ||
      this == disputed;
}

/// Onay talebi türü (ApprovalRequest.Type).
enum ApprovalType implements CodedEnum {
  fieldOrderProfit(1, 'Saha formu kârlılık onayı', 'Saha formu'),
  limitChange(2, 'Limit talebi', 'Limit'),
  companyOrderRequest(3, 'Şirket içi sipariş talebi', 'Sipariş talebi'),
  orderFinance(4, 'Sipariş finans onayı', 'Sipariş finans'),
  fieldFormFinance(5, 'Saha formu finans onayı', 'Saha finans'),
  customerOnboarding(6, 'Yeni cari finans onayı', 'Yeni cari'),
  leadFinance(7, 'Ön kayıt finans onayı', 'Ön kayıt'),
  unknown(-1, 'Onay talebi', 'Diğer');

  const ApprovalType(this.code, this.label, this.shortLabel);
  @override
  final int code;
  @override
  final String label;

  /// Liste satırı ve filtre çipi için kısa ad.
  final String shortLabel;
  @override
  bool get isUnknown => this == unknown;

  static ApprovalType fromCode(int? code) => _fromCode(values, code, unknown);

  /// Finans türleri (Koşullu onay yalnızca bunlarda).
  bool get isFinance =>
      this == orderFinance ||
      this == fieldFormFinance ||
      this == customerOnboarding ||
      this == leadFinance;
}

/// Onay talebi durumu.
enum ApprovalStatus implements CodedEnum {
  pending(0, 'Bekliyor'),
  approved(1, 'Onaylandı'),
  rejected(2, 'Reddedildi'),
  cancelled(3, 'İptal edildi'),
  infoRequested(4, 'Ek bilgi istendi'),
  unknown(-1, 'Bilinmiyor');

  const ApprovalStatus(this.code, this.label);
  @override
  final int code;
  @override
  final String label;
  @override
  bool get isUnknown => this == unknown;

  static ApprovalStatus fromCode(int? code) => _fromCode(values, code, unknown);

  /// Açık: karar ya da ek bilgi bekliyor.
  bool get isOpen => this == pending || this == infoRequested;
}

/// Onay kararı (komut; `approvals/{id}/decide` gövdesindeki `decision`).
enum ApprovalDecision implements CodedEnum {
  approve(1, 'Onayla'),
  conditionalApprove(2, 'Koşullu onayla'),
  requestInfo(3, 'Ek bilgi iste'),
  reject(4, 'Reddet'),
  unknown(-1, 'Bilinmiyor');

  const ApprovalDecision(this.code, this.label);
  @override
  final int code;
  @override
  final String label;
  @override
  bool get isUnknown => this == unknown;

  static ApprovalDecision fromCode(int? code) =>
      _fromCode(values, code, unknown);

  /// Not zorunlu kararlar (Ek bilgi iste, Reddet).
  bool get requiresNote => this == requestInfo || this == reject;
}

/// Onay SLA durumu.
enum ApprovalSlaState implements CodedEnum {
  none(0, 'Süre yok'),
  onTime(1, 'Süresinde'),
  dueSoon(2, 'Süresi doluyor'),
  overdue(3, 'Süresi geçti'),
  unknown(-1, 'Bilinmiyor');

  const ApprovalSlaState(this.code, this.label);
  @override
  final int code;
  @override
  final String label;
  @override
  bool get isUnknown => this == unknown;

  static ApprovalSlaState fromCode(int? code) =>
      _fromCode(values, code, unknown);
}

/// Sipariş ödeme (tahsilat) durumu (Order.PaymentStatus).
enum PaymentStatus implements CodedEnum {
  none(0, 'Belirtilmemiş'),
  pending(1, 'Bekliyor'),
  documentUploaded(2, 'Belge yüklendi'),
  collected(3, 'Tahsil edildi'),
  bounced(4, 'Karşılıksız'),
  refunded(5, 'İade'),
  cancelled(6, 'İptal'),
  unknown(-1, 'Bilinmiyor');

  const PaymentStatus(this.code, this.label);
  @override
  final int code;
  @override
  final String label;
  @override
  bool get isUnknown => this == unknown;

  static PaymentStatus fromCode(int? code) => _fromCode(values, code, unknown);

  bool get isFinal =>
      this == collected ||
      this == bounced ||
      this == refunded ||
      this == cancelled;
}

/// Siparişin (ve saha formunun) finans onayı durumu.
enum OrderFinanceStatus implements CodedEnum {
  notRequired(0, 'Gerekmiyor'),
  pending(1, 'Finans onayında'),
  approved(2, 'Finans onaylandı'),
  conditionallyApproved(3, 'Koşullu onaylandı'),
  infoRequested(4, 'Ek bilgi istendi'),
  rejected(5, 'Finans reddetti'),
  unknown(-1, 'Bilinmiyor');

  const OrderFinanceStatus(this.code, this.label);
  @override
  final int code;
  @override
  final String label;
  @override
  bool get isUnknown => this == unknown;

  static OrderFinanceStatus fromCode(int? code) =>
      _fromCode(values, code, unknown);

  /// Finans kararı bekleniyor.
  bool get isAwaitingDecision => this == pending || this == infoRequested;

  /// Finans açısından ilerleyebilir.
  bool get isCleared =>
      this == notRequired || this == approved || this == conditionallyApproved;
}

/// Saha ön kaydı durumu (CustomerLead.Status).
enum LeadStatus implements CodedEnum {
  draft(0, 'Taslak'),
  submitted(1, 'Finansa gönderildi'),
  inReview(2, 'Finans incelemesinde'),
  infoRequested(3, 'Ek bilgi istendi'),
  approved(4, 'Onaylandı'),
  converted(5, 'Cariye dönüştürüldü'),
  rejected(6, 'Reddedildi'),
  cancelled(7, 'İptal edildi'),
  unknown(-1, 'Bilinmiyor');

  const LeadStatus(this.code, this.label);
  @override
  final int code;
  @override
  final String label;
  @override
  bool get isUnknown => this == unknown;

  static LeadStatus fromCode(int? code) => _fromCode(values, code, unknown);

  /// Temsilci düzenleyebilir (taslak ya da ek bilgi istendi).
  bool get isEditable => this == draft || this == infoRequested;
}

/// Saha sipariş formu durumu.
enum FieldOrderFormStatus implements CodedEnum {
  draft(0, 'Taslak'),
  pendingApproval(1, 'Onay bekliyor'),
  approved(2, 'Onaylandı'),
  rejected(3, 'Reddedildi'),
  converted(4, 'Siparişe dönüştü'),
  cancelled(5, 'İptal edildi'),
  unknown(-1, 'Bilinmiyor');

  const FieldOrderFormStatus(this.code, this.label);
  @override
  final int code;
  @override
  final String label;
  @override
  bool get isUnknown => this == unknown;

  static FieldOrderFormStatus fromCode(int? code) =>
      _fromCode(values, code, unknown);

  bool get isEditable => this == draft;
  bool get isFinal =>
      this == rejected || this == converted || this == cancelled;
}

/// Belge eki türü (Attachment.Kind). Sunucu `kindLabel` gönderir; bu etiketler yedektir.
enum AttachmentKind implements CodedEnum {
  chequeImage(1, 'Çek görseli'),
  promissoryNoteImage(2, 'Senet görseli'),
  transferReceipt(3, 'Havale / EFT dekontu'),
  posSlip(4, 'POS slibi'),
  letterOfGuarantee(5, 'Teminat mektubu'),
  dbsContract(6, 'DBS sözleşmesi'),
  taxPlate(10, 'Vergi levhası'),
  signatureCircular(11, 'İmza sirküleri'),
  tradeRegistryGazette(12, 'Ticaret sicil gazetesi'),
  activityCertificate(13, 'Faaliyet belgesi'),
  visitPhoto(14, 'Ziyaret fotoğrafı'),
  riskReportPdf(20, 'Risk raporu (PDF)'),
  financeNote(21, 'Finans notu'),
  deliveryPhoto(30, 'Teslimat fotoğrafı'),
  deliverySignature(31, 'Teslim imzası'),
  disputePhoto(32, 'İtiraz fotoğrafı'),
  other(99, 'Diğer'),
  unknown(-1, 'Belge');

  const AttachmentKind(this.code, this.label);
  @override
  final int code;
  @override
  final String label;
  @override
  bool get isUnknown => this == unknown;

  static AttachmentKind fromCode(int? code) => _fromCode(values, code, unknown);
}

/// Belge ekinin sahibi olan kaydın türü (Attachment.OwnerType).
enum AttachmentOwnerType implements CodedEnum {
  order(1, 'Sipariş'),
  paymentInstrument(2, 'Çek / senet'),
  stationCustomer(3, 'Cari bağlantısı'),
  customer(4, 'Cari'),
  customerLead(5, 'Saha ön kaydı'),
  riskReport(6, 'Risk raporu'),
  approvalRequest(7, 'Onay talebi'),
  customerCollateral(8, 'Teminat'),
  fieldOrderForm(9, 'Saha sipariş formu'),
  shipment(10, 'Sevkiyat'),
  unknown(-1, 'Kayıt');

  const AttachmentOwnerType(this.code, this.label);
  @override
  final int code;
  @override
  final String label;
  @override
  bool get isUnknown => this == unknown;

  static AttachmentOwnerType fromCode(int? code) =>
      _fromCode(values, code, unknown);
}

/// Ödeme belgesi türü (PaymentInstrument.Kind).
enum InstrumentKind implements CodedEnum {
  cheque(1, 'Çek'),
  promissoryNote(2, 'Senet'),
  letterOfGuarantee(3, 'Teminat mektubu'),
  unknown(-1, 'Belge');

  const InstrumentKind(this.code, this.label);
  @override
  final int code;
  @override
  final String label;
  @override
  bool get isUnknown => this == unknown;

  static InstrumentKind fromCode(int? code) => _fromCode(values, code, unknown);
}

/// Çek / senet / mektup portföy durumu (PaymentInstrument.Status).
enum InstrumentStatus implements CodedEnum {
  received(1, 'Alındı'),
  inPortfolio(2, 'Portföyde'),
  deposited(3, 'Bankaya verildi'),
  collected(4, 'Tahsil edildi'),
  bounced(5, 'Karşılıksız'),
  returned(6, 'İade edildi'),
  protested(7, 'Protesto edildi'),
  unknown(-1, 'Bilinmiyor');

  const InstrumentStatus(this.code, this.label);
  @override
  final int code;
  @override
  final String label;
  @override
  bool get isUnknown => this == unknown;

  static InstrumentStatus fromCode(int? code) =>
      _fromCode(values, code, unknown);
}

/// Müşteri şirket kullanıcısının şirket içi rolü. Sunucuda null = Yönetici ([fromCode] null → [admin]).
enum CustomerUserRole implements CodedEnum {
  requester(1, 'Talep eden'),
  approver(2, 'Onaylayan'),
  admin(3, 'Yönetici'),
  unknown(-1, 'Bilinmiyor');

  const CustomerUserRole(this.code, this.label);
  @override
  final int code;
  @override
  final String label;
  @override
  bool get isUnknown => this == unknown;

  /// null → [admin] (eski / ana cari kullanıcısı).
  static CustomerUserRole fromCode(int? code) =>
      code == null ? admin : _fromCode(values, code, unknown);

  /// Şirket içi talepleri onaylayabilir (Onaylayan ya da Yönetici).
  bool get canApprove => this == approver || this == admin;
}

/// Cari finans kartı durumu (CustomerFinanceProfile.Status).
enum FinanceProfileStatus implements CodedEnum {
  pending(0, 'Finans onayı bekliyor'),
  approved(1, 'Onaylı'),
  conditional(2, 'Koşullu onaylı'),
  infoRequested(3, 'Ek bilgi istendi'),
  rejected(4, 'Reddedildi'),
  suspended(5, 'Askıya alındı'),
  unknown(-1, 'Bilinmiyor');

  const FinanceProfileStatus(this.code, this.label);
  @override
  final int code;
  @override
  final String label;
  @override
  bool get isUnknown => this == unknown;

  static FinanceProfileStatus fromCode(int? code) =>
      _fromCode(values, code, unknown);

  /// Sipariş verilebilir mi.
  bool get allowsOrdering => this == approved || this == conditional;
}

/// Risk sınıfı (A en iyi, D en riskli).
enum RiskClass implements CodedEnum {
  none(0, 'Bilinmiyor'),
  a(1, 'A (düşük risk)'),
  b(2, 'B'),
  c(3, 'C'),
  d(4, 'D (yüksek risk)'),
  unknown(-1, 'Bilinmiyor');

  const RiskClass(this.code, this.label);
  @override
  final int code;
  @override
  final String label;
  @override
  bool get isUnknown => this == unknown;

  static RiskClass fromCode(int? code) => _fromCode(values, code, unknown);

  bool get isHighRisk => this == c || this == d;
}

/// Şirket içi sipariş talebi durumu (CustomerOrderRequest.Status).
enum CustomerOrderRequestStatus implements CodedEnum {
  pending(0, 'Onay bekliyor'),
  approved(1, 'Onaylandı'),
  rejected(2, 'Reddedildi'),
  cancelled(3, 'Geri çekildi'),
  unknown(-1, 'Bilinmiyor');

  const CustomerOrderRequestStatus(this.code, this.label);
  @override
  final int code;
  @override
  final String label;
  @override
  bool get isUnknown => this == unknown;

  static CustomerOrderRequestStatus fromCode(int? code) =>
      _fromCode(values, code, unknown);
}

/// Etiket bütünlüğü testleri ve hata ayıklama ekranı için tüm kodlu enum'lar.
const List<List<CodedEnum>> allCodedEnums = [
  OrderStatus.values,
  ShipmentStatus.values,
  ApprovalType.values,
  ApprovalStatus.values,
  ApprovalDecision.values,
  ApprovalSlaState.values,
  PaymentStatus.values,
  OrderFinanceStatus.values,
  LeadStatus.values,
  FieldOrderFormStatus.values,
  AttachmentKind.values,
  AttachmentOwnerType.values,
  InstrumentKind.values,
  InstrumentStatus.values,
  CustomerUserRole.values,
  FinanceProfileStatus.values,
  RiskClass.values,
  CustomerOrderRequestStatus.values,
];

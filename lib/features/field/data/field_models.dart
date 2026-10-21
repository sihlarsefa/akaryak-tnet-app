import 'package:flutter/foundation.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/json.dart';
import '../../../core/utils/tr_time.dart';

/// Saha formu modelleri (sunucu: `FieldSalesDtos.cs`, `FieldOrderSupportDtos.cs`, `Mobile/FieldDtos.cs`).
/// JSON anahtarları C# camelCase adlarıyla aynıdır. Tarihler: oluşturma/gönderme/karar anları UTC (ofsetsiz);
/// sevk, teslim ve ödeme günleri Türkiye yerel günüdür.

/// Kâr modeli (`PricingModel`): 0 eski marj, 1 barem (sipariş formu v2).
enum FieldPricingModel {
  margin(0),
  barem(1);

  const FieldPricingModel(this.code);
  final int code;

  static FieldPricingModel fromCode(int? code) => code == 0 ? margin : barem;
}

/// Onay kademesi (`FieldApprovalLevels`): 0 otomatik, 1 bayi yöneticisi, 2 üst, 3 istisna.
abstract final class FieldLevels {
  static const auto = 0;
  static const manager = 1;
  static const senior = 2;
  static const exception = 3;

  /// Kısa ad (web `FieldOrderRules.LevelLabel`).
  static String label(int? level) => switch (level) {
    null => '—',
    auto => 'Otomatik',
    manager => 'Bayi yöneticisi',
    senior => 'Üst onay',
    _ => 'İstisna onayı',
  };

  /// "Onay bekliyor" uyarısındaki cümle (web `Detail.cshtml` FieldApprovalLevelsText).
  static String waitingText(int? level, {bool barem = true}) => switch (level) {
    null => 'Onay bekleniyor.',
    auto => 'Otomatik onay kademesinde.',
    manager => 'Bayi yöneticisinin onayı bekleniyor.',
    senior =>
      barem
          ? 'Üst onay (bayi müdürü / finans müdürü ya da merkez) bekleniyor.'
          : 'Üst yönetici onayı bekleniyor.',
    _ => 'İstisna onayı (bayi sahibi ya da merkez) bekleniyor.',
  };
}

/// Dönüşüm hatası işareti (`FieldOrderRules.ConversionErrorMarker`).
abstract final class FieldConversion {
  static const marker = 'Dönüşüm hatası:';
  static const pendingText =
      'Dönüşüm tamamlanmadı (işlem yarıda kalmış olabilir). Açılan siparişler korunur; '
      '"Dönüşümü tekrar dene" ile kalan satırları tamamlayın.';

  /// Karar notundan dönüşüm hatasını ayıklar.
  static String? extractError(String? decisionNote) {
    final n = decisionNote;
    if (n == null || n.isEmpty) return null;
    final i = n.indexOf(marker);
    if (i < 0) return null;
    final text = n.substring(i + marker.length).trim();
    return text.isEmpty ? null : text;
  }

  /// Karar notunun dönüşüm hatası dışındaki kısmı.
  static String? stripError(String? decisionNote) {
    final n = decisionNote;
    if (n == null || n.isEmpty) return n;
    final i = n.indexOf(marker);
    final text = (i < 0 ? n : n.substring(0, i)).trim();
    return text.isEmpty ? null : text;
  }
}

/// `IdNameDto`.
@immutable
class IdName {
  const IdName({required this.id, required this.name, this.extra});

  factory IdName.fromJson(JsonReader r) => IdName(
    id: r.integer('id'),
    name: r.str('name'),
    extra: r.nonEmpty('extra'),
  );

  final int id;
  final String name;

  /// Ör. "pasif" (pasif temsilci).
  final String? extra;

  bool get isInactive => extra == 'pasif';
}

/// Saha formu liste satırı (`FieldOrderListRowDto`).
@immutable
class FieldFormRow {
  const FieldFormRow({
    required this.id,
    required this.formNumber,
    required this.customerId,
    required this.customerTitle,
    required this.status,
    this.stationTitle,
    this.salesRepresentativeName,
    this.paymentTermDays = 0,
    this.lineCount = 0,
    this.totalLiters = 0,
    this.totalAmount = 0,
    this.totalProfit,
    this.marginPercent,
    this.minProfitPercent,
    this.requiredApprovalLevel,
    this.createdAt,
    this.submittedAt,
    this.decidedAt,
    this.pricingModel = FieldPricingModel.barem,
    this.financeStatus = OrderFinanceStatus.notRequired,
    this.paymentMethodCode,
  });

  factory FieldFormRow.fromJson(JsonReader r) => FieldFormRow(
    id: r.integer('id'),
    formNumber: r.str('formNumber'),
    customerId: r.integer('customerId'),
    customerTitle: r.str('customerTitle'),
    status: r.enumOf('status', FieldOrderFormStatus.fromCode),
    stationTitle: r.nonEmpty('stationTitle'),
    salesRepresentativeName: r.nonEmpty('salesRepresentativeName'),
    paymentTermDays: r.integer('paymentTermDays'),
    lineCount: r.integer('lineCount'),
    totalLiters: r.dec('totalLiters'),
    totalAmount: r.dec('totalAmount'),
    totalProfit: r.decOrNull('totalProfit'),
    marginPercent: r.decOrNull('marginPercent'),
    minProfitPercent: r.decOrNull('minProfitPercent'),
    requiredApprovalLevel: r.intOrNull('requiredApprovalLevel'),
    createdAt: r.dateUtc('createdAt'),
    submittedAt: r.dateUtc('submittedAt'),
    decidedAt: r.dateUtc('decidedAt'),
    pricingModel: FieldPricingModel.fromCode(r.intOrNull('pricingModel')),
    financeStatus: r.enumOf('financeStatus', OrderFinanceStatus.fromCode),
    paymentMethodCode: r.nonEmpty('paymentMethodCode'),
  );

  final int id;
  final String formNumber;
  final int customerId;
  final String customerTitle;
  final FieldOrderFormStatus status;
  final String? stationTitle;
  final String? salesRepresentativeName;
  final int paymentTermDays;
  final int lineCount;
  final double totalLiters;
  final double totalAmount;

  /// Yalnızca maliyet görebilene (aksi halde null).
  final double? totalProfit;
  final double? marginPercent;
  final double? minProfitPercent;
  final int? requiredApprovalLevel;
  final DateTime? createdAt;
  final DateTime? submittedAt;
  final DateTime? decidedAt;
  final FieldPricingModel pricingModel;
  final OrderFinanceStatus financeStatus;
  final String? paymentMethodCode;

  /// Son hareket anı (liste sıralaması ve "x önce").
  DateTime? get lastActivity => decidedAt ?? submittedAt ?? createdAt;
}

/// `field-orders` ve `field-orders/approvals` sayfası (`PagedFieldOrdersResponse`; skip/take).
@immutable
class FieldFormsPage {
  const FieldFormsPage({
    required this.items,
    required this.totalCount,
    this.includeCosts = false,
  });

  factory FieldFormsPage.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final items = r.list('items', FieldFormRow.fromJson);
    return FieldFormsPage(
      items: List.unmodifiable(items),
      totalCount: r.integer('totalCount', items.length),
      includeCosts: r.boolean('includeCosts'),
    );
  }

  final List<FieldFormRow> items;
  final int totalCount;
  final bool includeCosts;
}

/// Form satırı (`FieldOrderLineDto`; maliyet alanları maliyet görmeyene boş).
@immutable
class FieldFormLine {
  const FieldFormLine({
    required this.id,
    required this.productId,
    required this.productName,
    required this.deliveryPointId,
    required this.deliveryPointName,
    required this.quantityLiters,
    required this.proposedUnitPrice,
    this.requestedDeliveryDate,
    this.referenceUnitPrice,
    this.orderId,
    this.orderNumber,
    this.tuprasPriceM3,
    this.tuprasOverridden = false,
    this.pumpPricePerLiter,
    this.bindirimM3,
    this.priceEntryMode = 0,
    this.profitPercent,
    this.invoicePriceM3,
    this.tuprasDiffPercent,
    this.pumpDiscountPercent,
  });

  factory FieldFormLine.fromJson(JsonReader r) => FieldFormLine(
    id: r.integer('id'),
    productId: r.integer('productId'),
    productName: r.str('productName'),
    deliveryPointId: r.integer('deliveryPointId'),
    deliveryPointName: r.str('deliveryPointName'),
    quantityLiters: r.dec('quantityLiters'),
    proposedUnitPrice: r.dec('proposedUnitPrice'),
    requestedDeliveryDate: r.date('requestedDeliveryDate'),
    referenceUnitPrice: r.decOrNull('referenceUnitPrice'),
    orderId: r.intOrNull('orderId'),
    orderNumber: r.nonEmpty('orderNumber'),
    tuprasPriceM3: r.decOrNull('tuprasPriceM3'),
    tuprasOverridden: r.boolean('tuprasOverridden'),
    pumpPricePerLiter: r.decOrNull('pumpPricePerLiter'),
    bindirimM3: r.decOrNull('bindirimM3'),
    priceEntryMode: r.integer('priceEntryMode'),
    profitPercent: r.decOrNull('profitPercent'),
    invoicePriceM3: r.decOrNull('invoicePriceM3'),
    tuprasDiffPercent: r.decOrNull('tuprasDiffPercent'),
    pumpDiscountPercent: r.decOrNull('pumpDiscountPercent'),
  );

  final int id;
  final int productId;
  final String productName;
  final int deliveryPointId;
  final String deliveryPointName;
  final double quantityLiters;
  final double proposedUnitPrice;
  final DateTime? requestedDeliveryDate;
  final double? referenceUnitPrice;
  final int? orderId;
  final String? orderNumber;
  final double? tuprasPriceM3;
  final bool tuprasOverridden;
  final double? pumpPricePerLiter;

  /// Maliyet görmeyene boş.
  final double? bindirimM3;

  /// 0 fiyat (₺/L), 1 kâr %.
  final int priceEntryMode;
  final double? profitPercent;
  final double? invoicePriceM3;
  final double? tuprasDiffPercent;
  final double? pumpDiscountPercent;

  double get amount => quantityLiters * proposedUnitPrice;
}

/// Onay izi satırı (`FieldOrderApprovalDto`).
@immutable
class FieldFormApproval {
  const FieldFormApproval({
    required this.level,
    required this.levelLabel,
    required this.decision,
    required this.decisionLabel,
    this.approverName,
    this.note,
    this.marginPercent,
    this.decidedAt,
  });

  factory FieldFormApproval.fromJson(JsonReader r) => FieldFormApproval(
    level: r.integer('level'),
    levelLabel: r.str('levelLabel'),
    decision: r.integer('decision'),
    decisionLabel: r.str('decisionLabel'),
    approverName: r.nonEmpty('approverName'),
    note: r.nonEmpty('note'),
    marginPercent: r.decOrNull('marginPercent'),
    decidedAt: r.dateUtc('decidedAt'),
  );

  final int level;
  final String levelLabel;

  /// 0 otomatik onay, 1 onay, 2 ret, 3 otomatik ret.
  final int decision;
  final String decisionLabel;
  final String? approverName;
  final String? note;
  final double? marginPercent;
  final DateTime? decidedAt;

  bool get isRejection => decision == 2 || decision == 3;
}

/// Formun barem görünümü (`FieldOrderBaremDto`; maliyet görmeyene yalnızca bant ve ipucu).
@immutable
class FieldBaremView {
  const FieldBaremView({
    required this.bandKey,
    required this.outcomeLabel,
    this.hint = '',
    this.notices = const [],
    this.requiredLevel = 0,
    this.autoReject = false,
    this.costUnknown = false,
    this.outOfRange = false,
    this.chipText,
  });

  factory FieldBaremView.fromJson(JsonReader r) => FieldBaremView(
    bandKey: r.str('bandKey'),
    outcomeLabel: r.str('outcomeLabel'),
    hint: r.str('hint'),
    notices: List.unmodifiable(r.strings('notices')),
    requiredLevel: r.integer('requiredLevel'),
    autoReject: r.boolean('autoReject'),
    costUnknown: r.boolean('costUnknown'),
    outOfRange: r.boolean('outOfRange'),
    chipText: r.nonEmpty('chipText'),
  );

  final String bandKey;
  final String outcomeLabel;
  final String hint;
  final List<String> notices;
  final int requiredLevel;
  final bool autoReject;
  final bool costUnknown;
  final bool outOfRange;

  /// Yalnızca maliyet görebilene.
  final String? chipText;
}

/// Saha formu (`FieldOrderFormDto`).
@immutable
class FieldForm {
  const FieldForm({
    required this.id,
    required this.formNumber,
    required this.concurrencyToken,
    required this.stationId,
    required this.customerId,
    required this.customerTitle,
    required this.status,
    this.statusLabel,
    this.stationTitle,
    this.salesRepresentativeId,
    this.salesRepresentativeName,
    this.createdByName,
    this.paymentTermDays = 0,
    this.note,
    this.createdAt,
    this.submittedAt,
    this.decidedAt,
    this.decidedByName,
    this.decisionNote,
    this.convertedOrderIds = const [],
    this.requiredApprovalLevel,
    this.totalLiters = 0,
    this.totalAmount = 0,
    this.lines = const [],
    this.approvals = const [],
    this.canEdit = false,
    this.canSubmit = false,
    this.canCancel = false,
    this.canDecide = false,
    this.pricingModel = FieldPricingModel.barem,
    this.shipDate,
    this.paymentMethodCode,
    this.paymentMethodName,
    this.paymentDetails = const {},
    this.paymentDueDate,
    this.distributorName,
    this.terminalName,
    this.refineryLocation,
    this.purchaseTermDays,
    this.purchaseTermPercent,
    this.transportKm,
    this.transportPercent,
    this.transportTotal,
    this.isCombinedShipment = false,
    this.combinedTruckLiters,
    this.combinedTruckCost,
    this.collateralRatioPercent,
    this.otherPercent,
    this.minProfitPercent,
    this.strategicExceptionRequested = false,
    this.exceptionJustification,
    this.barem,
    this.financeStatus = OrderFinanceStatus.notRequired,
    this.financeStatusLabel,
    this.financeReasons,
    this.financeApprovalRequestId,
    this.awaitingFinance = false,
    this.salesInvoiceTotal,
    this.formProfitPercent,
    this.netProfit,
  });

  factory FieldForm.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final details = <String, String>{};
    r.map('paymentDetails').forEach((k, v) {
      if (v != null && '$v'.trim().isNotEmpty) details[k] = '$v';
    });
    final sales = r.objOrNull('salesForm');
    return FieldForm(
      id: r.integer('id'),
      formNumber: r.str('formNumber'),
      concurrencyToken: r.str('concurrencyToken'),
      stationId: r.integer('stationId'),
      customerId: r.integer('customerId'),
      customerTitle: r.str('customerTitle'),
      status: r.enumOf('status', FieldOrderFormStatus.fromCode),
      statusLabel: r.nonEmpty('statusLabel'),
      stationTitle: r.nonEmpty('stationTitle'),
      salesRepresentativeId: r.intOrNull('salesRepresentativeId'),
      salesRepresentativeName: r.nonEmpty('salesRepresentativeName'),
      createdByName: r.nonEmpty('createdByName'),
      paymentTermDays: r.integer('paymentTermDays'),
      note: r.nonEmpty('note'),
      createdAt: r.dateUtc('createdAt'),
      submittedAt: r.dateUtc('submittedAt'),
      decidedAt: r.dateUtc('decidedAt'),
      decidedByName: r.nonEmpty('decidedByName'),
      decisionNote: r.nonEmpty('decisionNote'),
      convertedOrderIds: List.unmodifiable(r.ints('convertedOrderIds')),
      requiredApprovalLevel: r.intOrNull('requiredApprovalLevel'),
      totalLiters: r.dec('totalLiters'),
      totalAmount: r.dec('totalAmount'),
      lines: List.unmodifiable(r.list('lines', FieldFormLine.fromJson)),
      approvals: List.unmodifiable(
        r.list('approvals', FieldFormApproval.fromJson),
      ),
      canEdit: r.boolean('canEdit'),
      canSubmit: r.boolean('canSubmit'),
      canCancel: r.boolean('canCancel'),
      canDecide: r.boolean('canDecide'),
      pricingModel: FieldPricingModel.fromCode(r.intOrNull('pricingModel')),
      shipDate: r.date('shipDate'),
      paymentMethodCode: r.nonEmpty('paymentMethodCode'),
      paymentMethodName: r.nonEmpty('paymentMethodName'),
      paymentDetails: Map.unmodifiable(details),
      paymentDueDate: r.date('paymentDueDate'),
      distributorName: r.nonEmpty('distributorName'),
      terminalName: r.nonEmpty('terminalName'),
      refineryLocation: r.nonEmpty('refineryLocation'),
      purchaseTermDays: r.intOrNull('purchaseTermDays'),
      purchaseTermPercent: r.decOrNull('purchaseTermPercent'),
      transportKm: r.decOrNull('transportKm'),
      transportPercent: r.decOrNull('transportPercent'),
      transportTotal: r.decOrNull('transportTotal'),
      isCombinedShipment: r.boolean('isCombinedShipment'),
      combinedTruckLiters: r.decOrNull('combinedTruckLiters'),
      combinedTruckCost: r.decOrNull('combinedTruckCost'),
      collateralRatioPercent: r.decOrNull('collateralRatioPercent'),
      otherPercent: r.decOrNull('otherPercent'),
      minProfitPercent: r.decOrNull('minProfitPercent'),
      strategicExceptionRequested: r.boolean('strategicExceptionRequested'),
      exceptionJustification: r.nonEmpty('exceptionJustification'),
      barem: r.objOrNull('barem') == null
          ? null
          : FieldBaremView.fromJson(r.obj('barem')),
      financeStatus: r.enumOf('financeStatus', OrderFinanceStatus.fromCode),
      financeStatusLabel: r.nonEmpty('financeStatusLabel'),
      financeReasons: r.nonEmpty('financeReasons'),
      financeApprovalRequestId: r.intOrNull('financeApprovalRequestId'),
      awaitingFinance: r.boolean('awaitingFinance'),
      salesInvoiceTotal: sales?.decOrNull('salesInvoiceTotal'),
      formProfitPercent: sales?.decOrNull('formProfitPercent'),
      netProfit: sales?.decOrNull('totalProfit'),
    );
  }

  final int id;
  final String formNumber;
  final String concurrencyToken;
  final int stationId;
  final int customerId;
  final String customerTitle;
  final FieldOrderFormStatus status;
  final String? statusLabel;
  final String? stationTitle;
  final int? salesRepresentativeId;
  final String? salesRepresentativeName;
  final String? createdByName;
  final int paymentTermDays;
  final String? note;
  final DateTime? createdAt;
  final DateTime? submittedAt;
  final DateTime? decidedAt;
  final String? decidedByName;
  final String? decisionNote;
  final List<int> convertedOrderIds;
  final int? requiredApprovalLevel;
  final double totalLiters;
  final double totalAmount;
  final List<FieldFormLine> lines;
  final List<FieldFormApproval> approvals;
  final bool canEdit;
  final bool canSubmit;
  final bool canCancel;
  final bool canDecide;
  final FieldPricingModel pricingModel;
  final DateTime? shipDate;
  final String? paymentMethodCode;
  final String? paymentMethodName;
  final Map<String, String> paymentDetails;
  final DateTime? paymentDueDate;
  final String? distributorName;
  final String? terminalName;
  final String? refineryLocation;

  /// Maliyet girdileri (maliyet görmeyene boş).
  final int? purchaseTermDays;
  final double? purchaseTermPercent;
  final double? transportKm;
  final double? transportPercent;
  final double? transportTotal;
  final bool isCombinedShipment;
  final double? combinedTruckLiters;
  final double? combinedTruckCost;
  final double? collateralRatioPercent;
  final double? otherPercent;
  final double? minProfitPercent;
  final bool strategicExceptionRequested;
  final String? exceptionJustification;
  final FieldBaremView? barem;
  final OrderFinanceStatus financeStatus;
  final String? financeStatusLabel;
  final String? financeReasons;
  final int? financeApprovalRequestId;
  final bool awaitingFinance;

  /// Excel açılımı toplamları (satış faturası herkese; kâr yalnızca maliyet görebilene).
  final double? salesInvoiceTotal;
  final double? formProfitPercent;
  final double? netProfit;

  bool get isClosed =>
      status == FieldOrderFormStatus.rejected ||
      status == FieldOrderFormStatus.cancelled;

  /// Finans durumu gösterilir mi (web `Detail.cshtml` financeVisible).
  bool get financeVisible =>
      financeStatus != OrderFinanceStatus.notRequired &&
      financeStatus != OrderFinanceStatus.unknown &&
      !(isClosed && financeStatus.isAwaitingDecision);

  /// "Finans ek bilgi istedi → Yanıtla" (form hâlâ açıkken ve talep kimliği varken).
  bool get financeInfoOpen =>
      financeStatus == OrderFinanceStatus.infoRequested &&
      financeApprovalRequestId != null &&
      (status == FieldOrderFormStatus.pendingApproval ||
          status == FieldOrderFormStatus.approved);

  /// Dönüşüm hatası metni (web `FieldOrderRules.ConversionErrorText`).
  String? get conversionError {
    final stored = FieldConversion.extractError(decisionNote);
    if (stored != null) return stored;
    if (status == FieldOrderFormStatus.approved && financeStatus.isCleared) {
      return FieldConversion.pendingText;
    }
    return null;
  }

  /// Karar notunun kullanıcıya gösterilecek kısmı.
  String? get decisionText => FieldConversion.stripError(decisionNote);

  String get displayStatus => statusLabel ?? status.label;
}

/// Satırdan açılan siparişin durumu (`FieldOrderLineOrderDto`).
@immutable
class FieldLineOrder {
  const FieldLineOrder({
    required this.lineId,
    required this.orderId,
    required this.orderNumber,
    required this.status,
  });

  factory FieldLineOrder.fromJson(JsonReader r) => FieldLineOrder(
    lineId: r.integer('lineId'),
    orderId: r.integer('orderId'),
    orderNumber: r.str('orderNumber'),
    status: r.enumOf('status', OrderStatus.fromCode),
  );

  final int lineId;
  final int orderId;
  final String orderNumber;
  final OrderStatus status;
}

/// `GET field-orders/{id}` (`FieldOrderDetailDto`).
@immutable
class FieldFormDetail {
  const FieldFormDetail({required this.form, this.orders = const []});

  factory FieldFormDetail.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return FieldFormDetail(
      form: FieldForm.fromJson(r['form']),
      orders: List.unmodifiable(r.list('orders', FieldLineOrder.fromJson)),
    );
  }

  final FieldForm form;
  final List<FieldLineOrder> orders;

  FieldLineOrder? orderOfLine(int lineId) {
    for (final o in orders) {
      if (o.lineId == lineId) return o;
    }
    return null;
  }
}

/// Gönderim / karar / yeniden deneme sonucu (`FieldOrderSubmitResultDto`).
@immutable
class FieldSubmitResult {
  const FieldSubmitResult({
    required this.formId,
    required this.formNumber,
    required this.status,
    this.requiredApprovalLevel,
    this.autoApproved = false,
    this.autoRejected = false,
    this.convertedOrderIds = const [],
    this.message = '',
    this.financeStatus = OrderFinanceStatus.notRequired,
  });

  factory FieldSubmitResult.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return FieldSubmitResult(
      formId: r.integer('formId'),
      formNumber: r.str('formNumber'),
      status: r.enumOf('status', FieldOrderFormStatus.fromCode),
      requiredApprovalLevel: r.intOrNull('requiredApprovalLevel'),
      autoApproved: r.boolean('autoApproved'),
      autoRejected: r.boolean('autoRejected'),
      convertedOrderIds: List.unmodifiable(r.ints('convertedOrderIds')),
      message: r.str('message'),
      financeStatus: r.enumOf('financeStatus', OrderFinanceStatus.fromCode),
    );
  }

  final int formId;
  final String formNumber;
  final FieldOrderFormStatus status;
  final int? requiredApprovalLevel;
  final bool autoApproved;
  final bool autoRejected;
  final List<int> convertedOrderIds;
  final String message;
  final OrderFinanceStatus financeStatus;
}

// ═══════════════════════════════════════════════════════════════════ Seçenekler (options-v2)

/// Kod + ad (`MobileCodeLabelDto`).
@immutable
class CodeLabel {
  const CodeLabel(this.code, this.label);

  factory CodeLabel.fromJson(JsonReader r) =>
      CodeLabel(r.str('code'), r.str('label', r.str('code')));

  final String code;
  final String label;
}

/// Ürün seçeneği (`FieldOptionsProductDto`).
@immutable
class FieldProductOption {
  const FieldProductOption({
    required this.id,
    required this.code,
    required this.name,
    this.suggestedUnitPrice,
    this.suggestedSource,
    this.suggestedSourceLabel,
    this.lastUnitPrice,
    this.pumpPricePerLiter,
    this.tuprasPricesM3 = const {},
    this.tuprasPriceDates = const {},
  });

  factory FieldProductOption.fromJson(JsonReader r) {
    final prices = <String, double>{};
    r.map('tuprasPricesM3').forEach((k, v) {
      final d = JsonReader.toDouble(v);
      if (d != null) prices[k] = d;
    });
    final dates = <String, DateTime>{};
    r.map('tuprasPriceDates').forEach((k, v) {
      final d = TrTime.parseDate(v?.toString());
      if (d != null) dates[k] = d;
    });
    return FieldProductOption(
      id: r.integer('id'),
      code: r.str('code'),
      name: r.str('name'),
      suggestedUnitPrice: r.decOrNull('suggestedUnitPrice'),
      suggestedSource: r.nonEmpty('suggestedSource'),
      suggestedSourceLabel: r.nonEmpty('suggestedSourceLabel'),
      lastUnitPrice: r.decOrNull('lastUnitPrice'),
      pumpPricePerLiter: r.decOrNull('pumpPricePerLiter'),
      tuprasPricesM3: Map.unmodifiable(prices),
      tuprasPriceDates: Map.unmodifiable(dates),
    );
  }

  final int id;
  final String code;
  final String name;
  final double? suggestedUnitPrice;
  final String? suggestedSource;
  final String? suggestedSourceLabel;
  final double? lastUnitPrice;
  final double? pumpPricePerLiter;

  /// Lokasyon kodu → Tüpraş ₺/m³ (KDV dahil).
  final Map<String, double> tuprasPricesM3;

  /// Lokasyon kodu → referans fiyatın günü (Türkiye gece yarısı).
  final Map<String, DateTime> tuprasPriceDates;

  /// Referans fiyat bugünden eski mi ("Bugünün Tüpraş fiyatı girilmedi").
  bool isTuprasStale(String? location, {DateTime? now}) {
    if (location == null) return false;
    final day = tuprasPriceDates[location];
    if (day == null) return false;
    return TrTime.dayDiff(day, now ?? TrTime.now()) > 0;
  }
}

/// Teslimat noktası seçeneği (`FieldOptionsPointDto`).
@immutable
class FieldPointOption {
  const FieldPointOption({
    required this.id,
    required this.name,
    this.city,
    this.district,
    this.address,
    this.place = '',
  });

  factory FieldPointOption.fromJson(JsonReader r) => FieldPointOption(
    id: r.integer('id'),
    name: r.str('name'),
    city: r.nonEmpty('city'),
    district: r.nonEmpty('district'),
    address: r.nonEmpty('address'),
    place: r.str('place'),
  );

  final int id;
  final String name;
  final String? city;
  final String? district;
  final String? address;

  /// "İlçe / İl".
  final String place;
}

/// Carinin bayideki limit durumu (`FieldOrderLimitStatusDto`).
@immutable
class FieldLimitStatus {
  const FieldLimitStatus({
    required this.state,
    this.limitType,
    this.limitPeriod,
    this.limitAmount,
    this.used = 0,
    this.requested = 0,
    this.available,
    this.unit = 'TL',
    this.message = '',
  });

  factory FieldLimitStatus.fromJson(JsonReader r) => FieldLimitStatus(
    state: r.str('state', 'unlimited'),
    limitType: r.nonEmpty('limitType'),
    limitPeriod: r.nonEmpty('limitPeriod'),
    limitAmount: r.decOrNull('limitAmount'),
    used: r.dec('used'),
    requested: r.dec('requested'),
    available: r.decOrNull('available'),
    unit: r.str('unit', 'TL'),
    message: r.str('message'),
  );

  /// none · unlimited · ok · exceeded · invalid.
  final String state;
  final String? limitType;
  final String? limitPeriod;
  final double? limitAmount;
  final double used;
  final double requested;
  final double? available;
  final String unit;
  final String message;

  bool get isBlocking =>
      state == 'exceeded' || state == 'invalid' || state == 'none';
  bool get isUnlimited => state == 'unlimited';

  /// Mevcut kullanım oranı (0..1+); limitsiz ise null.
  double? get usedRatio {
    final a = limitAmount;
    if (a == null || a <= 0) return null;
    return used / a;
  }
}

/// Ödeme yöntemi alanı (`PaymentFieldDto`).
@immutable
class PaymentFieldSpec {
  const PaymentFieldSpec({
    required this.key,
    required this.label,
    this.type = 'text',
    this.required = false,
    this.maxLength,
    this.options = const [],
    this.placeholder,
    this.choices = const [],
  });

  factory PaymentFieldSpec.fromJson(JsonReader r) => PaymentFieldSpec(
    key: r.str('key'),
    label: r.str('label'),
    type: r.str('type', 'text'),
    required: r.boolean('required'),
    maxLength: r.intOrNull('maxLength'),
    options: List.unmodifiable(r.strings('options')),
    placeholder: r.nonEmpty('placeholder'),
    choices: List.unmodifiable(
      r.list(
        'choices',
        (c) => (value: c.str('value'), label: c.str('label', c.str('value'))),
      ),
    ),
  );

  final String key;
  final String label;

  /// text | number | money | date | select | textarea.
  final String type;
  final bool required;
  final int? maxLength;
  final List<String> options;
  final String? placeholder;
  final List<({String value, String label})> choices;
}

/// Ödeme yöntemi kartı (`PaymentMethodOptionDto`).
@immutable
class PaymentMethodChoice {
  const PaymentMethodChoice({
    required this.code,
    required this.name,
    this.shortName,
    this.isDeferred = false,
    this.requiresFinance = false,
    this.documentKind,
    this.documentRequired = false,
    this.minTermDays = 0,
    this.maxTermDays = 0,
    this.defaultTermDays,
    this.fields = const [],
    this.hint,
  });

  factory PaymentMethodChoice.fromJson(JsonReader r) => PaymentMethodChoice(
    code: r.str('code'),
    name: r.str('name'),
    shortName: r.nonEmpty('shortName'),
    isDeferred: r.boolean('isDeferred'),
    requiresFinance: r.boolean('requiresFinance'),
    documentKind: r.intOrNull('documentKind') == null
        ? null
        : AttachmentKind.fromCode(r.intOrNull('documentKind')),
    documentRequired: r.boolean('documentRequired'),
    minTermDays: r.integer('minTermDays'),
    maxTermDays: r.integer('maxTermDays'),
    defaultTermDays: r.intOrNull('defaultTermDays'),
    fields: List.unmodifiable(r.list('fields', PaymentFieldSpec.fromJson)),
    hint: r.nonEmpty('hint'),
  );

  final String code;
  final String name;
  final String? shortName;
  final bool isDeferred;
  final bool requiresFinance;
  final AttachmentKind? documentKind;
  final bool documentRequired;
  final int minTermDays;
  final int maxTermDays;
  final int? defaultTermDays;
  final List<PaymentFieldSpec> fields;
  final String? hint;
}

/// Ödeme seçici verisi (`PaymentOptionsDto`).
@immutable
class PaymentChoices {
  const PaymentChoices({
    this.enabled = false,
    this.defaultMethodCode,
    this.methods = const [],
    this.blockedReason,
  });

  factory PaymentChoices.fromJson(JsonReader r) => PaymentChoices(
    enabled: r.boolean('enabled'),
    defaultMethodCode: r.nonEmpty('defaultMethodCode'),
    methods: List.unmodifiable(r.list('methods', PaymentMethodChoice.fromJson)),
    blockedReason: r.nonEmpty('blockedReason'),
  );

  final bool enabled;
  final String? defaultMethodCode;
  final List<PaymentMethodChoice> methods;
  final String? blockedReason;

  PaymentMethodChoice? method(String? code) {
    if (code == null) return null;
    for (final m in methods) {
      if (m.code == code) return m;
    }
    return null;
  }
}

/// Maliyet girdileri (`FieldOptionsCostInputsDto`; yalnızca maliyet görebilene).
@immutable
class FieldCostInputs {
  const FieldCostInputs({
    this.profitPercentEntry = true,
    this.defaultBindirimM3 = const {},
  });

  factory FieldCostInputs.fromJson(JsonReader r) {
    final map = <int, double>{};
    r.map('defaultBindirimM3').forEach((k, v) {
      final id = int.tryParse(k);
      final d = JsonReader.toDouble(v);
      if (id != null && d != null) map[id] = d;
    });
    return FieldCostInputs(
      profitPercentEntry: r.boolean('profitPercentEntry', true),
      defaultBindirimM3: Map.unmodifiable(map),
    );
  }

  final bool profitPercentEntry;
  final Map<int, double> defaultBindirimM3;
}

/// `GET field-orders/options-v2` (`FieldOrderOptionsV2Dto`).
@immutable
class FieldOptions {
  const FieldOptions({
    required this.stationId,
    required this.customerId,
    required this.customerTitle,
    required this.limit,
    this.showCosts = false,
    this.defaultDate,
    this.products = const [],
    this.points = const [],
    this.model = FieldPricingModel.barem,
    this.city,
    this.distributor,
    this.terminal,
    this.location,
    this.locations = const [],
    this.vatRatePercent = 20,
    this.pricesIncludeVat = true,
    this.collateralPct = 0,
    this.strategic = false,
    this.maxPaymentTermDays = 365,
    this.payment,
    this.costInputs,
  });

  factory FieldOptions.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return FieldOptions(
      showCosts: r.boolean('showCosts'),
      stationId: r.integer('stationId'),
      customerId: r.integer('customerId'),
      customerTitle: r.str('customerTitle'),
      defaultDate: r.date('defaultDate'),
      products: List.unmodifiable(
        r.list('products', FieldProductOption.fromJson),
      ),
      points: List.unmodifiable(r.list('points', FieldPointOption.fromJson)),
      limit: FieldLimitStatus.fromJson(r.obj('limit')),
      model: FieldPricingModel.fromCode(r.intOrNull('model')),
      city: r.nonEmpty('city'),
      distributor: r.nonEmpty('distributor'),
      terminal: r.nonEmpty('terminal'),
      location: r.nonEmpty('location'),
      locations: List.unmodifiable(r.list('locations', CodeLabel.fromJson)),
      vatRatePercent: r.dec('vatRatePercent', 20),
      pricesIncludeVat: r.boolean('pricesIncludeVat', true),
      collateralPct: r.dec('collateralPct'),
      strategic: r.boolean('strategic'),
      maxPaymentTermDays: r.integer('maxPaymentTermDays', 365),
      payment: r.objOrNull('payment') == null
          ? null
          : PaymentChoices.fromJson(r.obj('payment')),
      costInputs: r.objOrNull('costInputs') == null
          ? null
          : FieldCostInputs.fromJson(r.obj('costInputs')),
    );
  }

  final bool showCosts;
  final int stationId;
  final int customerId;
  final String customerTitle;
  final DateTime? defaultDate;
  final List<FieldProductOption> products;
  final List<FieldPointOption> points;
  final FieldLimitStatus limit;
  final FieldPricingModel model;
  final String? city;
  final String? distributor;
  final String? terminal;
  final String? location;
  final List<CodeLabel> locations;
  final double vatRatePercent;
  final bool pricesIncludeVat;
  final double collateralPct;
  final bool strategic;
  final int maxPaymentTermDays;
  final PaymentChoices? payment;
  final FieldCostInputs? costInputs;

  FieldProductOption? product(int? id) {
    if (id == null) return null;
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  FieldPointOption? point(int? id) {
    if (id == null) return null;
    for (final p in points) {
      if (p.id == id) return p;
    }
    return null;
  }

  String locationLabel(String? code) {
    if (code == null) return '—';
    for (final l in locations) {
      if (l.code == code) return l.label;
    }
    return code;
  }
}

/// Dağıtıcı / terminal önerisi (`FieldSupplyOptionDto`).
@immutable
class FieldSupplyOption {
  const FieldSupplyOption({required this.kind, required this.name});

  factory FieldSupplyOption.fromJson(JsonReader r) =>
      FieldSupplyOption(kind: r.str('kind'), name: r.str('name'));

  /// distributor · terminal.
  final String kind;
  final String name;

  bool get isDistributor => kind == 'distributor';
}

// ═══════════════════════════════════════════════════════════════════ Önizleme (preview-v2)

/// Renk bandı (`FieldPreviewBandDto`).
@immutable
class FieldBand {
  const FieldBand({
    required this.key,
    required this.label,
    this.tone = 'neutral',
    this.hint = '',
  });

  factory FieldBand.fromJson(JsonReader r) => FieldBand(
    key: r.str('key'),
    label: r.str('label'),
    tone: r.str('tone', 'neutral'),
    hint: r.str('hint'),
  );

  final String key;
  final String label;
  final String tone;
  final String hint;

  /// Otomatik ret: gönderilirse form reddedilir.
  bool get isReject => key == 'reject';

  @override
  bool operator ==(Object other) =>
      other is FieldBand && other.key == key && other.label == label;

  @override
  int get hashCode => Object.hash(key, label);
}

/// Önizleme satırı (`FieldPreviewLineDto`).
@immutable
class FieldPreviewLine {
  const FieldPreviewLine({
    required this.key,
    this.productId = 0,
    this.productName,
    this.liters = 0,
    this.unitPriceL,
    this.unitPriceM3,
    this.amount,
    this.costUnknown = false,
    this.tuprasM3,
    this.pumpM3,
    this.invoiceExVatM3,
    this.invoicePerLiter,
    this.invoiceExVatPerLiter,
    this.salesInvoice,
    this.tuprasDiffM3,
    this.tuprasDiffPercent,
    this.pumpMinusTuprasM3,
    this.pumpMinusTuprasPercent,
    this.pumpDiscountM3,
    this.pumpDiscountPercent,
    this.pumpAbove = false,
    this.profitPercent,
    this.netProfit,
    this.costM3,
    this.loss = false,
  });

  factory FieldPreviewLine.fromJson(JsonReader r) {
    final cost = r.objOrNull('cost');
    return FieldPreviewLine(
      key: r.integer('key'),
      productId: r.integer('productId'),
      productName: r.nonEmpty('productName'),
      liters: r.dec('liters'),
      unitPriceL: r.decOrNull('unitPriceL'),
      unitPriceM3: r.decOrNull('unitPriceM3'),
      amount: r.decOrNull('amount'),
      costUnknown: r.boolean('costUnknown'),
      tuprasM3: r.decOrNull('tuprasM3'),
      pumpM3: r.decOrNull('pumpM3'),
      invoiceExVatM3: r.decOrNull('invoiceExVatM3'),
      invoicePerLiter: r.decOrNull('invoicePerLiter'),
      invoiceExVatPerLiter: r.decOrNull('invoiceExVatPerLiter'),
      salesInvoice: r.decOrNull('salesInvoice'),
      tuprasDiffM3: r.decOrNull('tuprasDiffM3'),
      tuprasDiffPercent: r.decOrNull('tuprasDiffPercent'),
      pumpMinusTuprasM3: r.decOrNull('pumpMinusTuprasM3'),
      pumpMinusTuprasPercent: r.decOrNull('pumpMinusTuprasPercent'),
      pumpDiscountM3: r.decOrNull('pumpDiscountM3'),
      pumpDiscountPercent: r.decOrNull('pumpDiscountPercent'),
      pumpAbove: r.boolean('pumpAbove'),
      profitPercent: cost?.decOrNull('profitPercent'),
      netProfit: cost?.decOrNull('netProfit'),
      costM3: cost?.decOrNull('costM3'),
      loss: cost?.boolean('loss') ?? false,
    );
  }

  /// İstekteki satır sırası (0'dan).
  final int key;
  final int productId;
  final String? productName;
  final double liters;
  final double? unitPriceL;
  final double? unitPriceM3;
  final double? amount;
  final bool costUnknown;
  final double? tuprasM3;
  final double? pumpM3;
  final double? invoiceExVatM3;
  final double? invoicePerLiter;
  final double? invoiceExVatPerLiter;
  final double? salesInvoice;
  final double? tuprasDiffM3;
  final double? tuprasDiffPercent;
  final double? pumpMinusTuprasM3;
  final double? pumpMinusTuprasPercent;
  final double? pumpDiscountM3;
  final double? pumpDiscountPercent;
  final bool pumpAbove;

  /// Yalnızca maliyet görebilene (`cost`); aksi halde null.
  final double? profitPercent;
  final double? netProfit;
  final double? costM3;
  final bool loss;
}

/// `POST field-orders/preview-v2` (`FieldOrderPreviewV2Dto`).
@immutable
class FieldPreview {
  const FieldPreview({
    required this.band,
    this.showCosts = false,
    this.model = FieldPricingModel.barem,
    this.notices = const [],
    this.totalLiters = 0,
    this.totalM3 = 0,
    this.totalAmount,
    this.salesInvoice,
    this.lineCount = 0,
    this.lines = const [],
    this.limitState,
    this.limitMessage,
    this.limitBlocking = false,
    this.limitUnit = 'TL',
    this.limitUsedPct,
    this.dueDate,
    this.collateralPct,
    this.financeRequired = false,
    this.financeReasons = const [],
    this.financeBlocked,
    this.overriddenLines = const [],
    this.chip,
    this.reason,
    this.formProfitPercent,
    this.netProfit,
    this.marginPercent,
  });

  factory FieldPreview.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final totals = r.obj('totals');
    final limit = r.objOrNull('limit');
    final finance = r.obj('finance');
    final form = r.objOrNull('form');
    return FieldPreview(
      showCosts: r.boolean('showCosts'),
      model: FieldPricingModel.fromCode(r.intOrNull('model')),
      band: FieldBand.fromJson(r.obj('band')),
      notices: List.unmodifiable(r.strings('notices')),
      totalLiters: totals.dec('liters'),
      totalM3: totals.dec('m3'),
      totalAmount: totals.decOrNull('amount'),
      salesInvoice: totals.decOrNull('salesInvoice'),
      lineCount: totals.integer('lines'),
      lines: List.unmodifiable(r.list('lines', FieldPreviewLine.fromJson)),
      limitState: limit?.nonEmpty('state'),
      limitMessage: limit?.nonEmpty('message'),
      limitBlocking: limit?.boolean('blocking') ?? false,
      limitUnit: limit?.str('unit', 'TL') ?? 'TL',
      limitUsedPct: limit?.decOrNull('usedPct'),
      dueDate: r.date('dueDate'),
      collateralPct: r.decOrNull('collateralPct'),
      financeRequired: finance.boolean('required'),
      financeReasons: List.unmodifiable(finance.strings('reasons')),
      financeBlocked: finance.nonEmpty('blocked'),
      overriddenLines: List.unmodifiable(r.ints('overriddenLines')),
      chip: r.nonEmpty('chip'),
      reason: r.nonEmpty('reason'),
      formProfitPercent: form?.decOrNull('formProfitPercent'),
      netProfit: form?.decOrNull('netProfit'),
      marginPercent: form?.decOrNull('marginPercent'),
    );
  }

  final bool showCosts;
  final FieldPricingModel model;
  final FieldBand band;
  final List<String> notices;
  final double totalLiters;
  final double totalM3;
  final double? totalAmount;
  final double? salesInvoice;
  final int lineCount;
  final List<FieldPreviewLine> lines;
  final String? limitState;
  final String? limitMessage;
  final bool limitBlocking;
  final String limitUnit;

  /// (Kullanılan + bu form) ÷ limit × 100 (en çok 100); limitsiz ise null.
  final double? limitUsedPct;
  final DateTime? dueDate;
  final double? collateralPct;
  final bool financeRequired;
  final List<String> financeReasons;
  final String? financeBlocked;

  /// Tüpraş fiyatı elle değiştirilmiş satır numaraları (1'den).
  final List<int> overriddenLines;

  /// Yalnızca maliyet görebilene.
  final String? chip;
  final String? reason;
  final double? formProfitPercent;
  final double? netProfit;
  final double? marginPercent;

  /// Bant ipucu (sunucu ipucunun sonuna uyarıları ekler; burada uyarılar ayrı gösterildiği için ayıklanır).
  String get hint {
    var h = band.hint;
    for (final n in notices) {
      h = h.replaceAll(n, '');
    }
    return h.trim();
  }

  /// Gönderimi engelleyen durum metni (limit ya da finans).
  String? get blockingReason =>
      financeBlocked ?? (limitBlocking ? limitMessage : null);

  FieldPreviewLine? line(int key) {
    for (final l in lines) {
      if (l.key == key) return l;
    }
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════════ Portföy

/// Portföy satırı (`SalesRepPortfolioRowDto`).
@immutable
class PortfolioRow {
  const PortfolioRow({
    required this.customerId,
    required this.customerTitle,
    this.customerCode = '',
    this.city,
    this.assignedAt,
  });

  factory PortfolioRow.fromJson(JsonReader r) => PortfolioRow(
    customerId: r.integer('customerId'),
    customerTitle: r.str('customerTitle'),
    customerCode: r.str('customerCode'),
    city: r.nonEmpty('city'),
    assignedAt: r.dateUtc('assignedAt'),
  );

  final int customerId;
  final String customerTitle;
  final String customerCode;
  final String? city;
  final DateTime? assignedAt;

  JsonMap toJson() => {
    'customerId': customerId,
    'customerTitle': customerTitle,
    'customerCode': customerCode,
    'city': city,
    'assignedAt': assignedAt?.toIso8601String(),
  };
}

/// skip/take sayfası (`PagedResult<T>`; `me/portfolio`).
@immutable
class SkipTakePage<T> {
  const SkipTakePage({required this.items, required this.totalCount});

  factory SkipTakePage.fromJson(Object? json, T Function(JsonReader r) item) {
    final r = JsonReader.of(json);
    final items = r.list('items', item);
    return SkipTakePage(
      items: List.unmodifiable(items),
      totalCount: r.integer('totalCount', items.length),
    );
  }

  final List<T> items;
  final int totalCount;
}

// ═══════════════════════════════════════════════════════════════════ Cari kartı (B4 özeti)

/// `GET bayi/customers/{id}/summary` içinden saha kartında kullanılan alanlar (`CustomerSummaryDto`).
@immutable
class FieldCustomerSummary {
  const FieldCustomerSummary({
    required this.customerId,
    required this.title,
    this.code,
    this.city,
    this.district,
    this.financeLabel,
    this.canOrder = true,
    this.blockReason,
    this.limitUsagePct,
    this.limitTone = 'none',
    this.limitAmount,
    this.limitUsed,
    this.limitUnit = 'TL',
    this.limitPeriodLabel,
    this.contacts = const [],
    this.openForms = const [],
    this.canCreateFieldForm = false,
    this.isActive = true,
  });

  factory FieldCustomerSummary.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final finance = r.obj('finance');
    final limit = r.objOrNull('limit');
    return FieldCustomerSummary(
      customerId: r.integer('customerId'),
      title: r.str('title'),
      code: r.nonEmpty('code'),
      city: r.nonEmpty('city'),
      district: r.nonEmpty('district'),
      financeLabel: finance.nonEmpty('label'),
      canOrder: finance.boolean('canOrder', true),
      blockReason: finance.nonEmpty('blockReason'),
      limitUsagePct: limit?.decOrNull('usagePct'),
      limitTone: limit?.str('tone', 'none') ?? 'none',
      limitAmount: limit?.decOrNull('amount'),
      limitUsed: limit?.decOrNull('used'),
      limitUnit: limit?.str('unit', 'TL') ?? 'TL',
      limitPeriodLabel: limit?.nonEmpty('periodLabel'),
      contacts: List.unmodifiable(
        r.list(
          'contacts',
          (c) => (
            name: c.str('name'),
            role: c.nonEmpty('role'),
            phone: c.nonEmpty('phone'),
          ),
        ),
      ),
      openForms: List.unmodifiable(
        r.list(
          'openForms',
          (f) => (
            id: f.integer('id'),
            formNumber: f.str('formNumber'),
            status: f.enumOf('status', FieldOrderFormStatus.fromCode),
            totalLiters: f.dec('totalLiters'),
          ),
        ),
      ),
      canCreateFieldForm: r.obj('actions').boolean('canCreateFieldForm'),
      isActive: r.boolean('isActive', true),
    );
  }

  final int customerId;
  final String title;
  final String? code;
  final String? city;
  final String? district;
  final String? financeLabel;
  final bool canOrder;
  final String? blockReason;
  final double? limitUsagePct;
  final String limitTone;
  final double? limitAmount;
  final double? limitUsed;
  final String limitUnit;
  final String? limitPeriodLabel;
  final List<({String name, String? role, String? phone})> contacts;
  final List<
    ({
      int id,
      String formNumber,
      FieldOrderFormStatus status,
      double totalLiters,
    })
  >
  openForms;
  final bool canCreateFieldForm;
  final bool isActive;
}

// ═══════════════════════════════════════════════════════════════════ Belge (PDF)

/// Belge tarafı (`DocPartyDto`).
@immutable
class FieldDocParty {
  const FieldDocParty({
    required this.title,
    this.code,
    this.taxNumber,
    this.taxOffice,
    this.address,
    this.district,
    this.city,
    this.phone,
    this.email,
  });

  factory FieldDocParty.fromJson(JsonReader r) => FieldDocParty(
    title: r.nonEmpty('legalTitle') ?? r.str('title'),
    code: r.nonEmpty('code'),
    taxNumber: r.nonEmpty('taxNumber'),
    taxOffice: r.nonEmpty('taxOffice'),
    address: r.nonEmpty('address'),
    district: r.nonEmpty('district'),
    city: r.nonEmpty('city'),
    phone: r.nonEmpty('phone'),
    email: r.nonEmpty('email'),
  );

  final String title;
  final String? code;
  final String? taxNumber;
  final String? taxOffice;
  final String? address;
  final String? district;
  final String? city;
  final String? phone;
  final String? email;

  String get place => [?district, ?city].join(' / ');
}

/// Belge satırı (`FieldOrderDocumentLineDto`).
@immutable
class FieldDocLine {
  const FieldDocLine({
    required this.no,
    required this.productName,
    required this.deliveryPointName,
    required this.quantityLiters,
    required this.unitPrice,
    required this.amount,
    this.productCode = '',
    this.deliveryAddress,
    this.requestedDeliveryDate,
    this.orderNumber,
  });

  factory FieldDocLine.fromJson(JsonReader r) => FieldDocLine(
    no: r.integer('no'),
    productCode: r.str('productCode'),
    productName: r.str('productName'),
    deliveryPointName: r.str('deliveryPointName'),
    deliveryAddress: r.nonEmpty('deliveryAddress'),
    requestedDeliveryDate: r.date('requestedDeliveryDate'),
    quantityLiters: r.dec('quantityLiters'),
    unitPrice: r.dec('unitPrice'),
    amount: r.dec('amount'),
    orderNumber: r.nonEmpty('orderNumber'),
  );

  final int no;
  final String productCode;
  final String productName;
  final String deliveryPointName;
  final String? deliveryAddress;
  final DateTime? requestedDeliveryDate;
  final double quantityLiters;
  final double unitPrice;
  final double amount;
  final String? orderNumber;
}

/// İç belge satırı (`FieldOrderInternalLineDto`; maliyet içerir, müşteriye verilmez).
@immutable
class FieldDocInternalLine {
  const FieldDocInternalLine({
    required this.no,
    required this.productName,
    required this.quantityLiters,
    this.tuprasOverridden = false,
    this.bindirimM3,
    this.tuprasPriceM3,
    this.costM3,
    this.invoicePriceM3,
    this.profitPercent,
    this.profitTotal,
  });

  factory FieldDocInternalLine.fromJson(JsonReader r) {
    final res = r.obj('result');
    return FieldDocInternalLine(
      no: r.integer('no'),
      productName: r.str('productName'),
      quantityLiters: r.dec('quantityLiters'),
      tuprasOverridden: r.boolean('tuprasOverridden'),
      bindirimM3: r.decOrNull('bindirimM3'),
      tuprasPriceM3: res.decOrNull('tuprasPriceM3'),
      costM3: res.decOrNull('costM3'),
      invoicePriceM3: res.decOrNull('invoicePriceM3'),
      profitPercent: res.decOrNull('profitPercent'),
      profitTotal: res.decOrNull('profitTotal'),
    );
  }

  final int no;
  final String productName;
  final double quantityLiters;
  final bool tuprasOverridden;
  final double? bindirimM3;
  final double? tuprasPriceM3;
  final double? costM3;
  final double? invoicePriceM3;
  final double? profitPercent;
  final double? profitTotal;
}

/// İç belge açılımı (`FieldOrderInternalDocumentDto`).
@immutable
class FieldDocInternal {
  const FieldDocInternal({
    this.refineryLocationLabel,
    this.termDays = 0,
    this.purchaseTermDays,
    this.purchaseTermPercent,
    this.valorPercent,
    this.otherPercent,
    this.collateralRatioPercent,
    this.vatRatePercent = 20,
    this.transportTotal,
    this.lines = const [],
    this.formProfitPercent,
    this.profitTotalVatIncl,
    this.netProfit,
    this.baremOutcome,
    this.baremChip,
    this.financeStatusLabel,
    this.financeReasons,
    this.approvals = const [],
  });

  factory FieldDocInternal.fromJson(JsonReader r) {
    final totals = r.obj('totals');
    final barem = r.objOrNull('barem');
    return FieldDocInternal(
      refineryLocationLabel:
          r.nonEmpty('refineryLocationLabel') ?? r.nonEmpty('refineryLocation'),
      termDays: r.integer('termDays'),
      purchaseTermDays: r.intOrNull('purchaseTermDays'),
      purchaseTermPercent: r.decOrNull('purchaseTermPercent'),
      valorPercent: r.decOrNull('valorPercent'),
      otherPercent: r.decOrNull('otherPercent'),
      collateralRatioPercent: r.decOrNull('collateralRatioPercent'),
      vatRatePercent: r.dec('vatRatePercent', 20),
      transportTotal: r.decOrNull('transportTotal'),
      lines: List.unmodifiable(r.list('lines', FieldDocInternalLine.fromJson)),
      formProfitPercent: totals.decOrNull('formProfitPercent'),
      profitTotalVatIncl: totals.decOrNull('profitTotalVatIncl'),
      netProfit: totals.decOrNull('totalProfit'),
      baremOutcome: barem?.nonEmpty('outcomeLabel'),
      baremChip: barem?.nonEmpty('chipText'),
      financeStatusLabel: r.nonEmpty('financeStatusLabel'),
      financeReasons: r.nonEmpty('financeReasons'),
      approvals: List.unmodifiable(
        r.list('approvals', FieldFormApproval.fromJson),
      ),
    );
  }

  final String? refineryLocationLabel;
  final int termDays;
  final int? purchaseTermDays;
  final double? purchaseTermPercent;
  final double? valorPercent;
  final double? otherPercent;
  final double? collateralRatioPercent;
  final double vatRatePercent;
  final double? transportTotal;
  final List<FieldDocInternalLine> lines;
  final double? formProfitPercent;
  final double? profitTotalVatIncl;
  final double? netProfit;
  final String? baremOutcome;
  final String? baremChip;
  final String? financeStatusLabel;
  final String? financeReasons;
  final List<FieldFormApproval> approvals;
}

/// Yazdırılabilir saha sipariş formu (`FieldOrderDocumentDto`).
@immutable
class FieldDocument {
  const FieldDocument({
    required this.id,
    required this.formNumber,
    required this.statusLabel,
    required this.station,
    required this.customer,
    this.createdAt,
    this.submittedAt,
    this.decidedAt,
    this.paymentTermDays = 0,
    this.note,
    this.salesRepresentativeName,
    this.createdByName,
    this.approvedByName,
    this.approvalKind,
    this.lines = const [],
    this.totalLiters = 0,
    this.totalAmount = 0,
    this.printedBy = '',
    this.shipDate,
    this.paymentMethodName = '',
    this.paymentDueDate,
    this.distributorName,
    this.terminalName,
    this.internal,
  });

  factory FieldDocument.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return FieldDocument(
      id: r.integer('id'),
      formNumber: r.str('formNumber'),
      statusLabel: r.str('statusLabel'),
      station: FieldDocParty.fromJson(r.obj('station')),
      customer: FieldDocParty.fromJson(r.obj('customer')),
      createdAt: r.dateTr('createdAtLocal'),
      submittedAt: r.dateTr('submittedAtLocal'),
      decidedAt: r.dateTr('decidedAtLocal'),
      paymentTermDays: r.integer('paymentTermDays'),
      note: r.nonEmpty('note'),
      salesRepresentativeName: r.nonEmpty('salesRepresentativeName'),
      createdByName: r.nonEmpty('createdByName'),
      approvedByName: r.nonEmpty('approvedByName'),
      approvalKind: r.nonEmpty('approvalKind'),
      lines: List.unmodifiable(r.list('lines', FieldDocLine.fromJson)),
      totalLiters: r.dec('totalLiters'),
      totalAmount: r.dec('totalAmount'),
      printedBy: r.str('printedBy'),
      shipDate: r.date('shipDate'),
      paymentMethodName: r.str('paymentMethodName', 'Belirtilmemiş'),
      paymentDueDate: r.date('paymentDueDate'),
      distributorName: r.nonEmpty('distributorName'),
      terminalName: r.nonEmpty('terminalName'),
      internal: r.objOrNull('internal') == null
          ? null
          : FieldDocInternal.fromJson(r.obj('internal')),
    );
  }

  final int id;
  final String formNumber;
  final String statusLabel;
  final FieldDocParty station;
  final FieldDocParty customer;
  final DateTime? createdAt;
  final DateTime? submittedAt;
  final DateTime? decidedAt;
  final int paymentTermDays;
  final String? note;
  final String? salesRepresentativeName;
  final String? createdByName;
  final String? approvedByName;
  final String? approvalKind;
  final List<FieldDocLine> lines;
  final double totalLiters;
  final double totalAmount;
  final String printedBy;
  final DateTime? shipDate;
  final String paymentMethodName;
  final DateTime? paymentDueDate;
  final String? distributorName;
  final String? terminalName;
  final FieldDocInternal? internal;

  bool get isInternal => internal != null;
}

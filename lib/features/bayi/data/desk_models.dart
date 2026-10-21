import 'package:flutter/foundation.dart';

import '../../../core/models/models.dart';
import '../../../core/utils/turkish_text.dart';

/// Masa görünümü (`BayiQuoteDeskKeys`).
enum DeskView {
  all('all', 'Tümü'),
  awaitingQuote('new', 'Yeni'),
  revision('revision', 'Revize'),
  expiringSoon('expiringSoon', 'Süresi yaklaşan');

  const DeskView(this.key, this.label);
  final String key;
  final String label;

  static DeskView fromKey(String? key) {
    final k = key?.trim().asciiLower;
    for (final v in values) {
      if (v.key.asciiLower == k) return v;
    }
    return all;
  }
}

/// Masa sıralaması.
enum DeskSort {
  expiry('expiry', 'Süre sonu yakın'),
  delivery('delivery', 'Teslim günü yakın'),
  newest('newest', 'En yeni');

  const DeskSort(this.key, this.label);
  final String key;
  final String label;

  static DeskSort fromKey(String? key) {
    final k = key?.trim().asciiLower;
    for (final v in values) {
      if (v.key.asciiLower == k) return v;
    }
    return expiry;
  }
}

/// Masa başlığı: süre dolumu, finans bekleyenler ve teklif engeli.
@immutable
class DeskHeader {
  const DeskHeader({
    this.expiryEnabled = false,
    this.financeHeld = 0,
    this.quotingBlocked = false,
    this.quotingBlockedReason,
    this.canSubmit = false,
    this.epdkWarning,
    this.soonMinutes = 60,
    this.maxBatch = 50,
  });

  factory DeskHeader.fromJson(JsonReader r) => DeskHeader(
    expiryEnabled: r.boolean('expiryEnabled'),
    financeHeld: r.integer('financeHeld'),
    quotingBlocked: r.boolean('quotingBlocked'),
    quotingBlockedReason: r.nonEmpty('quotingBlockedReason'),
    canSubmit: r.boolean('canSubmit'),
    epdkWarning: r.nonEmpty('epdkWarning'),
    soonMinutes: r.integer('soonMinutes', 60),
    maxBatch: r.integer('maxBatch', 50),
  );

  final bool expiryEnabled;
  final int financeHeld;
  final bool quotingBlocked;
  final String? quotingBlockedReason;

  /// StationQuoteDesk Ekler ve engel yok.
  final bool canSubmit;
  final String? epdkWarning;
  final int soonMinutes;
  final int maxBatch;
}

/// Sekme sayıları.
@immutable
class DeskCounts {
  const DeskCounts({
    this.all = 0,
    this.awaitingQuote = 0,
    this.revision = 0,
    this.expiringSoon,
    this.financeHeld = 0,
  });

  factory DeskCounts.fromJson(JsonReader r) => DeskCounts(
    all: r.integer('all'),
    awaitingQuote: r.integer('awaitingQuote'),
    revision: r.integer('revision'),
    expiringSoon: r.intOrNull('expiringSoon'),
    financeHeld: r.integer('financeHeld'),
  );

  final int all;
  final int awaitingQuote;
  final int revision;

  /// Süre dolumu kapalıyken null.
  final int? expiringSoon;
  final int financeHeld;

  int? of(DeskView v) => switch (v) {
    DeskView.all => all,
    DeskView.awaitingQuote => awaitingQuote,
    DeskView.revision => revision,
    DeskView.expiringSoon => expiringSoon,
  };
}

/// Bugünkü tempo.
@immutable
class DeskToday {
  const DeskToday({
    this.ordersToday = 0,
    this.quotedToday = 0,
    this.avgFirstQuoteMinutes,
  });

  factory DeskToday.fromJson(JsonReader r) => DeskToday(
    ordersToday: r.integer('ordersToday'),
    quotedToday: r.integer('quotedToday'),
    avgFirstQuoteMinutes: r.intOrNull('avgFirstQuoteMinutes'),
  );

  final int ordersToday;
  final int quotedToday;
  final int? avgFirstQuoteMinutes;
}

/// Geçmiş alım fiyatı (onaylanan teklif).
@immutable
class DeskPricePoint {
  const DeskPricePoint({
    required this.orderId,
    required this.orderNumber,
    this.orderDate,
    this.quantityLiters = 0,
    this.unitPriceTry = 0,
  });

  factory DeskPricePoint.fromJson(JsonReader r) => DeskPricePoint(
    orderId: r.integer('orderId'),
    orderNumber: r.str('orderNumber'),
    orderDate: r.dateTr('orderDate'),
    quantityLiters: r.dec('quantityLiters'),
    unitPriceTry: r.dec('unitPriceTry'),
  );

  final int orderId;
  final String orderNumber;
  final DateTime? orderDate;
  final double quantityLiters;
  final double unitPriceTry;
}

/// Ödeme / finans çipi (web `QuoteDeskPaymentChip`).
@immutable
class DeskPayChip {
  const DeskPayChip({
    required this.line,
    this.methodName,
    this.statusLabel,
    this.tone = 'neutral',
    this.financeLabel,
    this.financeTone = 'neutral',
  });

  factory DeskPayChip.fromJson(JsonReader r) => DeskPayChip(
    line: r.str('line'),
    methodName: r.nonEmpty('methodName'),
    statusLabel: r.nonEmpty('statusLabel'),
    tone: r.str('tone', 'neutral'),
    financeLabel: r.nonEmpty('financeLabel'),
    financeTone: r.str('financeTone', 'neutral'),
  );

  final String line;
  final String? methodName;
  final String? statusLabel;
  final String tone;
  final String? financeLabel;
  final String financeTone;
}

/// Masa satırı (`BayiQuoteDeskRowDto`; tarihler +03:00).
@immutable
class DeskRow {
  const DeskRow({
    required this.orderId,
    required this.orderNumber,
    required this.status,
    this.statusLabel,
    this.customerId = 0,
    this.customerTitle = '',
    this.customerCode,
    this.productId = 0,
    this.productName = '',
    this.quantityLiters = 0,
    this.deliveryPointName,
    this.deliveryPointCity,
    this.deliveryPointDistrict,
    this.requestedDeliveryDate,
    this.expiresAt,
    this.createdAt,
    this.latestQuoteVersion,
    this.latestUnitPriceTry,
    this.latestQuoteDeliveryDate,
    this.latestRevisionNote,
    this.recentPrices = const [],
    this.paymentMethodName,
    this.paymentTermDays,
    this.paymentDueDate,
    this.paymentStatus = PaymentStatus.none,
    this.financeStatus = OrderFinanceStatus.notRequired,
    this.suggestedUnitPrice,
    this.suggestedSource,
    this.suggestedLabel,
    this.defaultDeliveryDate,
    this.secondsLeft,
    this.payChip,
  });

  factory DeskRow.fromJson(JsonReader r) {
    final chip = r.objOrNull('payChip');
    return DeskRow(
      orderId: r.integer('orderId'),
      orderNumber: r.str('orderNumber'),
      status: r.enumOf('status', OrderStatus.fromCode),
      statusLabel: r.nonEmpty('statusLabel'),
      customerId: r.integer('customerId'),
      customerTitle: r.str('customerTitle'),
      customerCode: r.nonEmpty('customerCode'),
      productId: r.integer('productId'),
      productName: r.str('productName'),
      quantityLiters: r.dec('quantityLiters'),
      deliveryPointName: r.nonEmpty('deliveryPointName'),
      deliveryPointCity: r.nonEmpty('deliveryPointCity'),
      deliveryPointDistrict: r.nonEmpty('deliveryPointDistrict'),
      requestedDeliveryDate: r.dateTr('requestedDeliveryDate'),
      expiresAt: r.dateTr('expiresAt'),
      createdAt: r.dateTr('createdAt'),
      latestQuoteVersion: r.intOrNull('latestQuoteVersion'),
      latestUnitPriceTry: r.decOrNull('latestUnitPriceTry'),
      latestQuoteDeliveryDate: r.dateTr('latestQuoteDeliveryDate'),
      latestRevisionNote: r.nonEmpty('latestRevisionNote'),
      recentPrices: List.unmodifiable(
        r.list('recentPrices', DeskPricePoint.fromJson),
      ),
      paymentMethodName: r.nonEmpty('paymentMethodName'),
      paymentTermDays: r.intOrNull('paymentTermDays'),
      paymentDueDate: r.dateTr('paymentDueDate'),
      paymentStatus: r.enumOf('paymentStatus', PaymentStatus.fromCode),
      financeStatus: r.enumOf('financeStatus', OrderFinanceStatus.fromCode),
      suggestedUnitPrice: r.decOrNull('suggestedUnitPrice'),
      suggestedSource: r.nonEmpty('suggestedSource'),
      suggestedLabel: r.nonEmpty('suggestedLabel'),
      defaultDeliveryDate: r.date('defaultDeliveryDate'),
      secondsLeft: r.intOrNull('secondsLeft'),
      payChip: chip == null ? null : DeskPayChip.fromJson(chip),
    );
  }

  final int orderId;
  final String orderNumber;
  final OrderStatus status;
  final String? statusLabel;
  final int customerId;
  final String customerTitle;
  final String? customerCode;
  final int productId;
  final String productName;
  final double quantityLiters;
  final String? deliveryPointName;
  final String? deliveryPointCity;
  final String? deliveryPointDistrict;
  final DateTime? requestedDeliveryDate;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final int? latestQuoteVersion;
  final double? latestUnitPriceTry;
  final DateTime? latestQuoteDeliveryDate;
  final String? latestRevisionNote;
  final List<DeskPricePoint> recentPrices;
  final String? paymentMethodName;
  final int? paymentTermDays;
  final DateTime? paymentDueDate;
  final PaymentStatus paymentStatus;
  final OrderFinanceStatus financeStatus;

  /// Önerilen ₺/L (geçerli fiyat → son alım → önceki teklif); yoksa null.
  final double? suggestedUnitPrice;
  final String? suggestedSource;
  final String? suggestedLabel;

  /// Varsayılan teklif teslim günü (Türkiye gece yarısı).
  final DateTime? defaultDeliveryDate;

  /// Süre sonuna kalan saniye (yanıt anında); süre dolumu kapalıyken null.
  final int? secondsLeft;
  final DeskPayChip? payChip;

  bool get isRevision => status == OrderStatus.revisionRequested;
}

/// `GET bayi/quote-desk` yanıtı.
@immutable
class DeskPage {
  const DeskPage({
    required this.header,
    this.rows = const [],
    this.totalCount = 0,
    this.page = 1,
    this.pageSize = 25,
    this.view = DeskView.all,
    this.sort = DeskSort.expiry,
    this.counts = const DeskCounts(),
    this.today = const DeskToday(),
    this.serverTime,
    required this.receivedAt,
  });

  factory DeskPage.fromJson(Object? json, {DateTime? receivedAt}) {
    final r = JsonReader.of(json);
    return DeskPage(
      header: DeskHeader.fromJson(r.obj('header')),
      rows: List.unmodifiable(r.list('rows', DeskRow.fromJson)),
      totalCount: r.integer('totalCount'),
      page: r.integer('page', 1),
      pageSize: r.integer('pageSize', 25),
      view: DeskView.fromKey(r.strOrNull('view')),
      sort: DeskSort.fromKey(r.strOrNull('sort')),
      counts: DeskCounts.fromJson(r.obj('counts')),
      today: DeskToday.fromJson(r.obj('today')),
      serverTime: r.dateTr('serverTime'),
      receivedAt: receivedAt ?? DateTime.now().toUtc(),
    );
  }

  final DeskHeader header;
  final List<DeskRow> rows;
  final int totalCount;
  final int page;
  final int pageSize;
  final DeskView view;
  final DeskSort sort;
  final DeskCounts counts;
  final DeskToday today;
  final DateTime? serverTime;

  /// Yanıtın alındığı an: geri sayım [DeskRow.secondsLeft] + bu andan hesaplanır (cihaz saatinden bağımsız).
  final DateTime receivedAt;

  bool get hasMore => page * pageSize < totalCount;
}

/// `GET bayi/quote-desk/counts`.
@immutable
class DeskCountsResult {
  const DeskCountsResult({
    this.expiryEnabled = false,
    this.counts = const DeskCounts(),
    this.today = const DeskToday(),
  });

  factory DeskCountsResult.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return DeskCountsResult(
      expiryEnabled: r.boolean('expiryEnabled'),
      counts: DeskCounts.fromJson(r.obj('counts')),
      today: DeskToday.fromJson(r.obj('today')),
    );
  }

  final bool expiryEnabled;
  final DeskCounts counts;
  final DeskToday today;
}

/// Süzgeç seçeneği (`QuoteDeskFacetDto`).
@immutable
class DeskFacet {
  const DeskFacet({required this.id, required this.title, this.count = 0});

  factory DeskFacet.fromJson(JsonReader r) => DeskFacet(
    id: r.integer('id'),
    title: r.str('title'),
    count: r.integer('count'),
  );

  final int id;
  final String title;
  final int count;
}

/// `GET stations/me/quote-desk/facets`: yalnızca bekleyen siparişi olan cariler / ürünler.
@immutable
class DeskFacets {
  const DeskFacets({this.customers = const [], this.products = const []});

  static const empty = DeskFacets();

  factory DeskFacets.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return DeskFacets(
      customers: List.unmodifiable(r.list('customers', DeskFacet.fromJson)),
      products: List.unmodifiable(r.list('products', DeskFacet.fromJson)),
    );
  }

  final List<DeskFacet> customers;
  final List<DeskFacet> products;
}

/// Satır sonucu (`QuoteDeskOutcomes`).
enum DeskOutcome {
  quoted('quoted', 'Teklif gönderildi'),
  routedToFinance('routedToFinance', 'Finans onayına gönderildi'),
  conflict('conflict', 'Başka bir işlemle güncellendi'),
  invalid('invalid', 'Gönderilemedi'),
  error('error', 'Hata');

  const DeskOutcome(this.key, this.label);
  final String key;
  final String label;

  static DeskOutcome fromKey(String? key) {
    final k = key?.trim().asciiLower;
    for (final v in values) {
      if (v.key.asciiLower == k) return v;
    }
    return error;
  }
}

/// `POST bayi/quote-desk/submit` satır sonucu.
@immutable
class DeskSubmitResult {
  const DeskSubmitResult({
    required this.orderId,
    required this.outcome,
    this.outcomeLabel,
    this.message = '',
  });

  factory DeskSubmitResult.fromJson(JsonReader r) => DeskSubmitResult(
    orderId: r.integer('orderId'),
    outcome: DeskOutcome.fromKey(r.strOrNull('outcome')),
    outcomeLabel: r.nonEmpty('outcomeLabel'),
    message: r.str('message'),
  );

  final int orderId;
  final DeskOutcome outcome;
  final String? outcomeLabel;
  final String message;

  bool get success => outcome == DeskOutcome.quoted;
  String get label => outcomeLabel ?? outcome.label;
}

/// Gönderilecek teklif satırı.
@immutable
class DeskSubmitItem {
  const DeskSubmitItem({
    required this.orderId,
    required this.unitPrice,
    required this.deliveryDate,
  });

  final int orderId;
  final double unitPrice;

  /// `yyyy-MM-dd`.
  final String deliveryDate;

  JsonMap toJson() => {
    'orderId': orderId,
    'unitPrice': unitPrice,
    'deliveryDate': deliveryDate,
  };
}

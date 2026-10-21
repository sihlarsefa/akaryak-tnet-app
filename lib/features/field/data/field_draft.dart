import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/models/json.dart';
import '../../../core/utils/tr_time.dart';
import 'field_models.dart';

/// Saha formu sihirbazının düzenlenen hâli (sunucuya `SaveFieldOrderRequest` olarak gider).
///
/// Değerler ayrıştırılmış sayılardır (₺/L 4, litre 3, tutar 2 ondalık); metin girişleri sihirbaz ekranında tutulur.
/// Sihirbazın yarıda kalan hâli bu sınıfın JSON'uyla cihaza yazılır ([toJson] / [fromJson]).
@immutable
class FieldFormDraft {
  const FieldFormDraft({
    this.formId,
    this.formNumber,
    this.concurrencyToken,
    this.stationId,
    this.customerId,
    this.customerTitle,
    this.shipDate,
    this.paymentMethodCode,
    this.paymentTermDays = 0,
    this.paymentDetails = const {},
    this.distributorName,
    this.terminalName,
    this.refineryLocation,
    this.transportKm,
    this.transportTotal,
    this.isCombinedShipment = false,
    this.combinedTruckLiters,
    this.combinedTruckCost,
    this.purchaseTermDays,
    this.purchaseTermPercent,
    this.transportPercent,
    this.otherPercent,
    this.strategicExceptionRequested = false,
    this.exceptionJustification,
    this.note,
    this.lines = const [],
  });

  /// Kayıtlı taslaktan (düzenleme).
  factory FieldFormDraft.fromForm(FieldForm f) => FieldFormDraft(
    formId: f.id,
    formNumber: f.formNumber,
    concurrencyToken: f.concurrencyToken,
    stationId: f.stationId,
    customerId: f.customerId,
    customerTitle: f.customerTitle,
    shipDate: f.shipDate,
    paymentMethodCode: f.paymentMethodCode,
    paymentTermDays: f.paymentTermDays,
    paymentDetails: f.paymentDetails,
    distributorName: f.distributorName,
    terminalName: f.terminalName,
    refineryLocation: f.refineryLocation,
    transportKm: f.transportKm,
    transportTotal: f.transportTotal,
    isCombinedShipment: f.isCombinedShipment,
    combinedTruckLiters: f.combinedTruckLiters,
    combinedTruckCost: f.combinedTruckCost,
    purchaseTermDays: f.purchaseTermDays,
    purchaseTermPercent: f.purchaseTermPercent,
    transportPercent: f.transportPercent,
    otherPercent: f.otherPercent,
    strategicExceptionRequested: f.strategicExceptionRequested,
    exceptionJustification: f.exceptionJustification,
    note: f.note,
    lines: [
      for (final l in f.lines)
        FieldLineDraft(
          key: FieldLineDraft.newKey(),
          productId: l.productId,
          deliveryPointId: l.deliveryPointId,
          liters: l.quantityLiters,
          date: l.requestedDeliveryDate,
          unitPrice: l.proposedUnitPrice,
          priceEdited: true,
          tuprasM3: l.tuprasPriceM3,
          tuprasEdited: l.tuprasOverridden,
          pumpPrice: l.pumpPricePerLiter,
          pumpEdited: l.pumpPricePerLiter != null,
          bindirimM3: l.bindirimM3,
          priceEntryMode: l.priceEntryMode,
          profitPercent: l.profitPercent,
        ),
    ],
  );

  factory FieldFormDraft.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final details = <String, String>{};
    r.map('paymentDetails').forEach((k, v) {
      if (v != null) details[k] = '$v';
    });
    return FieldFormDraft(
      formId: r.intOrNull('formId'),
      formNumber: r.nonEmpty('formNumber'),
      concurrencyToken: r.nonEmpty('concurrencyToken'),
      stationId: r.intOrNull('stationId'),
      customerId: r.intOrNull('customerId'),
      customerTitle: r.nonEmpty('customerTitle'),
      shipDate: r.date('shipDate'),
      paymentMethodCode: r.nonEmpty('paymentMethodCode'),
      paymentTermDays: r.integer('paymentTermDays'),
      paymentDetails: Map.unmodifiable(details),
      distributorName: r.nonEmpty('distributorName'),
      terminalName: r.nonEmpty('terminalName'),
      refineryLocation: r.nonEmpty('refineryLocation'),
      transportKm: r.decOrNull('transportKm'),
      transportTotal: r.decOrNull('transportTotal'),
      isCombinedShipment: r.boolean('isCombinedShipment'),
      combinedTruckLiters: r.decOrNull('combinedTruckLiters'),
      combinedTruckCost: r.decOrNull('combinedTruckCost'),
      purchaseTermDays: r.intOrNull('purchaseTermDays'),
      purchaseTermPercent: r.decOrNull('purchaseTermPercent'),
      transportPercent: r.decOrNull('transportPercent'),
      otherPercent: r.decOrNull('otherPercent'),
      strategicExceptionRequested: r.boolean('strategicExceptionRequested'),
      exceptionJustification: r.nonEmpty('exceptionJustification'),
      note: r.nonEmpty('note'),
      lines: List.unmodifiable(r.list('lines', FieldLineDraft.fromJson)),
    );
  }

  final int? formId;
  final String? formNumber;
  final String? concurrencyToken;
  final int? stationId;
  final int? customerId;
  final String? customerTitle;
  final DateTime? shipDate;
  final String? paymentMethodCode;
  final int paymentTermDays;
  final Map<String, String> paymentDetails;
  final String? distributorName;
  final String? terminalName;
  final String? refineryLocation;
  final double? transportKm;
  final double? transportTotal;
  final bool isCombinedShipment;
  final double? combinedTruckLiters;
  final double? combinedTruckCost;

  /// Yalnızca maliyet görebilen değiştirir.
  final int? purchaseTermDays;
  final double? purchaseTermPercent;
  final double? transportPercent;
  final double? otherPercent;
  final bool strategicExceptionRequested;
  final String? exceptionJustification;
  final String? note;
  final List<FieldLineDraft> lines;

  bool get isNew => formId == null;

  static const _unset = Object();

  FieldFormDraft copyWith({
    Object? formId = _unset,
    Object? formNumber = _unset,
    Object? concurrencyToken = _unset,
    Object? stationId = _unset,
    Object? customerId = _unset,
    Object? customerTitle = _unset,
    Object? shipDate = _unset,
    Object? paymentMethodCode = _unset,
    int? paymentTermDays,
    Map<String, String>? paymentDetails,
    Object? distributorName = _unset,
    Object? terminalName = _unset,
    Object? refineryLocation = _unset,
    Object? transportKm = _unset,
    Object? transportTotal = _unset,
    bool? isCombinedShipment,
    Object? combinedTruckLiters = _unset,
    Object? combinedTruckCost = _unset,
    Object? purchaseTermDays = _unset,
    Object? purchaseTermPercent = _unset,
    Object? transportPercent = _unset,
    Object? otherPercent = _unset,
    bool? strategicExceptionRequested,
    Object? exceptionJustification = _unset,
    Object? note = _unset,
    List<FieldLineDraft>? lines,
  }) {
    T pick<T>(Object? v, T current) {
      if (identical(v, _unset)) return current;
      // Ondalık alana tamsayı verilebilir (`liters: 8000`).
      if (v is int && <T>[] is List<double?>) return v.toDouble() as T;
      return v as T;
    }

    return FieldFormDraft(
      formId: pick<int?>(formId, this.formId),
      formNumber: pick<String?>(formNumber, this.formNumber),
      concurrencyToken: pick<String?>(concurrencyToken, this.concurrencyToken),
      stationId: pick<int?>(stationId, this.stationId),
      customerId: pick<int?>(customerId, this.customerId),
      customerTitle: pick<String?>(customerTitle, this.customerTitle),
      shipDate: pick<DateTime?>(shipDate, this.shipDate),
      paymentMethodCode: pick<String?>(
        paymentMethodCode,
        this.paymentMethodCode,
      ),
      paymentTermDays: paymentTermDays ?? this.paymentTermDays,
      paymentDetails: paymentDetails ?? this.paymentDetails,
      distributorName: pick<String?>(distributorName, this.distributorName),
      terminalName: pick<String?>(terminalName, this.terminalName),
      refineryLocation: pick<String?>(refineryLocation, this.refineryLocation),
      transportKm: pick<double?>(transportKm, this.transportKm),
      transportTotal: pick<double?>(transportTotal, this.transportTotal),
      isCombinedShipment: isCombinedShipment ?? this.isCombinedShipment,
      combinedTruckLiters: pick<double?>(
        combinedTruckLiters,
        this.combinedTruckLiters,
      ),
      combinedTruckCost: pick<double?>(
        combinedTruckCost,
        this.combinedTruckCost,
      ),
      purchaseTermDays: pick<int?>(purchaseTermDays, this.purchaseTermDays),
      purchaseTermPercent: pick<double?>(
        purchaseTermPercent,
        this.purchaseTermPercent,
      ),
      transportPercent: pick<double?>(transportPercent, this.transportPercent),
      otherPercent: pick<double?>(otherPercent, this.otherPercent),
      strategicExceptionRequested:
          strategicExceptionRequested ?? this.strategicExceptionRequested,
      exceptionJustification: pick<String?>(
        exceptionJustification,
        this.exceptionJustification,
      ),
      note: pick<String?>(note, this.note),
      lines: lines ?? this.lines,
    );
  }

  /// Satırın önizlemeye girecek kadar dolu olup olmadığı.
  bool lineIsComplete(FieldLineDraft l) => l.isComplete;

  /// Önizlemeye giden satırlar (eksik satırlar atlanır) ve sihirbaz satır anahtarı eşlemesi.
  List<FieldLineDraft> get completeLines => [
    for (final l in lines)
      if (l.isComplete) l,
  ];

  /// Sunucu isteği (`SaveFieldOrderRequest`). [includeCosts] false iken maliyet girdileri gönderilmez
  /// (sunucu zaten yok sayar). [onlyCompleteLines] önizlemede eksik satırları atlar.
  JsonMap toRequest({
    required bool includeCosts,
    bool onlyCompleteLines = false,
    bool forPreview = false,
  }) {
    final source = onlyCompleteLines ? completeLines : lines;
    final ship = shipDate;
    return {
      'stationId': stationId ?? 0,
      'customerId': customerId ?? 0,
      'paymentTermDays': paymentTermDays,
      'note': _trim(note),
      'concurrencyToken': ?concurrencyToken,
      'lines': [
        for (final l in source)
          l.toRequest(includeCosts: includeCosts, fallbackDate: ship),
      ],
      'shipDate': ?(ship == null ? null : TrTime.isoDate(ship)),
      'paymentMethodCode': _trim(paymentMethodCode),
      'paymentDetails': {
        for (final e in paymentDetails.entries)
          if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
      },
      'distributorName': _trim(distributorName),
      'terminalName': _trim(terminalName),
      'refineryLocation': _trim(refineryLocation),
      'transportKm': transportKm,
      'transportTotal': transportTotal,
      'isCombinedShipment': isCombinedShipment,
      'combinedTruckLiters': isCombinedShipment ? combinedTruckLiters : null,
      'combinedTruckCost': isCombinedShipment ? combinedTruckCost : null,
      if (includeCosts) ...{
        'purchaseTermDays': purchaseTermDays,
        'purchaseTermPercent': purchaseTermPercent,
        'transportPercent': transportPercent,
        'otherPercent': otherPercent,
      },
      'strategicExceptionRequested': strategicExceptionRequested,
      'exceptionJustification': strategicExceptionRequested
          ? _trim(exceptionJustification)
          : null,
      'includesCostInputs': includeCosts,
      if (forPreview) 'draftId': ?formId,
    };
  }

  JsonMap toJson() => {
    'formId': formId,
    'formNumber': formNumber,
    'concurrencyToken': concurrencyToken,
    'stationId': stationId,
    'customerId': customerId,
    'customerTitle': customerTitle,
    'shipDate': shipDate == null ? null : TrTime.isoDate(shipDate!),
    'paymentMethodCode': paymentMethodCode,
    'paymentTermDays': paymentTermDays,
    'paymentDetails': paymentDetails,
    'distributorName': distributorName,
    'terminalName': terminalName,
    'refineryLocation': refineryLocation,
    'transportKm': transportKm,
    'transportTotal': transportTotal,
    'isCombinedShipment': isCombinedShipment,
    'combinedTruckLiters': combinedTruckLiters,
    'combinedTruckCost': combinedTruckCost,
    'purchaseTermDays': purchaseTermDays,
    'purchaseTermPercent': purchaseTermPercent,
    'transportPercent': transportPercent,
    'otherPercent': otherPercent,
    'strategicExceptionRequested': strategicExceptionRequested,
    'exceptionJustification': exceptionJustification,
    'note': note,
    'lines': [for (final l in lines) l.toJson()],
  };

  /// Sihirbazdaki içeriğin karşılaştırma anahtarı (değişiklik var mı).
  String get fingerprint => toRequest(includeCosts: true).toString();

  /// Toplam litre (yalnızca girilmiş satırlar).
  double get totalLiters =>
      lines.fold<double>(0, (sum, l) => sum + (l.liters ?? 0));

  /// Tahmini tutar (litre × ₺/L; kesin değer sunucunun önizlemesindedir).
  double get estimatedAmount => lines.fold<double>(
    0,
    (sum, l) => sum + (l.liters ?? 0) * (l.unitPrice ?? 0),
  );

  static String? _trim(String? s) {
    final v = s?.trim();
    return v == null || v.isEmpty ? null : v;
  }
}

/// Sihirbazdaki ürün satırı.
@immutable
class FieldLineDraft {
  const FieldLineDraft({
    required this.key,
    this.productId,
    this.deliveryPointId,
    this.liters,
    this.date,
    this.unitPrice,
    this.priceEdited = false,
    this.tuprasM3,
    this.tuprasEdited = false,
    this.pumpPrice,
    this.pumpEdited = false,
    this.bindirimM3,
    this.priceEntryMode = 0,
    this.profitPercent,
  });

  factory FieldLineDraft.fromJson(JsonReader r) => FieldLineDraft(
    key: r.str('key', newKey()),
    productId: r.intOrNull('productId'),
    deliveryPointId: r.intOrNull('deliveryPointId'),
    liters: r.decOrNull('liters'),
    date: r.date('date'),
    unitPrice: r.decOrNull('unitPrice'),
    priceEdited: r.boolean('priceEdited'),
    tuprasM3: r.decOrNull('tuprasM3'),
    tuprasEdited: r.boolean('tuprasEdited'),
    pumpPrice: r.decOrNull('pumpPrice'),
    pumpEdited: r.boolean('pumpEdited'),
    bindirimM3: r.decOrNull('bindirimM3'),
    priceEntryMode: r.integer('priceEntryMode'),
    profitPercent: r.decOrNull('profitPercent'),
  );

  static final _rng = Random();
  static int _seq = 0;

  /// Liste anahtarı (yalnızca cihazda).
  static String newKey() =>
      'l${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${(_seq++).toRadixString(36)}${_rng.nextInt(1 << 16).toRadixString(36)}';

  final String key;
  final int? productId;
  final int? deliveryPointId;
  final double? liters;
  final DateTime? date;
  final double? unitPrice;

  /// Kullanıcı fiyatı kendisi yazdı (ürün değişince öneri üzerine yazılmaz).
  final bool priceEdited;

  /// Tüpraş ₺/m³ (KDV dahil); boş = referans.
  final double? tuprasM3;

  /// Kullanıcı Tüpraş fiyatını elle değiştirdi (lokasyon değişince referans üzerine yazılmaz).
  final bool tuprasEdited;
  final double? pumpPrice;
  final bool pumpEdited;

  /// Yalnızca maliyet görebilen.
  final double? bindirimM3;
  final int priceEntryMode;
  final double? profitPercent;

  bool get isComplete =>
      (productId ?? 0) > 0 &&
      (deliveryPointId ?? 0) > 0 &&
      (liters ?? 0) > 0 &&
      date != null &&
      (priceEntryMode == 1 ? profitPercent != null : (unitPrice ?? 0) > 0);

  static const _unset = Object();

  FieldLineDraft copyWith({
    Object? productId = _unset,
    Object? deliveryPointId = _unset,
    Object? liters = _unset,
    Object? date = _unset,
    Object? unitPrice = _unset,
    bool? priceEdited,
    Object? tuprasM3 = _unset,
    bool? tuprasEdited,
    Object? pumpPrice = _unset,
    bool? pumpEdited,
    Object? bindirimM3 = _unset,
    int? priceEntryMode,
    Object? profitPercent = _unset,
  }) {
    T pick<T>(Object? v, T current) {
      if (identical(v, _unset)) return current;
      // Ondalık alana tamsayı verilebilir (`liters: 8000`).
      if (v is int && <T>[] is List<double?>) return v.toDouble() as T;
      return v as T;
    }

    return FieldLineDraft(
      key: key,
      productId: pick<int?>(productId, this.productId),
      deliveryPointId: pick<int?>(deliveryPointId, this.deliveryPointId),
      liters: pick<double?>(liters, this.liters),
      date: pick<DateTime?>(date, this.date),
      unitPrice: pick<double?>(unitPrice, this.unitPrice),
      priceEdited: priceEdited ?? this.priceEdited,
      tuprasM3: pick<double?>(tuprasM3, this.tuprasM3),
      tuprasEdited: tuprasEdited ?? this.tuprasEdited,
      pumpPrice: pick<double?>(pumpPrice, this.pumpPrice),
      pumpEdited: pumpEdited ?? this.pumpEdited,
      bindirimM3: pick<double?>(bindirimM3, this.bindirimM3),
      priceEntryMode: priceEntryMode ?? this.priceEntryMode,
      profitPercent: pick<double?>(profitPercent, this.profitPercent),
    );
  }

  JsonMap toRequest({required bool includeCosts, DateTime? fallbackDate}) {
    final d = date ?? fallbackDate;
    final percent = includeCosts && priceEntryMode == 1;
    return {
      'productId': productId ?? 0,
      'deliveryPointId': deliveryPointId ?? 0,
      'quantityLiters': _round(liters ?? 0, 3),
      'requestedDeliveryDate': d == null ? null : TrTime.isoDate(d),
      'proposedUnitPrice': _round(unitPrice ?? 0, 4),
      'tuprasPriceM3': tuprasM3 == null ? null : _round(tuprasM3!, 2),
      'pumpPricePerLiter': pumpPrice == null ? null : _round(pumpPrice!, 4),
      if (includeCosts) ...{
        'bindirimM3': bindirimM3 == null ? null : _round(bindirimM3!, 2),
        'priceEntryMode': percent ? 1 : 0,
        'profitPercent': percent ? profitPercent : null,
      } else
        'priceEntryMode': 0,
    };
  }

  JsonMap toJson() => {
    'key': key,
    'productId': productId,
    'deliveryPointId': deliveryPointId,
    'liters': liters,
    'date': date == null ? null : TrTime.isoDate(date!),
    'unitPrice': unitPrice,
    'priceEdited': priceEdited,
    'tuprasM3': tuprasM3,
    'tuprasEdited': tuprasEdited,
    'pumpPrice': pumpPrice,
    'pumpEdited': pumpEdited,
    'bindirimM3': bindirimM3,
    'priceEntryMode': priceEntryMode,
    'profitPercent': profitPercent,
  };

  static double _round(double v, int decimals) {
    final f = pow(10, decimals).toDouble();
    return (v * f).roundToDouble() / f;
  }
}

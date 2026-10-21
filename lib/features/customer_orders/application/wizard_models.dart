import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/models/models.dart';
import '../../../core/utils/tr_time.dart';

/// Sihirbaz adımları.
enum WizardStep {
  products('Ürünler'),
  delivery('Teslimat'),
  payment('Ödeme'),
  summary('Özet');

  const WizardStep(this.label);
  final String label;
}

/// Sihirbazın açılış kaynağı (`/orders/new?fromTemplate=|fromRequest=|reorder=`).
enum DraftOrigin { fresh, template, reorder, request, partial }

String _uid() {
  final r = Random();
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${r.nextInt(1 << 20).toRadixString(36)}';
}

/// Sipariş satırı taslağı.
@immutable
class DraftLine {
  const DraftLine({
    required this.uid,
    this.productId,
    this.liters,
    this.custom = false,
    this.pointId,
    this.date,
  });

  factory DraftLine.create({int? productId, double? liters}) =>
      DraftLine(uid: _uid(), productId: productId, liters: liters);

  factory DraftLine.fromJson(JsonReader r) => DraftLine(
    uid: r.str('uid', _uid()),
    productId: r.intOrNull('productId'),
    liters: r.decOrNull('liters'),
    custom: r.boolean('custom'),
    pointId: r.intOrNull('pointId'),
    date: r.date('date'),
  );

  /// Yerel kimlik (liste anahtarı).
  final String uid;
  final int? productId;
  final double? liters;

  /// "Farklı nokta/tarih": satır kendi noktası ve tarihiyle gider.
  final bool custom;
  final int? pointId;

  /// Türkiye gece yarısı (an).
  final DateTime? date;

  DraftLine copyWith({
    int? productId,
    double? liters,
    bool clearLiters = false,
    bool? custom,
    int? pointId,
    DateTime? date,
  }) => DraftLine(
    uid: uid,
    productId: productId ?? this.productId,
    liters: clearLiters ? null : (liters ?? this.liters),
    custom: custom ?? this.custom,
    pointId: pointId ?? this.pointId,
    date: date ?? this.date,
  );

  JsonMap toJson() => {
    'uid': uid,
    'productId': productId,
    'liters': liters,
    'custom': custom,
    'pointId': pointId,
    'date': date == null ? null : TrTime.isoDate(date!),
  };
}

/// Ödeme taslağı (seçili yöntemin girilen değerleri).
@immutable
class DraftPayment {
  const DraftPayment({
    this.methodCode,
    this.cleared = false,
    this.termDays,
    this.installments,
    this.fields = const {},
    this.receiptPath,
    this.touched = false,
  });

  factory DraftPayment.fromJson(JsonReader r) => DraftPayment(
    methodCode: r.nonEmpty('methodCode'),
    cleared: r.boolean('cleared'),
    termDays: r.intOrNull('termDays'),
    installments: r.intOrNull('installments'),
    fields: Map.unmodifiable({
      for (final e in r.map('fields').entries)
        if (e.value != null) e.key: '${e.value}',
    }),
    receiptPath: r.nonEmpty('receiptPath'),
    touched: r.boolean('touched'),
  );

  /// Seçili yöntem; null = seçilmedi.
  final String? methodCode;

  /// Kullanıcı ödemeyi bilerek belirtmedi (varsayılan yeniden uygulanmaz).
  final bool cleared;
  final int? termDays;
  final int? installments;

  /// Alan değerleri (`amount` kullanıcı yazımıyla, tarihler `yyyy-MM-dd`).
  final Map<String, String> fields;

  /// Havale dekontu (isteğe bağlı; sipariş oluşunca yüklenir).
  final String? receiptPath;

  /// Kullanıcı bir yöntem seçti / değiştirdi.
  final bool touched;

  bool get hasMethod => methodCode != null;

  DraftPayment copyWith({
    String? methodCode,
    bool clearMethod = false,
    bool? cleared,
    int? termDays,
    bool clearTerm = false,
    int? installments,
    bool clearInstallments = false,
    Map<String, String>? fields,
    String? receiptPath,
    bool clearReceipt = false,
    bool? touched,
  }) => DraftPayment(
    methodCode: clearMethod ? null : (methodCode ?? this.methodCode),
    cleared: cleared ?? this.cleared,
    termDays: clearTerm ? null : (termDays ?? this.termDays),
    installments: clearInstallments
        ? null
        : (installments ?? this.installments),
    fields: fields ?? this.fields,
    receiptPath: clearReceipt ? null : (receiptPath ?? this.receiptPath),
    touched: touched ?? this.touched,
  );

  JsonMap toJson() => {
    'methodCode': methodCode,
    'cleared': cleared,
    'termDays': termDays,
    'installments': installments,
    'fields': fields,
    'receiptPath': receiptPath,
    'touched': touched,
  };
}

/// Sipariş taslağı (kullanıcı başına saklanır, 24 sa).
@immutable
class OrderDraft {
  const OrderDraft({
    this.stationId,
    this.lines = const [],
    this.pointId,
    this.date,
    this.payment = const DraftPayment(),
    this.note = '',
    this.templateId,
    this.saveAsTemplate = false,
    this.templateName = '',
    this.paymentGroupKey,
    this.step = WizardStep.products,
    this.origin = DraftOrigin.fresh,
    this.dirty = false,
  });

  factory OrderDraft.empty() => OrderDraft(lines: [DraftLine.create()]);

  factory OrderDraft.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final lines = r.list('lines', DraftLine.fromJson);
    return OrderDraft(
      stationId: r.intOrNull('stationId'),
      lines: List.unmodifiable(lines.isEmpty ? [DraftLine.create()] : lines),
      pointId: r.intOrNull('pointId'),
      date: r.date('date'),
      payment: DraftPayment.fromJson(r.obj('payment')),
      note: r.str('note'),
      templateId: r.intOrNull('templateId'),
      saveAsTemplate: r.boolean('saveAsTemplate'),
      templateName: r.str('templateName'),
      paymentGroupKey: r.nonEmpty('paymentGroupKey'),
      step: WizardStep.values.firstWhere(
        (s) => s.name == r.str('step'),
        orElse: () => WizardStep.products,
      ),
      origin: DraftOrigin.values.firstWhere(
        (o) => o.name == r.str('origin'),
        orElse: () => DraftOrigin.fresh,
      ),
      dirty: r.boolean('dirty'),
    );
  }

  final int? stationId;
  final List<DraftLine> lines;

  /// Ana teslimat noktası ve tarihi (satır kendi değerini taşımıyorsa).
  final int? pointId;
  final DateTime? date;
  final DraftPayment payment;

  /// "Onaylayana not" (yalnızca şirket içi onaya düşecek siparişte gider).
  final String note;
  final int? templateId;
  final bool saveAsTemplate;
  final String templateName;

  /// Kısmi hatadan sonra kalan satırların ödeme grubu.
  final String? paymentGroupKey;
  final WizardStep step;
  final DraftOrigin origin;

  /// Kullanıcı bir değişiklik yaptı (çıkışta onay sorulur).
  final bool dirty;

  /// Satırın gerçek noktası.
  int? pointOf(DraftLine l) => l.custom ? (l.pointId ?? pointId) : pointId;

  /// Satırın gerçek tarihi.
  DateTime? dateOf(DraftLine l) => l.custom ? (l.date ?? date) : date;

  double get totalLiters =>
      lines.fold<double>(0, (s, l) => s + (l.liters ?? 0));

  /// Noktaya giden toplam litre (tank uyarısı).
  Map<int, double> litersByPoint() {
    final out = <int, double>{};
    for (final l in lines) {
      final p = pointOf(l);
      if (p == null) continue;
      out[p] = (out[p] ?? 0) + (l.liters ?? 0);
    }
    return out;
  }

  /// Taslak boş sayılır (yalnızca boş satır).
  bool get isBlank =>
      lines.every((l) => l.productId == null && (l.liters ?? 0) <= 0);

  OrderDraft copyWith({
    int? stationId,
    List<DraftLine>? lines,
    int? pointId,
    DateTime? date,
    DraftPayment? payment,
    String? note,
    int? templateId,
    bool clearTemplate = false,
    bool? saveAsTemplate,
    String? templateName,
    String? paymentGroupKey,
    bool clearGroupKey = false,
    WizardStep? step,
    DraftOrigin? origin,
    bool? dirty,
  }) => OrderDraft(
    stationId: stationId ?? this.stationId,
    lines: lines == null ? this.lines : List.unmodifiable(lines),
    pointId: pointId ?? this.pointId,
    date: date ?? this.date,
    payment: payment ?? this.payment,
    note: note ?? this.note,
    templateId: clearTemplate ? null : (templateId ?? this.templateId),
    saveAsTemplate: saveAsTemplate ?? this.saveAsTemplate,
    templateName: templateName ?? this.templateName,
    paymentGroupKey: clearGroupKey
        ? null
        : (paymentGroupKey ?? this.paymentGroupKey),
    step: step ?? this.step,
    origin: origin ?? this.origin,
    dirty: dirty ?? this.dirty,
  );

  JsonMap toJson() => {
    'stationId': stationId,
    'lines': [for (final l in lines) l.toJson()],
    'pointId': pointId,
    'date': date == null ? null : TrTime.isoDate(date!),
    'payment': payment.toJson(),
    'note': note,
    'templateId': templateId,
    'saveAsTemplate': saveAsTemplate,
    'templateName': templateName,
    'paymentGroupKey': paymentGroupKey,
    'step': step.name,
    'origin': origin.name,
    'dirty': dirty,
  };
}

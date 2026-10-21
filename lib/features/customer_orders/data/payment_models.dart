import 'package:flutter/foundation.dart';

import '../../../core/models/models.dart';
import '../../../core/utils/turkish_text.dart';

/// Ödeme yöntemi kodları (`PaymentMethodCodes`).
abstract final class PaymentCodes {
  static const cash = 'NAKIT';
  static const transfer = 'HAVALE';
  static const card = 'KART';
  static const dbs = 'DBS';
  static const cheque = 'CEK';
  static const promissoryNote = 'SENET';
  static const openAccount = 'ACIK_HESAP';
  static const guarantee = 'TEMINAT';
  static const utts = 'UTTS';
  static const advance = 'AVANS';

  /// Çek / senet: belgenin vadesi esastır, sipariş grubu başına tek belge.
  static bool isInstrument(String? code) =>
      code == cheque || code == promissoryNote;
}

/// Yöntem detay alanı seçeneği (`PaymentFieldChoiceDto`).
@immutable
class PaymentFieldChoice {
  const PaymentFieldChoice({required this.value, required this.label});

  factory PaymentFieldChoice.fromJson(JsonReader r) =>
      PaymentFieldChoice(value: r.str('value'), label: r.str('label'));

  final String value;
  final String label;
}

/// Yöntem detay alanı şeması (`PaymentFieldDto`).
@immutable
class PaymentField {
  const PaymentField({
    required this.key,
    required this.label,
    this.type = 'text',
    this.required = false,
    this.maxLength,
    this.options = const [],
    this.placeholder,
    this.choices = const [],
  });

  factory PaymentField.fromJson(JsonReader r) => PaymentField(
    key: r.str('key'),
    label: r.str('label'),
    type: r.str('type', 'text').asciiLower,
    required: r.boolean('required'),
    maxLength: r.intOrNull('maxLength'),
    options: r.strings('options'),
    placeholder: r.nonEmpty('placeholder'),
    choices: List.unmodifiable(r.list('choices', PaymentFieldChoice.fromJson)),
  );

  /// `OrderPaymentSelection.Details` anahtarı (`bank`, `serialNo`, `amount`, `dueDate` …).
  final String key;
  final String label;

  /// text | number | money | date | select | textarea.
  final String type;
  final bool required;
  final int? maxLength;
  final List<String> options;
  final String? placeholder;
  final List<PaymentFieldChoice> choices;

  /// Seçim alanının seçenekleri (sunucu seçimleri ya da düz seçenekler).
  List<PaymentFieldChoice> get selectChoices => choices.isNotEmpty
      ? choices
      : [for (final o in options) PaymentFieldChoice(value: o, label: o)];
}

/// Seçicide bir yöntem kartı (`PaymentMethodOptionDto`).
@immutable
class PaymentMethodOption {
  const PaymentMethodOption({
    required this.code,
    required this.name,
    this.shortName,
    this.isDeferred = false,
    this.requiresFinance = false,
    this.documentKind,
    this.documentRequired = false,
    this.allowsInstallments = false,
    this.installmentOptions = const [],
    this.minTermDays = 0,
    this.maxTermDays = 0,
    this.defaultTermDays,
    this.fields = const [],
    this.hint,
  });

  factory PaymentMethodOption.fromJson(JsonReader r) => PaymentMethodOption(
    code: r.str('code').asciiUpper,
    name: r.str('name'),
    shortName: r.nonEmpty('shortName'),
    isDeferred: r.boolean('isDeferred'),
    requiresFinance: r.boolean('requiresFinance'),
    documentKind: r.has('documentKind')
        ? r.enumOf('documentKind', AttachmentKind.fromCode)
        : null,
    documentRequired: r.boolean('documentRequired'),
    allowsInstallments: r.boolean('allowsInstallments'),
    installmentOptions: r.ints('installmentOptions'),
    minTermDays: r.integer('minTermDays'),
    maxTermDays: r.integer('maxTermDays'),
    defaultTermDays: r.intOrNull('defaultTermDays'),
    fields: List.unmodifiable(r.list('fields', PaymentField.fromJson)),
    hint: r.nonEmpty('hint'),
  );

  final String code;
  final String name;
  final String? shortName;
  final bool isDeferred;

  /// Bu yöntemde sipariş finans onayına düşebilir (kesin karar sipariş anında).
  final bool requiresFinance;
  final AttachmentKind? documentKind;
  final bool documentRequired;
  final bool allowsInstallments;
  final List<int> installmentOptions;
  final int minTermDays;
  final int maxTermDays;
  final int? defaultTermDays;
  final List<PaymentField> fields;
  final String? hint;

  String get displayName => shortName ?? name;

  /// Vade seçimi var mı (vadeli yöntem).
  bool get hasTerm => maxTermDays > 0;

  bool get hasInstallments =>
      allowsInstallments && installmentOptions.isNotEmpty;

  bool get isInstrument => PaymentCodes.isInstrument(code);

  PaymentField? field(String key) {
    for (final f in fields) {
      if (f.key == key) return f;
    }
    return null;
  }

  /// Kart alt satırı: "Vadeli, 1–180 gün", "Peşin, taksit seçenekli", "Peşin".
  String get termLabel {
    if (maxTermDays > 0) {
      return minTermDays > 0
          ? 'Vadeli, $minTermDays–$maxTermDays gün'
          : 'Vadeli, en çok $maxTermDays gün';
    }
    if (allowsInstallments && installmentOptions.length > 1) {
      return 'Peşin, taksit seçenekli';
    }
    return 'Peşin';
  }
}

/// Ödeme seçici verisi (`PaymentOptionsDto`).
@immutable
class PaymentOptions {
  const PaymentOptions({
    this.stationId = 0,
    this.customerId = 0,
    this.enabled = true,
    this.defaultMethodCode,
    this.methods = const [],
    this.blockedReason,
    this.advanceBalance,
    this.linked = true,
  });

  factory PaymentOptions.fromJson(JsonReader r) => PaymentOptions(
    stationId: r.integer('stationId'),
    customerId: r.integer('customerId'),
    enabled: r.boolean('enabled', true),
    defaultMethodCode: r.nonEmpty('defaultMethodCode')?.asciiUpper,
    methods: List.unmodifiable(r.list('methods', PaymentMethodOption.fromJson)),
    blockedReason: r.nonEmpty('blockedReason'),
    advanceBalance: r.decOrNull('advanceBalance'),
    linked: r.boolean('linked', true),
  );

  final int stationId;
  final int customerId;

  /// `Payments.Enabled` kapalıysa false: seçici gösterilmez.
  final bool enabled;
  final String? defaultMethodCode;
  final List<PaymentMethodOption> methods;
  final String? blockedReason;

  /// Ön ödemeli bakiye (AVANS açıksa).
  final double? advanceBalance;
  final bool linked;

  PaymentMethodOption? method(String? code) {
    if (code == null) return null;
    for (final m in methods) {
      if (m.code == code) return m;
    }
    return null;
  }
}

/// `GET payments/options` (`CustomerPaymentOptionsDto`): seçenekler + ürün başına ₺/L.
@immutable
class CustomerPaymentOptions {
  const CustomerPaymentOptions({
    this.options = const PaymentOptions(),
    this.unitPrices = const {},
  });

  factory CustomerPaymentOptions.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final prices = <int, double>{};
    r.map('unitPrices').forEach((k, v) {
      final id = int.tryParse(k);
      final p = JsonReader.toDouble(v);
      if (id != null && p != null && p > 0) prices[id] = p;
    });
    return CustomerPaymentOptions(
      options: PaymentOptions.fromJson(r.obj('options')),
      unitPrices: Map.unmodifiable(prices),
    );
  }

  final PaymentOptions options;

  /// Ürün → ₺/L (yalnızca bağlı caride dolu).
  final Map<int, double> unitPrices;
}

/// Ödeme belgesinin yükleneceği hedef (`PaymentUploadTargetDto`).
@immutable
class PaymentUploadTarget {
  const PaymentUploadTarget({
    this.ownerType = AttachmentOwnerType.unknown,
    this.ownerId = 0,
    this.kind = AttachmentKind.unknown,
    this.kindLabel,
    this.required = false,
    this.canUpload = false,
    this.message,
    this.orderId,
  });

  factory PaymentUploadTarget.fromJson(JsonReader r) => PaymentUploadTarget(
    ownerType: r.enumOf('ownerType', AttachmentOwnerType.fromCode),
    ownerId: r.integer('ownerId'),
    kind: r.enumOf('kind', AttachmentKind.fromCode),
    kindLabel: r.nonEmpty('kindLabel'),
    required: r.boolean('required'),
    canUpload: r.boolean('canUpload'),
    message: r.nonEmpty('message'),
    orderId: r.intOrNull('orderId'),
  );

  /// 204 (belge gerekmiyor) → null.
  static PaymentUploadTarget? tryParse(Object? json) {
    if (json is! Map) return null;
    final t = PaymentUploadTarget.fromJson(JsonReader.of(json));
    return t.kind.isUnknown ? null : t;
  }

  final AttachmentOwnerType ownerType;
  final int ownerId;
  final AttachmentKind kind;
  final String? kindLabel;
  final bool required;
  final bool canUpload;
  final String? message;
  final int? orderId;

  String get label => kindLabel ?? kind.label;

  /// Yüklemeye hazır hedef (sipariş oluştu, yetki var).
  bool get isUploadable => canUpload && ownerId > 0 && !ownerType.isUnknown;

  JsonMap toJson() => {
    'ownerType': ownerType.code,
    'ownerId': ownerId,
    'kind': kind.code,
    'kindLabel': kindLabel,
    'required': required,
    'canUpload': canUpload,
    'message': message,
    'orderId': orderId,
  };
}

/// Gönderilecek ödeme seçimi (`OrderPaymentSelection`).
@immutable
class PaymentSelection {
  const PaymentSelection({
    required this.methodCode,
    this.termDays,
    this.installments,
    this.details = const {},
  });

  factory PaymentSelection.fromJson(JsonReader r) => PaymentSelection(
    methodCode: r.str('methodCode').asciiUpper,
    termDays: r.intOrNull('termDays'),
    installments: r.intOrNull('installments'),
    details: Map.unmodifiable({
      for (final e in r.map('details').entries)
        if (e.value != null && '${e.value}'.trim().isNotEmpty)
          e.key: '${e.value}'.trim(),
    }),
  );

  final String methodCode;
  final int? termDays;
  final int? installments;
  final Map<String, String> details;

  JsonMap toJson() => {
    'methodCode': methodCode,
    'termDays': termDays,
    'installments': installments,
    'details': {
      for (final e in details.entries)
        if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
    },
  };
}

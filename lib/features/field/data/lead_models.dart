import 'package:flutter/foundation.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/json.dart';
import '../../../core/utils/tr_time.dart';

/// Saha ön kaydı modelleri (sunucu: `LeadDtos.cs`, `Mobile/FieldDtos.cs`). Oluşturma, gönderme ve KVKK
/// anları UTC; ilk sevk ve ziyaret günleri Türkiye günüdür.

/// Teminat önerisi türü (`CollateralKind`).
enum CollateralOfferKind {
  letterOfGuarantee(1, 'Teminat mektubu'),
  dbs(2, 'DBS'),
  mortgage(3, 'İpotek'),
  cheque(4, 'Çek'),
  cash(5, 'Nakit teminat'),
  other(9, 'Diğer');

  const CollateralOfferKind(this.code, this.label);
  final int code;
  final String label;

  static CollateralOfferKind? fromCode(int? code) {
    for (final k in values) {
      if (k.code == code) return k;
    }
    return null;
  }
}

/// Liste satırı (`LeadListItemDto`).
@immutable
class LeadRow {
  const LeadRow({
    required this.id,
    required this.leadNumber,
    required this.status,
    required this.companyTitle,
    this.taxNumber = '',
    this.city,
    this.salesRepName,
    this.requestedLimitAmount,
    this.monthlyLiters,
    this.existsElsewhere = false,
    this.createdAt,
    this.submittedAt,
    this.convertedAt,
  });

  factory LeadRow.fromJson(JsonReader r) => LeadRow(
    id: r.integer('id'),
    leadNumber: r.str('leadNumber'),
    status: r.enumOf('status', LeadStatus.fromCode),
    companyTitle: r.str('companyTitle'),
    taxNumber: r.str('taxNumber'),
    city: r.nonEmpty('city'),
    salesRepName: r.nonEmpty('salesRepName'),
    requestedLimitAmount: r.decOrNull('requestedLimitAmount'),
    monthlyLiters: r.decOrNull('monthlyLiters'),
    existsElsewhere: r.boolean('existsElsewhere'),
    createdAt: r.dateUtc('createdAt'),
    submittedAt: r.dateUtc('submittedAt'),
    convertedAt: r.dateUtc('convertedAt'),
  );

  final int id;
  final String leadNumber;
  final LeadStatus status;
  final String companyTitle;
  final String taxNumber;
  final String? city;
  final String? salesRepName;
  final double? requestedLimitAmount;
  final double? monthlyLiters;
  final bool existsElsewhere;
  final DateTime? createdAt;
  final DateTime? submittedAt;
  final DateTime? convertedAt;
}

/// Yetkili (`LeadContactDto`).
@immutable
class LeadContact {
  const LeadContact({
    this.id = 0,
    this.name = '',
    this.title,
    this.phone,
    this.email,
    this.isPrimary = false,
    this.isInviteRecipient = false,
  });

  factory LeadContact.fromJson(JsonReader r) => LeadContact(
    id: r.integer('id'),
    name: r.str('name'),
    title: r.nonEmpty('title'),
    phone: r.nonEmpty('phone'),
    email: r.nonEmpty('email'),
    isPrimary: r.boolean('isPrimary'),
    isInviteRecipient: r.boolean('isInviteRecipient'),
  );

  final int id;
  final String name;
  final String? title;
  final String? phone;
  final String? email;
  final bool isPrimary;
  final bool isInviteRecipient;

  bool get isEmpty =>
      name.trim().isEmpty &&
      (title ?? '').trim().isEmpty &&
      (phone ?? '').trim().isEmpty &&
      (email ?? '').trim().isEmpty;

  static const _unset = Object();

  LeadContact copyWith({
    String? name,
    Object? title = _unset,
    Object? phone = _unset,
    Object? email = _unset,
    bool? isPrimary,
    bool? isInviteRecipient,
  }) {
    T pick<T>(Object? v, T current) {
      if (identical(v, _unset)) return current;
      // Ondalık alana tamsayı verilebilir (`liters: 8000`).
      if (v is int && <T>[] is List<double?>) return v.toDouble() as T;
      return v as T;
    }

    return LeadContact(
      id: id,
      name: name ?? this.name,
      title: pick<String?>(title, this.title),
      phone: pick<String?>(phone, this.phone),
      email: pick<String?>(email, this.email),
      isPrimary: isPrimary ?? this.isPrimary,
      isInviteRecipient: isInviteRecipient ?? this.isInviteRecipient,
    );
  }

  JsonMap toJson() => {
    'id': id,
    'name': name.trim(),
    'title': _t(title),
    'phone': _t(phone),
    'email': _t(email),
    'isPrimary': isPrimary,
    'isInviteRecipient': isInviteRecipient,
  };
}

/// Ürün ihtiyacı (`LeadProductDto`).
@immutable
class LeadProductNeed {
  const LeadProductNeed({
    required this.productId,
    this.productName,
    this.monthlyLiters = 0,
    this.committedMonthlyLiters,
  });

  factory LeadProductNeed.fromJson(JsonReader r) => LeadProductNeed(
    productId: r.integer('productId'),
    productName: r.nonEmpty('productName'),
    monthlyLiters: r.dec('monthlyLiters'),
    committedMonthlyLiters: r.decOrNull('committedMonthlyLiters'),
  );

  final int productId;
  final String? productName;
  final double monthlyLiters;
  final double? committedMonthlyLiters;

  JsonMap toJson() => {
    'productId': productId,
    'monthlyLiters': monthlyLiters,
    'committedMonthlyLiters': committedMonthlyLiters,
  };
}

/// Düzenlenen ön kayıt (`LeadSaveDto`). Sihirbaz bu sınıfı değiştirir; [toSaveJson] sunucuya gider.
@immutable
class LeadDraft {
  const LeadDraft({
    this.id = 0,
    this.stationId = 0,
    this.concurrencyToken,
    this.companyTitle = '',
    this.taxNumber = '',
    this.taxOffice,
    this.city,
    this.district,
    this.address,
    this.sector,
    this.foundedYear,
    this.phone,
    this.email,
    this.website,
    this.vehicleCount,
    this.vehicleTypes,
    this.hasTank = false,
    this.tankCapacityLiters,
    this.products = const [],
    this.contractMonths,
    this.firstOrderProductId,
    this.firstOrderLiters,
    this.firstShipDate,
    this.requestedMethodCodes = const [],
    this.requestedTermDays,
    this.requestedLimitAmount,
    this.collateralRatioPercent,
    this.collateralOfferKind,
    this.collateralOfferAmount,
    this.collateralOfferNote,
    this.currentDistributor,
    this.currentTerminal,
    this.currentPriceNote,
    this.priceExpectation,
    this.visitNote,
    this.visitLatitude,
    this.visitLongitude,
    this.visitAccuracyMeters,
    this.visitAt,
    this.deliveryPointName,
    this.deliveryPointCity,
    this.deliveryPointDistrict,
    this.deliveryPointAddress,
    this.contacts = const [],
    this.kvkkConsent = false,
    this.kvkkConsentMethod,
  });

  factory LeadDraft.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return LeadDraft(
      id: r.integer('id'),
      stationId: r.integer('stationId'),
      concurrencyToken: r.nonEmpty('concurrencyToken'),
      companyTitle: r.str('companyTitle'),
      taxNumber: r.str('taxNumber'),
      taxOffice: r.nonEmpty('taxOffice'),
      city: r.nonEmpty('city'),
      district: r.nonEmpty('district'),
      address: r.nonEmpty('address'),
      sector: r.nonEmpty('sector'),
      foundedYear: r.intOrNull('foundedYear'),
      phone: r.nonEmpty('phone'),
      email: r.nonEmpty('email'),
      website: r.nonEmpty('website'),
      vehicleCount: r.intOrNull('vehicleCount'),
      vehicleTypes: r.nonEmpty('vehicleTypes'),
      hasTank: r.boolean('hasTank'),
      tankCapacityLiters: r.decOrNull('tankCapacityLiters'),
      products: List.unmodifiable(r.list('products', LeadProductNeed.fromJson)),
      contractMonths: r.intOrNull('contractMonths'),
      firstOrderProductId: r.intOrNull('firstOrderProductId'),
      firstOrderLiters: r.decOrNull('firstOrderLiters'),
      firstShipDate: r.date('firstShipDate'),
      requestedMethodCodes: List.unmodifiable(
        r.strings('requestedMethodCodes'),
      ),
      requestedTermDays: r.intOrNull('requestedTermDays'),
      requestedLimitAmount: r.decOrNull('requestedLimitAmount'),
      collateralRatioPercent: r.decOrNull('collateralRatioPercent'),
      collateralOfferKind: CollateralOfferKind.fromCode(
        r.intOrNull('collateralOfferKind'),
      ),
      collateralOfferAmount: r.decOrNull('collateralOfferAmount'),
      collateralOfferNote: r.nonEmpty('collateralOfferNote'),
      currentDistributor: r.nonEmpty('currentDistributor'),
      currentTerminal: r.nonEmpty('currentTerminal'),
      currentPriceNote: r.nonEmpty('currentPriceNote'),
      priceExpectation: r.nonEmpty('priceExpectation'),
      visitNote: r.nonEmpty('visitNote'),
      visitLatitude: r.decOrNull('visitLatitude'),
      visitLongitude: r.decOrNull('visitLongitude'),
      visitAccuracyMeters: r.decOrNull('visitAccuracyMeters'),
      visitAt: r.date('visitAt'),
      deliveryPointName: r.nonEmpty('deliveryPointName'),
      deliveryPointCity: r.nonEmpty('deliveryPointCity'),
      deliveryPointDistrict: r.nonEmpty('deliveryPointDistrict'),
      deliveryPointAddress: r.nonEmpty('deliveryPointAddress'),
      contacts: List.unmodifiable(r.list('contacts', LeadContact.fromJson)),
      kvkkConsent: r.boolean('kvkkConsent'),
      kvkkConsentMethod: r.nonEmpty('kvkkConsentMethod'),
    );
  }

  final int id;
  final int stationId;
  final String? concurrencyToken;
  final String companyTitle;
  final String taxNumber;
  final String? taxOffice;
  final String? city;
  final String? district;
  final String? address;
  final String? sector;
  final int? foundedYear;
  final String? phone;
  final String? email;
  final String? website;
  final int? vehicleCount;
  final String? vehicleTypes;
  final bool hasTank;
  final double? tankCapacityLiters;
  final List<LeadProductNeed> products;
  final int? contractMonths;
  final int? firstOrderProductId;
  final double? firstOrderLiters;
  final DateTime? firstShipDate;
  final List<String> requestedMethodCodes;
  final int? requestedTermDays;
  final double? requestedLimitAmount;
  final double? collateralRatioPercent;
  final CollateralOfferKind? collateralOfferKind;
  final double? collateralOfferAmount;
  final String? collateralOfferNote;
  final String? currentDistributor;
  final String? currentTerminal;
  final String? currentPriceNote;
  final String? priceExpectation;
  final String? visitNote;
  final double? visitLatitude;
  final double? visitLongitude;
  final double? visitAccuracyMeters;
  final DateTime? visitAt;
  final String? deliveryPointName;
  final String? deliveryPointCity;
  final String? deliveryPointDistrict;
  final String? deliveryPointAddress;
  final List<LeadContact> contacts;
  final bool kvkkConsent;
  final String? kvkkConsentMethod;

  bool get isNew => id <= 0;

  /// Sunucunun taslak için istediği en az bilgi (ünvan ya da VKN).
  bool get canSaveDraft =>
      companyTitle.trim().isNotEmpty || taxNumber.trim().isNotEmpty;

  double get totalMonthlyLiters =>
      products.fold<double>(0, (s, p) => s + p.monthlyLiters);

  bool get hasVisitLocation => visitLatitude != null && visitLongitude != null;

  static const _unset = Object();

  LeadDraft copyWith({
    int? id,
    int? stationId,
    Object? concurrencyToken = _unset,
    String? companyTitle,
    String? taxNumber,
    Object? taxOffice = _unset,
    Object? city = _unset,
    Object? district = _unset,
    Object? address = _unset,
    Object? sector = _unset,
    Object? foundedYear = _unset,
    Object? phone = _unset,
    Object? email = _unset,
    Object? website = _unset,
    Object? vehicleCount = _unset,
    Object? vehicleTypes = _unset,
    bool? hasTank,
    Object? tankCapacityLiters = _unset,
    List<LeadProductNeed>? products,
    Object? contractMonths = _unset,
    Object? firstOrderProductId = _unset,
    Object? firstOrderLiters = _unset,
    Object? firstShipDate = _unset,
    List<String>? requestedMethodCodes,
    Object? requestedTermDays = _unset,
    Object? requestedLimitAmount = _unset,
    Object? collateralRatioPercent = _unset,
    Object? collateralOfferKind = _unset,
    Object? collateralOfferAmount = _unset,
    Object? collateralOfferNote = _unset,
    Object? currentDistributor = _unset,
    Object? currentTerminal = _unset,
    Object? currentPriceNote = _unset,
    Object? priceExpectation = _unset,
    Object? visitNote = _unset,
    Object? visitLatitude = _unset,
    Object? visitLongitude = _unset,
    Object? visitAccuracyMeters = _unset,
    Object? visitAt = _unset,
    Object? deliveryPointName = _unset,
    Object? deliveryPointCity = _unset,
    Object? deliveryPointDistrict = _unset,
    Object? deliveryPointAddress = _unset,
    List<LeadContact>? contacts,
    bool? kvkkConsent,
    Object? kvkkConsentMethod = _unset,
  }) {
    T pick<T>(Object? v, T current) {
      if (identical(v, _unset)) return current;
      // Ondalık alana tamsayı verilebilir (`liters: 8000`).
      if (v is int && <T>[] is List<double?>) return v.toDouble() as T;
      return v as T;
    }

    return LeadDraft(
      id: id ?? this.id,
      stationId: stationId ?? this.stationId,
      concurrencyToken: pick<String?>(concurrencyToken, this.concurrencyToken),
      companyTitle: companyTitle ?? this.companyTitle,
      taxNumber: taxNumber ?? this.taxNumber,
      taxOffice: pick<String?>(taxOffice, this.taxOffice),
      city: pick<String?>(city, this.city),
      district: pick<String?>(district, this.district),
      address: pick<String?>(address, this.address),
      sector: pick<String?>(sector, this.sector),
      foundedYear: pick<int?>(foundedYear, this.foundedYear),
      phone: pick<String?>(phone, this.phone),
      email: pick<String?>(email, this.email),
      website: pick<String?>(website, this.website),
      vehicleCount: pick<int?>(vehicleCount, this.vehicleCount),
      vehicleTypes: pick<String?>(vehicleTypes, this.vehicleTypes),
      hasTank: hasTank ?? this.hasTank,
      tankCapacityLiters: pick<double?>(
        tankCapacityLiters,
        this.tankCapacityLiters,
      ),
      products: products ?? this.products,
      contractMonths: pick<int?>(contractMonths, this.contractMonths),
      firstOrderProductId: pick<int?>(
        firstOrderProductId,
        this.firstOrderProductId,
      ),
      firstOrderLiters: pick<double?>(firstOrderLiters, this.firstOrderLiters),
      firstShipDate: pick<DateTime?>(firstShipDate, this.firstShipDate),
      requestedMethodCodes: requestedMethodCodes ?? this.requestedMethodCodes,
      requestedTermDays: pick<int?>(requestedTermDays, this.requestedTermDays),
      requestedLimitAmount: pick<double?>(
        requestedLimitAmount,
        this.requestedLimitAmount,
      ),
      collateralRatioPercent: pick<double?>(
        collateralRatioPercent,
        this.collateralRatioPercent,
      ),
      collateralOfferKind: pick<CollateralOfferKind?>(
        collateralOfferKind,
        this.collateralOfferKind,
      ),
      collateralOfferAmount: pick<double?>(
        collateralOfferAmount,
        this.collateralOfferAmount,
      ),
      collateralOfferNote: pick<String?>(
        collateralOfferNote,
        this.collateralOfferNote,
      ),
      currentDistributor: pick<String?>(
        currentDistributor,
        this.currentDistributor,
      ),
      currentTerminal: pick<String?>(currentTerminal, this.currentTerminal),
      currentPriceNote: pick<String?>(currentPriceNote, this.currentPriceNote),
      priceExpectation: pick<String?>(priceExpectation, this.priceExpectation),
      visitNote: pick<String?>(visitNote, this.visitNote),
      visitLatitude: pick<double?>(visitLatitude, this.visitLatitude),
      visitLongitude: pick<double?>(visitLongitude, this.visitLongitude),
      visitAccuracyMeters: pick<double?>(
        visitAccuracyMeters,
        this.visitAccuracyMeters,
      ),
      visitAt: pick<DateTime?>(visitAt, this.visitAt),
      deliveryPointName: pick<String?>(
        deliveryPointName,
        this.deliveryPointName,
      ),
      deliveryPointCity: pick<String?>(
        deliveryPointCity,
        this.deliveryPointCity,
      ),
      deliveryPointDistrict: pick<String?>(
        deliveryPointDistrict,
        this.deliveryPointDistrict,
      ),
      deliveryPointAddress: pick<String?>(
        deliveryPointAddress,
        this.deliveryPointAddress,
      ),
      contacts: contacts ?? this.contacts,
      kvkkConsent: kvkkConsent ?? this.kvkkConsent,
      kvkkConsentMethod: pick<String?>(
        kvkkConsentMethod,
        this.kvkkConsentMethod,
      ),
    );
  }

  /// Sunucu gövdesi (`LeadSaveDto`). Boş yetkili satırları atlanır.
  JsonMap toSaveJson() => {
    'id': id,
    'stationId': stationId,
    'concurrencyToken':
        concurrencyToken ?? '00000000-0000-0000-0000-000000000000',
    'companyTitle': companyTitle.trim(),
    'taxNumber': taxNumber.replaceAll(RegExp(r'\D'), ''),
    'taxOffice': _t(taxOffice),
    'city': _t(city),
    'district': _t(district),
    'address': _t(address),
    'sector': _t(sector),
    'foundedYear': foundedYear,
    'phone': _t(phone),
    'email': _t(email),
    'website': _t(website),
    'vehicleCount': vehicleCount,
    'vehicleTypes': _t(vehicleTypes),
    'hasTank': hasTank,
    'tankCapacityLiters': hasTank ? tankCapacityLiters : null,
    'products': [
      for (final p in products)
        if (p.monthlyLiters > 0 || (p.committedMonthlyLiters ?? 0) > 0)
          p.toJson(),
    ],
    'contractMonths': contractMonths,
    'firstOrderProductId': firstOrderProductId,
    'firstOrderLiters': firstOrderLiters,
    'firstShipDate': firstShipDate == null
        ? null
        : TrTime.isoDate(firstShipDate!),
    'requestedMethodCodes': requestedMethodCodes,
    'requestedTermDays': requestedTermDays,
    'requestedLimitAmount': requestedLimitAmount,
    'collateralRatioPercent': collateralRatioPercent,
    'collateralOfferKind': collateralOfferKind?.code,
    'collateralOfferAmount': collateralOfferAmount,
    'collateralOfferNote': _t(collateralOfferNote),
    'currentDistributor': _t(currentDistributor),
    'currentTerminal': _t(currentTerminal),
    'currentPriceNote': _t(currentPriceNote),
    'priceExpectation': _t(priceExpectation),
    'visitNote': _t(visitNote),
    'visitLatitude': visitLatitude,
    'visitLongitude': visitLongitude,
    'visitAccuracyMeters': visitAccuracyMeters,
    'visitAt': visitAt == null ? null : TrTime.isoDate(visitAt!),
    'deliveryPointName': _t(deliveryPointName),
    'deliveryPointCity': _t(deliveryPointCity),
    'deliveryPointDistrict': _t(deliveryPointDistrict),
    'deliveryPointAddress': _t(deliveryPointAddress),
    'contacts': [
      for (final c in contacts)
        if (!c.isEmpty) c.toJson(),
    ],
    'kvkkConsent': kvkkConsent,
    'kvkkConsentMethod': kvkkConsent ? _t(kvkkConsentMethod) : null,
  };

  /// Sihirbazın cihazda saklanan hâli (aynı gövde).
  JsonMap toJson() => {
    ...toSaveJson(),
    'contacts': [for (final c in contacts) c.toJson()],
    'products': [for (final p in products) p.toJson()],
  };

  /// İçerik parmak izi (değişiklik var mı).
  String get fingerprint => toSaveJson().toString();
}

/// Ön kayıt ayrıntısı (`LeadDetailDto`).
@immutable
class LeadDetail {
  const LeadDetail({
    required this.draft,
    required this.leadNumber,
    required this.status,
    this.statusLabel,
    this.stationTitle,
    this.salesRepName,
    this.createdByUserId,
    this.createdAt,
    this.submittedAt,
    this.kvkkConsentAt,
    this.kvkkDocumentVersion,
    this.existsElsewhere = false,
    this.customerId,
    this.convertedAt,
    this.decisionNote,
    this.approvalRequestId,
    this.canEdit = false,
    this.canSubmit = false,
    this.canCancel = false,
    this.totalMonthlyLiters = 0,
    this.firstOrderProductName,
    this.requestedMethodNames = const [],
    this.customerCode,
    this.inviteEmail,
    this.hasTaxPlate = false,
    this.attachmentCount = 0,
    this.approvalStatus,
    this.isFinanceViewer = false,
    this.canForwardToHq = false,
    this.isForwardedToHq = false,
    this.inviteExpiresAt,
    this.customerHasPortalUser = false,
    this.inviteCandidates = const [],
    this.canResendInvite = false,
  });

  factory LeadDetail.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return LeadDetail(
      draft: LeadDraft.fromJson(json),
      leadNumber: r.str('leadNumber'),
      status: r.enumOf('status', LeadStatus.fromCode),
      statusLabel: r.nonEmpty('statusLabel'),
      stationTitle: r.nonEmpty('stationTitle'),
      salesRepName: r.nonEmpty('salesRepName'),
      createdByUserId: r.nonEmpty('createdByUserId'),
      createdAt: r.dateUtc('createdAt'),
      submittedAt: r.dateUtc('submittedAt'),
      kvkkConsentAt: r.dateUtc('kvkkConsentAt'),
      kvkkDocumentVersion: r.nonEmpty('kvkkDocumentVersion'),
      existsElsewhere: r.boolean('existsElsewhere'),
      customerId: r.intOrNull('customerId'),
      convertedAt: r.dateUtc('convertedAt'),
      decisionNote: r.nonEmpty('decisionNote'),
      approvalRequestId: r.intOrNull('approvalRequestId'),
      canEdit: r.boolean('canEdit'),
      canSubmit: r.boolean('canSubmit'),
      canCancel: r.boolean('canCancel'),
      totalMonthlyLiters: r.dec('totalMonthlyLiters'),
      firstOrderProductName: r.nonEmpty('firstOrderProductName'),
      requestedMethodNames: List.unmodifiable(
        r.strings('requestedMethodNames'),
      ),
      customerCode: r.nonEmpty('customerCode'),
      inviteEmail: r.nonEmpty('inviteEmail'),
      hasTaxPlate: r.boolean('hasTaxPlate'),
      attachmentCount: r.integer('attachmentCount'),
      approvalStatus: r.intOrNull('approvalStatus') == null
          ? null
          : ApprovalStatus.fromCode(r.intOrNull('approvalStatus')),
      isFinanceViewer: r.boolean('isFinanceViewer'),
      canForwardToHq: r.boolean('canForwardToHq'),
      isForwardedToHq: r.boolean('isForwardedToHq'),
      inviteExpiresAt: r.dateTr('inviteExpiresAt'),
      customerHasPortalUser: r.boolean('customerHasPortalUser'),
      inviteCandidates: List.unmodifiable(r.strings('inviteCandidates')),
      canResendInvite: r.boolean('canResendInvite'),
    );
  }

  final LeadDraft draft;
  final String leadNumber;
  final LeadStatus status;
  final String? statusLabel;
  final String? stationTitle;
  final String? salesRepName;
  final String? createdByUserId;
  final DateTime? createdAt;
  final DateTime? submittedAt;
  final DateTime? kvkkConsentAt;
  final String? kvkkDocumentVersion;
  final bool existsElsewhere;
  final int? customerId;
  final DateTime? convertedAt;
  final String? decisionNote;
  final int? approvalRequestId;
  final bool canEdit;
  final bool canSubmit;
  final bool canCancel;
  final double totalMonthlyLiters;
  final String? firstOrderProductName;
  final List<String> requestedMethodNames;
  final String? customerCode;
  final String? inviteEmail;
  final bool hasTaxPlate;
  final int attachmentCount;
  final ApprovalStatus? approvalStatus;
  final bool isFinanceViewer;
  final bool canForwardToHq;
  final bool isForwardedToHq;
  final DateTime? inviteExpiresAt;
  final bool customerHasPortalUser;
  final List<String> inviteCandidates;
  final bool canResendInvite;

  int get id => draft.id;
  String get companyTitle => draft.companyTitle;
  String get displayStatus => statusLabel ?? status.label;
}

/// Form seçeneği (`LeadOptionDto`).
@immutable
class LeadOption {
  const LeadOption(this.value, this.text);

  factory LeadOption.fromJson(JsonReader r) =>
      LeadOption(r.str('value'), r.str('text', r.str('value')));

  final String value;
  final String text;
}

/// `GET leads/options`.
@immutable
class LeadOptions {
  const LeadOptions({
    this.products = const [],
    this.paymentMethods = const [],
    this.distributors = const [],
    this.kvkkMethods = const [],
    this.kvkkVersion = '',
    this.kvkkText = '',
    this.requiredKinds = const [AttachmentKind.taxPlate],
  });

  factory LeadOptions.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final o = r.obj('options');
    final kinds = r
        .ints('requiredKinds')
        .map(AttachmentKind.fromCode)
        .where((k) => !k.isUnknown)
        .toList();
    return LeadOptions(
      products: List.unmodifiable(o.list('products', LeadOption.fromJson)),
      paymentMethods: List.unmodifiable(
        o.list('paymentMethods', LeadOption.fromJson),
      ),
      distributors: List.unmodifiable(o.strings('distributors')),
      kvkkMethods: List.unmodifiable(o.strings('kvkkMethods')),
      kvkkVersion: r.str('kvkkVersion'),
      kvkkText: r.str('kvkkText'),
      requiredKinds: List.unmodifiable(
        kinds.isEmpty ? const [AttachmentKind.taxPlate] : kinds,
      ),
    );
  }

  final List<LeadOption> products;
  final List<LeadOption> paymentMethods;
  final List<String> distributors;
  final List<String> kvkkMethods;
  final String kvkkVersion;

  /// Web ön kayıt formundaki açık rıza cümlesinin aynısı.
  final String kvkkText;
  final List<AttachmentKind> requiredKinds;

  String productName(int? id) {
    for (final p in products) {
      if (p.value == '$id') return p.text;
    }
    return id == null ? '—' : 'Ürün #$id';
  }

  String methodName(String code) {
    for (final m in paymentMethods) {
      if (m.value == code) return m.text;
    }
    return code;
  }
}

/// VKN tekrar kontrolü (`LeadDuplicateCheckDto`).
@immutable
class LeadDuplicateCheck {
  const LeadDuplicateCheck({
    this.linkedInThisStation = false,
    this.existingCustomerCode,
    this.openLeadNumber,
    this.existsElsewhere = false,
    this.messages = const [],
    this.formatError,
  });

  factory LeadDuplicateCheck.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return LeadDuplicateCheck(
      linkedInThisStation: r.boolean('linkedInThisStation'),
      existingCustomerCode: r.nonEmpty('existingCustomerCode'),
      openLeadNumber: r.nonEmpty('openLeadNumber'),
      existsElsewhere: r.boolean('existsElsewhere'),
      messages: List.unmodifiable(r.strings('messages')),
      formatError: r.nonEmpty('formatError'),
    );
  }

  final bool linkedInThisStation;
  final String? existingCustomerCode;
  final String? openLeadNumber;
  final bool existsElsewhere;
  final List<String> messages;
  final String? formatError;

  /// Gönderimi engeller (bayide kayıtlı cari ya da açık ön kayıt).
  bool get blocksSubmit => linkedInThisStation || openLeadNumber != null;
  bool get isClean => !blocksSubmit && !existsElsewhere && formatError == null;
}

/// Kayıt sonucu (`LeadSaveResultDto`).
@immutable
class LeadSaveResult {
  const LeadSaveResult({
    required this.id,
    required this.leadNumber,
    required this.concurrencyToken,
    this.warnings = const [],
    this.status = LeadStatus.draft,
    this.created = false,
  });

  factory LeadSaveResult.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return LeadSaveResult(
      id: r.integer('id'),
      leadNumber: r.str('leadNumber'),
      concurrencyToken: r.str('concurrencyToken'),
      warnings: List.unmodifiable(r.strings('warnings')),
      status: r.enumOf('status', LeadStatus.fromCode),
      created: r.boolean('created'),
    );
  }

  final int id;
  final String leadNumber;
  final String concurrencyToken;
  final List<String> warnings;
  final LeadStatus status;
  final bool created;
}

/// Ön kayıt sayıları (`LeadStatsDto`).
@immutable
class LeadStats {
  const LeadStats({
    this.total = 0,
    this.submitted = 0,
    this.converted = 0,
    this.rejected = 0,
    this.draft = 0,
    this.inFinance = 0,
    this.cancelled = 0,
    this.conversionRatePercent,
  });

  factory LeadStats.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return LeadStats(
      total: r.integer('total'),
      submitted: r.integer('submitted'),
      converted: r.integer('converted'),
      rejected: r.integer('rejected'),
      draft: r.integer('draft'),
      inFinance: r.integer('inFinance'),
      cancelled: r.integer('cancelled'),
      conversionRatePercent: r.decOrNull('conversionRatePercent'),
    );
  }

  final int total;
  final int submitted;
  final int converted;
  final int rejected;
  final int draft;
  final int inFinance;
  final int cancelled;
  final double? conversionRatePercent;

  JsonMap toJson() => {
    'total': total,
    'submitted': submitted,
    'converted': converted,
    'rejected': rejected,
    'draft': draft,
    'inFinance': inFinance,
    'cancelled': cancelled,
    'conversionRatePercent': conversionRatePercent,
  };
}

/// Ön kayıt kuralları (web `LeadRules`, `CustomerLeadService.SubmitAsync` ile aynı).
abstract final class LeadRules {
  static const maxContacts = 10;
  static const maxProducts = 20;

  /// KVKK yöntemleri (sunucu seçenek göndermezse).
  static const kvkkMethodsFallback = [
    'Islak imzalı form',
    'Ekranda onay (tablet / telefon)',
    'E-posta ile onay',
    'SMS ile onay',
    'Sözlü (telefon kaydı)',
  ];

  /// Web `Leads/Edit.cshtml:474` açık rıza cümlesi (sunucu `kvkkText` göndermezse).
  static const kvkkTextFallback =
      'Firma yetkilisi, kişisel verilerinin cari açılışı, finansal değerlendirme (risk raporu dahil) ve '
      'iletişim amacıyla bayi ve AkaryakıtNet tarafından işlenmesine açık rıza verdi.';

  /// Basit e-posta denetimi (sunucu `LeadRules.IsEmail`).
  static bool isEmail(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return false;
    final at = v.indexOf('@');
    return at > 0 &&
        at == v.lastIndexOf('@') &&
        at < v.length - 3 &&
        v.indexOf('.', at) > at + 1 &&
        !v.endsWith('.') &&
        !v.contains(RegExp(r'\s'));
  }

  /// Finansa göndermek için eksikler (sunucu ile aynı metinler). [taxPlateReady]: vergi levhası yüklendi
  /// ya da yüklenmek üzere sırada.
  static List<String> missingForSubmit(
    LeadDraft d, {
    required bool taxPlateReady,
    required String? Function(String?) taxNumberError,
  }) {
    final missing = <String>[];
    if (d.companyTitle.trim().isEmpty) missing.add('Firma ünvanı');
    final taxError = taxNumberError(d.taxNumber);
    if (taxError != null) missing.add(taxError.replaceAll(RegExp(r'\.$'), ''));
    if ((d.taxOffice ?? '').trim().isEmpty) missing.add('Vergi dairesi');
    if ((d.city ?? '').trim().isEmpty) missing.add('İl');
    if ((d.district ?? '').trim().isEmpty) missing.add('İlçe');
    final contacts = d.contacts.where((c) => !c.isEmpty).toList();
    if (contacts.isEmpty) {
      missing.add('En az bir yetkili');
    } else if (contacts.any(
      (c) =>
          c.name.trim().isEmpty ||
          (c.phone ?? '').trim().isEmpty ||
          !isEmail(c.email),
    )) {
      missing.add('Yetkili adı, telefonu ve e-postası');
    }
    if (!d.products.any((p) => p.monthlyLiters > 0)) {
      missing.add('En az bir ürün için aylık litre');
    }
    if (!d.kvkkConsent) {
      missing.add('KVKK açık rızası');
    } else if ((d.kvkkConsentMethod ?? '').trim().isEmpty) {
      missing.add('KVKK rızasının alınma yöntemi');
    }
    if (!taxPlateReady) missing.add('Vergi levhası (Evrak)');
    return missing;
  }
}

/// Türkiye'nin 81 ili (web `LeadUi.Cities`; form önerileri).
const turkeyCities = [
  'Adana', 'Adıyaman', 'Afyonkarahisar', 'Ağrı', 'Aksaray', 'Amasya', //
  'Ankara', 'Antalya', 'Ardahan', 'Artvin', 'Aydın', 'Balıkesir', 'Bartın',
  'Batman', 'Bayburt', 'Bilecik', 'Bingöl', 'Bitlis', 'Bolu', 'Burdur',
  'Bursa', 'Çanakkale', 'Çankırı', 'Çorum', 'Denizli', 'Diyarbakır', 'Düzce',
  'Edirne', 'Elazığ', 'Erzincan', 'Erzurum', 'Eskişehir', 'Gaziantep',
  'Giresun', 'Gümüşhane', 'Hakkâri', 'Hatay', 'Iğdır', 'Isparta', 'İstanbul',
  'İzmir', 'Kahramanmaraş', 'Karabük', 'Karaman', 'Kars', 'Kastamonu',
  'Kayseri', 'Kilis', 'Kırıkkale', 'Kırklareli', 'Kırşehir', 'Kocaeli',
  'Konya', 'Kütahya', 'Malatya', 'Manisa', 'Mardin', 'Mersin', 'Muğla',
  'Muş', 'Nevşehir', 'Niğde', 'Ordu', 'Osmaniye', 'Rize', 'Sakarya', 'Samsun',
  'Şanlıurfa', 'Siirt', 'Sinop', 'Sivas', 'Şırnak', 'Tekirdağ', 'Tokat',
  'Trabzon', 'Tunceli', 'Uşak', 'Van', 'Yalova', 'Yozgat', 'Zonguldak',
];

String? _t(String? s) {
  final v = s?.trim();
  return v == null || v.isEmpty ? null : v;
}

import 'package:flutter/foundation.dart';

import '../../../core/models/models.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';

/// `GET driver/shipments?scope=` değerleri (spec B.10, `DriverShipmentScopes`).
enum DriverScope {
  /// Planlı + yolda + itirazlı (sunucu varsayılanı).
  active('active'),

  /// Bugüne planlanan (iptal hariç) + yoldaki + itirazlı.
  today('today'),

  /// Yarın ve sonrasına planlı.
  upcoming('upcoming'),

  /// Son 30 günde bildirilen, kabul edilen ya da iptal edilen (yeni önce).
  history('history');

  const DriverScope(this.query);
  final String query;
}

/// Teslimatlar sekmeleri (spec A.4 A7): Bugün / Yaklaşan / Geçmiş.
enum DriverTab {
  today('Bugün', DriverScope.today),
  upcoming('Yaklaşan', DriverScope.upcoming),
  history('Geçmiş', DriverScope.history);

  const DriverTab(this.label, this.scope);
  final String label;
  final DriverScope scope;
}

/// Teslimatlar satırı (`DriverShipmentRowDto`). Tarihler an (UTC `DateTime`); sunucu Türkiye
/// yerel `+03:00` gönderir. Pencere saatleri `HH:mm` metindir.
@immutable
class DriverShipmentRow {
  const DriverShipmentRow({
    required this.id,
    required this.code,
    required this.orderId,
    required this.orderNumber,
    required this.status,
    this.statusLabelFromServer,
    this.customerTitle,
    this.productName,
    required this.plannedLiters,
    this.deliveredLiters,
    this.scheduledAt,
    this.deliveryPointName,
    this.city,
    this.district,
    this.hasCoordinates = false,
    this.vehiclePlate,
    this.windowStart,
    this.windowEnd,
    this.disputeNote,
    this.raw = const {},
  });

  factory DriverShipmentRow.fromJson(JsonReader r) {
    final id = r.integer('id');
    return DriverShipmentRow(
      id: id,
      code: r.nonEmpty('code') ?? shipmentCode(id),
      orderId: r.integer('orderId'),
      orderNumber: r.str('orderNumber'),
      status: r.enumOf('status', ShipmentStatus.fromCode),
      statusLabelFromServer: r.nonEmpty('statusLabel'),
      customerTitle: r.nonEmpty('customerTitle'),
      productName: r.nonEmpty('productName'),
      plannedLiters: r.dec('plannedLiters'),
      deliveredLiters: r.decOrNull('deliveredLiters'),
      scheduledAt: r.dateTr('scheduledAt'),
      deliveryPointName: r.nonEmpty('deliveryPointName'),
      city: r.nonEmpty('city'),
      district: r.nonEmpty('district'),
      hasCoordinates: r.boolean('hasCoordinates'),
      vehiclePlate: r.nonEmpty('vehiclePlate'),
      windowStart: _hhmm(r.nonEmpty('windowStart')),
      windowEnd: _hhmm(r.nonEmpty('windowEnd')),
      disputeNote: r.nonEmpty('disputeNote'),
      raw: r.raw,
    );
  }

  /// "SVK-00001234" (web ve belgelerdeki kodla aynı).
  static String shipmentCode(int id) => 'SVK-${id.toString().padLeft(8, '0')}';

  final int id;
  final String code;
  final int orderId;
  final String orderNumber;
  final ShipmentStatus status;
  final String? statusLabelFromServer;
  final String? customerTitle;
  final String? productName;
  final double plannedLiters;
  final double? deliveredLiters;
  final DateTime? scheduledAt;
  final String? deliveryPointName;
  final String? city;
  final String? district;
  final bool hasCoordinates;
  final String? vehiclePlate;
  final String? windowStart;
  final String? windowEnd;
  final String? disputeNote;

  /// Sunucu gövdesi (önbelleğe olduğu gibi yazılır).
  final JsonMap raw;

  String get statusLabel => statusLabelFromServer ?? status.label;

  bool get isDisputed => status == ShipmentStatus.disputed;
  bool get isPlanned => status == ShipmentStatus.planned;
  bool get isInTransit => status == ShipmentStatus.inTransit;

  /// Şoförün işi sürüyor (yola çıkacak, yolda ya da düzeltecek).
  bool get isOpen => isPlanned || isInTransit || isDisputed;

  /// "Pendik / İstanbul".
  String? get placeLine {
    final parts = [?district, ?city];
    return parts.isEmpty ? null : parts.join(' / ');
  }

  /// "08:00–18:00"; yalnızca bir uç varsa "En erken 08:00" / "En geç 18:00".
  String? get windowLabel => formatWindow(windowStart, windowEnd);

  /// Plan anı bugünden önce ve hâlâ yola çıkılmadı.
  bool isOverdue(DateTime now) {
    final at = scheduledAt;
    return isPlanned && at != null && at.isBefore(TrTime.startOfDay(now));
  }

  static String? formatWindow(String? start, String? end) {
    if (start != null && end != null) return '$start–$end';
    if (start != null) return 'En erken $start';
    if (end != null) return 'En geç $end';
    return null;
  }

  /// `HH:mm:ss` gelirse `HH:mm`; `1.00:00:00` (24:00) → `24:00`.
  static String? _hhmm(String? v) {
    if (v == null) return null;
    if (v.startsWith('1.')) return '24:00';
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(v);
    if (m == null) return v;
    return '${m[1]!.padLeft(2, '0')}:${m[2]}';
  }

  @override
  bool operator ==(Object other) =>
      other is DriverShipmentRow &&
      other.id == id &&
      other.status == status &&
      other.deliveredLiters == deliveredLiters &&
      other.scheduledAt == scheduledAt &&
      other.disputeNote == disputeNote &&
      other.vehiclePlate == vehiclePlate;

  @override
  int get hashCode =>
      Object.hash(id, status, deliveredLiters, scheduledAt, disputeNote);
}

/// Teslim kanıtı zorunlulukları (`Mobile.Delivery*Required`).
@immutable
class DriverRequirements {
  const DriverRequirements({
    this.photo = false,
    this.signature = false,
    this.gps = false,
  });

  factory DriverRequirements.fromJson(JsonReader r) => DriverRequirements(
    photo: r.boolean('photo'),
    signature: r.boolean('signature'),
    gps: r.boolean('gps'),
  );

  final bool photo;
  final bool signature;
  final bool gps;
}

/// Şoförün bu sevkiyatta yapabilecekleri (sunucu ayrıca denetler).
@immutable
class DriverActions {
  const DriverActions({this.canStart = false, this.canDeliver = false});

  factory DriverActions.fromJson(JsonReader r) => DriverActions(
    canStart: r.boolean('canStart'),
    canDeliver: r.boolean('canDeliver'),
  );

  final bool canStart;
  final bool canDeliver;
}

/// `GET driver/shipments/{id}` (`DriverShipmentDetailDto`): satır + teslimat noktası, iletişim,
/// teslim bilgileri, ekler, zorunluluklar ve eylemler.
@immutable
class DriverShipmentDetail {
  const DriverShipmentDetail({
    required this.row,
    this.address,
    this.latitude,
    this.longitude,
    this.contactName,
    this.contactPhone,
    this.accessNotes,
    this.tankCapacityLiters,
    this.deliveryDocumentNo,
    this.recipientName,
    this.deliveryNote,
    this.signatureWaiverLabel,
    this.dispatchedAt,
    this.deliveredAt,
    this.attachments = const [],
    this.requirements = const DriverRequirements(),
    this.actions = const DriverActions(),
  });

  factory DriverShipmentDetail.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return DriverShipmentDetail(
      row: DriverShipmentRow.fromJson(r),
      address: r.nonEmpty('address'),
      latitude: r.decOrNull('latitude'),
      longitude: r.decOrNull('longitude'),
      contactName: r.nonEmpty('contactName'),
      contactPhone: r.nonEmpty('contactPhone'),
      accessNotes: r.nonEmpty('accessNotes'),
      tankCapacityLiters: r.decOrNull('tankCapacityLiters'),
      deliveryDocumentNo: r.nonEmpty('deliveryDocumentNo'),
      recipientName: r.nonEmpty('recipientName'),
      deliveryNote: r.nonEmpty('deliveryNote'),
      signatureWaiverLabel: r.nonEmpty('signatureWaiverLabel'),
      dispatchedAt: r.dateTr('dispatchedAt'),
      deliveredAt: r.dateTr('deliveredAt'),
      attachments: List.unmodifiable(
        r.list('attachments', Attachment.fromJson),
      ),
      requirements: DriverRequirements.fromJson(r.obj('requirements')),
      actions: DriverActions.fromJson(r.obj('actions')),
    );
  }

  final DriverShipmentRow row;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? contactName;
  final String? contactPhone;
  final String? accessNotes;
  final double? tankCapacityLiters;
  final String? deliveryDocumentNo;
  final String? recipientName;
  final String? deliveryNote;
  final String? signatureWaiverLabel;
  final DateTime? dispatchedAt;
  final DateTime? deliveredAt;
  final List<Attachment> attachments;
  final DriverRequirements requirements;
  final DriverActions actions;

  int get id => row.id;
  String get code => row.code;
  ShipmentStatus get status => row.status;
  bool get hasCoordinates => latitude != null && longitude != null;

  /// Teslim fotoğrafları (etkin).
  List<Attachment> get deliveryPhotos => [
    for (final a in attachments)
      if (a.kind == AttachmentKind.deliveryPhoto && a.isActive) a,
  ];

  /// Teslim imzası (etkin, en yenisi).
  Attachment? get signature {
    for (final a in attachments.reversed) {
      if (a.kind == AttachmentKind.deliverySignature && a.isActive) return a;
    }
    return null;
  }

  /// Teslim edilen − planlanan (L).
  double? get differenceLiters {
    final d = row.deliveredLiters;
    return d == null ? null : d - row.plannedLiters;
  }

  /// Tek satır adres: "Kurtköy Mah. …, Pendik / İstanbul".
  String? get fullAddress {
    final place = row.placeLine;
    final a = address;
    if (a == null) return place;
    if (place == null || a.contains(row.city ?? '\u0000')) return a;
    return '$a, $place';
  }
}

/// İmza alınamama nedenleri (`SignatureWaiverReasons`; teslim notuna önek olarak yazılır).
enum SignatureWaiverReason {
  noRecipient(
    1,
    'Alıcı yok / tanka teslim',
    'Teslim noktasında kimse yoktu; yakıt tanka boşaltıldı.',
  ),
  refused(2, 'İmzadan imtina', 'Teslim alan kişi imza atmak istemedi.'),
  other(3, 'Diğer', 'Başka bir neden; kısa bir açıklama yazın.');

  const SignatureWaiverReason(this.code, this.label, this.description);
  final int code;
  final String label;
  final String description;

  static SignatureWaiverReason? fromCode(int? code) {
    for (final r in values) {
      if (r.code == code) return r;
    }
    return null;
  }

  /// Açıklamanın üst sınırı (sunucu ile aynı).
  static const noteMaxLength = 200;
}

/// İmza alınamama seçimi (deliver `signatureWaiver`).
@immutable
class SignatureWaiver {
  const SignatureWaiver(this.reason, [this.note]);

  factory SignatureWaiver.fromJson(JsonReader r) => SignatureWaiver(
    SignatureWaiverReason.fromCode(r.intOrNull('reason')) ??
        SignatureWaiverReason.other,
    r.nonEmpty('note'),
  );

  final SignatureWaiverReason reason;
  final String? note;

  /// "Diğer – alıcı acil çıktı".
  String get text {
    final n = note?.trim();
    return n == null || n.isEmpty ? reason.label : '${reason.label} – $n';
  }

  /// Sunucu kuralı: "Diğer" için en az 3 karakter açıklama; en çok 200.
  String? validate() {
    final n = note?.trim() ?? '';
    if (reason == SignatureWaiverReason.other && n.length < 3) {
      return 'missing_note';
    }
    if (n.length > SignatureWaiverReason.noteMaxLength) return 'note_too_long';
    return null;
  }

  JsonMap toJson() => {'reason': reason.code, ...jsonEntry('note', _note)};

  String? get _note {
    final n = note?.trim();
    return n == null || n.isEmpty ? null : n;
  }

  @override
  bool operator ==(Object other) =>
      other is SignatureWaiver && other.reason == reason && other.note == note;

  @override
  int get hashCode => Object.hash(reason, note);
}

/// Cihazdan alınan konum (teslim / yola çıkış kanıtı).
@immutable
class DriverPosition {
  const DriverPosition({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.approximate = false,
    required this.capturedAt,
  });

  factory DriverPosition.fromJson(JsonReader r) => DriverPosition(
    latitude: r.dec('latitude'),
    longitude: r.dec('longitude'),
    accuracyMeters: r.decOrNull('accuracyMeters'),
    approximate: r.boolean('approximate'),
    capturedAt: r.dateUtc('capturedAt') ?? DateTime.now().toUtc(),
  );

  final double latitude;
  final double longitude;
  final double? accuracyMeters;

  /// Yalnızca yaklaşık konum izni (iOS "Hassas konum" kapalı / Android yaklaşık).
  final bool approximate;
  final DateTime capturedAt;

  /// Hassasiyet 50 m'den kötü (uyarı gösterilir).
  bool get isLowAccuracy => (accuracyMeters ?? 0) > 50;

  /// "±12 m".
  String get accuracyLabel => accuracyMeters == null
      ? 'hassasiyet bilinmiyor'
      : '±${Fmt.integer(accuracyMeters!.round())} m';

  bool isFresh(DateTime now, {Duration maxAge = const Duration(minutes: 2)}) =>
      now.difference(capturedAt) <= maxAge;

  /// Sunucu: enlem/boylam 6, doğruluk 2 ondalık.
  JsonMap toRequest() => {
    'latitude': _round(latitude, 6),
    'longitude': _round(longitude, 6),
    ...jsonEntry(
      'accuracyMeters',
      accuracyMeters == null ? null : _round(accuracyMeters!, 2),
    ),
  };

  JsonMap toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'accuracyMeters': accuracyMeters,
    'approximate': approximate,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
  };

  static double _round(double v, int digits) =>
      double.parse(v.toStringAsFixed(digits));
}

import 'package:flutter/foundation.dart';

import '../../../core/models/attachment.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/json.dart';
import '../../../core/models/shipment.dart';

/// `GET shipments` (`ShipmentListPageDto`): satırlar + durum sayaçları. Sayfalama `page`/`pageSize`.
@immutable
class ShipmentListPage {
  const ShipmentListPage({
    required this.items,
    required this.totalFiltered,
    required this.page,
    required this.pageSize,
    required this.totalPages,
    this.counts = const ShipmentCounts(),
  });

  factory ShipmentListPage.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final items = r.list('items', ShipmentListItem.fromJson);
    final pageSize = r.integer('pageSize', 25);
    final total = r.integer('totalFiltered', items.length);
    return ShipmentListPage(
      items: List.unmodifiable(items),
      totalFiltered: total,
      page: r.integer('page', 1),
      pageSize: pageSize,
      totalPages:
          r.intOrNull('totalPages') ??
          (pageSize <= 0 ? 1 : (total / pageSize).ceil()),
      counts: ShipmentCounts.fromJson(r),
    );
  }

  final List<ShipmentListItem> items;
  final int totalFiltered;
  final int page;
  final int pageSize;
  final int totalPages;
  final ShipmentCounts counts;

  bool get hasMore => page < totalPages;
}

/// Durum sayaçları (`countAll`, `countReported` …).
@immutable
class ShipmentCounts {
  const ShipmentCounts({
    this.all = 0,
    this.planned = 0,
    this.inTransit = 0,
    this.reported = 0,
    this.accepted = 0,
    this.disputed = 0,
    this.cancelled = 0,
  });

  factory ShipmentCounts.fromJson(JsonReader r) => ShipmentCounts(
    all: r.integer('countAll'),
    planned: r.integer('countPlanned'),
    inTransit: r.integer('countInTransit'),
    reported: r.integer('countReported'),
    accepted: r.integer('countAccepted'),
    disputed: r.integer('countDisputed'),
    cancelled: r.integer('countCancelled'),
  );

  final int all;
  final int planned;
  final int inTransit;
  final int reported;
  final int accepted;
  final int disputed;
  final int cancelled;

  int of(ShipmentStatus s) => switch (s) {
    ShipmentStatus.planned => planned,
    ShipmentStatus.inTransit => inTransit,
    ShipmentStatus.reported => reported,
    ShipmentStatus.accepted => accepted,
    ShipmentStatus.disputed => disputed,
    ShipmentStatus.cancelled => cancelled,
    ShipmentStatus.unknown => 0,
  };
}

/// Sevkiyatın teslimat noktası (`ShipmentDeliveryPointDto`). Pencere `HH:mm`.
@immutable
class ShipmentPlace {
  const ShipmentPlace({
    this.name,
    this.address,
    this.city,
    this.district,
    this.latitude,
    this.longitude,
    this.windowStart,
    this.windowEnd,
  });

  factory ShipmentPlace.fromJson(JsonReader r) => ShipmentPlace(
    name: r.nonEmpty('name'),
    address: r.nonEmpty('address'),
    city: r.nonEmpty('city'),
    district: r.nonEmpty('district'),
    latitude: r.decOrNull('latitude'),
    longitude: r.decOrNull('longitude'),
    windowStart: r.nonEmpty('windowStart'),
    windowEnd: r.nonEmpty('windowEnd'),
  );

  final String? name;
  final String? address;
  final String? city;
  final String? district;
  final double? latitude;
  final double? longitude;
  final String? windowStart;
  final String? windowEnd;

  bool get hasCoordinates => latitude != null && longitude != null;

  String? get cityDistrict {
    final parts = [district, city].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join(' / ');
  }

  String? get window => windowStart == null || windowEnd == null
      ? null
      : '$windowStart–$windowEnd';
}

/// Görüntüleyenin yapabilecekleri (`ShipmentMobileActionsDto`; sunucu ayrıca denetler).
@immutable
class ShipmentActions {
  const ShipmentActions({
    this.canDispatch = false,
    this.canReport = false,
    this.canReassign = false,
    this.canCancel = false,
    this.canAccept = false,
    this.canDispute = false,
    this.canAddDisputePhoto = false,
  });

  factory ShipmentActions.fromJson(JsonReader r) => ShipmentActions(
    canDispatch: r.boolean('canDispatch'),
    canReport: r.boolean('canReport'),
    canReassign: r.boolean('canReassign'),
    canCancel: r.boolean('canCancel'),
    canAccept: r.boolean('canAccept'),
    canDispute: r.boolean('canDispute'),
    canAddDisputePhoto: r.boolean('canAddDisputePhoto'),
  );

  final bool canDispatch;
  final bool canReport;
  final bool canReassign;
  final bool canCancel;
  final bool canAccept;
  final bool canDispute;
  final bool canAddDisputePhoto;
}

/// `GET shipments/{id}/detail` (`ShipmentMobileDetailDto`): sevkiyat ayrıntısı ve teslim kanıtı.
/// Tarihler Türkiye yerel (+03:00) ya da UTC (`deviceDeliveredAtUtc`); cari görünümünde iç alanlar boştur.
@immutable
class ShipmentDetail {
  const ShipmentDetail({
    required this.id,
    required this.code,
    required this.orderId,
    required this.orderNumber,
    required this.status,
    this.statusLabel,
    this.viewerSide = 'customer',
    this.stationTitle,
    this.customerTitle,
    this.productName,
    required this.plannedLiters,
    this.deliveredLiters,
    this.differenceLiters,
    this.scheduledAt,
    this.dispatchedAt,
    this.deliveredAt,
    this.deviceDeliveredAtUtc,
    this.timeSource,
    this.acceptedAt,
    this.vehiclePlate,
    this.driverName,
    this.deliveryDocumentNo,
    this.recipientName,
    this.deliveryNote,
    this.signatureWaiverLabel,
    this.disputeNote,
    this.distanceToDeliveryPointMeters,
    this.place = const ShipmentPlace(),
    this.attachments = const [],
    this.actions = const ShipmentActions(),
  });

  factory ShipmentDetail.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final id = r.integer('id');
    return ShipmentDetail(
      id: id,
      code: r.nonEmpty('code') ?? 'SVK-${id.toString().padLeft(8, '0')}',
      orderId: r.integer('orderId'),
      orderNumber: r.str('orderNumber'),
      status: r.enumOf('status', ShipmentStatus.fromCode),
      statusLabel: r.nonEmpty('statusLabel'),
      viewerSide: r.nonEmpty('viewerSide') ?? 'customer',
      stationTitle: r.nonEmpty('stationTitle'),
      customerTitle: r.nonEmpty('customerTitle'),
      productName: r.nonEmpty('productName'),
      plannedLiters: r.dec('plannedLiters'),
      deliveredLiters: r.decOrNull('deliveredLiters'),
      differenceLiters: r.decOrNull('differenceLiters'),
      scheduledAt: r.dateTr('scheduledAt'),
      dispatchedAt: r.dateTr('dispatchedAt'),
      deliveredAt: r.dateTr('deliveredAt'),
      deviceDeliveredAtUtc: r.dateUtc('deviceDeliveredAtUtc'),
      timeSource: r.nonEmpty('timeSource'),
      acceptedAt: r.dateTr('acceptedAt'),
      vehiclePlate: r.nonEmpty('vehiclePlate'),
      driverName: r.nonEmpty('driverName'),
      deliveryDocumentNo: r.nonEmpty('deliveryDocumentNo'),
      recipientName: r.nonEmpty('recipientName'),
      deliveryNote: r.nonEmpty('deliveryNote'),
      signatureWaiverLabel: r.nonEmpty('signatureWaiverLabel'),
      disputeNote: r.nonEmpty('disputeNote'),
      distanceToDeliveryPointMeters: r.intOrNull(
        'distanceToDeliveryPointMeters',
      ),
      place: ShipmentPlace.fromJson(r.obj('deliveryPoint')),
      attachments: List.unmodifiable(
        r.list('attachments', Attachment.fromJson).where((a) => a.isActive),
      ),
      actions: ShipmentActions.fromJson(r.obj('actions')),
    );
  }

  final int id;
  final String code;
  final int orderId;
  final String orderNumber;
  final ShipmentStatus status;
  final String? statusLabel;

  /// `bayi` | `customer` | `platform`.
  final String viewerSide;
  final String? stationTitle;
  final String? customerTitle;
  final String? productName;
  final double plannedLiters;
  final double? deliveredLiters;
  final double? differenceLiters;
  final DateTime? scheduledAt;
  final DateTime? dispatchedAt;
  final DateTime? deliveredAt;
  final DateTime? deviceDeliveredAtUtc;

  /// `device` | `server` | null (teslim yok).
  final String? timeSource;
  final DateTime? acceptedAt;
  final String? vehiclePlate;
  final String? driverName;

  /// İrsaliye no (şoförün referansı).
  final String? deliveryDocumentNo;
  final String? recipientName;
  final String? deliveryNote;
  final String? signatureWaiverLabel;
  final String? disputeNote;
  final int? distanceToDeliveryPointMeters;
  final ShipmentPlace place;
  final List<Attachment> attachments;
  final ShipmentActions actions;

  /// Teslim bildirilmiş (kanıt kartı gösterilir).
  bool get isDelivered =>
      deliveredLiters != null &&
      (status == ShipmentStatus.reported ||
          status == ShipmentStatus.accepted ||
          status == ShipmentStatus.disputed);

  double? get difference =>
      differenceLiters ??
      (deliveredLiters == null ? null : deliveredLiters! - plannedLiters);

  List<Attachment> get deliveryPhotos =>
      attachments.where((a) => a.kind == AttachmentKind.deliveryPhoto).toList();

  Attachment? get signature => attachments
      .where((a) => a.kind == AttachmentKind.deliverySignature)
      .firstOrNull;

  List<Attachment> get disputePhotos =>
      attachments.where((a) => a.kind == AttachmentKind.disputePhoto).toList();

  List<Attachment> get otherFiles =>
      attachments.where((a) => a.kind == AttachmentKind.other).toList();
}

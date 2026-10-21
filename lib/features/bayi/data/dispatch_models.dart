import 'package:flutter/foundation.dart';

import '../../../core/models/models.dart';
import 'bayi_json.dart';

/// Pano teslim kovası (`ShipmentBoardBucket`).
enum BoardBucket {
  overdue(0, 'Gecikmiş'),
  today(1, 'Bugün'),
  tomorrow(2, 'Yarın'),
  thisWeek(3, 'Bu hafta'),
  later(4, 'Daha sonra');

  const BoardBucket(this.code, this.label);
  final int code;
  final String label;

  static BoardBucket fromCode(int? code) => switch (code) {
    0 => overdue,
    1 => today,
    2 => tomorrow,
    3 => thisWeek,
    _ => later,
  };
}

/// Planlanacak litresi kalan onaylı sipariş (`ShipmentBoardOrderRow`; tarihler Türkiye yerel).
@immutable
class BoardOrder {
  const BoardOrder({
    required this.orderId,
    required this.orderNumber,
    this.requestedDeliveryDate,
    this.quoteDeliveryDate,
    this.quantityLiters = 0,
    this.allocatedLiters = 0,
    this.acceptedLiters = 0,
    this.openShipmentCount = 0,
    this.productName = '',
    this.customerTitle = '',
    this.deliveryPointName,
    this.deliveryCity,
    this.deliveryDistrict,
    this.windowStart,
    this.windowEnd,
    this.tankCapacityLiters,
    this.contactName,
    this.contactPhone,
    this.bucket = BoardBucket.later,
    this.remainingLiters = 0,
  });

  factory BoardOrder.fromJson(JsonReader r) {
    final quantity = r.dec('quantityLiters');
    final allocated = r.dec('allocatedLiters');
    final remaining =
        r.decOrNull('remainingLiters') ??
        (quantity - allocated < 0 ? 0.0 : quantity - allocated);
    return BoardOrder(
      orderId: r.integer('orderId'),
      orderNumber: r.str('orderNumber'),
      requestedDeliveryDate: r.dateTr('requestedDeliveryDate'),
      quoteDeliveryDate: r.dateTr('quoteDeliveryDate'),
      quantityLiters: quantity,
      allocatedLiters: allocated,
      acceptedLiters: r.dec('acceptedLiters'),
      openShipmentCount: r.integer('openShipmentCount'),
      productName: r.str('productName'),
      customerTitle: r.str('customerTitle'),
      deliveryPointName: r.nonEmpty('deliveryPointName'),
      deliveryCity: r.nonEmpty('deliveryCity'),
      deliveryDistrict: r.nonEmpty('deliveryDistrict'),
      windowStart: BayiJson.windowTime(r.strOrNull('deliveryWindowStart')),
      windowEnd: BayiJson.windowTime(r.strOrNull('deliveryWindowEnd')),
      tankCapacityLiters: r.decOrNull('tankCapacityLiters'),
      contactName: r.nonEmpty('contactName'),
      contactPhone: r.nonEmpty('contactPhone'),
      bucket: BoardBucket.fromCode(r.intOrNull('bucket')),
      remainingLiters: remaining,
    );
  }

  final int orderId;
  final String orderNumber;
  final DateTime? requestedDeliveryDate;
  final DateTime? quoteDeliveryDate;
  final double quantityLiters;
  final double allocatedLiters;
  final double acceptedLiters;
  final int openShipmentCount;
  final String productName;
  final String customerTitle;
  final String? deliveryPointName;
  final String? deliveryCity;
  final String? deliveryDistrict;
  final String? windowStart;
  final String? windowEnd;
  final double? tankCapacityLiters;
  final String? contactName;
  final String? contactPhone;
  final BoardBucket bucket;
  final double remainingLiters;

  /// Teklif teslim günü (yoksa istenen gün).
  DateTime? get deliveryDate => quoteDeliveryDate ?? requestedDeliveryDate;
  String? get window => BayiJson.windowLabel(windowStart, windowEnd);
}

/// Açık (planlı / yolda) sevkiyat (`ShipmentBoardShipmentRow`).
@immutable
class BoardShipment {
  const BoardShipment({
    required this.id,
    required this.orderId,
    required this.orderNumber,
    required this.status,
    this.scheduledAt,
    this.plannedLiters = 0,
    this.vehiclePlate = '',
    this.driverName = '',
    this.productName = '',
    this.customerTitle = '',
    this.deliveryPointName,
    this.deliveryCity,
    this.windowStart,
    this.windowEnd,
    this.driverUserId,
    this.driverAccountName,
    this.isAppDriver = false,
  });

  factory BoardShipment.fromJson(JsonReader r) => BoardShipment(
    id: r.integer('id'),
    orderId: r.integer('orderId'),
    orderNumber: r.str('orderNumber'),
    status: r.enumOf('status', ShipmentStatus.fromCode),
    scheduledAt: r.dateTr('scheduledAt'),
    plannedLiters: r.dec('plannedLiters'),
    vehiclePlate: r.str('vehiclePlate'),
    driverName: r.str('driverName'),
    productName: r.str('productName'),
    customerTitle: r.str('customerTitle'),
    deliveryPointName: r.nonEmpty('deliveryPointName'),
    deliveryCity: r.nonEmpty('deliveryCity'),
    windowStart: BayiJson.windowTime(r.strOrNull('deliveryWindowStart')),
    windowEnd: BayiJson.windowTime(r.strOrNull('deliveryWindowEnd')),
    driverUserId: r.nonEmpty('driverUserId'),
    driverAccountName: r.nonEmpty('driverAccountName'),
    isAppDriver: r.boolean('isAppDriver'),
  );

  final int id;
  final int orderId;
  final String orderNumber;
  final ShipmentStatus status;
  final DateTime? scheduledAt;
  final double plannedLiters;
  final String vehiclePlate;
  final String driverName;
  final String productName;
  final String customerTitle;
  final String? deliveryPointName;
  final String? deliveryCity;
  final String? windowStart;
  final String? windowEnd;

  /// Atanan şoför hesabı (yoksa sevkiyat şoförün "Teslimatlarım"ında görünmez).
  final String? driverUserId;
  final String? driverAccountName;

  /// Atanan şoförün uygulamada açık oturumu var.
  final bool isAppDriver;

  String get code => 'SVK-${id.toString().padLeft(8, '0')}';
  bool get hasDriverAccount => driverUserId != null;
}

/// Kova özeti (kesilmemiş sayı ve litre).
@immutable
class BoardBucketSummary {
  const BoardBucketSummary({
    required this.bucket,
    this.count = 0,
    this.liters = 0,
  });

  factory BoardBucketSummary.fromJson(JsonReader r) => BoardBucketSummary(
    bucket: BoardBucket.fromCode(r.intOrNull('bucket')),
    count: r.integer('count'),
    liters: r.dec('liters'),
  );

  final BoardBucket bucket;
  final int count;
  final double liters;
}

/// `GET shipments/board` (`ShipmentBoardData`).
@immutable
class ShipmentBoard {
  const ShipmentBoard({
    this.stationTitle = '',
    this.orders = const [],
    this.buckets = const [],
    this.orderTotal = 0,
    this.orderTotalLiters = 0,
    this.shipments = const [],
    this.shipmentsTruncated = false,
    this.earlierShipmentsTruncated = false,
    this.plannedCount = 0,
    this.plannedLiters = 0,
    this.inTransitCount = 0,
    this.inTransitLiters = 0,
    this.unassignedCount = 0,
  });

  factory ShipmentBoard.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final buckets = r.list('buckets', BoardBucketSummary.fromJson);
    return ShipmentBoard(
      stationTitle: r.obj('station').str('title'),
      orders: List.unmodifiable(r.list('orders', BoardOrder.fromJson)),
      buckets: List.unmodifiable(buckets),
      orderTotal:
          r.intOrNull('orderTotal') ??
          buckets.fold<int>(0, (sum, b) => sum + b.count),
      orderTotalLiters:
          r.decOrNull('orderTotalLiters') ??
          buckets.fold<double>(0, (sum, b) => sum + b.liters),
      shipments: List.unmodifiable(r.list('shipments', BoardShipment.fromJson)),
      shipmentsTruncated: r.boolean('shipmentsTruncated'),
      earlierShipmentsTruncated: r.boolean('earlierShipmentsTruncated'),
      plannedCount: r.integer('plannedCount'),
      plannedLiters: r.dec('plannedLiters'),
      inTransitCount: r.integer('inTransitCount'),
      inTransitLiters: r.dec('inTransitLiters'),
      unassignedCount: r.integer('unassignedCount'),
    );
  }

  final String stationTitle;
  final List<BoardOrder> orders;
  final List<BoardBucketSummary> buckets;
  final int orderTotal;
  final double orderTotalLiters;
  final List<BoardShipment> shipments;
  final bool shipmentsTruncated;
  final bool earlierShipmentsTruncated;
  final int plannedCount;
  final double plannedLiters;
  final int inTransitCount;
  final double inTransitLiters;
  final int unassignedCount;

  List<BoardOrder> ordersIn(BoardBucket b) =>
      orders.where((o) => o.bucket == b).toList();

  BoardBucketSummary? summaryOf(BoardBucket b) {
    for (final s in buckets) {
      if (s.bucket == b) return s;
    }
    return null;
  }
}

/// Plaka / sürücü önerisi.
@immutable
class BoardSuggestion {
  const BoardSuggestion({required this.value, this.pair});

  factory BoardSuggestion.fromJson(JsonReader r) =>
      BoardSuggestion(value: r.str('value'), pair: r.nonEmpty('pair'));

  final String value;

  /// Plaka için son sürücü; sürücü için son plaka.
  final String? pair;
}

/// `GET shipments/board/suggestions`.
@immutable
class BoardSuggestions {
  const BoardSuggestions({this.plates = const [], this.drivers = const []});

  static const empty = BoardSuggestions();

  factory BoardSuggestions.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return BoardSuggestions(
      plates: List.unmodifiable(
        r.list('plates', BoardSuggestion.fromJson).where((s) => s.value != ''),
      ),
      drivers: List.unmodifiable(
        r.list('drivers', BoardSuggestion.fromJson).where((s) => s.value != ''),
      ),
    );
  }

  final List<BoardSuggestion> plates;
  final List<BoardSuggestion> drivers;
}

/// `GET stations/me/drivers` satırı (`StationDriverDto`).
@immutable
class StationDriver {
  const StationDriver({
    required this.userId,
    required this.displayName,
    this.phone,
    this.isDriverRole = false,
    this.hasActiveDevice = false,
    this.activeShipments = 0,
  });

  factory StationDriver.fromJson(JsonReader r) => StationDriver(
    userId: r.str('userId'),
    displayName: r.str('displayName'),
    phone: r.nonEmpty('phone'),
    isDriverRole: r.boolean('isDriverRole'),
    hasActiveDevice: r.boolean('hasActiveDevice'),
    activeShipments: r.integer('activeShipments'),
  );

  final String userId;
  final String displayName;
  final String? phone;

  /// Şoför rolü (shipment.ownOnly).
  final bool isDriverRole;

  /// Uygulamada açık oturumu var ("uygulamada" rozeti).
  final bool hasActiveDevice;
  final int activeShipments;
}

/// `GET shipments` (`ShipmentListPageDto`).
@immutable
class ShipmentListPage {
  const ShipmentListPage({
    this.items = const [],
    this.totalFiltered = 0,
    this.page = 1,
    this.pageSize = 25,
    this.totalPages = 1,
    this.countAll = 0,
    this.countPlanned = 0,
    this.countInTransit = 0,
    this.countReported = 0,
    this.countAccepted = 0,
    this.countDisputed = 0,
    this.countCancelled = 0,
  });

  factory ShipmentListPage.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final total = r.integer('totalFiltered');
    final size = r.integer('pageSize', 25);
    return ShipmentListPage(
      items: List.unmodifiable(r.list('items', ShipmentListItem.fromJson)),
      totalFiltered: total,
      page: r.integer('page', 1),
      pageSize: size,
      totalPages:
          r.intOrNull('totalPages') ??
          (size <= 0 || total <= size ? 1 : (total / size).ceil()),
      countAll: r.integer('countAll'),
      countPlanned: r.integer('countPlanned'),
      countInTransit: r.integer('countInTransit'),
      countReported: r.integer('countReported'),
      countAccepted: r.integer('countAccepted'),
      countDisputed: r.integer('countDisputed'),
      countCancelled: r.integer('countCancelled'),
    );
  }

  final List<ShipmentListItem> items;
  final int totalFiltered;
  final int page;
  final int pageSize;
  final int totalPages;
  final int countAll;
  final int countPlanned;
  final int countInTransit;
  final int countReported;
  final int countAccepted;
  final int countDisputed;
  final int countCancelled;

  bool get hasMore => page < totalPages;

  int countOf(ShipmentStatus s) => switch (s) {
    ShipmentStatus.planned => countPlanned,
    ShipmentStatus.inTransit => countInTransit,
    ShipmentStatus.reported => countReported,
    ShipmentStatus.accepted => countAccepted,
    ShipmentStatus.disputed => countDisputed,
    ShipmentStatus.cancelled => countCancelled,
    ShipmentStatus.unknown => 0,
  };
}

/// Sevkiyatlar listesi süzgeci (`GET shipments` sorgusu).
@immutable
class ShipmentListFilter {
  const ShipmentListFilter({
    this.statuses = const {},
    this.hasDispute = false,
    this.todayLoadings = false,
    this.scheduledFrom,
    this.scheduledTo,
    this.search = '',
  });

  /// Depo: bugünkü yüklemeler (bugün planlı ya da yolda).
  static ShipmentListFilter todayLoadingsFilter() =>
      const ShipmentListFilter(todayLoadings: true);

  final Set<ShipmentStatus> statuses;
  final bool hasDispute;

  /// Bugün planlanan ve yola çıkacak / çıkmış sevkiyatlar (depo yükleme listesi).
  final bool todayLoadings;
  final DateTime? scheduledFrom;
  final DateTime? scheduledTo;
  final String search;

  bool get isFiltered =>
      statuses.isNotEmpty ||
      hasDispute ||
      todayLoadings ||
      scheduledFrom != null ||
      scheduledTo != null ||
      search.trim().isNotEmpty;

  ShipmentListFilter copyWith({
    Set<ShipmentStatus>? statuses,
    bool? hasDispute,
    bool? todayLoadings,
    Object? scheduledFrom = _keep,
    Object? scheduledTo = _keep,
    String? search,
  }) => ShipmentListFilter(
    statuses: statuses ?? this.statuses,
    hasDispute: hasDispute ?? this.hasDispute,
    todayLoadings: todayLoadings ?? this.todayLoadings,
    scheduledFrom: scheduledFrom == _keep
        ? this.scheduledFrom
        : scheduledFrom as DateTime?,
    scheduledTo: scheduledTo == _keep
        ? this.scheduledTo
        : scheduledTo as DateTime?,
    search: search ?? this.search,
  );

  /// Sunucu sorgusu. "Bugünkü yüklemeler": bugün + Planlandı / Yolda, plan saatine göre.
  Map<String, dynamic> toQuery({
    required int page,
    required int pageSize,
    required DateTime today,
  }) {
    final loading = todayLoadings;
    final from = loading ? today : scheduledFrom;
    final to = loading ? today : scheduledTo;
    final st = loading
        ? {ShipmentStatus.planned, ShipmentStatus.inTransit}
        : statuses;
    return {
      'page': page,
      'pageSize': pageSize,
      'statuses': [for (final s in st) s.code],
      'hasDispute': hasDispute ? true : null,
      'scheduledFrom': from == null ? null : BayiJson.isoDate(from),
      'scheduledTo': to == null ? null : BayiJson.isoDate(to),
      'search': search.trim(),
      // ShipmentSort: 1 ScheduledAsc (yükleme sırası), 0 IdDesc (yeni önce).
      'sort': loading ? 1 : null,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is ShipmentListFilter &&
      setEquals(other.statuses, statuses) &&
      other.hasDispute == hasDispute &&
      other.todayLoadings == todayLoadings &&
      other.scheduledFrom == scheduledFrom &&
      other.scheduledTo == scheduledTo &&
      other.search == search;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(statuses),
    hasDispute,
    todayLoadings,
    scheduledFrom,
    scheduledTo,
    search,
  );
}

const Object _keep = Object();

/// Sevkiyat ayrıntısının teslimat noktası.
@immutable
class ShipmentDetailPoint {
  const ShipmentDetailPoint({
    this.name,
    this.address,
    this.city,
    this.district,
    this.latitude,
    this.longitude,
    this.windowStart,
    this.windowEnd,
  });

  factory ShipmentDetailPoint.fromJson(JsonReader r) => ShipmentDetailPoint(
    name: r.nonEmpty('name'),
    address: r.nonEmpty('address'),
    city: r.nonEmpty('city'),
    district: r.nonEmpty('district'),
    latitude: r.decOrNull('latitude'),
    longitude: r.decOrNull('longitude'),
    windowStart: BayiJson.windowTime(r.strOrNull('windowStart')),
    windowEnd: BayiJson.windowTime(r.strOrNull('windowEnd')),
  );

  final String? name;
  final String? address;
  final String? city;
  final String? district;
  final double? latitude;
  final double? longitude;
  final String? windowStart;
  final String? windowEnd;

  String? get window => BayiJson.windowLabel(windowStart, windowEnd);
  String? get place {
    final p = [?district, ?city].join(' / ');
    return p.isEmpty ? null : p;
  }

  bool get canOpenMap => latitude != null && longitude != null;
}

/// Ayrıntıda görüntüleyenin yapabilecekleri (sunucu ayrıca denetler).
@immutable
class ShipmentDetailActions {
  const ShipmentDetailActions({
    this.canDispatch = false,
    this.canReport = false,
    this.canReassign = false,
    this.canCancel = false,
  });

  factory ShipmentDetailActions.fromJson(JsonReader r) => ShipmentDetailActions(
    canDispatch: r.boolean('canDispatch'),
    canReport: r.boolean('canReport'),
    canReassign: r.boolean('canReassign'),
    canCancel: r.boolean('canCancel'),
  );

  final bool canDispatch;
  final bool canReport;
  final bool canReassign;
  final bool canCancel;
}

/// `GET shipments/{id}/detail` (`ShipmentMobileDetailDto`; tarihler +03:00).
@immutable
class ShipmentDetail {
  const ShipmentDetail({
    required this.id,
    required this.code,
    required this.orderId,
    required this.orderNumber,
    required this.status,
    this.statusLabel,
    this.viewerSide = 'bayi',
    this.stationTitle,
    this.customerTitle,
    this.productName,
    this.plannedLiters = 0,
    this.deliveredLiters,
    this.differenceLiters,
    this.scheduledAt,
    this.dispatchedAt,
    this.deliveredAt,
    this.timeSource,
    this.acceptedAt,
    this.vehiclePlate,
    this.driverUserId,
    this.driverName,
    this.driverAccountName,
    this.isAppDriver = false,
    this.deliveryDocumentNo,
    this.recipientName,
    this.deliveryNote,
    this.signatureWaiverLabel,
    this.disputeNote,
    this.distanceToDeliveryPointMeters,
    this.deliveredAccuracyMeters,
    this.reportedByName,
    this.deliveryPoint = const ShipmentDetailPoint(),
    this.attachments = const [],
    this.actions = const ShipmentDetailActions(),
  });

  factory ShipmentDetail.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return ShipmentDetail(
      id: r.integer('id'),
      code:
          r.nonEmpty('code') ??
          'SVK-${r.integer('id').toString().padLeft(8, '0')}',
      orderId: r.integer('orderId'),
      orderNumber: r.str('orderNumber'),
      status: r.enumOf('status', ShipmentStatus.fromCode),
      statusLabel: r.nonEmpty('statusLabel'),
      viewerSide: r.str('viewerSide', 'bayi'),
      stationTitle: r.nonEmpty('stationTitle'),
      customerTitle: r.nonEmpty('customerTitle'),
      productName: r.nonEmpty('productName'),
      plannedLiters: r.dec('plannedLiters'),
      deliveredLiters: r.decOrNull('deliveredLiters'),
      differenceLiters: r.decOrNull('differenceLiters'),
      scheduledAt: r.dateTr('scheduledAt'),
      dispatchedAt: r.dateTr('dispatchedAt'),
      deliveredAt: r.dateTr('deliveredAt'),
      timeSource: r.nonEmpty('timeSource'),
      acceptedAt: r.dateTr('acceptedAt'),
      vehiclePlate: r.nonEmpty('vehiclePlate'),
      driverUserId: r.nonEmpty('driverUserId'),
      driverName: r.nonEmpty('driverName'),
      driverAccountName: r.nonEmpty('driverAccountName'),
      isAppDriver: r.boolean('isAppDriver'),
      deliveryDocumentNo: r.nonEmpty('deliveryDocumentNo'),
      recipientName: r.nonEmpty('recipientName'),
      deliveryNote: r.nonEmpty('deliveryNote'),
      signatureWaiverLabel: r.nonEmpty('signatureWaiverLabel'),
      disputeNote: r.nonEmpty('disputeNote'),
      distanceToDeliveryPointMeters: r.intOrNull(
        'distanceToDeliveryPointMeters',
      ),
      deliveredAccuracyMeters: r.decOrNull('deliveredAccuracyMeters'),
      reportedByName: r.nonEmpty('reportedByName'),
      deliveryPoint: ShipmentDetailPoint.fromJson(r.obj('deliveryPoint')),
      attachments: List.unmodifiable(
        r.list('attachments', Attachment.fromJson),
      ),
      actions: ShipmentDetailActions.fromJson(r.obj('actions')),
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

  /// `device` | `server` | null (teslim yok).
  final String? timeSource;
  final DateTime? acceptedAt;
  final String? vehiclePlate;
  final String? driverUserId;
  final String? driverName;
  final String? driverAccountName;
  final bool isAppDriver;
  final String? deliveryDocumentNo;
  final String? recipientName;
  final String? deliveryNote;
  final String? signatureWaiverLabel;
  final String? disputeNote;
  final int? distanceToDeliveryPointMeters;
  final double? deliveredAccuracyMeters;
  final String? reportedByName;
  final ShipmentDetailPoint deliveryPoint;
  final List<Attachment> attachments;
  final ShipmentDetailActions actions;

  bool get hasDelivery => deliveredLiters != null;

  /// Teslim kanıtı ekleri (fotoğraf, imza) ve itiraz fotoğrafları.
  List<Attachment> get proofAttachments => [
    for (final a in attachments)
      if (a.kind != AttachmentKind.disputePhoto) a,
  ];
  List<Attachment> get disputeAttachments => [
    for (final a in attachments)
      if (a.kind == AttachmentKind.disputePhoto) a,
  ];

  /// Gösterilecek şoför adı (plan adı, yoksa hesap adı).
  String? get driverLabel => driverName ?? driverAccountName;
}

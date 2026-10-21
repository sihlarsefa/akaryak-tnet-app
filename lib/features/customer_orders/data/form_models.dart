import 'package:flutter/foundation.dart';

import '../../../core/models/models.dart';
import '../../../core/utils/format.dart';

/// .NET `TimeSpan` JSON'u (`08:00:00`, gün sonu `1.00:00:00`) ya da `HH:mm` → dakika (0..1440).
int? parseTimeOfDayMinutes(Object? raw) {
  final s = raw?.toString().trim();
  if (s == null || s.isEmpty) return null;
  final m = RegExp(
    r'^(?:(\d+)\.)?(\d{1,2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?$',
  ).firstMatch(s);
  if (m == null) return null;
  final days = int.tryParse(m[1] ?? '0') ?? 0;
  final h = int.parse(m[2]!);
  final min = int.parse(m[3]!);
  final total = days * 1440 + h * 60 + min;
  return total < 0 || total > 1440 ? null : total;
}

/// Dakika → `HH:mm` (1440 → `24:00`).
String formatTimeOfDay(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// Katalog ürünü (`ProductDto`).
@immutable
class ProductOption {
  const ProductOption({
    required this.id,
    required this.name,
    this.code = '',
    this.unit = 'Litre',
    this.sortOrder = 0,
  });

  factory ProductOption.fromJson(JsonReader r) => ProductOption(
    id: r.integer('id'),
    name: r.str('name'),
    code: r.str('code'),
    unit: r.str('unit', 'Litre'),
    sortOrder: r.integer('sortOrder'),
  );

  final int id;
  final String name;
  final String code;
  final String unit;
  final int sortOrder;

  JsonMap toJson() => {
    'id': id,
    'name': name,
    'code': code,
    'unit': unit,
    'sortOrder': sortOrder,
    'isActive': true,
  };
}

/// Teslimat noktası (`DeliveryPointDetailsDto`): pencere, tank, erişim notları, konum.
@immutable
class DeliveryPointOption {
  const DeliveryPointOption({
    required this.id,
    required this.name,
    this.city = '',
    this.district = '',
    this.address = '',
    this.isActive = true,
    this.latitude,
    this.longitude,
    this.contactName,
    this.contactPhone,
    this.windowStartMinutes,
    this.windowEndMinutes,
    this.tankCapacityLiters,
    this.accessNotes,
  });

  factory DeliveryPointOption.fromJson(JsonReader r) => DeliveryPointOption(
    id: r.integer('id'),
    name: r.str('name'),
    city: r.str('city'),
    district: r.str('district'),
    address: r.str('address'),
    isActive: r.boolean('isActive', true),
    latitude: r.decOrNull('latitude'),
    longitude: r.decOrNull('longitude'),
    contactName: r.nonEmpty('contactName'),
    contactPhone: r.nonEmpty('contactPhone'),
    windowStartMinutes: parseTimeOfDayMinutes(
      r['deliveryWindowStart'] ?? r['windowStart'],
    ),
    windowEndMinutes: parseTimeOfDayMinutes(
      r['deliveryWindowEnd'] ?? r['windowEnd'],
    ),
    tankCapacityLiters: r.decOrNull('tankCapacityLiters'),
    accessNotes: r.nonEmpty('accessNotes'),
  );

  final int id;
  final String name;
  final String city;
  final String district;
  final String address;
  final bool isActive;
  final double? latitude;
  final double? longitude;
  final String? contactName;
  final String? contactPhone;
  final int? windowStartMinutes;
  final int? windowEndMinutes;
  final double? tankCapacityLiters;
  final String? accessNotes;

  bool get hasLocation => latitude != null && longitude != null;

  /// `08:00–18:00`; pencere yoksa null.
  String? get windowLabel {
    final s = windowStartMinutes;
    final e = windowEndMinutes;
    if (s == null && e == null) return null;
    if (s != null && e != null) {
      return '${formatTimeOfDay(s)}–${formatTimeOfDay(e)}';
    }
    if (s != null) return '${formatTimeOfDay(s)} sonrası';
    return '${formatTimeOfDay(e!)} öncesi';
  }

  /// `Pendik / İstanbul`.
  String get place =>
      [district, city].where((s) => s.trim().isNotEmpty).join(' / ');

  /// Tek satır adres: `Kurtköy Mah. …, Pendik / İstanbul`.
  String get fullAddress =>
      [address, place].where((s) => s.trim().isNotEmpty).join(', ');

  JsonMap toJson() => {
    'id': id,
    'name': name,
    'city': city,
    'district': district,
    'address': address,
    'isActive': isActive,
    'latitude': latitude,
    'longitude': longitude,
    'contactName': contactName,
    'contactPhone': contactPhone,
    'deliveryWindowStart': windowStartMinutes == null
        ? null
        : '${formatTimeOfDay(windowStartMinutes!)}:00',
    'deliveryWindowEnd': windowEndMinutes == null
        ? null
        : '${formatTimeOfDay(windowEndMinutes!)}:00',
    'tankCapacityLiters': tankCapacityLiters,
    'accessNotes': accessNotes,
  };
}

/// Şablon listesi satırı (`OrderTemplateListItemDto`; tarihler UTC).
@immutable
class TemplateListItem {
  const TemplateListItem({
    required this.id,
    required this.name,
    this.lineCount = 0,
    this.totalLiters = 0,
    this.summary = '',
    this.lastUsedAt,
    this.createdAt,
  });

  factory TemplateListItem.fromJson(JsonReader r) => TemplateListItem(
    id: r.integer('id'),
    name: r.str('name'),
    lineCount: r.integer('lineCount'),
    totalLiters: r.dec('totalLiters'),
    summary: r.str('summary'),
    lastUsedAt: r.dateUtc('lastUsedAt'),
    createdAt: r.dateUtc('createdAt'),
  );

  final int id;
  final String name;
  final int lineCount;
  final double totalLiters;

  /// "Motorin 10.000 L, 2 nokta".
  final String summary;
  final DateTime? lastUsedAt;
  final DateTime? createdAt;

  String get subtitle => summary.isNotEmpty
      ? summary
      : '$lineCount satır, ${Fmt.liters(totalLiters)}';
}

/// Şablon satırı (`OrderTemplateLineDto`).
@immutable
class TemplateLine {
  const TemplateLine({
    required this.productId,
    required this.deliveryPointId,
    required this.quantityLiters,
    this.productName = '',
    this.deliveryPointName = '',
    this.stationId,
    this.stationTitle,
    this.isAvailable = true,
    this.unavailableReason,
  });

  factory TemplateLine.fromJson(JsonReader r) => TemplateLine(
    productId: r.integer('productId'),
    deliveryPointId: r.integer('deliveryPointId'),
    quantityLiters: r.dec('quantityLiters'),
    productName: r.str('productName'),
    deliveryPointName: r.str('deliveryPointName'),
    stationId: r.intOrNull('stationId'),
    stationTitle: r.nonEmpty('stationTitle'),
    isAvailable: r.boolean('isAvailable', true),
    unavailableReason: r.nonEmpty('unavailableReason'),
  );

  final int productId;
  final int deliveryPointId;
  final double quantityLiters;
  final String productName;
  final String deliveryPointName;
  final int? stationId;
  final String? stationTitle;
  final bool isAvailable;
  final String? unavailableReason;
}

/// Şablon (`OrderTemplateDto`). Id 0 = kaydedilmemiş taslak (`from-order`).
@immutable
class OrderTemplate {
  const OrderTemplate({
    required this.id,
    required this.name,
    this.lines = const [],
    this.lastUsedAt,
  });

  factory OrderTemplate.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return OrderTemplate(
      id: r.integer('id'),
      name: r.str('name'),
      lines: List.unmodifiable(r.list('lines', TemplateLine.fromJson)),
      lastUsedAt: r.dateUtc('lastUsedAt'),
    );
  }

  final int id;
  final String name;
  final List<TemplateLine> lines;
  final DateTime? lastUsedAt;
}

/// `GET catalog/order-form` (`CustomerOrderFormOptionsDto`).
@immutable
class OrderFormOptions {
  const OrderFormOptions({
    this.customerId = 0,
    this.linkedStationId,
    this.linkedStationTitle,
    this.products = const [],
    this.deliveryPoints = const [],
    this.templates = const [],
  });

  factory OrderFormOptions.fromJson(Object? json) {
    final r = JsonReader.of(json);
    final products = r.list('products', ProductOption.fromJson)
      ..sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    return OrderFormOptions(
      customerId: r.integer('customerId'),
      linkedStationId: r.intOrNull('linkedStationId'),
      linkedStationTitle: r.nonEmpty('linkedStationTitle'),
      products: List.unmodifiable(products),
      deliveryPoints: List.unmodifiable(
        r
            .list('deliveryPoints', DeliveryPointOption.fromJson)
            .where((p) => p.isActive),
      ),
      templates: List.unmodifiable(
        r.list('templates', TemplateListItem.fromJson),
      ),
    );
  }

  final int customerId;
  final int? linkedStationId;
  final String? linkedStationTitle;
  final List<ProductOption> products;
  final List<DeliveryPointOption> deliveryPoints;
  final List<TemplateListItem> templates;

  ProductOption? product(int? id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  DeliveryPointOption? point(int? id) {
    for (final p in deliveryPoints) {
      if (p.id == id) return p;
    }
    return null;
  }
}

/// Şirket içi sipariş talebi (`CustomerOrderRequestDto`): "Başarısız satırları yeni siparişe aktar"
/// ve sonuç doğrulaması için gereken alanlar.
@immutable
class OrderRequestSnapshot {
  const OrderRequestSnapshot({
    required this.id,
    this.status = CustomerOrderRequestStatus.unknown,
    this.totalLiters = 0,
    this.createdAt,
    this.createdOrderIds = const [],
    this.lines = const [],
    this.paymentMethodCode,
    this.paymentTermDays,
    this.paymentInstallments,
    this.paymentDetailJson,
  });

  factory OrderRequestSnapshot.fromJson(JsonReader r) => OrderRequestSnapshot(
    id: r.integer('id'),
    status: r.enumOf('status', CustomerOrderRequestStatus.fromCode),
    totalLiters: r.dec('totalLiters'),
    createdAt: r.dateUtc('createdAt'),
    createdOrderIds: r.ints('createdOrderIds'),
    lines: List.unmodifiable(r.list('lines', OrderRequestLine.fromJson)),
    paymentMethodCode: r.nonEmpty('paymentMethodCode'),
    paymentTermDays: r.intOrNull('paymentTermDays'),
    paymentInstallments: r.intOrNull('paymentInstallments'),
    paymentDetailJson: r.nonEmpty('paymentDetailJson'),
  );

  static OrderRequestSnapshot parse(Object? json) =>
      OrderRequestSnapshot.fromJson(JsonReader.of(json));

  final int id;
  final CustomerOrderRequestStatus status;
  final double totalLiters;
  final DateTime? createdAt;
  final List<int> createdOrderIds;
  final List<OrderRequestLine> lines;
  final String? paymentMethodCode;
  final int? paymentTermDays;
  final int? paymentInstallments;
  final String? paymentDetailJson;

  /// Siparişe dönüşmemiş satırlar.
  List<OrderRequestLine> get failedLines =>
      lines.where((l) => l.orderId == null).toList();
}

/// Talep satırı (`CustomerOrderRequestLineDto`).
@immutable
class OrderRequestLine {
  const OrderRequestLine({
    required this.stationId,
    required this.productId,
    required this.deliveryPointId,
    required this.quantityLiters,
    this.requestedDeliveryDate,
    this.orderId,
    this.error,
    this.productName = '',
    this.deliveryPointName = '',
  });

  factory OrderRequestLine.fromJson(JsonReader r) => OrderRequestLine(
    stationId: r.integer('stationId'),
    productId: r.integer('productId'),
    deliveryPointId: r.integer('deliveryPointId'),
    quantityLiters: r.dec('quantityLiters'),
    requestedDeliveryDate: r.dateTr('requestedDeliveryDate'),
    orderId: r.intOrNull('orderId'),
    error: r.nonEmpty('error'),
    productName: r.str('productName'),
    deliveryPointName: r.str('deliveryPointName'),
  );

  final int stationId;
  final int productId;
  final int deliveryPointId;
  final double quantityLiters;
  final DateTime? requestedDeliveryDate;
  final int? orderId;
  final String? error;
  final String productName;
  final String deliveryPointName;
}

import 'package:flutter/foundation.dart';

import '../../../core/models/json.dart';
import 'window_time.dart';

/// Teslimat noktası (`DeliveryPointDetailsDto`, `GET customers/me/delivery-points`).
@immutable
class DeliveryPoint {
  const DeliveryPoint({
    required this.id,
    this.customerId = 0,
    required this.name,
    this.city = '',
    this.district = '',
    this.address = '',
    this.isActive = true,
    this.latitude,
    this.longitude,
    this.contactName,
    this.contactPhone,
    this.windowStart,
    this.windowEnd,
    this.tankCapacityLiters,
    this.accessNotes,
  });

  factory DeliveryPoint.fromJson(JsonReader r) => DeliveryPoint(
    id: r.integer('id'),
    customerId: r.integer('customerId'),
    name: r.str('name'),
    city: r.str('city'),
    district: r.str('district'),
    address: r.str('address'),
    isActive: r.boolean('isActive', true),
    latitude: r.decOrNull('latitude'),
    longitude: r.decOrNull('longitude'),
    contactName: r.nonEmpty('contactName'),
    contactPhone: r.nonEmpty('contactPhone'),
    windowStart: WindowTime.tryParse(r['deliveryWindowStart']),
    windowEnd: WindowTime.tryParse(r['deliveryWindowEnd']),
    tankCapacityLiters: r.decOrNull('tankCapacityLiters'),
    accessNotes: r.nonEmpty('accessNotes'),
  );

  final int id;
  final int customerId;
  final String name;
  final String city;
  final String district;
  final String address;
  final bool isActive;
  final double? latitude;
  final double? longitude;
  final String? contactName;
  final String? contactPhone;
  final WindowTime? windowStart;
  final WindowTime? windowEnd;
  final double? tankCapacityLiters;
  final String? accessNotes;

  bool get hasLocation => latitude != null && longitude != null;

  /// "Pendik / İstanbul".
  String get cityDistrict =>
      [district, city].where((s) => s.trim().isNotEmpty).join(' / ');

  String? get window => windowLabel(windowStart, windowEnd);

  JsonMap toJson() => {
    'id': id,
    'customerId': customerId,
    'name': name,
    'city': city,
    'district': district,
    'address': address,
    'isActive': isActive,
    'latitude': latitude,
    'longitude': longitude,
    'contactName': contactName,
    'contactPhone': contactPhone,
    'deliveryWindowStart': windowStart?.toJson(),
    'deliveryWindowEnd': windowEnd?.toJson(),
    'tankCapacityLiters': tankCapacityLiters,
    'accessNotes': accessNotes,
    'hasLocation': hasLocation,
  };
}

/// Kaydetme isteği (`SaveDeliveryPointDetailsRequest`). Kurallar sunucuyla aynıdır
/// (`DeliveryPointDetailsRules.Validate` + `DeliveryPointService.ValidateLengths`).
@immutable
class DeliveryPointDraft {
  const DeliveryPointDraft({
    this.id = 0,
    this.name = '',
    this.city = '',
    this.district = '',
    this.address = '',
    this.latitude,
    this.longitude,
    this.contactName,
    this.contactPhone,
    this.windowStart,
    this.windowEnd,
    this.tankCapacityLiters,
    this.accessNotes,
  });

  factory DeliveryPointDraft.of(DeliveryPoint p) => DeliveryPointDraft(
    id: p.id,
    name: p.name,
    city: p.city,
    district: p.district,
    address: p.address,
    latitude: p.latitude,
    longitude: p.longitude,
    contactName: p.contactName,
    contactPhone: p.contactPhone,
    windowStart: p.windowStart,
    windowEnd: p.windowEnd,
    tankCapacityLiters: p.tankCapacityLiters,
    accessNotes: p.accessNotes,
  );

  static const nameMaxLength = 150;
  static const cityMaxLength = 100;
  static const addressMaxLength = 500;
  static const contactNameMaxLength = 100;
  static const contactPhoneMaxLength = 30;
  static const accessNotesMaxLength = 500;
  static const tankMax = 10000000.0;

  final int id;
  final String name;
  final String city;
  final String district;
  final String address;
  final double? latitude;
  final double? longitude;
  final String? contactName;
  final String? contactPhone;
  final WindowTime? windowStart;
  final WindowTime? windowEnd;
  final double? tankCapacityLiters;
  final String? accessNotes;

  bool get isNew => id <= 0;

  /// Sunucu kuralları; geçerliyse null, değilse Türkçe mesaj.
  String? validate() {
    String t(String? s) => (s ?? '').trim();
    if (t(name).isEmpty) return 'Teslimat noktası adı zorunlu.';
    if (t(city).isEmpty || t(district).isEmpty || t(address).isEmpty) {
      return 'İl, ilçe ve açık adres zorunlu.';
    }
    if ((latitude == null) != (longitude == null)) {
      return 'Konum için enlem ve boylamı birlikte girin.';
    }
    final lat = latitude;
    if (lat != null && (lat < -90 || lat > 90)) {
      return 'Enlem −90 ile 90 arasında olmalı.';
    }
    final lng = longitude;
    if (lng != null && (lng < -180 || lng > 180)) {
      return 'Boylam −180 ile 180 arasında olmalı.';
    }
    if ((windowStart == null) != (windowEnd == null)) {
      return 'Teslim saat aralığının başlangıç ve bitişini birlikte girin.';
    }
    final s = windowStart;
    final e = windowEnd;
    if (s != null && e != null) {
      if (s.isEndOfDay) return 'Teslim saatleri 00:00–24:00 arasında olmalı.';
      if (s >= e) {
        return 'Teslim saat aralığında başlangıç bitişten önce olmalı.';
      }
    }
    final tank = tankCapacityLiters;
    if (tank != null && tank <= 0) {
      return 'Tank kapasitesi sıfırdan büyük olmalı.';
    }
    if (tank != null && tank > tankMax) return 'Tank kapasitesi çok büyük.';
    if (t(name).length > nameMaxLength) {
      return 'Nokta adı en çok $nameMaxLength karakter.';
    }
    if (t(city).length > cityMaxLength || t(district).length > cityMaxLength) {
      return 'İl ve ilçe en çok $cityMaxLength karakter.';
    }
    if (t(address).length > addressMaxLength) {
      return 'Açık adres en çok $addressMaxLength karakter.';
    }
    if (t(contactName).length > contactNameMaxLength) {
      return 'Sorumlu adı en çok $contactNameMaxLength karakter.';
    }
    if (t(contactPhone).length > contactPhoneMaxLength) {
      return 'Telefon en çok $contactPhoneMaxLength karakter.';
    }
    if (t(accessNotes).length > accessNotesMaxLength) {
      return 'Erişim notu en çok $accessNotesMaxLength karakter.';
    }
    return null;
  }

  static double? _round(double? v, int digits) =>
      v == null ? null : double.parse(v.toStringAsFixed(digits));

  static String? _clean(String? s) {
    final v = s?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  /// İstek gövdesi. Konum 6, tank 3 haneye yuvarlanır; boş metinler null gider.
  JsonMap toJson() => {
    'id': id,
    'customerId': 0,
    'name': name.trim(),
    'city': city.trim(),
    'district': district.trim(),
    'address': address.trim(),
    'latitude': _round(latitude, 6),
    'longitude': _round(longitude, 6),
    'contactName': _clean(contactName),
    'contactPhone': _clean(contactPhone),
    'deliveryWindowStart': windowStart?.toJson(),
    'deliveryWindowEnd': windowEnd?.toJson(),
    'tankCapacityLiters': _round(tankCapacityLiters, 3),
    'accessNotes': _clean(accessNotes),
  };

  DeliveryPointDraft copyWith({
    String? name,
    String? city,
    String? district,
    String? address,
    double? latitude,
    double? longitude,
    bool clearLocation = false,
    String? contactName,
    String? contactPhone,
    WindowTime? windowStart,
    WindowTime? windowEnd,
    bool clearWindow = false,
    double? tankCapacityLiters,
    bool clearTank = false,
    String? accessNotes,
  }) => DeliveryPointDraft(
    id: id,
    name: name ?? this.name,
    city: city ?? this.city,
    district: district ?? this.district,
    address: address ?? this.address,
    latitude: clearLocation ? null : (latitude ?? this.latitude),
    longitude: clearLocation ? null : (longitude ?? this.longitude),
    contactName: contactName ?? this.contactName,
    contactPhone: contactPhone ?? this.contactPhone,
    windowStart: clearWindow ? null : (windowStart ?? this.windowStart),
    windowEnd: clearWindow ? null : (windowEnd ?? this.windowEnd),
    tankCapacityLiters: clearTank
        ? null
        : (tankCapacityLiters ?? this.tankCapacityLiters),
    accessNotes: accessNotes ?? this.accessNotes,
  );
}

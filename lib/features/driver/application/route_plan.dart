import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../../core/models/models.dart';
import '../data/driver_models.dart';
import 'driver_lists.dart';
import 'driver_ops.dart';

/// Bir durağın güzergâhtaki yeri (yük çubuğu bölümü).
enum StopState {
  /// Teslim edildi (ya da teslimi telefonda kayıtlı, gönderilmeyi bekliyor): tankta değil.
  done,

  /// Sıradaki durak (plakadaki).
  current,

  /// Sonra gelecek.
  upcoming,
}

/// Güzergâhtaki bir durak: sevkiyat satırı, gerçek sıra numarası (1'den) ve durumu.
@immutable
class RouteStop {
  const RouteStop({
    required this.row,
    required this.number,
    required this.state,
  });

  final DriverShipmentRow row;

  /// Güzergâh sırası (plan saatine göre, 1'den başlar).
  final int number;
  final StopState state;

  double get liters => row.plannedLiters;
}

/// Bugünün güzergâhı (tasarım v2 §7.11): bugünkü duraklar plan saatine göre sıralı, sıradaki durak,
/// sıra numarası ve tankta kalan yük ("Sıradaki teslimat, 1 / 3 … 24.000 L").
///
/// İtirazlı kayıtlar (önceki bir teslimatın düzeltmesi) ve iptaller güzergâha girmez. Teslimi
/// telefonda kayıtlı (gönderilmeyi bekleyen) durak tamamlanmış sayılır: yük çubuğundaki bölümü boşalır
/// ve sıradaki durak plakaya geçer.
@immutable
class DriverRoutePlan {
  const DriverRoutePlan._(this.stops, this.next);

  factory DriverRoutePlan.of(
    List<DriverShipmentRow> today,
    DateTime now, {
    Map<int, DriverShipmentOps> ops = const {},
  }) {
    bool deliveredLocally(DriverShipmentRow r) =>
        ops[r.id]?.deliverWaiting ?? false;
    final route = [
      for (final r in today)
        if (r.status != ShipmentStatus.cancelled &&
            r.status != ShipmentStatus.disputed &&
            r.status != ShipmentStatus.unknown)
          r,
    ]..sort(_byPlan);
    final next = pickNextStop([
      for (final r in route)
        if (!deliveredLocally(r)) r,
    ], now);
    final stops = <RouteStop>[
      for (var i = 0; i < route.length; i++)
        RouteStop(
          row: route[i],
          number: i + 1,
          state: route[i].id == next?.id
              ? StopState.current
              : (route[i].isOpen && !deliveredLocally(route[i]))
              ? StopState.upcoming
              : StopState.done,
        ),
    ];
    return DriverRoutePlan._(List.unmodifiable(stops), next);
  }

  static int _byPlan(DriverShipmentRow a, DriverShipmentRow b) {
    // Yoldaki önce (şoför şu an onu taşıyor), sonra plan saati, sonra kimlik.
    if (a.isInTransit != b.isInTransit) return a.isInTransit ? -1 : 1;
    final at = a.scheduledAt;
    final bt = b.scheduledAt;
    if (at != null && bt != null && at != bt) return at.compareTo(bt);
    if (at == null && bt != null) return 1;
    if (at != null && bt == null) return -1;
    return a.id.compareTo(b.id);
  }

  /// Bugünkü duraklar, güzergâh sırasıyla.
  final List<RouteStop> stops;

  /// Sıradaki durak (plakadaki); yoksa null.
  final DriverShipmentRow? next;

  /// Sıradaki durağın güzergâhtaki numarası (1'den).
  int? get nextNumber {
    final id = next?.id;
    if (id == null) return null;
    for (final s in stops) {
      if (s.row.id == id) return s.number;
    }
    return null;
  }

  int get total => stops.length;

  /// Sıradakinden sonra gelecek duraklar.
  List<RouteStop> get upcoming => [
    for (final s in stops)
      if (s.state == StopState.upcoming) s,
  ];

  /// Tamamlanan duraklar.
  List<RouteStop> get done => [
    for (final s in stops)
      if (s.state == StopState.done) s,
  ];

  /// Tankta kalan yük: sıradaki ve sonraki durakların planlanan litresi.
  double get remainingLiters => stops
      .where((s) => s.state != StopState.done)
      .fold<double>(0, (sum, s) => sum + s.liters);
}

/// İki koordinat arasındaki kuş uçuşu uzaklık (metre, haversine).
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(a)));
}

/// "Birincil iş tırı izler" (§7.11): teslim noktasına 300 m'den uzaksa "Yol tarifi" birincildir;
/// 300 m içinde — ya da konum bilinmiyorsa / 100 m'den kötü hassasiyet 30 sn sürdüyse — "Teslim et".
/// "Teslim et" hiçbir zaman gizlenmez.
abstract final class DriverProximity {
  /// Teslim noktasına bu kadar yakınken "Teslim et" birincil olur.
  static const nearMeters = 300.0;

  /// Bundan kötü hassasiyet "bilinmiyor" sayılır.
  static const maxAccuracyMeters = 100.0;

  /// Konum bu kadar süre bilinmezse "Teslim et" birincil olur.
  static const unknownGrace = Duration(seconds: 30);

  /// Konum kullanılabilir mi (var ve yeterince hassas).
  static bool usable(DriverPosition? p) =>
      p != null &&
      !p.approximate &&
      (p.accuracyMeters ?? 0) <= maxAccuracyMeters;

  /// Teslim noktasına uzaklık (metre); konum ya da nokta koordinatı yoksa null.
  static double? distanceTo(DriverPosition? p, double? lat, double? lng) {
    if (p == null || lat == null || lng == null) return null;
    return distanceMeters(p.latitude, p.longitude, lat, lng);
  }

  /// "Teslim et" birincil mi.
  ///
  /// [unavailable]: konum hiç alınamayacak (izin yok, servis kapalı, şoför konumsuz devam etti).
  /// [unknownFor]: kullanılabilir konum olmadan geçen süre.
  static bool deliverIsPrimary({
    required DriverPosition? position,
    required double? lat,
    required double? lng,
    required bool unavailable,
    required Duration unknownFor,
  }) {
    if (lat == null || lng == null) return true;
    if (unavailable) return true;
    if (usable(position)) {
      return distanceTo(position, lat, lng)! <= nearMeters;
    }
    return unknownFor >= unknownGrace;
  }
}

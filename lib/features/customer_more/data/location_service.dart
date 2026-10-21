import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/utils/log.dart';

/// Konum izni durumu.
enum LocationAccess {
  /// Henüz sorulmadı (ön sayfa gösterilebilir).
  notAsked,

  /// Reddedildi; yeniden sorulabilir.
  denied,

  /// Kalıcı reddedildi; yalnızca Ayarlar'dan açılır.
  deniedForever,

  /// Konum servisleri kapalı.
  serviceOff,

  /// Hassas konum izni var.
  precise,

  /// Yalnızca yaklaşık konum (iOS "Hassas konum" kapalı / Android yaklaşık).
  approximate,
}

/// Konum ölçümü.
@immutable
class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    this.approximate = false,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;

  /// Yaklaşık konum izniyle alındı.
  final bool approximate;

  /// Uyarı sınırı (spec A.4 A3: 50 m üstü).
  static const warnAboveMeters = 50.0;

  bool get isImprecise => approximate || accuracyMeters > warnAboveMeters;
}

/// Cihaz konumu (yalnızca kullanım sırasında; arka planda konum yok). Testler sahte uygulama verir.
abstract interface class CmLocationService {
  Future<LocationAccess> access();

  /// İşletim sistemi izin penceresi (ön sayfadan sonra).
  Future<LocationAccess> request();

  /// Anlık konum; alınamazsa null.
  Future<LocationFix?> current();

  Future<bool> openAppSettings();
  Future<bool> openLocationSettings();
}

/// geolocator ile gerçek uygulama.
class GeolocatorLocationService implements CmLocationService {
  const GeolocatorLocationService();

  @override
  Future<LocationAccess> access() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationAccess.serviceOff;
      }
      return _map(await Geolocator.checkPermission(), asked: false);
    } catch (e) {
      AppLog.debug('Konum izni okunamadı: $e');
      return LocationAccess.denied;
    }
  }

  @override
  Future<LocationAccess> request() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationAccess.serviceOff;
      }
      return _map(await Geolocator.requestPermission(), asked: true);
    } catch (e) {
      AppLog.debug('Konum izni istenemedi: $e');
      return LocationAccess.denied;
    }
  }

  Future<LocationAccess> _map(
    LocationPermission p, {
    required bool asked,
  }) async {
    switch (p) {
      case LocationPermission.denied:
        return asked ? LocationAccess.denied : LocationAccess.notAsked;
      case LocationPermission.deniedForever:
        return LocationAccess.deniedForever;
      case LocationPermission.unableToDetermine:
        return LocationAccess.notAsked;
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        try {
          final acc = await Geolocator.getLocationAccuracy();
          return acc == LocationAccuracyStatus.reduced
              ? LocationAccess.approximate
              : LocationAccess.precise;
        } catch (_) {
          return LocationAccess.precise;
        }
    }
  }

  @override
  Future<LocationFix?> current() async {
    try {
      final approx =
          await Geolocator.getLocationAccuracy() ==
          LocationAccuracyStatus.reduced;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return LocationFix(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracyMeters: pos.accuracy,
        approximate: approx,
      );
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      return last == null
          ? null
          : LocationFix(
              latitude: last.latitude,
              longitude: last.longitude,
              accuracyMeters: last.accuracy,
            );
    } catch (e) {
      AppLog.debug('Konum alınamadı: $e');
      return null;
    }
  }

  @override
  Future<bool> openAppSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (_) {
      return false;
    }
  }
}

final cmLocationServiceProvider = Provider<CmLocationService>(
  (ref) => const GeolocatorLocationService(),
);

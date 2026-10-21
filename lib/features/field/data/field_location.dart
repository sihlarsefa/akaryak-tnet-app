import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/utils/log.dart';

/// Konum izninin uygulama içi hâli (spec C.7).
enum FieldLocationAccess {
  /// Henüz sorulmadı (işletim sistemi istemi gösterilebilir).
  notDetermined,

  /// Kullanıcı reddetti; tekrar sorulabilir.
  denied,

  /// Kalıcı olarak reddedildi: yalnızca Ayarlar'dan açılabilir.
  deniedForever,

  /// Kullanılıyor iken izin var (hassas konum).
  granted,

  /// İzin var ama yalnızca yaklaşık konum (iOS "Hassas konum" kapalı, Android yalnızca COARSE).
  approximate,

  /// Telefonun konum servisi kapalı.
  serviceDisabled,

  /// Platform desteklemiyor (test, masaüstü).
  unavailable,
}

extension FieldLocationAccessX on FieldLocationAccess {
  bool get canRead =>
      this == FieldLocationAccess.granted ||
      this == FieldLocationAccess.approximate;
}

/// Alınan konum.
@immutable
class FieldLocationFix {
  const FieldLocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.at,
    this.approximate = false,
  });

  final double latitude;
  final double longitude;

  /// Yatay doğruluk (metre).
  final double accuracyMeters;
  final DateTime at;

  /// Yalnızca yaklaşık konum izniyle alındı.
  final bool approximate;

  /// 50 m üstü doğruluk "düşük" sayılır (spec A.4 A3 ile aynı eşik).
  bool get isLowAccuracy => approximate || accuracyMeters > 50;
}

/// Konum hizmeti (Geolocator sarmalayıcısı; testler sahte verir).
abstract interface class FieldLocationService {
  /// İzin durumu (istem göstermez).
  Future<FieldLocationAccess> status();

  /// İşletim sistemi istemini gösterir.
  Future<FieldLocationAccess> request();

  /// Anlık konum. Hata: [FieldLocationException].
  Future<FieldLocationFix> current({
    Duration timeLimit = const Duration(seconds: 15),
  });

  /// Uygulama ayarları (izin kalıcı reddedildiyse, hassas konum kapalıysa).
  Future<bool> openAppSettings();

  /// Telefonun konum ayarları (servis kapalıysa).
  Future<bool> openLocationSettings();
}

/// Konum alınamadı (zaman aşımı, servis kapalı, izin yok).
class FieldLocationException implements Exception {
  const FieldLocationException(this.message, {this.access});
  final String message;
  final FieldLocationAccess? access;

  @override
  String toString() => 'FieldLocationException($message)';
}

/// Geolocator ile gerçek hizmet ("kullanılırken" izni; arka plan konumu yok).
class GeolocatorFieldLocationService implements FieldLocationService {
  const GeolocatorFieldLocationService();

  @override
  Future<FieldLocationAccess> status() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return FieldLocationAccess.serviceDisabled;
      }
      return _map(await Geolocator.checkPermission());
    } on MissingPluginException {
      return FieldLocationAccess.unavailable;
    } catch (e) {
      AppLog.debug('Konum izni okunamadı: $e');
      return FieldLocationAccess.unavailable;
    }
  }

  @override
  Future<FieldLocationAccess> request() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return FieldLocationAccess.serviceDisabled;
      }
      return _map(await Geolocator.requestPermission());
    } on MissingPluginException {
      return FieldLocationAccess.unavailable;
    } catch (e) {
      AppLog.debug('Konum izni istenemedi: $e');
      return FieldLocationAccess.unavailable;
    }
  }

  Future<FieldLocationAccess> _map(LocationPermission p) async {
    switch (p) {
      case LocationPermission.denied:
        return FieldLocationAccess.notDetermined;
      case LocationPermission.deniedForever:
        return FieldLocationAccess.deniedForever;
      case LocationPermission.unableToDetermine:
        return FieldLocationAccess.unavailable;
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        try {
          final accuracy = await Geolocator.getLocationAccuracy();
          return accuracy == LocationAccuracyStatus.reduced
              ? FieldLocationAccess.approximate
              : FieldLocationAccess.granted;
        } catch (_) {
          return FieldLocationAccess.granted;
        }
    }
  }

  @override
  Future<FieldLocationFix> current({
    Duration timeLimit = const Duration(seconds: 15),
  }) async {
    final access = await status();
    if (!access.canRead) {
      throw FieldLocationException(
        access == FieldLocationAccess.serviceDisabled
            ? 'Konum servisi kapalı.'
            : 'Konum izni yok.',
        access: access,
      );
    }
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeLimit,
        ),
      );
      return FieldLocationFix(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracyMeters: p.accuracy,
        at: p.timestamp.toUtc(),
        approximate: access == FieldLocationAccess.approximate,
      );
    } on TimeoutException {
      throw const FieldLocationException(
        'Konum zamanında alınamadı. Açık alanda tekrar deneyin.',
      );
    } catch (e) {
      AppLog.warn('Konum alınamadı', error: e);
      throw const FieldLocationException(
        'Konum alınamadı. Konum iznini kontrol edip tekrar deneyin.',
      );
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

final fieldLocationServiceProvider = Provider<FieldLocationService>(
  (ref) => const GeolocatorFieldLocationService(),
);

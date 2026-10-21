import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/storage/prefs_store.dart';
import '../../../core/utils/log.dart';
import '../data/driver_models.dart';

/// Konum izninin uygulama içindeki karşılığı.
enum DriverLocationPermission {
  /// Henüz sorulmadı (ya da tekrar sorulabilir).
  notDetermined,

  /// Kullanım sırasında izinli.
  granted,

  /// Reddedildi; sistem penceresi bir daha açılmaz (ayarlardan açılmalı).
  deniedForever,
}

/// Cihaz konumu (geolocator). Testler sahte bir uygulamayla değiştirir.
abstract class DriverLocationService {
  Future<bool> serviceEnabled();

  Future<DriverLocationPermission> permission();

  /// Sistem izin penceresini açar.
  Future<DriverLocationPermission> requestPermission();

  /// Yalnızca yaklaşık konum izni mi (iOS "Hassas konum" kapalı / Android yaklaşık).
  Future<bool> isApproximate();

  /// Güncel konum ([timeLimit] içinde; alınamazsa son bilinen konum, o da yoksa null).
  Future<DriverPosition?> current({
    Duration timeLimit = const Duration(seconds: 8),
  });

  Future<bool> openAppSettings();

  Future<bool> openLocationSettings();
}

class GeolocatorLocationService implements DriverLocationService {
  const GeolocatorLocationService();

  @override
  Future<bool> serviceEnabled() async {
    try {
      return await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<DriverLocationPermission> permission() async {
    try {
      return _map(await Geolocator.checkPermission());
    } catch (e) {
      AppLog.debug('Konum izni okunamadı: $e');
      return DriverLocationPermission.notDetermined;
    }
  }

  @override
  Future<DriverLocationPermission> requestPermission() async {
    try {
      return _map(await Geolocator.requestPermission());
    } catch (e) {
      AppLog.debug('Konum izni istenemedi: $e');
      return DriverLocationPermission.notDetermined;
    }
  }

  static DriverLocationPermission _map(LocationPermission p) => switch (p) {
    LocationPermission.always ||
    LocationPermission.whileInUse => DriverLocationPermission.granted,
    LocationPermission.deniedForever => DriverLocationPermission.deniedForever,
    LocationPermission.denied || LocationPermission.unableToDetermine =>
      DriverLocationPermission.notDetermined,
  };

  @override
  Future<bool> isApproximate() async {
    try {
      return await Geolocator.getLocationAccuracy() ==
          LocationAccuracyStatus.reduced;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<DriverPosition?> current({
    Duration timeLimit = const Duration(seconds: 8),
  }) async {
    final approximate = await isApproximate();
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeLimit,
        ),
      );
      return _toPosition(p, approximate);
    } catch (e) {
      AppLog.debug('Güncel konum alınamadı: $e');
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last == null) return null;
        final age = DateTime.now().difference(last.timestamp);
        if (age > const Duration(minutes: 10)) return null;
        return _toPosition(last, approximate);
      } catch (_) {
        return null;
      }
    }
  }

  static DriverPosition _toPosition(Position p, bool approximate) =>
      DriverPosition(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracyMeters: p.accuracy.isFinite && p.accuracy > 0
            ? p.accuracy
            : null,
        approximate: approximate,
        capturedAt: p.timestamp.toUtc(),
      );

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

final driverLocationServiceProvider = Provider<DriverLocationService>(
  (ref) => const GeolocatorLocationService(),
);

/// Konum yakalamanın aşaması (ekrandaki konum kartı bunu gösterir).
enum LocationPhase {
  /// Henüz denenmedi.
  idle,

  /// İzin / servis denetleniyor ya da konum alınıyor.
  acquiring,

  /// Konum hazır ([LocationCapture.position]).
  ready,

  /// İzin sorulmadı: "Konum ekle" (önce ön sayfa, sonra sistem penceresi).
  needsPermission,

  /// İzin kalıcı reddedildi: "Ayarları aç".
  denied,

  /// Konum servisleri kapalı.
  serviceOff,

  /// Konum alınamadı (zaman aşımı, kapalı alan).
  failed,

  /// Kullanıcı konumsuz devam etmeyi seçti.
  skipped,
}

/// Bir ekrandaki konum yakalama durumu (yola çıkış ya da teslim). Sistem penceresi yalnızca
/// [requestAndAcquire] ile açılır; ekran önce izin ön sayfasını gösterir (spec C.7).
class LocationCapture extends ChangeNotifier {
  LocationCapture(this.service, {DateTime Function()? clock})
    : _clock = clock ?? _utcNow;

  final DriverLocationService service;
  final DateTime Function() _clock;
  static DateTime _utcNow() => DateTime.now().toUtc();

  LocationPhase _phase = LocationPhase.idle;
  DriverPosition? _position;
  bool _disposed = false;
  Future<void>? _running;

  LocationPhase get phase => _phase;
  DriverPosition? get position => _position;
  bool get isBusy => _phase == LocationPhase.acquiring;
  bool get hasPosition => _position != null;

  /// İzin zaten varsa sessizce konum alır; yoksa yalnızca durumu gösterir (sistem penceresi açılmaz).
  Future<void> prime() => _run(interactive: false);

  /// Henüz denenmediyse [prime] çalıştırır; sürüyorsa bitmesini bekler.
  Future<void> ensurePrimed() {
    final running = _running;
    if (running != null) return running;
    if (_phase == LocationPhase.idle) return prime();
    return Future<void>.value();
  }

  /// "Konum ekle" / "Tekrar dene": gerekirse sistem izin penceresini açar ve konum alır.
  Future<void> requestAndAcquire() => _run(interactive: true);

  /// "Konumsuz devam et".
  void skip() {
    _position = null;
    _set(LocationPhase.skipped);
  }

  /// Onay anında kullanılacak konum: taze değilse bir kez kısa süreli yeniden denenir.
  Future<DriverPosition?> latest({
    Duration maxAge = const Duration(minutes: 2),
  }) async {
    final p = _position;
    if (p != null && p.isFresh(_clock(), maxAge: maxAge)) return p;
    if (_phase == LocationPhase.ready || _phase == LocationPhase.failed) {
      final perm = await service.permission();
      if (perm == DriverLocationPermission.granted) {
        final fresh = await service.current(
          timeLimit: const Duration(seconds: 4),
        );
        if (fresh != null) {
          _position = fresh;
          _set(LocationPhase.ready);
          return fresh;
        }
      }
    }
    return p;
  }

  Future<void> _run({required bool interactive}) {
    final running = _running;
    if (running != null) return running;
    final f = _acquire(interactive).whenComplete(() => _running = null);
    _running = f;
    return f;
  }

  Future<void> _acquire(bool interactive) async {
    _set(LocationPhase.acquiring);
    if (!await service.serviceEnabled()) {
      _set(LocationPhase.serviceOff);
      return;
    }
    var perm = await service.permission();
    if (perm == DriverLocationPermission.notDetermined && interactive) {
      perm = await service.requestPermission();
    }
    switch (perm) {
      case DriverLocationPermission.notDetermined:
        _set(
          interactive ? LocationPhase.denied : LocationPhase.needsPermission,
        );
        return;
      case DriverLocationPermission.deniedForever:
        _set(LocationPhase.denied);
        return;
      case DriverLocationPermission.granted:
        break;
    }
    final p = await service.current();
    if (p == null) {
      _set(LocationPhase.failed);
      return;
    }
    _position = p;
    _set(LocationPhase.ready);
  }

  void _set(LocationPhase phase) {
    _phase = phase;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// İzin ön sayfaları (spec C.7): reddedilen ön sayfa 7 gün kendiliğinden gösterilmez; kullanıcı
/// açıkça istediğinde (düğme) yine gösterilir.
class DriverPrimerPrefs {
  DriverPrimerPrefs(this.prefs, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final PrefsStore prefs;
  final DateTime Function() _clock;

  static const locationDeclinedKey = 'akn.driver.locationPrimerDeclinedAt';
  static const cameraAcceptedKey = 'akn.driver.cameraPrimerAccepted';
  static const cameraDeclinedKey = 'akn.driver.cameraPrimerDeclinedAt';
  static const quietPeriod = Duration(days: 7);

  bool _recently(String key) {
    final ms = prefs.getInt(key);
    if (ms == null) return false;
    final at = DateTime.fromMillisecondsSinceEpoch(ms);
    return _clock().difference(at) < quietPeriod;
  }

  /// Konum ön sayfası kendiliğinden gösterilebilir mi.
  bool get mayAutoShowLocation => !_recently(locationDeclinedKey);

  Future<void> locationDeclined() =>
      prefs.setInt(locationDeclinedKey, _clock().millisecondsSinceEpoch);

  /// Kamera ön sayfası gerekir mi (iOS; bir kez kabul edilince bir daha gösterilmez).
  bool get cameraPrimerNeeded => !prefs.getBool(cameraAcceptedKey);

  Future<void> cameraAccepted() => prefs.setBool(cameraAcceptedKey, true);

  Future<void> cameraDeclined() =>
      prefs.setInt(cameraDeclinedKey, _clock().millisecondsSinceEpoch);
}

final driverPrimerPrefsProvider = Provider<DriverPrimerPrefs>(
  (ref) => DriverPrimerPrefs(ref.watch(prefsStoreProvider)),
);

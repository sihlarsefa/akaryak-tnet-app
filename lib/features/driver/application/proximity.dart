import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/driver_models.dart';
import 'location.dart';
import 'route_plan.dart';

/// Sıradaki durağa yakınlığı izler (§7.11 "birincil iş tırı izler"). Konum izni zaten varsa konumu
/// sessizce alır ve [interval]'da bir tazeler; sistem izin penceresini **asla** açmaz (izin, teslim
/// özetinde ön sayfayla istenir). İzin ya da servis yoksa konum "alınamaz" sayılır ve "Teslim et"
/// hemen birincil olur.
class ProximityWatch extends ChangeNotifier {
  ProximityWatch(
    DriverLocationService service, {
    DateTime Function()? clock,
    this.interval = const Duration(seconds: 30),
  }) : _clock = clock ?? DateTime.now,
       capture = LocationCapture(service);

  /// Konum yakalama (ayrıntı ekranında yola çıkış konumu olarak da kullanılır).
  final LocationCapture capture;
  final Duration interval;
  final DateTime Function() _clock;

  Timer? _timer;
  DateTime? _unknownSince;
  bool _started = false;
  bool _disposed = false;

  /// Bir kez çağrılır: sessiz konum + periyodik tazeleme.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _unknownSince = _clock();
    capture.addListener(_onCapture);
    unawaited(capture.prime());
    _timer = Timer.periodic(interval, (_) => _tick());
  }

  /// Uygulama öne gelince: konum yeniden denenir (izin ayarlardan açılmış olabilir).
  void resume() {
    if (!_started || _disposed) return;
    unawaited(capture.prime());
  }

  void _tick() {
    if (_disposed) return;
    final phase = capture.phase;
    if (phase == LocationPhase.ready || phase == LocationPhase.failed) {
      unawaited(capture.latest(maxAge: interval - const Duration(seconds: 5)));
    }
    // "30 sn bilinmiyor" eşiği zamanla aşılır: yeniden çiz.
    notifyListeners();
  }

  void _onCapture() {
    if (DriverProximity.usable(capture.position)) {
      _unknownSince = null;
    } else {
      _unknownSince ??= _clock();
    }
    if (!_disposed) notifyListeners();
  }

  DriverPosition? get position => capture.position;

  /// Konum hiç alınamayacak: izin yok / kalıcı reddedildi, servis kapalı ya da konumsuz devam.
  bool get unavailable => switch (capture.phase) {
    LocationPhase.needsPermission ||
    LocationPhase.denied ||
    LocationPhase.serviceOff ||
    LocationPhase.skipped => true,
    _ => false,
  };

  /// Kullanılabilir konum olmadan geçen süre.
  Duration get unknownFor {
    final since = _unknownSince;
    if (since == null || DriverProximity.usable(position)) {
      return Duration.zero;
    }
    return _clock().difference(since);
  }

  /// Noktaya kuş uçuşu uzaklık (metre); kullanılabilir konum yoksa null.
  double? distanceTo(double? lat, double? lng) =>
      DriverProximity.usable(position)
      ? DriverProximity.distanceTo(position, lat, lng)
      : null;

  /// "Teslim et" birincil mi.
  bool deliverIsPrimary(double? lat, double? lng) =>
      DriverProximity.deliverIsPrimary(
        position: position,
        lat: lat,
        lng: lng,
        unavailable: unavailable,
        unknownFor: unknownFor,
      );

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    capture.removeListener(_onCapture);
    capture.dispose();
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../data/weather_models.dart';
import '../data/weather_repository.dart';

/// Hücre başına hava durumu. Kart ve sürüş bandı aynı veriyi paylaşır; veri 30 dakika bellekte kalır
/// (sunucu da 30 dakika önbellekler). Hata önbelleğe alınmaz: bir sonraki açılışta yeniden denenir.
final weatherProvider = FutureProvider.autoDispose
    .family<WeatherReport, WeatherCell>((ref, cell) async {
      ref.watch(currentUserIdProvider);
      final link = ref.keepAlive();
      final timer = Timer(const Duration(minutes: 30), link.close);
      ref.onDispose(timer.cancel);
      try {
        return await ref.watch(weatherRepositoryProvider).fetch(cell);
      } catch (_) {
        timer.cancel();
        link.close();
        rethrow;
      }
    });

/// Ekranda görünen sürüş bandı olan hücreler. Aynı hücrenin kartı uyarıyı ikinci kez yazmaz (bant
/// zaten gösteriyor). Değişiklikler kare sonunda yayımlanır (yapım ya da sökme sırasında değil).
class AlertBannerRegistry extends ChangeNotifier {
  final Map<WeatherCell, int> _mounted = {};

  bool has(WeatherCell cell) => (_mounted[cell] ?? 0) > 0;

  void add(WeatherCell cell) => _later(() {
    _mounted[cell] = (_mounted[cell] ?? 0) + 1;
    notifyListeners();
  });

  void remove(WeatherCell cell) => _later(() {
    final n = (_mounted[cell] ?? 0) - 1;
    if (n <= 0) {
      _mounted.remove(cell);
    } else {
      _mounted[cell] = n;
    }
    notifyListeners();
  });

  bool _disposed = false;

  void _later(VoidCallback change) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) change();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final alertBannerRegistryProvider = Provider<AlertBannerRegistry>((ref) {
  final r = AlertBannerRegistry();
  ref.onDispose(r.dispose);
  return r;
});

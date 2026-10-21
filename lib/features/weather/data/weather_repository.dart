import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/network/network_providers.dart';
import '../../../core/offline/cache_store.dart';
import 'weather_models.dart';

/// Hava durumu verisi yok (sunucu kapalı, kaynak yanıt vermiyor ya da tahmin bozuk).
class WeatherUnavailable implements Exception {
  const WeatherUnavailable(this.message, {this.disabled = false});

  /// Türkçe ve kısa (sunucunun mesajı ya da varsayılan).
  final String message;

  /// Sunucuda hava durumu kapalı (kart gizlenir).
  final bool disabled;

  @override
  String toString() => 'WeatherUnavailable($message)';
}

/// `GET weather?lat&lng` (spec B.11; sunucu önbellekli Open-Meteo vekili). Başarılı yanıt kullanıcıya
/// özel önbelleğe yazılır (6 saat); çevrimdışıyken o veri "eski" işaretiyle döner.
class WeatherRepository {
  WeatherRepository(this._api, this._cache, this._userId);

  final ApiClient _api;
  final CacheStore _cache;
  final String? _userId;

  static const cacheTtl = Duration(hours: 6);

  String? _key(WeatherCell cell) =>
      _userId == null ? null : CacheKeys.user(_userId, 'weather.${cell.key}');

  Future<WeatherReport> fetch(WeatherCell cell) async {
    try {
      final json = await _api.get<Object?>(
        'weather',
        query: {'lat': cell.lat, 'lng': cell.lng},
        quiet403: true,
        parse: (j) => j,
      );
      final report = WeatherReport.tryParse(json);
      if (report == null) {
        throw const WeatherUnavailable('Hava durumu şu an alınamıyor.');
      }
      final key = _key(cell);
      if (key != null) {
        await _cache.write(key, json, ttl: cacheTtl, userId: _userId);
      }
      return report;
    } on AppFailure catch (f) {
      final cached = await _cached(cell);
      if (cached != null && (f.isTransient || f is ServerFailure)) {
        return cached;
      }
      if (f is ServerFailure && f.statusCode == 503) {
        final message = f.problem?.detail ?? 'Hava durumu şu an alınamıyor.';
        throw WeatherUnavailable(message, disabled: message.contains('kapalı'));
      }
      if (cached != null) return cached;
      rethrow;
    }
  }

  Future<WeatherReport?> _cached(WeatherCell cell) async {
    final key = _key(cell);
    if (key == null) return null;
    final entry = await _cache.read(key);
    if (entry == null || entry.age > cacheTtl) return null;
    return WeatherReport.tryParse(entry.value)?.asStale();
  }
}

final weatherRepositoryProvider = Provider<WeatherRepository>(
  (ref) => WeatherRepository(
    ref.watch(apiClientProvider),
    ref.watch(cacheStoreProvider),
    ref.watch(currentUserIdProvider),
  ),
);

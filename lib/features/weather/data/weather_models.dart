import 'package:flutter/foundation.dart';

import '../../../core/models/json.dart';
import '../../../core/utils/tr_time.dart';
import 'driving_alert.dart';

/// Önbellek / sağlayıcı anahtarı: sunucunun 0,05° ızgarası (≈ 5 km). Aynı hücredeki teslimatlar ve
/// konumlar aynı veriyi paylaşır.
@immutable
class WeatherCell {
  const WeatherCell._(this.latKey, this.lngKey);

  factory WeatherCell.of(double lat, double lng) =>
      WeatherCell._((lat * 20).round(), (lng * 20).round());

  final int latKey;
  final int lngKey;

  double get lat => latKey / 20;
  double get lng => lngKey / 20;

  /// Önbellek anahtarı (`40.75_29.9`).
  String get key => '${lat.toStringAsFixed(2)}_${lng.toStringAsFixed(2)}';

  @override
  bool operator ==(Object other) =>
      other is WeatherCell && other.latKey == latKey && other.lngKey == lngKey;

  @override
  int get hashCode => Object.hash(latKey, lngKey);

  @override
  String toString() => 'WeatherCell($key)';
}

/// Şimdiki hava (Open-Meteo `current`).
@immutable
class WeatherNow {
  const WeatherNow({
    required this.temperature,
    required this.apparent,
    required this.code,
    required this.isDay,
    required this.windSpeed,
  });

  final double temperature;
  final double apparent;
  final int code;
  final bool isDay;

  /// km/s.
  final double windSpeed;
}

/// Saatlik tahmin (Open-Meteo `hourly`; saatler Türkiye saatiyle gelir, burada an olarak tutulur).
@immutable
class WeatherHour {
  const WeatherHour({
    required this.time,
    required this.temperature,
    required this.code,
    this.precipitationProbability = 0,
    this.precipitation = 0,
    this.snowfall = 0,
    this.visibility = 99999,
    this.windGusts = 0,
    this.humidity = 0,
    this.isDay = true,
  });

  /// An (UTC).
  final DateTime time;
  final double temperature;
  final int code;

  /// %.
  final int precipitationProbability;

  /// mm (o saat).
  final double precipitation;

  /// cm (o saat).
  final double snowfall;

  /// Görüş mesafesi (m).
  final double visibility;

  /// Rüzgâr hamlesi (km/s).
  final double windGusts;

  /// Bağıl nem (%).
  final double humidity;
  final bool isDay;
}

/// Günlük tahmin (Open-Meteo `daily`).
@immutable
class WeatherDay {
  const WeatherDay({
    required this.day,
    required this.code,
    required this.max,
    required this.min,
    this.precipitationProbability = 0,
  });

  /// Günün Türkiye gece yarısı (an).
  final DateTime day;
  final int code;
  final double max;
  final double min;
  final int precipitationProbability;
}

/// `GET weather?lat&lng` (spec B.11 `WeatherDto`): kaynak, alınma anı, yuvarlanmış konum, eski veri
/// işareti ve Open-Meteo tahmini (Europe/Istanbul, 3 gün).
@immutable
class WeatherReport {
  const WeatherReport({
    required this.latitude,
    required this.longitude,
    required this.fetchedAt,
    required this.now,
    required this.hours,
    required this.days,
    this.isStale = false,
    this.source = 'open-meteo',
  });

  /// Sunucu yanıtını okur. Tahmin eksik ya da bozuksa null (kart "alınamıyor" der).
  static WeatherReport? tryParse(Object? json) {
    final r = JsonReader.of(json);
    final f = r.objOrNull('forecast');
    if (f == null) return null;
    try {
      final current = f.obj('current');
      final hourly = f.obj('hourly');
      final daily = f.obj('daily');
      final times = hourly.strings('time');
      List<Object?> col(JsonReader o, String key) {
        final v = o[key];
        return v is List ? v : const [];
      }

      double d(List<Object?> list, int i, [double fallback = 0]) =>
          i < list.length
          ? (JsonReader.toDouble(list[i]) ?? fallback)
          : fallback;
      int n(List<Object?> list, int i, [int fallback = 0]) => i < list.length
          ? (JsonReader.toDouble(list[i])?.round() ?? fallback)
          : fallback;

      final temp = col(hourly, 'temperature_2m');
      final code = col(hourly, 'weather_code');
      final prob = col(hourly, 'precipitation_probability');
      final precip = col(hourly, 'precipitation');
      final snow = col(hourly, 'snowfall');
      final vis = col(hourly, 'visibility');
      final gust = col(hourly, 'wind_gusts_10m');
      final hum = col(hourly, 'relative_humidity_2m');
      final day = col(hourly, 'is_day');
      final hours = <WeatherHour>[];
      for (var i = 0; i < times.length; i++) {
        final t = TrTime.parseLocal(times[i]);
        if (t == null) continue;
        hours.add(
          WeatherHour(
            time: t,
            temperature: d(temp, i),
            code: n(code, i),
            precipitationProbability: n(prob, i),
            precipitation: d(precip, i),
            snowfall: d(snow, i),
            visibility: d(vis, i, 99999),
            windGusts: d(gust, i),
            humidity: d(hum, i),
            isDay: n(day, i, 1) == 1,
          ),
        );
      }

      final dayTimes = daily.strings('time');
      final dCode = col(daily, 'weather_code');
      final dMax = col(daily, 'temperature_2m_max');
      final dMin = col(daily, 'temperature_2m_min');
      final dProb = col(daily, 'precipitation_probability_max');
      final days = <WeatherDay>[];
      for (var i = 0; i < dayTimes.length; i++) {
        final t = TrTime.parseDate(dayTimes[i]);
        if (t == null) continue;
        days.add(
          WeatherDay(
            day: t,
            code: n(dCode, i),
            max: d(dMax, i),
            min: d(dMin, i),
            precipitationProbability: n(dProb, i),
          ),
        );
      }

      if (!current.has('temperature_2m') && hours.isEmpty) return null;
      return WeatherReport(
        latitude: r.dec('latitude'),
        longitude: r.dec('longitude'),
        fetchedAt: r.dateUtc('fetchedAtUtc') ?? TrTime.now(),
        isStale: r.boolean('isStale'),
        source: r.str('source', 'open-meteo'),
        now: WeatherNow(
          temperature: current.dec('temperature_2m'),
          apparent:
              current.decOrNull('apparent_temperature') ??
              current.dec('temperature_2m'),
          code: current.integer('weather_code'),
          isDay: current.integer('is_day', 1) == 1,
          windSpeed: current.dec('wind_speed_10m'),
        ),
        hours: List.unmodifiable(hours),
        days: List.unmodifiable(days),
      );
    } catch (_) {
      return null;
    }
  }

  final double latitude;
  final double longitude;
  final DateTime fetchedAt;

  /// Kaynak yanıt vermedi; sunucunun (ya da cihazın) son bildiği veri.
  final bool isStale;
  final String source;
  final WeatherNow now;
  final List<WeatherHour> hours;
  final List<WeatherDay> days;

  /// Eski veri olarak işaretlenmiş kopya (çevrimdışı önbellek).
  WeatherReport asStale() => WeatherReport(
    latitude: latitude,
    longitude: longitude,
    fetchedAt: fetchedAt,
    now: now,
    hours: hours,
    days: days,
    isStale: true,
    source: source,
  );

  /// Bugünün özeti (yoksa null).
  WeatherDay? get today {
    final n = TrTime.now();
    for (final d in days) {
      if (TrTime.isSameDay(d.day, n)) return d;
    }
    return days.isEmpty ? null : days.first;
  }

  /// İçinde bulunulan saatten başlayarak [count] saat.
  List<WeatherHour> nextHours(int count, {DateTime? now}) {
    final start = _hourStart(now ?? TrTime.now());
    return hours.where((h) => !h.time.isBefore(start)).take(count).toList();
  }

  /// Sürüş uyarısı (spec A.6): buz, kar, fırtına, yoğun yağış, sis, rüzgâr ≥ 60 km/s. Pencere:
  /// içinde bulunulan saatten 24 saat; [at] (ör. planlanan teslimat) ilerideyse o andan 6 saat
  /// sonrasına kadar (en çok 48 saat). Önce ciddiyet, sonra en yakın zaman. Uyarı yoksa null.
  DrivingAlert? drivingAlert({DateTime? now, DateTime? at}) {
    final n = now ?? TrTime.now();
    final start = _hourStart(n);
    var end = start.add(const Duration(hours: 24));
    if (at != null && at.isAfter(n)) {
      final until = at.add(const Duration(hours: 6));
      final cap = start.add(const Duration(hours: 48));
      end = until.isAfter(cap) ? cap : (until.isAfter(end) ? until : end);
    }
    DrivingAlert? best;
    for (var i = 0; i < hours.length; i++) {
      final h = hours[i];
      if (h.time.isBefore(start) || !h.time.isBefore(end)) continue;
      // Son 6 saatte yağış: ıslak zemin donabilir.
      var recent = 0.0;
      for (var k = (i - 6).clamp(0, i); k <= i; k++) {
        recent += hours[k].precipitation;
      }
      final a = DrivingAlert.evaluate(h, recentPrecipitation: recent);
      if (a == null) continue;
      if (best == null || a.level.index > best.level.index) best = a;
    }
    return best;
  }

  static DateTime _hourStart(DateTime instant) {
    final u = instant.toUtc();
    return DateTime.utc(u.year, u.month, u.day, u.hour);
  }
}

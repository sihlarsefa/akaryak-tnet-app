import 'dart:math' as math;

import '../../core/models/json.dart';
import '../../core/network/fake/fake_server.dart';
import '../../core/utils/tr_time.dart';

/// Sahte hava senaryosu (dev menüsü / testler).
enum WeatherScenario {
  /// Bölgeye göre: Kocaeli doğusu yarın sabah yoğun yağış, Bursa bu gece sis, diğerleri açık.
  auto,
  clear,
  heavyRain,
  ice,
  snow,
  storm,
  fog,
  wind,
}

/// Sahte hava ucunun anahtarları (sunucu örneği başına).
class WeatherFakeControls {
  WeatherFakeControls._();

  static final _byServer = Expando<WeatherFakeControls>('weatherFakeControls');

  static WeatherFakeControls of(FakeServer server) =>
      _byServer[server] ??= WeatherFakeControls._();

  WeatherScenario scenario = WeatherScenario.auto;

  /// true: 503 `service_unavailable` "Hava durumu şu an kapalı."
  bool disabled = false;

  /// true: 503 "alınamıyor" (kaynak yanıt vermiyor, önbellek yok).
  bool failing = false;

  /// Saat (testler ezer).
  DateTime Function() now = TrTime.now;

  int calls = 0;
}

/// Hava durumu sahte ucu (sahibi A8): `GET weather?lat&lng` → `WeatherDto {source: "open-meteo",
/// fetchedAtUtc, latitude, longitude, isStale, forecast}`; forecast Open-Meteo biçimindedir
/// (current / hourly / daily, Europe/Istanbul, 3 gün; saatler Türkiye saatiyle, ofsetsiz).
void registerWeatherFakes(FakeServer server) {
  final ctl = WeatherFakeControls.of(server);
  server.get('weather', (req) {
    req.requireUser();
    final lat = double.tryParse(req.query('lat') ?? '');
    final lng = double.tryParse(req.query('lng') ?? '');
    final errors = <String, List<String>>{
      if (lat == null || lat < -90 || lat > 90)
        'lat': ['Enlem -90 ile 90 arasında olmalıdır.'],
      if (lng == null || lng < -180 || lng > 180)
        'lng': ['Boylam -180 ile 180 arasında olmalıdır.'],
    };
    if (errors.isNotEmpty) throw FakeResponse.validation(errors);
    ctl.calls++;
    if (ctl.disabled) {
      throw FakeResponse.problem(
        503,
        'service_unavailable',
        'Hava durumu şu an kapalı.',
      );
    }
    if (ctl.failing) {
      throw FakeResponse.problem(
        503,
        'service_unavailable',
        'Hava durumu şu an alınamıyor; lütfen daha sonra yeniden deneyin.',
      );
    }
    final rLat = (lat! * 20).round() / 20;
    final rLng = (lng! * 20).round() / 20;
    final scenario = ctl.scenario == WeatherScenario.auto
        ? _regional(rLat, rLng)
        : ctl.scenario;
    final now = ctl.now();
    return {
      'source': 'open-meteo',
      'fetchedAtUtc': now.toUtc().toIso8601String(),
      'latitude': rLat,
      'longitude': rLng,
      'isStale': false,
      'forecast': fakeOpenMeteo(rLat, rLng, now: now, scenario: scenario),
    };
  });
}

WeatherScenario _regional(double lat, double lng) {
  if (lat < 40.5) return WeatherScenario.fog;
  if (lng >= 29.6) return WeatherScenario.heavyRain;
  return WeatherScenario.clear;
}

/// Open-Meteo biçiminde 3 günlük (72 saat) deterministik tahmin. Saatler bugünün Türkiye gece
/// yarısından başlar. Senaryo saatleri: yoğun yağış yarın 07–10, sis bu gece 22–03, buzlanma yarın
/// 04–08, kar yarın 06–12, fırtına bu akşam 18–20, rüzgâr bugün 13–16.
JsonMap fakeOpenMeteo(
  double lat,
  double lng, {
  required DateTime now,
  WeatherScenario scenario = WeatherScenario.clear,
}) {
  final w = TrTime.wall(now);
  final start = TrTime.fromWall(w.year, w.month, w.day);
  // Konuma göre küçük, sabit sapma (farklı noktalar birbirinin aynısı olmasın).
  final seed = ((lat * 97 + lng * 61) * 10).round().abs() % 7;
  final base = 13.0 + seed * 0.6 - (lat - 40) * 1.5;

  final times = <String>[];
  final temp = <double>[];
  final hum = <int>[];
  final prob = <int>[];
  final precip = <double>[];
  final snow = <double>[];
  final code = <int>[];
  final vis = <double>[];
  final gust = <double>[];
  final isDay = <int>[];

  double r1(double v) => (v * 10).round() / 10;

  for (var i = 0; i < 72; i++) {
    final t = start.add(Duration(hours: i));
    final hour = TrTime.wall(t).hour;
    final day = i ~/ 24;
    final diurnal = math.sin((hour - 9) / 24 * 2 * math.pi) * 5;
    var tt = base + diurnal - day * 0.8;
    var c = hour >= 11 && hour <= 16 ? 1 : (hour >= 20 || hour < 6 ? 0 : 2);
    var h = 62 - diurnal * 3;
    var p = 5;
    var pr = 0.0;
    var sn = 0.0;
    var v = 24000.0;
    var g = 14.0 + seed + (hour >= 12 && hour <= 17 ? 6 : 0);

    bool between(int d, int from, int to) =>
        day == d && hour >= from && hour <= to;

    switch (scenario) {
      case WeatherScenario.heavyRain:
        if (between(1, 5, 6) || between(1, 11, 12)) {
          c = 61;
          p = 70;
          pr = 1.2;
        }
        if (between(1, 7, 10)) {
          c = 65;
          p = 95;
          pr = 6.5;
          h = 94;
        }
      case WeatherScenario.fog:
        if (between(0, 22, 23) || between(1, 0, 3)) {
          c = 45;
          v = 400;
          h = 97;
        }
      case WeatherScenario.ice:
        if (between(1, 4, 8)) {
          c = 66;
          tt = -1.5;
          pr = 0.4;
          p = 60;
          h = 95;
        }
      case WeatherScenario.snow:
        if (between(1, 6, 12)) {
          c = 73;
          tt = -0.5;
          sn = 1.4;
          p = 85;
        }
      case WeatherScenario.storm:
        if (between(0, 18, 20)) {
          c = 95;
          p = 90;
          pr = 3.0;
          g = 48;
        }
      case WeatherScenario.wind:
        if (between(0, 13, 16)) {
          g = 72;
          c = 3;
        }
      case WeatherScenario.clear:
      case WeatherScenario.auto:
        break;
    }

    times.add(TrTime.isoLocal(t).substring(0, 16));
    temp.add(r1(tt));
    hum.add(h.round().clamp(10, 100));
    prob.add(p);
    precip.add(pr);
    snow.add(sn);
    code.add(c);
    vis.add(v);
    gust.add(r1(g));
    isDay.add(hour >= 7 && hour < 19 ? 1 : 0);
  }

  final dayTimes = <String>[];
  final dCode = <int>[];
  final dMax = <double>[];
  final dMin = <double>[];
  final dProb = <int>[];
  for (var d = 0; d < 3; d++) {
    final slice = temp.sublist(d * 24, d * 24 + 24);
    final codes = code.sublist(d * 24, d * 24 + 24);
    dayTimes.add(TrTime.isoDate(start.add(Duration(days: d))));
    dCode.add(codes.reduce(math.max));
    dMax.add(slice.reduce(math.max));
    dMin.add(slice.reduce(math.min));
    dProb.add(prob.sublist(d * 24, d * 24 + 24).reduce(math.max));
  }

  final nowIndex = now.difference(start).inHours.clamp(0, 71);
  return {
    'latitude': lat,
    'longitude': lng,
    'timezone': 'Europe/Istanbul',
    'current': {
      'time': times[nowIndex],
      'temperature_2m': temp[nowIndex],
      'apparent_temperature': r1(temp[nowIndex] - 1.4),
      'is_day': isDay[nowIndex],
      'weather_code': code[nowIndex],
      'wind_speed_10m': r1(gust[nowIndex] * 0.6),
    },
    'hourly': {
      'time': times,
      'temperature_2m': temp,
      'relative_humidity_2m': hum,
      'precipitation_probability': prob,
      'precipitation': precip,
      'snowfall': snow,
      'weather_code': code,
      'visibility': vis,
      'wind_gusts_10m': gust,
      'is_day': isDay,
    },
    'daily': {
      'time': dayTimes,
      'weather_code': dCode,
      'temperature_2m_max': dMax,
      'temperature_2m_min': dMin,
      'precipitation_probability_max': dProb,
    },
  };
}

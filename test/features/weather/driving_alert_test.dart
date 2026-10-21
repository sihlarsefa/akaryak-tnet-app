// Sürüş uyarısı kuralları (spec A.6; F2GO `SurusUyarisi` vakaları) ve Open-Meteo ayrıştırması.
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:akaryakitnet/features/weather/data/driving_alert.dart';
import 'package:akaryakitnet/features/weather/data/weather_models.dart';
import 'package:akaryakitnet/features/weather/weather_fake.dart';
import 'package:flutter_test/flutter_test.dart';

/// Türkiye saatiyle an.
DateTime tr(int y, int m, int d, int h, [int min = 0]) =>
    TrTime.fromWall(y, m, d, h, min);

WeatherHour hour(
  DateTime t, {
  double temp = 12,
  int code = 1,
  double precip = 0,
  double snow = 0,
  double visibility = 24000,
  double gusts = 20,
  double humidity = 60,
}) => WeatherHour(
  time: t,
  temperature: temp,
  code: code,
  precipitation: precip,
  snowfall: snow,
  visibility: visibility,
  windGusts: gusts,
  humidity: humidity,
);

WeatherReport report(List<WeatherHour> hours) => WeatherReport(
  latitude: 40.75,
  longitude: 29.9,
  fetchedAt: DateTime.utc(2026, 10, 21, 7),
  now: const WeatherNow(
    temperature: 12,
    apparent: 11,
    code: 1,
    isDay: true,
    windSpeed: 10,
  ),
  hours: hours,
  days: const [],
);

void main() {
  final now = tr(2026, 10, 21, 10);

  group('tek saatlik kurallar (F2GO vakaları)', () {
    test('dondurucu yağmur kodu → buzlanma riski (tehlike)', () {
      final a = DrivingAlert.evaluate(hour(now, code: 66))!;
      expect(a.what, 'buzlanma riski');
      expect(a.level, DrivingAlertLevel.danger);
      expect(a.advice, contains('Yavaş sürün'));
    });

    test('≤ 1° ve son 6 saatte yağış → buzlanma', () {
      expect(
        DrivingAlert.evaluate(
          hour(now, temp: 0.5),
          recentPrecipitation: 0.4,
        )?.what,
        'buzlanma riski',
      );
    });

    test('≤ 1° ve nem ≥ %90 → buzlanma; nem düşükse uyarı yok', () {
      expect(
        DrivingAlert.evaluate(hour(now, temp: 1, humidity: 92))?.what,
        'buzlanma riski',
      );
      expect(DrivingAlert.evaluate(hour(now, temp: 1, humidity: 60)), isNull);
    });

    test('kar (miktar ya da kod) → kar yağışı (tehlike)', () {
      final byAmount = DrivingAlert.evaluate(hour(now, snow: 0.5))!;
      expect(byAmount.what, 'kar yağışı');
      expect(byAmount.level, DrivingAlertLevel.danger);
      expect(DrivingAlert.evaluate(hour(now, code: 73))?.what, 'kar yağışı');
      expect(DrivingAlert.evaluate(hour(now, code: 86))?.what, 'kar yağışı');
    });

    test('gök gürültüsü (95, 96, 99) → tehlike', () {
      for (final code in [95, 96, 99]) {
        final a = DrivingAlert.evaluate(hour(now, code: code))!;
        expect(a.what, 'gök gürültülü sağanak');
        expect(a.level, DrivingAlertLevel.danger);
      }
    });

    test('yağış ≥ 4 mm ya da kod 65/82 → yoğun yağış (dikkat)', () {
      final a = DrivingAlert.evaluate(hour(now, precip: 4))!;
      expect(a.what, 'yoğun yağış');
      expect(a.level, DrivingAlertLevel.caution);
      expect(DrivingAlert.evaluate(hour(now, code: 65))?.what, 'yoğun yağış');
      expect(DrivingAlert.evaluate(hour(now, code: 82))?.what, 'yoğun yağış');
      expect(DrivingAlert.evaluate(hour(now, precip: 3.9, code: 61)), isNull);
    });

    test('görüş < 1000 m ya da kod 45/48 → sis', () {
      expect(DrivingAlert.evaluate(hour(now, visibility: 800))?.what, 'sis');
      expect(DrivingAlert.evaluate(hour(now, code: 48))?.what, 'sis');
      expect(DrivingAlert.evaluate(hour(now, visibility: 1000)), isNull);
    });

    test('rüzgâr hamlesi ≥ 60 km/s → kuvvetli rüzgâr; 59 → yok', () {
      final a = DrivingAlert.evaluate(hour(now, gusts: 72.4))!;
      expect(a.what, 'kuvvetli rüzgâr (72 km/s)');
      expect(a.level, DrivingAlertLevel.caution);
      expect(DrivingAlert.evaluate(hour(now, gusts: 59)), isNull);
      expect(
        DrivingAlert.evaluate(hour(now, gusts: 60))?.level,
        DrivingAlertLevel.caution,
      );
    });

    test('kural önceliği: buz, kardan önce gelir', () {
      expect(
        DrivingAlert.evaluate(hour(now, code: 66, snow: 2))?.what,
        'buzlanma riski',
      );
    });

    test('açık hava → uyarı yok', () {
      expect(DrivingAlert.evaluate(hour(now)), isNull);
    });
  });

  group('24 saatlik pencere', () {
    List<WeatherHour> day(Map<int, WeatherHour Function(DateTime t)> at) => [
      for (var i = -3; i < 40; i++)
        (at[i] ?? hour)(now.add(Duration(hours: i))),
    ];

    test('önce ciddiyet, sonra en yakın saat', () {
      final r = report(
        day({
          1: (t) => hour(t, precip: 6),
          5: (t) => hour(t, code: 95),
          8: (t) => hour(t, code: 66),
        }),
      );
      final a = r.drivingAlert(now: now)!;
      expect(a.level, DrivingAlertLevel.danger);
      expect(a.what, 'gök gürültülü sağanak', reason: 'en yakın tehlike');
    });

    test('aynı ciddiyette en yakın olan seçilir', () {
      final r = report(
        day({3: (t) => hour(t, visibility: 500), 2: (t) => hour(t, precip: 5)}),
      );
      expect(r.drivingAlert(now: now)!.what, 'yoğun yağış');
    });

    test('geçmiş saatler ve 24 saat sonrası sayılmaz', () {
      final r = report(
        day({-2: (t) => hour(t, code: 95), 25: (t) => hour(t, code: 95)}),
      );
      expect(r.drivingAlert(now: now), isNull);
    });

    test(
      'ileri teslimat ([at]) pencereyi teslimattan 6 saat sonrasına uzatır',
      () {
        final r = report(day({30: (t) => hour(t, snow: 1)}));
        expect(r.drivingAlert(now: now), isNull);
        final at = now.add(const Duration(hours: 27));
        expect(r.drivingAlert(now: now, at: at)?.what, 'kar yağışı');
        // Geçmişteki teslimat pencereyi değiştirmez.
        expect(
          r.drivingAlert(now: now, at: now.subtract(const Duration(hours: 2))),
          isNull,
        );
      },
    );

    test('son 6 saatin yağışı ıslak zemini buza çevirir', () {
      final r = report(
        day({
          2: (t) => hour(t, precip: 0.3, code: 61),
          5: (t) => hour(t, temp: 0, humidity: 50),
        }),
      );
      expect(r.drivingAlert(now: now)!.what, 'buzlanma riski');
    });
  });

  group('zaman ifadesi', () {
    String phrase(DateTime t, DateTime n) => DrivingAlert.timePhrase(t, now: n);

    test('aynı saat → "Şu an"', () {
      expect(
        phrase(tr(2026, 10, 21, 10, 40), tr(2026, 10, 21, 10, 5)),
        'Şu an',
      );
    });

    test('bugün: sabah / öğlen / akşam / gece', () {
      final n = tr(2026, 10, 21, 6);
      expect(phrase(tr(2026, 10, 21, 8), n), 'Bu sabah');
      expect(phrase(tr(2026, 10, 21, 14), n), 'Bugün öğlen');
      expect(phrase(tr(2026, 10, 21, 19), n), 'Bu akşam');
      expect(phrase(tr(2026, 10, 21, 23), n), 'Bu gece');
    });

    test('23:00\'te 02:00 "Bu gece"; 02:00\'de 08:00 "Bu sabah"', () {
      expect(phrase(tr(2026, 10, 22, 2), tr(2026, 10, 21, 23)), 'Bu gece');
      expect(phrase(tr(2026, 10, 22, 8), tr(2026, 10, 22, 2)), 'Bu sabah');
    });

    test('yarın: sabah / öğlen / akşam / gece', () {
      final n = tr(2026, 10, 21, 10);
      expect(phrase(tr(2026, 10, 22, 7), n), 'Yarın sabah');
      expect(phrase(tr(2026, 10, 22, 12), n), 'Yarın öğlen');
      expect(phrase(tr(2026, 10, 22, 18), n), 'Yarın akşam');
      expect(phrase(tr(2026, 10, 22, 22), n), 'Yarın gece');
      expect(phrase(tr(2026, 10, 23, 3), n), 'Yarın gece', reason: 'gece 03');
    });

    test('daha ileri günler gün adıyla', () {
      final n = tr(2026, 10, 21, 10); // Çarşamba
      expect(phrase(tr(2026, 10, 23, 8), n), 'Cuma sabahı');
      expect(phrase(tr(2026, 10, 23, 19), n), 'Cuma akşamı');
    });

    test('başlık: "Yarın sabah buzlanma riski"', () {
      final a = DrivingAlert.evaluate(hour(tr(2026, 10, 22, 7), code: 66))!;
      expect(a.title(now: tr(2026, 10, 21, 10)), 'Yarın sabah buzlanma riski');
    });
  });

  group('Open-Meteo ayrıştırma (sahte sunucu biçimi)', () {
    test('72 saat + 3 gün, saatler Türkiye saatiyle', () {
      final json = {
        'source': 'open-meteo',
        'fetchedAtUtc': '2026-10-21T07:00:00+00:00',
        'latitude': 40.75,
        'longitude': 29.9,
        'isStale': false,
        'forecast': fakeOpenMeteo(40.75, 29.9, now: now),
      };
      final r = WeatherReport.tryParse(json)!;
      expect(r.hours, hasLength(72));
      expect(r.days, hasLength(3));
      expect(r.hours.first.time, tr(2026, 10, 21, 0));
      expect(r.days.first.day, tr(2026, 10, 21, 0));
      expect(r.fetchedAt, DateTime.utc(2026, 10, 21, 7));
      final next = r.nextHours(3, now: now);
      expect(next.first.time, tr(2026, 10, 21, 10));
      expect(next, hasLength(3));
    });

    test('yoğun yağış senaryosu → "Yarın sabah yoğun yağış"', () {
      final json = {
        'forecast': fakeOpenMeteo(
          40.75,
          29.9,
          now: now,
          scenario: WeatherScenario.heavyRain,
        ),
      };
      final a = WeatherReport.tryParse(json)!.drivingAlert(now: now)!;
      expect(a.title(now: now), 'Yarın sabah yoğun yağış');
      expect(a.level, DrivingAlertLevel.caution);
    });

    test('her senaryonun uyarısı', () {
      String? what(WeatherScenario s) => WeatherReport.tryParse({
        'forecast': fakeOpenMeteo(40.9, 29.3, now: now, scenario: s),
      })!.drivingAlert(now: now)?.what;
      expect(what(WeatherScenario.clear), isNull);
      expect(what(WeatherScenario.ice), 'buzlanma riski');
      expect(what(WeatherScenario.snow), 'kar yağışı');
      expect(what(WeatherScenario.storm), 'gök gürültülü sağanak');
      expect(what(WeatherScenario.fog), 'sis');
      expect(what(WeatherScenario.wind), startsWith('kuvvetli rüzgâr'));
    });

    test('tahmin yoksa null', () {
      expect(WeatherReport.tryParse({'source': 'open-meteo'}), isNull);
      expect(WeatherReport.tryParse('x'), isNull);
    });

    test('hücre: 0,05° ızgara, aynı hücre eşit', () {
      final a = WeatherCell.of(40.7654, 29.9408);
      final b = WeatherCell.of(40.7612, 29.9301);
      expect(a, b);
      expect(a.lat, 40.75);
      expect(a.lng, 29.95);
      expect(a.key, '40.75_29.95');
    });
  });
}

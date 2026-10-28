import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import 'weather_models.dart';

/// Uyarının ciddiyeti (sıra önemlidir: büyük = daha ciddi).
enum DrivingAlertLevel { caution, danger }

/// Tek bir saatlik tahminden sürüş uyarısı (F2GO `SurusUyarisi` uyarlaması, spec A.6): buzlanma,
/// kar, gök gürültülü sağanak, yoğun yağış, sis, kuvvetli rüzgâr (≥ 60 km/s). Öneriler "siz" diliyle.
@immutable
class DrivingAlert {
  const DrivingAlert({
    required this.time,
    required this.what,
    required this.advice,
    required this.icon,
    required this.level,
  });

  /// Uyarının saati (an).
  final DateTime time;

  /// "buzlanma riski", "yoğun yağış" …
  final String what;
  final String advice;
  final IconData icon;
  final DrivingAlertLevel level;

  /// "Yarın sabah buzlanma riski".
  String title({DateTime? now}) => '${timePhrase(time, now: now)} $what';

  /// Rüzgâr hamlesi eşiği (km/s).
  static const windGustLimit = 60.0;

  static DrivingAlert? evaluate(
    WeatherHour h, {
    double recentPrecipitation = 0,
  }) {
    final k = h.code;
    final freezing = const {56, 57, 66, 67}.contains(k);
    if (freezing ||
        (h.temperature <= 1 &&
            (recentPrecipitation > 0.1 || h.humidity >= 90))) {
      return DrivingAlert(
        time: h.time,
        what: 'buzlanma riski',
        advice: 'Yavaş sürün; ani fren ve direksiyon hareketlerinden kaçının.',
        icon: PhosphorIconsRegular.snowflake,
        level: DrivingAlertLevel.danger,
      );
    }
    if (h.snowfall > 0.1 || const {71, 73, 75, 77, 85, 86}.contains(k)) {
      return DrivingAlert(
        time: h.time,
        what: 'kar yağışı',
        advice: 'Kış lastiği ve zincir bulundurun; takip mesafesini artırın.',
        icon: PhosphorIconsRegular.snowflake,
        level: DrivingAlertLevel.danger,
      );
    }
    if (const {95, 96, 99}.contains(k)) {
      return DrivingAlert(
        time: h.time,
        what: 'gök gürültülü sağanak',
        advice: 'Mümkünse yola çıkmayı erteleyin; ağaç altına park etmeyin.',
        icon: PhosphorIconsRegular.cloudLightning,
        level: DrivingAlertLevel.danger,
      );
    }
    if (h.precipitation >= 4 || const {65, 82}.contains(k)) {
      return DrivingAlert(
        time: h.time,
        what: 'yoğun yağış',
        advice: 'Hızınızı düşürün; takip mesafesini iki katına çıkarın.',
        icon: PhosphorIconsRegular.cloudRain,
        level: DrivingAlertLevel.caution,
      );
    }
    if (h.visibility < 1000 || const {45, 48}.contains(k)) {
      return DrivingAlert(
        time: h.time,
        what: 'sis',
        advice: 'Kısa far ve sis farını yakın; uzun far kullanmayın.',
        icon: PhosphorIconsRegular.cloudFog,
        level: DrivingAlertLevel.caution,
      );
    }
    if (h.windGusts >= windGustLimit) {
      return DrivingAlert(
        time: h.time,
        what: 'kuvvetli rüzgâr (${Fmt.integer(h.windGusts.round())} km/s)',
        advice: 'Direksiyonu sıkı tutun; köprü ve viyadüklerde dikkatli olun.',
        icon: PhosphorIconsRegular.wind,
        level: DrivingAlertLevel.caution,
      );
    }
    return null;
  }

  /// "Şu an", "Bu sabah", "Yarın akşam", "Perşembe sabahı" … (Türkiye saati). Gece 00–05 bir önceki
  /// günün gecesi sayılır: 23:00'te 02:00 "Bu gece"; gece 02:00'de 08:00 "Bu sabah".
  static String timePhrase(DateTime instant, {DateTime? now}) {
    final s = TrTime.wall(now ?? TrTime.now());
    final t = TrTime.wall(instant);
    // Takvim hesapları UTC alanlarla: cihazın yaz saati geçişi gün farkını bozmasın.
    DateTime calendar(DateTime x) => DateTime.utc(x.year, x.month, x.day);
    DateTime night(DateTime x) =>
        calendar(DateTime.utc(x.year, x.month, x.day, x.hour - 5));
    if (calendar(t) == calendar(s) && t.hour == s.hour) return 'Şu an';
    final diff = calendar(t) == calendar(s)
        ? 0
        : night(t).difference(night(s)).inHours ~/ 24;
    final h = t.hour;
    final part = h >= 5 && h < 11
        ? 0
        : h >= 11 && h < 17
        ? 1
        : h >= 17 && h < 21
        ? 2
        : 3;
    if (diff <= 0) {
      return const ['Bu sabah', 'Bugün öğlen', 'Bu akşam', 'Bu gece'][part];
    }
    if (diff == 1) {
      return const [
        'Yarın sabah',
        'Yarın öğlen',
        'Yarın akşam',
        'Yarın gece',
      ][part];
    }
    final day = Fmt.weekdayNames[night(t).weekday - 1];
    return '$day ${const ['sabahı', 'öğlen', 'akşamı', 'gecesi'][part]}';
  }
}

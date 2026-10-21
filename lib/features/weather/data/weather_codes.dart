import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';

/// Open-Meteo hava kodunun (WMO) Türkçe adı, ikonu ve tonu (F2GO `havaKodu` uyarlaması; mor yok).
@immutable
class WeatherCondition {
  const WeatherCondition(this.label, this.icon, this.tone);

  final String label;
  final IconData icon;

  /// İkon kutusunun tonu (renk tek başına anlam taşımaz; ad her zaman yazılır).
  final AknTone tone;

  /// WMO kodu → durum. Gece açık/az bulutlu havada ay ikonu.
  static WeatherCondition of(int code, {bool isDay = true}) {
    if (code == 0) {
      return isDay
          ? const WeatherCondition(
              'Açık',
              Icons.wb_sunny_rounded,
              AknTone.brand,
            )
          : const WeatherCondition(
              'Açık',
              Icons.nightlight_round,
              AknTone.neutral,
            );
    }
    if (code == 1) {
      return isDay
          ? const WeatherCondition(
              'Az bulutlu',
              Icons.wb_sunny_rounded,
              AknTone.brand,
            )
          : const WeatherCondition(
              'Az bulutlu',
              Icons.nightlight_round,
              AknTone.neutral,
            );
    }
    if (code == 2) {
      return const WeatherCondition(
        'Parçalı bulutlu',
        Icons.wb_cloudy_rounded,
        AknTone.neutral,
      );
    }
    if (code == 3) {
      return const WeatherCondition(
        'Kapalı',
        Icons.cloud_rounded,
        AknTone.neutral,
      );
    }
    if (code == 45 || code == 48) {
      return const WeatherCondition('Sisli', Icons.foggy, AknTone.neutral);
    }
    if (code >= 51 && code <= 55) {
      return const WeatherCondition(
        'Çiseleme',
        Icons.grain_rounded,
        AknTone.info,
      );
    }
    if (code == 56 || code == 57 || code == 66 || code == 67) {
      return const WeatherCondition(
        'Dondurucu yağmur',
        Icons.ac_unit_rounded,
        AknTone.info,
      );
    }
    if (code == 61) {
      return const WeatherCondition(
        'Hafif yağmur',
        Icons.water_drop_rounded,
        AknTone.info,
      );
    }
    if (code == 63) {
      return const WeatherCondition(
        'Yağmurlu',
        Icons.water_drop_rounded,
        AknTone.info,
      );
    }
    if (code == 65) {
      return const WeatherCondition(
        'Kuvvetli yağmur',
        Icons.water_drop_rounded,
        AknTone.info,
      );
    }
    if (code >= 71 && code <= 77) {
      return const WeatherCondition(
        'Karlı',
        Icons.ac_unit_rounded,
        AknTone.info,
      );
    }
    if (code >= 80 && code <= 82) {
      return const WeatherCondition(
        'Sağanak',
        Icons.water_drop_rounded,
        AknTone.info,
      );
    }
    if (code == 85 || code == 86) {
      return const WeatherCondition(
        'Kar sağanağı',
        Icons.ac_unit_rounded,
        AknTone.info,
      );
    }
    if (code >= 95) {
      return const WeatherCondition(
        'Gök gürültülü',
        Icons.thunderstorm_rounded,
        AknTone.warn,
      );
    }
    return const WeatherCondition(
      'Bulutlu',
      Icons.cloud_rounded,
      AknTone.neutral,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env/app_config_controller.dart';
import '../../../core/ui/ui.dart';
import '../application/weather_providers.dart';
import '../data/driving_alert.dart';
import '../data/weather_models.dart';

/// Sürüş uyarısı bandı (spec A.6): buz, kar, fırtına, yoğun yağış, sis, rüzgâr ≥ 60 km/s için
/// F2GO'daki "Yarın sabah …" diliyle uyarı ve öneri. Uyarı yoksa (ya da hava durumu kapalı / veri
/// yoksa) hiçbir şey çizmez; varsa altında 12 px boşluk bırakır. Ekrandayken aynı noktanın
/// `WeatherCard`'ı sürüş durumunu tekrar yazmaz. Sınıf adı ve kurucu imzası sabittir.
class DrivingAlertBanner extends ConsumerStatefulWidget {
  const DrivingAlertBanner({
    super.key,
    required this.lat,
    required this.lng,
    this.at,
  });

  final double lat;
  final double lng;

  /// Uyarının değerlendirileceği an (varsayılan: şimdi ve önümüzdeki saatler).
  final DateTime? at;

  @override
  ConsumerState<DrivingAlertBanner> createState() => _DrivingAlertBannerState();
}

class _DrivingAlertBannerState extends ConsumerState<DrivingAlertBanner> {
  WeatherCell? _registered;
  late final AlertBannerRegistry _registry = ref.read(
    alertBannerRegistryProvider,
  );

  void _register(WeatherCell? cell) {
    if (cell == _registered) return;
    final old = _registered;
    if (old != null) _registry.remove(old);
    if (cell != null) _registry.add(cell);
    _registered = cell;
  }

  @override
  void dispose() {
    final old = _registered;
    if (old != null) _registry.remove(old);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = ref.watch(appConfigProvider.select((c) => c.features.weather));
    final valid = widget.lat.isFinite && widget.lng.isFinite;
    final cell = on && valid ? WeatherCell.of(widget.lat, widget.lng) : null;
    if (cell == null) {
      _register(null);
      return const SizedBox.shrink();
    }
    final report = ref.watch(weatherProvider(cell)).valueOrNull;
    final alert = report?.drivingAlert(at: widget.at);
    // Bant uyarı gösterirken aynı noktanın kartı sürüş durumunu yazmaz (bandın penceresi kartınkini
    // kapsar: uyarı yoksa kartın "Sürüş için uygun hava" demesi tutarlıdır).
    _register(alert == null ? null : cell);
    return AnimatedSize(
      duration: AknMotion.of(context, AknMotion.base),
      curve: AknMotion.emphasizedCurve,
      alignment: Alignment.topCenter,
      child: alert == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AknBanner(
                tone: alert.level == DrivingAlertLevel.danger
                    ? AknTone.danger
                    : AknTone.warn,
                icon: alert.icon,
                title: alert.title(),
                message: alert.advice,
              ),
            ),
    );
  }
}

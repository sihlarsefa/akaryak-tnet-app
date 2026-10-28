import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env/app_config_controller.dart';
import '../../../core/ui/ui.dart';
import '../application/weather_providers.dart';
import '../data/driving_alert.dart';
import '../data/weather_models.dart';

/// Sürüş uyarısı bandı (spec A.6; tasarım v3): buz, kar, fırtına, yoğun yağış, sis, rüzgâr ≥ 60 km/s için
/// F2GO'daki "Yarın sabah …" diliyle uyarı ve öneri — tonun kuyusunda (dikkat koyu sarı, tehlike kırmızı;
/// r20, ince çizgi), solda tonun dolu renginde 40 px disk ve dolu simge. Bant yumuşakça açılır, disk "pop"
/// ile gelir ve iki kez dalga yayar (sonlu; azaltılmış harekette durur). Uyarı yoksa (ya da hava durumu
/// kapalı / veri yoksa) hiçbir şey çizmez; varsa altında 12 px boşluk bırakır. Ekrandayken aynı noktanın
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
    return AknAnimatedSize(
      duration: AknMotion.slow,
      curve: AknMotion.emphasizedCurve,
      alignment: Alignment.topCenter,
      child: alert == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AlertWell(
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

/// Uyarı kuyusu: tonun zemini ve çizgisi, 40 px dolu disk (açılışta "pop" + iki dalga), başlık ve öneri.
/// Ekran okuyucu tek düğüm olarak "başlık. öneri" okur (canlı bölge).
class _AlertWell extends StatefulWidget {
  const _AlertWell({
    required this.tone,
    required this.icon,
    required this.title,
    required this.message,
  });

  final AknTone tone;
  final IconData icon;
  final String title;
  final String message;

  @override
  State<_AlertWell> createState() => _AlertWellState();
}

class _AlertWellState extends State<_AlertWell>
    with SingleTickerProviderStateMixin {
  /// 0–0,3 disk "pop", 0,2–1 iki dalga (sonlu).
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else {
      unawaited(_c.forward());
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final tc = c.tone(widget.tone);
    final disc = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: tc.solid, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(_fill(widget.icon), size: 21, color: tc.onSolid),
    );
    return Semantics(
      container: true,
      liveRegion: true,
      label: '${widget.title}. ${widget.message}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        decoration: BoxDecoration(
          color: tc.bg,
          borderRadius: AknRadius.card,
          border: Border.all(color: tc.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox.square(
              dimension: 40,
              child: AnimatedBuilder(
                animation: _c,
                child: disc,
                builder: (context, child) {
                  final v = _c.value;
                  final pop = AknMotion.pop.transform((v / 0.3).clamp(0, 1));
                  // İki dalga: her biri dalga süresinin yarısında 40 → 64 px büyüyüp söner.
                  final w = ((v - 0.2) / 0.8).clamp(0.0, 1.0);
                  final wave = (w * 2) % 1.0;
                  final waving = w > 0 && w < 1;
                  return Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      if (waving)
                        Transform.scale(
                          scale: 1 + 0.6 * wave,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: tc.solid.withValues(
                                alpha: 0.28 * (1 - wave),
                              ),
                            ),
                          ),
                        ),
                      Transform.scale(scale: 0.4 + 0.6 * pop, child: child),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    style: t.bodyStrong.copyWith(color: c.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.message,
                    style: t.bodySmall.copyWith(color: c.ink),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Uyarı simgesinin dolu eşi (diskte dolu glif).
IconData _fill(IconData icon) {
  if (icon == PhosphorIconsRegular.snowflake) {
    return PhosphorIconsFill.snowflake;
  }
  if (icon == PhosphorIconsRegular.cloudLightning) {
    return PhosphorIconsFill.cloudLightning;
  }
  if (icon == PhosphorIconsRegular.cloudRain) {
    return PhosphorIconsFill.cloudRain;
  }
  if (icon == PhosphorIconsRegular.cloudFog) return PhosphorIconsFill.cloudFog;
  if (icon == PhosphorIconsRegular.wind) return PhosphorIconsFill.wind;
  return icon;
}

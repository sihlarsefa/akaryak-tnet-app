import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../copy.dart';
import '../data/driving_alert.dart';
import '../data/weather_codes.dart';
import '../data/weather_models.dart';

/// Sıcaklık: `14°` (yuvarlanmış; eksi değerler `-3°`).
String temp(double v) => '${v.round()}°';

/// Saat etiketi: `16:00`.
String hourLabel(DateTime instant) => Fmt.time(instant);

/// Simgenin dolu (Fill) eşi: büyük karoda dolu glif kullanılır.
IconData _filled(IconData icon) {
  if (icon == PhosphorIconsRegular.sun) return PhosphorIconsFill.sun;
  if (icon == PhosphorIconsRegular.moon) return PhosphorIconsFill.moon;
  if (icon == PhosphorIconsRegular.cloudSun) return PhosphorIconsFill.cloudSun;
  if (icon == PhosphorIconsRegular.cloud) return PhosphorIconsFill.cloud;
  if (icon == PhosphorIconsRegular.cloudFog) return PhosphorIconsFill.cloudFog;
  if (icon == PhosphorIconsRegular.cloudRain) {
    return PhosphorIconsFill.cloudRain;
  }
  if (icon == PhosphorIconsRegular.snowflake) {
    return PhosphorIconsFill.snowflake;
  }
  if (icon == PhosphorIconsRegular.cloudLightning) {
    return PhosphorIconsFill.cloudLightning;
  }
  if (icon == PhosphorIconsRegular.wind) return PhosphorIconsFill.wind;
  return icon;
}

/// Durumun karo renkleri (tasarım v3: yalnız sıcak ve nötr; mavi yok): güneş sıcak turuncu (kahraman
/// kartın karosu), fırtına koyu sarı, diğerleri grafit kuyu.
(Color bg, Color fg) _tileColors(AknColors c, AknTone tone) => switch (tone) {
  AknTone.brand => (c.plateIconFill, c.plateAccent),
  AknTone.warn => (c.warn.bg, c.warn.fg),
  AknTone.info => (c.surfaceAlt, c.ink),
  _ => (c.surfaceAlt, c.dim),
};

/// Hava durumu karosu (tasarım v3): yuvarlak köşeli kare, durumun sıcak / nötr tonunda; içinde dolu
/// Phosphor simgesi. Güneş çok yavaş döner, bulutlar hafifçe süzülür (ortam hareketi).
class WeatherIconTile extends StatelessWidget {
  const WeatherIconTile({super.key, required this.condition, this.size = 52});

  final WeatherCondition condition;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final (bg, fg) = _tileColors(c, condition.tone);
    final sun = condition.icon == PhosphorIconsRegular.sun;
    final glyph = Icon(_filled(condition.icon), size: size * 0.54, color: fg);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(size * 0.31),
          gradient: sun
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [c.plateTint, bg],
                )
              : null,
        ),
        alignment: Alignment.center,
        child: sun
            ? AknAmbient(
                period: const Duration(seconds: 24),
                curve: Curves.linear,
                builder: (context, t, child) =>
                    Transform.rotate(angle: 2 * math.pi * t, child: child),
                child: glyph,
              )
            : AknAmbient(
                period: AknMotion.float,
                reverse: true,
                builder: (context, t, child) => Transform.translate(
                  offset: Offset(2.5 * t - 1.25, 0),
                  child: child,
                ),
                child: glyph,
              ),
      ),
    );
  }
}

/// Saatlik tahmin hücresi (tasarım v3): hap biçimli kuyu (`surfaceAlt`, r16) — saat, simge, sıcaklık
/// (eş genişlikte rakamlar) ve (%20 üstünde) yağış olasılığı. Şimdiki saat yumuşak turuncu zeminde.
class WeatherHourCell extends StatelessWidget {
  const WeatherHourCell({
    super.key,
    required this.hour,
    this.label,
    this.highlight = false,
  });

  final WeatherHour hour;

  /// Varsayılan saat yerine (ör. "Şimdi").
  final String? label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final cond = WeatherCondition.of(hour.code, isDay: hour.isDay);
    final time = label ?? hourLabel(hour.time);
    final rain = hour.precipitationProbability >= 20
        ? '%${hour.precipitationProbability}'
        : null;
    final (_, accent) = _tileColors(c, cond.tone);
    return Semantics(
      label:
          '$time, ${temp(hour.temperature)}, ${cond.label}'
          '${rain == null ? '' : ', yağış olasılığı $rain'}',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 56),
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
        decoration: BoxDecoration(
          color: highlight ? c.brandSoft : c.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: highlight ? Border.all(color: c.brandLine) : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              time,
              style: t.captionStrong.copyWith(
                color: highlight ? c.brandInk : c.dim,
                fontFeatures: AknNumerals.tabular,
              ),
            ),
            const SizedBox(height: 6),
            Icon(_filled(cond.icon), size: 22, color: accent),
            const SizedBox(height: 6),
            Text(
              temp(hour.temperature),
              style: t.amount.copyWith(color: c.ink),
            ),
            if (rain != null)
              Text(
                rain,
                style: t.captionStrong.copyWith(
                  color: c.dim,
                  fontFeatures: AknNumerals.tabular,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Sürüş durumu şeridi (tasarım v3): tonun kuyusu (yumuşak zemin + ince çizgi, r16), solda tonun dolu
/// renginde 34 px disk ve beyaz simge, ink başlık ve öneri: uyarı (dikkat / tehlike) ya da "Sürüş için
/// uygun hava".
class DrivingStatusStrip extends StatelessWidget {
  const DrivingStatusStrip({super.key, required this.alert, this.now});

  final DrivingAlert? alert;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final a = alert;
    final tone = a == null
        ? AknTone.ok
        : a.level == DrivingAlertLevel.danger
        ? AknTone.danger
        : AknTone.warn;
    final tc = c.tone(tone);
    final title = a == null ? WeatherCopy.driveOk : a.title(now: now);
    final body = a == null ? WeatherCopy.driveOkHint : a.advice;
    return Semantics(
      container: true,
      label: '$title. $body',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
        decoration: BoxDecoration(
          color: tc.bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tc.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: tc.solid,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                a == null ? PhosphorIconsBold.check : _filled(a.icon),
                size: 18,
                color: tc.onSolid,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: t.bodyStrong.copyWith(color: c.ink)),
                  const SizedBox(height: 2),
                  Text(body, style: t.bodySmall.copyWith(color: c.ink)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Şimdiki durum satırı (kart ve ayrıntı sayfası): durum karosu, "Hava durumu" etiketi, sıcaklık
/// (eş genişlikte, ilk görünüşte sayarak gelir) ve durum adı.
class WeatherNowRow extends StatelessWidget {
  const WeatherNowRow({
    super.key,
    required this.report,
    this.large = false,
    this.trailing,
  });

  final WeatherReport report;
  final bool large;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final now = report.now;
    final cond = WeatherCondition.of(now.code, isDay: now.isDay);
    final figure = (large ? t.numberLarge : t.number).copyWith(
      fontSize: large ? 40 : 30,
      height: large ? 44 / 40 : 34 / 30,
      color: c.ink,
    );
    return Row(
      children: [
        WeatherIconTile(condition: cond, size: large ? 60 : 52),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                report.isStale
                    ? '${WeatherCopy.title}, ${WeatherCopy.stale}'
                    : WeatherCopy.title,
                style: t.caption.copyWith(color: c.dim),
              ),
              const SizedBox(height: 2),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 8,
                children: [
                  AnimatedNumber(
                    value: now.temperature.round(),
                    format: (v) => '${v.round()}°',
                    style: figure,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      cond.label,
                      style: t.bodyStrong.copyWith(color: c.ink),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// "En yüksek 18°, en düşük 9°, hissedilen 14°".
String weatherSummaryLine(WeatherReport r) {
  final d = r.today;
  if (d == null) return '${WeatherCopy.feelsLike} ${temp(r.now.apparent)}';
  return [
    '${WeatherCopy.high} ${temp(d.max)}',
    'en düşük ${temp(d.min)}',
    'hissedilen ${temp(r.now.apparent)}',
  ].join(', ');
}

/// Ekran okuyucu özeti: "Hava durumu: 14 derece, parçalı bulutlu, hissedilen 12 derece".
String weatherSemantics(WeatherReport r) {
  final cond = WeatherCondition.of(r.now.code, isDay: r.now.isDay);
  final d = r.today;
  return [
    '${WeatherCopy.title}: ${r.now.temperature.round()} derece',
    cond.label,
    'hissedilen ${r.now.apparent.round()} derece',
    if (d != null) 'en yüksek ${d.max.round()}, en düşük ${d.min.round()}',
    if (r.isStale) WeatherCopy.stale,
  ].join(', ');
}

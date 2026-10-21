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

/// Saatlik tahmin hücresi: saat, ikon, sıcaklık ve (%20 üstünde) yağış olasılığı.
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
    return Semantics(
      label:
          '$time, ${temp(hour.temperature)}, ${cond.label}'
          '${rain == null ? '' : ', yağış olasılığı $rain'}',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 56),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: highlight ? c.brandSoft : c.surfaceAlt,
          borderRadius: AknRadius.card,
          border: Border.all(color: highlight ? c.brandLine : c.lineSoft),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(time, style: t.captionStrong.copyWith(color: c.text)),
            const SizedBox(height: 4),
            Icon(cond.icon, size: 20, color: c.tone(cond.tone).fg),
            const SizedBox(height: 4),
            Text(temp(hour.temperature), style: t.bodyStrong),
            if (rain != null)
              Text(rain, style: t.captionStrong.copyWith(color: c.info.fg)),
          ],
        ),
      ),
    );
  }
}

/// Sürüş durumu şeridi: uyarı (dikkat / tehlike) ya da "Sürüş için uygun hava".
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
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: tc.bg,
          borderRadius: AknRadius.card,
          border: Border.all(color: tc.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                a?.icon ?? Icons.check_circle_rounded,
                size: 18,
                color: tc.fg,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: t.label.copyWith(color: tc.fg)),
                  const SizedBox(height: 2),
                  Text(body, style: t.bodySmall.copyWith(color: c.text)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Şimdiki durum satırı (kart ve ayrıntı sayfası).
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
    return Row(
      children: [
        AknIconBox(icon: cond.icon, tone: cond.tone, size: large ? 52 : 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                report.isStale
                    ? '${WeatherCopy.title} · ${WeatherCopy.stale}'
                    : WeatherCopy.title,
                style: t.caption.copyWith(color: c.dim),
              ),
              const SizedBox(height: 2),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 8,
                children: [
                  Text(
                    temp(now.temperature),
                    style: (large ? t.display : t.title).copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(cond.label, style: t.bodyStrong),
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

/// "En yüksek 18° · en düşük 9° · hissedilen 14°".
String weatherSummaryLine(WeatherReport r) {
  final d = r.today;
  if (d == null) return '${WeatherCopy.feelsLike} ${temp(r.now.apparent)}';
  return [
    '${WeatherCopy.high} ${temp(d.max)}',
    'en düşük ${temp(d.min)}',
    'hissedilen ${temp(r.now.apparent)}',
  ].join(' · ');
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

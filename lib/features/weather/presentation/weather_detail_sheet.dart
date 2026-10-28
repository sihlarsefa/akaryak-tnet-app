import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import '../copy.dart';
import '../data/weather_codes.dart';
import '../data/weather_models.dart';
import 'weather_widgets.dart';

/// Saatlik (12 saat; hap hücreler, "Şimdi" yumuşak turuncu) ve 3 günlük tahmin (durum karolu satırlar),
/// sürüş durumu ve Open-Meteo atfı (tasarım v3). Sayfa açılırken hücreler ve gün satırları sırayla
/// yukarı kayarak belirir.
Future<void> showWeatherDetailSheet(
  BuildContext context,
  WeatherReport report,
) => showAppSheet<void>(
  context: context,
  title: WeatherCopy.title,
  subtitle: '${WeatherCopy.lastUpdated} ${Fmt.time(report.fetchedAt)}',
  builder: (_) => WeatherDetail(report: report),
);

class WeatherDetail extends StatelessWidget {
  const WeatherDetail({super.key, required this.report});

  final WeatherReport report;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final now = report.now;
    final hours = report.nextHours(12);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: weatherSemantics(report),
          excludeSemantics: true,
          child: WeatherNowRow(report: report, large: true),
        ),
        const SizedBox(height: 10),
        Text(
          '${WeatherCopy.feelsLike} ${temp(now.apparent)}, '
          '${WeatherCopy.windInline} ${Fmt.integer(now.windSpeed.round())} km/s',
          style: t.bodySmall.copyWith(
            color: c.dim,
            fontFeatures: AknNumerals.tabular,
          ),
        ),
        const SizedBox(height: 16),
        DrivingStatusStrip(alert: report.drivingAlert()),
        if (hours.isNotEmpty) ...[
          const SectionHeader(
            title: WeatherCopy.hourly,
            padding: EdgeInsets.fromLTRB(0, 20, 0, 8),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // Hücreler yükselerek girer; kenarda kırpılmasınlar.
            clipBehavior: Clip.none,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < hours.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  StaggerItem(
                    index: i,
                    child: WeatherHourCell(
                      hour: hours[i],
                      label: i == 0 ? WeatherCopy.now : null,
                      highlight: i == 0,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (report.days.isNotEmpty) ...[
          const SectionHeader(
            title: WeatherCopy.threeDays,
            padding: EdgeInsets.fromLTRB(0, 20, 0, 4),
          ),
          for (final (i, d) in report.days.indexed) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: c.lineSoft),
            StaggerItem(
              index: 3 + i,
              child: _DayRow(day: d),
            ),
          ],
        ],
        const SizedBox(height: 12),
        Text(WeatherCopy.attribution, style: t.caption.copyWith(color: c.dim)),
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day});

  final WeatherDay day;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final cond = WeatherCondition.of(day.code);
    final diff = TrTime.dayDiff(TrTime.now(), day.day);
    final name = diff == 0
        ? WeatherCopy.today
        : diff == 1
        ? WeatherCopy.tomorrow
        : Fmt.weekday(day.day);
    final rain = day.precipitationProbability >= 20
        ? '%${day.precipitationProbability}'
        : null;
    return Semantics(
      label:
          '$name, ${cond.label}, en yüksek ${day.max.round()}, en düşük ${day.min.round()} derece'
          '${rain == null ? '' : ', yağış olasılığı $rain'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(name, style: t.bodyStrong.copyWith(color: c.ink)),
            ),
            WeatherIconTile(condition: cond, size: 36),
            const SizedBox(width: 10),
            Expanded(
              flex: 4,
              child: Text(
                cond.label,
                style: t.bodySmall.copyWith(color: c.dim),
              ),
            ),
            if (rain != null) ...[
              Text(
                rain,
                style: t.captionStrong.copyWith(
                  color: c.dim,
                  fontFeatures: AknNumerals.tabular,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Text(
              '${temp(day.max)} / ${temp(day.min)}',
              style: t.amount.copyWith(color: c.ink),
            ),
          ],
        ),
      ),
    );
  }
}

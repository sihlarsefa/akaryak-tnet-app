import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env/app_config_controller.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../application/weather_providers.dart';
import '../copy.dart';
import '../data/weather_models.dart';
import '../data/weather_repository.dart';
import 'weather_detail_sheet.dart';
import 'weather_widgets.dart';

/// Hava durumu kartı (spec A.6): teslimat noktasında ya da bulunulan yerde şimdiki durum, sonraki
/// saatler ve sürüş durumu (`GET weather?lat&lng`, "Open-Meteo" atfı). Dokununca saatlik ve 3 günlük
/// tahmin açılır. Sunucuda hava durumu kapalıysa hiçbir şey çizmez. Aynı noktanın
/// `DrivingAlertBanner`'ı ekrandaysa sürüş durumu bantta kalır (karta ikinci kez yazılmaz).
/// Sınıf adı ve kurucu imzası sabittir.
class WeatherCard extends ConsumerWidget {
  const WeatherCard({super.key, required this.lat, required this.lng});

  final double lat;
  final double lng;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(appConfigProvider.select((c) => c.features.weather));
    if (!on || !lat.isFinite || !lng.isFinite) return const SizedBox.shrink();
    final cell = WeatherCell.of(lat, lng);
    final async = ref.watch(weatherProvider(cell));
    return AnimatedSwitcher(
      duration: AknMotion.of(context, AknMotion.base),
      switchInCurve: AknMotion.standard,
      child: async.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        data: (r) =>
            _Loaded(key: const ValueKey('data'), report: r, cell: cell),
        loading: () => const _Skeleton(key: ValueKey('loading')),
        error: (e, _) {
          if (e is WeatherUnavailable && e.disabled) {
            return const SizedBox.shrink(key: ValueKey('off'));
          }
          return _Unavailable(
            key: const ValueKey('error'),
            onRetry: () => ref.invalidate(weatherProvider(cell)),
          );
        },
      ),
    );
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({super.key, required this.report, required this.cell});

  final WeatherReport report;
  final WeatherCell cell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.akn;
    final t = context.aknText;
    final registry = ref.watch(alertBannerRegistryProvider);
    final hours = report.nextHours(11);
    final picked = [
      for (var i = 2; i < hours.length; i += 2) hours[i],
    ].take(5).toList();
    return AknCard(
      onTap: () => showWeatherDetailSheet(context, report),
      semanticLabel: '${weatherSemantics(report)}. ${WeatherCopy.details}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          WeatherNowRow(
            report: report,
            trailing: Icon(Icons.chevron_right_rounded, color: c.faint),
          ),
          const SizedBox(height: 8),
          Text(weatherSummaryLine(report), style: t.bodySmall),
          if (picked.isNotEmpty) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < picked.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    WeatherHourCell(hour: picked[i]),
                  ],
                ],
              ),
            ),
          ],
          ListenableBuilder(
            listenable: registry,
            builder: (context, _) {
              if (registry.has(cell)) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: DrivingStatusStrip(alert: report.drivingAlert()),
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: report.isStale
                    ? Text(
                        '${WeatherCopy.lastUpdated} ${Fmt.time(report.fetchedAt)}',
                        style: t.caption.copyWith(color: c.dim),
                      )
                    : const SizedBox.shrink(),
              ),
              Text(
                WeatherCopy.attributionShort,
                style: t.caption.copyWith(color: c.dim),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton({super.key});

  @override
  Widget build(BuildContext context) => const Shimmer(
    semanticLabel: WeatherCopy.loading,
    child: SkeletonCard(lines: 3, margin: EdgeInsets.zero),
  );
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => AknCard(
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
    child: AknListTile(
      padding: EdgeInsets.zero,
      leadingIcon: Icons.cloud_off_rounded,
      title: WeatherCopy.unavailable,
      subtitle: WeatherCopy.unavailableHint,
      trailing: AknIconButton(
        icon: Icons.refresh_rounded,
        semanticLabel: WeatherCopy.retry,
        onPressed: onRetry,
      ),
    ),
  );
}

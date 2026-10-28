import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env/app_config_controller.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../application/weather_providers.dart';
import '../copy.dart';
import '../data/weather_codes.dart';
import '../data/weather_models.dart';
import '../data/weather_repository.dart';
import 'weather_detail_sheet.dart';
import 'weather_widgets.dart';

/// Hava durumu kartı (spec A.6; tasarım v3): beyaz kart (r20, kart gölgesi); güneşli havada sağ üstte
/// yumuşak sıcak bir ışık. Teslimat noktasında ya da bulunulan yerde şimdiki durum (sıcak / nötr karo,
/// sayarak gelen sıcaklık), sonraki saatler (hap hücreler) ve sürüş durumu (`GET weather?lat&lng`,
/// "Open-Meteo" atfı). Dokununca saatlik ve 3 günlük tahmin açılır. Sunucuda hava durumu kapalıysa hiçbir
/// şey çizmez. Aynı noktanın `DrivingAlertBanner`'ı ekrandaysa sürüş durumu bantta kalır (karta ikinci
/// kez yazılmaz). Yükleme → veri geçişi solarak ve hafifçe büyüyerek. Sınıf adı ve kurucu imzası sabittir.
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
      duration: AknMotion.of(context, AknMotion.slow),
      switchInCurve: AknMotion.emphasizedCurve,
      switchOutCurve: AknMotion.exit,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(a),
          child: child,
        ),
      ),
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
    final sunny =
        WeatherCondition.of(report.now.code, isDay: report.now.isDay).tone ==
        AknTone.brand;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        WeatherNowRow(
          report: report,
          trailing: Icon(
            PhosphorIconsRegular.caretRight,
            size: 18,
            color: c.dim,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          weatherSummaryLine(report),
          style: t.bodySmall.copyWith(
            color: c.dim,
            fontFeatures: AknNumerals.tabular,
          ),
        ),
        if (picked.isNotEmpty) ...[
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
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
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: report.isStale
                  ? Text(
                      '${WeatherCopy.lastUpdated} ${Fmt.time(report.fetchedAt)}',
                      style: t.caption.copyWith(
                        color: c.dim,
                        fontFeatures: AknNumerals.tabular,
                      ),
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
    );
    return AknCard(
      radius: 20,
      padding: EdgeInsets.zero,
      onTap: () => showWeatherDetailSheet(context, report),
      semanticLabel: '${weatherSemantics(report)}. ${WeatherCopy.details}',
      child: ClipRRect(
        borderRadius: AknRadius.card,
        child: Stack(
          children: [
            // Güneşli havada sağ üstte sıcak, yumuşak bir ışık (süs).
            if (sunny)
              Positioned(
                top: -70,
                right: -60,
                child: IgnorePointer(
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [c.plateTint, c.plateTint.withValues(alpha: 0)],
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: content,
            ),
          ],
        ),
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
    radius: 20,
    padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
    child: AknListTile(
      padding: EdgeInsets.zero,
      leadingIcon: PhosphorIconsRegular.cloudSlash,
      title: WeatherCopy.unavailable,
      subtitle: WeatherCopy.unavailableHint,
      trailing: AknIconButton(
        icon: PhosphorIconsRegular.arrowClockwise,
        semanticLabel: WeatherCopy.retry,
        onPressed: onRetry,
      ),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/routing/home_placeholder.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../application/driver_lists.dart';
import '../../application/driver_ops.dart';
import '../../copy.dart';
import '../../data/driver_models.dart';

/// Ana sayfanın lacivert başlığı: selamlama, günün özeti ve sıradaki teslimat (saat penceresi,
/// litre, plaka; yoldaysa tek geçişlik rota şeridi), "Yol tarifi" ve sıradaki adım düğmesi.
class NextStopHero extends ConsumerWidget {
  const NextStopHero({
    super.key,
    required this.onOpen,
    required this.onDeliver,
    required this.onNavigate,
  });

  final ValueChanged<DriverShipmentRow> onOpen;
  final ValueChanged<DriverShipmentRow> onDeliver;
  final ValueChanged<DriverShipmentRow> onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(sessionControllerProvider).access;
    final todayAsync = ref.watch(driverListProvider(DriverTab.today));
    final today = todayAsync.valueOrNull;
    final now = TrTime.now();
    final next = today == null ? null : pickNextStop(today.items, now);
    final ops = next == null ? null : ref.watchDriverOps()[next.id];
    final firstName = (access?.displayName ?? '').split(' ').first;
    final open = today?.open.length ?? 0;
    final done = today?.closed.length ?? 0;

    return AknHeroPanel(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Builder(
        builder: (context) {
          final t = context.aknText;
          final c = context.akn;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${HomePlaceholder.greeting()}${firstName.isEmpty ? '' : ', $firstName'}',
                style: t.title,
              ),
              const SizedBox(height: 2),
              Text(
                [
                  '${Fmt.longDate(now)} ${Fmt.weekday(now)}',
                  if (today != null) DriverCopy.todaySummary(open, done),
                ].join(' · '),
                style: t.body.copyWith(color: c.dim),
              ),
              const SizedBox(height: 16),
              if (next == null)
                _Nothing(loading: today == null && !todayAsync.hasError)
              else
                _NextStop(
                  row: next,
                  now: now,
                  startQueued: ops?.startWaiting ?? false,
                  onOpen: () => onOpen(next),
                  onDeliver: () => onDeliver(next),
                  onNavigate: () => onNavigate(next),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Nothing extends StatelessWidget {
  const _Nothing({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    if (loading) {
      return const SizedBox(
        height: 72,
        child: Center(child: ChevronSpinner(size: 24)),
      );
    }
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AknRadius.card,
        border: Border.all(color: c.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline_rounded, color: c.ink),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DriverCopy.nothingToday, style: t.bodyStrong),
                const SizedBox(height: 2),
                Text(DriverCopy.nothingTodayHint, style: t.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NextStop extends StatelessWidget {
  const _NextStop({
    required this.row,
    required this.now,
    required this.startQueued,
    required this.onOpen,
    required this.onDeliver,
    required this.onNavigate,
  });

  final DriverShipmentRow row;
  final DateTime now;
  final bool startQueued;
  final VoidCallback onOpen;
  final VoidCallback onDeliver;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final inTransit = row.isInTransit || startQueued;
    final overdue = row.isOverdue(now);
    final at = row.scheduledAt;
    final window = row.windowLabel;
    final style = row.status.statusStyle.withLabel(row.statusLabelFromServer);
    final summary = [
      inTransit ? DriverCopy.enRoute : DriverCopy.nextStop,
      ?row.customerTitle,
      ?row.deliveryPointName,
      ?row.placeLine,
      '${Fmt.dayLabel(at, now: now)} ${Fmt.time(at)}',
      if (window != null) '${DriverCopy.window} $window',
      Fmt.liters(row.plannedLiters),
      ?row.productName,
      if (overdue) DriverCopy.overdue,
    ].join(', ');

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AknRadius.card,
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            label: summary,
            onTap: onOpen,
            excludeSemantics: true,
            child: InkWell(
              onTap: onOpen,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AknRadius.md),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          inTransit
                              ? Icons.local_shipping_rounded
                              : Icons.navigation_rounded,
                          size: 18,
                          color: c.brand,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            inTransit
                                ? DriverCopy.enRoute
                                : DriverCopy.nextStop,
                            style: t.label.copyWith(color: c.brandInk),
                          ),
                        ),
                        StatusChip.style(style, size: StatusChipSize.small),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      row.customerTitle ?? row.code,
                      style: t.headline,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [?row.deliveryPointName, ?row.placeLine].join(' · '),
                      style: t.body.copyWith(color: c.dim),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Pill(
                          icon: Icons.event_rounded,
                          text: '${Fmt.dayLabel(at, now: now)} ${Fmt.time(at)}',
                          tone: overdue ? AknTone.danger : null,
                        ),
                        if (overdue)
                          const _Pill(
                            icon: Icons.history_toggle_off_rounded,
                            text: DriverCopy.overdue,
                            tone: AknTone.danger,
                          ),
                        if (window != null)
                          _Pill(icon: Icons.schedule_rounded, text: window),
                        _Pill(
                          icon: Icons.local_gas_station_rounded,
                          text: [
                            Fmt.liters(row.plannedLiters),
                            ?row.productName,
                          ].join(' · '),
                        ),
                        if (row.vehiclePlate != null)
                          PlateBadge(plate: row.vehiclePlate!, fontSize: 12),
                      ],
                    ),
                    if (inTransit) ...[
                      const SizedBox(height: 12),
                      const _RouteStrip(),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: AknButton.secondary(
                    label: DriverCopy.actionNavigate,
                    icon: Icons.directions_rounded,
                    expand: true,
                    onPressed: onNavigate,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: inTransit
                      ? AknButton(
                          label: DriverCopy.actionDeliver,
                          icon: Icons.task_alt_rounded,
                          expand: true,
                          onPressed: onDeliver,
                        )
                      : AknButton(
                          label: DriverCopy.actionStart,
                          icon: Icons.play_arrow_rounded,
                          expand: true,
                          onPressed: onOpen,
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text, this.tone});

  final IconData icon;
  final String text;
  final AknTone? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final tc = tone == null ? null : c.tone(tone!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tc?.bg ?? c.surfaceAlt,
        borderRadius: AknRadius.pillAll,
        border: Border.all(color: tc?.line ?? c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: tc?.fg ?? c.ink),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: context.aknText.captionStrong.copyWith(
                color: tc?.fg ?? c.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Yolda: rota şeridi bir kez akar (canlı konum ya da varış tahmini değildir; spec C.6). Lacivert
/// zeminde hedef iğnesi açık renkte çizilir.
class _RouteStrip extends StatelessWidget {
  const _RouteStrip();

  @override
  Widget build(BuildContext context) {
    final reduced = context.reduceMotion;
    final c = context.akn;
    return Semantics(
      label: DriverCopy.enRouteCaption,
      excludeSemantics: true,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: reduced ? 0.55 : 0.12, end: 0.55),
        duration: reduced ? Duration.zero : const Duration(milliseconds: 1400),
        curve: AknMotion.emphasizedCurve,
        builder: (context, p, _) => LayoutBuilder(
          builder: (context, box) {
            const h = 36.0;
            const truck = h * 0.62;
            const inset = h * 0.25;
            final x = inset + (box.maxWidth - inset * 2) * p;
            return SizedBox(
              height: h,
              width: box.maxWidth,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: TruckRoutePainter(
                        progress: p,
                        color: c.brand,
                        track: c.lineStrong,
                        inset: inset,
                        pin: c.ink,
                      ),
                    ),
                  ),
                  Positioned(
                    left: x - truck / 2,
                    top: h / 2 - truck * 0.86,
                    child: Icon(
                      Icons.local_shipping_rounded,
                      size: truck,
                      color: c.brand,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/models.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../copy.dart';
import '../../data/form_models.dart';
import '../../data/home_models.dart';
import '../../data/order_models.dart';
import 'common.dart';
import 'contact_actions.dart';

/// Takip adımı simgesi (sunucunun FontAwesome `icon` alanı kullanılmaz; spec A.4).
IconData trackingStepIcon(String key) => switch (key) {
  'received' => Icons.receipt_long_rounded,
  'quote' => Icons.request_quote_rounded,
  'approval' => Icons.task_alt_rounded,
  'dispatch' => Icons.local_shipping_rounded,
  'delivered' => Icons.flag_rounded,
  _ => Icons.circle_outlined,
};

TimelineState _state(TrackingState s) => switch (s) {
  TrackingState.done => TimelineState.done,
  TrackingState.current => TimelineState.current,
  TrackingState.failed => TimelineState.failed,
  TrackingState.pending => TimelineState.upcoming,
};

String? _at(DateTime? at, {bool dateOnly = false}) {
  if (at == null) return null;
  if (dateOnly) return Fmt.date(at);
  return '${Fmt.dayLabel(at)} ${Fmt.time(at)}';
}

/// Büyük yazıda (yaklaşık %130 ve üstü) çizelgenin sağa yaslı saat metni dar kartlara sığmaz;
/// saat alt satıra (alt başlığın başına) alınır. Ekran okuyucu etiketi aynı bilgiyi taşır.
List<TimelineStep> fitTimelineSteps(
  BuildContext context,
  List<TimelineStep> steps,
) {
  if (!isLargeText(context)) return steps;
  return [
    for (final s in steps)
      if (s.time == null)
        s
      else
        TimelineStep(
          title: s.title,
          subtitle: s.subtitle == null ? s.time : '${s.time} · ${s.subtitle}',
          state: s.state,
          icon: s.icon,
          content: s.content,
        ),
  ];
}

/// Sipariş takibi: adım çizelgesi, yoldaki araç, sevkiyat kartları, harita ve bayi iletişimi.
class TrackingCard extends ConsumerWidget {
  const TrackingCard({
    super.key,
    required this.order,
    required this.tracking,
    this.point,
    this.station,
  });

  final OrderDetail order;
  final OrderTracking tracking;

  /// Teslimat noktası (pencere ve konum; sipariş formundan).
  final DeliveryPointOption? point;

  /// Bayi iletişimi (varsayılan bayi bu siparişin bayisiyse).
  final StationContact? station;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.aknText;
    final c = context.akn;
    final steps = tracking.steps;
    final active = tracking.activeShipment;
    final inTransit = active?.status == ShipmentStatus.inTransit;
    final reduce =
        MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    final shipments = tracking.shipments
        .where((s) => s.status != ShipmentStatus.cancelled)
        .toList();
    final cancelled = tracking.shipments.length - shipments.length;

    return SectionCard(
      title: OrdersCopy.tracking,
      icon: Icons.route_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (steps.isNotEmpty)
            StepTimeline(
              steps: fitTimelineSteps(context, [
                for (final s in steps)
                  TimelineStep(
                    title: s.label,
                    subtitle: s.detail,
                    time: _at(s.at, dateOnly: s.atIsDateOnly),
                    state: _state(s.state),
                    icon: s.state == TrackingState.done
                        ? null
                        : trackingStepIcon(s.key),
                  ),
              ]),
            ),
          if (active != null) ...[
            const SizedBox(height: 12),
            _ActiveShipment(
              shipment: active,
              point: point,
              moving: inTransit && !reduce,
            ),
          ],
          if (shipments.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              shipments.length == 1
                  ? 'Sevkiyat'
                  : 'Sevkiyatlar (${shipments.length})',
              style: t.label.copyWith(color: c.dim),
            ),
            const SizedBox(height: 8),
            for (final s in shipments) ...[
              ShipmentMiniCard(shipment: s),
              const SizedBox(height: 8),
            ],
            if (cancelled > 0)
              Text(
                '$cancelled sevkiyat planı iptal edildi.',
                style: t.caption.copyWith(color: c.dim),
              ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (point != null &&
                  (point!.hasLocation || point!.fullAddress.isNotEmpty))
                AknButton.secondary(
                  label: OrdersCopy.openMap,
                  icon: Icons.map_rounded,
                  size: AknButtonSize.small,
                  semanticLabel: '${point!.name} noktasını haritada aç',
                  onPressed: () => openExternal(
                    context,
                    ref,
                    ContactLinks.map(
                      lat: point!.latitude,
                      lng: point!.longitude,
                      address: point!.fullAddress,
                    ),
                    failMessage: 'Harita açılamadı.',
                  ),
                ),
            ],
          ),
          if (station != null) ...[
            const SizedBox(height: 4),
            StationContactButtons(
              station: station,
              dense: true,
              message:
                  '${order.orderNumber} numaralı siparişim hakkında yazıyorum.',
            ),
          ],
        ],
      ),
    );
  }
}

class _ActiveShipment extends StatelessWidget {
  const _ActiveShipment({
    required this.shipment,
    required this.point,
    required this.moving,
  });

  final TrackingShipment shipment;
  final DeliveryPointOption? point;
  final bool moving;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final s = shipment;
    final inTransit = s.status == ShipmentStatus.inTransit;
    final window = point?.windowLabel;
    final estimate = s.scheduledAt == null
        ? null
        : '${OrdersCopy.estimatedDelivery}: ${Fmt.date(s.scheduledAt)}${window == null ? '' : ' $window'}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: AknRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusChip.style(
                s.status.statusStyle,
                size: StatusChipSize.small,
              ),
              if (s.vehiclePlate.trim().isNotEmpty)
                Semantics(
                  label: 'Plaka ${Fmt.plate(s.vehiclePlate)}',
                  excludeSemantics: true,
                  child: PlateBadge(plate: s.vehiclePlate, fontSize: 13),
                ),
              if (s.driverName.trim().isNotEmpty)
                Text(s.driverName, style: t.bodySmall.copyWith(color: c.text)),
            ],
          ),
          if (inTransit) ...[
            const SizedBox(height: 8),
            TruckRoute(
              moving: moving,
              height: 40,
              originLabel: 'Bayi',
              destinationLabel: point?.name ?? 'Teslimat noktası',
              semanticLabel: 'Araç yolda. ${OrdersCopy.inTransitCaption}.',
            ),
            const SizedBox(height: 4),
            Text(
              [
                OrdersCopy.inTransitCaption,
                if (s.dispatchedAt != null)
                  '${Fmt.time(s.dispatchedAt)}\'de çıktı',
              ].join(' · '),
              style: t.caption.copyWith(color: c.dim),
            ),
          ],
          if (estimate != null &&
              (s.status == ShipmentStatus.planned || inTransit)) ...[
            const SizedBox(height: 8),
            Text(estimate, style: t.bodyStrong),
          ],
        ],
      ),
    );
  }
}

/// Sevkiyat kartı: kod, plaka, litre (teslim / plan), irsaliye no ve küçük zaman çizelgesi.
/// Dokununca teslimat ayrıntısı (`/shipments/{id}`, teslim kanıtı ve kabul / itiraz) açılır.
class ShipmentMiniCard extends StatelessWidget {
  const ShipmentMiniCard({super.key, required this.shipment});

  final TrackingShipment shipment;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final s = shipment;
    final delivered = s.deliveredLiters;
    final fill = delivered == null || s.plannedLiters <= 0
        ? 0.0
        : (delivered / s.plannedLiters).clamp(0.0, 1.0);
    final steps = <TimelineStep>[
      TimelineStep(
        title: 'Planlandı',
        time: s.scheduledAt == null ? null : Fmt.date(s.scheduledAt),
        state: TimelineState.done,
      ),
      TimelineStep(
        title: 'Yola çıktı',
        time: s.dispatchedAt == null ? null : _at(s.dispatchedAt),
        state: s.dispatchedAt != null || s.isDispatched
            ? TimelineState.done
            : (s.status == ShipmentStatus.planned
                  ? TimelineState.current
                  : TimelineState.upcoming),
      ),
      TimelineStep(
        title: 'Teslim edildi',
        subtitle: delivered == null
            ? null
            : '${Fmt.liters(delivered)}${s.deliveryDocumentNo == null ? '' : ' · İrsaliye no ${s.deliveryDocumentNo}'}',
        time: _at(s.deliveredAt),
        state: s.deliveredAt != null
            ? TimelineState.done
            : (s.status == ShipmentStatus.inTransit
                  ? TimelineState.current
                  : TimelineState.upcoming),
      ),
      if (s.status == ShipmentStatus.disputed)
        TimelineStep(
          title: 'İtiraz edildi',
          subtitle: s.disputeNote,
          time: _at(s.disputedAt),
          state: TimelineState.warning,
        )
      else
        TimelineStep(
          title: 'Teslim alındı',
          time: _at(s.acceptedAt),
          state: s.status == ShipmentStatus.accepted
              ? TimelineState.done
              : (s.status == ShipmentStatus.reported
                    ? TimelineState.current
                    : TimelineState.upcoming),
        ),
    ];
    final label = [
      'Sevkiyat ${s.displayCode}',
      s.status.label,
      'Plan ${Fmt.liters(s.plannedLiters)}',
      if (delivered != null) 'Teslim ${Fmt.liters(delivered)}',
    ].join(', ');
    return AknCard(
      padding: const EdgeInsets.all(12),
      shadow: false,
      semanticLabel: '$label. Ayrıntı için dokunun.',
      onTap: () => context.push(AppRoutes.shipment(s.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              FuelDrop(fill: fill, size: 30, semanticLabel: null),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.displayCode, style: t.bodyStrong),
                    Text(
                      delivered == null
                          ? 'Plan ${Fmt.liters(s.plannedLiters)}'
                          : '${Fmt.liters(delivered)} / ${Fmt.liters(s.plannedLiters)}',
                      style: t.bodySmall.copyWith(color: c.dim),
                    ),
                  ],
                ),
              ),
              StatusChip.style(
                s.status.statusStyle,
                size: StatusChipSize.small,
              ),
            ],
          ),
          const SizedBox(height: 8),
          StepTimeline(steps: fitTimelineSteps(context, steps), dense: true),
          if (s.status == ShipmentStatus.reported) ...[
            const SizedBox(height: 8),
            AknButton(
              label: OrdersCopy.confirmDelivery,
              icon: Icons.fact_check_rounded,
              size: AknButtonSize.small,
              expand: true,
              onPressed: () => context.push(AppRoutes.shipment(s.id)),
            ),
          ],
        ],
      ),
    );
  }
}

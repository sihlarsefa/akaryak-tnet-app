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
import 'contact_actions.dart';
import 'order_parts.dart';

TimelineState _state(TrackingState s) => switch (s) {
  TrackingState.done => TimelineState.done,
  TrackingState.current => TimelineState.current,
  TrackingState.failed => TimelineState.failed,
  TrackingState.pending => TimelineState.upcoming,
};

String? _at(DateTime? at, {bool dateOnly = false}) {
  if (at == null) return null;
  if (dateOnly) return dayMonthLong(at);
  return relativeMoment(at);
}

/// "Sipariş akışı" (§6.14): sunucunun takip adımları kronolojik dikey zaman çizelgesinde.
class OrderFlowTimeline extends StatelessWidget {
  const OrderFlowTimeline({
    super.key,
    required this.steps,
    this.yourMove = false,
  });

  final List<TrackingStep> steps;

  /// Sıradaki adım müşterinin hamlesi (turuncu halka).
  final bool yourMove;

  @override
  Widget build(BuildContext context) => StepTimeline(
    yourMove: yourMove,
    steps: [
      for (final s in steps)
        TimelineStep(
          title: s.label,
          subtitle: s.detail,
          time: _at(s.at, dateOnly: s.atIsDateOnly),
          state: _state(s.state),
        ),
    ],
  );
}

/// Etkin sevkiyat bölümü (§7.4 "Yolda", §7.10): yoldaysa büyük rota çizgisi (» araç), çıkış ve
/// varış etiketleri, sürücü ve plaka, "Haritada aç"; planlıysa tarih; teslim bildirildiyse kabul
/// çağrısı (asıl düğme alttaki çubukta).
class ActiveShipmentSection extends ConsumerWidget {
  const ActiveShipmentSection({
    super.key,
    required this.order,
    required this.shipment,
    this.point,
    this.station,
    this.canAccept = false,
  });

  final OrderDetail order;
  final TrackingShipment shipment;
  final DeliveryPointOption? point;
  final StationContact? station;

  /// Müşteri teslimatı kabul edebilir (alt çubukta "Teslimatı onayla").
  final bool canAccept;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.aknText;
    final c = context.akn;
    final s = shipment;
    final inTransit = s.status == ShipmentStatus.inTransit;
    final reported = s.status == ShipmentStatus.reported;
    final pointName = point?.name ?? order.deliveryPointName;
    final window = point?.windowLabel;
    final title = switch (s.status) {
      ShipmentStatus.inTransit => 'Yolda',
      ShipmentStatus.reported => 'Teslim edildi',
      ShipmentStatus.disputed => 'İtirazlı teslimat',
      _ => 'Sevkiyat planlandı',
    };
    final eta = s.scheduledAt == null
        ? null
        : '${relativeDay(s.scheduledAt)}${window == null ? '' : ', $window'}';
    final origin = [
      shortCompany(order.stationTitle).isEmpty
          ? 'Bayi'
          : shortCompany(order.stationTitle),
      if (s.dispatchedAt != null) '${Fmt.time(s.dispatchedAt)} çıktı',
    ].join(', ');

    final children = <Widget>[];
    if (inTransit) {
      children.addAll([
        TruckRoute(
          moving: true,
          originLabel: origin,
          destinationLabel: pointName.isEmpty ? 'Teslimat noktası' : pointName,
          semanticLabel:
              'Yolda. $origin, ${pointName.isEmpty ? 'teslimat noktası' : pointName}'
              '${eta == null ? '' : ', tahmini teslim $eta'}.',
        ),
        const SizedBox(height: 10),
        if (eta != null)
          FactRow(label: OrdersCopy.estimatedDelivery, value: eta),
        Text(
          '${OrdersCopy.inTransitCaption}.',
          style: t.bodySmall.copyWith(color: c.dim),
        ),
      ]);
    } else if (reported) {
      final liters = s.deliveredLiters;
      children.add(
        FactLine(
          icon: Icons.local_gas_station_outlined,
          text: [
            if (liters != null) '${Fmt.liters(liters)} teslim edildi',
            if (s.deliveredAt != null) relativeMoment(s.deliveredAt),
            if (s.deliveryDocumentNo != null)
              'irsaliye ${s.deliveryDocumentNo}',
          ].join(', '),
        ),
      );
      children.add(const SizedBox(height: 8));
      children.add(
        Text(
          canAccept
              ? 'Litreyi ve irsaliyeyi kontrol edip teslimatı onaylayın; bir sorun varsa itiraz edin.'
              : 'Teslimat şirket yöneticinizin onayını bekliyor.',
          style: t.bodySmall.copyWith(color: c.dim),
        ),
      );
    } else if (s.status == ShipmentStatus.disputed) {
      children.add(
        FactLine(
          icon: Icons.error_outline_rounded,
          tone: AknTone.danger,
          text: s.disputeNote == null
              ? 'İtirazınız bayiye iletildi.'
              : 'İtirazınız: ${s.disputeNote}',
        ),
      );
    } else if (eta != null) {
      children.add(
        FactLine(
          icon: Icons.event_outlined,
          text: '${pointName.isEmpty ? 'Teslimat' : pointName}, $eta teslim',
        ),
      );
    }

    final driver = s.driverName.trim();
    final plate = s.vehiclePlate.trim();
    if (driver.isNotEmpty || plate.isNotEmpty) {
      children.addAll([
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.person_outline_rounded, size: 20, color: c.dim),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                driver.isEmpty ? 'Sürücü' : driver,
                style: t.bodyStrong.copyWith(color: c.ink),
              ),
            ),
            if (plate.isNotEmpty)
              Semantics(
                label: 'Plaka ${Fmt.plate(plate)}',
                excludeSemantics: true,
                child: PlateBadge(plate: plate),
              ),
          ],
        ),
      ]);
    }

    final hasMap =
        point != null && (point!.hasLocation || point!.fullAddress.isNotEmpty);
    if (hasMap || station != null) {
      children.add(const SizedBox(height: 12));
      children.add(
        StationContactButtons(
          station: station,
          dense: true,
          message:
              '${order.orderNumber} numaralı siparişim hakkında yazıyorum.',
          leading: [
            if (hasMap)
              AknButton.secondary(
                label: OrdersCopy.openMap,
                icon: Icons.map_outlined,
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
      );
    }

    return OrderSection(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// Sevkiyat satırları (§6.8): "10.000 L planlandı" / "9.980 L teslim edildi", kod, plaka ve
/// sürücü; izleyiciye göre lamba ("Teslimatı onaylayın" sıra sizde). Dokununca teslimat ayrıntısı
/// (`/shipments/{id}`: teslim kanıtı, kabul / itiraz) açılır.
class ShipmentRows extends StatelessWidget {
  const ShipmentRows({
    super.key,
    required this.shipments,
    required this.viewer,
  });

  /// İptal edilenler hariç.
  final List<TrackingShipment> shipments;
  final StatusViewer viewer;

  @override
  Widget build(BuildContext context) => AknLedger(
    children: [
      for (final s in shipments)
        () {
          final lamp = AknStatus.shipmentLamp(s.status, viewer);
          final delivered = s.deliveredLiters;
          final title = delivered == null
              ? Fmt.liters(s.plannedLiters)
              : '${Fmt.liters(delivered)} teslim edildi';
          final sub = [
            s.displayCode,
            if (s.vehiclePlate.trim().isNotEmpty) Fmt.plate(s.vehiclePlate),
            if (s.driverName.trim().isNotEmpty) s.driverName.trim(),
          ].join(', ');
          final when = s.deliveredAt ?? s.dispatchedAt ?? s.scheduledAt;
          return AknListTile(
            title: title,
            subtitle: sub,
            meta: when == null ? null : relativeDay(when),
            status: AknStatusLine(lamp: AknLamp.status(lamp)),
            semanticLabel:
                '$title, sevkiyat ${s.displayCode}, ${lamp.label}. Ayrıntı için dokunun.',
            onTap: () => context.push(AppRoutes.shipment(s.id)),
          );
        }(),
    ],
  );
}

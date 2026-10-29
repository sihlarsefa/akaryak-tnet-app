import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/models.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/turkish_text.dart';
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

/// Etkin sevkiyat kartı (§7.10; v4 §5 ekran 05): sayfanın StageNow satırı durumu ve tahmini
/// teslimi zaten söyler ("Yolda · Tahmini teslim bugün, 08:00–18:00"); kart onları tekrar etmez.
/// Yoldaysa büyük rota çizgisi (» araç; çıkış ve varış etiketleri, "canlı konum değildir"),
/// teslim bildirildiyse ne yapılacağı ve irsaliye; sürücü ve plaka; "Haritada aç" ve bayi
/// iletişimi. Söyleyecek bir şey yoksa çizilmez.
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
        Text(
          '${OrdersCopy.inTransitCaption}.',
          style: t.bodySmall.copyWith(color: c.dim),
        ),
      ]);
    } else if (reported) {
      children.add(
        Text(
          canAccept
              ? 'Litreyi ve irsaliyeyi kontrol edip teslimatı onaylayın; bir sorun varsa itiraz edin.'
              : 'Teslimat şirket yöneticinizin onayını bekliyor.',
          style: t.bodySmall.copyWith(color: c.dim),
        ),
      );
      if (s.deliveryDocumentNo != null) {
        children.addAll([
          const SizedBox(height: 6),
          FactRow(label: 'İrsaliye', value: s.deliveryDocumentNo!),
        ]);
      }
    }

    final driver = s.driverName.trim();
    final plate = s.vehiclePlate.trim();
    if (driver.isNotEmpty || plate.isNotEmpty) {
      children.addAll([
        if (children.isNotEmpty) const SizedBox(height: 14),
        Row(
          children: [
            ExcludeSemantics(
              child: Icon(
                PhosphorIconsRegular.steeringWheel,
                size: 20,
                color: c.dim,
              ),
            ),
            const SizedBox(width: 10),
            // Sürücü solda, plaka sağda; büyük yazıda yan yana sığmazlarsa plaka adın altına iner
            // (sütundan genişse kendi içinde küçülür) — satır taşmaz.
            Expanded(
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Text(
                    driver.isEmpty ? 'Sürücü' : driver,
                    style: t.bodyStrong.copyWith(color: c.ink),
                  ),
                  if (plate.isNotEmpty)
                    Semantics(
                      label: 'Plaka ${Fmt.plate(plate)}',
                      excludeSemantics: true,
                      child: PlateBadge(plate: plate),
                    ),
                ],
              ),
            ),
          ],
        ),
      ]);
    }

    final hasMap =
        point != null && (point!.hasLocation || point!.fullAddress.isNotEmpty);
    final contact =
        station != null &&
        (station!.callNumber != null || station!.whatsappNumber != null);
    if (hasMap || contact) {
      children.addAll([
        if (children.isNotEmpty) const SizedBox(height: 12),
        StationContactButtons(
          station: station,
          dense: true,
          message:
              '${order.orderNumber} numaralı siparişim hakkında yazıyorum.',
          leading: [
            if (hasMap)
              AknButton.secondary(
                label: OrdersCopy.openMap,
                icon: PhosphorIconsRegular.mapTrifold,
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
      ]);
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: AknLedger(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sevkiyat satırları (§6.8; v4 defter satırı): "10.000 L planlandı" / "9.980 L teslim edildi",
/// plaka ve sürücü, sağda gün; sıra müşterideyse yapılacak iş Pas satırda ("Teslimatı
/// onaylayın"), yalnızca itirazlı sevkiyatta durum hapı. Dokununca teslimat ayrıntısı
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
          // "10.000 L planlandı", "10.000 L yolda", "9.980 L teslim edildi"; sıra sizdeyken ya da
          // sorunlu sevkiyatta durum ayrı satırdadır.
          final title = delivered != null
              ? '${Fmt.liters(delivered)} teslim edildi'
              : lamp.yourMove || lamp.problem
              ? Fmt.liters(s.plannedLiters)
              : '${Fmt.liters(s.plannedLiters)} ${TurkishText.lower(lamp.label)}';
          final sub = [
            if (s.vehiclePlate.trim().isNotEmpty) Fmt.plate(s.vehiclePlate),
            if (s.driverName.trim().isNotEmpty) s.driverName.trim(),
          ].join(' · ');
          final when = s.deliveredAt ?? s.dispatchedAt ?? s.scheduledAt;
          return AknListTile(
            padding: a2RowPadding,
            title: title,
            subtitle: sub.isEmpty ? null : sub,
            meta: when == null ? null : relativeDay(when),
            next: lamp.yourMove ? lamp.label : null,
            status: lamp.problem ? AknLamp.status(lamp) : null,
            semanticLabel:
                '$title, sevkiyat ${s.displayCode}, ${lamp.label}. Ayrıntı için dokunun.',
            onTap: () {
              AknHaptics.selection();
              context.push(AppRoutes.shipment(s.id));
            },
          );
        }(),
    ],
  );
}

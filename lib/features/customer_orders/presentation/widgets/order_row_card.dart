import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/models/models.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../application/ordering_config.dart';
import '../../data/order_models.dart';
import 'order_parts.dart';

/// Siparişlerim satırı (tasarım v2 §6.8, pano ekran 4): ledger satırı.
///
/// ```
/// Motorin, 8.000 L                                   338.800,00 ₺
/// Tuzla Şantiye, 22 Ekim                                42,35 ₺/L
/// ● Kararınızı bekliyor                        ⏱ 2 sa 57 dk kaldı
/// [yoldaysa rota çizgisi]
/// ```
///
/// Durum lambası izleyiciye göredir (§10.3); sıra müşterideyse turuncu nokta + Pas yazı ve Pas
/// geri sayım. Eksik ödeme belgesi gibi ek durumlar küçük lambalarla alt satıra iner. Ekran
/// okuyucu satırı tek düğüm olarak okur (sipariş numarası dahil).
class OrderRowCard extends ConsumerWidget {
  const OrderRowCard({super.key, required this.row, this.onTap});

  final CustomerOrderRow row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.aknText;
    final c = context.akn;
    final config = ref.watch(orderingConfigValueProvider);
    final viewer = customerViewer(ref.watch(accessPolicyProvider));
    final lamp = orderLampFor(
      viewer,
      status: row.status,
      serverLabel: row.statusLabel,
      shipment: row.activeShipmentStatus,
      finance: row.financeStatus,
      financeLabel: row.financeLabel,
    );
    final expires = row.expiresAt;
    final showCountdown =
        expires != null &&
        !row.financeStatus.isAwaitingDecision &&
        (row.status == OrderStatus.awaitingApproval ||
            row.status == OrderStatus.awaitingQuote ||
            row.status == OrderStatus.revisionRequested);
    final deadline = expires == null ? null : config.deviceDeadline(expires);
    final inTransit = row.activeShipmentStatus == ShipmentStatus.inTransit;

    final price = row.quotedUnitPrice;
    final total = row.quotedTotal;
    final where = [
      if (row.deliveryPointName != null) row.deliveryPointName!,
      if (row.requestedDeliveryDate != null)
        relativeDay(row.requestedDeliveryDate),
    ].join(', ');

    // Sağdaki not: geri sayım; yoksa teklif bekleyen siparişte bayinin adı.
    Widget? trailing;
    if (showCountdown && deadline != null) {
      trailing = CountdownBadge(deadline: deadline, yourMove: lamp.yourMove);
    } else if (row.status == OrderStatus.awaitingQuote ||
        row.status == OrderStatus.revisionRequested ||
        row.status == OrderStatus.created) {
      final s = shortCompany(row.stationTitle);
      if (s.isNotEmpty) {
        trailing = Text(s, style: t.bodySmall.copyWith(color: c.dim));
      }
    }

    final extras = <Widget>[
      if (row.paymentDocumentMissing)
        const AknLamp(
          label: 'Ödeme belgesi bekleniyor',
          tone: AknTone.warn,
          size: AknLampSize.small,
        ),
    ];

    final semantics = [
      orderTitle(row.productName, row.quantityLiters),
      'Sipariş ${row.orderNumber}',
      lamp.label,
      if (where.isNotEmpty) where,
      if (total != null) 'Teklif ${Fmt.money(total)}',
      if (price != null) Fmt.unitPrice(price),
      if (showCountdown && deadline != null)
        'Kalan süre ${Fmt.countdown(deadline.difference(TrTime.now()))}',
      if (row.paymentDocumentMissing) 'Ödeme belgesi bekleniyor',
    ].join(', ');

    return AknListTile(
      key: ValueKey('order-row-${row.id}'),
      title: orderTitle(row.productName, row.quantityLiters),
      subtitle: where.isEmpty ? null : where,
      amount: total == null ? null : Fmt.money(total),
      amountMeta: price == null ? null : Fmt.unitPrice(price),
      status: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AknStatusLine(lamp: AknLamp.status(lamp), trailing: trailing),
          for (final e in extras) ...[
            const SizedBox(height: 4),
            Align(alignment: AlignmentDirectional.centerStart, child: e),
          ],
        ],
      ),
      footer: inTransit
          ? const TruckRoute(moving: true, semanticLabel: 'Araç yolda')
          : null,
      semanticLabel: semantics,
      onTap: onTap,
    );
  }
}

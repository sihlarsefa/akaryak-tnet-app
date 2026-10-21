import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/models.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../application/ordering_config.dart';
import '../../data/order_models.dart';
import 'common.dart';

/// Siparişlerim satırı: numara + durum, ürün · litre · nokta, bayi · teslim tarihi, teklif,
/// geri sayım ve uyarı çipleri (finans, belge, sevkiyat). Ekran okuyucu tek düğüm okur.
class OrderRowCard extends ConsumerWidget {
  const OrderRowCard({super.key, required this.row, this.onTap});

  final CustomerOrderRow row;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.aknText;
    final c = context.akn;
    final config = ref.watch(orderingConfigValueProvider);
    final status = row.status.statusStyle.withLabel(row.statusLabel);
    final expires = row.expiresAt;
    final showCountdown =
        expires != null &&
        (row.status == OrderStatus.awaitingApproval ||
            row.status == OrderStatus.awaitingQuote ||
            row.status == OrderStatus.revisionRequested);
    final chips = <Widget>[
      if (row.financeStatus.isAwaitingDecision ||
          row.financeStatus == OrderFinanceStatus.rejected)
        StatusChip.style(
          row.financeStatus.statusStyle.withLabel(row.financeLabel),
          size: StatusChipSize.small,
        ),
      if (row.paymentDocumentMissing)
        const StatusChip(
          label: 'Belge bekleniyor',
          tone: AknTone.warn,
          icon: Icons.photo_camera_outlined,
          size: StatusChipSize.small,
        ),
      if (row.activeShipmentStatus != null)
        StatusChip.style(
          row.activeShipmentStatus!.statusStyle.withLabel(
            row.activeShipmentStatusLabel,
          ),
          size: StatusChipSize.small,
        ),
    ];
    final price = row.quotedUnitPrice;
    final total = row.quotedTotal;
    final semantics = [
      'Sipariş ${row.orderNumber}',
      status.label,
      [
        row.productName,
        Fmt.liters(row.quantityLiters),
      ].whereType<String>().join(', '),
      if (row.deliveryPointName != null) row.deliveryPointName!,
      if (total != null) 'Teklif ${Fmt.money(total)}',
      if (showCountdown)
        'Kalan süre ${Fmt.countdown(config.deviceDeadline(expires).difference(TrTime.now()))}',
      if (row.paymentDocumentMissing) 'Ödeme belgesi bekleniyor',
    ].join(', ');
    return AknCard(
      onTap: onTap,
      semanticLabel: semantics,
      accent: row.status == OrderStatus.awaitingApproval
          ? AknTone.warn
          : (row.paymentDocumentMissing ? AknTone.warn : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(row.orderNumber, style: t.bodyStrong),
              StatusChip.style(status, size: StatusChipSize.small),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              row.productName,
              Fmt.liters(row.quantityLiters),
              row.deliveryPointName,
            ].whereType<String>().join(' · '),
            style: t.body.copyWith(color: c.ink),
          ),
          const SizedBox(height: 2),
          Text(
            [
              row.stationTitle,
              if (row.requestedDeliveryDate != null)
                'Teslim ${Fmt.date(row.requestedDeliveryDate)}',
            ].whereType<String>().join(' · '),
            style: t.bodySmall.copyWith(color: c.dim),
          ),
          if (price != null || showCountdown) ...[
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                if (price != null)
                  AmountText(
                    '${Fmt.unitPrice(price)}${total == null ? '' : ' · ${Fmt.money(total)}'}',
                  ),
                if (showCountdown)
                  FitBadge(
                    child: CountdownBadge(
                      deadline: config.deviceDeadline(expires),
                    ),
                  ),
              ],
            ),
          ],
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: chips),
          ],
        ],
      ),
    );
  }
}

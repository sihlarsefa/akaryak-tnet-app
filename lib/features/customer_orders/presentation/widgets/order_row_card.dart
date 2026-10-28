import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/models/models.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../application/ordering_config.dart';
import '../../data/order_models.dart';
import 'common.dart';
import 'order_parts.dart';

/// Siparişlerim kartı (tasarım v3 §4, pano ekran 4): kırık beyaz sayfada yüzen beyaz r20 kart.
///
/// ```
/// ╭──────────────────────────────────────────────────────╮
/// │ [▣] Motorin, 8.000 L                     338.800,00 ₺ │
/// │     Tuzla Şantiye, 22 Ekim                  42,35 ₺/L │
/// │     ● Kararınızı bekliyor          ⏱ 2 sa 57 dk kaldı │
/// │ [yoldaysa rota çizgisi]                               │
/// ╰──────────────────────────────────────────────────────╯
/// ```
///
/// Baştaki karo siparişin aşamasını gösterir ([orderStageIcon]) ve lambanın tonunda boyanır;
/// tutarlar tablo rakamlıdır. Durum lambası izleyiciye göredir (§10.3); sıra müşterideyse turuncu
/// nokta + Pas yazı ve Pas geri sayım. Eksik ödeme belgesi gibi ek durumlar küçük lambalarla alt
/// satıra iner. Basınca kart 0,97'ye iner. Ekran okuyucu kartı tek düğüm olarak okur (sipariş
/// numarası dahil).
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

    final tap = onTap;
    final title = orderTitle(row.productName, row.quantityLiters);
    final titleStyle = a2RowTitle(t, c);
    final amount = total == null ? null : Fmt.money(total);
    final meta = price == null ? null : Fmt.unitPrice(price);
    return A2Card(
      pressable: tap != null,
      // Tutar başlığın yanına sığmazsa (uzun ürün adı, büyük tutar) alt satıra iner; başlık tek
      // satıra sığmıyorsa ürün adından kırılır, litre birimiyle aynı satırda kalır ("Motorin," /
      // "20.000 L").
      child: LayoutBuilder(
        builder: (context, box) {
          final width = box.maxWidth - 32 - 56;
          final beside = a2AmountBeside(
            context,
            width: width,
            title: title,
            titleStyle: titleStyle,
            amount: amount,
            meta: meta,
          );
          return _tile(
            context,
            title: a2WrapSafe(context, title, titleStyle, width: width),
            titleStyle: titleStyle,
            beside: beside,
            amount: amount,
            meta: meta,
            where: where,
            lamp: lamp,
            trailing: trailing,
            extras: extras,
            inTransit: inTransit,
            semantics: semantics,
            tap: tap,
          );
        },
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required String title,
    required TextStyle titleStyle,
    required bool beside,
    required String? amount,
    required String? meta,
    required String where,
    required StatusLamp lamp,
    required Widget? trailing,
    required List<Widget> extras,
    required bool inTransit,
    required String semantics,
    required VoidCallback? tap,
  }) {
    final c = context.akn;
    return AknListTile(
      key: ValueKey('order-row-${row.id}'),
      leading: A2IconTile(icon: orderStageIcon(lamp), tone: lamp.tone),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      titleStyle: titleStyle,
      title: title,
      subtitle: where.isEmpty ? null : where,
      amount: beside ? amount : null,
      amountMeta: beside ? meta : null,
      status: beside || amount == null
          ? null
          : A2AmountLine(amount: amount, meta: meta),
      // Kartın alt şeridi: içeriden bir çizginin altında durum (lamba + geri sayım) kart
      // genişliğince; yoldaysa rota çizgisi.
      footer: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(height: 1, thickness: 1, color: c.lineSoft),
          const SizedBox(height: 10),
          AknStatusLine(lamp: AknLamp.status(lamp), trailing: trailing),
          for (final e in extras) ...[
            const SizedBox(height: 6),
            Align(alignment: AlignmentDirectional.centerStart, child: e),
          ],
          if (inTransit) ...[
            const SizedBox(height: 12),
            const TruckRoute(moving: true, semanticLabel: 'Araç yolda'),
          ],
        ],
      ),
      semanticLabel: semantics,
      onTap: tap == null
          ? null
          : () {
              AknHaptics.selection();
              tap();
            },
    );
  }
}

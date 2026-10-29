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

/// Siparişler satırı (tasarım v4 §5 ekran 04): defterde (`AknLedger`) bir satır; kutu, karo ve
/// hap yok.
///
/// ```
/// Motorin, 8.000 L                                         338.800,00 ₺
/// Tuzla Şantiye · yarın                                       42,35 ₺/L
/// Çek görselini yükleyin (Pas, sıra sizde)               ⏱ 2 sa 59 dk
/// ```
///
/// * Onay bekleyen: sıra müşterideyse üçüncü satır yapılacak işi söyler ("Teklifi onaylayın",
///   belge eksikse "Çek görselini yükleyin") ve sağında kısa geri sayım (3 saatten uzaksa soluk).
/// * Aktif: üçüncü satır siparişin Akış'ı — beş bölüt ve » ile bir cümle ("Demir Petrol teklif
///   hazırlıyor", "Yolda", "Teslimatı onaylayın").
/// * Geçmiş: olağan sonuç yazılmaz; yalnızca reddedilen ya da süresi dolan siparişte durum hapı.
///
/// Ekran okuyucu satırı tek düğüm okur (sipariş numarası dahil).
class OrderRow extends ConsumerWidget {
  const OrderRow({
    super.key,
    required this.row,
    required this.segment,
    this.onTap,
    this.showStation = false,
  });

  final CustomerOrderRow row;
  final OrderSegment segment;
  final VoidCallback? onTap;

  /// Birden çok bayiden alan müşteride ikinci satır bayiyi de söyler.
  final bool showStation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(orderingConfigValueProvider);
    final policy = ref.watch(accessPolicyProvider);
    final viewer = customerViewer(policy);
    final station = shortCompany(row.stationTitle);
    final lamp = orderLampFor(
      viewer,
      status: row.status,
      serverLabel: row.statusLabel,
      shipment: row.activeShipmentStatus,
      finance: row.financeStatus,
      financeLabel: row.financeLabel,
      actor: station.isEmpty ? null : station,
      answersInfo: customerAnswersInfo(policy),
      missingDocument: viewer.canDecide
          ? missingDocumentPhrase(
              missing: row.paymentDocumentMissing,
              methodCode: row.paymentMethodCode,
            )
          : null,
    );
    final expires = row.expiresAt;
    final countdown =
        expires != null &&
        !row.financeStatus.isAwaitingDecision &&
        (row.status == OrderStatus.awaitingApproval ||
            row.status == OrderStatus.awaitingQuote ||
            row.status == OrderStatus.revisionRequested);
    final deadline = expires == null ? null : config.deviceDeadline(expires);

    // Litre birimiyle aynı satırda kalır ("Kurşunsuz Benzin 95," / "5.000 L").
    final title = keepUnits(orderTitle(row.productName, row.quantityLiters));
    // İkinci satır en çok iki olgu: nokta ve gün (Geçmiş'te gün başlıkta yazar); birden çok
    // bayiden alan müşteride gün yerine bayi.
    final day = row.requestedDeliveryDate == null
        ? null
        : relativeDay(row.requestedDeliveryDate);
    final second = segment == OrderSegment.history
        ? (showStation && station.isNotEmpty ? station : null)
        : day;
    final subtitle = [
      if (row.deliveryPointName != null) row.deliveryPointName!,
      ?second,
    ].join(' · ');
    final total = row.quotedTotal;
    final price = row.quotedUnitPrice;
    final amount = total == null ? null : Fmt.money(total);
    final meta = price == null ? null : Fmt.unitPrice(price);

    // Üçüncü satır, bölüme göre.
    String? next;
    Widget? metaWidget;
    Widget? flow;
    Widget? status;
    switch (segment) {
      case OrderSegment.decision:
        if (lamp.yourMove) next = lamp.label;
        if (countdown && deadline != null) {
          metaWidget = CountdownBadge(
            deadline: deadline,
            yourMove: lamp.yourMove,
            compact: true,
            subject: 'Teklif',
          );
        }
      case OrderSegment.active:
        flow = AknFlowPips(flow: AknFlow.customer(lamp), sentence: lamp.label);
      case OrderSegment.history:
        if (lamp.problem || row.status == OrderStatus.expired) {
          status = AknLamp.status(lamp);
        }
    }

    final semantics = [
      title,
      'Sipariş ${row.orderNumber}',
      lamp.label,
      if (subtitle.isNotEmpty) subtitle,
      if (amount != null) 'Teklif $amount',
      ?meta,
      if (countdown && deadline != null)
        'Kalan süre ${Fmt.countdown(deadline.difference(TrTime.now()))}',
    ].join(', ');

    final tap = onTap;
    return AknListTile(
      key: ValueKey('order-row-${row.id}'),
      title: title,
      subtitle: subtitle.isEmpty ? null : subtitle,
      amount: amount,
      amountMeta: meta,
      next: next,
      metaWidget: metaWidget,
      flow: flow,
      status: status,
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/models.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../application/bayi_grants.dart';
import '../../application/orders_controller.dart';
import '../../copy.dart';
import '../../data/order_models.dart';
import '../widgets/bayi_widgets.dart';
import '../widgets/paged_list_body.dart';
import 'order_filters_sheet.dart';

/// Siparişler (spec A.4, tasarım v2 §7.7): kök başlık, segment çipleri (`bayi/orders/counts`), arama
/// kuyusu, durum / ödeme / finans / cari / tarih süzgeçleri, sonsuz kaydırma; defter satırına
/// dokununca sipariş ayrıntısı.
class BayiOrdersPage extends ConsumerStatefulWidget {
  const BayiOrdersPage({super.key});

  @override
  ConsumerState<BayiOrdersPage> createState() => _BayiOrdersPageState();
}

class _BayiOrdersPageState extends ConsumerState<BayiOrdersPage> {
  // Arama kutusu listeyle kayar; yazılan metin kutu ekrandan çıkınca kaybolmasın.
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(
      text: ref.read(bayiOrdersProvider).filter.q,
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(bayiOrdersProvider);
    final c = ref.read(bayiOrdersProvider.notifier);
    final f = s.filter;
    final counts = s.counts;
    final segments = [
      for (final seg in BayiOrderSegment.values)
        if (counts == null || counts.of(seg) > 0 || f.segment == seg) seg,
    ];
    final advanced = f.advancedCount;
    final total = s.list.totalCount;
    return AppScaffold(
      title: 'Siparişler',
      refreshing: s.list.refreshing,
      actions: [
        FilterButton(
          label: 'Süzgeçler',
          count: advanced,
          onPressed: () => showOrderFiltersSheet(context),
        ),
      ],
      // Segmentler, arama ve süzgeç özeti listeyle birlikte kayar.
      body: PagedListBody<BayiOrderRow>(
        list: s.list,
        header: [
          const SizedBox(height: 4),
          FilterChips<BayiOrderSegment>(
            options: [
              for (final seg in segments)
                FilterOption(
                  value: seg,
                  label: seg.label,
                  count: counts?.of(seg),
                ),
            ],
            selected: {?f.segment},
            onChanged: (v) => c.setSegment(v.isEmpty ? null : v.first),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: SearchField(
              hint: 'Sipariş no, cari, ürün ya da nokta',
              controller: _search,
              onChanged: c.setQuery,
            ),
          ),
          if (advanced > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                children: [
                  Text(
                    _describe(f),
                    style: context.aknText.label.copyWith(
                      color: context.akn.dim,
                      fontWeight: FontWeight.w400,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  AknInlineLink(
                    label: BayiCopy.clearFilters,
                    onTap: () => c.setFilter(f.clearAdvanced()),
                  ),
                ],
              ),
            ),
        ],
        onRefresh: () => c.refresh(silent: true),
        onLoadMore: () => unawaited(c.loadMore()),
        filtered: f.isFiltered,
        onClearFilters: () {
          _search.clear();
          c.clearAll();
        },
        empty: const EmptyState(
          title: BayiCopy.ordersEmptyTitle,
          message: BayiCopy.ordersEmptyMessage,
          illustration: AknIllustration.orders,
        ),
        footer: total <= 0
            ? null
            : ListFooterNote(
                f.isFiltered
                    ? 'Süzgece uyan ${Fmt.integer(total)} sipariş gösteriliyor.'
                    : 'Toplam ${Fmt.integer(total)} sipariş. Tamamlanan ve iptal olanları süzgeçten bulabilirsiniz.',
              ),
        itemBuilder: (context, row, _) => BayiOrderCard(row: row),
      ),
    );
  }

  static String _describe(BayiOrdersFilter f) => [
    if (f.statuses.isNotEmpty) f.statuses.map((s) => s.label).join(', '),
    if (f.paymentStatus != null)
      'ödeme ${TurkishText.lower(f.paymentStatus!.label)}',
    if (f.financeStatus != null) TurkishText.lower(f.financeStatus!.label),
    if (f.customerId != null) f.customerTitle ?? 'Cari #${f.customerId}',
    if (f.createdFrom != null || f.createdTo != null)
      'oluşturulma ${Fmt.date(f.createdFrom)}–${Fmt.date(f.createdTo)}',
    if (f.requestedFrom != null || f.requestedTo != null)
      'teslim ${Fmt.date(f.requestedFrom)}–${Fmt.date(f.requestedTo)}',
    if (f.sort != BayiOrderSort.created) TurkishText.lower(f.sort.label),
  ].join(', ');
}

/// Siparişin satırdaki sevkiyat durumu (lamba için): kısmi teslim ve sevkiyatsız durumda yok.
ShipmentStatus? bayiShipmentStatus(BayiShipmentState s) => switch (s) {
  BayiShipmentState.planned => ShipmentStatus.planned,
  BayiShipmentState.inTransit => ShipmentStatus.inTransit,
  BayiShipmentState.reported => ShipmentStatus.reported,
  BayiShipmentState.disputed => ShipmentStatus.disputed,
  BayiShipmentState.delivered => ShipmentStatus.accepted,
  BayiShipmentState.partial || BayiShipmentState.none => null,
};

/// Sipariş satırı (tasarım v2 §6.8 defter satırı, bayi):
///
/// ```
/// Körfez Nakliyat ve Ticaret                     338.800,00 ₺
/// SIP-20261020-12009, Motorin, 10.000 L, …          42,35 ₺/L
/// ● Müşteri kararında                       ⏱ 2 sa 57 dk kaldı
/// [ödeme notu] [yolda ise rota çizgisi]
/// ```
class BayiOrderCard extends ConsumerWidget {
  const BayiOrderCard({super.key, required this.row});

  final BayiOrderRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = row;
    final viewer = ref.watch(bayiGrantsProvider).viewer;
    final quoted = r.unitPrice != null;
    final expires = r.expiresAt;
    final open = r.status.isOpen;
    final showCountdown =
        open && expires != null && expires.isAfter(DateTime.now().toUtc());
    final financeWait = r.financeStatus.isAwaitingDecision;
    final toPlan = r.status == OrderStatus.approved && r.remainingLiters > 0;
    final shipment = toPlan ? null : bayiShipmentStatus(r.shipmentState);

    // Lamba: finans kararı bekleyen sipariş finansın; diğerleri izleyiciye göre (§10.3).
    final StatusLamp lamp;
    if (financeWait && open) {
      lamp = StatusLamp.fromStyle(
        r.financeStatus.statusStyle.withLabel(r.financeLabel),
      );
    } else {
      lamp = AknStatus.lampFor(
        r.status,
        viewer,
        serverLabel: r.statusLabel,
        shipment: shipment,
      );
    }

    Widget? trailing;
    if (showCountdown) {
      trailing = CountdownBadge(
        deadline: expires,
        yourMove: lamp.yourMove,
        subject: 'Sipariş',
      );
    } else if (toPlan) {
      trailing = _Note('Kalan ${Fmt.liters(r.remainingLiters)}');
    } else if (r.requestedDeliveryDate != null && open) {
      trailing = _Note('${dayMonthLong(r.requestedDeliveryDate!)} teslim');
    }

    final payment = r.paymentStatus == PaymentStatus.none
        ? null
        : [
            ?r.paymentMethodName,
            TurkishText.lower(r.paymentStatusLabel ?? r.paymentStatus.label),
          ].join(', ');
    final inTransit = r.shipmentState == BayiShipmentState.inTransit;

    return AknListTile(
      title: r.customerTitle ?? Fmt.dash,
      subtitle: keepUnits(
        [
          r.orderNumber,
          ?r.productName,
          Fmt.liters(r.quantityLiters),
          ?(r.deliveryPointName ?? r.deliveryCity),
        ].join(', '),
      ),
      amount: r.totalAmount == null ? null : Fmt.money(r.totalAmount),
      amountMeta: quoted ? Fmt.unitPrice(r.unitPrice) : null,
      status: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AknStatusLine(lamp: AknLamp.status(lamp), trailing: trailing),
          if (payment != null) ...[
            const SizedBox(height: 4),
            RowNote(
              icon: Icons.payments_outlined,
              text: payment,
              tone: r.paymentStatus.statusStyle.tone,
            ),
          ],
        ],
      ),
      footer: inTransit
          ? TruckRoute(
              moving: true,
              semanticLabel:
                  'Yolda. ${r.deliveryPointName ?? r.customerTitle ?? ''}',
            )
          : null,
      onTap: () => GoRouter.of(context).push(AppRoutes.bayiOrder(r.id)),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: context.aknText.bodySmall.copyWith(
      color: context.akn.ink,
      fontWeight: FontWeight.w500,
    ),
  );
}

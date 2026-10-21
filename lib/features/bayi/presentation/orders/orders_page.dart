import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/models.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/orders_controller.dart';
import '../../copy.dart';
import '../../data/order_models.dart';
import '../widgets/bayi_widgets.dart';
import '../widgets/paged_list_body.dart';
import 'order_filters_sheet.dart';

/// Siparişler (spec A.4): segment çipleri (`bayi/orders/counts`), arama, durum / ödeme / finans / cari /
/// tarih süzgeçleri, sonsuz kaydırma; satıra dokununca sipariş ayrıntısı.
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
    return AppScaffold(
      title: 'Siparişler',
      subtitle: s.list.loading
          ? null
          : '${Fmt.integer(s.list.totalCount)} sipariş',
      refreshing: s.list.refreshing,
      actions: [
        FilterButton(
          label: 'Süzgeçler',
          count: advanced,
          onPressed: () => showOrderFiltersSheet(context),
        ),
      ],
      // Arama, segmentler ve süzgeç özeti listeyle birlikte kayar.
      body: PagedListBody<BayiOrderRow>(
        list: s.list,
        header: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: SearchField(
              hint: 'Sipariş no, cari, ürün, nokta',
              controller: _search,
              onChanged: c.setQuery,
            ),
          ),
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
          if (advanced > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _describe(f),
                    style: context.aknText.caption,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  TextButton(
                    onPressed: () => c.setFilter(f.clearAdvanced()),
                    child: const Text(BayiCopy.clearFilters),
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
        itemBuilder: (context, row, _) => BayiOrderCard(row: row),
      ),
    );
  }

  static String _describe(BayiOrdersFilter f) => [
    if (f.statuses.isNotEmpty) f.statuses.map((s) => s.label).join(', '),
    if (f.paymentStatus != null) 'Ödeme: ${f.paymentStatus!.label}',
    if (f.financeStatus != null) f.financeStatus!.label,
    if (f.customerId != null) f.customerTitle ?? 'Cari #${f.customerId}',
    if (f.createdFrom != null || f.createdTo != null)
      'Oluşturulma ${Fmt.date(f.createdFrom)}–${Fmt.date(f.createdTo)}',
    if (f.requestedFrom != null || f.requestedTo != null)
      'Teslim ${Fmt.date(f.requestedFrom)}–${Fmt.date(f.requestedTo)}',
    if (f.sort != BayiOrderSort.created) f.sort.label,
  ].join(' · ');
}

/// Sipariş satırı.
class BayiOrderCard extends StatelessWidget {
  const BayiOrderCard({super.key, required this.row});

  final BayiOrderRow row;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final r = row;
    final quoted = r.unitPrice != null;
    final expires = r.expiresAt;
    final showCountdown =
        expires != null && expires.isAfter(DateTime.now().toUtc());
    return AknCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      onTap: () => GoRouter.of(context).push(AppRoutes.bayiOrder(r.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  r.orderNumber,
                  style: t.label.copyWith(color: c.dim),
                ),
              ),
              FitEnd(
                child: StatusChip.style(
                  r.status.statusStyle.withLabel(r.statusLabel),
                  size: StatusChipSize.small,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(r.customerTitle ?? '—', style: t.bodyStrong),
          const SizedBox(height: 2),
          Text(
            [
              ?r.productName,
              Fmt.liters(r.quantityLiters),
              ?r.deliveryCity,
            ].join(' · '),
            style: t.bodySmall,
          ),
          Text(
            'İstenen teslim ${Fmt.date(r.requestedDeliveryDate)}'
            '${quoted ? ' · ${Fmt.unitPrice(r.unitPrice)}' : ''}'
            '${r.totalAmount == null ? '' : ' · ${Fmt.money(r.totalAmount)}'}',
            style: t.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (r.financeStatus != OrderFinanceStatus.notRequired)
                FitStart(
                  child: StatusChip.style(
                    r.financeStatus.statusStyle.withLabel(r.financeLabel),
                    size: StatusChipSize.small,
                  ),
                ),
              if (r.paymentStatus != PaymentStatus.none)
                FitStart(
                  child: StatusChip(
                    label:
                        '${r.paymentMethodName ?? 'Ödeme'} · ${r.paymentStatusLabel ?? r.paymentStatus.label}',
                    tone: r.paymentStatus.statusStyle.tone,
                    icon: Icons.payments_outlined,
                    size: StatusChipSize.small,
                  ),
                ),
              if (r.shipmentState != BayiShipmentState.none)
                FitStart(
                  child: StatusChip(
                    label: r.shipmentStateLabel ?? r.shipmentState.label,
                    tone: _shipmentTone(r.shipmentState),
                    icon: Icons.local_shipping_outlined,
                    size: StatusChipSize.small,
                  ),
                ),
              if (r.remainingLiters > 0)
                ToneTag(
                  label: 'Planlanacak ${Fmt.liters(r.remainingLiters)}',
                  tone: AknTone.info,
                  icon: Icons.event_note_rounded,
                ),
              if (showCountdown)
                FitStart(
                  child: CountdownBadge(deadline: expires, showRing: false),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static AknTone _shipmentTone(BayiShipmentState s) => switch (s) {
    BayiShipmentState.disputed => AknTone.danger,
    BayiShipmentState.reported => AknTone.warn,
    BayiShipmentState.inTransit => AknTone.brand,
    BayiShipmentState.planned => AknTone.info,
    BayiShipmentState.delivered => AknTone.ok,
    BayiShipmentState.partial => AknTone.info,
    BayiShipmentState.none => AknTone.neutral,
  };
}

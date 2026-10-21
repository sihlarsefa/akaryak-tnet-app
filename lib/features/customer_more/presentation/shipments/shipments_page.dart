import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/models/shipment.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/shipments_controller.dart';
import '../../copy.dart';
import '../cm_widgets.dart';

/// Teslimatlar (müşteri): Aktif / Geçmiş, durum çipleri (sunucu sayaçları), arama, sonsuz kaydırma.
/// Kabul bekleyen teslimatlar vurgulanır ("Teslimatı onaylayın").
class ShipmentsPage extends ConsumerWidget {
  const ShipmentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(shipmentsControllerProvider);
    final ctrl = ref.read(shipmentsControllerProvider.notifier);
    final c = s.counts;
    final chips = <FilterOption<ShipmentStatus>>[
      for (final st in s.segment.statuses)
        FilterOption(
          value: st,
          label: switch (st) {
            ShipmentStatus.reported => 'Onay bekleyen',
            ShipmentStatus.inTransit => 'Yolda',
            ShipmentStatus.planned => 'Planlandı',
            ShipmentStatus.disputed => 'İtirazlı',
            ShipmentStatus.accepted => 'Teslim alındı',
            ShipmentStatus.cancelled => 'İptal',
            ShipmentStatus.unknown => st.label,
          },
          count: c.of(st),
        ),
    ];
    final awaiting = c.reported;
    return AppScaffold(
      title: CmCopy.shipmentsTitle,
      refreshing: s.page.refreshing,
      body: Column(
        children: [
          const SizedBox(height: 8),
          CmSegmented<ShipmentSegment>(
            segments: [
              for (final seg in ShipmentSegment.values)
                FilterOption(
                  value: seg,
                  label: seg.label,
                  count: s.page.loading && s.counts.all == 0
                      ? null
                      : s.segmentCount(seg),
                ),
            ],
            value: s.segment,
            onChanged: ctrl.setSegment,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SearchField(
              hint: 'Sipariş no, SVK kodu, plaka ara',
              onChanged: ctrl.setSearch,
            ),
          ),
          FilterChips<ShipmentStatus>(
            options: chips,
            selected: {?s.status},
            onChanged: (set) => ctrl.setStatus(set.firstOrNull),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: _ShipmentList(
              state: s,
              // Liste ile kayar: büyük yazı boyutunda sabit başlık ekranı doldurmasın.
              leading:
                  s.segment == ShipmentSegment.active &&
                      awaiting > 0 &&
                      s.status != ShipmentStatus.reported
                  ? AknBanner(
                      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                      tone: AknTone.warn,
                      icon: Icons.fact_check_rounded,
                      title: '$awaiting ${CmCopy.awaitingBanner}',
                      message:
                          'Teslim edilen miktarı ve kanıtları kontrol edip onaylayın ya da itiraz edin.',
                      actionLabel: 'Göster',
                      onAction: () => ctrl.setStatus(ShipmentStatus.reported),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShipmentList extends ConsumerWidget {
  const _ShipmentList({required this.state, this.leading});

  final ShipmentsState state;

  /// Listenin başında, kayan bilgi (ör. onay bekleyen teslimatlar).
  final Widget? leading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(shipmentsControllerProvider.notifier);
    final p = state.page;
    if (p.showSkeleton) return const SkeletonList(itemCount: 5);
    if (p.isEmpty) {
      final err = p.error;
      Widget child;
      if (err != null) {
        child = CmFailureView(failure: err, onRetry: ctrl.load);
      } else if (state.filtered) {
        child = EmptyState(
          title: CmCopy.filteredEmpty,
          message: 'Arama ya da durum seçimini değiştirin.',
          illustration: AknIllustration.search,
          actionLabel: CmCopy.clearFilters,
          onAction: ctrl.clearFilters,
        );
      } else {
        child = EmptyState(
          title: state.segment == ShipmentSegment.active
              ? CmCopy.shipmentsEmpty
              : CmCopy.historyEmpty,
          message: CmCopy.shipmentsEmptyMessage,
          illustration: AknIllustration.delivery,
        );
      }
      return PullToRefresh(
        onRefresh: () => ctrl.load(refresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [?leading, child],
        ),
      );
    }
    return PullToRefresh(
      onRefresh: () => ctrl.load(refresh: true),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 400) ctrl.loadMore();
          return false;
        },
        child: StaggerScope(
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            itemCount: p.items.length + 1 + (leading == null ? 0 : 1),
            itemBuilder: (context, index) {
              final lead = leading;
              if (lead != null && index == 0) return lead;
              final i = lead == null ? index : index - 1;
              if (i == p.items.length) {
                return LoadMoreFooter(
                  loading: p.loadingMore,
                  error: p.loadMoreError,
                  onRetry: ctrl.loadMore,
                );
              }
              final item = p.items[i];
              return StaggerItem(
                index: i,
                child: ShipmentCard(
                  item: item,
                  onTap: () => context.push(AppRoutes.shipment(item.id)),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Teslimat satırı.
class ShipmentCard extends StatelessWidget {
  const ShipmentCard({super.key, required this.item, this.onTap});

  final ShipmentListItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final st = item.status.statusStyle;
    final reported = item.status == ShipmentStatus.reported;
    final disputed = item.status == ShipmentStatus.disputed;
    final delivered = item.deliveredLiters;
    final place = [
      item.deliveryPointName,
      [
        item.deliveryDistrict,
        item.deliveryCity,
      ].whereType<String>().join(' / '),
    ].whereType<String>().where((x) => x.isNotEmpty).join(' · ');
    final when = item.deliveredAt != null
        ? 'Teslim ${Fmt.dayLabel(item.deliveredAt)} ${Fmt.time(item.deliveredAt)}'
        : 'Plan ${Fmt.dayLabel(item.scheduledAt)} ${Fmt.time(item.scheduledAt)}';
    final litres = delivered == null
        ? Fmt.liters(item.plannedLiters)
        : '${Fmt.liters(delivered)} / ${Fmt.liters(item.plannedLiters)}';
    final label = [
      item.code,
      st.label,
      '${item.productName} $litres',
      if (place.isNotEmpty) place,
      when,
      if (item.vehiclePlate.isNotEmpty) 'Plaka ${Fmt.plate(item.vehiclePlate)}',
      if (reported) 'Teslimatı onaylayın',
    ].join(', ');
    return AknCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      onTap: onTap,
      accent: reported ? AknTone.warn : (disputed ? AknTone.danger : null),
      semanticLabel: label,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CmHeadRow(
              title: Text(
                '${item.code} · ${item.orderNumber}',
                style: t.caption,
              ),
              trailing: StatusChip.style(st, size: StatusChipSize.small),
            ),
            const SizedBox(height: 6),
            Text(
              '${item.productName} · $litres',
              style: t.bodyStrong.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (place.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(place, style: t.bodySmall),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.deliveredAt != null
                          ? Icons.task_alt_rounded
                          : Icons.event_rounded,
                      size: 16,
                      color: c.dim,
                    ),
                    const SizedBox(width: 4),
                    Flexible(child: Text(when, style: t.caption)),
                  ],
                ),
                if (item.vehiclePlate.isNotEmpty)
                  PlateBadge(plate: item.vehiclePlate, fontSize: 11),
              ],
            ),
            if (reported) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.fact_check_rounded, size: 18, color: c.warn.fg),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Teslimatı onaylayın',
                      style: t.label.copyWith(color: c.warn.fg),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: c.warn.fg),
                ],
              ),
            ],
            if (disputed && item.disputeNote != null) ...[
              const SizedBox(height: 8),
              Text(
                'İtiraz: ${item.disputeNote}',
                style: t.bodySmall.copyWith(color: c.danger.fg),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

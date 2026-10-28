import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/models/shipment.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/turkish_text.dart';
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
          const SizedBox(height: 4),
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
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: CmSearchField(
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
                      margin: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                      tone: AknTone.brand,
                      icon: PhosphorIconsRegular.listChecks,
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
          children: [
            ?leading,
            FadeUp(offset: 16, scale: 0.97, child: child),
          ],
        ),
      );
    }
    // Kartlar sırayla yükselerek gelir; süzgeç ya da arama değişince akış yeniden başlar.
    return StaggerScope(
      key: ValueKey((state.segment, state.status, state.search)),
      child: PullToRefresh(
        onRefresh: () => ctrl.load(refresh: true),
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.extentAfter < 400) ctrl.loadMore();
            return false;
          },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              top: 4,
              bottom: 16 + MediaQuery.paddingOf(context).bottom,
            ),
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
                key: ValueKey(item.id),
                index: i,
                child: Padding(
                  padding: CmCard.listMargin,
                  child: ShipmentCard(
                    item: item,
                    onTap: () => context.push(AppRoutes.shipment(item.id)),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Teslimat kartı (tasarım v3 §4): beyaz r20 kart; başta durumun simge karosu, ürün ve litre, nokta
/// ve gün, sağda plaka; ince çizginin altında durum lambası (müşterinin gözünden: "Teslimatı
/// onaylayın" sıra sizde) ve saat; yoldaysa rota çizgisi, itirazlıysa not. Basınca 0,97'ye iner.
class ShipmentCard extends StatelessWidget {
  const ShipmentCard({super.key, required this.item, this.onTap});

  final ShipmentListItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final reported = item.status == ShipmentStatus.reported;
    final disputed = item.status == ShipmentStatus.disputed;
    final inTransit = item.status == ShipmentStatus.inTransit;
    final delivered = item.deliveredLiters;
    final lamp = AknStatus.shipmentLamp(
      item.status,
      const StatusViewer.customer(),
    );
    final day = item.deliveredAt ?? item.scheduledAt;
    final place = [
      item.deliveryPointName ??
          [
            item.deliveryDistrict,
            item.deliveryCity,
          ].whereType<String>().join(' / '),
      if (day != null) TurkishText.lower(Fmt.dayLabel(day)),
    ].where((x) => x.isNotEmpty).join(', ');
    final time = item.deliveredAt != null
        ? 'teslim ${Fmt.time(item.deliveredAt)}'
        : (item.scheduledAt == null
              ? null
              : '${inTransit ? 'varış' : 'plan'} ${Fmt.time(item.scheduledAt)}');
    final litres = delivered == null
        ? Fmt.liters(item.plannedLiters)
        : Fmt.liters(delivered);
    final title = '${item.productName}, $litres';
    final plate = item.vehiclePlate.isEmpty
        ? null
        : Fmt.plate(item.vehiclePlate);
    final label = [
      title,
      if (delivered != null) 'planlanan ${Fmt.liters(item.plannedLiters)}',
      if (place.isNotEmpty) place,
      lamp.label,
      ?time,
      if (plate != null) 'plaka $plate',
      item.code,
      'sipariş ${item.orderNumber}',
      if (disputed && item.disputeNote != null) 'itiraz: ${item.disputeNote}',
    ].join(', ');
    final tap = onTap;
    return CmCard(
      pressable: tap != null,
      child: AknListTile(
        leading: CmIconTile(icon: _statusIcon(item.status), tone: lamp.tone),
        padding: CmCard.rowPadding,
        titleStyle: cmRowTitle(context),
        title: cmKeepUnits(title),
        subtitle: place.isEmpty ? item.code : place,
        meta: plate,
        footer: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Divider(height: 1, thickness: 1, color: c.lineSoft),
            const SizedBox(height: 10),
            AknStatusLine(
              lamp: AknLamp.status(lamp),
              trailing: time == null
                  ? null
                  : Text(
                      time,
                      style: t.bodySmall.copyWith(
                        color: reported ? c.brandInk : c.ink,
                        fontWeight: FontWeight.w600,
                        fontFeatures: AknNumerals.tabular,
                      ),
                    ),
            ),
            if (inTransit) ...[
              const SizedBox(height: 12),
              const TruckRoute(moving: true, height: 22),
            ] else if (disputed && item.disputeNote != null) ...[
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
        semanticLabel: label,
        onTap: tap == null
            ? null
            : () {
                AknHaptics.selection();
                tap();
              },
      ),
    );
  }

  /// Kartın baş simgesi: planlandı (takvim), yolda (tır), teslim (kontrol listesi), kabul (mühür),
  /// itiraz, iptal.
  static IconData _statusIcon(ShipmentStatus s) => switch (s) {
    ShipmentStatus.planned => PhosphorIconsRegular.calendarCheck,
    ShipmentStatus.inTransit => PhosphorIconsRegular.truck,
    ShipmentStatus.reported => PhosphorIconsRegular.listChecks,
    ShipmentStatus.accepted => PhosphorIconsRegular.sealCheck,
    ShipmentStatus.disputed => PhosphorIconsRegular.warningOctagon,
    ShipmentStatus.cancelled => PhosphorIconsRegular.xCircle,
    ShipmentStatus.unknown => PhosphorIconsRegular.truck,
  };
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/permissions.dart';
import '../../../../core/auth/session_controller.dart';
import '../../../../core/models/enums.dart';
import '../../../../core/models/shipment.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../../customer_orders/api.dart' show LedgerSliver;
import '../../application/shipments_controller.dart';
import '../../copy.dart';
import '../cm_widgets.dart';

/// Teslimatlar (müşteri; tasarım v4 §3.2): sayfa bandı "Teslimatlar" ve canlı durum satırı ("1
/// teslimat onayınızı bekliyor") + ⌕ + Filtre (durum) → tek
/// anahtar [AknSegmented] (Aktif · Geçmiş) → tek defter: satırlar kutusuz, karo ve hap yok; sıra
/// sizdeyse Pas iş satırı "Teslimatı onaylayın". Sonsuz kaydırma.
class ShipmentsPage extends ConsumerStatefulWidget {
  const ShipmentsPage({super.key});

  @override
  ConsumerState<ShipmentsPage> createState() => _ShipmentsPageState();
}

class _ShipmentsPageState extends ConsumerState<ShipmentsPage> {
  bool _search = false;
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  static String _statusLabel(ShipmentStatus st) => switch (st) {
    ShipmentStatus.reported => 'Onay bekleyen',
    ShipmentStatus.inTransit => 'Yolda',
    ShipmentStatus.planned => 'Planlandı',
    ShipmentStatus.disputed => 'İtirazlı',
    ShipmentStatus.accepted => 'Teslim alındı',
    ShipmentStatus.cancelled => 'İptal',
    ShipmentStatus.unknown => st.label,
  };

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(shipmentsControllerProvider);
    final ctrl = ref.read(shipmentsControllerProvider.notifier);
    final policy = ref.watch(accessPolicyProvider);
    final canDecide = policy.can(Pg.customerQuotes, Perm.edit);
    final c = s.counts;
    final awaiting = c.reported;
    final moving = c.of(ShipmentStatus.inTransit);
    final Object? status = awaiting > 0
        ? (canDecide
              ? AknStatusClause.yourMove('$awaiting ${CmCopy.awaitingBanner}')
              : '$awaiting teslimat onay bekliyor')
        : s.page.loading && c.all == 0
        ? null
        : moving > 0
        ? '$moving teslimat yolda'
        : 'Yolda teslimat yok';
    return AppScaffold(
      title: CmCopy.shipmentsTitle,
      bandIcon: PhosphorIconsRegular.truck,
      // Durum satırına dokunmak süzgeç olurdu; çekirdeğin bandında satırın dokunma alanı 48 dp
      // değil (bildirildi): onay bekleyenler Filtre'den süzülür.
      status: status,
      refreshing: s.page.refreshing,
      actions: [
        AknSearchReveal.button(
          semanticLabel: 'Teslimatlarda ara',
          onPressed: () => setState(() => _search = true),
        ),
        AknFilterButton(
          count: s.status == null ? 0 : 1,
          sheetBuilder: (ctx) => Consumer(
            builder: (ctx, ref, _) {
              final st = ref.watch(shipmentsControllerProvider);
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: FilterChips<ShipmentStatus>(
                  options: [
                    for (final x in st.segment.statuses)
                      FilterOption(
                        value: x,
                        label: _statusLabel(x),
                        count: st.counts.of(x),
                      ),
                  ],
                  selected: {?st.status},
                  onChanged: (set) {
                    ref
                        .read(shipmentsControllerProvider.notifier)
                        .setStatus(set.firstOrNull);
                    Navigator.of(ctx).maybePop();
                  },
                ),
              );
            },
          ),
        ),
      ],
      body: Column(
        children: [
          AknSearchReveal(
            open: _search,
            controller: _query,
            hint: 'Ürün, nokta ya da plaka ara',
            onChanged: ctrl.setSearch,
            onClose: () => setState(() => _search = false),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: AknSegmented<ShipmentSegment>(
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
          ),
          Expanded(
            child: _ShipmentList(state: s, canDecide: canDecide),
          ),
        ],
      ),
    );
  }
}

class _ShipmentList extends ConsumerWidget {
  const _ShipmentList({required this.state, required this.canDecide});

  final ShipmentsState state;
  final bool canDecide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(shipmentsControllerProvider.notifier);
    final p = state.page;
    if (p.showSkeleton) {
      return const SkeletonList(itemCount: 5, lines: 3, leading: false);
    }
    if (p.isEmpty) {
      final err = p.error;
      Widget child;
      if (err != null) {
        child = CmFailureView(failure: err, onRetry: ctrl.load);
      } else if (state.filtered) {
        final q = state.search.trim();
        child = EmptyState.compact(
          title: q.isEmpty ? CmCopy.filteredEmpty : '‘$q’ için sonuç yok',
          message: 'Yazımı kontrol edin ya da filtreleri temizleyin.',
          illustration: AknIllustration.search,
          actionLabel: CmCopy.clearFilters,
          onAction: ctrl.clearFilters,
        );
      } else {
        child = EmptyState.compact(
          title: state.segment == ShipmentSegment.active
              ? CmCopy.shipmentsEmpty
              : CmCopy.historyEmpty,
          message: state.segment == ShipmentSegment.active
              ? CmCopy.shipmentsEmptyMessage
              : 'Teslim alınan ve iptal edilen teslimatlar burada.',
          illustration: AknIllustration.delivery,
        );
      }
      return PullToRefresh(
        onRefresh: () => ctrl.load(refresh: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 32),
            FadeUp(offset: 16, scale: 0.97, child: child),
          ],
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
        child: CustomScrollView(
          key: ValueKey((state.segment, state.status, state.search)),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            LedgerSliver(
              first: true,
              rows: [
                for (final (i, item) in p.items.indexed)
                  AknRowPour(
                    index: i,
                    child: ShipmentCard(
                      key: ValueKey(item.id),
                      item: item,
                      canDecide: canDecide,
                      onTap: () => context.push(AppRoutes.shipment(item.id)),
                    ),
                  ),
              ],
            ),
            SliverToBoxAdapter(
              child: LoadMoreFooter(
                loading: p.loadingMore,
                error: p.loadMoreError,
                onRetry: ctrl.loadMore,
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.only(
                bottom: 16 + MediaQuery.paddingOf(context).bottom,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Teslimat satırı (tasarım v4 defter satırı): ürün ve litre, nokta ve gün, sağda saat ("teslim
/// 15:40", "varış 09:00"); sıra sizdeyse Pas iş satırı "Teslimatı onaylayın"; durum hapı yalnızca
/// itirazlı ya da iptal teslimatta. Kod ve plaka ayrıntıda yazar.
class ShipmentCard extends StatelessWidget {
  const ShipmentCard({
    super.key,
    required this.item,
    this.onTap,
    this.canDecide = true,
  });

  final ShipmentListItem item;
  final VoidCallback? onTap;

  /// Teslimatı onaylayabilir (yönetici / onaylayan): "Teslimatı onaylayın" sıra sizde.
  final bool canDecide;

  @override
  Widget build(BuildContext context) {
    final disputed = item.status == ShipmentStatus.disputed;
    final inTransit = item.status == ShipmentStatus.inTransit;
    final delivered = item.deliveredLiters;
    final lamp = AknStatus.shipmentLamp(
      item.status,
      StatusViewer.customer(canDecide: canDecide),
    );
    final day = item.deliveredAt ?? item.scheduledAt;
    final place = [
      item.deliveryPointName ??
          [
            item.deliveryDistrict,
            item.deliveryCity,
          ].whereType<String>().join(' / '),
      if (day != null) TurkishText.lower(Fmt.dayLabel(day)),
    ].where((x) => x.isNotEmpty).join(' · ');
    final time = item.deliveredAt != null
        ? 'teslim ${Fmt.time(item.deliveredAt)}'
        : (item.scheduledAt == null
              ? null
              : '${inTransit ? 'varış' : 'plan'} ${Fmt.time(item.scheduledAt)}');
    final litres = delivered == null
        ? Fmt.liters(item.plannedLiters)
        : Fmt.liters(delivered);
    final title = '${item.productName}, $litres';
    // Olağan durum soluk ikinci satırda; sıra sizdeyse Pas iş satırı; sorun hapla.
    final calm = !lamp.yourMove && !lamp.problem;
    final label = [
      title,
      if (delivered != null) 'planlanan ${Fmt.liters(item.plannedLiters)}',
      if (place.isNotEmpty) place,
      lamp.label,
      ?time,
      item.code,
      'sipariş ${item.orderNumber}',
      if (disputed && item.disputeNote != null) 'itiraz: ${item.disputeNote}',
    ].join(', ');
    final tap = onTap;
    return AknListTile(
      title: cmKeepUnits(title),
      subtitle: [if (calm) lamp.label, if (place.isNotEmpty) place].join(' · '),
      meta: time,
      next: lamp.yourMove ? lamp.label : null,
      status: lamp.problem ? AknLamp.status(lamp) : null,
      semanticLabel: label,
      onTap: tap == null
          ? null
          : () {
              AknHaptics.selection();
              tap();
            },
    );
  }
}

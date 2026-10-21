import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/permissions.dart';
import '../../../../core/auth/session_controller.dart';
import '../../../../core/models/models.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../application/bayi_grants.dart';
import '../../application/bayi_runtime.dart';
import '../../application/dispatch_controller.dart';
import '../../copy.dart';
import '../../data/dispatch_models.dart';
import '../widgets/bayi_widgets.dart';
import '../widgets/paged_list_body.dart';
import 'plan_sheet.dart';
import 'shipment_sheet.dart';

enum _Segment { board, list }

/// Sevkiyat (spec A.4 / A.3 adım 5–7): pano (planlanacak siparişler kovalarda, açık sevkiyatlar günlere
/// göre, şoför hesabı uyarısı) ve "Sevkiyatlar" listesi (durum, itirazlı, bugünkü yüklemeler, tarih,
/// arama). Ayrıntı sayfasından Yola çıkar / Teslim bildir / Şoför değiştir / İptal. Depo personeli
/// listeyi "Bugünkü yüklemeler" ile açar; planlama yetkisi olmayan "Planla" görmez.
class DispatchPage extends ConsumerStatefulWidget {
  const DispatchPage({super.key});

  @override
  ConsumerState<DispatchPage> createState() => _DispatchPageState();
}

class _DispatchPageState extends ConsumerState<DispatchPage> {
  late _Segment _segment = _initialSegment();

  _Segment _initialSegment() {
    final access = ref.read(sessionControllerProvider).access;
    final depot = access?.bayiRoleCodes.contains(BayiRoleCodes.depot) ?? false;
    final g = ref.read(bayiGrantsProvider);
    if (!g.viewBoard) return _Segment.list;
    return depot ? _Segment.list : _Segment.board;
  }

  @override
  Widget build(BuildContext context) {
    final g = ref.watch(bayiGrantsProvider);
    final board = ref.watch(dispatchBoardProvider);
    final list = ref.watch(shipmentListProvider);
    final segments = [
      if (g.viewBoard) const FilterOption(value: _Segment.board, label: 'Pano'),
      if (g.viewShipments)
        const FilterOption(value: _Segment.list, label: 'Sevkiyatlar'),
    ];
    final refreshing = _segment == _Segment.board
        ? board.refreshing
        : list.list.refreshing;
    return AppScaffold(
      title: 'Sevkiyat',
      subtitle: board.data?.stationTitle,
      refreshing: refreshing,
      body: Column(
        children: [
          if (segments.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: BayiSegmented<_Segment>(
                segments: segments,
                value: _segment,
                onChanged: (v) => setState(() => _segment = v),
              ),
            ),
          Expanded(
            child: FadeThroughSwitcher(
              child: _segment == _Segment.board
                  ? const _BoardView(key: ValueKey('board'))
                  : const _ListView(key: ValueKey('list')),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Pano

class _BoardView extends ConsumerWidget {
  const _BoardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(dispatchBoardProvider);
    final c = ref.read(dispatchBoardProvider.notifier);
    return LoadableBody<ShipmentBoard>(
      state: state,
      onRetry: c.refresh,
      builder: (context, b) => PullToRefresh(
        onRefresh: c.refresh,
        child: _BoardList(board: b, state: state),
      ),
    );
  }
}

class _BoardList extends ConsumerWidget {
  const _BoardList({required this.board, required this.state});

  final ShipmentBoard board;
  final Loadable<ShipmentBoard> state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = board;
    final g = ref.watch(bayiGrantsProvider);
    final t = context.aknText;
    final days = _groupByDay(b.shipments);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        UpdatedCaption(updatedAt: state.updatedAt, error: state.error),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              KpiRow(
                children: [
                  KpiTile(
                    label: 'Planlanacak',
                    value: b.orderTotal,
                    icon: Icons.event_note_rounded,
                    tone: b.orderTotal > 0 ? AknTone.info : null,
                    caption: Fmt.liters(b.orderTotalLiters),
                  ),
                  KpiTile(
                    label: 'Planlı',
                    value: b.plannedCount,
                    icon: Icons.event_rounded,
                    caption: Fmt.liters(b.plannedLiters),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              KpiRow(
                children: [
                  KpiTile(
                    label: 'Yolda',
                    value: b.inTransitCount,
                    icon: Icons.local_shipping_rounded,
                    tone: b.inTransitCount > 0 ? AknTone.brand : null,
                    caption: Fmt.liters(b.inTransitLiters),
                  ),
                  KpiTile(
                    label: 'Şoför hesabı yok',
                    value: b.unassignedCount,
                    icon: Icons.person_search_rounded,
                    tone: b.unassignedCount > 0 ? AknTone.warn : null,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (b.unassignedCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: AknBanner(
              tone: AknTone.warn,
              icon: Icons.person_search_rounded,
              message:
                  '${b.unassignedCount} planlı sevkiyatta uygulama şoförü yok; bu teslimatlar şoförün Teslimatlarım listesinde görünmez. Ayrıntıdan "Şoför değiştir" ile atayın.',
            ),
          ),
        if (!g.planShipment)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: AknBanner(
              tone: AknTone.neutral,
              icon: Icons.visibility_outlined,
              message: g.dispatchOrReport
                  ? 'Planlama yetkiniz yok; yola çıkarma ve teslim bildirme sevkiyat ayrıntısından yapılır.'
                  : 'Sevkiyatları görüntüleyebilirsiniz; değişiklik yetkiniz yok.',
            ),
          ),
        BayiSectionHeader(title: 'Planlanacak siparişler', count: b.orderTotal),
        if (b.orders.isEmpty)
          const EmptyState(
            compact: true,
            title: BayiCopy.boardEmptyTitle,
            message: BayiCopy.boardEmptyMessage,
            illustration: AknIllustration.delivery,
          ),
        for (final bucket in BoardBucket.values)
          if (b.ordersIn(bucket).isNotEmpty) ...[
            _BucketHeader(bucket: bucket, summary: b.summaryOf(bucket)),
            ...staggered([
              for (final o in b.ordersIn(bucket))
                _BoardOrderCard(
                  order: o,
                  canPlan: g.planShipment,
                  canOpen: g.viewOrders,
                ),
            ]),
          ],
        BayiSectionHeader(title: 'Açık sevkiyatlar', count: b.shipments.length),
        if (b.shipments.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Planlı ya da yolda sevkiyat yok.', style: t.bodySmall),
          ),
        for (final (title, rows) in days) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
            child: Text(title, style: t.label),
          ),
          SectionCard(
            padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
            child: Column(
              children: [for (final s in rows) BoardShipmentLine(shipment: s)],
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (b.shipmentsTruncated || b.earlierShipmentsTruncated)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Liste sınırına ulaşıldı; tümü için "Sevkiyatlar" sekmesini kullanın.',
              style: t.caption,
            ),
          ),
      ],
    );
  }

  /// "Önceki günler", "Bugün", "Yarın", gün adı.
  static List<(String, List<BoardShipment>)> _groupByDay(
    List<BoardShipment> rows,
  ) {
    final today = TrTime.todayStart();
    final groups = <String, List<BoardShipment>>{};
    for (final s in rows) {
      final at = s.scheduledAt;
      final key = at == null || at.isBefore(today)
          ? 'Önceki günler'
          : '${Fmt.dayLabel(at)} · ${Fmt.date(at)}';
      (groups[key] ??= []).add(s);
    }
    return [for (final e in groups.entries) (e.key, e.value)];
  }
}

class _BucketHeader extends StatelessWidget {
  const _BucketHeader({required this.bucket, this.summary});

  final BoardBucket bucket;
  final BoardBucketSummary? summary;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final s = summary;
    final overdue = bucket == BoardBucket.overdue;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        children: [
          Icon(
            overdue ? Icons.history_rounded : Icons.event_rounded,
            size: 16,
            color: overdue ? c.warn.fg : c.dim,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              s == null
                  ? bucket.label
                  : '${bucket.label} · ${s.count} sipariş · ${Fmt.liters(s.liters)}',
              style: t.label.copyWith(color: overdue ? c.warn.fg : null),
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardOrderCard extends StatelessWidget {
  const _BoardOrderCard({
    required this.order,
    required this.canPlan,
    required this.canOpen,
  });

  final BoardOrder order;
  final bool canPlan;
  final bool canOpen;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final o = order;
    final planned = o.quantityLiters - o.remainingLiters;
    return AknCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      onTap: canOpen
          ? () => GoRouter.of(context).push(AppRoutes.bayiOrder(o.orderId))
          : null,
      accent: o.bucket == BoardBucket.overdue ? AknTone.warn : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(o.customerTitle, style: t.bodyStrong),
          Text([o.orderNumber, o.productName].join(' · '), style: t.bodySmall),
          const SizedBox(height: 8),
          BayiUsageBar(
            value: o.quantityLiters <= 0 ? 0 : planned / o.quantityLiters,
            label: 'Kalan ${Fmt.liters(o.remainingLiters)}',
            valueLabel:
                '${Fmt.liters(planned)} / ${Fmt.liters(o.quantityLiters)} planlı',
            tone: AknTone.info,
            height: 6,
          ),
          const SizedBox(height: 8),
          Text(
            [
              if (o.deliveryDate != null)
                'Teslim ${Fmt.dayLabel(o.deliveryDate)}',
              ?o.deliveryPointName,
              ?o.deliveryCity,
            ].join(' · '),
            style: t.bodySmall,
          ),
          if (o.window != null || o.tankCapacityLiters != null)
            Text(
              [
                if (o.window != null) 'Pencere ${o.window}',
                if (o.tankCapacityLiters != null)
                  'Tank ${Fmt.liters(o.tankCapacityLiters)}',
              ].join(' · '),
              style: t.bodySmall,
            ),
          if (canPlan) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: AknButton(
                label: 'Planla',
                icon: Icons.event_available_rounded,
                size: AknButtonSize.small,
                semanticLabel: '${o.orderNumber} için sevkiyat planla',
                onPressed: () =>
                    showPlanSheet(context, PlanTarget.fromBoard(o)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Pano sevkiyat satırı: saat, durum, cari, litre, plaka, şoför ve "uygulamada" rozeti.
class BoardShipmentLine extends StatelessWidget {
  const BoardShipmentLine({super.key, required this.shipment});

  final BoardShipment shipment;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final s = shipment;
    return Semantics(
      button: true,
      label: [
        s.code,
        s.status.label,
        s.customerTitle,
        Fmt.liters(s.plannedLiters),
        if (s.scheduledAt != null) Fmt.time(s.scheduledAt),
        if (s.driverName.isNotEmpty) s.driverName,
        if (s.isAppDriver) 'uygulamada',
        if (!s.hasDriverAccount) 'şoför hesabı yok',
      ].join(', '),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => showShipmentSheet(context, s.id, code: s.code),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 50,
                child: Text(
                  s.scheduledAt == null ? Fmt.dash : Fmt.time(s.scheduledAt),
                  style: t.bodyStrong.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.customerTitle, style: t.bodyStrong),
                    Text(
                      [
                        Fmt.liters(s.plannedLiters),
                        if (s.driverName.isNotEmpty) s.driverName,
                      ].join(' · '),
                      style: t.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FitStart(
                          child: StatusChip.style(
                            s.status.statusStyle,
                            size: StatusChipSize.small,
                          ),
                        ),
                        if (s.vehiclePlate.isNotEmpty)
                          PlateBadge(plate: s.vehiclePlate, fontSize: 11),
                        if (s.isAppDriver) const InAppBadge(),
                        if (!s.hasDriverAccount &&
                            s.status == ShipmentStatus.planned)
                          const ToneTag(
                            label: 'Şoför hesabı yok',
                            tone: AknTone.warn,
                            icon: Icons.person_off_outlined,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ Sevkiyatlar listesi

class _ListView extends ConsumerStatefulWidget {
  const _ListView({super.key});

  @override
  ConsumerState<_ListView> createState() => _ListViewState();
}

class _ListViewState extends ConsumerState<_ListView> {
  // Arama kutusu listeyle kayar; yazılan metin kutu ekrandan çıkınca kaybolmasın.
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(
      text: ref.read(shipmentListProvider).filter.search,
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _clear() {
    _search.clear();
    ref.read(shipmentListProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(shipmentListProvider);
    final c = ref.read(shipmentListProvider.notifier);
    final f = s.filter;
    final counts = s.counts;
    const statuses = [
      ShipmentStatus.planned,
      ShipmentStatus.inTransit,
      ShipmentStatus.reported,
      ShipmentStatus.disputed,
      ShipmentStatus.accepted,
      ShipmentStatus.cancelled,
    ];
    final t = context.aknText;
    final today = TrTime.todayStart();
    // Arama, çipler ve özet listeyle birlikte kayar (küçük ekranda / büyük yazıda liste sıkışmaz).
    final header = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: SearchField(
          hint: 'Sevkiyat no, sipariş no, plaka, şoför',
          controller: _search,
          onChanged: c.setSearch,
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _Chip(
              label: 'Bugünkü yüklemeler',
              icon: Icons.local_gas_station_outlined,
              selected: f.todayLoadings,
              onTap: c.toggleTodayLoadings,
            ),
            _Chip(
              label: 'İtirazlı',
              icon: Icons.report_outlined,
              selected: f.hasDispute,
              onTap: c.toggleDisputes,
            ),
            for (final st in statuses)
              _Chip(
                label: st.label,
                count: counts?.countOf(st),
                selected:
                    !f.todayLoadings &&
                    f.statuses.length == 1 &&
                    f.statuses.contains(st),
                onTap: () => c.toggleStatus(st),
              ),
          ],
        ),
      ),
      if (f.scheduledFrom != null || f.scheduledTo != null || f.todayLoadings)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                f.todayLoadings
                    ? 'Bugün (${Fmt.date(today)}) planlanan ve yoldaki sevkiyatlar, yükleme sırasıyla'
                    : 'Plan tarihi ${Fmt.date(f.scheduledFrom)}–${Fmt.date(f.scheduledTo)}',
                style: t.caption,
              ),
              TextButton(
                onPressed: _clear,
                child: const Text(BayiCopy.clearFilters),
              ),
            ],
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: TextButton.icon(
            onPressed: () => _pickRange(context),
            icon: const Icon(Icons.date_range_rounded, size: 18),
            label: const Text('Tarih aralığı'),
          ),
        ),
      ),
    ];
    return PagedListBody<ShipmentListItem>(
      list: s.list,
      header: header,
      onRefresh: () => c.reload(silent: true),
      onLoadMore: () => unawaited(c.loadMore()),
      filtered: f.isFiltered && !f.todayLoadings,
      onClearFilters: _clear,
      empty: EmptyState(
        title: f.todayLoadings
            ? BayiCopy.todayLoadingsEmpty
            : BayiCopy.shipmentsEmptyTitle,
        message: f.todayLoadings ? null : BayiCopy.shipmentsEmptyMessage,
        illustration: AknIllustration.delivery,
      ),
      itemBuilder: (context, row, _) => ShipmentListCard(item: row),
    );
  }

  Future<void> _pickRange(BuildContext context) async {
    final today = TrTime.todayStart();
    DateTime local(DateTime i) {
      final w = TrTime.wall(i);
      return DateTime(w.year, w.month, w.day);
    }

    final f = ref.read(shipmentListProvider).filter;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: local(TrTime.addDays(today, -365)),
      lastDate: local(TrTime.addDays(today, 90)),
      initialDateRange: f.scheduledFrom == null || f.scheduledTo == null
          ? null
          : DateTimeRange(
              start: local(f.scheduledFrom!),
              end: local(f.scheduledTo!),
            ),
      helpText: 'Plan tarihi aralığı',
      cancelText: 'Vazgeç',
      confirmText: 'Uygula',
      saveText: 'Uygula',
    );
    if (picked == null) return;
    ref
        .read(shipmentListProvider.notifier)
        .setRange(
          TrTime.fromWall(
            picked.start.year,
            picked.start.month,
            picked.start.day,
          ),
          TrTime.fromWall(picked.end.year, picked.end.month, picked.end.day),
        );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.count,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final int? count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: FilterChip(
      label: Text(count == null ? label : '$label  $count'),
      avatar: selected || icon == null ? null : Icon(icon, size: 16),
      selected: selected,
      onSelected: (_) => onTap(),
    ),
  );
}

/// Sevkiyat listesi satırı.
class ShipmentListCard extends StatelessWidget {
  const ShipmentListCard({super.key, required this.item});

  final ShipmentListItem item;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final s = item;
    final diff = s.differenceLiters;
    return AknCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      accent: s.status == ShipmentStatus.disputed ? AknTone.danger : null,
      onTap: () => showShipmentSheet(context, s.id, code: s.code),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.code,
                  style: t.label.copyWith(color: context.akn.dim),
                ),
              ),
              FitEnd(
                child: StatusChip.style(
                  s.status.statusStyle,
                  size: StatusChipSize.small,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(s.customerName, style: t.bodyStrong),
          Text(
            [
              s.orderNumber,
              s.productName,
              Fmt.liters(s.deliveredLiters ?? s.plannedLiters),
              if (diff != null && diff.abs() >= 0.001)
                'fark ${Fmt.liters(diff)}',
            ].join(' · '),
            style: t.bodySmall,
          ),
          Text(
            [
              'Plan ${Fmt.dateTime(s.scheduledAt)}',
              ?s.deliveryPointName,
            ].join(' · '),
            style: t.bodySmall,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (s.vehiclePlate.isNotEmpty)
                PlateBadge(plate: s.vehiclePlate, fontSize: 11),
              if (s.driverName.isNotEmpty)
                ToneTag(
                  label: s.driverName,
                  icon: Icons.person_outline_rounded,
                ),
              if (s.deliveryDocumentNo != null)
                ToneTag(
                  label: 'İrsaliye ${s.deliveryDocumentNo}',
                  icon: Icons.description_outlined,
                ),
            ],
          ),
          if (s.disputeNote != null) ...[
            const SizedBox(height: 8),
            Text(
              s.disputeNote!,
              style: t.bodySmall.copyWith(color: context.akn.danger.fg),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

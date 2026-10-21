import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../application/spending_controller.dart';
import '../../copy.dart';
import '../../data/customer_more_repository.dart';
import '../../data/spending.dart';
import '../cm_widgets.dart';
import 'spending_charts.dart';

/// Harcamalar: yalnızca sunucu toplamları (`customers/me/spending`). Sekmeler Ay / Ürün / Nokta / Bayi,
/// çubuklar bu özellikte çizilir; ortalama ₺/L sunucudan; aralık en geniş 36 ay.
class SpendingPage extends ConsumerWidget {
  const SpendingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(spendingControllerProvider);
    final ctrl = ref.read(spendingControllerProvider.notifier);
    final r = s.report;
    return AppScaffold(
      title: CmCopy.spendingTitle,
      subtitle: '${Fmt.date(s.range.from)} – ${Fmt.date(s.range.to)}',
      refreshing: s.loading && r != null,
      body: PullToRefresh(
        onRefresh: ctrl.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const SizedBox(height: 8),
            FilterChips<SpendingPreset>(
              options: [
                for (final p in SpendingPreset.values)
                  FilterOption(
                    value: p,
                    label: p == SpendingPreset.custom ? 'Özel…' : p.label,
                    icon: p == SpendingPreset.custom
                        ? Icons.date_range_rounded
                        : null,
                  ),
              ],
              selected: {s.preset},
              allowEmpty: false,
              onChanged: (set) async {
                final p = set.firstOrNull;
                if (p == null) return;
                if (p == SpendingPreset.custom) {
                  await _pickCustom(context, ctrl, s.range);
                } else {
                  ctrl.setPreset(p);
                }
              },
            ),
            if (!s.filter.isEmpty) _ActiveFilters(filter: s.filter),
            if (s.clamped)
              AknBanner(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                tone: AknTone.warn,
                message:
                    'Rapor en fazla ${SpendingRange.maxMonths} ay kapsar; başlangıç tarihi ${Fmt.date(s.range.from)} olarak kısaltıldı.',
              ),
            if (r == null && s.loading)
              const _SpendingSkeleton()
            else if (r == null && s.error != null)
              CmFailureView(failure: s.error!, onRetry: ctrl.load)
            else if (r != null) ...[
              _Kpis(report: r),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: context.akn.dim,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        CmCopy.spendingCaption,
                        style: context.aknText.caption.copyWith(
                          color: context.akn.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (r.truncated)
                const AknBanner(
                  margin: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  tone: AknTone.info,
                  message:
                      'Kırılımlarda en yüksek tutarlı kayıtlar gösteriliyor; toplamlar tüm siparişleri kapsar.',
                ),
              if (r.isEmpty)
                EmptyState(
                  title: 'Bu aralıkta harcama yok',
                  message: CmCopy.spendingEmpty,
                  illustration: AknIllustration.orders,
                  actionLabel: s.filter.isEmpty ? null : 'Süzgeci kaldır',
                  onAction: s.filter.isEmpty
                      ? null
                      : () => ctrl.setFilter(const SpendingFilter()),
                )
              else ...[
                CmSegmented<SpendingTab>(
                  segments: [
                    for (final tab in SpendingTab.values)
                      FilterOption(value: tab, label: tab.label),
                  ],
                  value: s.tab,
                  onChanged: ctrl.setTab,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilterChips<SpendingMetric>(
                    options: [
                      for (final m in SpendingMetric.values)
                        FilterOption(value: m, label: m.label),
                    ],
                    selected: {s.metric},
                    allowEmpty: false,
                    onChanged: (set) {
                      final m = set.firstOrNull;
                      if (m != null) ctrl.setMetric(m);
                    },
                  ),
                ),
                _TabBody(
                  state: s,
                  report: r,
                  onDrill: (b) => _drill(context, ctrl, s, b),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  static Future<void> _pickCustom(
    BuildContext context,
    SpendingController ctrl,
    SpendingRange current,
  ) async {
    final today = TrTime.wall(TrTime.now());
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(today.year - 6),
      lastDate: DateTime(today.year, today.month, today.day),
      initialDateRange: DateTimeRange(
        start: TrTime.wall(current.from),
        end: TrTime.wall(current.to),
      ),
      helpText: 'Rapor aralığı (en çok 36 ay)',
      saveText: 'Uygula',
    );
    if (picked == null) return;
    ctrl.setCustomRange(
      SpendingRange(
        from: TrTime.fromWall(
          picked.start.year,
          picked.start.month,
          picked.start.day,
        ),
        to: TrTime.fromWall(picked.end.year, picked.end.month, picked.end.day),
      ),
    );
  }

  static Future<void> _drill(
    BuildContext context,
    SpendingController ctrl,
    SpendingState s,
    SpendingBucket b,
  ) async {
    final (what, filter) = switch (s.tab) {
      SpendingTab.product => (
        'ürüne',
        SpendingFilter(
          productId: b.id,
          productName: b.name,
          deliveryPointId: s.filter.deliveryPointId,
          deliveryPointName: s.filter.deliveryPointName,
          stationId: s.filter.stationId,
          stationName: s.filter.stationName,
        ),
      ),
      SpendingTab.point => (
        'teslimat noktasına',
        SpendingFilter(
          deliveryPointId: b.id,
          deliveryPointName: b.name,
          productId: s.filter.productId,
          productName: s.filter.productName,
          stationId: s.filter.stationId,
          stationName: s.filter.stationName,
        ),
      ),
      SpendingTab.station => (
        'bayiye',
        SpendingFilter(
          stationId: b.id,
          stationName: b.name,
          productId: s.filter.productId,
          productName: s.filter.productName,
          deliveryPointId: s.filter.deliveryPointId,
          deliveryPointName: s.filter.deliveryPointName,
        ),
      ),
      SpendingTab.month => ('', s.filter),
    };
    final apply = await showAppSheet<bool>(
      context: context,
      title: b.name,
      subtitle: b.extra,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FactRow(label: 'Tutar', value: Fmt.money(b.amount)),
          FactRow(label: 'Litre', value: Fmt.liters(b.liters)),
          FactRow(
            label: 'Ortalama birim fiyat',
            value: Fmt.unitPrice(b.avgUnitPrice),
          ),
          FactRow(label: 'Sipariş', value: '${b.orderCount}'),
          FactRow(label: 'Tutar payı', value: Fmt.percent(b.amountShare)),
          const SizedBox(height: 16),
          AknButton(
            label: 'Bu $what göre süz',
            icon: Icons.filter_alt_rounded,
            expand: true,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (apply == true) ctrl.setFilter(filter);
  }
}

class _ActiveFilters extends ConsumerWidget {
  const _ActiveFilters({required this.filter});

  final SpendingFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(spendingControllerProvider.notifier);
    final f = filter;
    final chips = <(String, SpendingFilter)>[
      if (f.productId != null)
        (
          'Ürün: ${f.productName ?? '#${f.productId}'}',
          SpendingFilter(
            deliveryPointId: f.deliveryPointId,
            deliveryPointName: f.deliveryPointName,
            stationId: f.stationId,
            stationName: f.stationName,
          ),
        ),
      if (f.deliveryPointId != null)
        (
          'Nokta: ${f.deliveryPointName ?? '#${f.deliveryPointId}'}',
          SpendingFilter(
            productId: f.productId,
            productName: f.productName,
            stationId: f.stationId,
            stationName: f.stationName,
          ),
        ),
      if (f.stationId != null)
        (
          'Bayi: ${f.stationName ?? '#${f.stationId}'}',
          SpendingFilter(
            productId: f.productId,
            productName: f.productName,
            deliveryPointId: f.deliveryPointId,
            deliveryPointName: f.deliveryPointName,
          ),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Wrap(
        spacing: 8,
        children: [
          for (final (label, next) in chips)
            InputChip(
              label: Text(label),
              onDeleted: () => ctrl.setFilter(next),
              deleteButtonTooltipMessage: 'Kaldır',
            ),
        ],
      ),
    );
  }
}

class _Kpis extends StatelessWidget {
  const _Kpis({required this.report});

  final SpendingReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        children: [
          KpiRow(
            children: [
              KpiTile(
                label: 'Toplam tutar',
                value: r.totalAmount,
                format: Fmt.moneyCompact,
                icon: Icons.payments_rounded,
                tone: AknTone.brand,
                semanticLabel: 'Toplam tutar ${Fmt.money(r.totalAmount)}',
              ),
              KpiTile(
                label: 'Toplam litre',
                value: r.totalLiters,
                format: Fmt.liters,
                icon: Icons.local_gas_station_rounded,
                tone: AknTone.info,
              ),
            ],
          ),
          const SizedBox(height: 12),
          KpiRow(
            children: [
              KpiTile(
                label: 'Ortalama ₺/L',
                value: r.avgUnitPrice,
                format: Fmt.unitPrice,
                icon: Icons.speed_rounded,
                tone: AknTone.neutral,
              ),
              KpiTile(
                label: 'Sipariş',
                value: r.totalOrders,
                icon: Icons.receipt_long_rounded,
                tone: AknTone.ok,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TabBody extends StatelessWidget {
  const _TabBody({
    required this.state,
    required this.report,
    required this.onDrill,
  });

  final SpendingState state;
  final SpendingReport report;
  final void Function(SpendingBucket b) onDrill;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final r = report;
    final metric = state.metric;
    switch (state.tab) {
      case SpendingTab.month:
        final newest = r.months.reversed.where((m) => m.orderCount > 0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CmSection(
              title: metric == SpendingMetric.amount
                  ? 'Aylık tutar'
                  : 'Aylık litre',
              subtitle: '${r.months.length} ay',
              child: MonthBarChart(months: r.months, metric: metric),
            ),
            CmSection(
              title: 'Aylar',
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Column(
                children: [
                  for (final m in newest)
                    FactRow(
                      label: m.label,
                      value: '${Fmt.money(m.amount)} · ${Fmt.liters(m.liters)}',
                    ),
                  if (newest.isEmpty)
                    Text('Siparişli ay yok.', style: t.bodySmall),
                ],
              ),
            ),
          ],
        );
      case SpendingTab.product:
      case SpendingTab.point:
      case SpendingTab.station:
        final list = switch (state.tab) {
          SpendingTab.product => r.byProduct,
          SpendingTab.point => r.byDeliveryPoint,
          _ => r.byStation,
        };
        final title = switch (state.tab) {
          SpendingTab.product => 'Ürünlere göre',
          SpendingTab.point => 'Teslimat noktalarına göre',
          _ => 'Bayilere göre',
        };
        return CmSection(
          title: title,
          subtitle: list.length > 6
              ? 'İlk 5 kalem ve diğerleri · ${list.length} kalem'
              : '${list.length} kalem',
          child: list.isEmpty
              ? Text('Kayıt yok.', style: t.bodySmall)
              : BucketBars(buckets: list, metric: metric, onTap: onDrill),
        );
    }
  }
}

class _SpendingSkeleton extends StatelessWidget {
  const _SpendingSkeleton();

  @override
  Widget build(BuildContext context) => const Shimmer(
    semanticLabel: 'Harcamalar yükleniyor',
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: SkeletonBox(height: 84, radius: 12)),
              SizedBox(width: 12),
              Expanded(child: SkeletonBox(height: 84, radius: 12)),
            ],
          ),
          SizedBox(height: 16),
          SkeletonBox(height: 220, radius: 12),
        ],
      ),
    ),
  );
}

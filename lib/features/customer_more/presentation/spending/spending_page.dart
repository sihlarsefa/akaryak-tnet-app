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
                        ? PhosphorIconsRegular.calendarDots
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
                margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                tone: AknTone.warn,
                message:
                    'Rapor en fazla ${SpendingRange.maxMonths} ay kapsar; başlangıç tarihi ${Fmt.date(s.range.from)} olarak kısaltıldı.',
              ),
            if (r == null && s.loading)
              const _SpendingSkeleton()
            else if (r == null && s.error != null)
              CmFailureView(failure: s.error!, onRetry: ctrl.load)
            else if (r != null) ...[
              _Kpis(report: r, range: s.range),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                child: Text(
                  CmCopy.spendingCaption,
                  style: context.aknText.bodySmall.copyWith(
                    color: context.akn.dim,
                  ),
                ),
              ),
              if (r.truncated)
                const AknBanner(
                  margin: EdgeInsets.fromLTRB(20, 4, 20, 8),
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
                const SizedBox(height: 8),
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Wrap(
        spacing: 8,
        children: [
          for (final (label, next) in chips)
            InputChip(
              label: Text(label),
              labelStyle: context.aknText.label.copyWith(
                color: context.akn.brandInk,
              ),
              backgroundColor: context.akn.brandSoft,
              deleteIconColor: context.akn.brandInk,
              side: BorderSide.none,
              shape: const StadiumBorder(),
              onDeleted: () {
                AknHaptics.selection();
                ctrl.setFilter(next);
              },
              deleteButtonTooltipMessage: 'Kaldır',
            ),
        ],
      ),
    );
  }
}

/// Raporun kahraman kartı (tasarım v3 §4 AknPlate): seçilen aralığın toplam harcaması (rakamlar
/// yuvarlanarak gelir), kural ve okumalar (litre, ortalama ₺/L, sipariş). Ekranın tek kahraman
/// kartı.
class _Kpis extends StatelessWidget {
  const _Kpis({required this.report, required this.range});

  final SpendingReport report;
  final SpendingRange range;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final avg = r.avgUnitPrice;
    final spoken = [
      'Toplam harcama ${Fmt.money(r.totalAmount)}',
      '${Fmt.date(range.from)} ile ${Fmt.date(range.to)} arası',
      'toplam litre ${Fmt.liters(r.totalLiters)}',
      if (avg != null) 'ortalama ${Fmt.unitPrice(avg)}',
      '${r.totalOrders} sipariş',
    ].join(', ');
    return CmPlate(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      semanticLabel: spoken,
      head: PlateHead(
        icon: PhosphorIconsRegular.money,
        title: 'Toplam harcama',
        period: '${Fmt.dayMonth(range.from)} – ${Fmt.dayMonth(range.to)}',
      ),
      figure: PlateFigure(value: Fmt.number(r.totalAmount.round()), unit: '₺'),
      readouts: [
        PlateReadout(
          label: 'Toplam litre',
          value: Fmt.number(r.totalLiters, maxFraction: 0),
          unit: 'L',
        ),
        PlateReadout(
          label: 'Ortalama',
          value: avg == null
              ? Fmt.dash
              : Fmt.number(avg, minFraction: 2, maxFraction: 2),
          unit: avg == null ? null : '₺/L',
        ),
        PlateReadout(label: 'Sipariş', value: Fmt.integer(r.totalOrders)),
      ],
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
    // Sekme değişince yeni sekmenin kartları birbiri ardına yükselerek gelir (v3 §5).
    return CmRiseScope(
      key: ValueKey(state.tab),
      child: _body(context, t, r, metric),
    );
  }

  Widget _body(
    BuildContext context,
    AknTextStyles t,
    SpendingReport r,
    SpendingMetric metric,
  ) {
    switch (state.tab) {
      case SpendingTab.month:
        final newest = r.months.reversed.where((m) => m.orderCount > 0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CmRise(
              index: 0,
              child: CmSection(
                title: metric == SpendingMetric.amount
                    ? 'Aylık tutar'
                    : 'Aylık litre',
                subtitle: '${r.months.length} ay',
                child: MonthBarChart(months: r.months, metric: metric),
              ),
            ),
            CmRise(
              index: 1,
              child: CmSection(
                title: 'Aylar',
                bleed: true,
                child: newest.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                        child: Text(
                          'Siparişli ay yok.',
                          style: t.bodySmall.copyWith(color: context.akn.dim),
                        ),
                      )
                    : AknLedger(
                        children: [
                          for (final m in newest)
                            AknListTile(
                              padding: CmCard.rowPadding,
                              titleStyle: cmRowTitle(context),
                              title: m.label,
                              subtitle: '${m.orderCount} sipariş',
                              amount: Fmt.money(m.amount),
                              amountMeta: Fmt.liters(m.liters),
                              semanticLabel:
                                  '${m.label}, ${Fmt.money(m.amount)}, ${Fmt.liters(m.liters)}, ${m.orderCount} sipariş',
                            ),
                        ],
                      ),
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
        return CmRise(
          index: 0,
          child: CmSection(
            title: title,
            subtitle: list.length > 6
                ? 'İlk 5 kalem ve diğerleri, ${list.length} kalem'
                : '${list.length} kalem',
            child: list.isEmpty
                ? Text(
                    'Kayıt yok.',
                    style: t.bodySmall.copyWith(color: context.akn.dim),
                  )
                : BucketBars(buckets: list, metric: metric, onTap: onDrill),
          ),
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
      padding: EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        children: [
          SkeletonBox(height: 196, radius: AknRadius.plateRadius),
          SizedBox(height: 24),
          SkeletonBox(height: 220, radius: 20),
        ],
      ),
    ),
  );
}

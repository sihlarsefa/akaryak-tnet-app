import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/env/app_config_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/network/failure_copy.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/routing/route_access.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../customer_orders/api.dart' show Loadable;
import '../application/stats_providers.dart';
import '../application/stats_scope.dart';
import '../copy.dart';
import '../data/stats_models.dart';
import 'charts/bar_chart.dart';
import 'charts/line_chart.dart';
import 'charts/mix_chart.dart';
import 'deck/deck_cards.dart' show usageColor;
import 'stats_format.dart';
import 'widgets/stats_atoms.dart';
import 'widgets/stats_palette.dart';

/// Aylık grafiğin ölçüsü.
enum _Metric { amount, liters, orders }

/// İstatistikler (`/stats`, spec R1 §3.3): üstte sabit dönem seçici (Bu ay · Geçen ay · Son 3 ay ·
/// Bu yıl), aşağı çekerek yenileme, ilk yüklemede iskelet, dönem başına son sonuç önbellekte
/// (çevrimdışıyken "Son güncelleme"), hata ekranı. Bölümler: KPI'lar → aylık grafik (Tutar / Litre /
/// Sipariş) → ürün dağılımı halkası → (bayi) huni, sevkiyat, tahsilat, en çok alan cariler, ekip, limit
/// riski → (müşteri) birim fiyat çizgisi, bayiler, teslimat noktaları, sipariş durumu, limitler ve
/// "Detaylı harcama raporu".
class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key, this.initialPeriod = StatsPeriod.month});

  final StatsPeriod initialPeriod;

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  late StatsPeriod _period = widget.initialPeriod;
  _Metric _metric = _Metric.amount;
  int? _month;

  void _setPeriod(StatsPeriod p) {
    if (p == _period) return;
    setState(() {
      _period = p;
      _month = null;
    });
  }

  Future<void> _refresh() async {
    final scope = ref.read(statsScopeProvider);
    if (scope.isBayi) {
      await ref.read(bayiStatsProvider(_period).notifier).refresh();
    } else if (scope == StatsScope.customer) {
      await ref.read(customerStatsProvider(_period).notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(statsScopeProvider);
    String? subtitle;
    var refreshing = false;
    Widget body;
    String state;
    if (scope == StatsScope.none) {
      state = 'none';
      body = _centered(
        _StatsFailure(failure: const ForbiddenFailure(), onRetry: _refresh),
      );
    } else if (scope.isBayi) {
      final s = ref.watch(bayiStatsProvider(_period));
      final d = s.data;
      subtitle = d?.stationTitle;
      refreshing = s.loading && d != null;
      (state, body) = _bodyFor(
        s,
        (d) => _BayiSections(
          data: d,
          own: d.isOwn || scope == StatsScope.own,
          metric: _metric,
          onMetric: (m) => setState(() => _metric = m),
          month: _month,
          onMonth: (i) => setState(() => _month = i),
        ),
      );
    } else {
      final s = ref.watch(customerStatsProvider(_period));
      final d = s.data;
      subtitle = d?.customerTitle;
      refreshing = s.loading && d != null;
      (state, body) = _bodyFor(
        s,
        (d) => _CustomerSections(
          data: d,
          metric: _metric,
          onMetric: (m) => setState(() => _metric = m),
          month: _month,
          onMonth: (i) => setState(() => _month = i),
        ),
      );
    }

    return AppScaffold(
      title: StatsCopy.pageTitle,
      subtitle: subtitle,
      refreshing: refreshing,
      body: Column(
        children: [
          if (scope != StatsScope.none)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Semantics(
                container: true,
                label: StatsCopy.periodSemantics,
                child: AknSegmented<StatsPeriod>(
                  segments: [
                    for (final p in StatsPeriod.values)
                      FilterOption(value: p, label: p.label),
                  ],
                  value: _period,
                  onChanged: _setPeriod,
                ),
              ),
            ),
          Expanded(
            child: FadeThroughSwitcher(
              child: KeyedSubtree(
                key: ValueKey('${_period.key}-$state'),
                child: body,
              ),
            ),
          ),
        ],
      ),
    );
  }

  (String, Widget) _bodyFor<T>(
    Loadable<T> s,
    Widget Function(T data) sections,
  ) {
    final d = s.data;
    if (d == null) {
      final error = s.error;
      if (error != null && !s.loading) {
        return (
          'error',
          _centered(_StatsFailure(failure: error, onRetry: _refresh)),
        );
      }
      return ('loading', const _PageSkeleton());
    }
    return (
      'data',
      PullToRefresh(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            _UpdatedNote(
              updatedAt: s.updatedAt,
              fromCache: s.fromCache,
              error: s.error,
            ),
            StaggerScope(child: sections(d)),
          ],
        ),
      ),
    );
  }

  Widget _centered(Widget child) => LayoutBuilder(
    builder: (context, cons) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: cons.maxHeight),
        child: Center(child: child),
      ),
    ),
  );
}

// ============================================================== bayi

class _BayiSections extends ConsumerWidget {
  const _BayiSections({
    required this.data,
    required this.own,
    required this.metric,
    required this.onMetric,
    required this.month,
    required this.onMonth,
  });

  final BayiStats data;
  final bool own;
  final _Metric metric;
  final ValueChanged<_Metric> onMetric;
  final int? month;
  final ValueChanged<int> onMonth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.akn;
    final d = data;
    final sales = d.sales;
    final compare = d.period.key.compareShort;
    final nav = _Nav(ref);
    final children = <Widget>[
      _PeriodCaption(period: d.period),
      if (sales != null) ...[
        _KpiGrid(
          tiles: [
            KpiTile(
              label: own ? StatsCopy.cardSalesOwn : StatsCopy.kpiSales,
              value: sales.amount,
              format: StatsFmt.money,
              icon: Icons.payments_rounded,
              tone: AknTone.brand,
              trend: StatsFmt.change(sales.amount, sales.prevAmount),
              trendLabel: compare,
            ),
            KpiTile(
              label: StatsCopy.kpiLiters,
              value: sales.liters,
              format: StatsFmt.liters,
              icon: Icons.local_gas_station_rounded,
              tone: AknTone.info,
              trend: StatsFmt.change(sales.liters, sales.prevLiters),
              trendLabel: compare,
            ),
            KpiTile(
              label: StatsCopy.kpiOrders,
              value: sales.orders,
              icon: Icons.receipt_long_rounded,
              tone: AknTone.brand,
              trend: StatsFmt.change(sales.orders, sales.prevOrders),
              trendLabel: compare,
            ),
            if (sales.activeCustomers != null)
              KpiTile(
                label: StatsCopy.kpiActiveCustomers,
                value: sales.activeCustomers,
                icon: Icons.groups_rounded,
                tone: AknTone.ok,
                caption: (sales.newCustomers ?? 0) > 0
                    ? '+${sales.newCustomers} yeni cari'
                    : null,
              )
            else
              KpiTile(
                label: StatsCopy.kpiUnitPrice,
                value: sales.unitPrice,
                format: StatsFmt.unitPrice,
                icon: Icons.sell_rounded,
                tone: AknTone.ok,
                trend: StatsFmt.change(sales.unitPrice, sales.prevUnitPrice),
                trendLabel: compare,
              ),
          ],
        ),
      ],
      if (d.months.isNotEmpty)
        _MonthlySection(
          months: d.months,
          metric: metric,
          onMetric: onMetric,
          selected: month,
          onSelected: onMonth,
          noun: 'satış',
        ),
      if (d.products.isNotEmpty)
        _MixSection(products: d.products, subtitle: StatsCopy.mixSubtitle),
      if (d.funnel != null)
        _FunnelSection(
          funnel: d.funnel!,
          onOpen: own ? null : nav.maybe(AppRoutes.quoteDesk),
        ),
      if (d.deliveries != null && !own)
        _DeliveriesSection(
          deliveries: d.deliveries!,
          onOpen: nav.maybe(AppRoutes.dispatch),
        ),
      if (d.collections != null && !own)
        _CollectionsSection(
          collections: d.collections!,
          onOpen: nav.maybe(AppRoutes.payments),
        ),
      if (d.topCustomers.isNotEmpty)
        _Section(
          title: own
              ? StatsCopy.topCustomersOwnTitle
              : StatsCopy.topCustomersTitle,
          subtitle: 'Tutara göre · ilk ${math.min(10, d.topCustomers.length)}',
          icon: Icons.workspace_premium_rounded,
          tone: AknTone.brand,
          child: Column(
            children: [
              for (var i = 0; i < math.min(10, d.topCustomers.length); i++)
                _TapRow(
                  onTap: nav.maybe(
                    AppRoutes.customer(d.topCustomers[i].customerId),
                  ),
                  child: ShareRow(
                    rank: i + 1,
                    title: d.topCustomers[i].title,
                    value: StatsFmt.money(d.topCustomers[i].amount),
                    trailingNote: StatsFmt.rate(d.topCustomers[i].share),
                    share: d.topCustomers[i].share,
                    color: c.logo,
                    index: i,
                    subtitle:
                        '${StatsFmt.liters(d.topCustomers[i].liters)} · '
                        '${StatsCopy.ordersCount(d.topCustomers[i].orders)}',
                  ),
                ),
            ],
          ),
        ),
      if (d.team.isNotEmpty)
        _TeamSection(
          team: d.team,
          own: own,
          onOpen: nav.maybe(AppRoutes.field),
        ),
      if (d.risk != null && d.risk!.nearLimitCount > 0 && !own)
        _Section(
          title: StatsCopy.riskTitle,
          subtitle:
              '${d.risk!.nearLimitCount} cari limitinin %80 ve üzerini kullanıyor',
          icon: Icons.speed_rounded,
          tone: AknTone.danger,
          child: Column(
            children: [
              for (final r in [
                ...d.risk!.nearLimit,
              ]..sort((a, b) => b.usageRate.compareTo(a.usageRate)))
                _TapRow(
                  onTap: nav.maybe(AppRoutes.customer(r.customerId)),
                  child: ShareRow(
                    title: r.title,
                    value: StatsFmt.rate(r.usageRate),
                    share: r.usageRate,
                    color: usageColor(c, r.usageRate),
                    semanticsLabel:
                        '${r.title}, limit kullanımı ${StatsFmt.rate(r.usageRate)}',
                  ),
                ),
            ],
          ),
        ),
      if (d.sales != null && d.sales!.isEmpty && d.products.isEmpty)
        const _EmptyPeriod(customer: false),
      _Footer(failed: d.failedSections, generatedAt: d.generatedAt),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: staggered(children),
    );
  }
}

// ============================================================== müşteri

class _CustomerSections extends ConsumerWidget {
  const _CustomerSections({
    required this.data,
    required this.metric,
    required this.onMetric,
    required this.month,
    required this.onMonth,
  });

  final CustomerStats data;
  final _Metric metric;
  final ValueChanged<_Metric> onMetric;
  final int? month;
  final ValueChanged<int> onMonth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.akn;
    final d = data;
    final spend = d.spending;
    final compare = d.period.key.compareShort;
    final nav = _Nav(ref);
    final priced = d.months.where((m) => m.unitPrice != null).length;
    final children = <Widget>[
      _PeriodCaption(period: d.period),
      if (spend != null)
        _KpiGrid(
          tiles: [
            KpiTile(
              label: StatsCopy.kpiSpending,
              value: spend.amount,
              format: StatsFmt.money,
              icon: Icons.payments_rounded,
              tone: AknTone.brand,
              trend: StatsFmt.change(spend.amount, spend.prevAmount),
              trendLabel: compare,
            ),
            KpiTile(
              label: StatsCopy.kpiLitersCustomer,
              value: spend.liters,
              format: StatsFmt.liters,
              icon: Icons.local_gas_station_rounded,
              tone: AknTone.info,
              trend: StatsFmt.change(spend.liters, spend.prevLiters),
              trendLabel: compare,
            ),
            KpiTile(
              label: StatsCopy.kpiOrders,
              value: spend.orders,
              icon: Icons.receipt_long_rounded,
              tone: AknTone.brand,
              trend: StatsFmt.change(spend.orders, spend.prevOrders),
              trendLabel: compare,
            ),
            KpiTile(
              label: StatsCopy.kpiUnitPrice,
              value: spend.unitPrice,
              format: StatsFmt.unitPrice,
              icon: Icons.sell_rounded,
              tone: AknTone.ok,
              trend: StatsFmt.change(spend.unitPrice, spend.prevUnitPrice),
              trendLabel: compare,
              positiveIsGood: false,
            ),
          ],
        ),
      if (d.months.isNotEmpty)
        _MonthlySection(
          months: d.months,
          metric: metric,
          onMetric: onMetric,
          selected: month,
          onSelected: onMonth,
          noun: 'harcama',
        ),
      if (d.products.isNotEmpty)
        _MixSection(
          products: d.products,
          subtitle: StatsCopy.mixSubtitleCustomer,
        ),
      if (priced >= 2)
        _Section(
          title: StatsCopy.unitPriceTitle,
          subtitle: 'Aylara göre ₺/L · düşüş sizin için iyidir',
          icon: Icons.sell_rounded,
          tone: AknTone.ok,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (spend?.unitPrice != null) ...[
                Text(
                  StatsFmt.unitPrice(spend!.unitPrice),
                  style: context.aknText.amountLarge.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                DeltaChip(
                  current: spend.unitPrice,
                  previous: spend.prevUnitPrice,
                  compareLabel: compare,
                  lowerIsBetter: true,
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                height: 170,
                child: StatsLineChart(
                  points: [
                    for (final m in d.months)
                      LinePoint(label: m.shortLabel, value: m.unitPrice),
                  ],
                  color: StatsHue.of(c, AknTone.ok).mark,
                  valueLabel: (v) =>
                      StatsFmt.unitPrice(v).replaceAll(' ₺/L', ''),
                  semanticsLabel: [
                    'Aylara göre ortalama birim fiyat',
                    for (final m in d.months)
                      if (m.unitPrice != null)
                        '${m.longLabel} ${StatsFmt.unitPrice(m.unitPrice)}',
                  ].join(', '),
                ),
              ),
            ],
          ),
        ),
      if (d.stations.isNotEmpty)
        _Section(
          title: StatsCopy.stationsTitle,
          subtitle: 'Tutara göre',
          icon: Icons.storefront_rounded,
          tone: AknTone.brand,
          child: Column(
            children: [
              for (var i = 0; i < d.stations.length; i++)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                  child: ShareRow(
                    title: d.stations[i].title,
                    value: StatsFmt.money(d.stations[i].amount),
                    trailingNote: StatsFmt.rate(d.stations[i].share),
                    share: d.stations[i].share,
                    color: c.logo,
                    index: i,
                    subtitle: StatsFmt.liters(d.stations[i].liters),
                  ),
                ),
            ],
          ),
        ),
      if (d.deliveryPoints.isNotEmpty)
        _Section(
          title: StatsCopy.pointsTitle,
          subtitle: 'Litreye göre',
          icon: Icons.place_rounded,
          tone: AknTone.info,
          child: Column(
            children: [
              for (final (i, p) in ([
                ...d.deliveryPoints,
              ]..sort((a, b) => b.liters.compareTo(a.liters))).indexed)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                  child: ShareRow(
                    title: p.name,
                    value: StatsFmt.liters(p.liters),
                    trailingNote: StatsFmt.rate(p.share),
                    share: p.share,
                    color: StatsHue.of(c, AknTone.info).mark,
                    index: i,
                    subtitle: [
                      if (p.city != null) p.city!,
                      StatsFmt.money(p.amount),
                    ].join(' · '),
                  ),
                ),
            ],
          ),
        ),
      if (d.orders != null) _OrderStatusSection(orders: d.orders!, nav: nav),
      if (d.limits.isNotEmpty)
        _Section(
          title: StatsCopy.limitsTitle,
          subtitle: 'Bayi başına kullanım',
          icon: Icons.speed_rounded,
          tone: AknTone.warn,
          onOpen: nav.maybe(AppRoutes.limits),
          child: Column(
            children: [
              for (var i = 0; i < d.limits.length; i++)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 14),
                  child: _LimitRow(limit: d.limits[i]),
                ),
            ],
          ),
        ),
      if (nav.can(AppRoutes.spending))
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: AknCard(
            padding: EdgeInsets.zero,
            radius: 16,
            onTap: () => context.push(AppRoutes.spending),
            child: const AknListTile(
              leadingIcon: Icons.insights_rounded,
              leadingTone: AknTone.brand,
              title: StatsCopy.spendingReport,
              subtitle: StatsCopy.spendingReportHint,
              showChevron: true,
            ),
          ),
        ),
      if (spend != null && spend.isEmpty && d.products.isEmpty)
        const _EmptyPeriod(customer: true),
      _Footer(failed: d.failedSections, generatedAt: d.generatedAt),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: staggered(children),
    );
  }
}

// ============================================================== bölümler

/// Rotaya izin varsa gezinme (izin yoksa satır dokunulmaz).
class _Nav {
  _Nav(this.ref);

  final WidgetRef ref;

  bool can(String route) => RouteAccess.isAllowed(
    route,
    ref.read(accessPolicyProvider),
    ref.read(appConfigProvider).features,
  );

  /// İzin varsa açan geri çağırım, yoksa null.
  VoidCallback? maybe(String route) {
    if (!can(route)) return null;
    final context = ref.context;
    return () => unawaited(context.push(route));
  }
}

/// "1–21 Ekim 2026 · karşılaştırma: 1–21 Eylül 2026".
class _PeriodCaption extends StatelessWidget {
  const _PeriodCaption({required this.period});

  final StatsPeriodInfo period;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final range = StatsFmt.range(period.from, period.to);
    final compare = StatsFmt.range(period.compareFrom, period.compareTo);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            period.from == null ? period.title : '${period.title} · $range',
            style: t.label.copyWith(color: c.ink, fontWeight: FontWeight.w700),
          ),
          if (period.compareFrom != null)
            Text(
              '${period.compareLabel ?? 'Karşılaştırma'}: $compare',
              style: t.caption.copyWith(color: c.dim),
            ),
        ],
      ),
    );
  }
}

/// İki sütunlu KPI ızgarası (eşit yükseklik; büyük yazıda tek sütun).
class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: [
          for (var i = 0; i < tiles.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 12),
            KpiRow(children: tiles.sublist(i, math.min(i + 2, tiles.length))),
          ],
        ],
      ),
    );
  }
}

/// Bölüm kartı: ikon kutusu · başlık · alt başlık (· "Aç") + içerik.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.tone = AknTone.brand,
    this.onOpen,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final AknTone tone;
  final VoidCallback? onOpen;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final hue = StatsHue.of(c, tone);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: AknCard(
        radius: 20,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: hue.glyph.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, size: 19, color: hue.glyph),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: t.bodyStrong.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: c.ink,
                          ),
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          style: t.caption.copyWith(color: c.dim),
                        ),
                    ],
                  ),
                ),
                if (onOpen != null)
                  AknIconButton(
                    icon: Icons.chevron_right_rounded,
                    semanticLabel: '$title ekranını aç',
                    color: c.dim,
                    onPressed: onOpen,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

/// Dokunulabilir satır (48 dp en az yükseklik); dokunulamıyorsa yalnızca dolgu.
class _TapRow extends StatelessWidget {
  const _TapRow({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final padded = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AknSpace.minTap),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: child,
      ),
    );
    if (onTap == null) return padded;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: padded,
    );
  }
}

class _MonthlySection extends StatelessWidget {
  const _MonthlySection({
    required this.months,
    required this.metric,
    required this.onMetric,
    required this.selected,
    required this.onSelected,
    required this.noun,
  });

  final List<StatsMonth> months;
  final _Metric metric;
  final ValueChanged<_Metric> onMetric;
  final int? selected;
  final ValueChanged<int> onSelected;
  final String noun;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final (Color color, double Function(StatsMonth) value) = switch (metric) {
      _Metric.amount => (c.logo, (StatsMonth m) => m.amount),
      _Metric.liters => (c.info.fg, (StatsMonth m) => m.liters),
      _Metric.orders => (c.ok.fg, (StatsMonth m) => m.orders.toDouble()),
    };
    String short(double v) => switch (metric) {
      _Metric.amount => StatsFmt.moneyCompact(v),
      _Metric.liters => StatsFmt.litersCompact(v),
      _Metric.orders => StatsFmt.count(v),
    };
    String spoken(double v) => switch (metric) {
      _Metric.amount => StatsFmt.moneySpoken(v),
      _Metric.liters => StatsFmt.litersSpoken(v),
      _Metric.orders => '${StatsFmt.count(v)} sipariş',
    };
    final sel = (selected ?? months.length - 1).clamp(0, months.length - 1);
    final m = months[sel];
    return _Section(
      title: StatsCopy.monthlyTitle,
      subtitle: months.length > 6 ? 'Son 12 ay' : 'Son 6 ay',
      icon: Icons.bar_chart_rounded,
      tone: AknTone.brand,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AknSegmented<_Metric>(
            margin: EdgeInsets.zero,
            segments: const [
              FilterOption(
                value: _Metric.amount,
                label: StatsCopy.metricAmount,
              ),
              FilterOption(
                value: _Metric.liters,
                label: StatsCopy.metricLiters,
              ),
              FilterOption(
                value: _Metric.orders,
                label: StatsCopy.metricOrders,
              ),
            ],
            value: metric,
            onChanged: onMetric,
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 210,
            child: StatsBarChart(
              key: ValueKey('monthly-${metric.name}-${months.length}'),
              bars: [
                for (final x in months)
                  ChartBar(
                    label: x.shortLabel,
                    longLabel: x.longLabel,
                    value: value(x),
                  ),
              ],
              color: color,
              axis: true,
              valueLabel: short,
              axisLabel: StatsFmt.compactNumber,
              spoken: (b) => '${b.longLabel} $noun ${spoken(b.value)}',
              emptyHint: StatsCopy.emptyPeriod,
              maxBarWidth: months.length > 6 ? 16 : 24,
              onSelected: onSelected,
            ),
          ),
          const SizedBox(height: 10),
          Semantics(
            liveRegion: true,
            child: Text(
              '${m.longLabel} · ${StatsFmt.money(m.amount)} · '
              '${StatsFmt.liters(m.liters)} · ${StatsCopy.ordersCount(m.orders)}',
              style: t.caption.copyWith(color: c.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _MixSection extends StatelessWidget {
  const _MixSection({required this.products, required this.subtitle});

  final List<StatsProduct> products;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final slices = productSlices(c, products, otherLabel: StatsCopy.other);
    if (slices.isEmpty) return const SizedBox.shrink();
    final total = products.fold<double>(0, (s, p) => s + p.liters);
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
    return _Section(
      title: StatsCopy.mixTitle,
      subtitle: subtitle,
      icon: Icons.donut_large_rounded,
      tone: AknTone.info,
      child: LayoutBuilder(
        builder: (context, cons) {
          final donut = StatsDonut(
            slices: slices,
            centerValue: StatsFmt.litersCompact(total),
            centerLabel: 'toplam',
          );
          final legend = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < slices.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                MixLegendRow(
                  slice: slices[i],
                  dense: false,
                  detail: StatsFmt.litersCompact(slices[i].liters),
                ),
              ],
            ],
          );
          if (cons.maxWidth < 330 || large) {
            return Column(
              children: [
                Center(child: donut),
                const SizedBox(height: 16),
                legend,
              ],
            );
          }
          return Row(
            children: [
              donut,
              const SizedBox(width: 20),
              Expanded(child: legend),
            ],
          );
        },
      ),
    );
  }
}

class _FunnelSection extends StatelessWidget {
  const _FunnelSection({required this.funnel, this.onOpen});

  final StatsFunnel funnel;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final mark = c.logo;
    final conv = funnel.conversion;
    return _Section(
      title: StatsCopy.funnelTitle,
      subtitle: conv == null
          ? 'Talepten onaya'
          : 'Talepten onaya · ${StatsFmt.rate(conv, decimals: 1)} dönüşüm',
      icon: Icons.filter_alt_rounded,
      tone: AknTone.brand,
      onOpen: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FunnelBars(
            barHeight: 12,
            rows: [
              FunnelRow('Talep', funnel.requests, mark.withValues(alpha: 0.5)),
              FunnelRow(
                'Teklif verilen',
                funnel.quoted,
                mark.withValues(alpha: 0.75),
              ),
              FunnelRow('Onaylanan', funnel.accepted, mark),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatsTag(
                label: '${StatsCopy.rejected} ${funnel.rejected}',
                tone: funnel.rejected > 0 ? AknTone.danger : AknTone.neutral,
                icon: Icons.block_rounded,
              ),
              StatsTag(
                label: '${StatsCopy.expired} ${funnel.expired}',
                tone: funnel.expired > 0 ? AknTone.warn : AknTone.neutral,
                icon: Icons.timer_off_rounded,
              ),
              if (funnel.avgFirstQuoteMinutes != null)
                StatsTag(
                  label: StatsCopy.firstQuote(
                    StatsFmt.minutes(funnel.avgFirstQuoteMinutes),
                  ),
                  tone: AknTone.info,
                  icon: Icons.bolt_rounded,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tonlu bilgi satırı (sayfa): ikon · etiket · değer · not.
class _Fact extends StatelessWidget {
  const _Fact({
    required this.icon,
    required this.label,
    required this.value,
    this.note,
    this.tone = AknTone.neutral,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? note;
  final AknTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final tc = c.tone(tone);
    return Semantics(
      label: '$label: $value${note == null ? '' : ', $note'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: StatsLineRow(
          gap: 10,
          leading: Padding(
            padding: const EdgeInsetsDirectional.only(end: 10),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: tc.bg,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, size: 17, color: tc.fg),
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: t.label.copyWith(color: c.text)),
              if (note != null)
                Text(note!, style: t.caption.copyWith(color: c.dim)),
            ],
          ),
          trailing: Text(
            value,
            style: t.bodyStrong.copyWith(
              fontWeight: FontWeight.w800,
              color: c.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

class _DeliveriesSection extends StatelessWidget {
  const _DeliveriesSection({required this.deliveries, this.onOpen});

  final StatsDeliveries deliveries;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final d = deliveries;
    final rate = d.onTimeRate;
    final ring = MediaQuery.textScalerOf(context).scale(92).clamp(92.0, 120.0);
    final tone = rate == null
        ? AknTone.neutral
        : rate >= 0.9
        ? AknTone.ok
        : rate >= 0.75
        ? AknTone.warn
        : AknTone.danger;
    return _Section(
      title: StatsCopy.deliveriesTitle,
      subtitle:
          '${d.delivered} teslimat · ${StatsFmt.liters(d.deliveredLiters)}',
      icon: Icons.local_shipping_rounded,
      tone: AknTone.info,
      onOpen: onOpen,
      child: Row(
        children: [
          ProgressRing(
            value: rate ?? 0,
            size: ring,
            strokeWidth: 9,
            color: rate == null ? c.line : c.tone(tone).fg,
            trackColor: c.lineSoft,
            animateFromZero: true,
            duration: AknMotion.emphasized,
            semanticLabel: 'Zamanında teslim',
            semanticValue: rate == null ? 'veri yok' : StatsFmt.rate(rate),
            // İçerik halkanın iç çemberine çizilen kareye sığar (büyük yazıda küçülür).
            child: Padding(
              padding: EdgeInsets.all((ring - (ring - 18) * 0.7071) / 2),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      rate == null ? StatsFmt.dash : StatsFmt.rate(rate),
                      style: t.headline.copyWith(
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      StatsCopy.onTime,
                      style: t.caption.copyWith(fontSize: 11, color: c.dim),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [
                _Fact(
                  icon: Icons.local_shipping_rounded,
                  label: StatsCopy.inTransit,
                  value: '${d.inTransit}',
                  tone: AknTone.brand,
                ),
                _Fact(
                  icon: Icons.event_rounded,
                  label: StatsCopy.planned,
                  value: '${d.planned}',
                  tone: AknTone.info,
                ),
                _Fact(
                  icon: Icons.report_problem_rounded,
                  label: StatsCopy.disputes,
                  value: '${d.disputes}',
                  tone: d.disputes > 0 ? AknTone.danger : AknTone.neutral,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionsSection extends StatelessWidget {
  const _CollectionsSection({required this.collections, this.onOpen});

  final StatsCollections collections;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final x = collections;
    return _Section(
      title: StatsCopy.collectionsTitle,
      subtitle: StatsCopy.paymentsCount(x.collectedCount),
      icon: Icons.account_balance_wallet_rounded,
      tone: AknTone.ok,
      onOpen: onOpen,
      child: Column(
        children: [
          _Fact(
            icon: Icons.check_rounded,
            label: 'Tahsil edilen',
            value: StatsFmt.money(x.collectedAmount),
            note: StatsCopy.paymentsCount(x.collectedCount),
            tone: AknTone.ok,
          ),
          _Fact(
            icon: Icons.error_outline_rounded,
            label: StatsCopy.overdue,
            value: StatsFmt.money(x.overdueAmount),
            note: StatsCopy.paymentsCount(x.overdueCount),
            tone: x.overdueCount > 0 ? AknTone.danger : AknTone.neutral,
          ),
          _Fact(
            icon: Icons.schedule_rounded,
            label: StatsCopy.dueSoon(x.dueSoonDays),
            value: StatsFmt.money(x.dueSoonAmount),
            note: StatsCopy.paymentsCount(x.dueSoonCount),
            tone: x.dueSoonCount > 0 ? AknTone.warn : AknTone.neutral,
          ),
        ],
      ),
    );
  }
}

class _TeamSection extends StatelessWidget {
  const _TeamSection({required this.team, required this.own, this.onOpen});

  final List<StatsTeamMember> team;
  final bool own;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final rows = [...team]
      ..sort((a, b) {
        final x = b.converted.compareTo(a.converted);
        return x != 0 ? x : b.forms.compareTo(a.forms);
      });
    final forms = team.fold<int>(0, (a, m) => a + m.forms);
    final converted = team.fold<int>(0, (a, m) => a + m.converted);
    return _Section(
      title: own ? StatsCopy.cardOwnForms : StatsCopy.teamTitle,
      subtitle: forms > 0
          ? '$forms form · ${StatsFmt.rate(converted / forms)} siparişe dönüştü'
          : 'Bu dönemde form yok',
      icon: Icons.groups_rounded,
      tone: AknTone.ok,
      onOpen: onOpen,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Semantics(
              label:
                  '${rows[i].name}: ${rows[i].forms} form, ${rows[i].converted} sipariş, '
                  '${StatsFmt.litersSpoken(rows[i].liters)}',
              excludeSemantics: true,
              child: Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
                child: StatsLineRow(
                  gap: 12,
                  trailingShare: 0.45,
                  leading: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 12),
                    child: AknAvatar(name: rows[i].name, size: 36),
                  ),
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        rows[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.label.copyWith(
                          color: c.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ShareBar(
                        value: rows[i].conversion ?? 0,
                        color: StatsHue.of(c, AknTone.ok).mark,
                        delay: Duration(milliseconds: 60 * i),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${StatsCopy.formsSummary(rows[i].forms, rows[i].converted)}'
                        '${rows[i].conversion == null ? '' : ' · ${StatsFmt.rate(rows[i].conversion)}'}',
                        style: t.caption.copyWith(color: c.dim),
                      ),
                    ],
                  ),
                  trailing: Text(
                    StatsFmt.litersCompact(rows[i].liters),
                    style: t.label.copyWith(
                      color: c.ink,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderStatusSection extends StatelessWidget {
  const _OrderStatusSection({required this.orders, required this.nav});

  final StatsOrderStatus orders;
  final _Nav nav;

  @override
  Widget build(BuildContext context) {
    final o = orders;
    final cells = [
      (
        StatsCopy.awaitingQuote,
        o.awaitingQuote,
        AknTone.info,
        Icons.hourglass_empty_rounded,
        '${AppRoutes.orders}?segment=active',
      ),
      (
        StatsCopy.awaitingDecision,
        o.awaitingDecision,
        AknTone.warn,
        Icons.gavel_rounded,
        '${AppRoutes.orders}?segment=decision',
      ),
      (
        StatsCopy.awaitingCompanyApproval,
        o.awaitingCompanyApproval,
        AknTone.info,
        Icons.how_to_reg_rounded,
        AppRoutes.approvals,
      ),
      (
        StatsCopy.inTransit,
        o.inTransit,
        AknTone.brand,
        Icons.local_shipping_rounded,
        AppRoutes.shipments,
      ),
      (
        StatsCopy.deliveredStatus,
        o.delivered,
        AknTone.ok,
        Icons.task_alt_rounded,
        '${AppRoutes.orders}?segment=history',
      ),
      (
        StatsCopy.disputedStatus,
        o.disputed,
        AknTone.danger,
        Icons.report_problem_rounded,
        AppRoutes.shipments,
      ),
    ];
    return _Section(
      title: StatsCopy.orderStatusTitle,
      subtitle: '${o.open} açık sipariş · teslimler dönemlik',
      icon: Icons.receipt_long_rounded,
      tone: AknTone.brand,
      child: LayoutBuilder(
        builder: (context, cons) {
          final cols = MediaQuery.textScalerOf(context).scale(10) >= 14 ? 1 : 2;
          final w = (cons.maxWidth - 10 * (cols - 1)) / cols;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (label, count, tone, icon, route) in cells)
                SizedBox(
                  width: w,
                  child: _StatusTile(
                    label: label,
                    count: count,
                    tone: count > 0 ? tone : AknTone.neutral,
                    icon: icon,
                    onTap: nav.maybe(route),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.label,
    required this.count,
    required this.tone,
    required this.icon,
    this.onTap,
  });

  final String label;
  final int count;
  final AknTone tone;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final tc = c.tone(tone);
    return Semantics(
      button: onTap != null,
      label: '$label: $count',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: tc.bg,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: tc.fg),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$count',
                          style: t.headline.copyWith(
                            fontWeight: FontWeight.w800,
                            color: c.ink,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.caption.copyWith(color: c.text),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LimitRow extends StatelessWidget {
  const _LimitRow({required this.limit});

  final StatsLimit limit;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final l = limit;
    String fmt(num? v) => l.isLiters ? StatsFmt.liters(v) : StatsFmt.money(v);
    if (l.isUnlimited) {
      return Row(
        children: [
          Expanded(
            child: Text(
              l.stationTitle,
              style: t.label.copyWith(
                color: c.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const StatsTag(
            label: StatsCopy.unlimited,
            tone: AknTone.ok,
            icon: Icons.all_inclusive_rounded,
          ),
        ],
      );
    }
    final rate = l.usageRate ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UsageBar(
          value: rate,
          label: l.stationTitle,
          valueLabel: StatsFmt.rate(rate),
        ),
        const SizedBox(height: 4),
        Text(
          'Kullanılabilir ${fmt(l.available)} · kullanılan ${fmt(l.used)} · limit ${fmt(l.limit)}',
          style: t.caption.copyWith(color: c.dim),
        ),
      ],
    );
  }
}

class _EmptyPeriod extends StatelessWidget {
  const _EmptyPeriod({required this.customer});

  final bool customer;

  @override
  Widget build(BuildContext context) => EmptyState(
    compact: true,
    title: customer ? StatsCopy.emptyPeriodCustomer : StatsCopy.emptyPeriod,
    message: StatsCopy.emptyPeriodMessage,
    illustration: AknIllustration.orders,
  );
}

class _Footer extends StatelessWidget {
  const _Footer({required this.failed, required this.generatedAt});

  final Set<String> failed;
  final DateTime? generatedAt;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (failed.isNotEmpty) ...[
            const AknBanner(
              tone: AknTone.warn,
              icon: Icons.sync_problem_rounded,
              message: StatsCopy.partialFailure,
            ),
            const SizedBox(height: 12),
          ],
          Text(StatsCopy.methodology, style: t.caption.copyWith(color: c.dim)),
          if (generatedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Hesaplandı ${Fmt.relative(generatedAt)}',
              style: t.caption.copyWith(color: c.dim),
            ),
          ],
        ],
      ),
    );
  }
}

/// "Son güncelleme 14:20 · 5 dk önce" (önbellekten gösterilen ya da tazelenemeyen veri).
class _UpdatedNote extends StatelessWidget {
  const _UpdatedNote({
    required this.updatedAt,
    required this.fromCache,
    required this.error,
  });

  final DateTime? updatedAt;
  final bool fromCache;
  final AppFailure? error;

  @override
  Widget build(BuildContext context) {
    final at = updatedAt;
    if (at == null || (!fromCache && error == null)) {
      return const SizedBox.shrink();
    }
    final c = context.akn;
    final t = context.aknText;
    final offline =
        fromCache || error is OfflineFailure || error is TimeoutFailure;
    final text = offline
        ? 'Son güncelleme ${Fmt.time(at)} · ${Fmt.relative(at)}'
        : 'Yenilenemedi · son güncelleme ${Fmt.relative(at)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            Icon(
              offline ? Icons.history_rounded : Icons.sync_problem_rounded,
              size: 16,
              color: c.dim,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text, style: t.caption.copyWith(color: c.dim)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Yükleme hatası (spec C.7 metinleri).
class _StatsFailure extends StatelessWidget {
  const _StatsFailure({required this.failure, required this.onRetry});

  final AppFailure failure;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final f = failure;
    return switch (f) {
      ForbiddenFailure() => const EmptyState(
        title: FailureCopy.forbidden,
        message: 'İstatistikleri görüntüleme yetkiniz yok.',
        illustration: AknIllustration.locked,
      ),
      NotFoundFailure() => const EmptyState(
        title: 'İstatistikler henüz hazır değil',
        message: 'Sunucu güncellenince istatistikler burada görünecek.',
        illustration: AknIllustration.search,
      ),
      _ => ErrorState(
        title: FailureCopy.title(f),
        message: FailureCopy.message(f),
        offline: f is OfflineFailure,
        traceId: FailureCopy.supportCodeOf(f) == null ? null : f.traceId,
        onRetry: () => unawaited(onRetry()),
        retryLabel: FailureCopy.retry,
      ),
    };
  }
}

class _PageSkeleton extends StatelessWidget {
  const _PageSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    Widget box(double h) => Container(
      height: h,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.lineSoft),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonLine(widthFactor: 0.4, height: 14),
          SizedBox(height: 10),
          SkeletonLine(widthFactor: 0.7, height: 22),
          Spacer(),
          SkeletonLine(widthFactor: 0.3, height: 10),
        ],
      ),
    );
    return Shimmer(
      semanticLabel: StatsCopy.deckLoading,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          const SkeletonLine(widthFactor: 0.45, height: 12),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: box(104)),
              const SizedBox(width: 12),
              Expanded(child: box(104)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: box(104)),
              const SizedBox(width: 12),
              Expanded(child: box(104)),
            ],
          ),
          const SizedBox(height: 12),
          box(300),
          const SizedBox(height: 12),
          box(200),
        ],
      ),
    );
  }
}

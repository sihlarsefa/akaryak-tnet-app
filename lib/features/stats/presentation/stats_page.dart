import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/env/app_config_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/network/failure_copy.dart';
import '../../../core/pdf/akn_pdf.dart';
import '../../../core/routing/app_location.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/routing/route_access.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import '../../customer_orders/api.dart' show Loadable;
import '../application/stats_providers.dart';
import '../application/stats_scope.dart';
import '../copy.dart';
import '../data/stats_models.dart';
import 'charts/bar_chart.dart';
import 'charts/line_chart.dart';
import 'charts/mix_chart.dart';
import 'deck/deck_cards.dart'
    show bayiDeckCards, customerDeckCards, usageColor, usageTone;
import 'stats_format.dart';
import 'stats_pdf.dart';
import 'widgets/stats_atoms.dart';

/// Aylık grafiğin ölçüsü.
enum _Metric { amount, liters, orders }

/// İstatistikler (`/stats`, tasarım v3 "Akış"): itilmiş çubuk "İstatistikler" + paylaş (PDF), dönem
/// seçici (Bu ay, Geçen ay, Son 3 ay, Bu yıl; kayan yaylı başparmak), "1–21 Ekim, güncellendi 10:41",
/// **tek plaka** (bayide Satış, müşteride Harcama: beyaz, sıcak tonlu hero kartı — rakam döner, fark
/// çipi, kural, sayaç gibi yerine oturan okumalar), ardından sayfada yüzen beyaz bölüm kartları (r22):
/// "Aylık gelişim" (Tutar / Litre / Sipariş, yaylanarak yükselen sütunlar, ay sonu tahmini, "Tablo
/// olarak göster"), "Ürün dağılımı" (büyüyen sıralı çubuklar), huni, sevkiyat, tahsilat, en çok alan
/// cariler, saha ekibi, limit riski; müşteride kendini çizen birim fiyat çizgisi, bayiler, noktalar,
/// sipariş durumu, limitler ve "Detaylı harcama raporu". Plaka yükselerek gelir, bölümler sırayla
/// (kaydırınca da görünür oldukça) belirir; dönem değişince içerik solarak geçer. Aşağı çekip
/// yenileme, dönem başına önbellek (çevrimdışı "Son güncelleme"), hata ekranı.
class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key, this.initialPeriod = StatsPeriod.month});

  final StatsPeriod initialPeriod;

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  late StatsPeriod _period = widget.initialPeriod;
  _Metric _metric = _Metric.amount;
  bool _table = false;
  bool _sharing = false;

  void _setPeriod(StatsPeriod p) {
    if (p == _period) return;
    setState(() => _period = p);
  }

  Future<void> _refresh() async {
    final scope = ref.read(statsScopeProvider);
    if (scope.isBayi) {
      await ref.read(bayiStatsProvider(_period).notifier).refresh();
    } else if (scope == StatsScope.customer) {
      await ref.read(customerStatsProvider(_period).notifier).refresh();
    }
  }

  Future<void> _share(Object data, StatsScope scope) async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final bytes = data is BayiStats
          ? await StatsPdf.bayi(
              data,
              own: data.isOwn || scope == StatsScope.own,
            )
          : await StatsPdf.customer(data as CustomerStats);
      await AknPdf.share(bytes, StatsPdf.fileName(_period));
    } catch (_) {
      AppToast.error(StatsCopy.shareFailed);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// "Nasıl hesaplanır?" (v4 §4: (i) /stats'ta): sayfadaki her ölçünün nasıl hesaplandığı, destenin
  /// kart metinleriyle (`DeckCardSpec.howTo`) ve genel yöntem notuyla.
  Future<void> _showHowTo(Object data, StatsScope scope) async {
    final specs = data is BayiStats
        ? bayiDeckCards(
            context,
            data,
            own: data.isOwn || scope == StatsScope.own,
          )
        : customerDeckCards(context, data as CustomerStats);
    final seen = <String>{};
    final items = [
      for (final spec in specs)
        if (seen.add(spec.title)) (spec.title, spec.howTo),
    ];
    await showAppSheet<void>(
      context: context,
      title: StatsCopy.deckHowTo,
      builder: (ctx) {
        final c = ctx.akn;
        final t = ctx.aknText;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (title, text) in items) ...[
              Semantics(
                header: true,
                child: Text(title, style: t.bodyStrong.copyWith(color: c.ink)),
              ),
              const SizedBox(height: 4),
              Text(text, style: t.bodySmall.copyWith(color: c.dim)),
              const SizedBox(height: 16),
            ],
            Text(
              StatsCopy.methodology,
              style: t.label.copyWith(
                fontWeight: FontWeight.w500,
                color: c.dim,
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(statsScopeProvider);
    var refreshing = false;
    Object? data;
    Widget body;
    String state;
    if (scope == StatsScope.none) {
      state = 'none';
      body = _centered(
        _StatsFailure(failure: const ForbiddenFailure(), onRetry: _refresh),
      );
    } else if (scope.isBayi) {
      final s = ref.watch(bayiStatsProvider(_period));
      data = s.data;
      refreshing = s.loading && s.data != null;
      (state, body) = _bodyFor(
        s,
        (d) => _BayiSections(
          data: d,
          own: d.isOwn || scope == StatsScope.own,
          metric: _metric,
          onMetric: (m) => setState(() => _metric = m),
          table: _table,
          onTable: () => setState(() => _table = !_table),
        ).children(context, ref),
      );
    } else {
      final s = ref.watch(customerStatsProvider(_period));
      data = s.data;
      refreshing = s.loading && s.data != null;
      (state, body) = _bodyFor(
        s,
        (d) => _CustomerSections(
          data: d,
          metric: _metric,
          onMetric: (m) => setState(() => _metric = m),
          table: _table,
          onTable: () => setState(() => _table = !_table),
        ).children(context, ref),
      );
    }
    final shareable = data;

    return AppScaffold(
      title: StatsCopy.pageTitle,
      refreshing: refreshing,
      showBell: false,
      actions: [
        if (scope != StatsScope.none) ...[
          // v4 §4: "Nasıl hesaplanır?" destenin ⋯ menüsünden buraya (i) olarak taşındı.
          AknIconButton(
            icon: PhosphorIconsRegular.info,
            semanticLabel: StatsCopy.deckHowTo,
            onPressed: shareable == null
                ? null
                : () => unawaited(_showHowTo(shareable, scope)),
          ),
          AknIconButton(
            icon: PhosphorIconsRegular.export,
            semanticLabel: StatsCopy.share,
            onPressed: shareable == null || _sharing
                ? null
                : () => unawaited(_share(shareable, scope)),
          ),
        ],
      ],
      body: Column(
        children: [
          if (scope != StatsScope.none)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Semantics(
                container: true,
                label: StatsCopy.periodSemantics,
                child: _Picker<StatsPeriod>(
                  options: [
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
    List<Widget> Function(T data) sections,
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
    final bottom = MediaQuery.paddingOf(context).bottom;
    final failed = d is BayiStats
        ? d.failedSections
        : (d as CustomerStats).failedSections;
    final generatedAt = d is BayiStats
        ? d.generatedAt
        : (d as CustomerStats).generatedAt;
    // v4 §5 12: dönem plakanın başlığında; "güncellendi" sayfanın sonundaki notta.
    final children = [
      ...sections(d),
      _Footer(
        failed: failed,
        generatedAt: generatedAt,
        updatedAt: s.updatedAt ?? generatedAt,
        fromCache: s.fromCache,
        error: s.error,
      ),
    ];
    // Bölümler ilk açılışta sırayla belirir (StaggerItem); plaka kendi yükselişiyle gelir. Bölümler
    // tek bir sütundadır: kaydırırken üstteki bölüm görünmez olsa bile sayfa bir bütün kalır.
    return (
      'data',
      PullToRefresh(
        onRefresh: _refresh,
        child: StaggerScope(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(bottom: 32 + bottom),
            children: [
              const SizedBox(height: 4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++)
                    children[i] is _HeadlinePlate
                        ? children[i]
                        : StatsStaggerItem(index: i, child: children[i]),
                ],
              ),
            ],
          ),
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

/// Bayi bölümleri: plaka, aylık gelişim, ürün dağılımı, huni, sevkiyat, tahsilat, cariler, ekip ve
/// risk (listenin çocukları olarak; [children]).
class _BayiSections {
  const _BayiSections({
    required this.data,
    required this.own,
    required this.metric,
    required this.onMetric,
    required this.table,
    required this.onTable,
  });

  final BayiStats data;
  final bool own;
  final _Metric metric;
  final ValueChanged<_Metric> onMetric;
  final bool table;
  final VoidCallback onTable;

  List<Widget> children(BuildContext context, WidgetRef ref) {
    final d = data;
    final sales = d.sales;
    final nav = _Nav(ref);
    final topCount = math.min(10, d.topCustomers.length);
    final topAmount = d.topCustomers.fold<double>(
      0,
      (m, r) => math.max(m, r.amount),
    );
    final children = <Widget>[
      if (sales != null)
        _HeadlinePlate(
          title: own ? StatsCopy.cardSalesOwn : StatsCopy.kpiSales,
          period: d.period,
          summary: sales,
          readouts: [
            PlateReadout(
              label: StatsCopy.kpiLiters,
              value: StatsFmt.count(sales.liters),
              unit: 'L',
            ),
            PlateReadout(
              label: StatsCopy.kpiOrders,
              value: StatsFmt.count(sales.orders),
            ),
            if (sales.activeCustomers != null)
              PlateReadout(
                label: StatsCopy.kpiActiveCustomers,
                value: StatsFmt.count(sales.activeCustomers),
              )
            else
              _priceReadout(sales.unitPrice),
          ],
        ),
      if (d.months.isNotEmpty)
        _MonthlySection(
          months: d.months,
          metric: metric,
          onMetric: onMetric,
          table: table,
          onTable: onTable,
          noun: 'satış',
        ),
      if (d.products.isNotEmpty)
        _ProductsSection(products: d.products, caption: StatsCopy.mixSubtitle),
      if (d.funnel != null) _FunnelSection(funnel: d.funnel!),
      if (d.deliveries != null && !own)
        _DeliveriesSection(deliveries: d.deliveries!),
      if (d.collections != null && !own)
        _CollectionsSection(collections: d.collections!),
      if (d.topCustomers.isNotEmpty)
        StatsSection(
          title: own
              ? StatsCopy.topCustomersOwnTitle
              : StatsCopy.topCustomersTitle,
          caption: StatsCopy.byAmount,
          children: [
            StatsRankedList(
              items: [
                for (final r in d.topCustomers.take(topCount))
                  RankedItem(
                    label: r.title,
                    value: StatsFmt.money(r.amount),
                    note: StatsFmt.rate(r.share),
                    fraction: topAmount <= 0 ? 0 : r.amount / topAmount,
                    onTap: nav.maybe(AppRoutes.customer(r.customerId)),
                    semanticLabel:
                        '${r.title}, ${StatsFmt.moneySpoken(r.amount)}, '
                        'payı ${StatsFmt.rate(r.share)}, '
                        '${StatsFmt.liters(r.liters)}, '
                        '${StatsCopy.ordersCount(r.orders)}',
                  ),
              ],
            ),
          ],
        ),
      if (d.team.isNotEmpty) _TeamSection(team: d.team, own: own),
      if (d.risk != null && d.risk!.nearLimitCount > 0 && !own)
        _RiskSection(risk: d.risk!, nav: nav),
      if (d.sales != null && d.sales!.isEmpty && d.products.isEmpty)
        const _EmptyPeriod(customer: false),
    ];
    return children;
  }
}

PlateReadout _priceReadout(double? price) => PlateReadout(
  label: StatsCopy.readoutAverage,
  value: StatsFmt.price(price),
  unit: price == null ? null : '₺/L',
  semanticLabel: price == null
      ? '${StatsCopy.kpiUnitPrice}: veri yok'
      : '${StatsCopy.kpiUnitPrice}: ${StatsFmt.price(price)} lira litre',
);

// ============================================================== müşteri

/// Müşteri bölümleri: plaka, aylık gelişim, ürünler, birim fiyat, bayiler, noktalar, sipariş durumu,
/// limitler ve detaylı harcama raporu (listenin çocukları olarak; [children]).
class _CustomerSections {
  const _CustomerSections({
    required this.data,
    required this.metric,
    required this.onMetric,
    required this.table,
    required this.onTable,
  });

  final CustomerStats data;
  final _Metric metric;
  final ValueChanged<_Metric> onMetric;
  final bool table;
  final VoidCallback onTable;

  List<Widget> children(BuildContext context, WidgetRef ref) {
    final d = data;
    final spend = d.spending;
    final nav = _Nav(ref);
    final priced = d.months.where((m) => m.unitPrice != null).length;
    final stationTop = d.stations.fold<double>(
      0,
      (m, s) => math.max(m, s.amount),
    );
    final points = [...d.deliveryPoints]
      ..sort((a, b) => b.liters.compareTo(a.liters));
    final pointLiters = points.fold<double>(0, (a, p) => a + p.liters);
    final children = <Widget>[
      if (spend != null)
        _HeadlinePlate(
          title: StatsCopy.kpiSpending,
          period: d.period,
          summary: spend,
          readouts: [
            PlateReadout(
              label: StatsCopy.kpiLitersCustomer,
              value: StatsFmt.count(spend.liters),
              unit: 'L',
            ),
            PlateReadout(
              label: StatsCopy.kpiOrders,
              value: StatsFmt.count(spend.orders),
            ),
            _priceReadout(spend.unitPrice),
          ],
        ),
      if (d.months.isNotEmpty)
        _MonthlySection(
          months: d.months,
          metric: metric,
          onMetric: onMetric,
          table: table,
          onTable: onTable,
          noun: 'harcama',
        ),
      if (d.products.isNotEmpty)
        _ProductsSection(
          products: d.products,
          caption: StatsCopy.mixSubtitleCustomer,
        ),
      if (priced >= 2)
        _UnitPriceSection(
          price: spend?.unitPrice,
          previous: spend?.prevUnitPrice,
          compare: d.period.key.compareShort,
          months: d.months,
        ),
      if (d.stations.isNotEmpty)
        StatsSection(
          title: StatsCopy.stationsTitle,
          caption: StatsCopy.byAmount,
          children: [
            StatsRankedList(
              items: [
                for (final s in d.stations)
                  RankedItem(
                    label: s.title,
                    value: StatsFmt.money(s.amount),
                    note: StatsFmt.rate(s.share),
                    fraction: stationTop <= 0 ? 0 : s.amount / stationTop,
                    semanticLabel:
                        '${s.title}, ${StatsFmt.moneySpoken(s.amount)}, '
                        '${StatsFmt.liters(s.liters)}, payı ${StatsFmt.rate(s.share)}',
                  ),
              ],
            ),
          ],
        ),
      if (points.isNotEmpty)
        StatsSection(
          title: StatsCopy.pointsTitle,
          caption: StatsCopy.byLiters,
          children: [
            StatsRankedList(
              items: [
                for (final p in points)
                  RankedItem(
                    label: [p.name, ?p.city].join(', '),
                    value: StatsFmt.liters(p.liters),
                    note: pointLiters <= 0
                        ? null
                        : StatsFmt.rate(p.liters / pointLiters),
                    fraction: pointLiters <= 0 ? 0 : p.liters / pointLiters,
                  ),
              ],
            ),
          ],
        ),
      if (d.orders != null) _OrderStatusSection(orders: d.orders!, nav: nav),
      if (d.limits.isNotEmpty)
        StatsSection(
          title: StatsCopy.limitsTitle,
          children: [
            StatsDivided(
              children: [for (final l in d.limits) _LimitRow(limit: l)],
            ),
          ],
        ),
      if (nav.can(AppRoutes.spending))
        StatsCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: AknListTile(
            leadingIcon: PhosphorIconsRegular.fileText,
            leadingTone: AknTone.brand,
            title: StatsCopy.spendingReport,
            subtitle: StatsCopy.spendingReportHint,
            showChevron: true,
            onTap: () => context.openAppLocation(AppRoutes.spending),
          ),
        ),
      if (spend != null && spend.isEmpty && d.products.isEmpty)
        const _EmptyPeriod(customer: true),
    ];
    return children;
  }
}

// ============================================================== bölümler

/// Rotaya izin varsa gezinme (izin yoksa satır dokunulmaz). Hedef bir sekmeyse (müşterinin
/// Siparişler'i, Onaylar'ı, Teslimat'ı) sekmeye geçilir, ayrıntıysa itilir: itilen İstatistikler'in
/// üstüne bir sekme rotası `push` edilirse kabuk ikinci kez kurulurdu (QA SC-01).
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
    return () => context.openAppLocation(route);
  }
}

/// Seçici: etiketler sığıyorsa bölmeli kontrol (`AknSegmented`), büyük yazıda ya da dar ekranda
/// sığmıyorsa yatay kayan çipler (`FilterChips`); etiket kesilmez.
class _Picker<T> extends StatelessWidget {
  const _Picker({
    required this.options,
    required this.value,
    required this.onChanged,
    this.dense = false,
  });

  final List<FilterOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final scaler = MediaQuery.textScalerOf(context);
    final style = t.label.copyWith(fontSize: 14, fontWeight: FontWeight.w600);
    return LayoutBuilder(
      builder: (context, cons) {
        final slot = (cons.maxWidth - 2 * AknSpace.page - 6) / options.length;
        var fits = true;
        for (final o in options) {
          final tp = TextPainter(
            text: TextSpan(text: o.label, style: style),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          if (tp.width + 16 > slot) fits = false;
          tp.dispose();
        }
        if (fits) {
          return AknSegmented<T>(
            segments: options,
            value: value,
            onChanged: onChanged,
            dense: dense,
          );
        }
        return FilterChips<T>(
          options: options,
          selected: {value},
          allowEmpty: false,
          onChanged: (s) {
            if (s.isNotEmpty) onChanged(s.first);
          },
        );
      },
    );
  }
}

/// Sayfanın tek plakası (tasarım v4 §5 12): başlık ve dönem tek satırda ("Harcama  1–28 Ekim"),
/// fark çipi sağda (`PlateHead.trailing`), rakam döner, altında üç okuma; simge kutusu yok. Sayfa
/// açılınca yükselerek ve hafifçe büyüyerek gelir; okumalar sayaç gibi yerine oturur. Çip varken
/// karşılaştırmanın kısa adı dönem satırındadır ("1–28 Ekim · geçen aya göre"; v4 tur 2 A11: çip
/// neye göre olduğunu yanında söyler ve satır çipin yanında tek satırda kalır); ekran okuyucu uzun
/// cümleyi duyar.
class _HeadlinePlate extends StatelessWidget {
  const _HeadlinePlate({
    required this.title,
    required this.period,
    required this.summary,
    required this.readouts,
  });

  final String title;
  final StatsPeriodInfo period;
  final StatsSummary summary;
  final List<PlateReadout> readouts;

  @override
  Widget build(BuildContext context) {
    final pct = StatsFmt.change(summary.amount, summary.prevAmount);
    final compare = period.key.compareShort;
    return StatsRise(
      offset: 24,
      scale: 0.94,
      duration: AknMotion.heroRise,
      child: AknPlate(
        margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        head: PlateHead(
          title: title,
          period: [
            period.from == null
                ? period.title
                : StatsFmt.rangeShort(period.from, period.to),
            if (pct != null) period.key.compareBrief,
          ].join(' · '),
          trailing: pct == null
              ? null
              : Semantics(
                  label: '${StatsFmt.deltaSpoken(pct)}, $compare',
                  excludeSemantics: true,
                  child: AknDeltaChip(
                    label: StatsFmt.deltaPercent(pct),
                    direction: pct.abs() < StatsFmt.flatThreshold
                        ? AknDeltaDirection.flat
                        : pct > 0
                        ? AknDeltaDirection.up
                        : AknDeltaDirection.down,
                  ),
                ),
        ),
        figure: PlateFigure(
          value: StatsFmt.count(summary.amount),
          unit: '₺',
          semanticLabel: StatsFmt.moneyWholeSpoken(summary.amount),
        ),
        below: PlateReadouts(items: readouts),
      ),
    );
  }
}

/// Bu ayın ay sonu tahmini (son sütun içinde bulunduğumuz ay ise ve ayın 5'inden sonra).
double? _monthProjection(List<StatsMonth> months, double value) {
  if (months.isEmpty || value <= 0) return null;
  final now = TrTime.wall(TrTime.now());
  final last = months.last;
  if (last.year != now.year || last.month != now.month) return null;
  return plateMonthEndProjection(value, DateTime(now.year, now.month, now.day));
}

/// Aylık gelişim (kart): ölçü seçici (kayan başparmak), yaylanarak yükselen sütunlar (bu ay turuncu
/// degrade, tahmin kesikli), lejant ve "Tablo olarak göster" — grafik ile tablo arasında solarak ve
/// yüksekliği kayarak geçer.
class _MonthlySection extends StatelessWidget {
  const _MonthlySection({
    required this.months,
    required this.metric,
    required this.onMetric,
    required this.table,
    required this.onTable,
    required this.noun,
  });

  final List<StatsMonth> months;
  final _Metric metric;
  final ValueChanged<_Metric> onMetric;
  final bool table;
  final VoidCallback onTable;
  final String noun;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    double value(StatsMonth m) => switch (metric) {
      _Metric.amount => m.amount,
      _Metric.liters => m.liters,
      _Metric.orders => m.orders.toDouble(),
    };
    String full(double v) => switch (metric) {
      _Metric.amount => StatsFmt.money(v),
      _Metric.liters => StatsFmt.liters(v),
      _Metric.orders => StatsCopy.ordersCount(v.round()),
    };
    String short(double v) => switch (metric) {
      _Metric.orders => StatsFmt.count(v),
      _ => StatsFmt.compactNumber(v),
    };
    String legend(double v) => switch (metric) {
      _Metric.amount => StatsFmt.moneyCompact(v),
      _Metric.liters => StatsFmt.litersCompact(v),
      _Metric.orders => StatsCopy.ordersCount(v.round()),
    };
    String spoken(double v) => switch (metric) {
      _Metric.amount => StatsFmt.moneySpoken(v),
      _Metric.liters => StatsFmt.litersSpoken(v),
      _Metric.orders => StatsCopy.ordersCount(v.round()),
    };
    String bare(double v) => short(v).split(' ').first;
    final last = months.last;
    final proj = _monthProjection(months, value(last));
    return StatsSection(
      title: StatsCopy.monthlyTitle,
      caption: months.length > 6
          ? StatsCopy.lastTwelveMonths
          : StatsCopy.lastSixMonths,
      children: [
        Semantics(
          container: true,
          label: StatsCopy.metricSemantics,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: _MetricTabs(value: metric, onChanged: onMetric),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: AknAnimatedSize(
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: AknMotion.of(context, AknMotion.base),
              switchInCurve: AknMotion.emphasizedCurve,
              switchOutCurve: AknMotion.exit,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, ?current],
              ),
              child: table
                  ? _MonthTable(
                      key: const ValueKey('table'),
                      months: months,
                      value: value,
                      format: full,
                    )
                  : StatsBarChart(
                      key: ValueKey('monthly-${metric.name}-${months.length}'),
                      bars: [
                        for (final x in months)
                          ChartBar(
                            label: x.shortLabel,
                            longLabel: x.longLabel,
                            value: value(x),
                          ),
                      ],
                      valueLabel: short,
                      extremeLabel: bare,
                      projection: proj,
                      projectionLabel: bare,
                      bubbleLabel: (b) => '${b.longLabel}: ${full(b.value)}',
                      spoken: (b) => [
                        '${b.longLabel} $noun ${spoken(b.value)}',
                        if (b.longLabel == last.longLabel && proj != null)
                          StatsCopy.projectionLegend(spoken(proj)),
                      ].join(', '),
                      emptyHint: StatsCopy.emptyPeriod,
                      maxBarWidth: months.length > 6 ? 12 : 16,
                      // v4 §5 12: yalnızca bu ay etiketli; tahmin altındaki cümlede.
                      labelExtreme: false,
                      labelProjection: false,
                    ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 2,
            spacing: 12,
            children: [
              if (proj != null && !table)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ChartDashedSwatch(),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        StatsCopy.projectionFooter(legend(proj)),
                        style: t.label.copyWith(
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ],
                )
              else
                const SizedBox.shrink(),
              AknButton.ghost(
                label: table ? StatsCopy.chartShort : StatsCopy.tableShort,
                semanticLabel: table
                    ? StatsCopy.chartShow
                    : StatsCopy.tableShow,
                size: AknButtonSize.small,
                onPressed: onTable,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Kartın içindeki ölçü sekmeleri (tasarım v4 §5 12): "Tutar · Litre · Sipariş" metin sekmeleri
/// (seçili mürekkep 700, diğerleri soluk 600) ve seçilenin altında yaylanarak kayan 2 dp turuncu çizgi;
/// dolu iz yok (ekranın tek dolu izi dönem seçicisi). Her sekme ≥ 48 dp hedef, ekran okuyucuda seçili
/// düğme; sığmazsa (büyük yazı) tümü birlikte küçülür.
class _MetricTabs extends StatelessWidget {
  const _MetricTabs({required this.value, required this.onChanged});

  final _Metric value;
  final ValueChanged<_Metric> onChanged;

  static String _label(_Metric m) => switch (m) {
    _Metric.amount => StatsCopy.metricAmount,
    _Metric.liters => StatsCopy.metricLiters,
    _Metric.orders => StatsCopy.metricOrders,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final scaler = MediaQuery.textScalerOf(context);
    final base = t.label.copyWith(fontSize: 14, height: 18 / 14);
    final on = base.copyWith(fontWeight: FontWeight.w700, color: c.ink);
    final off = base.copyWith(fontWeight: FontWeight.w600, color: c.dim);
    final duration = AknMotion.of(context, AknMotion.thumb);
    double measure(String text) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: on),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = tp.width.ceilToDouble();
      tp.dispose();
      return w;
    }

    const metrics = _Metric.values;
    final texts = [for (final m in metrics) measure(_label(m))];
    // Her sekme en az 48 dp; yazılar arasında 6'şar dp iç boşluk.
    final tabs = [for (final w in texts) math.max(48.0, w + 12)];
    final xs = <double>[];
    var x = 0.0;
    for (final w in tabs) {
      xs.add(x);
      x += w + 8;
    }
    final total = x - 8;
    final i = metrics.indexOf(value);
    final row = SizedBox(
      width: total,
      height: 48,
      child: Stack(
        children: [
          for (var k = 0; k < metrics.length; k++)
            Positioned(
              left: xs[k],
              width: tabs[k],
              top: 0,
              bottom: 0,
              child: Semantics(
                button: true,
                selected: k == i,
                inMutuallyExclusiveGroup: true,
                label: _label(metrics[k]),
                excludeSemantics: true,
                onTap: () => onChanged(metrics[k]),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (k == i) return;
                    AknHaptics.selection();
                    onChanged(metrics[k]);
                  },
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: duration,
                      curve: AknMotion.standard,
                      style: k == i ? on : off,
                      child: Text(
                        _label(metrics[k]),
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          AnimatedPositioned(
            duration: duration,
            curve: AknMotion.spring,
            left: xs[i] + (tabs[i] - texts[i]) / 2,
            width: texts[i],
            bottom: 8,
            height: 2,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.brand,
                  borderRadius: const BorderRadius.all(Radius.circular(1)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: row,
      ),
    );
  }
}

/// Grafiğin tablo hâli: ay | değer (sağa hizalı).
class _MonthTable extends StatelessWidget {
  const _MonthTable({
    super.key,
    required this.months,
    required this.value,
    required this.format,
  });

  final List<StatsMonth> months;
  final double Function(StatsMonth) value;
  final String Function(double) format;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final rows = months.reversed.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++)
          Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: i == 0
                ? null
                : BoxDecoration(
                    border: Border(top: BorderSide(color: c.line)),
                  ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(
                    rows[i].longLabel,
                    style: t.body.copyWith(
                      color: c.ink,
                      fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                Text(
                  format(value(rows[i])),
                  style: t.body.copyWith(
                    color: c.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Ürün dağılımı: litreye göre sıralı çubuklar (tek seri, ürüne renk yok; düz veri olduğundan
/// turuncu vurgu da yok: ilk satır mürekkep, v4 tur 2 A20).
class _ProductsSection extends StatelessWidget {
  const _ProductsSection({required this.products, required this.caption});

  final List<StatsProduct> products;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final total = products.fold<double>(0, (a, p) => a + p.liters);
    final shares = products.fold<double>(0, (a, p) => a + p.share);
    double frac(StatsProduct p) =>
        total > 0 ? p.liters / total : (shares > 0 ? p.share / shares : 0);
    final rows = [...products]..sort((a, b) => frac(b).compareTo(frac(a)));
    return StatsSection(
      title: StatsCopy.mixTitle,
      caption: caption,
      children: [
        StatsRankedList(
          accent: false,
          items: [
            for (final p in rows)
              RankedItem(
                label: p.name,
                value: StatsFmt.liters(p.liters),
                note: StatsFmt.rate(frac(p)),
                fraction: frac(p),
                semanticLabel:
                    '${p.name}, ${StatsFmt.litersSpoken(p.liters)}, '
                    'payı ${StatsFmt.rate(frac(p))}, ${StatsFmt.money(p.amount)}',
              ),
          ],
        ),
      ],
    );
  }
}

/// Sipariş hunisi: Talep, Teklif verilen, Onaylanan (sonuç turuncu) ve defter satırları.
class _FunnelSection extends StatelessWidget {
  const _FunnelSection({required this.funnel});

  final StatsFunnel funnel;

  @override
  Widget build(BuildContext context) {
    final f = funnel;
    final conv = f.conversion;
    final top = math.max(f.requests, math.max(f.quoted, f.accepted));
    double frac(int v) => top <= 0 ? 0 : v / top;
    return StatsSection(
      title: StatsCopy.funnelTitle,
      subtitle: StatsCopy.funnelSentence(f.requests, f.accepted),
      caption: conv == null
          ? null
          : '${StatsFmt.rate(conv, decimals: 1)} ${StatsCopy.conversion}',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
          child: PlateFunnel(
            steps: [
              PlateFunnelStep(
                label: StatsCopy.funnelRequests,
                value: StatsFmt.count(f.requests),
                fraction: frac(f.requests),
              ),
              PlateFunnelStep(
                label: 'Teklif verilen',
                value: StatsFmt.count(f.quoted),
                fraction: frac(f.quoted),
              ),
              PlateFunnelStep(
                label: 'Onaylanan',
                value: StatsFmt.count(f.accepted),
                fraction: frac(f.accepted),
                highlight: true,
              ),
            ],
          ),
        ),
        StatsDivided(
          children: [
            StatsFactRow(
              label: StatsCopy.rejected,
              value: StatsFmt.count(f.rejected),
            ),
            StatsFactRow(
              label: StatsCopy.expired,
              value: StatsFmt.count(f.expired),
            ),
            if (f.avgFirstQuoteMinutes != null)
              StatsFactRow(
                label: StatsCopy.firstQuoteLine,
                value: StatsFmt.minutes(f.avgFirstQuoteMinutes),
              ),
          ],
        ),
      ],
    );
  }
}

/// Sevkiyat: zamanında oranı ölçerde (hedef %90 çizgisi) ve anlık durum okumaları.
class _DeliveriesSection extends StatelessWidget {
  const _DeliveriesSection({required this.deliveries});

  final StatsDeliveries deliveries;

  @override
  Widget build(BuildContext context) {
    final d = deliveries;
    final rate = d.onTimeRate;
    return StatsSection(
      title: StatsCopy.deliveriesTitle,
      subtitle:
          '${StatsCopy.deliveriesCount(d.delivered)}, '
          '${StatsFmt.liters(d.deliveredLiters)}',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (rate != null) ...[
                StatsRateLine(
                  rate: StatsFmt.rate(rate),
                  label: StatsCopy.onTime,
                  trailing: StatsCopy.onTimeTarget,
                ),
                const SizedBox(height: 12),
                PlateMeter(
                  value: rate,
                  threshold: StatsCopy.onTimeGoal,
                  semanticLabel: 'Zamanında teslim, hedef yüzde 90',
                ),
                const SizedBox(height: 18),
              ],
              PlateReadouts(
                items: [
                  PlateReadout(
                    label: StatsCopy.inTransit,
                    value: StatsFmt.count(d.inTransit),
                  ),
                  PlateReadout(
                    label: StatsCopy.planned,
                    value: StatsFmt.count(d.planned),
                  ),
                  PlateReadout(
                    label: StatsCopy.disputes,
                    value: StatsFmt.count(d.disputes),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tahsilat: defter satırları; gecikme kırmızı lamba ve kalın (beyaz sayfada durum rengi serbest).
class _CollectionsSection extends StatelessWidget {
  const _CollectionsSection({required this.collections});

  final StatsCollections collections;

  @override
  Widget build(BuildContext context) {
    final x = collections;
    return StatsSection(
      title: StatsCopy.collectionsTitle,
      children: [
        StatsDivided(
          children: [
            AknListTile(
              title: StatsCopy.overdue,
              amount: StatsFmt.money(x.overdueAmount),
              status: x.overdueCount > 0
                  ? AknLamp(
                      label: StatsCopy.overdueLate(x.overdueCount),
                      tone: AknTone.danger,
                      solid: true,
                    )
                  : const AknLamp(label: StatsCopy.noOverdue, tone: AknTone.ok),
            ),
            AknListTile(
              title: StatsCopy.dueSoon(x.dueSoonDays),
              subtitle: StatsCopy.paymentsCount(x.dueSoonCount),
              amount: StatsFmt.money(x.dueSoonAmount),
            ),
            AknListTile(
              title: StatsCopy.collectedRow,
              subtitle: StatsCopy.paymentsCount(x.collectedCount),
              amount: StatsFmt.money(x.collectedAmount),
            ),
          ],
        ),
      ],
    );
  }
}

/// Saha ekibi: iki seri (form, siparişe dönüşen) sıralı çubuklar ve lejant.
class _TeamSection extends StatelessWidget {
  const _TeamSection({required this.team, required this.own});

  final List<StatsTeamMember> team;
  final bool own;

  @override
  Widget build(BuildContext context) {
    final rows = [...team]
      ..sort((a, b) {
        final x = b.converted.compareTo(a.converted);
        return x != 0 ? x : b.forms.compareTo(a.forms);
      });
    final forms = team.fold<int>(0, (a, m) => a + m.forms);
    final converted = team.fold<int>(0, (a, m) => a + m.converted);
    final most = rows.fold<int>(
      0,
      (m, r) => math.max(m, math.max(r.forms, r.converted)),
    );
    return StatsSection(
      title: own ? StatsCopy.cardOwnForms : StatsCopy.teamTitle,
      subtitle: forms > 0
          ? '${StatsCopy.formsSummary(forms, converted)}, '
                '${StatsFmt.rate(converted / forms)} ${StatsCopy.converted}'
          : 'Bu dönemde form yok',
      children: [
        StatsRankedList(
          items: [
            for (final m in rows)
              RankedItem(
                label: m.name,
                value: StatsCopy.formsSummary(m.forms, m.converted),
                note: m.conversion == null ? null : StatsFmt.rate(m.conversion),
                track: most <= 0 ? 0 : m.forms / most,
                fraction: most <= 0 ? 0 : m.converted / most,
                semanticLabel:
                    '${m.name}: ${StatsCopy.formsSummary(m.forms, m.converted)}, '
                    '${StatsFmt.litersSpoken(m.liters)}',
              ),
          ],
          legend: const [
            RankedLegend(StatsCopy.legendConverted),
            RankedLegend(StatsCopy.legendForms, filled: false),
          ],
        ),
      ],
    );
  }
}

/// Limit riski: kullanım satırları (%80 ve üstü koyu sarı, %95 ve üstü kırmızı; ikon + kelime),
/// çubuk %100'de durur.
class _RiskSection extends StatelessWidget {
  const _RiskSection({required this.risk, required this.nav});

  final StatsRisk risk;
  final _Nav nav;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final rows = [...risk.nearLimit]
      ..sort((a, b) => b.usageRate.compareTo(a.usageRate));
    return StatsSection(
      title: StatsCopy.riskTitle,
      subtitle:
          '${risk.nearLimitCount} cari limitinin %80 ve üzerini kullanıyor',
      children: [
        StatsRankedList(
          threshold: StatsCopy.warnLevel,
          items: [
            for (final r in rows)
              RankedItem(
                label: r.title,
                value: StatsFmt.rate(r.usageRate),
                fraction: math.min(1, r.usageRate),
                color: usageColor(c, r.usageRate),
                onTap: nav.maybe(AppRoutes.customer(r.customerId)),
                status: _UsageLamp(rate: r.usageRate),
                semanticLabel:
                    '${r.title}, limit kullanımı ${StatsFmt.rate(r.usageRate)}, '
                    '${_usageWord(r.usageRate)}',
              ),
          ],
        ),
      ],
    );
  }
}

String _usageWord(double rate) => rate >= 1
    ? StatsCopy.limitOver
    : rate >= 0.95
    ? StatsCopy.limitCritical
    : StatsCopy.limitNear;

/// Kullanım lambası (ikon değil, lamba + kelime; renk tek başına anlam taşımaz).
class _UsageLamp extends StatelessWidget {
  const _UsageLamp({required this.rate});

  final double rate;

  @override
  Widget build(BuildContext context) {
    final tone = usageTone(rate);
    if (tone == AknTone.neutral) return const SizedBox.shrink();
    return AknLamp(
      label: _usageWord(rate),
      tone: tone,
      size: AknLampSize.small,
    );
  }
}

/// Ortalama birim fiyat (müşteri): büyük okuma, fark çipi (düşüş iyi) ve 6 aylık çizgi.
class _UnitPriceSection extends StatelessWidget {
  const _UnitPriceSection({
    required this.price,
    required this.previous,
    required this.compare,
    required this.months,
  });

  final double? price;
  final double? previous;
  final String compare;
  final List<StatsMonth> months;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final p = price;
    final prev = previous;
    final diff = p == null || prev == null ? null : p - prev;
    final flat = diff != null && diff.abs() < 0.005;
    return StatsSection(
      title: StatsCopy.unitPriceTitle,
      caption: 'litre başına',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (p != null)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: StatsReadoutFigure(
                    value: StatsFmt.price(p),
                    unit: '₺/L',
                  ),
                ),
              if (diff != null) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AknDeltaChip.change(
                      flat ? 0 : diff,
                      label: StatsFmt.priceDelta(diff),
                      positiveIsGood: false,
                      onPlate: false,
                    ),
                    Text(
                      StatsCopy.priceSentence(
                        compare,
                        cheaper: flat ? null : diff < 0,
                      ),
                      style: t.bodySmall.copyWith(color: c.dim),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                height: 140,
                child: StatsLineChart(
                  points: [
                    for (final m in months)
                      LinePoint(label: m.shortLabel, value: m.unitPrice),
                  ],
                  valueLabel: StatsFmt.price,
                  semanticsLabel: [
                    'Aylara göre ortalama birim fiyat',
                    for (final m in months)
                      if (m.unitPrice != null)
                        '${m.longLabel} ${StatsFmt.unitPrice(m.unitPrice)}',
                  ].join(', '),
                  emptyHint: StatsCopy.noPrice,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sipariş durumu (müşteri): durum satırları, sayılar sağda; karar sizdeyse "Sıra sizde" lambası.
class _OrderStatusSection extends StatelessWidget {
  const _OrderStatusSection({required this.orders, required this.nav});

  final StatsOrderStatus orders;
  final _Nav nav;

  @override
  Widget build(BuildContext context) {
    final o = orders;
    final rows = [
      (
        StatsCopy.awaitingDecision,
        o.awaitingDecision,
        '${AppRoutes.orders}?segment=decision',
      ),
      (
        StatsCopy.awaitingQuote,
        o.awaitingQuote,
        '${AppRoutes.orders}?segment=active',
      ),
      (
        StatsCopy.awaitingCompanyApproval,
        o.awaitingCompanyApproval,
        AppRoutes.approvals,
      ),
      (StatsCopy.inTransit, o.inTransit, AppRoutes.shipments),
      (
        StatsCopy.deliveredStatus,
        o.delivered,
        '${AppRoutes.orders}?segment=history',
      ),
      (StatsCopy.disputedStatus, o.disputed, AppRoutes.shipments),
    ];
    return StatsSection(
      title: StatsCopy.orderStatusTitle,
      subtitle: '${o.open} ${StatsCopy.openOrders}; teslimler dönemlik',
      children: [
        StatsDivided(
          children: [
            for (final (label, count, route) in rows)
              AknListTile(
                dense: true,
                title: label,
                amount: StatsFmt.count(count),
                showChevron: nav.can(route),
                onTap: nav.maybe(route),
                status: label == StatsCopy.awaitingDecision && count > 0
                    ? const AknLamp(
                        label: StatsCopy.yourMove,
                        tone: AknTone.brand,
                        solid: true,
                      )
                    : label == StatsCopy.disputedStatus && count > 0
                    ? const AknLamp(
                        label: StatsCopy.disputedStatus,
                        tone: AknTone.danger,
                      )
                    : null,
                semanticLabel: '$label: $count',
              ),
          ],
        ),
      ],
    );
  }
}

/// Bayideki limit kullanımı (müşteri): ad, oran, ölçer (eşik %80; çubuk %100'de durur), lamba ve
/// kullanılabilir / limit.
class _LimitRow extends StatelessWidget {
  const _LimitRow({required this.limit});

  final StatsLimit limit;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final l = limit;
    String fmt(num? v) => l.isLiters ? StatsFmt.liters(v) : StatsFmt.money(v);
    if (l.isUnlimited) {
      return AknListTile(
        dense: true,
        title: l.stationTitle,
        amount: StatsCopy.unlimited,
      );
    }
    final rate = l.usageRate ?? 0;
    return StatsRankedList(
      threshold: StatsCopy.warnLevel,
      items: [
        RankedItem(
          label: l.stationTitle,
          value: StatsFmt.rate(rate),
          fraction: math.min(1, rate),
          color: usageColor(c, rate),
          status: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                StatsCopy.limitCaption(fmt(l.available), fmt(l.limit)),
                style: context.aknText.bodySmall.copyWith(color: c.dim),
              ),
              if (usageTone(rate) != AknTone.neutral) ...[
                const SizedBox(height: 4),
                _UsageLamp(rate: rate),
              ],
            ],
          ),
          semanticLabel:
              '${l.stationTitle}, limit kullanımı ${StatsFmt.rate(rate)}, '
              '${StatsCopy.limitCaption(fmt(l.available), fmt(l.limit))}',
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
    illustration: AknIllustration.stats,
  );
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.failed,
    required this.generatedAt,
    this.updatedAt,
    this.fromCache = false,
    this.error,
  });

  final Set<String> failed;
  final DateTime? generatedAt;

  /// Verinin alındığı an (v4 §5 12: "güncellendi" sayfanın sonundaki notta).
  final DateTime? updatedAt;
  final bool fromCache;
  final AppFailure? error;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final at = updatedAt ?? generatedAt;
    final stale = at != null && (fromCache || error != null);
    final offline =
        fromCache || error is OfflineFailure || error is TimeoutFailure;
    final style = t.caption.copyWith(color: c.dim);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (failed.isNotEmpty) ...[
            const AknBanner(
              tone: AknTone.warn,
              icon: PhosphorIconsRegular.cloudWarning,
              message: StatsCopy.partialFailure,
            ),
            const SizedBox(height: 12),
          ],
          if (stale)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      offline
                          ? PhosphorIconsRegular.clockCounterClockwise
                          : PhosphorIconsRegular.cloudWarning,
                      size: 16,
                      color: c.dim,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        offline
                            ? StatsCopy.lastUpdate(
                                Fmt.time(at),
                                TurkishText.lower(Fmt.relative(at)),
                              )
                            : StatsCopy.notRefreshed(
                                TurkishText.lower(Fmt.relative(at)),
                              ),
                        style: style,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (at != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(StatsCopy.updatedAt(Fmt.time(at)), style: style),
            ),
          Text(StatsCopy.methodology, style: style),
        ],
      ),
    );
  }
}

/// Yükleme hatası (yüzen çizimli boş / hata durumu; tasarım v3 §4 metinleri).
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
        message:
            'İstatistikleri görüntüleme yetkiniz yok. Yöneticinizden yetki isteyin.',
        illustration: AknIllustration.locked,
      ),
      NotFoundFailure() => const EmptyState(
        title: 'İstatistikler henüz hazır değil',
        message: 'Sunucu güncellenince istatistikler burada görünecek.',
        illustration: AknIllustration.stats,
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

/// İlk yükleme: parıltılı iskelet sayfanın düzenini taklit eder (plaka kartı, bölüm kartları,
/// sütunlar); veri gelince içerik solarak geçer.
class _PageSkeleton extends StatelessWidget {
  const _PageSkeleton();

  @override
  Widget build(BuildContext context) {
    const heights = [0.5, 0.56, 0.52, 0.62, 0.7, 0.66, 0.64, 0.68, 0.8, 0.74];
    final c = context.akn;
    Widget card(Widget child) => DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AknRadius.section,
        border: c.isDark ? Border.all(color: c.line) : null,
        boxShadow: AknShadows.card(c),
      ),
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    );
    return Shimmer(
      semanticLabel: StatsCopy.deckLoading,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        children: [
          const SkeletonLine(widthFactor: 0.5, height: 12),
          const SizedBox(height: 14),
          DecoratedBox(
            decoration: c.plateDecoration(raised: false),
            child: const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SkeletonBox(width: 40, height: 40, radius: 12),
                      SizedBox(width: 12),
                      SkeletonBox(width: 110, height: 14, radius: 7),
                    ],
                  ),
                  SizedBox(height: 16),
                  SkeletonBox(width: 220, height: 44, radius: 12),
                  SizedBox(height: 12),
                  SkeletonBox(width: 150, height: 22, radius: 8),
                  SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(child: SkeletonBox(height: 40, radius: 10)),
                      SizedBox(width: 10),
                      Expanded(child: SkeletonBox(height: 40, radius: 10)),
                      SizedBox(width: 10),
                      Expanded(child: SkeletonBox(height: 40, radius: 10)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          card(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SkeletonLine(widthFactor: 0.4, height: 18),
                const SizedBox(height: 16),
                const SkeletonBox(height: 36, radius: 18),
                const SizedBox(height: 22),
                SizedBox(
                  height: 112,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      for (final h in heights)
                        SkeletonBox(width: 12, height: 112 * h, radius: 6),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          card(
            const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SkeletonLine(widthFactor: 0.45, height: 18),
                SizedBox(height: 16),
                SkeletonLine(widthFactor: 0.9, height: 12),
                SizedBox(height: 8),
                SkeletonBox(height: 10, radius: 5),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/permissions.dart';
import '../../../../core/auth/session_controller.dart';
import '../../../../core/models/models.dart';
import '../../../../core/routing/app_location.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../application/bayi_grants.dart';
import '../../application/bayi_runtime.dart';
import '../../application/dispatch_controller.dart';
import '../../copy.dart';
import '../../data/bayi_json.dart';
import '../../data/dispatch_models.dart';
import '../widgets/bayi_widgets.dart';
import '../widgets/paged_list_body.dart';
import 'plan_sheet.dart';
import 'shipment_sheet.dart';

enum _Segment { board, list }

/// Sevkiyat (spec A.4 / A.3 adım 5–7, tasarım v3 "Akış"): pano (planlanacak siparişler kovalarda,
/// açık sevkiyatlar günlere göre, şoför hesabı uyarısı) ve "Sevkiyatlar" listesi (durum çipleri,
/// itirazlı, bugünkü yüklemeler, tarih, arama); iki görünüm arasında solarak geçilir. Her sipariş ve
/// sevkiyat beyaz bir kart: cari ve nokta, sağda litre (tablo rakamları) ve küçük ADR levhası, ikinci
/// satırda saat / pencere, şoför ve TR plakası; yoldakilerde tır rota çizgisinde ilerler; planlanan
/// litre çubuğu dolarak gelir. Kartlar art arda yükselerek gelir. Ayrıntı sayfasından Yola çıkar /
/// Teslim bildir / Şoför değiştir / İptal. Depo personeli listeyi "Bugünkü yüklemeler" ile açar;
/// planlama yetkisi olmayan "Planla" görmez.
class DispatchPage extends ConsumerStatefulWidget {
  const DispatchPage({super.key});

  @override
  ConsumerState<DispatchPage> createState() => _DispatchPageState();
}

class _DispatchPageState extends ConsumerState<DispatchPage> {
  late _Segment _segment = _initialSegment();

  /// Uygulanan son `?lane=` (aynı bağlantı tekrar uygulanmaz; elle seçim korunur).
  String? _linked;

  _Segment _initialSegment() {
    final access = ref.read(sessionControllerProvider).access;
    final depot = access?.bayiRoleCodes.contains(BayiRoleCodes.depot) ?? false;
    final g = ref.read(bayiGrantsProvider);
    if (!g.viewBoard) return _Segment.list;
    return depot ? _Segment.list : _Segment.board;
  }

  /// `?lane=` (v4 §3.5): plan / driver → pano; disputed → itirazlı sevkiyatlar; transit → yoldakiler;
  /// loadings → bugünkü yüklemeler.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lane = queryParamOf(context, 'lane');
    if (lane == _linked) return;
    _linked = lane;
    if (lane == null) return;
    // Sekmede uygulanan bağlantı adresten düşer (v4 tur 2): aynı göreve yeniden dokunmak yine
    // uygulanır (sekme son adresini hatırlar; aynı adres "uygulanmış" sayılırdı).
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeLink());
    final g = ref.read(bayiGrantsProvider);
    final list = ref.read(shipmentListProvider.notifier);
    switch (lane) {
      case 'plan' || 'driver' when g.viewBoard:
        _segment = _Segment.board;
      case 'disputed' when g.viewShipments:
        _segment = _Segment.list;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final f = ref.read(shipmentListProvider).filter;
          if (!f.hasDispute) list.toggleDisputes();
        });
      case 'transit' when g.viewShipments:
        _segment = _Segment.list;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final f = ref.read(shipmentListProvider).filter;
          if (!(f.statuses.length == 1 &&
              f.statuses.contains(ShipmentStatus.inTransit))) {
            list.toggleStatus(ShipmentStatus.inTransit);
          }
        });
      case 'loadings' when g.viewShipments:
        _segment = _Segment.list;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!ref.read(shipmentListProvider).filter.todayLoadings) {
            list.toggleTodayLoadings();
          }
        });
    }
  }

  /// Sekmedeki sayfada `?lane=` uygulanınca yalın adrese dönülür; itilen sayfaya dokunulmaz.
  void _consumeLink() {
    if (!mounted || !AknTabScope.isIn(context)) return;
    final router = GoRouter.of(context);
    final uri = router.state.uri;
    if (uri.path != AppRoutes.dispatch ||
        !uri.queryParameters.containsKey('lane')) {
      return;
    }
    _linked = null;
    router.go(AppRoutes.dispatch);
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
    // Durum satırı (v4 §3.2): "4 sipariş planlanmayı bekliyor".
    final toPlan = board.data?.orderTotal ?? 0;
    final Object? status = board.data == null
        ? null
        : toPlan > 0 && g.planShipment
        ? AknStatusClause.yourMove(
            '${Fmt.integer(toPlan)} sipariş planlanmayı bekliyor',
          )
        : toPlan > 0
        ? '${Fmt.integer(toPlan)} sipariş planlanmayı bekliyor'
        : 'Planlanacak sipariş yok';
    return AppScaffold(
      title: 'Sevkiyat',
      bandIcon: PhosphorIconsRegular.truck,
      status: status,
      refreshing: refreshing,
      body: Column(
        children: [
          if (segments.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: AknSegmented<_Segment>(
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

// ------------------------------------------------------------------ Ortak satır

/// Sevkiyat kartının sağ sütunu: küçük ADR levhası ve litre (`number` 24/30, tablo rakamları; birim
/// `readoutUnit`).
class _Liters extends StatelessWidget {
  const _Liters({required this.liters, this.product});

  final double liters;
  final String? product;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final adr = AdrPlate.forProduct(product, height: 22);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (adr != null) ...[adr, const SizedBox(width: 8)],
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text.rich(
              TextSpan(
                text: Fmt.number(liters, maxFraction: 3),
                style: t.number.copyWith(color: c.ink),
                children: [
                  TextSpan(
                    text: ' L',
                    style: t.readoutUnit.copyWith(color: c.ink),
                  ),
                ],
              ),
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ),
      ],
    );
  }
}

/// Sevkiyat ekranının kart içeriği: başlık + ikinci satır solda, [right] sağda (dar ekranda ya da
/// büyük yazıda başlığın altına iner), altında durum satırı, isteğe bağlı rota çizgisi ve eylem;
/// saat başlığın önünde Beton küçük hapta. Basınca Beton dolgu (kart da küçülür).
class _DispatchRow extends StatelessWidget {
  const _DispatchRow({
    required this.title,
    required this.subtitle,
    required this.right,
    required this.status,
    this.meta,
    this.footer,
    this.onTap,
    this.leadingTime,
  });

  final String title;
  final String subtitle;
  final Widget right;
  final Widget status;

  /// İkinci satırın altında kısa not satırı (TR plakası, şoför).
  final Widget? meta;
  final Widget? footer;
  final VoidCallback? onTap;

  /// Başlığın önünde saat ("09:00"), açık sevkiyatlarda.
  final String? leadingTime;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final large = isLargeText(context);
    final titleStyle = t.headline.copyWith(color: c.ink);
    final time = leadingTime;
    final titleText = Text.rich(
      TextSpan(
        children: [
          if (time != null) ...[
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.surfaceAlt,
                    borderRadius: AknRadius.tag,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 1,
                    ),
                    child: Text(
                      time,
                      style: t.label.copyWith(
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                        fontFeatures: AknNumerals.tabular,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          TextSpan(text: title),
        ],
      ),
      style: titleStyle,
      maxLines: large ? 4 : 2,
      overflow: TextOverflow.ellipsis,
    );
    final sub = Text(subtitle, style: t.bodySmall.copyWith(color: c.dim));
    final head = LayoutBuilder(
      builder: (context, constraints) {
        if (large || constraints.maxWidth < 300) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleText,
              const SizedBox(height: 4),
              right,
              const SizedBox(height: 4),
              sub,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [titleText, const SizedBox(height: 2), sub],
              ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.5),
              child: right,
            ),
          ],
        );
      },
    );
    Widget row = Padding(
      padding: kCardRowPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          head,
          if (meta != null) ...[const SizedBox(height: 6), meta!],
          const SizedBox(height: 8),
          status,
          if (footer != null) ...[const SizedBox(height: 10), footer!],
        ],
      ),
    );
    if (onTap != null) {
      row = Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: c.surfaceAlt,
          child: row,
        ),
      );
    }
    return row;
  }
}

/// Şoför ve plaka satırı: TR plakası, şoför adı, "uygulamada" ya da "Şoför hesabı yok".
class _DriverMeta extends StatelessWidget {
  const _DriverMeta({
    required this.plate,
    required this.driver,
    required this.inApp,
    required this.noAccount,
  });

  final String plate;
  final String driver;
  final bool inApp;
  final bool noAccount;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (plate.isNotEmpty) PlateBadge(plate: plate, fontSize: 12),
        if (driver.isNotEmpty)
          Text(driver, style: t.bodySmall.copyWith(color: c.ink)),
        if (inApp)
          const AknLamp(
            label: 'uygulamada',
            tone: AknTone.ok,
            size: AknLampSize.small,
          ),
        if (noAccount)
          const AknLamp(
            label: 'Şoför hesabı yok',
            tone: AknTone.warn,
            size: AknLampSize.small,
          ),
      ],
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
    final k = context.akn;
    final days = _groupByDay(b.shipments);
    String liters(double v) => Fmt.liters(v);
    // Kartlar art arda yükselir; aşağıdakiler kaydırdıkça kayarak girer.
    var n = 0;
    Widget card(Widget row) => StaggerItem(
      index: n++,
      child: BayiCard(margin: PagedListBody.cardMargin, child: row),
    );
    return StaggerScope(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          UpdatedCaption(updatedAt: state.updatedAt, error: state.error),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            // Okumalar ikişerli iki satırda (dört kart yan yana sıkışmasın); büyük yazıda en çok 1,5×.
            child: PlateClamp(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KpiRow(
                    children: [
                      // Web panelinin KPI kartları: simge karosu; sıra bayide (planlanacak)
                      // turuncu, sorun (sürücüsüz) uyarı tonunda.
                      KpiTile(
                        label: 'Planlanacak',
                        icon: PhosphorIconsRegular.calendarBlank,
                        tone: b.orderTotal > 0 ? AknTone.brand : null,
                        value: b.orderTotal,
                        caption: liters(b.orderTotalLiters),
                      ),
                      KpiTile(
                        label: 'Planlı',
                        icon: PhosphorIconsRegular.calendarCheck,
                        value: b.plannedCount,
                        caption: liters(b.plannedLiters),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  KpiRow(
                    children: [
                      KpiTile(
                        label: 'Yolda',
                        icon: PhosphorIconsRegular.truck,
                        value: b.inTransitCount,
                        caption: liters(b.inTransitLiters),
                      ),
                      KpiTile(
                        label: 'Sürücüsüz',
                        icon: PhosphorIconsRegular.steeringWheel,
                        tone: b.unassignedCount > 0 ? AknTone.warn : null,
                        value: b.unassignedCount,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (b.unassignedCount > 0)
            PageWell(
              top: 16,
              tone: AknTone.warn,
              icon: PhosphorIconsRegular.userFocus,
              message:
                  '${b.unassignedCount} planlı sevkiyatta uygulama şoförü yok; bu teslimatlar şoförün Teslimatlar listesinde görünmez. Ayrıntıdan "Şoför değiştir" ile atayın.',
            ),
          if (!g.planShipment)
            PageWell(
              top: 16,
              tone: AknTone.neutral,
              icon: PhosphorIconsRegular.eye,
              message: g.dispatchOrReport
                  ? 'Planlama yetkiniz yok; yola çıkarma ve teslim bildirme sevkiyat ayrıntısından yapılır.'
                  : 'Sevkiyatları görüntüleyebilirsiniz; değişiklik yetkiniz yok.',
            ),
          SectionHeader(title: 'Planlanacak siparişler', count: b.orderTotal),
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
              for (final o in b.ordersIn(bucket))
                card(
                  BoardOrderRow(
                    order: o,
                    canPlan: g.planShipment,
                    canOpen: g.viewOrders,
                  ),
                ),
            ],
          SectionHeader(title: 'Açık sevkiyatlar', count: b.shipments.length),
          if (b.shipments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Planlı ya da yolda sevkiyat yok.',
                style: t.bodySmall.copyWith(color: k.dim),
              ),
            ),
          for (final (title, rows) in days) ...[
            DayHeader(
              title,
              trailing:
                  '${rows.length} sevkiyat, ${liters(rows.fold<double>(0, (a, s) => a + s.plannedLiters))}',
            ),
            for (final s in rows) card(BoardShipmentLine(shipment: s)),
          ],
          if (b.shipmentsTruncated || b.earlierShipmentsTruncated)
            const ListFooterNote(
              'Liste sınırına ulaşıldı; tümü için "Sevkiyatlar" sekmesini kullanın.',
            ),
        ],
      ),
    );
  }

  /// "Önceki günler", "Bugün, 21 Ekim", "Yarın, 22 Ekim", gün adı.
  static List<(String, List<BoardShipment>)> _groupByDay(
    List<BoardShipment> rows,
  ) {
    final today = TrTime.todayStart();
    final groups = <String, List<BoardShipment>>{};
    for (final s in rows) {
      final at = s.scheduledAt;
      final key = at == null || at.isBefore(today)
          ? 'Önceki günler'
          : '${Fmt.dayLabel(at)}, ${dayMonthLong(at)}';
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
    final s = summary;
    return DayHeader(
      bucket.label,
      trailing: s == null
          ? null
          : '${s.count} sipariş, ${Fmt.liters(s.liters)}',
    );
  }
}

/// Pano: planlanacak sipariş satırı (cari ve nokta, kalan litre + ADR, pencere ve tank, "Planla").
class BoardOrderRow extends ConsumerWidget {
  const BoardOrderRow({
    super.key,
    required this.order,
    required this.canPlan,
    required this.canOpen,
  });

  final BoardOrder order;
  final bool canPlan;
  final bool canOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = order;
    final viewer = ref.watch(bayiGrantsProvider).viewer;
    final planned = o.quantityLiters - o.remainingLiters;
    final overdue = o.bucket == BoardBucket.overdue;
    final lamp = overdue
        ? const StatusLamp(
            tone: AknTone.danger,
            label: 'Teslim günü geçti',
            icon: PhosphorIconsRegular.clockCounterClockwise,
          )
        : AknStatus.lampFor(OrderStatus.approved, viewer);
    final notes = [
      if (o.window != null) 'Pencere ${o.window}',
      if (o.tankCapacityLiters != null)
        'tank ${Fmt.liters(o.tankCapacityLiters)}',
    ].join(', ');
    return _DispatchRow(
      title: o.customerTitle,
      subtitle: keepUnits(
        [
          o.orderNumber,
          o.productName,
          ?o.deliveryPointName,
          if (o.deliveryDate != null) '${_dayWord(o.deliveryDate!)} teslim',
        ].join(', '),
      ),
      right: _Liters(liters: o.remainingLiters, product: o.productName),
      meta: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (notes.isNotEmpty)
            RowNote(icon: PhosphorIconsRegular.clock, text: keepUnits(notes)),
          if (planned > 0) ...[
            if (notes.isNotEmpty) const SizedBox(height: 6),
            // Planlanan pay bir ilerlemedir: turuncu dolgu, mürekkep değer (v3); uyarı / tehlike
            // eşiği yok.
            BayiUsageBar(
              value: o.quantityLiters <= 0 ? 0 : planned / o.quantityLiters,
              label: 'Planlı',
              valueLabel:
                  '${Fmt.liters(planned)} / ${Fmt.liters(o.quantityLiters)}',
              warnAt: double.infinity,
              dangerAt: double.infinity,
              height: 6,
            ),
          ],
        ],
      ),
      status: AknStatusLine(
        lamp: AknLamp.status(lamp),
        trailing: canPlan
            ? AknButton.secondary(
                label: 'Planla',
                size: AknButtonSize.small,
                semanticLabel: '${o.orderNumber} için sevkiyat planla',
                onPressed: () =>
                    showPlanSheet(context, PlanTarget.fromBoard(o)),
              )
            : null,
      ),
      onTap: canOpen
          ? () => GoRouter.of(context).push(AppRoutes.bayiOrder(o.orderId))
          : null,
    );
  }
}

/// Pano sevkiyat satırı: saat, cari, nokta, litre + ADR; TR plakası, şoför ve "uygulamada" ya da
/// "Şoför hesabı yok"; durum lambası; yoldakilerde rota çizgisi.
class BoardShipmentLine extends ConsumerWidget {
  const BoardShipmentLine({super.key, required this.shipment});

  final BoardShipment shipment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = shipment;
    final viewer = ref.watch(bayiGrantsProvider).viewer;
    final window = BayiJson.windowLabel(s.windowStart, s.windowEnd);
    final noAccount = !s.hasDriverAccount && s.status == ShipmentStatus.planned;
    final semantic = [
      s.code,
      s.status.label,
      s.customerTitle,
      Fmt.liters(s.plannedLiters),
      if (s.scheduledAt != null) Fmt.time(s.scheduledAt),
      if (s.driverName.isNotEmpty) s.driverName,
      if (s.isAppDriver) 'uygulamada',
      if (!s.hasDriverAccount) 'şoför hesabı yok',
    ].join(', ');
    return Semantics(
      button: true,
      label: semantic,
      excludeSemantics: true,
      onTap: () => showShipmentSheet(context, s.id, code: s.code),
      child: _DispatchRow(
        leadingTime: s.scheduledAt == null ? null : Fmt.time(s.scheduledAt),
        title: s.customerTitle,
        subtitle: keepUnits(
          [
            ?s.deliveryPointName,
            s.productName,
            if (window != null) 'pencere $window',
          ].join(', '),
        ),
        right: _Liters(liters: s.plannedLiters, product: s.productName),
        meta: s.vehiclePlate.isEmpty && s.driverName.isEmpty && !noAccount
            ? null
            : _DriverMeta(
                plate: s.vehiclePlate,
                driver: s.driverName,
                inApp: s.isAppDriver,
                noAccount: noAccount,
              ),
        status: AknLamp.status(AknStatus.shipmentLamp(s.status, viewer)),
        footer: s.status == ShipmentStatus.inTransit
            ? TruckRoute(
                moving: true,
                semanticLabel:
                    'Yolda. ${s.deliveryPointName ?? s.customerTitle}',
              )
            : null,
        onTap: () => showShipmentSheet(context, s.id, code: s.code),
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
    final k = context.akn;
    final today = TrTime.todayStart();
    final ranged = f.scheduledFrom != null || f.scheduledTo != null;
    // Çipler, arama ve özet listeyle birlikte kayar (küçük ekranda / büyük yazıda liste sıkışmaz).
    final header = <Widget>[
      const SizedBox(height: 4),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            AknChip(
              label: 'Bugünkü yüklemeler',
              selected: f.todayLoadings,
              onTap: c.toggleTodayLoadings,
            ),
            const SizedBox(width: 8),
            for (final st in statuses) ...[
              AknChip(
                label: st.label,
                count: counts?.countOf(st),
                selected:
                    !f.todayLoadings &&
                    f.statuses.length == 1 &&
                    f.statuses.contains(st),
                onTap: () => c.toggleStatus(st),
              ),
              const SizedBox(width: 8),
            ],
            AknChip(
              label: 'İtiraz geçmişi',
              semanticLabel: 'İtiraz kaydı olan sevkiyatlar',
              selected: f.hasDispute,
              onTap: c.toggleDisputes,
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: SearchField(
          hint: 'Sevkiyat no, sipariş no, plaka ya da şoför',
          controller: _search,
          onChanged: c.setSearch,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          children: [
            if (f.todayLoadings || ranged)
              Text(
                f.todayLoadings
                    ? 'Bugün (${dayMonthLong(today)}) planlanan ve yoldaki sevkiyatlar, yükleme sırasıyla'
                    : 'Plan tarihi ${Fmt.date(f.scheduledFrom)}–${Fmt.date(f.scheduledTo)}',
                style: t.label.copyWith(
                  fontWeight: FontWeight.w400,
                  color: k.dim,
                ),
              ),
            AknInlineLink(
              label: f.todayLoadings || ranged
                  ? BayiCopy.clearFilters
                  : 'Tarih aralığı seç',
              onTap: f.todayLoadings || ranged
                  ? _clear
                  : () => _pickRange(context),
            ),
          ],
        ),
      ),
    ];
    return PagedListBody<ShipmentListItem>(
      list: s.list,
      header: header,
      // Süzgeç değişince kartlar yeniden art arda gelir (aramada değil).
      staggerKey: (
        f.todayLoadings,
        f.hasDispute,
        Object.hashAllUnordered(f.statuses),
        f.scheduledFrom,
        f.scheduledTo,
      ),
      onRefresh: () => c.reload(silent: true),
      onLoadMore: () => unawaited(c.loadMore()),
      filtered: f.isFiltered && !f.todayLoadings,
      onClearFilters: _clear,
      empty: EmptyState(
        title: f.todayLoadings
            ? BayiCopy.todayLoadingsEmpty
            : BayiCopy.shipmentsEmptyTitle,
        message: f.todayLoadings
            ? BayiCopy.todayLoadingsEmptyMessage
            : BayiCopy.shipmentsEmptyMessage,
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

/// Sevkiyat listesi kartı (tasarım v3; kartı [PagedListBody] çizer): cari, sevkiyat ve sipariş
/// numarası, ürün; litre + ADR; plan zamanı, nokta; TR plakası ve şoför; durum çipi; itiraz notu.
class ShipmentListCard extends ConsumerWidget {
  const ShipmentListCard({super.key, required this.item});

  final ShipmentListItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.aknText;
    final k = context.akn;
    final s = item;
    final viewer = ref.watch(bayiGrantsProvider).viewer;
    final diff = s.differenceLiters;
    return _DispatchRow(
      title: s.customerName,
      subtitle: keepUnits(
        [
          s.code,
          s.orderNumber,
          s.productName,
          if (diff != null && diff.abs() >= 0.001) 'fark ${Fmt.liters(diff)}',
        ].join(', '),
      ),
      right: _Liters(
        liters: s.deliveredLiters ?? s.plannedLiters,
        product: s.productName,
      ),
      meta: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            [
              'Plan ${whenOf(s.scheduledAt)}',
              ?s.deliveryPointName,
              if (s.deliveryDocumentNo != null)
                'irsaliye ${s.deliveryDocumentNo}',
            ].join(', '),
            style: t.bodySmall.copyWith(color: k.dim),
          ),
          if (s.vehiclePlate.isNotEmpty || s.driverName.isNotEmpty) ...[
            const SizedBox(height: 6),
            _DriverMeta(
              plate: s.vehiclePlate,
              driver: s.driverName,
              inApp: false,
              noAccount: false,
            ),
          ],
        ],
      ),
      status: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          AknLamp.status(AknStatus.shipmentLamp(s.status, viewer)),
          if (s.disputeNote != null) ...[
            const SizedBox(height: 4),
            Text(
              s.disputeNote!,
              style: t.bodySmall.copyWith(color: k.ink),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
      footer: s.status == ShipmentStatus.inTransit
          ? TruckRoute(
              moving: true,
              semanticLabel: 'Yolda. ${s.deliveryPointName ?? s.customerName}',
            )
          : null,
      onTap: () => showShipmentSheet(context, s.id, code: s.code),
    );
  }
}

/// "bugün", "yarın", "dün" ya da "22 Ekim".
String _dayWord(DateTime at) => switch (TrTime.dayDiff(TrTime.now(), at)) {
  0 => 'bugün',
  1 => 'yarın',
  -1 => 'dün',
  _ => dayMonthLong(at),
};

/// "bugün 09:00", "dün 14:20", "23 Eki 08:30".
String whenOf(DateTime? at) {
  if (at == null) return Fmt.dash;
  final diff = TrTime.dayDiff(TrTime.now(), at);
  final time = Fmt.time(at);
  if (diff == 0) return 'bugün $time';
  if (diff == 1) return 'yarın $time';
  if (diff == -1) return 'dün $time';
  return '${Fmt.dayMonth(at)} $time';
}

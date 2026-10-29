import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/models.dart';
import '../../../../core/routing/app_location.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../application/bayi_grants.dart';
import '../../application/orders_controller.dart';
import '../../copy.dart';
import '../../data/order_models.dart';
import '../widgets/bayi_widgets.dart';
import '../widgets/paged_list_body.dart';
import 'order_filters_sheet.dart';

/// Siparişler (tasarım v4 "Sade" §5 06).
///
/// * Bant: "Siparişler", canlı durum satırı ("4 sipariş teklifinizi bekliyor": altındaki "Teklif
///   bekleyen 4" çipiyle aynı sayı), ⌕ (arama şeridi bandın altında açılır) ve Filtre (durum, ödeme,
///   finans, cari, tarih, sıralama; rozet açık filtre sayısı).
/// * Tek çip satırı: Tümü, sonra sayısı sıfırdan büyük her segment akış sırasıyla ("Müşteri
///   kararında"); açılışta Teklifler alt menüdeyse Tümü, değilse "Teklif bekleyen"
///   ([BayiOrdersController.defaultSegment]); `?segment=` derin bağlantısı segmenti seçer.
/// * Liste tek bir defter kartı: iki satırlık satırlar (müşteri + litre; ürün · nokta + geri sayım ya
///   da teslim günü); yalnızca Tümü'de üçüncü satır sipariş akışı (» noktaları + cümle). 3 saatten
///   uzak geri sayım soluk; çip, ödeme satırı ve sipariş no yok (arama numarayı yine bulur).
class BayiOrdersPage extends ConsumerStatefulWidget {
  const BayiOrdersPage({super.key});

  @override
  ConsumerState<BayiOrdersPage> createState() => _BayiOrdersPageState();
}

class _BayiOrdersPageState extends ConsumerState<BayiOrdersPage> {
  late final TextEditingController _search;
  late bool _searching;

  /// Uygulanan son `?segment=` (aynı bağlantı tekrar uygulanmaz; elle seçim korunur).
  String? _linked;

  @override
  void initState() {
    super.initState();
    final q = ref.read(bayiOrdersProvider).filter.q;
    _search = TextEditingController(text: q);
    _searching = q.trim().isNotEmpty;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final param = queryParamOf(context, 'segment');
    if (param == _linked) return;
    _linked = param;
    final seg = param == null
        ? null
        : param == 'all'
        ? null
        : BayiOrderSegment.fromKey(param);
    if (param == null || (seg == null && param != 'all')) return;
    // Sağlayıcı kurulum sırasında değiştirilmez: kare çizildikten sonra.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(bayiOrdersProvider.notifier).setSegment(seg);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _closeSearch() {
    if (!_searching) return;
    setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(bayiOrdersProvider);
    final c = ref.read(bayiOrdersProvider.notifier);
    final g = ref.watch(bayiGrantsProvider);
    final f = s.filter;
    final counts = s.counts;
    final segments = [
      for (final seg in BayiOrderSegment.values)
        if (counts == null || counts.of(seg) > 0 || f.segment == seg) seg,
    ];
    final advanced = f.advancedCount;
    // Durum satırı altındaki çiple aynı sayıyı söyler: "4 sipariş teklifinizi bekliyor" =
    // "Teklif bekleyen 4" (revize istenenlerin kendi çipi var, v4 §3.2).
    final quotes = counts?.of(BayiOrderSegment.awaitingQuote) ?? 0;
    final revisions = counts?.of(BayiOrderSegment.revisionRequested) ?? 0;
    final toPlan = counts?.of(BayiOrderSegment.toPlan) ?? 0;
    Object? status;
    if (g.quoteOnOrder && quotes > 0) {
      status = AknStatusClause.yourMove(
        '${Fmt.integer(quotes)} sipariş teklifinizi bekliyor',
      );
    } else if (g.quoteOnOrder && revisions > 0) {
      status = AknStatusClause.yourMove(
        '${Fmt.integer(revisions)} siparişte revize istendi',
      );
    } else if (g.planShipment && toPlan > 0) {
      status = AknStatusClause.yourMove(
        '${Fmt.integer(toPlan)} sipariş planlanmayı bekliyor',
      );
    } else if (counts != null) {
      status = 'Bekleyen işiniz yok';
    }
    final all = f.segment == null;
    final query = f.q.trim();
    return AppScaffold(
      title: 'Siparişler',
      bandIcon: PhosphorIconsRegular.receipt,
      status: status,
      refreshing: s.list.refreshing,
      actions: [
        AknSearchReveal.button(
          semanticLabel: 'Sipariş ara',
          onPressed: () => setState(() => _searching = true),
        ),
        AknFilterButton(
          count: advanced,
          onPressed: () => showOrderFiltersSheet(context),
        ),
      ],
      body: Column(
        children: [
          AknSearchReveal(
            open: _searching,
            controller: _search,
            hint: 'Müşteri, ürün ya da sipariş ara',
            onChanged: c.setQuery,
            onClose: _closeSearch,
          ),
          Expanded(
            child: PagedListBody<BayiOrderRow>(
              list: s.list,
              ledger: true,
              header: [
                const SizedBox(height: 4),
                FilterChips<BayiOrderSegment?>(
                  allowEmpty: false,
                  options: [
                    const FilterOption<BayiOrderSegment?>(
                      value: null,
                      label: 'Tümü',
                    ),
                    for (final seg in segments)
                      FilterOption<BayiOrderSegment?>(
                        value: seg,
                        label: seg.label,
                        count: counts?.of(seg),
                      ),
                  ],
                  selected: {f.segment},
                  onChanged: (v) => c.setSegment(v.first),
                ),
                if (advanced > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      children: [
                        Text(
                          _describe(f),
                          style: context.aknText.label.copyWith(
                            color: context.akn.dim,
                            fontWeight: FontWeight.w400,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        AknInlineLink(
                          label: BayiCopy.clearFilters,
                          onTap: () => c.setFilter(f.clearAdvanced()),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
              ],
              onRefresh: () => c.refresh(silent: true),
              onLoadMore: () => unawaited(c.loadMore()),
              filtered: f.isFiltered,
              query: query,
              onClearFilters: () {
                _search.clear();
                _closeSearch();
                c.clearAll();
              },
              empty: const EmptyState(
                compact: true,
                title: BayiCopy.ordersEmptyTitle,
                message: BayiCopy.ordersEmptyMessage,
                illustration: AknIllustration.orders,
              ),
              footer: all && advanced == 0 && query.isEmpty
                  ? const ListFooterNote(
                      'Tamamlanan ve iptal edilen siparişleri Filtre ile bulabilirsiniz.',
                    )
                  : null,
              // Segment değişince satırlar yeniden akar (aramada değil: yazarken liste zıplamaz).
              staggerKey: f.segment,
              itemBuilder: (context, row, _) =>
                  BayiOrderCard(row: row, flow: all),
            ),
          ),
        ],
      ),
    );
  }

  static String _describe(BayiOrdersFilter f) => [
    if (f.statuses.isNotEmpty) f.statuses.map((s) => s.label).join(', '),
    if (f.paymentStatus != null)
      'ödeme ${TurkishText.lower(f.paymentStatus!.label)}',
    if (f.financeStatus != null) TurkishText.lower(f.financeStatus!.label),
    if (f.customerId != null) f.customerTitle ?? 'Cari #${f.customerId}',
    if (f.createdFrom != null || f.createdTo != null)
      'oluşturulma ${Fmt.date(f.createdFrom)}–${Fmt.date(f.createdTo)}',
    if (f.requestedFrom != null || f.requestedTo != null)
      'teslim ${Fmt.date(f.requestedFrom)}–${Fmt.date(f.requestedTo)}',
    if (f.sort != BayiOrderSort.created) TurkishText.lower(f.sort.label),
  ].join(', ');
}

/// Siparişin satırdaki sevkiyat durumu (lamba için): kısmi teslim ve sevkiyatsız durumda yok.
ShipmentStatus? bayiShipmentStatus(BayiShipmentState s) => switch (s) {
  BayiShipmentState.planned => ShipmentStatus.planned,
  BayiShipmentState.inTransit => ShipmentStatus.inTransit,
  BayiShipmentState.reported => ShipmentStatus.reported,
  BayiShipmentState.disputed => ShipmentStatus.disputed,
  BayiShipmentState.delivered => ShipmentStatus.accepted,
  BayiShipmentState.partial || BayiShipmentState.none => null,
};

/// Satıra sığan ürün adı: "Kurşunsuz Benzin 95" → "Kurşunsuz 95".
String shortProduct(String name) =>
    name.replaceFirst(RegExp(r'\s+[Bb]enzin(?=\s+\d)'), '').trim();

/// Siparişin izleyene göre durumu: finans kararı bekleyen açık sipariş finansın; diğerleri izleyiciye
/// göre (§10.3).
StatusLamp bayiOrderLamp(BayiOrderRow r, StatusViewer viewer) {
  final toPlan = r.status == OrderStatus.approved && r.remainingLiters > 0;
  final shipment = toPlan ? null : bayiShipmentStatus(r.shipmentState);
  if (r.financeStatus.isAwaitingDecision && r.status.isOpen) {
    return StatusLamp(
      tone: r.financeStatus.statusStyle.tone,
      label: r.financeLabel ?? r.financeStatus.label,
      icon: r.financeStatus.statusStyle.icon,
      stage: AknStage.teklif,
    );
  }
  return AknStatus.lampFor(
    r.status,
    viewer,
    serverLabel: r.statusLabel,
    shipment: shipment,
  );
}

/// Sipariş satırı (v4 §5 06; satır defter kartının bir dilimi, kartı [PagedListBody] çizer):
///
/// ```
/// Körfez Nakliyat ve Ticaret                               10.000 L
/// Motorin · Körfez Garaj                                   ⏱ 41 dk
/// ━━[»]┄┄┄┄  Teklif verin                    (yalnızca Tümü, [flow])
/// ```
///
/// Geri sayım 3 saatten uzaksa soluk; 3 saat ve altında sıra sizdeyse Pas, 30 dakika ve altında
/// kırmızı. Geri sayım yoksa teslim günü ya da planlanacak kalan litre. Hap yalnızca istisnada
/// (karşılıksız ödeme). Satırda döngü yok.
class BayiOrderCard extends ConsumerWidget {
  const BayiOrderCard({super.key, required this.row, this.flow = false});

  final BayiOrderRow row;

  /// Üçüncü satır: sipariş akışı (» noktaları + cümle); yalnızca Tümü'de.
  final bool flow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = row;
    final viewer = ref.watch(bayiGrantsProvider).viewer;
    final c = context.akn;
    final t = context.aknText;
    final expires = r.expiresAt;
    final open = r.status.isOpen;
    final financeWait = r.financeStatus.isAwaitingDecision;
    final showCountdown =
        open &&
        !financeWait &&
        expires != null &&
        expires.isAfter(DateTime.now().toUtc());
    final toPlan = r.status == OrderStatus.approved && r.remainingLiters > 0;
    final lamp = bayiOrderLamp(r, viewer);

    Widget? meta;
    String? metaText;
    if (showCountdown) {
      meta = CountdownBadge(
        deadline: expires,
        yourMove: lamp.yourMove,
        compact: true,
        subject: 'Sipariş',
      );
    } else if (toPlan) {
      metaText = 'Kalan ${Fmt.liters(r.remainingLiters)}';
    } else if (r.requestedDeliveryDate != null && open) {
      metaText = '${dayMonthLong(r.requestedDeliveryDate!)} teslim';
    }
    if (metaText != null) {
      meta = Text(
        keepUnits(metaText),
        style: t.label.copyWith(
          fontWeight: FontWeight.w500,
          color: c.dim,
          fontFeatures: AknNumerals.tabular,
        ),
      );
    }

    final place = r.deliveryPointName ?? r.deliveryCity;
    final product = r.productName == null ? null : shortProduct(r.productName!);
    final subtitle = [?product, ?place].join(' · ');
    // Revize istenen siparişte bayinin işi teklifi yenilemek: cümle bunu söyler.
    final sentence = r.status == OrderStatus.revisionRequested && lamp.yourMove
        ? 'Teklifi yenileyin'
        : lamp.label;
    final bounced = r.paymentStatus == PaymentStatus.bounced;
    // P5: cümle yalnızca iş 3 saat içinde dolacaksa Pas (geri sayım gibi); değilse satır
    // mürekkep, » sakin.
    final urgent =
        showCountdown &&
        expires.difference(DateTime.now().toUtc()) <= const Duration(hours: 3);
    return AknListTile(
      title: r.customerTitle ?? Fmt.dash,
      subtitle: subtitle.isEmpty ? null : subtitle,
      amount: Fmt.liters(r.quantityLiters),
      metaWidget: meta,
      flow: flow
          ? AknFlowPips(
              flow: AknFlow.bayi(lamp),
              sentence: sentence,
              urgent: urgent,
            )
          : null,
      status: bounced
          ? const AknLamp(label: 'Ödeme karşılıksız', tone: AknTone.danger)
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      semanticLabel: [
        r.customerTitle ?? '',
        Fmt.liters(r.quantityLiters),
        ?r.productName,
        ?place,
        sentence,
        ?metaText,
        if (showCountdown)
          'süre ${Fmt.countdown(expires.difference(DateTime.now().toUtc()))}',
        if (bounced) 'ödeme karşılıksız',
      ].where((p) => p.isNotEmpty).join(', '),
      onTap: () => GoRouter.of(context).push(AppRoutes.bayiOrder(r.id)),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/models.dart';
import '../../../../core/offline/connectivity.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../application/bayi_actions.dart';
import '../../application/bayi_grants.dart';
import '../../application/desk_controller.dart';
import '../../application/orders_controller.dart';
import '../../data/order_models.dart';
import '../dispatch/plan_sheet.dart';
import '../dispatch/shipment_sheet.dart';
import '../widgets/bayi_widgets.dart';
import '../widgets/paged_list_body.dart';
import 'quote_sheet.dart';

/// Sipariş ayrıntısı (bayi; tasarım v3 "Akış"): itilen başlıkta sipariş numarası; nesne başlığı
/// ("Motorin, 8.000 L"), cari ve teslim satırı; durum kartı (aşama şeridi, izleyiciye göre durum çipi —
/// durum değişince solup büyüyerek yenilenir — ve geri sayım, yoldaysa tır rota çizgisinde); **kahraman
/// kart** = bayinin teklifi (teklif yoksa tahmini tutar; yükselerek gelir); ödeme kartı; Teslimat, Cari,
/// Sevkiyatlar, Teklif geçmişi ve Sipariş akışı beyaz kartlarda, art arda yükselerek. Alt çubukta
/// yetkiye göre Teklif ver / Teklifi güncelle, Sevkiyat planla, Tamamla (spec A.1).
class BayiOrderDetailPage extends ConsumerWidget {
  const BayiOrderDetailPage({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bayiOrderProvider(orderId));
    final c = ref.read(bayiOrderProvider(orderId).notifier);
    final bundle = state.data;
    final g = ref.watch(bayiGrantsProvider);
    final blocked = g.viewDesk
        ? ref.watch(
            quoteDeskProvider.select((s) => s.header?.quotingBlocked ?? false),
          )
        : false;
    final actions = bundle == null
        ? const <_OrderAction>{}
        : _availableActions(g, bundle, quotingBlocked: blocked);
    return AppScaffold(
      title: bundle?.order.orderNumber ?? 'Sipariş',
      refreshing: state.refreshing,
      actionBar: actions.isEmpty
          ? null
          : _Actions(bundle: bundle!, actions: actions),
      body: LoadableBody<BayiOrderBundle>(
        state: state,
        onRetry: c.refresh,
        builder: (context, b) => PullToRefresh(
          onRefresh: c.refresh,
          child: _Body(bundle: b),
        ),
      ),
    );
  }
}

/// Siparişin şu anki sevkiyat durumu (lamba ve aşama şeridi için): planlanacak litre varken yok
/// (sipariş "Sevkiyat planlayın" der); yoksa en çok ilgi isteyen sevkiyat.
ShipmentStatus? orderShipmentStatus(BayiOrderBundle b) {
  final f = b.fulfillment;
  final o = b.order;
  if (f == null || f.shipments.isEmpty) return null;
  if (o.status == OrderStatus.approved && b.remainingLiters > 0) return null;
  const order = [
    ShipmentStatus.disputed,
    ShipmentStatus.reported,
    ShipmentStatus.inTransit,
    ShipmentStatus.planned,
    ShipmentStatus.accepted,
  ];
  for (final s in order) {
    if (f.shipments.any((x) => x.status == s)) return s;
  }
  return null;
}

extension on OrderFinanceStatus {
  /// Finans onayı verilmiş (koşulsuz ya da koşullu): ayrı uyarı kutusu değil, ödeme satırının altında
  /// tek satır.
  bool get isSettled =>
      this == OrderFinanceStatus.approved ||
      this == OrderFinanceStatus.conditionallyApproved;
}

/// "bugün 10:05", "dün 14:20", "21 Eki 09:10".
String whenShort(DateTime? at) {
  if (at == null) return Fmt.dash;
  final diff = TrTime.dayDiff(TrTime.now(), at);
  final time = Fmt.time(at);
  if (diff == 0) return 'bugün $time';
  if (diff == -1) return 'dün $time';
  return '${Fmt.dayMonth(at)} $time';
}

class _Body extends ConsumerWidget {
  const _Body({required this.bundle});

  final BayiOrderBundle bundle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = bundle.order;
    final t = context.aknText;
    final c = context.akn;
    final g = ref.watch(bayiGrantsProvider);
    final q = o.currentQuote;
    final openStatus = o.status.isOpen;
    // Geri sayım yalnızca süre dolumu açıkken (masa başlığı `expiryEnabled`; masayı göremeyen göstermez).
    final expiryOn =
        g.viewDesk &&
        ref.watch(quoteDeskProvider.select((s) => s.expiryEnabled));
    final expires = expiryOn ? o.expiresAt : null;
    final finance = o.financeStatus;
    final financeWait = finance.isAwaitingDecision && openStatus;
    final completionHint = bundle.fulfillment?.completionHint;
    final lamp = financeWait
        ? StatusLamp(
            tone: finance.statusStyle.tone,
            label: finance.label,
            icon: finance.statusStyle.icon,
            stage: AknStage.teklif,
          )
        : AknStatus.lampFor(
            o.status,
            g.viewer,
            serverLabel: o.statusLabel,
            shipment: orderShipmentStatus(bundle),
          );
    final stages = [for (final s in AknStage.stops()) s.label];
    final stageIndex = lamp.complete
        ? stages.length
        : (lamp.stageIndex() ?? 0).clamp(0, stages.length - 1);
    final showCountdown =
        openStatus &&
        expires != null &&
        expires.isAfter(DateTime.now().toUtc());
    final requested = o.requestedDeliveryDate;

    // Kartlar art arda yükselir; aşağıdakiler kaydırdıkça kayarak girer.
    var n = 0;
    Widget stagger(Widget child) => StaggerItem(index: n++, child: child);
    return StaggerScope(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          // Nesne başlığı (§6.1): "Motorin, 8.000 L" + cari + nokta ve teslim günü.
          FadeUp(
            offset: 10,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              // Web panelinin sayfa bandı: açık turuncu zemin, simge karosu; üst satırda cari,
              // başlık ve tek satırlık açıklama (nokta ve teslim günü).
              child: DecoratedBox(
                decoration: AknPageBand.decorationOf(c),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AknPageBand.tileOf(context, PhosphorIconsRegular.drop),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              o.customerTitle,
                              style: t.caption.copyWith(
                                fontWeight: FontWeight.w600,
                                color: c.brandInk,
                              ),
                            ),
                            // Nesne başlığı büyük yazıda en çok 1,5× (kök başlıklar gibi); kalan
                            // metin ölçeklenir.
                            MediaQuery.withClampedTextScaling(
                              maxScaleFactor: 1.5,
                              child: Semantics(
                                header: true,
                                child: Text(
                                  keepUnits(
                                    '${o.productName}, ${Fmt.liters(o.quantityLiters)}',
                                  ),
                                  style: t.display.copyWith(
                                    fontSize: 24,
                                    height: 30 / 24,
                                    color: c.ink,
                                    fontFeatures: AknNumerals.tabular,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 1),
                                  child: Icon(
                                    PhosphorIconsRegular.mapPin,
                                    size: 16,
                                    color: c.dim,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    [
                                      o.deliveryPointName,
                                      if (requested != null)
                                        '${dayMonthLong(requested)} ${Fmt.weekday(requested)} teslim',
                                    ].join(', '),
                                    style: t.label.copyWith(
                                      fontWeight: FontWeight.w500,
                                      color: c.dim,
                                    ),
                                  ),
                                ),
                              ],
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
          // Durum kartı: aşama şeridi, durum çipi ve geri sayım, yoldaysa rota çizgisi.
          stagger(
            SectionCard(
              margin: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StageStrip(
                    stages: stages,
                    current: stageIndex,
                    yourMove: lamp.yourMove,
                    problem: lamp.problem ? StageProblem.rejected : null,
                    // Büyük yazıda tek satır özet ("Aşama 3 / 6: Karar"); geçmişin tamamı "Sipariş
                    // akışı"nda.
                    fallback: StageStripFallback.compact,
                  ),
                  const SizedBox(height: 16),
                  _StateSwap(
                    child: AknStatusLine(
                      key: ValueKey(lamp.label),
                      lamp: AknLamp.status(lamp),
                      trailing: showCountdown
                          ? CountdownBadge(
                              deadline: expires,
                              yourMove: lamp.yourMove,
                              subject: 'Sipariş',
                            )
                          : null,
                    ),
                  ),
                  if (lamp.stage == AknStage.yolda) ...[
                    const SizedBox(height: 12),
                    TruckRoute(
                      moving: true,
                      destinationLabel: o.deliveryPointName,
                      semanticLabel: 'Yolda. ${o.deliveryPointName}',
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (finance != OrderFinanceStatus.notRequired && !finance.isSettled)
            PageWell(
              top: 12,
              tone: finance.statusStyle.tone,
              icon: finance.statusStyle.icon,
              title: finance.label,
              message:
                  o.financeReasons ??
                  (finance.isAwaitingDecision
                      ? 'Finans kararı gelene kadar teklif verilemez.'
                      : 'Finans değerlendirmesi tamamlandı.'),
              actionLabel: o.financeApprovalRequestId != null && g.viewApprovals
                  ? 'Onay talebini aç'
                  : null,
              onAction: o.financeApprovalRequestId != null && g.viewApprovals
                  ? () => GoRouter.of(
                      context,
                    ).push(AppRoutes.approval(o.financeApprovalRequestId!))
                  : null,
            ),
          // Kahraman kart: bayinin teklifi, ilk açılışta yükselip büyüyerek gelir.
          FadeUp(
            offset: 24,
            scale: 0.94,
            duration: AknMotion.heroRise,
            curve: AknMotion.emphasizedCurve,
            child: _QuotePlate(order: o),
          ),
          if (q?.revisionNote != null)
            PageWell(
              top: 12,
              tone: AknTone.info,
              icon: PhosphorIconsRegular.chatCircle,
              title: 'Carinin revize notu',
              message: q!.revisionNote!,
            ),
          stagger(
            SectionCard(
              margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PaymentLine(order: o, canOpen: g.viewPayments),
                  if (finance.isSettled) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color: c.lineSoft,
                      ),
                    ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _GlyphTile(
                          icon: PhosphorIconsRegular.shieldCheck,
                          color: c.ok.fg,
                          fill: c.ok.bg,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '${finance.label}.${o.financeReasons == null ? '' : ' ${o.financeReasons}'}',
                              style: t.body.copyWith(color: c.ink),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (o.quotes.length > 1)
            stagger(
              GroupCard(
                title: 'Teklif geçmişi',
                child: _Facts(
                  children: [
                    for (final v in [
                      ...o.quotes,
                    ]..sort((a, b) => b.version.compareTo(a.version)))
                      FactRow(
                        label: 'v${v.version}, ${whenShort(v.createdAt)}',
                        value:
                            '${Fmt.unitPrice(v.unitPriceTry)}${v.id == q?.id ? ' (güncel)' : ''}',
                        valueStyle: const TextStyle(
                          fontFeatures: AknNumerals.tabular,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          stagger(
            GroupCard(
              title: 'Teslimat',
              child: _Facts(
                children: [
                  FactRow(label: 'Nokta', value: o.deliveryPointName),
                  if (o.deliveryAddress.isNotEmpty)
                    FactRow(label: 'Adres', value: o.deliveryAddress),
                  FactRow(
                    label: 'İstenen teslim',
                    value: Fmt.longDate(o.requestedDeliveryDate),
                  ),
                  if (q?.deliveryDate != null)
                    FactRow(
                      label: 'Teklif teslim günü',
                      value: Fmt.longDate(q!.deliveryDate),
                    ),
                  FactRow(
                    label: 'Oluşturuldu',
                    value: Fmt.dateTime(o.createdAt),
                  ),
                ],
              ),
            ),
          ),
          if (g.viewCustomers)
            stagger(
              GroupCard(
                title: 'Cari',
                padding: const EdgeInsets.only(bottom: 4),
                child: AknListTile(
                  leading: _GlyphTile(
                    icon: PhosphorIconsRegular.buildings,
                    color: c.ink,
                    fill: c.surfaceAlt,
                  ),
                  title: o.customerTitle,
                  subtitle: 'Cari kartı: limit, açık siparişler, notlar',
                  showChevron: true,
                  padding: const EdgeInsets.fromLTRB(18, 8, 14, 10),
                  onTap: () => GoRouter.of(
                    context,
                  ).push(AppRoutes.customer(o.customerId)),
                ),
              ),
            ),
          // Kısmi teslim kabul edildi, açık sevkiyat yok: siparişin neden kapanmadığı ve ne
          // yapılacağı (web "Sipariş henüz tamamlanmadı" uyarısı). "Tamamla" çağrısı yalnızca
          // tamamlayabilene.
          if (o.status == OrderStatus.approved &&
              completionHint != null &&
              (!bundle.fulfillment!.invitesCompletion || g.completeOrder))
            PageWell(
              top: 16,
              tone: AknTone.info,
              icon: PhosphorIconsRegular.info,
              title: 'Sipariş henüz tamamlanmadı',
              message: completionHint,
            ),
          stagger(_ShipmentsSection(bundle: bundle)),
          if (bundle.timeline.isNotEmpty || bundle.timelineFailed)
            stagger(
              GroupCard(
                title: 'Sipariş akışı',
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 14),
                child: bundle.timelineFailed
                    ? Text(
                        'Sipariş akışı yüklenemedi. Sayfayı aşağı çekerek yenileyin.',
                        style: t.bodySmall.copyWith(color: c.dim),
                      )
                    : StepTimeline(
                        yourMove: lamp.yourMove,
                        steps: _steps(
                          o,
                          bundle.timeline,
                          large: isLargeText(context),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  /// Büyük yazı ölçeğinde zaman başlığın yanında değil alt satırda (çekirdek satırda esnemez).
  static List<TimelineStep> _steps(
    OrderDetail o,
    List<OrderTimelineItem> items, {
    required bool large,
  }) {
    final out = <TimelineStep>[];
    for (var i = 0; i < items.length; i++) {
      final e = items[i];
      final last = i == items.length - 1;
      final state = switch (e.toStatus) {
        OrderStatus.rejected => TimelineState.failed,
        OrderStatus.expired => TimelineState.warning,
        _ when last && o.status.isOpen => TimelineState.current,
        _ => TimelineState.done,
      };
      final time = e.changedAt == null ? null : whenShort(e.changedAt);
      final below = [if (large && time != null) time, ?e.note];
      out.add(
        TimelineStep(
          title: e.toStatus.label,
          subtitle: below.isEmpty ? null : below.join('\n'),
          time: large ? null : time,
          state: state,
        ),
      );
    }
    return out;
  }
}

/// Kart içi olgular: etiket / değer satırları, aralarında ince çizgi (`lineSoft`).
class _Facts extends StatelessWidget {
  const _Facts({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0)
          Divider(height: 1, thickness: 1, color: context.akn.lineSoft),
        children[i],
      ],
    ],
  );
}

/// 36 px yuvarlak köşeli simge karosu (kart satırlarının önü).
class _GlyphTile extends StatelessWidget {
  const _GlyphTile({
    required this.icon,
    required this.color,
    required this.fill,
  });

  final IconData icon;
  final Color color;
  final Color fill;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AknRadius.sm),
      ),
      child: Icon(icon, size: 19, color: color),
    ),
  );
}

/// Durum değişiminde içerik solup büyüyerek yenilenir (v3 §5); hareket azaltmada doğrudan.
class _StateSwap extends StatelessWidget {
  const _StateSwap({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: AknMotion.of(context, AknMotion.base),
    switchInCurve: AknMotion.standard,
    switchOutCurve: AknMotion.exit,
    layoutBuilder: (current, previous) => Stack(
      alignment: AlignmentDirectional.topStart,
      children: [...previous, ?current],
    ),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        alignment: AlignmentDirectional.centerStart.resolve(
          Directionality.of(context),
        ),
        scale: animation.drive(Tween<double>(begin: 0.92, end: 1)),
        child: child,
      ),
    ),
    child: child,
  );
}

/// Ekranın tek plakası (§5.2): bayinin teklifi — toplam (`338.800` + `,00 ₺`), kural, Birim fiyat /
/// Miktar / Teslim. Teklif yokken tahmini tutar (varsa); ikisi de yoksa düz bir not.
class _QuotePlate extends StatelessWidget {
  const _QuotePlate({required this.order});

  final OrderDetail order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final q = o.currentQuote;
    final t = context.aknText;
    final c = context.akn;
    const margin = EdgeInsets.fromLTRB(20, 16, 20, 0);
    if (q == null && o.estimatedAmount == null) {
      return Padding(
        padding: margin,
        child: Text(
          'Henüz teklif verilmedi.',
          style: t.bodySmall.copyWith(color: c.dim),
        ),
      );
    }
    final total = q?.totalAmountTry ?? o.estimatedAmount!;
    final fixed = Fmt.number(total, minFraction: 2, maxFraction: 2);
    final comma = fixed.lastIndexOf(',');
    final whole = comma < 0 ? fixed : fixed.substring(0, comma);
    final decimals = comma < 0 ? null : fixed.substring(comma);
    final delivery = q?.deliveryDate ?? o.requestedDeliveryDate;
    final spoken = q == null
        ? 'Tahmini tutar ${Fmt.money(total)}'
        : 'Teklifiniz ${Fmt.money(total)}, birim fiyat ${Fmt.unitPrice(q.unitPriceTry)}';
    return AknPlate(
      margin: margin,
      semanticLabel: spoken,
      head: PlateHead(
        icon: PhosphorIconsRegular.invoice,
        title: q == null ? 'Tahmini tutar' : 'Teklifiniz',
        period: q == null
            ? 'teklif bekleniyor'
            : [
                if (q.version > 1) 'v${q.version}',
                whenShort(q.createdAt),
              ].join(', '),
      ),
      figure: PlateFigure(
        value: q == null ? Fmt.number(total.round()) : whole,
        decimals: q == null ? null : decimals,
        unit: '₺',
        semanticLabel: spoken,
      ),
      below: PlateClamp(
        child: PlateReadouts(
          items: [
            if (q != null)
              PlateReadout(
                label: 'Birim fiyat',
                value: Fmt.number(
                  q.unitPriceTry,
                  minFraction: 2,
                  maxFraction: 4,
                ),
                unit: '₺/L',
              ),
            PlateReadout(
              label: 'Miktar',
              value: Fmt.number(o.quantityLiters, maxFraction: 3),
              unit: 'L',
            ),
            PlateReadout(
              label: q == null ? 'İstenen teslim' : 'Teslim',
              value: delivery == null ? Fmt.dash : dayMonthLong(delivery),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kahraman kartın altındaki ödeme kartı (tasarım v3): tonlu simge karosu, yöntem, vade, durum;
/// tahsilat kaydına bağlantı.
class _PaymentLine extends StatelessWidget {
  const _PaymentLine({required this.order, required this.canOpen});

  final OrderDetail order;
  final bool canOpen;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final t = context.aknText;
    final c = context.akn;
    final term = o.paymentTermDays ?? 0;
    final method = paymentMethodName(o.paymentMethodCode);
    final status = switch (o.paymentStatus) {
      PaymentStatus.pending => 'Ödeme bekleniyor.',
      PaymentStatus.documentUploaded => 'Ödeme belgesi yüklendi.',
      PaymentStatus.collected => 'Tahsil edildi.',
      PaymentStatus.bounced => 'Karşılıksız çıktı.',
      PaymentStatus.refunded => 'İade edildi.',
      PaymentStatus.cancelled => 'Ödeme iptal edildi.',
      _ => '',
    };
    final due = o.paymentDueDate == null
        ? ''
        : ' Son ödeme ${dayMonthLong(o.paymentDueDate!)}.';
    final text =
        '$method${term > 0 ? ', $term gün vade' : ''}.${status.isEmpty ? '' : ' $status'}$due';
    final tone = o.paymentStatus.statusStyle.tone;
    final (icon, color, fill) = switch (o.paymentStatus) {
      PaymentStatus.collected || PaymentStatus.documentUploaded => (
        PhosphorIconsFill.checkCircle,
        c.ok.fg,
        c.ok.bg,
      ),
      PaymentStatus.bounced => (
        PhosphorIconsFill.warningCircle,
        c.danger.fg,
        c.danger.bg,
      ),
      _ => (
        PhosphorIconsRegular.money,
        tone == AknTone.warn ? c.warn.fg : c.ink,
        tone == AknTone.warn ? c.warn.bg : c.surfaceAlt,
      ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GlyphTile(icon: icon, color: color, fill: fill),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: t.body.copyWith(color: c.ink)),
                if (canOpen && o.paymentStatus != PaymentStatus.none)
                  AknInlineLink(
                    label: 'Tahsilat kaydını aç',
                    onTap: () =>
                        GoRouter.of(context).push(AppRoutes.payment(o.id)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ShipmentsSection extends ConsumerWidget {
  const _ShipmentsSection({required this.bundle});

  final BayiOrderBundle bundle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.aknText;
    final c = context.akn;
    final g = ref.watch(bayiGrantsProvider);
    final f = bundle.fulfillment;
    final o = bundle.order;
    if (f == null && !bundle.fulfillmentFailed) return const SizedBox.shrink();
    final approved =
        o.status == OrderStatus.approved || o.status == OrderStatus.completed;
    if (f == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Text(
          'Sevkiyatlar yüklenemedi. Sayfayı aşağı çekerek yenileyin.',
          style: t.bodySmall.copyWith(color: c.dim),
        ),
      );
    }
    final accepted = bundle.acceptedLiters;
    final ratio = o.quantityLiters <= 0 ? 0.0 : accepted / o.quantityLiters;
    return GroupCard(
      title: 'Sevkiyatlar',
      count: f.shipments.length,
      padding: EdgeInsets.only(bottom: f.shipments.isEmpty ? 14 : 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (approved)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Teslim alınan pay bir ilerlemedir: turuncu dolgu, mürekkep değer (v3); uyarı /
                  // tehlike eşiği yok (tamamı teslim alınınca kırmızıya dönmez).
                  BayiUsageBar(
                    value: ratio,
                    label: 'Teslim alınan',
                    valueLabel:
                        '${Fmt.liters(accepted)} / ${Fmt.liters(o.quantityLiters)}',
                    warnAt: double.infinity,
                    dangerAt: double.infinity,
                  ),
                  if (o.status == OrderStatus.approved &&
                      bundle.remainingLiters > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Planlanacak ${Fmt.liters(bundle.remainingLiters)}',
                        style: t.bodySmall.copyWith(color: c.ink),
                      ),
                    ),
                ],
              ),
            ),
          if (f.shipments.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
              child: Text(
                approved
                    ? 'Henüz sevkiyat planlanmadı.'
                    : 'Sipariş onaylanınca sevkiyat planlanır.',
                style: t.bodySmall.copyWith(color: c.dim),
              ),
            ),
          AknLedger(
            children: [
              for (final s in f.shipments)
                AknListTile(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                  title: keepUnits(
                    '${s.code}, ${Fmt.liters(s.deliveredLiters ?? s.plannedLiters)}',
                  ),
                  subtitle: [
                    whenShort(s.scheduledAt),
                    if (s.vehiclePlate.isNotEmpty) Fmt.plate(s.vehiclePlate),
                    if (s.driverName.isNotEmpty) s.driverName,
                  ].join(', '),
                  status: AknLamp.status(
                    AknStatus.shipmentLamp(s.status, g.viewer),
                  ),
                  footer: s.status == ShipmentStatus.inTransit
                      ? TruckRoute(
                          moving: true,
                          semanticLabel: 'Yolda. ${o.deliveryPointName}',
                        )
                      : null,
                  onTap: g.viewShipments
                      ? () => showShipmentSheet(context, s.id, code: s.code)
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Sipariş ayrıntısı eylemleri (spec A.1).
enum _OrderAction { quote, plan, complete }

/// Yetki + durum: Teklif ver (StationQuotes:Ekler; engel ve finans beklemesi yokken), Sevkiyat planla
/// (StationShipments:Ekler; onaylı ve kalan litre var), Tamamla (StationOrders:Duzenler; sunucunun
/// tamamlama kuralı, [BayiOrderBundle.completion]: tüm litre ya da teslim toleransı içinde teslim
/// alındı, ya da sevkiyatsız eski sipariş).
Set<_OrderAction> _availableActions(
  BayiGrants g,
  BayiOrderBundle b, {
  required bool quotingBlocked,
}) {
  final o = b.order;
  return {
    if (g.canQuoteOrder(
      o.status,
      o.financeStatus,
      quotingBlocked: quotingBlocked,
    ))
      _OrderAction.quote,
    if (g.planShipment &&
        o.status == OrderStatus.approved &&
        b.fulfillment != null &&
        b.remainingLiters > 0)
      _OrderAction.plan,
    if (g.completeOrder && b.completion != null) _OrderAction.complete,
  };
}

class _Actions extends ConsumerStatefulWidget {
  const _Actions({required this.bundle, required this.actions});

  final BayiOrderBundle bundle;
  final Set<_OrderAction> actions;

  @override
  ConsumerState<_Actions> createState() => _ActionsState();
}

class _ActionsState extends ConsumerState<_Actions> {
  bool _completing = false;

  Future<void> _complete() async {
    final b = widget.bundle;
    final o = b.order;
    final why = switch (b.completion) {
      BayiCompletion.withinTolerance =>
        'Teslim alınan ${Fmt.liters(b.acceptedLiters)} / ${Fmt.liters(o.quantityLiters)} teslim toleransı içinde. ',
      BayiCompletion.noShipments => '',
      _ => 'Tüm litre teslim alındı. ',
    };
    final ok = await showConfirmSheet(
      context,
      title: 'Sipariş tamamlansın mı?',
      message: keepUnits('$why${o.orderNumber} tamamlandı olarak işaretlenir.'),
      confirmLabel: 'Tamamla',
      icon: PhosphorIconsFill.checkCircle,
      tone: AknTone.ok,
    );
    if (!ok || !mounted) return;
    setState(() => _completing = true);
    try {
      await ref.read(bayiActionsProvider).completeOrder(o.id);
      if (mounted) AppToast.success('Sipariş tamamlandı.', context: context);
    } catch (e) {
      if (mounted) showActionFailure(context, e);
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.bundle;
    final o = b.order;
    final g = ref.watch(bayiGrantsProvider);
    final online = ref.watch(isOnlineProvider);
    double? suggestion;
    if (g.viewDesk) {
      final rows = ref.watch(quoteDeskProvider.select((s) => s.rows));
      for (final r in rows) {
        if (r.orderId == o.id) suggestion = r.suggestedUnitPrice;
      }
    }
    final canQuote = widget.actions.contains(_OrderAction.quote);
    final canPlan = widget.actions.contains(_OrderAction.plan);
    final canComplete = widget.actions.contains(_OrderAction.complete);
    final revision = o.status == OrderStatus.revisionRequested;
    final buttons = <Widget>[
      if (canQuote)
        AknButton(
          label: revision ? 'Teklifi güncelle' : 'Teklif ver',
          expand: true,
          onPressed: online
              ? () => showQuoteSheet(context, o, suggestion: suggestion)
              : null,
        ),
      if (canPlan)
        AknButton(
          label: 'Sevkiyat planla',
          expand: true,
          onPressed: online
              ? () => showPlanSheet(
                  context,
                  PlanTarget(
                    orderId: o.id,
                    orderNumber: o.orderNumber,
                    remainingLiters: b.remainingLiters,
                    customerTitle: o.customerTitle,
                    productName: o.productName,
                    deliveryDate:
                        o.currentQuote?.deliveryDate ?? o.requestedDeliveryDate,
                    deliveryPointName: o.deliveryPointName,
                  ),
                )
              : null,
        ),
      if (canComplete)
        AknButton.secondary(
          label: 'Tamamla',
          expand: true,
          loading: _completing,
          onPressed: online ? () => unawaited(_complete()) : null,
        ),
    ];
    // Alt çubukta yükseklik sınırlıdır: düğme satırı kendi yüksekliğinde kalsın.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!online)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Çevrimdışısınız; işlem için bağlantı gerekli.',
              textAlign: TextAlign.center,
              style: context.aknText.label.copyWith(color: context.akn.dim),
            ),
          ),
        Row(
          children: [
            for (var i = 0; i < buttons.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: buttons[i]),
            ],
          ],
        ),
      ],
    );
  }
}

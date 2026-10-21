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

/// Sipariş ayrıntısı (bayi; tasarım v2 §7.8 "aynı sayfa"): itilen başlıkta sipariş numarası; nesne
/// başlığı ("Motorin, 8.000 L"), cari ve teslim satırı; aşama şeridi; izleyiciye göre durum satırı;
/// **plaka** = bayinin teklifi (teklif yoksa tahmini tutar); ödeme satırı; Teslimat, Cari, Sevkiyatlar,
/// Teklif geçmişi ve Sipariş akışı bölümleri. Alt çubukta yetkiye göre Teklif ver / Teklifi güncelle,
/// Sevkiyat planla, Tamamla (spec A.1).
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

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        // Nesne başlığı (§6.1): "Motorin, 8.000 L" + cari + nokta ve teslim günü.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Nesne başlığı büyük yazıda en çok 1,5× (kök başlıklar gibi); kalan metin ölçeklenir.
              MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.5,
                child: Semantics(
                  header: true,
                  child: Text(
                    keepUnits(
                      '${o.productName}, ${Fmt.liters(o.quantityLiters)}',
                    ),
                    style: t.display.copyWith(color: c.ink),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(o.customerTitle, style: t.bodyStrong.copyWith(color: c.ink)),
              Text(
                [
                  o.deliveryPointName,
                  if (requested != null)
                    '${dayMonthLong(requested)} ${Fmt.weekday(requested)} teslim',
                ].join(', '),
                style: t.bodySmall.copyWith(color: c.dim),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: StageStrip(
            stages: stages,
            current: stageIndex,
            yourMove: lamp.yourMove,
            problem: lamp.problem ? StageProblem.rejected : null,
            // Büyük yazıda tek satır özet ("Aşama 3 / 6: Karar"); geçmişin tamamı "Sipariş akışı"nda.
            fallback: StageStripFallback.compact,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: AknStatusLine(
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
        if (lamp.stage == AknStage.yolda)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: TruckRoute(
              moving: true,
              destinationLabel: o.deliveryPointName,
              semanticLabel: 'Yolda. ${o.deliveryPointName}',
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
        _QuotePlate(order: o),
        if (q?.revisionNote != null)
          PageWell(
            top: 12,
            tone: AknTone.info,
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Carinin revize notu',
            message: q!.revisionNote!,
          ),
        _PaymentLine(order: o, canOpen: g.viewPayments),
        if (finance.isSettled)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified_user_outlined, size: 20, color: c.ok.fg),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${finance.label}.${o.financeReasons == null ? '' : ' ${o.financeReasons}'}',
                    style: t.body.copyWith(color: c.ink),
                  ),
                ),
              ],
            ),
          ),
        if (o.quotes.length > 1) ...[
          const SectionHeader(title: 'Teklif geçmişi'),
          _Facts(
            children: [
              for (final v in [
                ...o.quotes,
              ]..sort((a, b) => b.version.compareTo(a.version)))
                FactRow(
                  label: 'v${v.version}, ${whenShort(v.createdAt)}',
                  value:
                      '${Fmt.unitPrice(v.unitPriceTry)}${v.id == q?.id ? ' (güncel)' : ''}',
                ),
            ],
          ),
        ],
        const SectionHeader(title: 'Teslimat'),
        _Facts(
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
            FactRow(label: 'Oluşturuldu', value: Fmt.dateTime(o.createdAt)),
          ],
        ),
        if (g.viewCustomers) ...[
          const SectionHeader(title: 'Cari'),
          AknListTile(
            leadingIcon: Icons.apartment_outlined,
            title: o.customerTitle,
            subtitle: 'Cari kartı: limit, açık siparişler, notlar',
            showChevron: true,
            onTap: () =>
                GoRouter.of(context).push(AppRoutes.customer(o.customerId)),
          ),
        ],
        _ShipmentsSection(bundle: bundle),
        if (bundle.timeline.isNotEmpty || bundle.timelineFailed) ...[
          const SectionHeader(title: 'Sipariş akışı'),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
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
        ],
      ],
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

/// Bölüm içi olgular: 20 px kenarda etiket / değer satırları, aralarında ince çizgi.
class _Facts extends StatelessWidget {
  const _Facts({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: context.akn.line),
          children[i],
        ],
      ],
    ),
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
        icon: Icons.request_quote_outlined,
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

/// Plakanın altındaki ödeme satırı (§7.8): yöntem, vade, durum; tahsilat kaydına bağlantı.
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
    final (icon, color) = switch (o.paymentStatus) {
      PaymentStatus.collected ||
      PaymentStatus.documentUploaded => (Icons.check_circle_rounded, c.ok.fg),
      PaymentStatus.bounced => (Icons.error_rounded, c.danger.fg),
      _ => (Icons.payments_outlined, tone == AknTone.warn ? c.warn.fg : c.dim),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text, style: t.body.copyWith(color: c.ink)),
              ),
            ],
          ),
          if (canOpen && o.paymentStatus != PaymentStatus.none)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 30),
              child: AknInlineLink(
                label: 'Tahsilat kaydını aç',
                onTap: () => GoRouter.of(context).push(AppRoutes.payment(o.id)),
              ),
            ),
        ],
      ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: 'Sevkiyatlar', count: f.shipments.length),
        if (approved)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BayiUsageBar(
                  value: ratio,
                  label: 'Teslim alınan',
                  valueLabel:
                      '${Fmt.liters(accepted)} / ${Fmt.liters(o.quantityLiters)}',
                  tone: AknTone.info,
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
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
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
    );
  }
}

/// Sipariş ayrıntısı eylemleri (spec A.1).
enum _OrderAction { quote, plan, complete }

/// Yetki + durum: Teklif ver (StationQuotes:Ekler; engel ve finans beklemesi yokken), Sevkiyat planla
/// (StationShipments:Ekler; onaylı ve kalan litre var), Tamamla (StationOrders:Duzenler; tüm litre teslim
/// alındı).
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
    if (g.completeOrder &&
        o.status == OrderStatus.approved &&
        b.fulfillment != null &&
        b.acceptedLiters + 0.0005 >= o.quantityLiters)
      _OrderAction.complete,
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
    final o = widget.bundle.order;
    final ok = await showConfirmSheet(
      context,
      title: 'Sipariş tamamlansın mı?',
      message:
          'Tüm litre teslim alındı. ${o.orderNumber} tamamlandı olarak işaretlenir.',
      confirmLabel: 'Tamamla',
      icon: Icons.task_alt_rounded,
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

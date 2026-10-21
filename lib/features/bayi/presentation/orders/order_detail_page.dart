import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/models.dart';
import '../../../../core/offline/connectivity.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
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

/// Sipariş ayrıntısı (bayi; spec C.5 Detail tarifi): lacivert başlık, teklif / teslimat / ödeme /
/// sevkiyat / zaman çizelgesi kartları; yetkiye göre Teklif ver, Sevkiyat planla, Tamamla (spec A.1).
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
      subtitle: bundle?.order.customerTitle,
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

class _Body extends ConsumerWidget {
  const _Body({required this.bundle});

  final BayiOrderBundle bundle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = bundle.order;
    final t = context.aknText;
    final g = ref.watch(bayiGrantsProvider);
    final q = o.currentQuote;
    final openStatus = o.status.isOpen;
    // Geri sayım yalnızca süre dolumu açıkken (masa başlığı `expiryEnabled`; masayı göremeyen göstermez).
    final expiryOn =
        g.viewDesk &&
        ref.watch(quoteDeskProvider.select((s) => s.expiryEnabled));
    final expires = expiryOn ? o.expiresAt : null;
    final finance = o.financeStatus;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        AknHeroPanel(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Builder(
            builder: (context) {
              final t = context.aknText;
              final c = context.akn;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FitStart(
                        child: StatusChip.style(
                          o.status.statusStyle.withLabel(o.statusLabel),
                        ),
                      ),
                      if (openStatus &&
                          expires != null &&
                          expires.isAfter(DateTime.now().toUtc()))
                        FitStart(
                          child: CountdownBadge(
                            deadline: expires,
                            prefix: 'Kalan',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Semantics(
                    header: true,
                    child: Text(o.customerTitle, style: t.title),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${o.productName} · ${Fmt.liters(o.quantityLiters)}',
                    style: t.bodyStrong,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Oluşturuldu ${Fmt.dateTime(o.createdAt)}',
                    style: t.bodySmall.copyWith(color: c.dim),
                  ),
                ],
              );
            },
          ),
        ),
        if (finance != OrderFinanceStatus.notRequired)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: AknBanner(
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
          ),
        const BayiSectionHeader(title: 'Teklif'),
        SectionCard(
          child: q == null
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('Henüz teklif verilmedi.', style: t.bodySmall),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FactRow(
                      label: 'Birim fiyat',
                      value: Fmt.unitPrice(q.unitPriceTry),
                    ),
                    FactRow(
                      label: 'Toplam',
                      value: Fmt.money(q.totalAmountTry),
                    ),
                    FactRow(
                      label: 'Teklif teslim günü',
                      value: Fmt.date(q.deliveryDate),
                    ),
                    FactRow(
                      label: 'Sürüm',
                      value: 'v${q.version} · ${Fmt.dateTime(q.createdAt)}',
                    ),
                    if (q.revisionNote != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: AknBanner(
                          tone: AknTone.info,
                          icon: Icons.chat_bubble_outline_rounded,
                          title: 'Carinin revize notu',
                          message: q.revisionNote!,
                        ),
                      ),
                    if (o.quotes.length > 1) ...[
                      const Divider(height: 16),
                      for (final v in [
                        ...o.quotes,
                      ]..sort((a, b) => b.version.compareTo(a.version)))
                        if (v.id != q.id)
                          FactRow(
                            label: 'v${v.version} · ${Fmt.date(v.createdAt)}',
                            value: Fmt.unitPrice(v.unitPriceTry),
                          ),
                    ],
                  ],
                ),
        ),
        const BayiSectionHeader(title: 'Teslimat'),
        SectionCard(
          child: Column(
            children: [
              FactRow(label: 'Nokta', value: o.deliveryPointName),
              if (o.deliveryAddress.isNotEmpty)
                FactRow(label: 'Adres', value: o.deliveryAddress),
              FactRow(
                label: 'İstenen teslim',
                value: Fmt.longDate(o.requestedDeliveryDate),
              ),
            ],
          ),
        ),
        const BayiSectionHeader(title: 'Ödeme'),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FactRow(
                label: 'Yöntem',
                value: paymentMethodName(o.paymentMethodCode),
              ),
              if (o.paymentTermDays != null && o.paymentTermDays! > 0)
                FactRow(label: 'Vade', value: '${o.paymentTermDays} gün'),
              if (o.paymentDueDate != null)
                FactRow(
                  label: 'Ödeme tarihi',
                  value: Fmt.date(o.paymentDueDate),
                ),
              if (o.paymentStatus != PaymentStatus.none)
                FactRow(
                  label: 'Durum',
                  value: o.paymentStatus.label,
                  tone: o.paymentStatus.statusStyle.tone,
                ),
              if (o.estimatedAmount != null && q == null)
                FactRow(
                  label: 'Tahmini tutar',
                  value: Fmt.money(o.estimatedAmount),
                ),
              if (g.viewPayments && o.paymentStatus != PaymentStatus.none)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        GoRouter.of(context).push(AppRoutes.payment(o.id)),
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: const Text('Tahsilat kaydını aç'),
                  ),
                ),
            ],
          ),
        ),
        _ShipmentsCard(bundle: bundle),
        if (bundle.timeline.isNotEmpty || bundle.timelineFailed) ...[
          const BayiSectionHeader(title: 'Zaman çizelgesi'),
          SectionCard(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: bundle.timelineFailed
                ? Text('Zaman çizelgesi yüklenemedi.', style: t.bodySmall)
                : StepTimeline(
                    steps: _steps(
                      o,
                      bundle.timeline,
                      large: isLargeText(context),
                    ),
                  ),
          ),
        ],
        if (g.viewCustomers)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: AknCard(
              padding: EdgeInsets.zero,
              onTap: () =>
                  GoRouter.of(context).push(AppRoutes.customer(o.customerId)),
              child: AknListTile(
                leadingIcon: Icons.apartment_rounded,
                title: 'Cari kartı',
                subtitle: o.customerTitle,
                showChevron: true,
              ),
            ),
          ),
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
      final time = e.changedAt == null ? null : Fmt.dateTime(e.changedAt);
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

class _ShipmentsCard extends ConsumerWidget {
  const _ShipmentsCard({required this.bundle});

  final BayiOrderBundle bundle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.aknText;
    final g = ref.watch(bayiGrantsProvider);
    final f = bundle.fulfillment;
    final o = bundle.order;
    if (f == null && !bundle.fulfillmentFailed) return const SizedBox.shrink();
    final approved =
        o.status == OrderStatus.approved || o.status == OrderStatus.completed;
    if (f == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        child: Text('Sevkiyatlar yüklenemedi.', style: t.bodySmall),
      );
    }
    final accepted = bundle.acceptedLiters;
    final ratio = o.quantityLiters <= 0 ? 0.0 : accepted / o.quantityLiters;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BayiSectionHeader(title: 'Sevkiyatlar', count: f.shipments.length),
        SectionCard(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (approved) ...[
                BayiUsageBar(
                  value: ratio,
                  label: 'Teslim alınan',
                  valueLabel:
                      '${Fmt.liters(accepted)} / ${Fmt.liters(o.quantityLiters)}',
                  tone: ratio >= 1 ? AknTone.ok : AknTone.info,
                ),
                if (o.status == OrderStatus.approved &&
                    bundle.remainingLiters > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Planlanacak ${Fmt.liters(bundle.remainingLiters)}',
                      style: t.bodySmall,
                    ),
                  ),
                const SizedBox(height: 8),
              ],
              if (f.shipments.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    approved
                        ? 'Henüz sevkiyat planlanmadı.'
                        : 'Sipariş onaylanınca sevkiyat planlanır.',
                    style: t.bodySmall,
                  ),
                ),
              for (final s in f.shipments)
                AknListTile(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  title:
                      '${s.code} · ${Fmt.liters(s.deliveredLiters ?? s.plannedLiters)}',
                  subtitle: [
                    Fmt.dateTime(s.scheduledAt),
                    if (s.vehiclePlate.isNotEmpty) Fmt.plate(s.vehiclePlate),
                    if (s.driverName.isNotEmpty) s.driverName,
                  ].join(' · '),
                  trailing: FitEnd(
                    child: StatusChip.style(
                      s.status.statusStyle,
                      size: StatusChipSize.small,
                    ),
                  ),
                  onTap: g.viewShipments
                      ? () => showShipmentSheet(context, s.id, code: s.code)
                      : null,
                ),
            ],
          ),
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
    final buttons = <Widget>[
      if (canQuote)
        AknButton(
          label: 'Teklif ver',
          icon: Icons.request_quote_rounded,
          expand: true,
          onPressed: online
              ? () => showQuoteSheet(context, o, suggestion: suggestion)
              : null,
        ),
      if (canPlan)
        AknButton(
          label: 'Sevkiyat planla',
          icon: Icons.event_available_rounded,
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
          icon: Icons.task_alt_rounded,
          expand: true,
          loading: _completing,
          onPressed: online ? () => unawaited(_complete()) : null,
        ),
    ];
    // Alt çubukta yükseklik sınırlıdır: düğme satırı kendi yüksekliğinde kalsın.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
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

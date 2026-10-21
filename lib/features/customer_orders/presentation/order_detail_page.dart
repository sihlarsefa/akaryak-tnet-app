import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/models/models.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/connectivity.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import '../application/home_controller.dart';
import '../application/loadable.dart';
import '../application/order_view_controller.dart';
import '../application/ordering_config.dart';
import '../application/quote_decision.dart';
import '../copy.dart';
import '../data/customer_orders_repository.dart';
import '../data/order_models.dart';
import 'templates_page.dart';
import 'widgets/common.dart';
import 'widgets/contact_actions.dart';
import 'widgets/order_parts.dart';
import 'widgets/payment_block.dart';
import 'widgets/payment_document_flow.dart';
import 'widgets/quote_decision_card.dart';
import 'widgets/tracking_card.dart';

/// Sipariş ayrıntısı (spec A.4; tasarım v2 §7.8, pano ekran 5).
///
/// Itilmiş çubuk "SIP-…" + ⋯ → "Motorin, 8.000 L" (display) ve nokta / teslim günü → aşama şeridi
/// → durum satırı (lamba + geri sayım) → **teklif plakası** (ekranın tek plakası) → ödeme satırı
/// → "Son alımlarınızla kıyas" → yolda / sevkiyatlar → "Sipariş akışı" → ödeme, bilgiler,
/// belgeler. Karar sırası müşterideyse alt çubukta "Teklifi onayla" + "Revize iste" / "Reddet".
///
/// Teklif / yoldaki araç beklenirken 30 sn'de bir yoklanır; çevrimdışıyken son kayıt gösterilir
/// ve kararlar kapalıdır.
class OrderDetailPage extends ConsumerStatefulWidget {
  const OrderDetailPage({super.key, required this.orderId});

  final int orderId;

  @override
  ConsumerState<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends ConsumerState<OrderDetailPage>
    with WidgetsBindingObserver {
  static const pollEvery = Duration(seconds: 30);

  Timer? _poll;
  bool _foreground = true;
  QuoteAction? _pending;
  bool _checking = false;
  String? _conflict;
  bool _uncertain = false;

  /// Teklif onaylanınca plaka "mühürlenir" (§8.2).
  int _stamp = 0;

  int get _id => widget.orderId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poll = Timer.periodic(pollEvery, (_) => _maybePoll());
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg && !_foreground) unawaited(_refresh());
    _foreground = fg;
  }

  void _maybePoll() {
    if (!mounted || !_foreground || _pending != null) return;
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final data = ref.read(orderViewProvider(_id)).data;
    if (data == null || !shouldPollOrder(data)) return;
    unawaited(_refresh());
  }

  Future<void> _refresh() =>
      ref.read(orderViewProvider(_id).notifier).refresh();

  void _refreshEverything() => ref.read(a2DataRevisionProvider.notifier).bump();

  // ------------------------------------------------------------------ Teklif kararı

  Future<void> _decide(OrderView v, QuoteAction action) async {
    final q = v.latestQuote;
    if (q == null || _pending != null) return;
    String? note;
    if (action == QuoteAction.approve) {
      final ok = await showApproveRecap(
        context,
        quote: q,
        order: v.detail,
        paymentLine: v.detail.paymentMethodCode == null
            ? null
            : paymentLineOf(v.detail),
      );
      if (!ok) return;
    } else {
      note = await showDecisionNoteSheet(
        context,
        revise: action == QuoteAction.revise,
      );
      if (note == null) return;
    }
    if (!mounted) return;
    setState(() {
      _pending = action;
      _checking = false;
      _conflict = null;
      _uncertain = false;
    });
    final outcome = await ref
        .read(quoteDecisionExecutorProvider)
        .decide(
          orderId: _id,
          action: action,
          expectedQuoteId: q.id,
          note: note,
          refetchStatus: () async =>
              (await ref.read(orderViewProvider(_id).notifier).reload())
                  ?.detail
                  .status,
          onChecking: () {
            if (mounted) setState(() => _checking = true);
          },
        );
    if (!mounted) return;
    setState(() {
      _pending = null;
      _checking = false;
    });
    switch (outcome) {
      case DecisionDone():
        final text = switch (action) {
          QuoteAction.approve =>
            'Teklif onaylandı. Bayi sevkiyatı planlayacak.',
          QuoteAction.revise =>
            'Revize istendi. Bayi yeni teklif hazırlayacak.',
          QuoteAction.reject => 'Teklif reddedildi.',
        };
        if (action == QuoteAction.approve) setState(() => _stamp++);
        AppToast.success(text, context: context);
        unawaited(
          SemanticsService.sendAnnouncement(
            View.of(context),
            text,
            TextDirection.ltr,
          ),
        );
        await _refresh();
        _refreshEverything();
      case DecisionConflict(:final message):
        setState(() => _conflict = message);
        await _refresh();
      case DecisionFailed(:final failure):
        if (failure is! ForbiddenFailure) {
          AppToast.error(OrdersCopy.failureMessage(failure), context: context);
        }
        await _refresh();
      case DecisionUncertain():
        setState(() => _uncertain = true);
    }
  }

  Future<void> _upload(OrderView v) async {
    final target = v.documentTarget;
    if (target == null) return;
    final done = await showPaymentDocumentSheet(
      context,
      target: target,
      orderNumber: v.detail.orderNumber,
    );
    if (done && mounted) {
      await _refresh();
      _refreshEverything();
    }
  }

  Future<void> _makeTemplate(OrderView v) async {
    final repo = ref.read(customerOrdersRepositoryProvider);
    try {
      final draft = await repo.templateFromOrder(_id);
      if (!mounted) return;
      final name = await showTemplateNameSheet(context, initial: draft.name);
      if (name == null || !mounted) return;
      await repo.saveTemplate(
        name: name,
        lines: [
          for (final l in draft.lines)
            (
              productId: l.productId,
              deliveryPointId: l.deliveryPointId,
              liters: l.quantityLiters,
              stationId: l.stationId ?? v.detail.stationId,
            ),
        ],
      );
      if (!mounted) return;
      AppToast.show(
        '“$name” şablon olarak kaydedildi.',
        type: AppToastType.success,
        context: context,
        actionLabel: 'Şablonlarım',
        onAction: () => context.push(templatesRoute),
      );
      _refreshEverything();
    } on AppFailure catch (f) {
      if (mounted && f is! ForbiddenFailure) {
        AppToast.error(OrdersCopy.failureMessage(f), context: context);
      }
    }
  }

  void _reorder(OrderDetail d) =>
      context.push('${AppRoutes.orderNew}?reorder=${d.id}');

  /// ⋯: siparişi tekrarla, şablon olarak kaydet, sipariş belgeleri.
  Future<void> _openMenu(
    OrderView v, {
    required bool canCreate,
    required bool canDocs,
  }) async {
    final choice = await showAppSheet<String>(
      context: context,
      title: v.detail.orderNumber,
      padding: const EdgeInsets.only(bottom: 12),
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canCreate) ...[
            AknListTile(
              leadingIcon: Icons.replay_rounded,
              title: OrdersCopy.reorder,
              subtitle: 'Aynı ürün ve noktayla yeni sipariş',
              onTap: () => Navigator.of(ctx).pop('reorder'),
            ),
            AknListTile(
              leadingIcon: Icons.bookmark_add_outlined,
              title: OrdersCopy.makeTemplate,
              subtitle: 'Sonraki siparişlerde tek dokunuşla kullanın',
              onTap: () => Navigator.of(ctx).pop('template'),
            ),
          ],
          if (canDocs)
            AknListTile(
              leadingIcon: Icons.folder_open_outlined,
              title: 'Sipariş belgeleri',
              subtitle: 'Sipariş formu, teklif, teslim tutanağı',
              onTap: () => Navigator.of(ctx).pop('docs'),
            ),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case 'reorder':
        _reorder(v.detail);
      case 'template':
        await _makeTemplate(v);
      case 'docs':
        unawaited(
          context.push('${AppRoutes.documents}?orderId=${v.detail.id}'),
        );
    }
  }

  // ------------------------------------------------------------------ Görünüm

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(orderViewProvider(_id));
    final v = s.data;
    final policy = ref.watch(accessPolicyProvider);
    final online = ref.watch(isOnlineProvider);
    final canDecide = policy.can(Pg.customerQuotes, Perm.edit);
    final canCreate = policy.can(Pg.customerCreateOrder, Perm.create);
    final canDocs =
        policy.can(Pg.customerDocuments) &&
        policy.canAny(const [Pg.customerOrders, Pg.customerQuotes]);
    final decisionOpen =
        v != null &&
        v.detail.status == OrderStatus.awaitingApproval &&
        v.latestQuote != null;
    final reported = v?.tracking?.shipments
        .where((x) => x.status == ShipmentStatus.reported)
        .firstOrNull;
    final closed =
        v != null &&
        (v.detail.status == OrderStatus.completed ||
            v.detail.status == OrderStatus.rejected ||
            v.detail.status == OrderStatus.expired);

    Widget body;
    if (v == null && s.isFirstLoad) {
      body = const SkeletonList(itemCount: 4, lines: 3);
    } else if (v == null) {
      body = Center(
        child: SingleChildScrollView(
          child: FailureView(
            failure: s.error ?? const UnknownFailure(),
            onRetry: _refresh,
          ),
        ),
      );
    } else {
      body = PullToRefresh(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          children: [ContentWidth(child: _content(context, v, s, canDocs))],
        ),
      );
    }

    Widget? dock;
    if (v != null && decisionOpen && canDecide) {
      dock = _DecisionDock(
        view: v,
        online: online,
        pending: _pending,
        checking: _checking,
        onDecide: (a) => _decide(v, a),
      );
    } else if (reported != null &&
        (v?.tracking?.canAcceptDeliveries ?? false)) {
      dock = AknButton(
        label: OrdersCopy.confirmDelivery,
        icon: Icons.task_alt_rounded,
        expand: true,
        onPressed: () => context.push(AppRoutes.shipment(reported.id)),
      );
    } else if (closed && canCreate) {
      dock = AknButton(
        label: OrdersCopy.reorder,
        icon: Icons.replay_rounded,
        expand: true,
        semanticLabel: 'Bu siparişi tekrarla',
        onPressed: () => _reorder(v.detail),
      );
    }

    return AppScaffold(
      title: v?.detail.orderNumber ?? OrdersCopy.orderDetail,
      largeTitle: false,
      showBell: false,
      refreshing: s.refreshing,
      actions: [
        if (v != null && (canCreate || canDocs))
          AknIconButton(
            icon: Icons.more_horiz_rounded,
            semanticLabel: 'Diğer seçenekler',
            onPressed: () =>
                _openMenu(v, canCreate: canCreate, canDocs: canDocs),
          ),
      ],
      actionBar: dock,
      body: body,
    );
  }

  Widget _content(
    BuildContext context,
    OrderView v,
    Loadable<OrderView> s,
    bool canDocs,
  ) {
    final t = context.aknText;
    final c = context.akn;
    final d = v.detail;
    final home = ref.watch(customerHomeProvider).data;
    final form = ref.watch(orderFormProvider).data;
    final policy = ref.watch(accessPolicyProvider);
    final config = ref.watch(orderingConfigValueProvider);
    final viewer = customerViewer(policy);
    final station = home?.station?.id == d.stationId ? home?.station : null;
    final point = form?.point(d.deliveryPointId);
    final canCreate = policy.can(Pg.customerCreateOrder, Perm.create);
    final tracking = v.tracking;
    final active = tracking?.activeShipment;
    final awaitingQuote =
        d.status == OrderStatus.awaitingQuote ||
        d.status == OrderStatus.revisionRequested ||
        d.status == OrderStatus.created;

    final lamp = orderLampFor(
      viewer,
      status: d.status,
      serverLabel: d.statusDisplay,
      shipment: active?.status,
      finance: d.financeStatus,
    );

    // Plakadaki teklif: karar ekranında en son sürüm; sonrasında seçili teklif kendi adıyla.
    // Sunucu her yeni teklifi "seçili" kaydeder ve revize / ret / süre dolumunda bunu değiştirmez.
    final decision = d.status == OrderStatus.awaitingApproval;
    final quoteTitle = switch (d.status) {
      OrderStatus.awaitingApproval =>
        shortCompany(d.stationTitle).isEmpty
            ? 'Teklif'
            : '${shortCompany(d.stationTitle)} teklifi',
      OrderStatus.approved || OrderStatus.completed => 'Onaylanan teklif',
      OrderStatus.revisionRequested => 'Revize istenen teklif',
      OrderStatus.rejected => 'Reddedilen teklif',
      OrderStatus.expired => 'Süresi dolan teklif',
      _ => null,
    };
    final quote = quoteTitle == null
        ? null
        : (decision ? v.latestQuote : d.currentQuote);
    final deliveryDiffers =
        decision &&
        quote?.deliveryDate != null &&
        d.requestedDeliveryDate != null &&
        !TrTime.isSameDay(quote!.deliveryDate!, d.requestedDeliveryDate!);

    final expiryOn = config.expiryEnabled(tracking?.expiryEnabled ?? true);
    final expires = d.expiresAt;
    final showCountdown =
        expiryOn &&
        expires != null &&
        !d.financeStatus.isAwaitingDecision &&
        (decision || awaitingQuote);

    final strip = _stripFor(lamp, active?.status);
    final pointName =
        point?.name ??
        (d.deliveryPointName.isEmpty ? null : d.deliveryPointName);
    final shipments = (tracking?.shipments ?? const <TrackingShipment>[])
        .where((x) => x.status != ShipmentStatus.cancelled)
        .toList();
    final cancelled = (tracking?.shipments.length ?? 0) - shipments.length;
    final versions = v.quoteVersions;
    final comparison = tracking?.priceComparison;

    Widget pad(Widget child, {double top = 12}) => Padding(
      padding: EdgeInsets.fromLTRB(AknSpace.page, top, AknSpace.page, 0),
      child: child,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LastUpdatedNote(updatedAt: s.updatedAt, fromCache: s.fromCache),
        // Nesne başlığı.
        pad(
          top: 8,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  orderTitle(d.productName, d.quantityLiters),
                  style: t.display.copyWith(color: c.ink),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                [
                  ?pointName,
                  if (d.requestedDeliveryDate != null)
                    '${dayMonthWeekday(d.requestedDeliveryDate)} teslim',
                ].join(', '),
                style: t.bodySmall.copyWith(color: c.dim),
              ),
            ],
          ),
        ),
        pad(
          top: 18,
          StageStrip(
            stages: [for (final st in AknStage.stops()) st.label],
            current: strip.$1,
            yourMove: lamp.yourMove,
            problem: strip.$2,
            // Büyük yazıda tek satır özet ("Aşama 3 / 6: Karar"); ayrıntılı akış aşağıda.
            fallback: StageStripFallback.compact,
          ),
        ),
        pad(
          top: 18,
          AknStatusLine(
            lamp: AknLamp.status(lamp),
            trailing: showCountdown
                ? CountdownBadge(
                    deadline: config.deviceDeadline(expires),
                    start: quote?.createdAt == null || !decision
                        ? null
                        : config.deviceDeadline(quote!.createdAt!),
                    yourMove: lamp.yourMove,
                    subject: decision ? 'Teklif' : 'Teklif süresi',
                  )
                : null,
          ),
        ),
        if (_conflict != null)
          pad(
            AknBanner(
              tone: AknTone.warn,
              icon: Icons.sync_problem_rounded,
              title: OrdersCopy.conflict,
              message: _conflict!,
              actionLabel: OrdersCopy.refresh,
              onAction: () {
                setState(() => _conflict = null);
                unawaited(_refresh());
              },
            ),
          ),
        if (_uncertain)
          pad(
            AknBanner(
              tone: AknTone.warn,
              icon: Icons.schedule_rounded,
              title: 'Kararınız doğrulanamadı',
              message:
                  'Bağlantı gelince aynı kararı güvenle yeniden gönderebilirsiniz; '
                  'iki kez işlenmez.',
              actionLabel: OrdersCopy.retry,
              onAction: () => setState(() => _uncertain = false),
            ),
          ),
        for (final w in _financeWells(context, d)) pad(w),
        for (final w in _statusWells(d)) pad(w),
        // Ekranın tek plakası: teklif; teklif yoksa tahmini tutar.
        if (quote != null && quoteTitle != null)
          pad(
            QuotePlate(
              quote: quote,
              detail: d,
              title: quoteTitle,
              stamp: _stamp,
            ),
          )
        else if (awaitingQuote && d.estimatedAmount != null)
          pad(EstimatePlate(detail: d)),
        if (deliveryDiffers)
          pad(
            FactLine(
              icon: Icons.event_busy_outlined,
              tone: AknTone.warn,
              text:
                  '${OrdersCopy.deliveryDiffers}: istediğiniz gün ${dayMonthWeekday(d.requestedDeliveryDate)}.',
            ),
          ),
        if (decision && v.advanceInsufficient)
          pad(
            AknBanner(
              tone: AknTone.danger,
              icon: Icons.account_balance_wallet_outlined,
              title: 'Ön ödemeli bakiye yetersiz',
              message:
                  'Kullanılabilir bakiye ${Fmt.money(v.advanceBalance)}, teklif tutarı '
                  '${Fmt.money(quote?.totalAmountTry)}. Bakiye yüklemek için bayinizle görüşün.',
            ),
          ),
        if (d.paymentMethodCode != null && (decision || quote != null))
          pad(
            PaymentFactLine(
              view: v,
              onUpload: v.documentTarget?.isUploadable == true
                  ? () => _upload(v)
                  : null,
            ),
          ),
        if (decision && quote != null && PriceComparison.shows(comparison))
          pad(
            top: 24,
            PriceComparison(comparison: comparison!, offer: quote.unitPriceTry),
          ),
        if (awaitingQuote && !d.financeStatus.isAwaitingDecision)
          OrderSection(
            title: d.status == OrderStatus.revisionRequested
                ? 'Revize teklif bekleniyor'
                : 'Teklif bekleniyor',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${OrdersCopy.awaitingQuoteHint}.',
                  style: t.body.copyWith(color: c.ink),
                ),
                if (d.status == OrderStatus.revisionRequested &&
                    quote?.revisionNote != null) ...[
                  const SizedBox(height: 8),
                  FactRow(label: 'Revize notunuz', value: quote!.revisionNote!),
                ],
                if (station != null) ...[
                  const SizedBox(height: 10),
                  StationContactButtons(
                    station: station,
                    message:
                        '${d.orderNumber} numaralı siparişim hakkında yazıyorum.',
                  ),
                ],
              ],
            ),
          ),
        if (active != null)
          ActiveShipmentSection(
            order: d,
            shipment: active,
            point: point,
            station: awaitingQuote ? null : station,
            canAccept: tracking?.canAcceptDeliveries ?? false,
          ),
        if (shipments.isNotEmpty)
          OrderSection(
            title: 'Sevkiyatlar',
            count: shipments.length,
            bleed: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ShipmentRows(shipments: shipments, viewer: viewer),
                if (cancelled > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Text(
                      '$cancelled sevkiyat planı iptal edildi.',
                      style: t.bodySmall.copyWith(color: c.dim),
                    ),
                  ),
              ],
            ),
          ),
        if (tracking != null && tracking.steps.isNotEmpty)
          OrderSection(
            title: OrdersCopy.tracking,
            child: OrderFlowTimeline(
              steps: tracking.steps,
              yourMove: lamp.yourMove,
            ),
          ),
        if (versions.length > 1)
          OrderSection(
            title: OrdersCopy.versions,
            bleed: true,
            child: QuoteVersions(versions: versions),
          ),
        if (d.paymentMethodCode != null)
          PaymentBlock(
            view: v,
            onUpload: v.documentTarget?.isUploadable == true
                ? () => _upload(v)
                : null,
          ),
        OrderSection(
          title: 'Sipariş bilgileri',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FactRow(label: 'Sipariş no', value: d.orderNumber),
              if (d.stationTitle.isNotEmpty)
                FactRow(label: 'Bayi', value: d.stationTitle),
              FactRow(label: 'Nokta', value: pointName ?? Fmt.dash),
              if (d.deliveryAddress.isNotEmpty)
                FactRow(label: 'Adres', value: d.deliveryAddress),
              if (point?.windowLabel != null)
                FactRow(label: 'Teslim saatleri', value: point!.windowLabel!),
              FactRow(
                label: 'İstenen tarih',
                value: dayMonthWeekday(d.requestedDeliveryDate),
              ),
              if (d.createdAt != null)
                FactRow(
                  label: 'Verildi',
                  value:
                      '${dayMonthLong(d.createdAt)} ${Fmt.time(d.createdAt)}',
                ),
            ],
          ),
        ),
        if (canDocs)
          OrderSection(
            title: 'Belgeler',
            bleed: true,
            child: AknListTile(
              leadingIcon: Icons.folder_open_outlined,
              title: 'Sipariş belgeleri',
              subtitle: 'Sipariş formu, teklif, teslim tutanağı',
              showChevron: true,
              onTap: () =>
                  context.push('${AppRoutes.documents}?orderId=${d.id}'),
            ),
          ),
        if (canCreate && !decision) const SizedBox(height: 8),
      ],
    );
  }

  /// Şeritteki konum ve sorun işareti.
  (int, StageProblem?) _stripFor(StatusLamp lamp, ShipmentStatus? shipment) {
    final n = AknStage.stops().length;
    if (lamp.complete) return (n, null);
    final i = lamp.stageIndex() ?? 0;
    final problem = !lamp.problem
        ? null
        : (shipment == ShipmentStatus.disputed
              ? StageProblem.attention
              : StageProblem.rejected);
    return (i < 0 ? 0 : i, problem);
  }

  List<Widget> _financeWells(BuildContext context, OrderDetail d) {
    switch (d.financeStatus) {
      case OrderFinanceStatus.pending:
        return [
          const AknBanner(
            tone: AknTone.info,
            icon: Icons.account_balance_outlined,
            title: 'Finans onayında',
            message:
                'Bayinin finans ekibi siparişinizi inceliyor; onaylanınca bayi teklif verir.',
          ),
        ];
      case OrderFinanceStatus.infoRequested:
        final id = d.financeApprovalRequestId;
        return [
          AknBanner(
            tone: AknTone.warn,
            icon: Icons.mark_email_unread_outlined,
            title: 'Finans ek bilgi istedi',
            message:
                'Yanıtınız ve istenen belge gelene kadar teklif verilemez.',
            actionLabel: 'Yanıtla',
            onAction: () => context.push(
              id == null ? AppRoutes.financeInfo : AppRoutes.approval(id),
            ),
          ),
        ];
      case OrderFinanceStatus.rejected:
        return [
          AknBanner(
            tone: AknTone.danger,
            icon: Icons.block_rounded,
            title: 'Finans reddetti',
            message:
                d.financeReasons ??
                'Bayinin finans ekibi bu siparişi onaylamadı; bayinizle görüşün.',
          ),
        ];
      case OrderFinanceStatus.conditionallyApproved:
        return [
          const AknBanner(
            tone: AknTone.ok,
            icon: Icons.verified_outlined,
            title: 'Koşullu onaylandı',
            message: 'Finans, ödeme koşullarını güncelleyerek onayladı.',
          ),
        ];
      default:
        return const [];
    }
  }

  List<Widget> _statusWells(OrderDetail d) => switch (d.status) {
    OrderStatus.expired => [
      const AknBanner(
        tone: AknTone.neutral,
        icon: Icons.timer_off_outlined,
        title: 'Süresi doldu',
        message:
            'Bu siparişin teklif süresi doldu. Aynı siparişi yeniden verebilirsiniz.',
      ),
    ],
    OrderStatus.rejected => [
      const AknBanner(
        tone: AknTone.neutral,
        icon: Icons.do_not_disturb_on_outlined,
        title: 'Reddedildi',
        message: 'Bu sipariş kapandı.',
      ),
    ],
    _ => const [],
  };
}

/// Karar çubuğu (§7.8): "Teklifi onayla" (tam genişlik; belge eksikse / avans yetmezse /
/// çevrimdışıyken kapalı ve nedeni altında), altında "Revize iste" ve "Reddet". Belirsiz sonuçta
/// "Kararınız kontrol ediliyor".
class _DecisionDock extends StatelessWidget {
  const _DecisionDock({
    required this.view,
    required this.online,
    required this.pending,
    required this.checking,
    required this.onDecide,
  });

  final OrderView view;
  final bool online;
  final QuoteAction? pending;
  final bool checking;
  final ValueChanged<QuoteAction> onDecide;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final busy = pending != null;
    final stacked = MediaQuery.textScalerOf(context).scale(15) > 19.5;
    final target = view.documentTarget;
    final blockedReason = !online
        ? OrdersCopy.decisionOffline
        : view.paymentDocumentMissing
        ? '${target?.label ?? 'Ödeme belgesi'} yüklenmeden onaylanamaz'
        : view.advanceInsufficient
        ? 'Bakiye yetersiz; bayinizle görüşün'
        : null;
    final approve = AknButton(
      label: OrdersCopy.approve,
      expand: true,
      loading: pending == QuoteAction.approve,
      semanticLabel: blockedReason == null
          ? OrdersCopy.approve
          : '${OrdersCopy.approve}, kapalı: $blockedReason',
      onPressed: busy || blockedReason != null
          ? null
          : () => onDecide(QuoteAction.approve),
    );
    final revise = AknButton.secondary(
      label: OrdersCopy.revise,
      size: AknButtonSize.medium,
      expand: true,
      loading: pending == QuoteAction.revise,
      onPressed: busy || !online ? null : () => onDecide(QuoteAction.revise),
    );
    final reject = AknButton.danger(
      label: OrdersCopy.reject,
      size: AknButtonSize.medium,
      expand: true,
      loading: pending == QuoteAction.reject,
      onPressed: busy || !online ? null : () => onDecide(QuoteAction.reject),
    );
    Widget note(IconData icon, String text, {Widget? lead}) => Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          lead ?? Icon(icon, size: 16, color: c.dim),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: t.bodySmall.copyWith(color: c.dim)),
          ),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        approve,
        if (checking)
          note(
            Icons.sync_rounded,
            OrdersCopy.decisionChecking,
            lead: const SizedBox(
              width: 16,
              height: 16,
              child: ChevronSpinner(size: 16),
            ),
          )
        // Büyük yazıda neden çubukta tekrarlanmaz (sayfadaki uyarı ve düğmenin ekran okuyucu
        // etiketi söyler); çevrimdışıyken üstteki çevrimdışı satırı söyler.
        else if (blockedReason != null && !busy && !stacked)
          note(Icons.info_outline_rounded, blockedReason),
        const SizedBox(height: 10),
        if (stacked) ...[
          revise,
          const SizedBox(height: 8),
          reject,
        ] else
          Row(
            children: [
              Expanded(child: revise),
              const SizedBox(width: 10),
              Expanded(child: reject),
            ],
          ),
      ],
    );
  }
}

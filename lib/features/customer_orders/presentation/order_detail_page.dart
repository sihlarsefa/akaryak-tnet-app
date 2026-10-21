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
import '../application/home_controller.dart';
import '../application/loadable.dart';
import '../application/order_view_controller.dart';
import '../application/quote_decision.dart';
import '../copy.dart';
import '../data/customer_orders_repository.dart';
import 'templates_page.dart';
import 'widgets/common.dart';
import 'widgets/contact_actions.dart';
import 'widgets/payment_block.dart';
import 'widgets/payment_document_flow.dart';
import 'widgets/quote_decision_card.dart';
import 'widgets/tracking_card.dart';

/// Sipariş ayrıntısı (spec A.4): durum kahramanı, teklif kararı, ödeme ve belge durumu, takip,
/// sevkiyatlar, belgeler, "Tekrarla" ve "Şablon yap". Teklif / yoldaki araç beklenirken 30 sn'de
/// bir yoklanır; çevrimdışıyken son kayıt gösterilir ve kararlar kapalıdır.
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
            'Teklifi onayladınız. Bayi sevkiyatı planlayacak.',
          QuoteAction.revise => 'Revize talebiniz bayiye iletildi.',
          QuoteAction.reject => 'Teklifi reddettiniz.',
        };
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

  // ------------------------------------------------------------------ Görünüm

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(orderViewProvider(_id));
    final v = s.data;
    final policy = ref.watch(accessPolicyProvider);
    final online = ref.watch(isOnlineProvider);
    final canDecide = policy.can(Pg.customerQuotes, Perm.edit);
    final decisionOpen =
        v != null &&
        v.detail.status == OrderStatus.awaitingApproval &&
        v.latestQuote != null;

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
          children: [
            ContentWidth(child: _content(context, v, s, canDecide, online)),
          ],
        ),
      );
    }

    return AppScaffold(
      title: v?.detail.orderNumber ?? OrdersCopy.orderDetail,
      subtitle: v?.detail.stationTitle,
      refreshing: s.refreshing,
      actionBar: decisionOpen && canDecide
          ? _DecisionBar(
              view: v,
              online: online,
              pending: _pending,
              checking: _checking,
              onDecide: (a) => _decide(v, a),
            )
          : null,
      body: body,
    );
  }

  Widget _content(
    BuildContext context,
    OrderView v,
    Loadable<OrderView> s,
    bool canDecide,
    bool online,
  ) {
    final d = v.detail;
    final home = ref.watch(customerHomeProvider).data;
    final form = ref.watch(orderFormProvider).data;
    final policy = ref.watch(accessPolicyProvider);
    final station = home?.station?.id == d.stationId ? home?.station : null;
    final point = form?.point(d.deliveryPointId);
    final canCreate = policy.can(Pg.customerCreateOrder, Perm.create);
    final canDocs =
        policy.can(Pg.customerDocuments) &&
        policy.canAny(const [Pg.customerOrders, Pg.customerQuotes]);
    final awaitingQuote =
        d.status == OrderStatus.awaitingQuote ||
        d.status == OrderStatus.revisionRequested ||
        d.status == OrderStatus.created;
    // Sunucu her yeni teklifi "seçili" kaydeder ve revize / ret / süre dolumunda bunu değiştirmez:
    // "Onaylanan teklif" yalnızca onaylanmış ve tamamlanmış siparişte; reddedilen, revizesi istenen
    // ya da süresi dolan teklif kendi adıyla gösterilir.
    final quoteCard = switch (d.status) {
      OrderStatus.approved || OrderStatus.completed => _QuoteKind.approved,
      OrderStatus.revisionRequested => _QuoteKind.revisionRequested,
      OrderStatus.rejected => _QuoteKind.rejected,
      OrderStatus.expired => _QuoteKind.expired,
      _ => null,
    };
    final shownQuote = quoteCard == null ? null : d.currentQuote;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LastUpdatedNote(updatedAt: s.updatedAt, fromCache: s.fromCache),
        _Hero(detail: d),
        if (_conflict != null)
          _PageBanner(
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
        if (_uncertain)
          _PageBanner(
            tone: AknTone.warn,
            icon: Icons.schedule_rounded,
            title: 'Kararınız doğrulanamadı',
            message:
                'Bağlantı gelince aynı kararı güvenle yeniden gönderebilirsiniz; '
                'iki kez işlenmez.',
            actionLabel: OrdersCopy.retry,
            onAction: () => setState(() => _uncertain = false),
          ),
        ..._financeBanners(context, d),
        ..._statusBanners(context, d, canCreate),
        if (d.status == OrderStatus.awaitingApproval)
          QuoteDecisionCard(
            view: v,
            decisionPending: _pending != null,
            onUploadDocument: v.documentTarget?.isUploadable == true
                ? () => _upload(v)
                : null,
          )
        else if (shownQuote != null && quoteCard != null)
          _QuoteSummary(quote: shownQuote, detail: d, kind: quoteCard),
        if (awaitingQuote && !d.financeStatus.isAwaitingDecision)
          SectionCard(
            title: d.status == OrderStatus.revisionRequested
                ? 'Revize teklif bekleniyor'
                : 'Teklif bekleniyor',
            icon: Icons.hourglass_top_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${OrdersCopy.awaitingQuoteHint}.',
                  style: context.aknText.body,
                ),
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
        if (d.paymentMethodCode != null)
          PaymentBlock(
            view: v,
            onUpload: v.documentTarget?.isUploadable == true
                ? () => _upload(v)
                : null,
          ),
        _DeliveryFacts(
          detail: d,
          pointName: point?.name,
          window: point?.windowLabel,
        ),
        if (v.tracking != null)
          TrackingCard(
            order: d,
            tracking: v.tracking!,
            point: point,
            station: awaitingQuote ? null : station,
          ),
        if (canDocs)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: AknCard(
              padding: EdgeInsets.zero,
              child: AknListTile(
                leadingIcon: Icons.folder_open_rounded,
                title: 'Sipariş belgeleri',
                subtitle: 'Sipariş formu, teklif, teslim tutanağı',
                onTap: () =>
                    context.push('${AppRoutes.documents}?orderId=${d.id}'),
              ),
            ),
          ),
        if (canCreate)
          SectionCard(
            title: 'Bu siparişle',
            icon: Icons.bolt_rounded,
            child: ButtonRow(
              children: [
                AknButton.secondary(
                  label: 'Tekrarla',
                  icon: Icons.replay_rounded,
                  expand: true,
                  semanticLabel: 'Bu siparişi tekrarla',
                  onPressed: () =>
                      context.push('${AppRoutes.orderNew}?reorder=${d.id}'),
                ),
                AknButton.secondary(
                  label: 'Şablon yap',
                  icon: Icons.bookmark_add_rounded,
                  expand: true,
                  semanticLabel: 'Bu siparişten şablon oluştur',
                  onPressedAsync: () => _makeTemplate(v),
                  showSuccess: false,
                ),
              ],
            ),
          ),
      ],
    );
  }

  List<Widget> _financeBanners(BuildContext context, OrderDetail d) {
    switch (d.financeStatus) {
      case OrderFinanceStatus.pending:
        return [
          const _PageBanner(
            tone: AknTone.info,
            icon: Icons.account_balance_rounded,
            title: 'Finans onayında',
            message:
                'Bayinin finans ekibi siparişinizi inceliyor; onaylanınca bayi teklif verir.',
          ),
        ];
      case OrderFinanceStatus.infoRequested:
        final id = d.financeApprovalRequestId;
        return [
          _PageBanner(
            tone: AknTone.warn,
            icon: Icons.mark_email_unread_rounded,
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
          _PageBanner(
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
          const _PageBanner(
            tone: AknTone.ok,
            icon: Icons.verified_rounded,
            title: 'Koşullu onaylandı',
            message: 'Finans, ödeme koşullarını güncelleyerek onayladı.',
          ),
        ];
      default:
        return const [];
    }
  }

  List<Widget> _statusBanners(
    BuildContext context,
    OrderDetail d,
    bool canCreate,
  ) => switch (d.status) {
    OrderStatus.expired => [
      _PageBanner(
        tone: AknTone.neutral,
        icon: Icons.timer_off_rounded,
        title: 'Süresi doldu',
        message:
            'Bu siparişin süresi doldu. Aynı siparişi yeniden verebilirsiniz.',
        actionLabel: canCreate ? 'Tekrarla' : null,
        onAction: canCreate
            ? () => context.push('${AppRoutes.orderNew}?reorder=${d.id}')
            : null,
      ),
    ],
    OrderStatus.rejected => [
      const _PageBanner(
        tone: AknTone.neutral,
        icon: Icons.do_not_disturb_on_rounded,
        title: 'Reddedildi',
        message: 'Bu sipariş kapandı.',
      ),
    ],
    _ => const [],
  };
}

class _PageBanner extends StatelessWidget {
  const _PageBanner({
    required this.tone,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final AknTone tone;
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => AknBanner(
    tone: tone,
    icon: icon,
    title: title,
    message: message,
    actionLabel: actionLabel,
    onAction: onAction,
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
  );
}

class _Hero extends StatelessWidget {
  const _Hero({required this.detail});

  final OrderDetail detail;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    return AknHeroPanel(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Builder(
        builder: (context) {
          final t = context.aknText;
          final c = context.akn;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(d.orderNumber, style: t.title),
                  StatusChip.style(
                    d.status.statusStyle.withLabel(d.statusDisplay),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${d.productName} · ${Fmt.liters(d.quantityLiters)}',
                style: t.headline,
              ),
              const SizedBox(height: 4),
              Text(
                [
                  d.stationTitle,
                  if (d.createdAt != null)
                    'Verildi ${Fmt.dateTime(d.createdAt)}',
                ].join(' · '),
                style: t.bodySmall.copyWith(color: c.dim),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DeliveryFacts extends StatelessWidget {
  const _DeliveryFacts({required this.detail, this.pointName, this.window});

  final OrderDetail detail;
  final String? pointName;
  final String? window;

  @override
  Widget build(BuildContext context) {
    final d = detail;
    return SectionCard(
      title: 'Teslimat',
      icon: Icons.place_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FactRow(
            label: 'Nokta',
            value:
                pointName ??
                (d.deliveryPointName.isEmpty ? Fmt.dash : d.deliveryPointName),
          ),
          if (d.deliveryAddress.isNotEmpty)
            FactRow(label: 'Adres', value: d.deliveryAddress),
          FactRow(
            label: 'İstenen tarih',
            value:
                '${Fmt.date(d.requestedDeliveryDate)}${window == null ? '' : ' · $window'}',
          ),
        ],
      ),
    );
  }
}

/// Karar ekranı dışındaki teklif kartının anlamı (başlık ve simge).
enum _QuoteKind {
  approved('Onaylanan teklif', Icons.verified_rounded),
  revisionRequested('Revize istenen teklif', Icons.edit_note_rounded),
  rejected('Reddedilen teklif', Icons.do_not_disturb_on_rounded),
  expired('Süresi dolan teklif', Icons.timer_off_rounded);

  const _QuoteKind(this.title, this.icon);

  final String title;
  final IconData icon;
}

class _QuoteSummary extends StatelessWidget {
  const _QuoteSummary({
    required this.quote,
    required this.detail,
    required this.kind,
  });

  final Quote quote;
  final OrderDetail detail;
  final _QuoteKind kind;

  @override
  Widget build(BuildContext context) => SectionCard(
    title: kind.title,
    icon: kind.icon,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FactRow(label: 'Birim fiyat', value: Fmt.unitPrice(quote.unitPriceTry)),
        FactRow(label: 'Toplam', value: Fmt.money(quote.totalAmountTry)),
        FactRow(
          label: 'Teslim tarihi',
          value: Fmt.date(quote.deliveryDate ?? detail.requestedDeliveryDate),
        ),
        FactRow(label: 'Sürüm', value: 'v${quote.version}'),
        if (kind == _QuoteKind.revisionRequested && quote.revisionNote != null)
          FactRow(label: 'Revize notunuz', value: quote.revisionNote!),
      ],
    ),
  );
}

/// Karar çubuğu: Onayla (belge eksikse / avans yetmezse / çevrimdışıyken kapalı), Revize iste,
/// Reddet. Belirsiz sonuçta "Kararınız kontrol ediliyor".
class _DecisionBar extends StatelessWidget {
  const _DecisionBar({
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
    final blockedReason = !online
        ? OrdersCopy.decisionOffline
        : view.paymentDocumentMissing
        ? '${view.documentTarget?.label ?? 'Ödeme belgesi'} yüklenmeden onaylanamaz'
        : view.advanceInsufficient
        ? 'Bakiye yetersiz; bayinizle görüşün'
        : null;
    final approve = AknButton(
      label: OrdersCopy.approve,
      icon: Icons.check_rounded,
      expand: true,
      loading: pending == QuoteAction.approve,
      semanticLabel: blockedReason == null
          ? 'Teklifi onayla'
          : 'Teklifi onayla, kapalı: $blockedReason',
      onPressed: busy || blockedReason != null
          ? null
          : () => onDecide(QuoteAction.approve),
    );
    final revise = AknButton.secondary(
      label: OrdersCopy.revise,
      expand: true,
      loading: pending == QuoteAction.revise,
      onPressed: busy || !online ? null : () => onDecide(QuoteAction.revise),
    );
    final reject = AknButton.ghost(
      label: OrdersCopy.reject,
      expand: true,
      loading: pending == QuoteAction.reject,
      onPressed: busy || !online ? null : () => onDecide(QuoteAction.reject),
    );
    final stacked = MediaQuery.textScalerOf(context).scale(15) > 19.5;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (checking)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: ChevronSpinner(size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    OrdersCopy.decisionChecking,
                    style: t.bodySmall.copyWith(color: c.text),
                  ),
                ),
              ],
            ),
          )
        else if (blockedReason != null && !busy)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: c.dim),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    blockedReason,
                    style: t.caption.copyWith(color: c.dim),
                  ),
                ),
              ],
            ),
          ),
        approve,
        const SizedBox(height: 6),
        if (stacked) ...[
          revise,
          const SizedBox(height: 4),
          reject,
        ] else
          Row(
            children: [
              Expanded(child: reject),
              const SizedBox(width: 12),
              Expanded(child: revise),
            ],
          ),
      ],
    );
  }
}

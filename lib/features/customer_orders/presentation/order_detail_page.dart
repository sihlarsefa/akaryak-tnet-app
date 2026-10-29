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
import '../../../core/routing/app_location.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
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

/// Sipariş ayrıntısı (spec A.4; tasarım v4 §5 ekran 05).
///
/// ```
/// (←) Sipariş (⋯)                       kaydırınca çubukta "Motorin, 8.000 L"
/// Motorin, 8.000 L                      AknObjectHeader (başlık, nokta · gün, kopyalanan kod)
/// Tuzla Şantiye · 29 Ekim
/// SIP-20261028-12002
/// ●━━━━●━━━━[»]┄┄┄┄○┄┄┄┄○              » Akış çizgisi (Sipariş · Teklif · Onay · Yolda · Teslim)
/// Teklifi onaylayın          ⏱ 2 sa 59 dk   StageNow: kimin sırası, ne zamana kadar
/// ╭ Demir Petrol teklifi · bugün 18:17 ╮   teklif plakası (r26, çerçevesiz)
/// │ 338.800,00 ₺ · 42,35 ₺/L · çek … │
/// ══ [ Çek görselini yükle ] → "Teklifi onayla"   karar çubuğu (ActionBar.decision)
///    Revize iste        Reddet
/// ```
///
/// Altında: yoldaki araç, sevkiyatlar, ödeme, sipariş bilgileri, "Sipariş geçmişi ›" (akış
/// çizelgesi sayfada açılır) ve belgeler. Birincil düğme her zaman yapılabilecek adımdır: eksik
/// belge önce yüklenir, sonra düğme "Teklifi onayla"ya dönüşür. `?focus=quote|documents` teklif
/// plakasını, `?focus=delivery` sevkiyatı gösterir ve parlatır.
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
        actionLabel: OrdersCopy.templates,
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
      context.push(AppRoutes.orderNewFrom(reorder: d.id));

  /// ⋯: siparişi tekrarla, şablon olarak kaydet, sipariş belgeleri.
  Future<void> _openMenu(
    OrderView v, {
    required bool canCreate,
    required bool canDocs,
  }) async {
    final choice = await showAppSheet<String>(
      context: context,
      title: orderTitle(v.detail.productName, v.detail.quantityLiters),
      padding: const EdgeInsets.only(bottom: 12),
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canCreate) ...[
            AknListTile(
              leadingIcon: PhosphorIconsRegular.arrowCounterClockwise,
              title: OrdersCopy.reorder,
              subtitle: 'Aynı ürün ve noktayla yeni sipariş',
              onTap: () => Navigator.of(ctx).pop('reorder'),
            ),
            AknListTile(
              leadingIcon: PhosphorIconsRegular.bookmarkSimple,
              title: OrdersCopy.makeTemplate,
              subtitle: 'Sonraki siparişlerde tek dokunuşla kullanın',
              onTap: () => Navigator.of(ctx).pop('template'),
            ),
          ],
          if (canDocs)
            AknListTile(
              leadingIcon: PhosphorIconsRegular.folderOpen,
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

  /// "Sipariş geçmişi": sunucunun takip adımları sayfada açılır (v4 §5: ayrıntıdaki akış kartı
  /// yerine bir satır).
  void _openHistory(OrderTracking tracking, bool yourMove) => unawaited(
    showAppSheet<void>(
      context: context,
      title: OrdersCopy.history,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: OrderFlowTimeline(steps: tracking.steps, yourMove: yourMove),
      ),
    ),
  );

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
    final focus = focusParamOf(context);

    Widget body;
    if (v == null && s.isFirstLoad) {
      body = const SkeletonList(itemCount: 4, lines: 3, leading: false);
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
          padding: EdgeInsets.only(
            bottom: 32 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            ContentWidth(
              child: _content(context, v, s, canDocs: canDocs, focus: focus),
            ),
          ],
        ),
      );
    }

    return AppScaffold(
      title: OrdersCopy.orderDetail,
      collapsedTitle: v == null
          ? null
          : orderTitle(v.detail.productName, v.detail.quantityLiters),
      largeTitle: false,
      refreshing: s.refreshing,
      actions: [
        if (v != null && (canCreate || canDocs))
          AknIconButton(
            icon: PhosphorIconsRegular.dotsThree,
            semanticLabel: 'Diğer seçenekler',
            onPressed: () =>
                _openMenu(v, canCreate: canCreate, canDocs: canDocs),
          ),
      ],
      actionBar: v == null
          ? null
          : _dock(
              v,
              online: online,
              canDecide: canDecide,
              canCreate: canCreate,
            ),
      body: body,
    );
  }

  /// Alt çubuk (v4 P3): her zaman şimdi yapılabilecek adım. Karar müşterideyken
  /// [ActionBar.decision]: eksik belge önce birincil düğmedir ("Çek görselini yükle"); yüklenince
  /// düğme "Teklifi onayla"ya dönüşür (onay işareti çıkar). Bakiye yetmiyorsa bayi aranır.
  /// Çevrimdışıyken düğme yok, neden yazılır.
  Widget? _dock(
    OrderView v, {
    required bool online,
    required bool canDecide,
    required bool canCreate,
  }) {
    final d = v.detail;
    final decisionOpen =
        d.status == OrderStatus.awaitingApproval &&
        v.latestQuote != null &&
        !d.financeStatus.isAwaitingDecision;
    if (decisionOpen && canDecide) {
      if (!online && _pending == null) {
        return const ActionBar(
          child: _DockNote(
            icon: PhosphorIconsRegular.cloudSlash,
            text: OrdersCopy.decisionOffline,
          ),
        );
      }
      final busy = _pending != null;
      final target = v.documentTarget;
      final home = ref.read(customerHomeProvider).data;
      final station = home?.station?.id == d.stationId ? home?.station : null;
      final tel = ContactLinks.tel(station?.callNumber);
      final revise = AknButton.ghost(
        label: OrdersCopy.revise,
        loading: _pending == QuoteAction.revise,
        onPressed: busy ? null : () => _decide(v, QuoteAction.revise),
      );
      final reject = AknButton.danger(
        label: OrdersCopy.reject,
        loading: _pending == QuoteAction.reject,
        onPressed: busy ? null : () => _decide(v, QuoteAction.reject),
      );
      AknButton primary;
      String? caption;
      var secondaries = <AknButton>[revise, reject];
      if (v.paymentDocumentMissing && target != null && target.isUploadable) {
        primary = AknButton(
          label: AknStatus.uploadAction(target.kind),
          icon: PhosphorIconsRegular.camera,
          celebrate: true,
          onPressed: () => unawaited(_upload(v)),
        );
        caption = 'Yükledikten sonra teklifi onaylayabilirsiniz';
      } else if (v.paymentDocumentMissing) {
        // Belgeyi bu kullanıcı yükleyemez: yapılabilecek adım revize istemek.
        primary = AknButton(
          label: OrdersCopy.revise,
          loading: _pending == QuoteAction.revise,
          onPressed: () => _decide(v, QuoteAction.revise),
        );
        secondaries = [reject];
        caption =
            target?.message ??
            '${target?.label ?? 'Ödeme belgesi'} yüklenmeden onaylanamaz; '
                'şirket yöneticiniz yükleyebilir.';
      } else if (v.advanceInsufficient) {
        caption =
            'Ön ödemeli bakiye yetersiz: kullanılabilir ${Fmt.money(v.advanceBalance)}';
        if (tel != null) {
          primary = AknButton(
            label: 'Bayinizi arayın',
            icon: PhosphorIconsRegular.phone,
            onPressed: () => unawaited(
              openExternal(
                context,
                ref,
                tel,
                failMessage: 'Arama başlatılamadı.',
              ),
            ),
          );
        } else {
          primary = AknButton(
            label: OrdersCopy.revise,
            loading: _pending == QuoteAction.revise,
            onPressed: () => _decide(v, QuoteAction.revise),
          );
          secondaries = [reject];
        }
      } else {
        primary = AknButton(
          label: OrdersCopy.approve,
          celebrate: true,
          loading: _pending == QuoteAction.approve,
          onPressed: () => _decide(v, QuoteAction.approve),
        );
      }
      if (_checking) caption = OrdersCopy.decisionChecking;
      return ActionBar.decision(
        primary: primary,
        caption: caption,
        secondaries: secondaries,
      );
    }

    final reported = v.tracking?.shipments
        .where((x) => x.status == ShipmentStatus.reported)
        .firstOrNull;
    if (reported != null && (v.tracking?.canAcceptDeliveries ?? false)) {
      return AknButton(
        label: OrdersCopy.confirmDelivery,
        icon: PhosphorIconsFill.checkCircle,
        expand: true,
        // Sevkiyatta kabul / itiraz sonrası dönüşte sipariş yeniden okunur; dock ve izleme
        // eski kalmaz (QA C-03).
        onPressed: () async {
          await context.push(AppRoutes.shipment(reported.id));
          if (!mounted) return;
          await ref.read(orderViewProvider(_id).notifier).reload();
        },
      );
    }
    if (d.financeStatus == OrderFinanceStatus.infoRequested && canDecide) {
      final id = d.financeApprovalRequestId;
      return AknButton(
        label: 'Bilgi gönder',
        icon: PhosphorIconsRegular.paperPlaneTilt,
        expand: true,
        onPressed: () => context.push(
          id == null ? AppRoutes.financeInfo : AppRoutes.approval(id),
        ),
      );
    }
    final closed =
        d.status == OrderStatus.completed ||
        d.status == OrderStatus.rejected ||
        d.status == OrderStatus.expired;
    if (closed && canCreate) {
      return AknButton(
        label: OrdersCopy.reorder,
        icon: PhosphorIconsRegular.arrowCounterClockwise,
        expand: true,
        semanticLabel: 'Bu siparişi tekrarla',
        onPressed: () => _reorder(d),
      );
    }
    return null;
  }

  Widget _content(
    BuildContext context,
    OrderView v,
    Loadable<OrderView> s, {
    required bool canDocs,
    required String? focus,
  }) {
    final d = v.detail;
    final home = ref.watch(customerHomeProvider).data;
    final form = ref.watch(orderFormProvider).data;
    final policy = ref.watch(accessPolicyProvider);
    final config = ref.watch(orderingConfigValueProvider);
    final viewer = customerViewer(policy);
    final station = home?.station?.id == d.stationId ? home?.station : null;
    final point = form?.point(d.deliveryPointId);
    final tracking = v.tracking;
    final active = tracking?.activeShipment;
    final awaitingQuote =
        d.status == OrderStatus.awaitingQuote ||
        d.status == OrderStatus.revisionRequested ||
        d.status == OrderStatus.created;
    final short = shortCompany(d.stationTitle);

    final lamp = orderLampFor(
      viewer,
      status: d.status,
      serverLabel: d.statusDisplay,
      shipment: active?.status,
      finance: d.financeStatus,
      actor: short.isEmpty ? null : short,
    );

    // Plakadaki teklif: karar ekranında en son sürüm; sonrasında seçili teklif kendi adıyla.
    // Sunucu her yeni teklifi "seçili" kaydeder ve revize / ret / süre dolumunda bunu değiştirmez.
    final decision = d.status == OrderStatus.awaitingApproval;
    final quoteTitle = switch (d.status) {
      OrderStatus.awaitingApproval =>
        short.isEmpty ? 'Teklif' : '$short teklifi',
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
        quote?.deliveryDate != null &&
        d.requestedDeliveryDate != null &&
        !TrTime.isSameDay(quote!.deliveryDate!, d.requestedDeliveryDate!);

    final expiryOn = config.expiryEnabled(tracking?.expiryEnabled ?? true);
    final expires = d.expiresAt;
    final deadline =
        expiryOn &&
            expires != null &&
            !d.financeStatus.isAwaitingDecision &&
            (decision || awaitingQuote)
        ? config.deviceDeadline(expires)
        : null;

    final pointName =
        point?.name ??
        (d.deliveryPointName.isEmpty ? null : d.deliveryPointName);
    final shipments = (tracking?.shipments ?? const <TrackingShipment>[])
        .where((x) => x.status != ShipmentStatus.cancelled)
        .toList();
    final cancelled = (tracking?.shipments.length ?? 0) - shipments.length;
    final versions = v.quoteVersions;
    final comparison = tracking?.priceComparison;
    final t = context.aknText;
    final c = context.akn;

    Widget pad(Widget child, {double top = 14, Key? key}) => Padding(
      key: key,
      padding: EdgeInsets.fromLTRB(AknSpace.page, top, AknSpace.page, 0),
      child: child,
    );

    // Ekranın tek kutusu: teklif plakası (karar ekranında son alımlarla kıyas da içinde); teklif
    // yoksa tahmini tutar.
    Widget? plate;
    if (quote != null && quoteTitle != null) {
      plate = QuotePlate(
        quote: quote,
        detail: d,
        title: quoteTitle,
        stamp: _stamp,
        line: [
          Fmt.unitPrice(quote.unitPriceTry),
          if (d.paymentMethodCode != null) paymentShortOf(d),
          if (deliveryDiffers)
            'teslim ${dayMonthLong(quote.deliveryDate)} '
                '(${TurkishText.lower(OrdersCopy.deliveryDiffers)})',
        ].join(' · '),
        below: decision && PriceComparison.shows(comparison)
            ? PriceComparison(
                comparison: comparison!,
                offer: quote.unitPriceTry,
                onPlate: true,
              )
            : null,
      );
    } else if (awaitingQuote && d.estimatedAmount != null) {
      plate = EstimatePlate(detail: d);
    }

    final countdown = deadline == null
        ? null
        : CountdownBadge(
            deadline: deadline,
            yourMove: lamp.yourMove,
            compact: true,
            subject: decision ? 'Teklif' : 'Teklif süresi',
          );
    // Büyük yazıda (≥ 1,3×) geri sayım cümlenin altına iner: satır taşmaz, cümle kesilmez.
    final largeText = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final Widget stage = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        StageNow(
          sentence: lamp.label,
          yourMove: lamp.yourMove,
          trailing: largeText ? null : countdown,
          detail: _stageDetail(
            v,
            lamp: lamp,
            station: short,
            deadline: deadline,
            active: active,
            pointWindow: point?.windowLabel,
          ),
        ),
        if (largeText && countdown != null) ...[
          const SizedBox(height: 6),
          Align(alignment: AlignmentDirectional.centerStart, child: countdown),
        ],
      ],
    );

    final hasHistory = tracking != null && tracking.steps.isNotEmpty;
    final moreRows = <Widget>[
      if (hasHistory)
        AknListTile(
          title: OrdersCopy.history,
          subtitle: 'Siparişin adımları ve zamanları',
          showChevron: true,
          onTap: () => _openHistory(tracking, lamp.yourMove),
        ),
      if (canDocs)
        AknListTile(
          title: 'Sipariş belgeleri',
          subtitle: 'Sipariş formu, teklif, teslim tutanağı',
          showChevron: true,
          onTap: () {
            AknHaptics.selection();
            context.push('${AppRoutes.documents}?orderId=${d.id}');
          },
        ),
    ];

    final dockUpload =
        decision &&
        v.paymentDocumentMissing &&
        (v.documentTarget?.isUploadable ?? false) &&
        policy.can(Pg.customerQuotes, Perm.edit);

    // Sayfanın blokları: açılışta sırayla yükselerek gelir, sonradan eklenen blok (uyarı, yeni
    // bölüm) kendi yerinde belirir.
    final blocks = <(String, Widget)>[
      // Nesne başlığı: insan adıyla sipariş; kod kopyalanan alt yazı.
      (
        'title',
        AknObjectHeader(
          title: orderTitle(d.productName, d.quantityLiters),
          line: [
            ?pointName,
            if (d.requestedDeliveryDate != null)
              dayMonthLong(d.requestedDeliveryDate),
          ].join(' · '),
          caption: d.orderNumber,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
        ),
      ),
      // » Akış çizgisi sayfa genişliğinde, altında kimin sırası olduğu.
      (
        'journey',
        pad(
          top: 0,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AknFlowLine(flow: AknFlow.customer(lamp)),
              const SizedBox(height: 16),
              stage,
            ],
          ),
        ),
      ),
      (
        'alerts',
        A2Swap(
          child: _conflict != null
              ? pad(
                  key: const ValueKey('conflict'),
                  AknBanner(
                    tone: AknTone.warn,
                    icon: PhosphorIconsRegular.cloudWarning,
                    title: OrdersCopy.conflict,
                    message: _conflict!,
                    actionLabel: OrdersCopy.refresh,
                    onAction: () {
                      setState(() => _conflict = null);
                      unawaited(_refresh());
                    },
                  ),
                )
              : _uncertain
              ? pad(
                  key: const ValueKey('uncertain'),
                  AknBanner(
                    tone: AknTone.warn,
                    icon: PhosphorIconsRegular.clock,
                    title: 'Kararınız doğrulanamadı',
                    message:
                        'Bağlantı gelince aynı kararı güvenle yeniden gönderebilirsiniz; '
                        'iki kez işlenmez.',
                    actionLabel: OrdersCopy.retry,
                    onAction: () => setState(() => _uncertain = false),
                  ),
                )
              : const SizedBox(key: ValueKey('calm'), width: double.infinity),
        ),
      ),
      // Yoldaki araç teklif plakasından önce gelir (o anın asıl bilgisi).
      if (active != null)
        (
          'active',
          AknFocusFlash(
            active: focus == 'delivery',
            child: ActiveShipmentSection(
              order: d,
              shipment: active,
              point: point,
              station: awaitingQuote ? null : station,
              canAccept: tracking?.canAcceptDeliveries ?? false,
            ),
          ),
        ),
      if (plate != null)
        (
          'plate',
          pad(
            top: 18,
            AknFocusFlash(
              active: focus == 'quote' || focus == 'documents',
              borderRadius: AknRadius.plate,
              child: plate,
            ),
          ),
        ),
      if (d.status == OrderStatus.revisionRequested &&
          quote?.revisionNote != null)
        (
          'revision',
          pad(
            top: 12,
            FactLine(
              icon: PhosphorIconsRegular.chatText,
              text: 'Revize notunuz: ',
              strong: quote!.revisionNote,
            ),
          ),
        ),
      // Teklif beklenirken bayiyle iletişim (karo yok, tek satır).
      if (awaitingQuote && station != null)
        (
          'station',
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: AknLedger(
              children: [
                AknListTile(
                  title: short.isEmpty ? 'Bayiniz' : 'Bayiniz · $short',
                  subtitle: OrdersCopy.awaitingQuoteHint,
                  subtitleMaxLines: 2,
                  footer: StationContactButtons(
                    station: station,
                    dense: true,
                    message:
                        '${d.orderNumber} numaralı siparişim hakkında yazıyorum.',
                  ),
                ),
              ],
            ),
          ),
        ),
      // Kısmi teslim kabul edildi, açık sevkiyat yok: siparişin neden açık kaldığı (sunucunun notu;
      // web "Sipariş henüz tamamlanmadı" uyarısı).
      if (d.status == OrderStatus.approved && v.completionHint != null)
        (
          'completion',
          pad(
            top: 16,
            MergeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sipariş henüz tamamlanmadı',
                    style: t.bodyStrong.copyWith(color: c.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    v.completionHint!,
                    style: t.bodySmall.copyWith(color: c.dim),
                  ),
                ],
              ),
            ),
          ),
        ),
      if (shipments.isNotEmpty)
        (
          'shipments',
          AknFocusFlash(
            active: focus == 'delivery' && active == null,
            child: OrderSection(
              title: 'Sevkiyatlar',
              count: shipments.length,
              bleed: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ShipmentRows(shipments: shipments, viewer: viewer),
                  if (cancelled > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                      child: Text(
                        '$cancelled sevkiyat planı iptal edildi.',
                        style: t.bodySmall.copyWith(color: c.dim),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      if (versions.length > 1)
        (
          'versions',
          OrderSection(
            title: OrdersCopy.versions,
            bleed: true,
            child: QuoteVersions(versions: versions),
          ),
        ),
      if (d.paymentMethodCode != null)
        (
          'payment',
          PaymentBlock(
            view: v,
            dockUpload: dockUpload,
            onUpload: v.documentTarget?.isUploadable == true
                ? () => _upload(v)
                : null,
          ),
        ),
      (
        'info',
        OrderSection(
          title: 'Sipariş bilgileri',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
      ),
      if (moreRows.isNotEmpty)
        (
          'more',
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: AknLedger(children: moreRows),
          ),
        ),
    ];

    // Bloklar birbiri ardına yükselerek gelir; giriş bitince içerik yeniden kurulmaz (teklif
    // kartının rakamları bir kez yuvarlanır).
    return A2RiseScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LastUpdatedNote(updatedAt: s.updatedAt, fromCache: s.fromCache),
          for (final (i, (id, block)) in blocks.indexed)
            A2Rise(key: ValueKey(id), index: i, child: block),
        ],
      ),
    );
  }

  /// StageNow'un ikinci satırı (v4 §3b): kim, ne zamana kadar ("Demir Petrol teklif verdi ·
  /// bugün 21:00'e kadar").
  String? _stageDetail(
    OrderView v, {
    required StatusLamp lamp,
    required String station,
    required DateTime? deadline,
    required TrackingShipment? active,
    String? pointWindow,
  }) {
    final d = v.detail;
    final who = station.isEmpty ? 'Bayiniz' : station;
    String? until() {
      final at = deadline;
      if (at == null) return null;
      return '${relativeDay(at)} ${withDative(Fmt.time(at))} kadar';
    }

    switch (d.financeStatus) {
      case OrderFinanceStatus.pending:
        return 'Bayinin finans ekibi siparişinizi inceliyor; onaylanınca teklif gelir.';
      case OrderFinanceStatus.infoRequested:
        return 'Yanıtınız ve istenen belge gelene kadar teklif verilemez.';
      case OrderFinanceStatus.rejected:
        return d.financeReasons ??
            'Bayinin finans ekibi bu siparişi onaylamadı; bayinizle görüşün.';
      default:
        break;
    }
    final s = active?.status;
    if (s != null &&
        (d.status == OrderStatus.approved ||
            d.status == OrderStatus.completed)) {
      final when = active?.scheduledAt;
      final day = when == null
          ? null
          : '${relativeDay(when)}${pointWindow == null ? '' : ', $pointWindow'}';
      return switch (s) {
        ShipmentStatus.planned => day == null ? null : '$day teslim',
        ShipmentStatus.inTransit => day == null ? null : 'Tahmini teslim $day',
        ShipmentStatus.reported => [
          if (active?.deliveredLiters != null)
            '${Fmt.liters(active!.deliveredLiters)} teslim edildi',
          if (active?.deliveredAt != null) relativeMoment(active!.deliveredAt),
        ].join(' · '),
        ShipmentStatus.disputed =>
          active?.disputeNote == null
              ? 'İtirazınız bayiye iletildi.'
              : 'İtirazınız: ${active!.disputeNote}',
        _ => null,
      };
    }
    return switch (d.status) {
      OrderStatus.awaitingApproval =>
        lamp.yourMove
            ? ['$who teklif verdi', ?until()].join(' · ')
            : 'Şirket yöneticiniz teklifi onaylayacak.',
      OrderStatus.awaitingQuote ||
      OrderStatus.created => 'Teklif gelince size haber veririz.',
      OrderStatus.revisionRequested => '$who yeni teklif hazırlıyor.',
      OrderStatus.approved => '$who sevkiyatı planlayacak.',
      OrderStatus.completed =>
        (v.tracking?.acceptedLiters ?? 0) > 0
            ? '${Fmt.liters(v.tracking!.acceptedLiters)} teslim alındı.'
            : null,
      OrderStatus.rejected => 'Bu sipariş kapandı.',
      OrderStatus.expired =>
        'Teklif süresi doldu. Aynı siparişi yeniden verebilirsiniz.',
      _ => null,
    };
  }
}

/// Karar çubuğunda düğme yerine bir neden (çevrimdışı): simge ve 14/20 soluk cümle.
class _DockNote extends StatelessWidget {
  const _DockNote({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AknSpace.minTap),
      child: Row(
        children: [
          ExcludeSemantics(child: Icon(icon, size: 20, color: c.dim)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: t.bodySmall.copyWith(color: c.dim)),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/models.dart';
import '../../../../core/offline/connectivity.dart';
import '../../../../core/routing/app_location.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../application/bayi_actions.dart';
import '../../application/bayi_grants.dart';
import '../../application/desk_controller.dart';
import '../../application/orders_controller.dart';
import '../../copy.dart';
import '../../data/order_models.dart';
import '../dispatch/plan_sheet.dart';
import '../dispatch/shipment_sheet.dart';
import '../widgets/bayi_widgets.dart';
import '../widgets/paged_list_body.dart';
import 'quote_sheet.dart';

/// Sipariş ayrıntısı (bayi; tasarım v4 "Sade" §5 07).
///
/// * Çubuk: geri · "Sipariş" · ⋯ (sipariş geçmişi, numarayı kopyala); zil yok. Sayfa kayınca
///   çubukta siparişin adı ("Motorin, 15.000 L").
/// * Üstte nesne başlığı (`AknObjectHeader`): üst satır müşteri (dokununca cari kartı), başlık
///   "Motorin, 15.000 L", satır "Pendik Lojistik Merkezi · 30 Ekim", altında kopyalanabilir sipariş
///   numarası.
/// * » Akış çizgisi sayfa genişliğinde, bayinin kelimeleriyle (Teklif · Müşteri onayı · Sevkiyat ·
///   Teslim) ve `StageNow`: "Teklif verin" + geri sayım, altında kimin ne zamana kadar yapacağı.
/// * Gövde: teklif yokken "Teklif" defteri (liste fiyatıyla tahmin, ödeme, son alım); teklif varsa
///   "Teklifiniz" plakası; Teslimat, Sevkiyatlar ve Teklif geçmişi defterleri (simge karosu yok).
/// * Alt çubuk `ActionBar.decision`: yetkiye göre tek birincil (Teklif ver / Teklifi güncelle,
///   Sevkiyat planla ya da Tamamla); diğerleri hayalet düğme. Birincil hiç kapalı değildir:
///   çevrimdışıyken dokununca ne gerektiğini söyler.
class BayiOrderDetailPage extends ConsumerStatefulWidget {
  const BayiOrderDetailPage({super.key, required this.orderId});

  final int orderId;

  @override
  ConsumerState<BayiOrderDetailPage> createState() =>
      _BayiOrderDetailPageState();
}

class _BayiOrderDetailPageState extends ConsumerState<BayiOrderDetailPage> {
  bool _completing = false;

  Future<void> _complete(BayiOrderBundle b) async {
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
      message: keepUnits('${why}Sipariş tamamlandı olarak işaretlenir.'),
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

  /// Alt çubuk (v4 `ActionBar.decision`): ilk eylem birincil, diğerleri hayalet.
  ActionBar? _dock(BayiOrderBundle b, Set<_OrderAction> actions) {
    if (actions.isEmpty) return null;
    final o = b.order;
    final g = ref.read(bayiGrantsProvider);
    final online = ref.watch(isOnlineProvider);
    void offline() => AppToast.info(
      'Çevrimdışısınız; işlem için bağlantı gerekli.',
      context: context,
    );
    double? suggestion;
    if (g.viewDesk) {
      final rows = ref.watch(quoteDeskProvider.select((s) => s.rows));
      for (final r in rows) {
        if (r.orderId == o.id) suggestion = r.suggestedUnitPrice;
      }
    }
    final revision = o.status == OrderStatus.revisionRequested;
    final buttons = <AknButton>[
      if (actions.contains(_OrderAction.quote))
        AknButton(
          label: revision ? 'Teklifi güncelle' : 'Teklif ver',
          onPressed: online
              ? () => showQuoteSheet(context, o, suggestion: suggestion)
              : offline,
        ),
      if (actions.contains(_OrderAction.plan))
        AknButton(
          label: 'Sevkiyat planla',
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
              : offline,
        ),
      if (actions.contains(_OrderAction.complete))
        AknButton(
          label: 'Tamamla',
          loading: _completing,
          onPressed: online ? () => unawaited(_complete(b)) : offline,
        ),
    ];
    return ActionBar.decision(
      primary: buttons.first,
      caption: online ? null : 'Çevrimdışısınız; işlem için bağlantı gerekli.',
      secondaries: [
        for (final s in buttons.skip(1))
          AknButton.ghost(
            label: s.label,
            loading: s.loading,
            onPressed: s.onPressed,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.orderId;
    final state = ref.watch(bayiOrderProvider(id));
    final c = ref.read(bayiOrderProvider(id).notifier);
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
    final o = bundle?.order;
    return AppScaffold(
      title: 'Sipariş',
      collapsedTitle: o == null
          ? null
          : keepUnits('${o.productName}, ${Fmt.liters(o.quantityLiters)}'),
      refreshing: state.refreshing,
      actions: [
        if (bundle != null)
          AknIconButton(
            icon: PhosphorIconsRegular.dotsThree,
            semanticLabel: 'Diğer işlemler',
            onPressed: () => _showMore(context, bundle, g),
          ),
      ],
      actionBar: bundle == null ? null : _dock(bundle, actions),
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

/// ⋯: sipariş geçmişi (zaman çizelgesi bir sayfada) ve sipariş numarasını kopyalama.
void _showMore(BuildContext context, BayiOrderBundle b, BayiGrants g) {
  final o = b.order;
  unawaited(
    showAppSheet<void>(
      context: context,
      title: 'Sipariş',
      subtitle: o.orderNumber,
      builder: (sheet) {
        void close() => Navigator.of(sheet).pop();
        return AknLedger(
          children: [
            if (b.timeline.isNotEmpty || b.timelineFailed)
              AknListTile(
                title: 'Sipariş geçmişi',
                subtitle: 'Siparişin bütün adımları ve saatleri',
                showChevron: true,
                onTap: () {
                  close();
                  _showHistory(context, b);
                },
              ),
            AknListTile(
              title: 'Sipariş numarasını kopyala',
              subtitle: o.orderNumber,
              onTap: () {
                close();
                unawaited(
                  Clipboard.setData(ClipboardData(text: o.orderNumber)),
                );
                AppToast.success(
                  '${o.orderNumber} kopyalandı',
                  context: context,
                );
              },
            ),
            if (g.viewPayments && o.paymentStatus != PaymentStatus.none)
              AknListTile(
                title: 'Tahsilat kaydı',
                subtitle: paymentMethodName(o.paymentMethodCode),
                showChevron: true,
                onTap: () {
                  close();
                  unawaited(GoRouter.of(context).push(AppRoutes.payment(o.id)));
                },
              ),
          ],
        );
      },
    ),
  );
}

/// "Sipariş geçmişi" sayfası: siparişin durum adımları ve saatleri.
void _showHistory(BuildContext context, BayiOrderBundle b) {
  final t = context.aknText;
  final c = context.akn;
  final lamp = b.order.status.isOpen;
  unawaited(
    showAppSheet<void>(
      context: context,
      title: 'Sipariş geçmişi',
      builder: (sheet) => b.timelineFailed
          ? Text(
              'Sipariş geçmişi yüklenemedi. Sayfayı aşağı çekerek yenileyin.',
              style: t.bodySmall.copyWith(color: c.dim),
            )
          : StepTimeline(
              yourMove: false,
              steps: _steps(
                b.order,
                b.timeline,
                large: isLargeText(context),
                open: lamp,
              ),
            ),
    ),
  );
}

/// Büyük yazı ölçeğinde zaman başlığın yanında değil alt satırda (çekirdek satırda esnemez).
List<TimelineStep> _steps(
  OrderDetail o,
  List<OrderTimelineItem> items, {
  required bool large,
  required bool open,
}) {
  final out = <TimelineStep>[];
  for (var i = 0; i < items.length; i++) {
    final e = items[i];
    final last = i == items.length - 1;
    final state = switch (e.toStatus) {
      OrderStatus.rejected => TimelineState.failed,
      OrderStatus.expired => TimelineState.warning,
      _ when last && open => TimelineState.current,
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

/// Siparişin şu anki sevkiyat durumu (lamba ve akış için): planlanacak litre varken yok (sipariş
/// "Sevkiyat planlayın" der); yoksa en çok ilgi isteyen sevkiyat.
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
  /// Finans onayı verilmiş (koşulsuz ya da koşullu).
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
  if (diff == 1) return 'yarın $time';
  return '${Fmt.dayMonth(at)} $time';
}

/// "bugün 21:00'e kadar", "yarın 09:17'ye kadar".
String _until(DateTime at) {
  final diff = TrTime.dayDiff(TrTime.now(), at);
  final day = switch (diff) {
    0 => 'bugün',
    1 => 'yarın',
    -1 => 'dün',
    _ => Fmt.dayMonth(at),
  };
  return '$day ${timeDative(Fmt.time(at))} kadar';
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
    final showCountdown =
        openStatus &&
        !financeWait &&
        expires != null &&
        expires.isAfter(DateTime.now().toUtc());
    final requested = o.requestedDeliveryDate;
    final focus = focusParamOf(context);

    // Son alım ve öneri (masa yüklüyse): "Son alım 41,55 ₺/L · 27 Eki".
    String? lastPurchase;
    if (g.viewDesk) {
      final rows = ref.watch(quoteDeskProvider.select((s) => s.rows));
      for (final r in rows) {
        if (r.orderId != o.id || r.recentPrices.isEmpty) continue;
        final p = r.recentPrices.first;
        lastPurchase = [
          Fmt.unitPrice(p.unitPriceTry),
          if (p.orderDate != null) Fmt.dayMonth(p.orderDate),
        ].join(' · ');
      }
    }

    final detail =
        _shipmentDetail(bundle) ??
        _detail(
          o,
          lamp,
          expires: showCountdown ? expires : null,
          financeWait: financeWait,
          remaining: bundle.remainingLiters,
        );

    final payment = _paymentLine(o);
    final paymentFact = FactRow(label: 'Ödeme', value: payment);
    final Widget paymentRow =
        g.viewPayments && o.paymentStatus != PaymentStatus.none
        ? _LinkedFact(
            semanticLabel: 'Ödeme: $payment. Tahsilat kaydını açar',
            onTap: () => GoRouter.of(context).push(AppRoutes.payment(o.id)),
            child: paymentFact,
          )
        : paymentFact;

    // Kartlar art arda yükselir; aşağıdakiler kaydırdıkça kayarak girer.
    var n = 0;
    Widget stagger(Widget child) => StaggerItem(index: n++, child: child);
    final place = o.deliveryPointName;
    return StaggerScope(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          FadeUp(
            offset: 10,
            child: AknObjectHeader(
              overline: o.customerTitle,
              onOverline: g.viewCustomers
                  ? () => GoRouter.of(
                      context,
                    ).push(AppRoutes.customer(o.customerId))
                  : null,
              title: keepUnits(
                '${o.productName}, ${Fmt.liters(o.quantityLiters)}',
              ),
              line: [
                if (place.isNotEmpty) place,
                if (requested != null) dayMonthLong(requested),
              ].join(' · '),
              caption: o.orderNumber,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            ),
          ),
          // » Akış: sayfa genişliğinde, etiketler görünür; altında şimdiki adım.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: AknFlowLine(flow: AknFlow.bayi(lamp)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: StageNow(
              sentence: lamp.label,
              yourMove: lamp.yourMove,
              trailing: showCountdown
                  ? CountdownBadge(
                      deadline: expires,
                      yourMove: lamp.yourMove,
                      compact: true,
                      subject: 'Teklif süresi',
                    )
                  : null,
              detail: detail,
            ),
          ),
          if (financeWait &&
              o.financeApprovalRequestId != null &&
              g.viewApprovals)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: AknInlineLink(
                  label: 'Onay talebini aç',
                  onTap: () => GoRouter.of(
                    context,
                  ).push(AppRoutes.approval(o.financeApprovalRequestId!)),
                ),
              ),
            ),
          // Teklif: teklif yokken olgular; teklif varsa plaka.
          AknFocusFlash(
            active: focus == 'quote',
            child: q == null
                ? _Section(
                    title: 'Teklif',
                    children: [
                      if (o.estimatedAmount != null)
                        FactRow(
                          label: 'Liste fiyatıyla tahmin',
                          value: '≈ ${Fmt.moneyWhole(o.estimatedAmount)}',
                        ),
                      paymentRow,
                      ?(lastPurchase == null
                          ? null
                          : FactRow(label: 'Son alım', value: lastPurchase)),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FadeUp(
                        offset: 24,
                        scale: 0.96,
                        duration: AknMotion.heroRise,
                        curve: AknMotion.emphasizedCurve,
                        child: _QuotePlate(order: o),
                      ),
                      _Section(
                        title: null,
                        top: 12,
                        children: [
                          paymentRow,
                          if (q.revisionNote != null)
                            FactRow(
                              label: 'Revize notu',
                              value: q.revisionNote!,
                            ),
                          if (finance.isSettled)
                            FactRow(
                              label: 'Finans',
                              value: [
                                finance.label,
                                ?o.financeReasons,
                              ].join('. '),
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
          // Kısmi teslim kabul edildi, açık sevkiyat yok: siparişin neden kapanmadığı (tek uyarı).
          if (o.status == OrderStatus.approved &&
              completionHint != null &&
              (!bundle.fulfillment!.invitesCompletion || g.completeOrder))
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: AknBanner(
                tone: AknTone.info,
                title: 'Sipariş henüz tamamlanmadı',
                message: completionHint,
              ),
            ),
          stagger(
            _Section(
              title: 'Teslimat',
              children: [
                if (o.deliveryAddress.isNotEmpty)
                  FactRow(label: 'Adres', value: o.deliveryAddress),
                FactRow(
                  label: 'İstenen teslim',
                  value: Fmt.longDate(o.requestedDeliveryDate),
                ),
                if (q?.deliveryDate != null &&
                    !_sameDay(q!.deliveryDate, o.requestedDeliveryDate))
                  FactRow(
                    label: 'Teklif teslim günü',
                    value: Fmt.longDate(q.deliveryDate),
                  ),
                FactRow(label: 'Oluşturuldu', value: whenShort(o.createdAt)),
              ],
            ),
          ),
          stagger(_ShipmentsSection(bundle: bundle)),
          if (o.quotes.length > 1)
            stagger(
              _Section(
                title: 'Teklif geçmişi',
                children: [
                  for (final v in [
                    ...o.quotes,
                  ]..sort((a, b) => b.version.compareTo(a.version)))
                    FactRow(
                      label: 'v${v.version} · ${whenShort(v.createdAt)}',
                      value:
                          '${Fmt.unitPrice(v.unitPriceTry)}${v.id == q?.id ? ' (güncel)' : ''}',
                      valueStyle: const TextStyle(
                        fontFeatures: AknNumerals.tabular,
                      ),
                    ),
                ],
              ),
            ),
          if (bundle.timelineFailed)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Text(
                'Sipariş geçmişi yüklenemedi. Sayfayı aşağı çekerek yenileyin.',
                style: t.bodySmall.copyWith(color: c.dim),
              ),
            ),
        ],
      ),
    );
  }

  /// Sevkiyattaki siparişin ikinci satırı: kim, ne zaman ("Ali Kaya · yükleme bugün 09:00").
  static String? _shipmentDetail(BayiOrderBundle b) {
    final status = orderShipmentStatus(b);
    final f = b.fulfillment;
    if (status == null || f == null) return null;
    final s = f.shipments.where((x) => x.status == status).firstOrNull;
    if (s == null) return null;
    final who = s.driverName.isEmpty ? null : s.driverName;
    final at = s.scheduledAt == null ? null : whenShort(s.scheduledAt);
    return switch (status) {
      ShipmentStatus.planned => [
        ?who,
        if (at != null) 'yükleme $at',
        if (who == null) 'şoför atanmadı',
      ].join(' · '),
      ShipmentStatus.inTransit => [
        ?who,
        if (s.vehiclePlate.isNotEmpty) Fmt.plate(s.vehiclePlate),
        if (at != null) 'çıkış $at',
      ].join(' · '),
      ShipmentStatus.reported =>
        '${b.order.customerTitle} teslimatı onaylayacak',
      ShipmentStatus.disputed =>
        '${b.order.customerTitle} teslimata itiraz etti',
      _ => null,
    };
  }

  static bool _sameDay(DateTime? a, DateTime? b) =>
      a != null && b != null && TrTime.dayDiff(a, b) == 0;

  /// StageNow'ın ikinci satırı: kim, ne zamana kadar.
  static String? _detail(
    OrderDetail o,
    StatusLamp lamp, {
    required DateTime? expires,
    required bool financeWait,
    required double remaining,
  }) {
    final by = expires == null ? null : _until(expires);
    if (financeWait) {
      return o.financeReasons ?? 'Finans kararı gelene kadar teklif verilemez.';
    }
    final who = o.customerTitle;
    return switch (o.status) {
      OrderStatus.awaitingQuote => [
        lamp.yourMove ? '$who teklifinizi bekliyor' : 'Teklif bekleniyor',
        ?by,
      ].join(' · '),
      OrderStatus.revisionRequested => ['$who revize istedi', ?by].join(' · '),
      OrderStatus.awaitingApproval => [
        '$who teklifinizi değerlendiriyor',
        ?by,
      ].join(' · '),
      OrderStatus.approved when remaining > 0 =>
        'Planlanacak ${Fmt.liters(remaining)}',
      OrderStatus.rejected => '$who teklifi reddetti',
      OrderStatus.expired => 'Karar süresi doldu',
      OrderStatus.completed => 'Sipariş kapandı',
      _ => null,
    };
  }

  /// "Havale / EFT (peşin), bekliyor", "Çek, 30 gün vade · tahsil edildi".
  static String _paymentLine(OrderDetail o) {
    final term = o.paymentTermDays ?? 0;
    final method = paymentMethodName(o.paymentMethodCode);
    final status = switch (o.paymentStatus) {
      PaymentStatus.pending => 'bekliyor',
      PaymentStatus.documentUploaded => 'belge yüklendi',
      PaymentStatus.collected => 'tahsil edildi',
      PaymentStatus.bounced => 'karşılıksız',
      PaymentStatus.refunded => 'iade edildi',
      PaymentStatus.cancelled => 'iptal edildi',
      _ => null,
    };
    final due = o.paymentDueDate == null
        ? null
        : 'son ödeme ${dayMonthLong(o.paymentDueDate!)}';
    return [
      [method, if (term > 0) '$term gün vade'].join(', '),
      ?status,
      ?due,
    ].join(' · ');
  }
}

/// Başlıklı olgu defteri: başlık (`SectionHeader`) ve tek kartta ince çizgiyle ayrılmış satırlar.
/// Başlıksızsa yalnızca kart.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.top});

  final String? title;
  final List<Widget> children;
  final double? top;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null)
          SectionHeader(title: title!)
        else
          SizedBox(height: top ?? 0),
        AknLedger(
          children: [
            for (final r in children)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: r,
              ),
          ],
        ),
      ],
    );
  }
}

/// Dokununca bir sayfa açan olgu satırı: olgu ve sağda ›; ekran okuyucuda tek düğme.
class _LinkedFact extends StatelessWidget {
  const _LinkedFact({
    required this.child,
    required this.onTap,
    required this.semanticLabel,
  });

  final Widget child;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    excludeSemantics: true,
    onTap: onTap,
    child: InkWell(
      onTap: () {
        AknHaptics.selection();
        onTap();
      },
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AknSpace.minTap),
        child: Row(
          children: [
            Expanded(child: child),
            const SizedBox(width: 6),
            Icon(
              PhosphorIconsRegular.caretRight,
              size: 16,
              color: context.akn.dim,
            ),
          ],
        ),
      ),
    ),
  );
}

/// "Teklifiniz" plakası: toplam (`338.800` + `,00 ₺`), birim fiyat ve teslim günü; sürüm ve saat
/// başlığın yanında.
class _QuotePlate extends StatelessWidget {
  const _QuotePlate({required this.order});

  final OrderDetail order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final q = o.currentQuote!;
    final total = q.totalAmountTry;
    final fixed = Fmt.number(total, minFraction: 2, maxFraction: 2);
    final comma = fixed.lastIndexOf(',');
    final whole = comma < 0 ? fixed : fixed.substring(0, comma);
    final decimals = comma < 0 ? null : fixed.substring(comma);
    final delivery = q.deliveryDate ?? o.requestedDeliveryDate;
    final spoken =
        'Teklifiniz ${Fmt.money(total)}, birim fiyat ${Fmt.unitPrice(q.unitPriceTry)}';
    return AknPlate(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      raised: false,
      semanticLabel: spoken,
      head: PlateHead(
        title: 'Teklifiniz',
        period: [
          if (q.version > 1) 'v${q.version}',
          whenShort(q.createdAt),
        ].join(' · '),
      ),
      figure: PlateFigure(
        value: whole,
        decimals: decimals,
        unit: '₺',
        semanticLabel: spoken,
      ),
      below: PlateClamp(
        child: PlateReadouts(
          items: [
            PlateReadout(
              label: 'Birim fiyat',
              value: Fmt.number(q.unitPriceTry, minFraction: 2, maxFraction: 4),
              unit: '₺/L',
            ),
            PlateReadout(
              label: 'Teslim',
              value: delivery == null ? Fmt.dash : dayMonthLong(delivery),
            ),
          ],
        ),
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
    // Onaydan önce sevkiyat yok: bölüm de yok (akış çizgisi "Sevkiyat"ın sırada olduğunu söyler).
    if (!approved && f.shipments.isEmpty) return const SizedBox.shrink();
    final accepted = bundle.acceptedLiters;
    final ratio = o.quantityLiters <= 0 ? 0.0 : accepted / o.quantityLiters;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionHeader(
          title: 'Sevkiyatlar',
          count: f.shipments.isEmpty ? null : f.shipments.length,
        ),
        if (approved)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Teslim alınan pay bir ilerlemedir: turuncu dolgu, mürekkep değer.
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
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Text(
              'Henüz sevkiyat planlanmadı.',
              style: t.bodySmall.copyWith(color: c.dim),
            ),
          )
        else
          AknLedger(
            children: [
              for (final s in f.shipments)
                AknListTile(
                  title: keepUnits(
                    '${whenShort(s.scheduledAt)} · ${Fmt.liters(s.deliveredLiters ?? s.plannedLiters)}',
                  ),
                  subtitle: [
                    if (s.vehiclePlate.isNotEmpty) Fmt.plate(s.vehiclePlate),
                    if (s.driverName.isNotEmpty) s.driverName,
                  ].join(' · '),
                  status: AknLamp.status(
                    AknStatus.shipmentLamp(s.status, g.viewer),
                  ),
                  semanticLabel: [
                    s.code,
                    whenShort(s.scheduledAt),
                    Fmt.liters(s.deliveredLiters ?? s.plannedLiters),
                    TurkishText.lower(
                      AknStatus.shipmentLamp(s.status, g.viewer).label,
                    ),
                    if (s.driverName.isNotEmpty) s.driverName,
                  ].join(', '),
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

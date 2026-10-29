import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/models.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../application/bayi_actions.dart';
import '../../application/bayi_grants.dart';
import '../../application/customers_controller.dart';
import '../../data/customer_models.dart';
import '../widgets/bayi_widgets.dart';
import '../widgets/paged_list_body.dart';
import 'customer_sheets.dart';

/// Cari 360-lite kartı (spec A.4 / B.7 `CustomerSummaryDto`, tasarım v3 "Akış"): sayfa başlığı (baş
/// harf yuvarlağı, ünvan, kod / VKN / yer, finans çipi), **tek kahraman kart "Kullanılabilir limit"**
/// (kalan, kullanım ölçeri, Limit / Kullanılan / Kullanım; yükselerek gelir), bekleyen limit talebi,
/// sonra beyaz kartlarda finans kartı, tahsilat özeti, açık / son siparişler, saha formları, teslimat
/// noktaları (pencere, tank, yetkili, erişim notu, harita), yetkililer, görüşme notları — kartlar art
/// arda yükselerek gelir. Eylemler yetkiye ve sunucu bayraklarına göre. Saha temsilcisi portföy
/// görünümünde not ve limit talebi görmez.
class BayiCustomerPage extends ConsumerWidget {
  const BayiCustomerPage({super.key, required this.customerId});

  final int customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(customerSummaryProvider(customerId));
    final c = ref.read(customerSummaryProvider(customerId).notifier);
    final s = state.data;
    final g = ref.watch(bayiGrantsProvider);
    final quote =
        s != null && s.actions.canQuote && (g.quoteOnDesk || g.quoteOnOrder);
    final form = s != null && s.actions.canCreateFieldForm && g.createFieldForm;
    final phone = s?.contacts.where((x) => x.phone != null).firstOrNull?.phone;
    return AppScaffold(
      // v4 §3.2: itilen sayfa nesnenin türüyle adlanır; kod başlıkta değil (P4).
      title: 'Cari',
      collapsedTitle: s?.title,
      refreshing: state.refreshing,
      actions: [
        if (phone != null)
          AknIconButton(
            icon: PhosphorIconsRegular.phone,
            semanticLabel: 'Cariyi ara',
            onPressed: () => callPhone(context, phone),
          ),
      ],
      actionBar: !quote && !form
          ? null
          : _ActionPair(
              primary: !quote
                  ? null
                  : AknButton(
                      label: 'Teklif ver',
                      expand: true,
                      onPressed: () => g.viewDesk
                          ? openDestination(
                              context,
                              '${AppRoutes.quoteDesk}?customerId=$customerId',
                            )
                          : openDestination(context, AppRoutes.bayiOrders),
                    ),
              secondary: !form
                  ? null
                  : AknButton.secondary(
                      label: 'Saha formu',
                      expand: true,
                      onPressed: () => GoRouter.of(context).push(
                        '${AppRoutes.fieldFormNew}?customerId=$customerId'
                        '&customerTitle=${Uri.encodeQueryComponent(s.title)}',
                      ),
                    ),
            ),
      body: LoadableBody<CustomerSummary>(
        state: state,
        onRetry: c.refresh,
        builder: (context, data) => PullToRefresh(
          onRefresh: c.refresh,
          child: _Body(summary: data),
        ),
      ),
    );
  }
}

/// Alt eylem çubuğundaki iki düğme (tasarım v3): yan yana eşit genişlikte; büyük yazıda alt alta tam
/// genişlik (iki satıra kırılan etiket düğmeleri farklı yükseklikte bırakmasın).
class _ActionPair extends StatelessWidget {
  const _ActionPair({this.primary, this.secondary});

  final Widget? primary;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final a = primary;
    final b = secondary;
    if (a == null || b == null) return a ?? b ?? const SizedBox.shrink();
    if (isLargeText(context)) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [a, const SizedBox(height: 10), b],
      );
    }
    return Row(
      children: [
        Expanded(child: a),
        const SizedBox(width: 12),
        Expanded(child: b),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.summary});

  final CustomerSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = summary;
    final g = ref.watch(bayiGrantsProvider);
    final t = context.aknText;
    final k = context.akn;
    // Kartlar art arda yükselir; aşağıdakiler kaydırdıkça kayarak girer.
    var n = 0;
    Widget stagger(Widget child) => StaggerItem(index: n++, child: child);
    const rowPad = EdgeInsets.fromLTRB(18, 12, 18, 12);
    return StaggerScope(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          FadeUp(offset: 10, child: _Header(summary: s)),
          if (!s.finance.canOrder)
            PageWell(
              top: 14,
              tone: AknTone.warn,
              icon: PhosphorIconsRegular.prohibit,
              title: 'Sipariş verilemiyor',
              message: s.finance.blockReason ?? s.finance.label,
            ),
          if (s.limit != null) _LimitPlate(summary: s),
          if (s.financeCard != null)
            stagger(_FinanceCard(card: s.financeCard!)),
          if (s.collections != null)
            stagger(_CollectionsCard(c: s.collections!)),
          if (s.openOrders.isNotEmpty)
            stagger(
              GroupCard(
                title: 'Açık siparişler',
                count: s.openOrders.length,
                padding: const EdgeInsets.only(bottom: 4),
                child: AknLedger(
                  children: [
                    for (final o in s.openOrders)
                      _OrderLine(order: o, canOpen: g.viewOrders),
                  ],
                ),
              ),
            ),
          if (s.lastOrders.isNotEmpty)
            stagger(
              GroupCard(
                title: 'Son siparişler',
                padding: const EdgeInsets.only(bottom: 4),
                child: AknLedger(
                  children: [
                    for (final o in s.lastOrders)
                      _OrderLine(order: o, canOpen: g.viewOrders),
                  ],
                ),
              ),
            ),
          if (s.openForms.isNotEmpty)
            stagger(
              GroupCard(
                title: 'Saha formları',
                count: s.openForms.length,
                padding: const EdgeInsets.only(bottom: 4),
                child: AknLedger(
                  children: [
                    for (final f in s.openForms)
                      AknListTile(
                        padding: rowPad,
                        title: f.formNumber,
                        amount: f.totalAmount == null
                            ? null
                            : Fmt.money(f.totalAmount),
                        amountMeta: Fmt.liters(f.totalLiters),
                        status: AknLamp.style(
                          f.status.statusStyle.withLabel(f.statusLabel),
                        ),
                        onTap: g.viewFieldForms
                            ? () => GoRouter.of(
                                context,
                              ).push(AppRoutes.fieldForm(f.id))
                            : null,
                      ),
                  ],
                ),
              ),
            ),
          if (s.deliveryPoints.isNotEmpty)
            stagger(
              GroupCard(
                title: 'Teslimat noktaları',
                count: s.deliveryPoints.length,
                padding: const EdgeInsets.only(bottom: 4),
                child: AknLedger(
                  children: [
                    for (final p in s.deliveryPoints) _PointRow(point: p),
                  ],
                ),
              ),
            ),
          if (s.contacts.isNotEmpty)
            stagger(
              GroupCard(
                title: 'Yetkililer',
                padding: const EdgeInsets.only(bottom: 4),
                child: AknLedger(
                  children: [
                    for (final c in s.contacts)
                      AknListTile(
                        padding: rowPad,
                        leading: AknAvatar(name: c.name, size: 40),
                        title: c.name,
                        subtitle: [
                          ?c.role,
                          if (c.phone != null) Fmt.phone(c.phone),
                          ?c.email,
                        ].join(', '),
                        trailing: c.phone == null
                            ? null
                            : AknIconButton(
                                icon: PhosphorIconsRegular.phone,
                                semanticLabel: '${c.name} ara',
                                onPressed: () => callPhone(context, c.phone!),
                              ),
                      ),
                  ],
                ),
              ),
            ),
          if (s.actions.canViewNotes) stagger(_NotesSection(summary: s)),
          if (s.isPortfolioView)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(
                      PhosphorIconsRegular.briefcase,
                      size: 16,
                      color: k.dim,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Portföy görünümü: görüşme notları ve limit talepleri bayi yöneticinizde.',
                      style: t.bodySmall.copyWith(color: k.dim),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Sayfa başlığı (tasarım v3): baş harf yuvarlağı (52 px), ünvan (`display`), kod / VKN / yer; altında
/// finans çipi, pasif ve portföy.
class _Header extends StatelessWidget {
  const _Header({required this.summary});

  final CustomerSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    final t = context.aknText;
    final c = context.akn;
    final status = s.finance.status;
    final meta = [
      if (s.taxNumberMasked != null) 'VKN ${s.taxNumberMasked}',
      ?s.place,
    ].join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: AknAvatar(name: s.title, size: 52),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.5,
                      child: Semantics(
                        header: true,
                        child: Text(
                          s.title,
                          style: t.display.copyWith(color: c.ink),
                        ),
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(meta, style: t.bodySmall.copyWith(color: c.dim)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              // Olağan durum ("Onaylı") yazılmaz (v4 P4); yalnızca istisna.
              if (status != null && status != FinanceProfileStatus.approved)
                AknLamp.style(status.statusStyle.withLabel(s.finance.label))
              else if (status == null && s.finance.label.isNotEmpty)
                AknLamp(label: s.finance.label, tone: AknTone.neutral),
              if (!s.isActive)
                const AknLamp(label: 'Pasif', tone: AknTone.neutral),
              if (s.isPortfolioView)
                const AknLamp(label: 'Portföyünüzde', tone: AknTone.info),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ekranın tek plakası: "Kullanılabilir limit" — kalan tutar (ya da litre), kullanım ölçeri (%80
/// uyarı çizgisi), Limit / Kullanılan / Kullanım; altında bekleyen talep ve "Limit talebi".
class _LimitPlate extends ConsumerWidget {
  const _LimitPlate({required this.summary});

  final CustomerSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = summary;
    final l = s.limit!;
    final g = ref.watch(bayiGrantsProvider);
    final t = context.aknText;
    final k = context.akn;
    final pending = s.pendingLimitRequest;
    final canRequest = s.actions.canRequestLimit && g.requestLimit;
    String num0(double? v) => Fmt.number((v ?? 0).round());
    final unit = l.isLiters ? 'L' : '₺';
    String amountText(double? v) =>
        l.isLiters ? Fmt.liters(v) : Fmt.money(v, decimals: 0);
    final remaining = l.remaining ?? ((l.amount ?? 0) - l.used);
    final usage = (l.usagePct ?? 0) / 100;
    final over = remaining < 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (l.isUnlimited)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: RowNote(
              icon: PhosphorIconsFill.gauge,
              text:
                  'Bu caride limit yok (limitsiz). Kullanılan ${amountText(l.used)}.',
            ),
          )
        else
          // Kahraman kart ilk açılışta yükselip büyüyerek gelir.
          FadeUp(
            offset: 24,
            scale: 0.94,
            duration: AknMotion.heroRise,
            curve: AknMotion.emphasizedCurve,
            child: AknPlate(
              margin: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              semanticLabel:
                  'Kullanılabilir limit ${amountText(remaining)}, kullanım ${Fmt.percent(l.usagePct)}',
              head: PlateHead(
                icon: PhosphorIconsFill.gauge,
                title: 'Kullanılabilir limit',
                period: l.periodLabel ?? l.period,
              ),
              figure: PlateFigure(
                value: num0(remaining),
                unit: unit,
                semanticLabel: 'Kullanılabilir limit ${amountText(remaining)}',
              ),
              delta: over
                  ? Row(
                      children: [
                        const PlateBang(),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Limit aşıldı',
                            style: t.bodyStrong.copyWith(color: k.ink),
                          ),
                        ),
                      ],
                    )
                  : null,
              chart: PlateMeter(
                value: usage.clamp(0.0, 1.0),
                threshold: 0.8,
                semanticLabel: 'Limit kullanımı',
                semanticValue: Fmt.percent(l.usagePct),
              ),
              below: PlateClamp(
                child: PlateReadouts(
                  items: [
                    PlateReadout(
                      label: 'Limit',
                      value: num0(l.amount),
                      unit: unit,
                    ),
                    PlateReadout(
                      label: 'Kullanılan',
                      value: num0(l.used),
                      unit: unit,
                    ),
                    PlateReadout(
                      label: 'Kullanım',
                      value: Fmt.percent(l.usagePct),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (pending != null)
          PageWell(
            top: 12,
            tone: AknTone.info,
            icon: PhosphorIconsRegular.hourglassHigh,
            title: 'Bekleyen limit talebi, merkez onayında',
            message: [
              if (pending.period != null) pending.period!,
              if (pending.amount != null)
                pending.limitType == 'Litre'
                    ? Fmt.liters(pending.amount)
                    : Fmt.money(pending.amount, decimals: 0),
              if (pending.createdAt != null)
                TurkishText.lower(Fmt.relative(pending.createdAt)),
            ].join(', '),
          ),
        if (canRequest)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: AknButton.secondary(
                label: 'Limit talebi',
                icon: PhosphorIconsRegular.trendUp,
                size: AknButtonSize.small,
                onPressed: () => showLimitRequestSheet(context, s),
              ),
            ),
          ),
      ],
    );
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

class _FinanceCard extends ConsumerWidget {
  const _FinanceCard({required this.card});

  final SummaryFinanceCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = card;
    return GroupCard(
      title: 'Finans kartı',
      actionLabel: 'Kartı aç',
      onAction: () => GoRouter.of(
        context,
      ).push(AppRoutes.financeCustomer(c.stationCustomerId)),
      child: _Facts(
        children: [
          if (c.status != null)
            FactRow(
              label: 'Durum',
              value: c.statusLabel ?? c.status!.label,
              tone: c.status!.statusStyle.tone,
            ),
          FactRow(
            label: 'Risk sınıfı',
            value: c.riskClassLabel ?? c.riskClass.label,
            tone: c.riskClass.isHighRisk ? AknTone.warn : null,
          ),
          if (c.nextReviewDate != null)
            FactRow(
              label: 'Sonraki gözden geçirme',
              value: Fmt.date(c.nextReviewDate),
            ),
          if (c.hasBouncedCheque)
            const FactRow(
              label: 'Karşılıksız çek',
              value: 'Var',
              tone: AknTone.danger,
            ),
          if (c.hasProtestedNote)
            const FactRow(
              label: 'Protestolu senet',
              value: 'Var',
              tone: AknTone.danger,
            ),
          if (!c.hasProfile)
            FactRow(
              label: 'Kart',
              value: c.isGrandfathered
                  ? 'Eski bağlantı (kartsız onaylı)'
                  : 'Kart oluşturulmadı',
            ),
        ],
      ),
    );
  }
}

class _CollectionsCard extends StatelessWidget {
  const _CollectionsCard({required this.c});

  final SummaryCollections c;

  @override
  Widget build(BuildContext context) {
    return GroupCard(
      title: 'Tahsilat',
      actionLabel: 'Tümü',
      onAction: () => openDestination(context, AppRoutes.payments),
      child: _Facts(
        children: [
          FactRow(
            label: 'Vadesi geçen',
            value: c.overdueCount == 0
                ? 'Yok'
                : '${c.overdueCount} ödeme, ${Fmt.money(c.overdueAmount)}',
            tone: c.overdueCount > 0 ? AknTone.danger : AknTone.ok,
          ),
          FactRow(
            label: 'Açık çek / senet',
            value: c.openInstruments == 0
                ? 'Yok'
                : '${c.openInstruments} adet'
                      '${c.nextInstrumentDue == null ? '' : ', ilk vade ${Fmt.date(c.nextInstrumentDue)}'}',
          ),
          if (c.advanceBalance != null)
            FactRow(
              label: 'Avans bakiyesi',
              value: Fmt.money(c.advanceBalance),
              valueStyle: const TextStyle(fontFeatures: AknNumerals.tabular),
            ),
        ],
      ),
    );
  }
}

/// Cari kartındaki sipariş satırı: ürün ve litre, numara ve tarih, tutar, durum lambası.
class _OrderLine extends ConsumerWidget {
  const _OrderLine({required this.order, required this.canOpen});

  final SummaryOrder order;
  final bool canOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = order;
    final viewer = ref.watch(bayiGrantsProvider).viewer;
    return AknListTile(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      title: keepUnits(
        [?o.productName, Fmt.liters(o.quantityLiters)].join(', '),
      ),
      subtitle: [
        o.orderNumber,
        if (o.createdAt != null) Fmt.date(o.createdAt),
      ].join(', '),
      amount: o.totalAmount == null ? null : Fmt.money(o.totalAmount),
      status: AknLamp.status(
        AknStatus.lampFor(o.status, viewer, serverLabel: o.statusLabel),
      ),
      onTap: canOpen
          ? () => GoRouter.of(context).push(AppRoutes.bayiOrder(o.id))
          : null,
    );
  }
}

/// Teslimat noktası satırı: ad, adres; pencere ve tank; erişim notu; sorumlu; "Sorumluyu ara",
/// "Haritada aç".
class _PointRow extends StatelessWidget {
  const _PointRow({required this.point});

  final SummaryDeliveryPoint point;

  @override
  Widget build(BuildContext context) {
    final p = point;
    final t = context.aknText;
    final c = context.akn;
    final address = [
      ?p.address,
      [?p.district, ?p.city].join(' / '),
    ].where((s) => s.isNotEmpty).join(', ');
    final facts = [
      if (p.window != null) 'Teslim ${p.window}',
      if (p.tankCapacityLiters != null)
        'tank ${Fmt.liters(p.tankCapacityLiters)}',
    ].join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.name, style: t.headline.copyWith(color: c.ink)),
          if (address.isNotEmpty)
            Text(address, style: t.bodySmall.copyWith(color: c.dim)),
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 6),
            RowNote(icon: PhosphorIconsRegular.clock, text: keepUnits(facts)),
          ],
          if (p.accessNotes != null) ...[
            const SizedBox(height: 4),
            RowNote(
              icon: PhosphorIconsRegular.door,
              text: 'Erişim: ${p.accessNotes}',
            ),
          ],
          if (p.contactName != null) ...[
            const SizedBox(height: 4),
            RowNote(
              icon: PhosphorIconsRegular.user,
              text:
                  'Sorumlu: ${p.contactName}${p.contactPhone == null ? '' : ', ${Fmt.phone(p.contactPhone)}'}',
            ),
          ],
          if (p.contactPhone != null || p.canOpenMap)
            Wrap(
              spacing: 20,
              children: [
                if (p.contactPhone != null)
                  AknInlineLink(
                    label: 'Sorumluyu ara',
                    onTap: () => callPhone(context, p.contactPhone!),
                  ),
                if (p.canOpenMap)
                  AknInlineLink(
                    label: 'Haritada aç',
                    onTap: () => openMap(
                      context,
                      latitude: p.latitude!,
                      longitude: p.longitude!,
                      label: p.name,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _NotesSection extends ConsumerWidget {
  const _NotesSection({required this.summary});

  final CustomerSummary summary;

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    CustomerNote n,
  ) async {
    final ok = await showConfirmSheet(
      context,
      title: 'Not silinsin mi?',
      message: n.body,
      confirmLabel: 'Sil',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(bayiActionsProvider).deleteNote(summary.customerId, n.id);
      ref
          .read(customerSummaryProvider(summary.customerId).notifier)
          .removeNote(n.id);
      if (context.mounted) AppToast.success('Not silindi.', context: context);
    } catch (e) {
      if (context.mounted) showActionFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = summary;
    final t = context.aknText;
    final k = context.akn;
    final g = ref.watch(bayiGrantsProvider);
    final canAdd = s.actions.canAddNote && g.addCustomerNote;
    return GroupCard(
      title: 'Görüşme notları',
      actionLabel: canAdd ? 'Not ekle' : null,
      onAction: canAdd ? () => showAddNoteSheet(context, s.customerId) : null,
      padding: EdgeInsets.only(bottom: s.notes.isEmpty ? 14 : 4),
      child: s.notes.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text(
                'Henüz not yok.',
                style: t.bodySmall.copyWith(color: k.dim),
              ),
            )
          : AknLedger(
              children: [
                for (final n in s.notes)
                  // Yeni not kayarak girer.
                  StaggerItem(
                    key: ValueKey(n.id),
                    index: 0,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        18,
                        10,
                        8,
                        10,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  n.body,
                                  style: t.body.copyWith(color: k.ink),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${n.createdByDisplay}, ${TurkishText.lower(Fmt.relative(n.createdAt))}',
                                  style: t.caption.copyWith(color: k.dim),
                                ),
                              ],
                            ),
                          ),
                          if (n.canDelete && canAdd)
                            AknIconButton(
                              icon: PhosphorIconsRegular.trash,
                              semanticLabel: 'Notu sil',
                              onPressed: () =>
                                  unawaited(_delete(context, ref, n)),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

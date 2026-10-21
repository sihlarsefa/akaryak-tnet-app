import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/bayi_actions.dart';
import '../../application/bayi_grants.dart';
import '../../application/customers_controller.dart';
import '../../data/customer_models.dart';
import '../widgets/bayi_widgets.dart';
import '../widgets/paged_list_body.dart';
import 'customer_sheets.dart';

/// Cari 360-lite kartı (spec A.4 / B.7 `CustomerSummaryDto`): limit göstergesi, bekleyen limit talebi,
/// finans durumu ve finans kartı bağlantısı, tahsilat özeti, açık / son siparişler, saha formları,
/// teslimat noktaları (pencere, tank, yetkili, erişim notu, harita), yetkililer, görüşme notları;
/// eylemler yetkiye ve sunucu bayraklarına göre. Saha temsilcisi portföy görünümünde not ve limit
/// talebi görmez.
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
      title: s?.title ?? 'Cari',
      subtitle: s?.code,
      refreshing: state.refreshing,
      actions: [
        if (phone != null)
          AknIconButton(
            icon: Icons.call_outlined,
            semanticLabel: 'Cariyi ara',
            onPressed: () => callPhone(context, phone),
          ),
      ],
      actionBar: !quote && !form
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (quote)
                      Expanded(
                        child: AknButton(
                          label: 'Teklif ver',
                          icon: Icons.request_quote_rounded,
                          expand: true,
                          onPressed: () => g.viewDesk
                              ? openDestination(
                                  context,
                                  '${AppRoutes.quoteDesk}?customerId=$customerId',
                                )
                              : openDestination(context, AppRoutes.bayiOrders),
                        ),
                      ),
                    if (quote && form) const SizedBox(width: 12),
                    if (form)
                      Expanded(
                        child: AknButton.secondary(
                          label: 'Saha formu',
                          icon: Icons.post_add_rounded,
                          expand: true,
                          onPressed: () => GoRouter.of(context).push(
                            '${AppRoutes.fieldFormNew}?customerId=$customerId'
                            '&customerTitle=${Uri.encodeQueryComponent(s.title)}',
                          ),
                        ),
                      ),
                  ],
                ),
              ],
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

class _Body extends ConsumerWidget {
  const _Body({required this.summary});

  final CustomerSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = summary;
    final g = ref.watch(bayiGrantsProvider);
    final t = context.aknText;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _Hero(summary: s),
        if (!s.finance.canOrder)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: AknBanner(
              tone: AknTone.warn,
              icon: Icons.block_rounded,
              title: 'Sipariş verilemiyor',
              message: s.finance.blockReason ?? s.finance.label,
            ),
          ),
        if (s.limit != null) _LimitCard(summary: s),
        if (s.financeCard != null) _FinanceCard(card: s.financeCard!),
        if (s.collections != null) _CollectionsCard(c: s.collections!),
        if (s.openOrders.isNotEmpty) ...[
          BayiSectionHeader(
            title: 'Açık siparişler',
            count: s.openOrders.length,
          ),
          SectionCard(
            child: Column(
              children: [
                for (final o in s.openOrders)
                  _OrderLine(order: o, canOpen: g.viewOrders),
              ],
            ),
          ),
        ],
        if (s.lastOrders.isNotEmpty) ...[
          const BayiSectionHeader(title: 'Son siparişler'),
          SectionCard(
            child: Column(
              children: [
                for (final o in s.lastOrders)
                  _OrderLine(order: o, canOpen: g.viewOrders),
              ],
            ),
          ),
        ],
        if (s.openForms.isNotEmpty) ...[
          BayiSectionHeader(title: 'Saha formları', count: s.openForms.length),
          SectionCard(
            child: Column(
              children: [
                for (final f in s.openForms)
                  AknListTile(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    title: f.formNumber,
                    subtitle: [
                      Fmt.liters(f.totalLiters),
                      if (f.totalAmount != null) Fmt.money(f.totalAmount),
                    ].join(' · '),
                    trailing: FitEnd(
                      child: StatusChip.style(
                        f.status.statusStyle.withLabel(f.statusLabel),
                        size: StatusChipSize.small,
                      ),
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
        ],
        if (s.deliveryPoints.isNotEmpty) ...[
          BayiSectionHeader(
            title: 'Teslimat noktaları',
            count: s.deliveryPoints.length,
          ),
          for (final p in s.deliveryPoints) _PointCard(point: p),
        ],
        if (s.contacts.isNotEmpty) ...[
          const BayiSectionHeader(title: 'Yetkililer'),
          SectionCard(
            child: Column(
              children: [
                for (final c in s.contacts)
                  AknListTile(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    leading: AknAvatar(name: c.name, size: 36),
                    title: c.name,
                    subtitle: [
                      ?c.role,
                      if (c.phone != null) Fmt.phone(c.phone),
                      ?c.email,
                    ].join(' · '),
                    trailing: c.phone == null
                        ? null
                        : AknIconButton(
                            icon: Icons.call_outlined,
                            semanticLabel: '${c.name} ara',
                            onPressed: () => callPhone(context, c.phone!),
                          ),
                  ),
              ],
            ),
          ),
        ],
        if (s.actions.canViewNotes) _NotesSection(summary: s),
        if (s.isPortfolioView)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              'Portföy görünümü: görüşme notları ve limit talepleri bayi yöneticinizde.',
              style: t.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.summary});

  final CustomerSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return AknHeroPanel(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Builder(
        builder: (context) {
          final t = context.aknText;
          final c = context.akn;
          final status = s.finance.status;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AknAvatar(name: s.title, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(s.title, style: t.headline),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                [
                  ?s.code,
                  if (s.taxNumberMasked != null) 'VKN ${s.taxNumberMasked}',
                  ?s.place,
                ].join(' · '),
                style: t.bodySmall.copyWith(color: c.dim),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (status != null)
                    FitStart(
                      child: StatusChip.style(
                        status.statusStyle.withLabel(s.finance.label),
                      ),
                    )
                  else if (s.finance.label.isNotEmpty)
                    FitStart(
                      child: StatusChip(
                        label: s.finance.label,
                        tone: AknTone.neutral,
                        icon: Icons.account_balance_outlined,
                      ),
                    ),
                  if (!s.isActive)
                    const StatusChip(
                      label: 'Pasif',
                      tone: AknTone.neutral,
                      icon: Icons.block_rounded,
                    ),
                  if (s.isPortfolioView)
                    const StatusChip(
                      label: 'Portföyünüzde',
                      tone: AknTone.info,
                      icon: Icons.storefront_rounded,
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LimitCard extends ConsumerWidget {
  const _LimitCard({required this.summary});

  final CustomerSummary summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = summary;
    final l = s.limit!;
    final g = ref.watch(bayiGrantsProvider);
    final t = context.aknText;
    String fmt(double? v) =>
        l.isLiters ? Fmt.liters(v) : Fmt.money(v, decimals: 0);
    final pending = s.pendingLimitRequest;
    final canRequest = s.actions.canRequestLimit && g.requestLimit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BayiSectionHeader(
          title: 'Limit',
          subtitle: l.isUnlimited ? null : (l.periodLabel ?? l.period),
          actionLabel: canRequest ? 'Limit talebi' : null,
          onAction: canRequest ? () => showLimitRequestSheet(context, s) : null,
        ),
        SectionCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (l.isUnlimited)
                Text('Bu caride limit yok (limitsiz).', style: t.body)
              else ...[
                BayiUsageBar(
                  value: (l.usagePct ?? 0) / 100,
                  label: 'Kullanım',
                  valueLabel: Fmt.percent(l.usagePct),
                  tone: limitTone(l.tone),
                ),
                const SizedBox(height: 8),
                FactRow(label: 'Limit', value: fmt(l.amount)),
                FactRow(label: 'Kullanılan', value: fmt(l.used)),
                if (l.remaining != null)
                  FactRow(
                    label: 'Kalan',
                    value: fmt(l.remaining),
                    tone: (l.remaining ?? 0) < 0 ? AknTone.danger : null,
                  ),
              ],
              if (pending != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 6),
                  child: AknBanner(
                    tone: AknTone.info,
                    icon: Icons.hourglass_top_rounded,
                    title: 'Bekleyen limit talebi · merkez onayında',
                    message: [
                      if (pending.period != null) pending.period!,
                      if (pending.amount != null)
                        pending.limitType == 'Litre'
                            ? Fmt.liters(pending.amount)
                            : Fmt.money(pending.amount, decimals: 0),
                      if (pending.createdAt != null)
                        Fmt.relative(pending.createdAt),
                    ].join(' · '),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FinanceCard extends ConsumerWidget {
  const _FinanceCard({required this.card});

  final SummaryFinanceCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BayiSectionHeader(
          title: 'Finans kartı',
          actionLabel: 'Kartı aç',
          onAction: () => GoRouter.of(
            context,
          ).push(AppRoutes.financeCustomer(c.stationCustomerId)),
        ),
        SectionCard(
          child: Column(
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
        ),
      ],
    );
  }
}

class _CollectionsCard extends StatelessWidget {
  const _CollectionsCard({required this.c});

  final SummaryCollections c;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BayiSectionHeader(
          title: 'Tahsilat',
          actionLabel: 'Tümü',
          onAction: () => openDestination(context, AppRoutes.payments),
        ),
        SectionCard(
          child: Column(
            children: [
              FactRow(
                label: 'Vadesi geçen',
                value: c.overdueCount == 0
                    ? 'Yok'
                    : '${c.overdueCount} ödeme · ${Fmt.money(c.overdueAmount)}',
                tone: c.overdueCount > 0 ? AknTone.danger : AknTone.ok,
              ),
              FactRow(
                label: 'Açık çek / senet',
                value: c.openInstruments == 0
                    ? 'Yok'
                    : '${c.openInstruments} adet'
                          '${c.nextInstrumentDue == null ? '' : ' · ilk vade ${Fmt.date(c.nextInstrumentDue)}'}',
              ),
              if (c.advanceBalance != null)
                FactRow(
                  label: 'Avans bakiyesi',
                  value: Fmt.money(c.advanceBalance),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrderLine extends StatelessWidget {
  const _OrderLine({required this.order, required this.canOpen});

  final SummaryOrder order;
  final bool canOpen;

  @override
  Widget build(BuildContext context) {
    final o = order;
    return AknListTile(
      padding: const EdgeInsets.symmetric(vertical: 10),
      title: o.orderNumber,
      subtitle: [
        ?o.productName,
        Fmt.liters(o.quantityLiters),
        if (o.totalAmount != null) Fmt.money(o.totalAmount),
        if (o.createdAt != null) Fmt.date(o.createdAt),
      ].join(' · '),
      trailing: FitEnd(
        child: StatusChip.style(
          o.status.statusStyle.withLabel(o.statusLabel),
          size: StatusChipSize.small,
        ),
      ),
      onTap: canOpen
          ? () => GoRouter.of(context).push(AppRoutes.bayiOrder(o.id))
          : null,
    );
  }
}

class _PointCard extends StatelessWidget {
  const _PointCard({required this.point});

  final SummaryDeliveryPoint point;

  @override
  Widget build(BuildContext context) {
    final p = point;
    final t = context.aknText;
    return AknCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.name, style: t.bodyStrong),
          if (p.address != null || p.district != null || p.city != null)
            Text(
              [
                ?p.address,
                [?p.district, ?p.city].join(' / '),
              ].where((s) => s.isNotEmpty).join(', '),
              style: t.bodySmall,
            ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (p.window != null)
                ToneTag(
                  label: 'Teslim ${p.window}',
                  tone: AknTone.info,
                  icon: Icons.schedule_rounded,
                ),
              if (p.tankCapacityLiters != null)
                ToneTag(
                  label: 'Tank ${Fmt.liters(p.tankCapacityLiters)}',
                  icon: Icons.propane_tank_outlined,
                ),
            ],
          ),
          if (p.accessNotes != null) ...[
            const SizedBox(height: 6),
            Text('Erişim: ${p.accessNotes}', style: t.bodySmall),
          ],
          if (p.contactName != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Sorumlu: ${p.contactName}${p.contactPhone == null ? '' : ' · ${Fmt.phone(p.contactPhone)}'}',
                style: t.bodySmall,
              ),
            ),
          Wrap(
            spacing: 4,
            children: [
              if (p.contactPhone != null)
                TextButton.icon(
                  onPressed: () => callPhone(context, p.contactPhone!),
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text('Sorumluyu ara'),
                ),
              if (p.canOpenMap)
                TextButton.icon(
                  onPressed: () => openMap(
                    context,
                    latitude: p.latitude!,
                    longitude: p.longitude!,
                    label: p.name,
                  ),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Haritada aç'),
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
    final g = ref.watch(bayiGrantsProvider);
    final canAdd = s.actions.canAddNote && g.addCustomerNote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BayiSectionHeader(
          title: 'Görüşme notları',
          actionLabel: canAdd ? 'Not ekle' : null,
          onAction: canAdd
              ? () => showAddNoteSheet(context, s.customerId)
              : null,
        ),
        SectionCard(
          child: s.notes.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('Henüz not yok.', style: t.bodySmall),
                )
              : Column(
                  children: [
                    for (final n in s.notes)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(n.body, style: t.body),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${n.createdByDisplay} · ${Fmt.relative(n.createdAt)}',
                                    style: t.caption,
                                  ),
                                ],
                              ),
                            ),
                            if (n.canDelete && canAdd)
                              AknIconButton(
                                icon: Icons.delete_outline_rounded,
                                semanticLabel: 'Notu sil',
                                onPressed: () =>
                                    unawaited(_delete(context, ref, n)),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

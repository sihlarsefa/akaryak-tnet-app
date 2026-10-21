import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/models/models.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../application/bayi_grants.dart';
import '../../data/home_models.dart';
import '../dispatch/shipment_sheet.dart';
import '../widgets/bayi_widgets.dart';

/// İki sütunlu KPI ızgarası (360 dp'de ve 200 % yazıda taşmaz).
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      rows.add(
        KpiRow(
          children: [
            tiles[i],
            if (i + 1 < tiles.length) tiles[i + 1] else const SizedBox.shrink(),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            rows[i],
          ],
        ],
      ),
    );
  }
}

/// Teklifler (masa KPI'ları, süresi yaklaşanlar, en eski teklif bekleyenler).
class DeskSectionView extends ConsumerWidget {
  const DeskSectionView({super.key, required this.desk});

  final BayiDeskSection desk;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(bayiGrantsProvider);
    void openDesk() => openDestination(context, AppRoutes.quoteDesk);
    void openOrder(int id) => g.viewOrders
        ? GoRouter.of(context).push(AppRoutes.bayiOrder(id))
        : openDesk();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BayiSectionHeader(
          title: 'Teklifler',
          actionLabel: g.viewDesk
              ? 'Teklif masası'
              : (g.viewOrders ? 'Siparişler' : null),
          onAction: g.viewDesk
              ? openDesk
              : g.viewOrders
              ? () => openDestination(context, AppRoutes.bayiOrders)
              : null,
        ),
        KpiGrid(
          tiles: [
            KpiTile(
              label: 'Teklif bekleyen',
              value: desk.awaitingQuote,
              icon: Icons.request_quote_rounded,
              tone: desk.awaitingQuote > 0 ? AknTone.brand : null,
              onTap: g.viewDesk ? openDesk : null,
            ),
            KpiTile(
              label: 'Revize istenen',
              value: desk.revisionRequested,
              icon: Icons.edit_rounded,
              tone: desk.revisionRequested > 0 ? AknTone.info : null,
              onTap: g.viewDesk ? openDesk : null,
            ),
            if (desk.expiryEnabled && desk.expiringSoon != null)
              KpiTile(
                label: 'Süresi yaklaşan',
                value: desk.expiringSoon,
                icon: Icons.timer_outlined,
                tone: (desk.expiringSoon ?? 0) > 0 ? AknTone.warn : null,
                caption: '${desk.expiringWindowMinutes} dk içinde',
              ),
            KpiTile(
              label: 'Cari kararında',
              value: desk.awaitingCustomer,
              icon: Icons.hourglass_top_rounded,
            ),
          ],
        ),
        if (desk.financeHeld > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: AknBanner(
              tone: AknTone.info,
              icon: Icons.account_balance_rounded,
              message:
                  '${desk.financeHeld} sipariş finans onayında; finans onaylayınca masaya düşer.',
            ),
          ),
        if (desk.expiryEnabled && desk.expiring.isNotEmpty) ...[
          const BayiSectionHeader(
            title: 'Süresi yaklaşanlar',
            padding: EdgeInsets.fromLTRB(16, 16, 8, 6),
          ),
          SectionCard(
            accent: AknTone.warn,
            child: Column(
              children: [
                for (final o in desk.expiring)
                  _OrderLine(
                    row: o,
                    countdown: true,
                    onTap: () => openOrder(o.orderId),
                  ),
              ],
            ),
          ),
        ],
        if (desk.awaitingQuoteList.isNotEmpty) ...[
          const BayiSectionHeader(
            title: 'En eski teklif bekleyenler',
            padding: EdgeInsets.fromLTRB(16, 16, 8, 6),
          ),
          SectionCard(
            child: Column(
              children: [
                for (final o in desk.awaitingQuoteList)
                  _OrderLine(
                    row: o,
                    countdown: desk.expiryEnabled,
                    onTap: () => g.viewDesk ? openDesk() : openOrder(o.orderId),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _OrderLine extends StatelessWidget {
  const _OrderLine({
    required this.row,
    required this.onTap,
    this.countdown = false,
  });

  final DashboardOrderRow row;
  final VoidCallback onTap;
  final bool countdown;

  @override
  Widget build(BuildContext context) {
    final left = row.remaining();
    final deadline = TrTime.now().add(left);
    return AknListTile(
      padding: const EdgeInsets.symmetric(vertical: 10),
      title: row.customerTitle ?? row.orderNumber,
      subtitle: [
        row.orderNumber,
        if (row.productName != null) row.productName!,
        Fmt.liters(row.quantityLiters),
      ].join(' · '),
      trailing: countdown && row.msLeft > 0
          ? FitEnd(child: CountdownBadge(deadline: deadline, showRing: false))
          : null,
      showChevron: true,
      onTap: onTap,
    );
  }
}

/// Bugünkü sevkiyatlar ve itirazlar.
class ShipmentsSectionView extends ConsumerWidget {
  const ShipmentsSectionView({super.key, required this.section});

  final BayiShipmentsSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(bayiGrantsProvider);
    final s = section;
    void openBoard() => openDestination(context, AppRoutes.dispatch);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BayiSectionHeader(
          title: 'Sevkiyatlar',
          actionLabel: g.viewBoard ? 'Sevkiyat' : null,
          onAction: g.viewBoard ? openBoard : null,
        ),
        KpiGrid(
          tiles: [
            KpiTile(
              label: 'Planlı (bugün)',
              value: s.plannedDue,
              icon: Icons.event_rounded,
              tone: s.plannedDue > 0 ? AknTone.info : null,
              caption: 'Toplam planlı ${Fmt.integer(s.planned)}',
              onTap: g.viewBoard ? openBoard : null,
            ),
            KpiTile(
              label: 'Yolda',
              value: s.inTransit,
              icon: Icons.local_shipping_rounded,
              tone: s.inTransit > 0 ? AknTone.brand : null,
              onTap: g.viewBoard ? openBoard : null,
            ),
            KpiTile(
              label: 'Kabul bekleyen',
              value: s.reported,
              icon: Icons.fact_check_rounded,
              tone: s.reported > 0 ? AknTone.warn : null,
            ),
            KpiTile(
              label: 'İtirazlı',
              value: s.disputes,
              icon: Icons.report_rounded,
              tone: s.disputes > 0 ? AknTone.danger : null,
            ),
          ],
        ),
        if (s.unassignedDriver > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: AknBanner(
              tone: AknTone.warn,
              icon: Icons.person_search_rounded,
              message:
                  '${s.unassignedDriver} planlı sevkiyatta uygulama şoförü atanmamış; bu teslimatlar şoför uygulamasında görünmez.',
              actionLabel: g.viewBoard ? 'Sevkiyatı aç' : null,
              onAction: g.viewBoard ? openBoard : null,
            ),
          ),
        if (s.disputeList.isNotEmpty) ...[
          const BayiSectionHeader(
            title: 'Açık itirazlar',
            padding: EdgeInsets.fromLTRB(16, 16, 8, 6),
          ),
          SectionCard(
            accent: AknTone.danger,
            child: Column(
              children: [for (final r in s.disputeList) ShipmentLine(row: r)],
            ),
          ),
        ],
        if (s.today.isNotEmpty) ...[
          const BayiSectionHeader(
            title: 'Bugün',
            padding: EdgeInsets.fromLTRB(16, 16, 8, 6),
          ),
          SectionCard(
            child: Column(
              children: [for (final r in s.today) ShipmentLine(row: r)],
            ),
          ),
        ],
      ],
    );
  }
}

/// Panel sevkiyat satırı: saat, durum, cari, litre, plaka; dokununca ayrıntı sayfası.
class ShipmentLine extends StatelessWidget {
  const ShipmentLine({super.key, required this.row});

  final DashboardShipmentRow row;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final r = row;
    final code = 'SVK-${r.shipmentId.toString().padLeft(8, '0')}';
    return Semantics(
      button: true,
      label: [
        code,
        r.status.label,
        ?r.customerTitle,
        Fmt.liters(r.plannedLiters),
        if (r.scheduledAt != null) Fmt.dayLabel(r.scheduledAt),
        if (r.scheduledAt != null) Fmt.time(r.scheduledAt),
      ].join(', '),
      excludeSemantics: true,
      child: InkWell(
        onTap: () => showShipmentSheet(context, r.shipmentId, code: code),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 52,
                child: Text(
                  r.scheduledAt == null ? Fmt.dash : Fmt.time(r.scheduledAt),
                  style: t.bodyStrong.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.customerTitle ?? r.orderNumber,
                      style: t.bodyStrong,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        Fmt.liters(r.plannedLiters),
                        ?r.driverName,
                        if (r.disputeNote != null) r.disputeNote!,
                      ].join(' · '),
                      style: t.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FitStart(
                          child: StatusChip.style(
                            r.status.statusStyle,
                            size: StatusChipSize.small,
                          ),
                        ),
                        if (r.isOverdue)
                          const ToneTag(label: 'Gecikmiş', tone: AknTone.warn),
                        if (r.vehiclePlate != null)
                          PlateBadge(plate: r.vehiclePlate!, fontSize: 11),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

/// Onaylarım kartı.
class ApprovalsSectionView extends StatelessWidget {
  const ApprovalsSectionView({super.key, required this.section});

  final BayiApprovalsSection section;

  @override
  Widget build(BuildContext context) {
    final s = section;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const BayiSectionHeader(title: 'Onaylarım'),
        SectionCard(
          accent: s.overdue > 0
              ? AknTone.danger
              : (s.toMe > 0 ? AknTone.warn : null),
          child: Column(
            children: [
              CountLine(
                label: 'Kararınızı bekleyen',
                count: s.toMe,
                icon: Icons.task_alt_rounded,
                tone: s.toMe > 0 ? AknTone.warn : null,
                onTap: () => openDestination(context, AppRoutes.approvals),
              ),
              if (s.overdue > 0)
                CountLine(
                  label: 'Süresi geçen',
                  count: s.overdue,
                  icon: Icons.alarm_off_rounded,
                  tone: AknTone.danger,
                  onTap: () => openDestination(context, AppRoutes.approvals),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tahsilat özeti.
class CollectionsSectionView extends StatelessWidget {
  const CollectionsSectionView({super.key, required this.section});

  final BayiCollectionsSection section;

  @override
  Widget build(BuildContext context) {
    final s = section;
    final t = context.aknText;
    final large = isLargeText(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BayiSectionHeader(
          title: 'Tahsilat',
          actionLabel: 'Tümü',
          onAction: () => openDestination(context, AppRoutes.payments),
        ),
        KpiGrid(
          tiles: [
            KpiTile(
              label: 'Vadesi geçen',
              value: s.overdueCount,
              icon: Icons.event_busy_rounded,
              tone: s.overdueCount > 0 ? AknTone.danger : null,
              caption: s.overdueCount > 0 ? Fmt.money(s.overdueAmount) : null,
              onTap: () => openDestination(context, AppRoutes.payments),
            ),
            KpiTile(
              label: 'Kontrol bekleyen belge',
              value: s.documentsAwaitingCheck,
              icon: Icons.upload_file_rounded,
              tone: s.documentsAwaitingCheck > 0 ? AknTone.info : null,
              onTap: () => openDestination(context, AppRoutes.payments),
            ),
            KpiTile(
              label: 'Vadesi yaklaşan çek/senet',
              value: s.instrumentsDueSoonCount,
              icon: Icons.money_rounded,
              caption: '${s.dueSoonDays} gün içinde',
            ),
            KpiTile(
              label: 'Karşılıksız (30 gün)',
              value: s.bounced30d,
              icon: Icons.money_off_rounded,
              tone: s.bounced30d > 0 ? AknTone.danger : null,
            ),
          ],
        ),
        if (s.overdue.isNotEmpty) ...[
          const BayiSectionHeader(
            title: 'Vadesi geçen ödemeler',
            padding: EdgeInsets.fromLTRB(16, 16, 8, 6),
          ),
          SectionCard(
            accent: AknTone.danger,
            child: Column(
              children: [
                for (final p in s.overdue)
                  AknListTile(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    title: p.customerTitle,
                    subtitle: [
                      if (large && p.amount != null) Fmt.money(p.amount),
                      p.orderNumber,
                      ?p.methodName,
                      if (p.dueDate != null) 'vade ${Fmt.date(p.dueDate)}',
                    ].join(' · '),
                    meta: p.amount == null || large
                        ? null
                        : Fmt.money(p.amount),
                    onTap: () =>
                        GoRouter.of(context).push(AppRoutes.payment(p.orderId)),
                  ),
              ],
            ),
          ),
        ],
        if (s.instrumentsDueSoon.isNotEmpty) ...[
          const BayiSectionHeader(
            title: 'Vadesi yaklaşan çek / senetler',
            padding: EdgeInsets.fromLTRB(16, 16, 8, 6),
          ),
          SectionCard(
            child: Column(
              children: [
                for (final i in s.instrumentsDueSoon)
                  AknListTile(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    leadingIcon: AknStatus.instrumentKind(i.kind).icon,
                    title: i.customerTitle,
                    subtitle: [
                      if (large) Fmt.money(i.amount),
                      i.kind.label,
                      ?i.bankName,
                      if (i.dueDate != null) 'vade ${Fmt.date(i.dueDate)}',
                    ].join(' · '),
                    meta: large ? null : Fmt.money(i.amount),
                    onTap: i.orderId == null
                        ? null
                        : () => GoRouter.of(
                            context,
                          ).push(AppRoutes.payment(i.orderId!)),
                  ),
              ],
            ),
          ),
        ],
        if (s.overdue.isEmpty && s.instrumentsDueSoon.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text('Vadesi geçen ödeme yok.', style: t.bodySmall),
          ),
      ],
    );
  }
}

/// Finans kartı kuyruğu.
class FinanceSectionView extends StatelessWidget {
  const FinanceSectionView({super.key, required this.section});

  final BayiFinanceSection section;

  @override
  Widget build(BuildContext context) {
    final s = section;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BayiSectionHeader(
          title: 'Finans kartları',
          actionLabel: 'Finans',
          onAction: () => openDestination(context, AppRoutes.finance),
        ),
        SectionCard(
          child: Column(
            children: [
              CountLine(
                label: 'İnceleme bekleyen',
                count: s.pending,
                icon: Icons.hourglass_top_rounded,
                tone: s.pending > 0 ? AknTone.warn : null,
              ),
              CountLine(
                label: 'Ek bilgi beklenen',
                count: s.infoRequested,
                icon: Icons.contact_support_rounded,
                tone: s.infoRequested > 0 ? AknTone.info : null,
              ),
              CountLine(
                label: 'Gözden geçirme tarihi geçen',
                count: s.reviewOverdue,
                icon: Icons.event_busy_rounded,
                tone: s.reviewOverdue > 0 ? AknTone.warn : null,
              ),
              CountLine(
                label: 'Karşılıksız / protestolu',
                count: s.flagged,
                icon: Icons.gpp_maybe_rounded,
                tone: s.flagged > 0 ? AknTone.danger : null,
              ),
            ],
          ),
        ),
        if (s.attention.isNotEmpty) ...[
          const BayiSectionHeader(
            title: 'İlgi bekleyen kartlar',
            padding: EdgeInsets.fromLTRB(16, 16, 8, 6),
          ),
          SectionCard(
            child: Column(
              children: [
                for (final a in s.attention)
                  AknListTile(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    title: a.customerTitle,
                    subtitle: [
                      if (a.status != null) a.status!.label,
                      'Risk ${a.riskClass.label}',
                      if (a.hasBouncedCheque) 'karşılıksız çek',
                    ].join(' · '),
                    onTap: () => GoRouter.of(
                      context,
                    ).push(AppRoutes.financeCustomer(a.stationCustomerId)),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Ön kayıt istatistikleri.
class LeadsSectionView extends StatelessWidget {
  const LeadsSectionView({super.key, required this.section});

  final BayiLeadsSection section;

  @override
  Widget build(BuildContext context) {
    final s = section.stats;
    final rate = s.conversionRatePercent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BayiSectionHeader(
          title: 'Ön kayıtlar',
          subtitle: section.periodLabel.isEmpty ? null : section.periodLabel,
          actionLabel: 'Saha',
          onAction: () => openDestination(context, AppRoutes.field),
        ),
        KpiGrid(
          tiles: [
            KpiTile(
              label: 'Toplam',
              value: s.total,
              icon: Icons.storefront_rounded,
            ),
            KpiTile(
              label: 'Finansta',
              value: s.inFinance + s.submitted,
              icon: Icons.account_balance_rounded,
              tone: s.inFinance + s.submitted > 0 ? AknTone.info : null,
            ),
            KpiTile(
              label: 'Cariye dönüşen',
              value: s.converted,
              icon: Icons.how_to_reg_rounded,
              tone: s.converted > 0 ? AknTone.ok : null,
              caption: rate == null ? null : 'Dönüşüm ${Fmt.percent(rate)}',
            ),
            KpiTile(
              label: 'Taslak',
              value: s.draft,
              icon: Icons.edit_note_rounded,
            ),
          ],
        ),
      ],
    );
  }
}

/// Saha formları (yönetici görünümü).
class FieldSectionView extends ConsumerWidget {
  const FieldSectionView({super.key, required this.section});

  final BayiFieldSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = section;
    final g = ref.watch(bayiGrantsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BayiSectionHeader(
          title: 'Saha formları',
          actionLabel: 'Saha',
          onAction: () => openDestination(context, AppRoutes.field),
        ),
        SectionCard(
          child: Column(
            children: [
              if (s.approvalsToMe > 0)
                CountLine(
                  label: 'Kararınızı bekleyen',
                  count: s.approvalsToMe,
                  icon: Icons.task_alt_rounded,
                  tone: AknTone.warn,
                  onTap: g.viewApprovals
                      ? () => openDestination(context, AppRoutes.approvals)
                      : null,
                ),
              CountLine(
                label: 'Onay bekleyen',
                count: s.pending,
                icon: Icons.hourglass_top_rounded,
              ),
              CountLine(
                label: 'Taslak',
                count: s.drafts,
                icon: Icons.edit_note_rounded,
              ),
              CountLine(
                label: 'Siparişe dönüşen (30 gün)',
                count: s.converted,
                icon: Icons.receipt_long_rounded,
                tone: s.converted > 0 ? AknTone.ok : null,
              ),
              if (s.rejected > 0)
                CountLine(
                  label: 'Reddedilen (30 gün)',
                  count: s.rejected,
                  icon: Icons.cancel_rounded,
                  tone: AknTone.danger,
                ),
            ],
          ),
        ),
        if (s.recent.isNotEmpty) ...[
          const BayiSectionHeader(
            title: 'Son formlar',
            padding: EdgeInsets.fromLTRB(16, 16, 8, 6),
          ),
          SectionCard(
            child: Column(
              children: [
                for (final f in s.recent)
                  AknListTile(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    title: f.customerTitle ?? f.formNumber,
                    subtitle: '${f.formNumber} · ${Fmt.liters(f.totalLiters)}',
                    trailing: FitEnd(
                      child: StatusChip.style(
                        f.status.statusStyle.withLabel(f.statusLabel),
                        size: StatusChipSize.small,
                      ),
                    ),
                    onTap: () =>
                        GoRouter.of(context).push(AppRoutes.fieldForm(f.id)),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Satış özeti: son 7 gün, en çok alan cariler, limitine yaklaşanlar.
class SalesSectionView extends ConsumerWidget {
  const SalesSectionView({super.key, required this.section});

  final BayiSalesSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = section;
    final t = context.aknText;
    final large = isLargeText(context);
    final g = ref.watch(bayiGrantsProvider);
    final values = [for (final d in s.days) d.liters];
    final trendUp =
        values.length > 1 && values.last >= values[values.length - 2];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BayiSectionHeader(title: 'Son ${s.windowDays} gün'),
        SectionCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  _Stat(label: 'Sipariş', value: Fmt.integer(s.windowOrders)),
                  _Stat(label: 'Litre', value: Fmt.liters(s.windowLiters)),
                  _Stat(
                    label: 'Tutar',
                    value: Fmt.moneyCompact(s.windowAmount),
                  ),
                ],
              ),
              if (values.length > 1) ...[
                const SizedBox(height: 12),
                Sparkline(
                  values: values,
                  height: 48,
                  semanticLabel:
                      'Son ${s.windowDays} gün litre, ${trendUp ? 'artışta' : 'düşüşte'}; bugün ${Fmt.liters(values.last)}',
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(Fmt.dayMonth(s.days.first.day), style: t.caption),
                    const Spacer(),
                    Text('Bugün', style: t.caption),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (s.topCustomers.isNotEmpty) ...[
          const BayiSectionHeader(
            title: 'En çok alan cariler',
            padding: EdgeInsets.fromLTRB(16, 16, 8, 6),
          ),
          SectionCard(
            child: Column(
              children: [
                for (final c in s.topCustomers)
                  AknListTile(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    leading: AknAvatar(name: c.customerTitle, size: 36),
                    title: c.customerTitle,
                    subtitle: [
                      if (large) Fmt.moneyCompact(c.amount),
                      '${Fmt.integer(c.orders)} sipariş',
                      Fmt.liters(c.liters),
                    ].join(' · '),
                    meta: large ? null : Fmt.moneyCompact(c.amount),
                    onTap: g.viewCustomers
                        ? () => GoRouter.of(
                            context,
                          ).push(AppRoutes.customer(c.customerId))
                        : null,
                  ),
              ],
            ),
          ),
        ],
        if (s.nearLimit.isNotEmpty) ...[
          BayiSectionHeader(
            title: 'Limitine yaklaşanlar',
            count: s.nearLimitTotal,
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 6),
          ),
          SectionCard(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                for (final l in s.nearLimit)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: InkWell(
                      onTap: g.viewCustomers
                          ? () => GoRouter.of(
                              context,
                            ).push(AppRoutes.customer(l.customerId))
                          : null,
                      child: BayiUsageBar(
                        value: l.usedPercent / 100,
                        label: l.customerTitle,
                        valueLabel: Fmt.percent(l.usedPercent),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: t.caption),
          Text(
            value,
            style: t.amount.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Kurulum uyarıları: düzeltme portalda (PORTAL_BASE_URL + portalPath).
class SetupSectionView extends ConsumerWidget {
  const SetupSectionView({super.key, required this.section});

  final BayiSetupSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.aknText;
    final open = section.checks
        .where((c) => c.isOpen || c.state != SetupCheckState.ok)
        .toList();
    if (open.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BayiSectionHeader(title: 'Kurulum uyarıları', count: open.length),
        SectionCard(
          accent: AknTone.warn,
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Column(
            children: [
              for (final c in open)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          c.state == SetupCheckState.missing
                              ? Icons.error_outline_rounded
                              : Icons.warning_amber_rounded,
                          size: 20,
                          color: context.akn
                              .tone(
                                c.state == SetupCheckState.missing
                                    ? AknTone.danger
                                    : AknTone.warn,
                              )
                              .fg,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.title, style: t.bodyStrong),
                            if (c.summary.isNotEmpty)
                              Text(c.summary, style: t.bodySmall),
                            if (c.hint != null)
                              Text(c.hint!, style: t.bodySmall),
                            if (c.portalPath != null)
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  alignment: Alignment.centerLeft,
                                ),
                                onPressed: () =>
                                    openPortal(context, ref, c.portalPath!),
                                icon: const Icon(
                                  Icons.open_in_new_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  c.portalLabel == null
                                      ? 'Portalda düzelt'
                                      : 'Portalda düzelt · ${c.portalLabel}',
                                ),
                              ),
                          ],
                        ),
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

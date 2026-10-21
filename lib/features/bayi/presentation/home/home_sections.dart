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
import '../widgets/bayi_widgets.dart' show openDestination, openPortal;
import 'home_atoms.dart';

/// Bayi ana sayfasının bölümleri (tasarım v2 §7.5–7.6): her bölüm bir başlık ([SectionHeader]) ve
/// beyaz defter satırları; kart, renkli şerit, renkli simge kutusu yok. Sayılar sağda (`number`),
/// tutarlar sağda (`amount`), durum lamba + kelime.

/// Okuma satırı (eski iki sütunlu KPI ızgarası): tasarım v2 §6.9 okuma şeridi. Geniş ekranda tek
/// satır, dar ekranda ve büyük yazıda ikişer sütun.
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
    child: KpiRow(children: tiles),
  );
}

/// Teklif masası bölümleri (sipariş masası ana sayfası): finans bekleyen bilgisi, süresi yaklaşanlar
/// (geri sayım Pas, 30 dk altında kırmızı) ve en eski teklif bekleyenler.
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
    final expiring = desk.expiryEnabled
        ? desk.expiring
        : const <DashboardOrderRow>[];
    final shown = {for (final o in expiring) o.orderId};
    final oldest = [
      for (final o in desk.awaitingQuoteList)
        if (!shown.contains(o.orderId)) o,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (desk.financeHeld > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: AknBanner(
              tone: AknTone.info,
              icon: Icons.account_balance_outlined,
              message:
                  '${desk.financeHeld} sipariş finans onayında; finans onaylayınca masaya düşer.',
            ),
          ),
        if (expiring.isNotEmpty) ...[
          SectionHeader(
            title: 'Süresi yaklaşanlar',
            count: desk.expiringSoon ?? expiring.length,
            actionLabel: g.viewDesk ? 'Teklif masası' : null,
            onAction: g.viewDesk ? openDesk : null,
          ),
          AknLedger(
            children: [
              for (final o in expiring)
                HomeOrderRow(
                  row: o,
                  countdown: true,
                  onTap: () => openOrder(o.orderId),
                ),
            ],
          ),
        ],
        if (oldest.isNotEmpty) ...[
          SectionHeader(
            title: 'En eski teklif bekleyenler',
            actionLabel: expiring.isEmpty && g.viewDesk
                ? 'Teklif masası'
                : null,
            onAction: expiring.isEmpty && g.viewDesk ? openDesk : null,
          ),
          AknLedger(
            children: [
              for (final o in oldest)
                HomeOrderRow(
                  row: o,
                  countdown: desk.expiryEnabled,
                  onTap: () => g.viewDesk ? openDesk() : openOrder(o.orderId),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Teklif bekleyen sipariş satırı (§7.7 masa satırının sade hâli): cari, sipariş no + ürün + litre,
/// lamba "Teklif verin" ya da "Revize istendi" ve sağda geri sayım.
class HomeOrderRow extends StatelessWidget {
  const HomeOrderRow({
    super.key,
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
    final revision = row.status == OrderStatus.revisionRequested;
    final decision = row.status == OrderStatus.awaitingApproval;
    final lamp = AknLamp(
      label: revision
          ? 'Revize istendi'
          : decision
          ? 'Müşteri kararında'
          : 'Teklif verin',
      tone: decision ? AknTone.info : AknTone.brand,
    );
    final total = row.latestTotalAmountTry;
    return AknListTile(
      title: row.customerTitle ?? row.orderNumber,
      subtitle: [
        row.orderNumber,
        ?row.productName,
        Fmt.liters(row.quantityLiters),
        ?row.deliveryPointName,
      ].join(', '),
      amount: total == null ? null : Fmt.money(total),
      amountMeta: row.latestUnitPriceTry == null
          ? null
          : Fmt.unitPrice(row.latestUnitPriceTry),
      status: AknStatusLine(
        lamp: lamp,
        trailing: countdown && row.msLeft > 0
            ? CountdownBadge(
                deadline: deadline,
                showRing: false,
                yourMove: !decision,
                subject: 'Teklif',
              )
            : null,
      ),
      onTap: onTap,
    );
  }
}

/// Sevkiyatlar (§7.5): şoförsüz plan uyarısı, açık itirazlar (kırmızı lamba) ve bugünün satırları.
/// [dispatcher] (sevkiyat / depo ana sayfası, §7.6): "Sürücü bekleyenler" satırlarında "Sürücü ata",
/// "Yolda" satırlarında güzergâh çizgisi, ardından "Açık itirazlar".
class ShipmentsSectionView extends ConsumerWidget {
  const ShipmentsSectionView({
    super.key,
    required this.section,
    this.dispatcher = false,
  });

  final BayiShipmentsSection section;
  final bool dispatcher;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(bayiGrantsProvider);
    final s = section;
    void openBoard() => openDestination(context, AppRoutes.dispatch);
    final canBoard = g.viewShipments;
    if (dispatcher) {
      final waiting = [
        for (final r in s.today)
          if (r.status == ShipmentStatus.planned && r.driverName == null) r,
      ];
      final moving = [
        for (final r in s.today)
          if (r.status == ShipmentStatus.inTransit) r,
      ];
      final rest = [
        for (final r in s.today)
          if (!waiting.contains(r) && !moving.contains(r)) r,
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (waiting.isNotEmpty || s.unassignedDriver > 0) ...[
            SectionHeader(
              title: 'Sürücü bekleyenler',
              count: s.unassignedDriver > 0
                  ? s.unassignedDriver
                  : waiting.length,
              actionLabel: canBoard ? 'Sevkiyat' : null,
              onAction: canBoard ? openBoard : null,
            ),
            if (waiting.isEmpty)
              _UnassignedWell(
                count: s.unassignedDriver,
                onOpen: canBoard ? openBoard : null,
              )
            else
              AknLedger(
                children: [
                  for (final r in waiting)
                    ShipmentLine(
                      row: r,
                      adr: true,
                      action: g.assignDriver ? 'Sürücü ata' : null,
                    ),
                ],
              ),
          ],
          if (moving.isNotEmpty) ...[
            SectionHeader(title: 'Yolda', count: moving.length),
            AknLedger(
              children: [
                for (final r in moving)
                  ShipmentLine(row: r, route: true, adr: true),
              ],
            ),
          ],
          if (s.disputeList.isNotEmpty) ...[
            SectionHeader(title: 'Açık itirazlar', count: s.disputes),
            AknLedger(
              children: [
                for (final r in s.disputeList) ShipmentLine(row: r, adr: true),
              ],
            ),
          ],
          if (rest.isNotEmpty) ...[
            SectionHeader(
              title: 'Bugün',
              actionLabel:
                  canBoard && waiting.isEmpty && s.unassignedDriver == 0
                  ? 'Sevkiyat'
                  : null,
              onAction: canBoard ? openBoard : null,
            ),
            AknLedger(
              children: [for (final r in rest) ShipmentLine(row: r, adr: true)],
            ),
          ],
          if (s.today.isEmpty &&
              s.disputeList.isEmpty &&
              s.unassignedDriver == 0)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: _QuietLine(text: 'Bugün planlı sevkiyat yok.'),
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Sevkiyatlar',
          actionLabel: canBoard ? 'Tümü' : null,
          onAction: canBoard ? openBoard : null,
        ),
        if (s.unassignedDriver > 0)
          _UnassignedWell(
            count: s.unassignedDriver,
            onOpen: canBoard ? openBoard : null,
          ),
        if (s.disputeList.isNotEmpty) ...[
          _SubHeader(text: 'Açık itirazlar', count: s.disputes),
          AknLedger(
            children: [for (final r in s.disputeList) ShipmentLine(row: r)],
          ),
        ],
        if (s.today.isNotEmpty) ...[
          _SubHeader(text: 'Bugün', count: s.today.length),
          AknLedger(children: [for (final r in s.today) ShipmentLine(row: r)]),
        ],
        if (s.today.isEmpty && s.disputeList.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: _QuietLine(
              text: s.planned > 0
                  ? 'Bugün planlı sevkiyat yok; toplam ${Fmt.integer(s.planned)} planlı sevkiyat var.'
                  : 'Bugün planlı sevkiyat yok.',
            ),
          ),
      ],
    );
  }
}

class _UnassignedWell extends StatelessWidget {
  const _UnassignedWell({required this.count, this.onOpen});

  final int count;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
    child: AknBanner(
      tone: AknTone.warn,
      icon: Icons.person_search_outlined,
      message:
          '$count planlı sevkiyatta uygulama şoförü atanmamış; bu teslimatlar şoför uygulamasında görünmez.',
      actionLabel: onOpen == null ? null : 'Sürücü ata',
      onAction: onOpen,
    ),
  );
}

/// Bölüm içi alt başlık (`label` 13/18 600 soluk): "Bugün", "Açık itirazlar".
class _SubHeader extends StatelessWidget {
  const _SubHeader({required this.text, this.count});

  final String text;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Semantics(
        header: true,
        child: Text(
          count == null ? text : '$text ${Fmt.integer(count)}',
          style: t.label.copyWith(fontWeight: FontWeight.w600, color: c.dim),
        ),
      ),
    );
  }
}

class _QuietLine extends StatelessWidget {
  const _QuietLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: context.aknText.bodySmall.copyWith(color: context.akn.dim),
  );
}

/// Sevkiyat satırı (§7.15): cari ve litre (sağda), sevkiyat no + saat + sürücü, lamba ve TR plakası;
/// yoldakilerde güzergâh çizgisi. Dokununca sevkiyat ayrıntısı açılır.
class ShipmentLine extends StatelessWidget {
  const ShipmentLine({
    super.key,
    required this.row,
    this.action,
    this.route = false,
    this.adr = false,
  });

  final DashboardShipmentRow row;

  /// Yük satırında ADR levhası (yalnızca sevkiyat ekranları, §6.16).
  final bool adr;

  /// Satır sonunda küçük ikincil düğme ("Sürücü ata"); ayrıntı sayfasını açar.
  final String? action;

  /// Yoldaki sevkiyat için güzergâh çizgisi.
  final bool route;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final r = row;
    final code = 'SVK-${r.shipmentId.toString().padLeft(8, '0')}';
    void open() => showShipmentSheet(context, r.shipmentId, code: code);
    final when = r.scheduledAt == null
        ? null
        : '${lowerFirst(Fmt.dayLabel(r.scheduledAt))} ${Fmt.time(r.scheduledAt)}';
    final status = r.status.statusStyle;
    final plateAdr = adr
        ? AdrPlate.forProduct(r.productName, height: 24)
        : null;
    final plate = r.vehiclePlate == null
        ? null
        : PlateBadge(plate: r.vehiclePlate!, fontSize: 12);
    final trailing = <Widget>[
      if (r.isOverdue)
        Text(
          'Gecikti',
          style: t.bodySmall.copyWith(
            color: c.warn.fg,
            fontWeight: FontWeight.w600,
          ),
        ),
      ?plate,
      ?plateAdr,
    ];
    return AknListTile(
      title: r.customerTitle ?? r.orderNumber,
      subtitle: [
        [code, ?r.productName, ?when].join(', '),
        [
          r.driverName ?? 'Sürücü atanmadı',
          if (r.disputeNote != null) r.disputeNote!,
        ].join(', '),
      ].join('\n'),
      subtitleMaxLines: 3,
      amount: Fmt.liters(r.plannedLiters),
      amountMeta: r.deliveryPointName,
      semanticLabel: [
        r.customerTitle ?? r.orderNumber,
        Fmt.liters(r.plannedLiters),
        status.label,
        code,
        ?when,
        r.driverName ?? 'Sürücü atanmadı',
        if (r.vehiclePlate != null) 'plaka ${Fmt.plate(r.vehiclePlate)}',
        if (r.isOverdue) 'gecikti',
        if (r.disputeNote != null) r.disputeNote!,
      ].join(', '),
      status: AknStatusLine(
        lamp: AknLamp.style(status),
        trailing: trailing.isEmpty
            ? null
            : Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: trailing,
              ),
      ),
      footer: route && r.status == ShipmentStatus.inTransit
          ? TruckRoute(
              moving: true,
              height: 16,
              semanticLabel:
                  'Yolda: ${r.deliveryPointName ?? r.customerTitle ?? ''}',
            )
          : action == null
          ? null
          : Align(
              alignment: AlignmentDirectional.centerStart,
              child: AknButton.secondary(
                label: action!,
                size: AknButtonSize.small,
                onPressed: open,
              ),
            ),
      onTap: open,
    );
  }
}

/// Onaylarım (§7.5): kararınızı bekleyenler ("Onayınızı bekliyor", sıra sizde) ve süresi geçenler
/// (kırmızı lamba).
class ApprovalsSectionView extends StatelessWidget {
  const ApprovalsSectionView({super.key, required this.section});

  final BayiApprovalsSection section;

  @override
  Widget build(BuildContext context) {
    final s = section;
    final c = context.akn;
    void open() => openDestination(context, AppRoutes.approvals);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: 'Onaylarım', actionLabel: 'Tümü', onAction: open),
        AknLedger(
          children: [
            HomeCountRow(
              label: 'Kararınızı bekleyen',
              count: s.toMe,
              highlight: s.toMe > 0 ? c.brandInk : null,
              lamp: s.toMe > 0
                  ? const AknLamp(
                      label: 'Onayınızı bekliyor',
                      tone: AknTone.brand,
                    )
                  : const AknLamp(
                      label: 'Bekleyen onay yok',
                      tone: AknTone.neutral,
                    ),
              onTap: open,
            ),
            if (s.overdue > 0)
              HomeCountRow(
                label: 'Süresi geçen',
                count: s.overdue,
                highlight: c.danger.fg,
                lamp: const AknLamp(
                  label: 'Süresi geçti',
                  tone: AknTone.danger,
                ),
                onTap: open,
              ),
          ],
        ),
      ],
    );
  }
}

/// Tahsilat (§7.5): vadesi geçen ödemeler kırmızı lamba satırında ("Vadesi geçen 2 ödeme",
/// 184.000 ₺, "En eskisi 6 gün gecikmede"), ardından belge kontrolü, vadesi yaklaşan çek / senet ve
/// karşılıksızlar. [detailed] (finans, muhasebe; §7.6): vadesi geçen ödemeler tek tek (en eskisi
/// önce) ve vadesi yaklaşan çek / senetler satır satır.
class CollectionsSectionView extends StatelessWidget {
  const CollectionsSectionView({
    super.key,
    required this.section,
    this.detailed = false,
  });

  final BayiCollectionsSection section;
  final bool detailed;

  @override
  Widget build(BuildContext context) {
    final s = section;
    final c = context.akn;
    void openPayments() => openDestination(context, AppRoutes.payments);
    final oldest = _oldestDays(s.overdue);
    final overdueRow = s.overdueCount > 0
        ? HomeLampAmountRow(
            label: 'Vadesi geçen ${Fmt.integer(s.overdueCount)} ödeme',
            tone: AknTone.danger,
            amount: Fmt.moneyWhole(s.overdueAmount),
            meta: oldest == null
                ? null
                : oldest == 0
                ? 'En eskisinin vadesi bugün doldu'
                : 'En eskisi $oldest gün gecikmede',
            onTap: openPayments,
          )
        : const HomeLampAmountRow(
            label: 'Vadesi geçen ödeme yok',
            tone: AknTone.ok,
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Tahsilat',
          actionLabel: 'Tümü',
          onAction: openPayments,
        ),
        AknLedger(
          children: [
            if (!detailed || s.overdue.isEmpty) overdueRow,
            if (detailed)
              for (final p in _byDue(s.overdue))
                AknListTile(
                  title: p.customerTitle.isEmpty
                      ? p.orderNumber
                      : p.customerTitle,
                  subtitle: [
                    p.orderNumber,
                    ?p.methodName,
                    if (p.dueDate != null) 'vade ${Fmt.date(p.dueDate)}',
                  ].join(', '),
                  amount: p.amount == null ? null : Fmt.money(p.amount),
                  status: AknLamp(
                    label: _lateLabel(p.dueDate),
                    tone: AknTone.danger,
                  ),
                  onTap: () =>
                      GoRouter.of(context).push(AppRoutes.payment(p.orderId)),
                ),
            if (s.documentsAwaitingCheck > 0)
              HomeCountRow(
                label: 'Kontrol bekleyen belge',
                count: s.documentsAwaitingCheck,
                lamp: const AknLamp(
                  label: 'Belge yüklendi',
                  tone: AknTone.info,
                ),
                onTap: openPayments,
              ),
            if (!detailed && s.instrumentsDueSoonCount > 0)
              AknListTile(
                title:
                    'Vadesi yaklaşan ${Fmt.integer(s.instrumentsDueSoonCount)} çek / senet',
                subtitle: '${s.dueSoonDays} gün içinde',
                amount: Fmt.moneyWhole(s.instrumentsDueSoonAmount),
                onTap: () => openDestination(
                  context,
                  '${AppRoutes.payments}?tab=instruments',
                ),
              ),
            if (s.bounced30d > 0)
              HomeCountRow(
                label: 'Karşılıksız (30 gün)',
                count: s.bounced30d,
                highlight: c.danger.fg,
                lamp: const AknLamp(label: 'Karşılıksız', tone: AknTone.danger),
                onTap: openPayments,
              ),
          ],
        ),
        if (detailed && s.instrumentsDueSoon.isNotEmpty) ...[
          SectionHeader(
            title: 'Vadesi yaklaşan çek / senetler',
            count: s.instrumentsDueSoonCount,
            subtitle:
                '${s.dueSoonDays} gün içinde, toplam ${Fmt.moneyWhole(s.instrumentsDueSoonAmount)}',
          ),
          AknLedger(
            children: [
              for (final i in s.instrumentsDueSoon)
                AknListTile(
                  title: i.customerTitle,
                  subtitle: [
                    i.kind.label,
                    ?i.bankName,
                    if (i.dueDate != null) 'vade ${Fmt.date(i.dueDate)}',
                  ].join(', '),
                  amount: Fmt.money(i.amount),
                  onTap: i.orderId == null
                      ? null
                      : () => GoRouter.of(
                          context,
                        ).push(AppRoutes.payment(i.orderId!)),
                ),
            ],
          ),
        ],
      ],
    );
  }

  static List<BayiPaymentRow> _byDue(List<BayiPaymentRow> rows) {
    final list = [...rows];
    list.sort((a, b) {
      final x = a.dueDate;
      final y = b.dueDate;
      if (x == null) return 1;
      if (y == null) return -1;
      return x.compareTo(y);
    });
    return list;
  }

  static int? _oldestDays(List<BayiPaymentRow> rows) {
    int? days;
    for (final p in rows) {
      final d = p.dueDate;
      if (d == null) continue;
      final late = TrTime.dayDiff(d, TrTime.now());
      if (days == null || late > days) days = late;
    }
    return days == null || days < 0 ? null : days;
  }

  static String _lateLabel(DateTime? due) {
    if (due == null) return 'Vadesi geçti';
    final late = TrTime.dayDiff(due, TrTime.now());
    return late <= 0 ? 'Vadesi bugün' : '$late gün gecikti';
  }
}

/// Finans kartları kuyruğu (§7.6 "İlgi bekleyen finans kartları").
class FinanceSectionView extends StatelessWidget {
  const FinanceSectionView({super.key, required this.section});

  final BayiFinanceSection section;

  @override
  Widget build(BuildContext context) {
    final s = section;
    final c = context.akn;
    void open() => openDestination(context, AppRoutes.finance);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Finans kartları',
          actionLabel: 'Finans',
          onAction: open,
        ),
        AknLedger(
          children: [
            HomeCountRow(
              label: 'İnceleme bekleyen',
              count: s.pending,
              highlight: s.pending > 0 ? c.brandInk : null,
              lamp: s.pending > 0
                  ? const AknLamp(
                      label: 'Kararınızı bekliyor',
                      tone: AknTone.brand,
                    )
                  : null,
              onTap: open,
            ),
            if (s.infoRequested > 0)
              HomeCountRow(
                label: 'Ek bilgi beklenen',
                count: s.infoRequested,
                lamp: const AknLamp(label: 'Müşteride', tone: AknTone.info),
                onTap: open,
              ),
            if (s.reviewOverdue > 0)
              HomeCountRow(
                label: 'Gözden geçirme tarihi geçen',
                count: s.reviewOverdue,
                lamp: const AknLamp(label: 'Tarihi geçti', tone: AknTone.warn),
                onTap: open,
              ),
            if (s.flagged > 0)
              HomeCountRow(
                label: 'Karşılıksız / protestolu',
                count: s.flagged,
                highlight: c.danger.fg,
                lamp: const AknLamp(label: 'Riskli', tone: AknTone.danger),
                onTap: open,
              ),
          ],
        ),
        if (s.attention.isNotEmpty) ...[
          const SectionHeader(title: 'İlgi bekleyen kartlar'),
          AknLedger(
            children: [
              for (final a in s.attention)
                AknListTile(
                  title: a.customerTitle,
                  subtitle: [
                    'Risk ${a.riskClass.label}',
                    if (a.nextReviewDate != null)
                      'gözden geçirme ${Fmt.date(a.nextReviewDate)}',
                  ].join(', '),
                  amount: a.overdueAmount == null || a.overdueAmount == 0
                      ? null
                      : Fmt.moneyWhole(a.overdueAmount),
                  amountMeta: a.overdueAmount == null || a.overdueAmount == 0
                      ? null
                      : 'vadesi geçen',
                  status: a.hasBouncedCheque || a.hasProtestedNote
                      ? AknLamp(
                          label: a.hasBouncedCheque
                              ? 'Karşılıksız çek'
                              : 'Protestolu senet',
                          tone: AknTone.danger,
                        )
                      : a.status == null
                      ? null
                      : AknLamp(label: a.status!.label, tone: AknTone.info),
                  onTap: () => GoRouter.of(
                    context,
                  ).push(AppRoutes.financeCustomer(a.stationCustomerId)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Ön kayıtlar (dönem özeti): okuma şeridi.
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
        SectionHeader(
          title: 'Ön kayıtlar',
          subtitle: section.periodLabel.isEmpty ? null : section.periodLabel,
          actionLabel: 'Saha',
          onAction: () => openDestination(context, AppRoutes.field),
        ),
        KpiGrid(
          tiles: [
            KpiTile(label: 'Toplam', value: s.total),
            KpiTile(label: 'Finansta', value: s.inFinance + s.submitted),
            KpiTile(
              label: 'Cariye dönüşen',
              value: s.converted,
              caption: rate == null ? null : 'Dönüşüm ${Fmt.percent(rate)}',
            ),
          ],
        ),
      ],
    );
  }
}

/// Saha formları (yönetici görünümü, §7.6 satış müdürü): kararınızı bekleyenler önce, sonra onay
/// bekleyen, taslak, dönüşen ve reddedilen sayıları; son formlar satır satır.
class FieldSectionView extends ConsumerWidget {
  const FieldSectionView({super.key, required this.section});

  final BayiFieldSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = section;
    final c = context.akn;
    final g = ref.watch(bayiGrantsProvider);
    void openField() => openDestination(context, AppRoutes.field);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: 'Saha formları',
          actionLabel: 'Saha',
          onAction: openField,
        ),
        AknLedger(
          children: [
            if (s.approvalsToMe > 0)
              HomeCountRow(
                label: 'Kararınızı bekleyen',
                count: s.approvalsToMe,
                highlight: c.brandInk,
                lamp: const AknLamp(
                  label: 'Onayınızı bekliyor',
                  tone: AknTone.brand,
                ),
                onTap: g.viewApprovals
                    ? () => openDestination(context, AppRoutes.approvals)
                    : null,
              ),
            HomeCountRow(
              label: 'Onay bekleyen',
              count: s.pending,
              onTap: openField,
            ),
            HomeCountRow(
              label: 'Siparişe dönüşen',
              meta: 'Son 30 gün',
              count: s.converted,
              onTap: openField,
            ),
            if (s.drafts > 0)
              HomeCountRow(label: 'Taslak', count: s.drafts, onTap: openField),
            if (s.rejected > 0)
              HomeCountRow(
                label: 'Reddedilen',
                meta: 'Son 30 gün',
                count: s.rejected,
                lamp: const AknLamp(label: 'Reddedildi', tone: AknTone.danger),
                onTap: openField,
              ),
          ],
        ),
        if (s.recent.isNotEmpty) ...[
          const SectionHeader(title: 'Son formlar'),
          AknLedger(
            children: [
              for (final f in s.recent)
                AknListTile(
                  title: f.customerTitle ?? f.formNumber,
                  subtitle: [
                    f.formNumber,
                    if (f.createdAt != null) Fmt.dayLabel(f.createdAt),
                  ].join(', '),
                  amount: Fmt.liters(f.totalLiters),
                  amountMeta: f.totalAmount == null
                      ? null
                      : Fmt.moneyWhole(f.totalAmount),
                  status: AknLamp.style(
                    f.status.statusStyle.withLabel(f.statusLabel),
                  ),
                  onTap: () =>
                      GoRouter.of(context).push(AppRoutes.fieldForm(f.id)),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Satış özeti (son N gün okuma şeridi + günlük litre çizgisi), en çok alan cariler ve limitine
/// yaklaşanlar (§7.6 satış müdürü). [summary] false iken yalnızca cariler ve limitler.
class SalesSectionView extends ConsumerWidget {
  const SalesSectionView({
    super.key,
    required this.section,
    this.summary = true,
  });

  final BayiSalesSection section;
  final bool summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = section;
    final t = context.aknText;
    final c = context.akn;
    final g = ref.watch(bayiGrantsProvider);
    final values = [for (final d in s.days) d.liters];
    final trendUp =
        values.length > 1 && values.last >= values[values.length - 2];
    VoidCallback? openCustomer(int id) => g.viewCustomers
        ? () => GoRouter.of(context).push(AppRoutes.customer(id))
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summary) ...[
          SectionHeader(title: 'Son ${s.windowDays} gün'),
          KpiGrid(
            tiles: [
              KpiTile(label: 'Sipariş', value: s.windowOrders),
              KpiTile(label: 'Litre', value: s.windowLiters, unit: 'L'),
              KpiTile(
                label: 'Tutar',
                value: s.windowAmount,
                format: Fmt.moneyCompact,
              ),
            ],
          ),
          if (values.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Sparkline(
                    values: values,
                    height: 44,
                    semanticLabel:
                        'Son ${s.windowDays} gün litre, ${trendUp ? 'artışta' : 'düşüşte'}; bugün ${Fmt.liters(values.last)}',
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        Fmt.dayMonth(s.days.first.day),
                        style: t.caption.copyWith(color: c.dim),
                      ),
                      const Spacer(),
                      Text('bugün', style: t.caption.copyWith(color: c.dim)),
                    ],
                  ),
                ],
              ),
            ),
        ],
        if (s.topCustomers.isNotEmpty) ...[
          const SectionHeader(title: 'En çok alan cariler'),
          AknLedger(
            children: [
              for (final cu in s.topCustomers.take(5))
                AknListTile(
                  title: cu.customerTitle,
                  subtitle:
                      '${Fmt.integer(cu.orders)} sipariş, ${Fmt.liters(cu.liters)}',
                  amount: Fmt.moneyWhole(cu.amount),
                  onTap: openCustomer(cu.customerId),
                ),
            ],
          ),
        ],
        if (s.nearLimit.isNotEmpty) ...[
          SectionHeader(title: 'Limitine yaklaşanlar', count: s.nearLimitTotal),
          AknLedger(
            children: [
              for (final l in s.nearLimit)
                AknListTile(
                  title: l.customerTitle,
                  amount: Fmt.percent(l.usedPercent),
                  amountMeta: l.periodLabel.isEmpty ? null : l.periodLabel,
                  footer: UsageBar(
                    value: l.usedPercent / 100,
                    valueLabel: Fmt.percent(l.usedPercent),
                  ),
                  semanticLabel:
                      '${l.customerTitle}, limitin ${Fmt.percent(l.usedPercent)} kullanıldı',
                  onTap: openCustomer(l.customerId),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Kurulum uyarıları (§7.5): her açık kontrol bir uyarı kuyusu; düzeltme web portalında
/// ("Portalda düzelt").
class SetupSectionView extends ConsumerWidget {
  const SetupSectionView({super.key, required this.section});

  final BayiSetupSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = section.checks
        .where((c) => c.isOpen || c.state != SetupCheckState.ok)
        .toList();
    if (open.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: 'Kurulum uyarıları', count: open.length),
        for (final c in open)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: HomeWell(
              tone: c.state == SetupCheckState.missing
                  ? AknTone.danger
                  : AknTone.warn,
              icon: c.state == SetupCheckState.missing
                  ? Icons.error_outline_rounded
                  : Icons.warning_amber_rounded,
              title: c.title,
              message: [
                if (c.summary.isNotEmpty) c.summary,
                if (c.hint != null) c.hint!,
              ].join(' '),
              actionLabel: c.portalPath == null ? null : 'Portalda düzelt',
              onAction: c.portalPath == null
                  ? null
                  : () => openPortal(context, ref, c.portalPath!),
            ),
          ),
      ],
    );
  }
}

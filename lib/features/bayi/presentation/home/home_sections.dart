import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/enums.dart' show ApprovalType;
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../../finance/api.dart'
    show MyApprovals, myApprovalsBySubjectProvider, onboardingApprovals;
import '../../application/bayi_grants.dart';
import '../../data/home_models.dart';
import '../widgets/bayi_widgets.dart' show openDestination, openPortal;

/// Bayi ana sayfasının "Bugün" defteri (tasarım v4 "Sade" §3.3, §5 03): rol bölümlerinin her biri
/// tek satır — Tahsilat, Sevkiyatlar, Finans, Saha, Ön kayıtlar, Satış — tek bir defter kartında,
/// satırlar ince çizgiyle ayrılır. "Sıra sizde" kartına sığmayan sıradaki işler ([overflow]) en
/// üstte gelir. Kahramanın bir sayısını asla tekrarlamaz: hattaki (Finans · Teklif · Müşteri · Plan ·
/// Yolda · Teslim) ve görev satırlarındaki sayılar burada yazılmaz. Simge karosu yok; satırlar
/// dokununca ilgili sayfayı açar.
class BayiTodayLedger extends ConsumerWidget {
  const BayiTodayLedger({
    super.key,
    required this.data,
    this.overflow = const [],
    this.heroKinds = const {},
    this.showSales = true,
  });

  final BayiHomeData data;

  /// "Sıra sizde" kartına sığmayan işler (kartın sırasıyla).
  final List<AknTask> overflow;

  /// Kahramanda (görev ya da satır olarak) görünen kuyruklar: aynı sayı burada yinelenmez.
  /// Anahtarlar: `overdue-payments`, `documents`, `reviews`, `disputes`, `drivers`, `plan`.
  final Set<String> heroKinds;

  /// Satış özeti (istatistik destesi olmayanlar için).
  final bool showSales;

  /// Defterin satırları (testler ve boşluk kontrolü için ayrı). [onboarding]: izleyenin Bende'deki
  /// yeni cari finans talepleri (finans satırının sırası ve tekrarı buna göre).
  static List<Widget> rowsOf(
    BuildContext context,
    BayiHomeData data,
    BayiGrants g, {
    List<AknTask> overflow = const [],
    Set<String> heroKinds = const {},
    bool showSales = true,
    MyApprovals? onboarding,
  }) {
    void open(String route) => openDestination(context, route);
    final rows = <Widget>[
      for (final t in overflow)
        AknListTile(
          title: t.title,
          subtitle: t.subtitle,
          amount: t.amount,
          showChevron: t.onTap != null,
          onTap: t.onTap,
        ),
    ];

    // Sevkiyatlar: bugünün sevkiyatları (hattın sayıları değil, günün listesi).
    final s = data.shipments;
    if (s != null && s.today.isNotEmpty) {
      final first = [...s.today]
        ..sort((a, b) {
          final x = a.scheduledAt;
          final y = b.scheduledAt;
          if (x == null) return 1;
          if (y == null) return -1;
          return x.compareTo(y);
        });
      final f = first.first;
      final at = f.scheduledAt;
      rows.add(
        AknListTile(
          title: 'Bugün ${Fmt.integer(s.today.length)} sevkiyat',
          subtitle: [
            if (at != null) 'İlki ${Fmt.time(at)}',
            ?(f.customerTitle ?? f.deliveryPointName),
          ].join(' · '),
          showChevron: g.viewShipments,
          onTap: g.viewShipments ? () => open(AppRoutes.dispatch) : null,
        ),
      );
    }

    // Tahsilat: kahramanda olmayan para işleri.
    final m = data.collections;
    if (m != null) {
      if (m.overdueCount > 0 && !heroKinds.contains('overdue-payments')) {
        rows.add(
          AknListTile(
            title: 'Vadesi geçen ${Fmt.integer(m.overdueCount)} ödeme',
            subtitle: _oldest(m.overdue),
            amount: Fmt.moneyWhole(m.overdueAmount),
            showChevron: g.viewPayments,
            onTap: g.viewPayments
                ? () => open('${AppRoutes.payments}?filter=overdue')
                : null,
          ),
        );
      }
      if (m.instrumentsDueSoonCount > 0) {
        rows.add(
          AknListTile(
            title:
                'Vadesi yaklaşan ${Fmt.integer(m.instrumentsDueSoonCount)} çek ya da senet',
            subtitle: '${m.dueSoonDays} gün içinde',
            amount: Fmt.moneyWhole(m.instrumentsDueSoonAmount),
            showChevron: g.viewPayments,
            onTap: g.viewPayments
                ? () => open('${AppRoutes.payments}?tab=instruments')
                : null,
          ),
        );
      }
      if (m.bounced30d > 0) {
        rows.add(
          AknListTile(
            title: 'Karşılıksız çıkan ${Fmt.integer(m.bounced30d)} ödeme',
            subtitle: 'Son 30 gün',
            showChevron: g.viewPayments,
            // Satırın saydığı liste açılır (v4 tur 2): Tahsilat, karşılıksız süzgeciyle.
            onTap: g.viewPayments
                ? () => open('${AppRoutes.payments}?filter=bounced')
                : null,
          ),
        );
      }
    }

    // Finans kartları. Onay bekleyen kart bir onay talebidir: izleyenin sırasıysa kahramanın onay
    // satırı onu zaten sayar ("bir iş, bir sayı", v4 P2) — burada yinelenmez. Sıra başkasındaysa
    // sakin bir bilgi satırı.
    final fin = data.finance;
    if (fin != null) {
      final decider = onboarding == null || onboarding.total > 0;
      if (fin.pending > 0 && !(decider && heroKinds.contains('approvals'))) {
        rows.add(
          AknListTile(
            title: decider
                ? 'Finans onayınızı bekleyen ${Fmt.integer(fin.pending)} cari'
                : 'Finans onayında ${Fmt.integer(fin.pending)} cari',
            subtitle: 'Finans kartı',
            showChevron: true,
            onTap: () => open('${AppRoutes.finance}?filter=pending'),
          ),
        );
      }
      if (fin.infoRequested > 0) {
        rows.add(
          AknListTile(
            title: 'Bilgi beklenen ${Fmt.integer(fin.infoRequested)} cari',
            subtitle: 'Müşteriden ek bilgi istendi',
            showChevron: true,
            onTap: () => open(AppRoutes.finance),
          ),
        );
      }
      if (fin.flagged > 0) {
        rows.add(
          AknListTile(
            title:
                'Karşılıksız ya da protestolu ${Fmt.integer(fin.flagged)} cari',
            subtitle: 'Riskli kartlar',
            showChevron: true,
            onTap: () => open(AppRoutes.finance),
          ),
        );
      }
    }

    // Saha (yönetici görünümü).
    final field = data.field;
    if (field != null && !data.isFieldSales) {
      if (field.pending > 0) {
        rows.add(
          AknListTile(
            title: 'Onay bekleyen ${Fmt.integer(field.pending)} saha formu',
            subtitle: field.converted > 0
                ? 'Son 30 günde ${Fmt.integer(field.converted)} form siparişe dönüştü'
                : null,
            showChevron: g.viewFieldForms || g.viewApprovals,
            // Onaylayanın kararı Onaylar'dadır (saha formu türüne süzülü); diğerleri onay bekleyen
            // formların listesini açar (v4 tur 2: satırın sayısı açılan listede görünür).
            onTap: g.viewApprovals && g.policy.isApprover
                ? () => open(
                    '${AppRoutes.approvals}?type=${ApprovalType.fieldOrderProfit.code}',
                  )
                : g.viewFieldForms
                ? () => open('${AppRoutes.field}?segment=pending')
                : null,
          ),
        );
      } else if (field.converted > 0) {
        rows.add(
          AknListTile(
            title:
                'Son 30 günde ${Fmt.integer(field.converted)} form siparişe dönüştü',
            showChevron: g.viewFieldForms,
            onTap: g.viewFieldForms ? () => open(AppRoutes.field) : null,
          ),
        );
      }
    }

    // Ön kayıtlar (dönem özeti).
    final leads = data.leads;
    if (leads != null && leads.stats.total > 0) {
      final st = leads.stats;
      rows.add(
        AknListTile(
          title: '${Fmt.integer(st.total)} ön kayıt',
          subtitle: [
            if (leads.periodLabel.isNotEmpty) leads.periodLabel,
            if (st.converted > 0) '${Fmt.integer(st.converted)} cariye dönüştü',
          ].join(' · '),
          showChevron: g.viewLeads,
          onTap: g.viewLeads ? () => open(AppRoutes.field) : null,
        ),
      );
    }

    // Satış özeti (desteyi görmeyenler) ve limitine yaklaşan cariler.
    final sales = data.sales;
    if (sales != null) {
      if (showSales && sales.windowOrders > 0) {
        rows.add(
          AknListTile(
            title: 'Son ${sales.windowDays} gün',
            subtitle:
                '${Fmt.integer(sales.windowOrders)} sipariş · ${Fmt.liters(sales.windowLiters)}',
            amount: Fmt.moneyCompact(sales.windowAmount),
          ),
        );
      }
      if (sales.nearLimitTotal > 0) {
        rows.add(
          AknListTile(
            title:
                'Limitine yaklaşan ${Fmt.integer(sales.nearLimitTotal)} cari',
            subtitle: sales.nearLimit.isEmpty
                ? null
                : sales.nearLimit
                      .take(2)
                      .map(
                        (l) =>
                            '${l.customerTitle} ${Fmt.percent(l.usedPercent)}',
                      )
                      .join(' · '),
            showChevron: g.viewCustomers,
            onTap: g.viewCustomers ? () => open(AppRoutes.customers) : null,
          ),
        );
      }
    }
    return rows;
  }

  static String? _oldest(List<BayiPaymentRow> rows) {
    int? days;
    for (final p in rows) {
      final d = p.dueDate;
      if (d == null) continue;
      final late = TrTime.dayDiff(d, TrTime.now());
      if (days == null || late > days) days = late;
    }
    if (days == null || days < 0) return null;
    return days == 0
        ? 'En eskisinin vadesi bugün doldu'
        : 'En eskisi $days gün gecikmede';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(bayiGrantsProvider);
    final pending = (data.finance?.pending ?? 0) > 0;
    final rows = rowsOf(
      context,
      data,
      g,
      overflow: overflow,
      heroKinds: heroKinds,
      showSales: showSales,
      onboarding: pending
          ? ref.watch(myApprovalsBySubjectProvider(onboardingApprovals))
          : null,
    );
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SectionHeader(title: 'Bugün'),
        AknLedger(pour: true, children: rows),
      ],
    );
  }
}

/// Kurulum uyarıları (v4 §5 03): her açık kontrol bir defter satırı (başlık, özet ve ipucu, durum
/// hapı), dokununca web portalında düzeltme sayfası açılır — satırın sağındaki dışarı ok simgesi bunu
/// önceden söyler (v4 B15: uygulamadan çıkış sürpriz olmaz). Bugünün Tüpraş fiyatı (`tupras-today`)
/// burada yok: o iş "Sıra sizde" kartındadır.
class SetupSectionView extends ConsumerWidget {
  const SetupSectionView({super.key, required this.section});

  final BayiSetupSection section;

  /// Gösterilecek kontroller (açık olanlar; `tupras-today` hariç).
  static List<BayiSetupCheck> openChecks(BayiSetupSection s) => [
    for (final c in s.checks)
      if ((c.isOpen || c.state != SetupCheckState.ok) &&
          c.key != 'tupras-today')
        c,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = openChecks(section);
    if (open.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionHeader(title: 'Kurulum uyarıları', count: open.length),
        AknLedger(
          children: [
            for (final c in open)
              AknListTile(
                title: c.title,
                subtitle: [
                  if (c.summary.isNotEmpty) c.summary,
                  if (c.hint != null) c.hint!,
                ].join(' '),
                subtitleMaxLines: 3,
                status: AknLamp(
                  label:
                      c.stateLabel ??
                      (c.state == SetupCheckState.missing
                          ? 'Eksik'
                          : 'Kontrol edin'),
                  tone: c.state == SetupCheckState.missing
                      ? AknTone.danger
                      : AknTone.warn,
                ),
                showChevron: false,
                trailing: c.portalPath == null
                    ? null
                    : ExcludeSemantics(
                        child: Icon(
                          PhosphorIconsRegular.arrowSquareOut,
                          size: 18,
                          color: context.akn.dim,
                        ),
                      ),
                semanticLabel: [
                  c.title,
                  if (c.summary.isNotEmpty) c.summary,
                  if (c.portalPath != null) 'web portalında açılır',
                ].join(', '),
                onTap: c.portalPath == null
                    ? null
                    : () => openPortal(context, ref, c.portalPath!),
              ),
          ],
        ),
      ],
    );
  }
}

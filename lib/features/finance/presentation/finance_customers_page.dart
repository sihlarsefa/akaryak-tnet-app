import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/enums.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import '../../approvals/api.dart';
import '../application/finance_providers.dart';
import '../copy.dart';
import '../data/finance_models.dart';
import '../data/finance_repository.dart';

/// Finans (spec A.4 A5; tasarım v2 §7.7, §7.13): kök başlık, arama kuyusu, durum için bölmeli seçici,
/// risk ve "gözden geçirmesi geçen" çipleri, cari finans kartları ledger satırları olarak.
class FinanceCustomersPage extends ConsumerStatefulWidget {
  const FinanceCustomersPage({super.key});

  @override
  ConsumerState<FinanceCustomersPage> createState() =>
      _FinanceCustomersPageState();
}

class _FinanceCustomersPageState extends ConsumerState<FinanceCustomersPage> {
  FinanceQuery _query = const FinanceQuery();
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(financeListProvider(_query));
    final ctrl = ref.read(financeListProvider(_query).notifier);
    final q = _query;
    return AppScaffold(
      title: FinanceCopy.title,
      refreshing: state.refreshing,
      body: A5PagedListView<FinanceListItem>(
        state: state,
        staggerKey: q,
        onRefresh: ctrl.refresh,
        onLoadMore: () => unawaited(ctrl.loadMore()),
        padding: const EdgeInsets.only(top: 4, bottom: 24),
        itemSpacing: 0,
        header: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: SearchField(
              controller: _searchCtrl,
              hint: FinanceCopy.searchHint,
              onChanged: (s) =>
                  setState(() => _query = _query.copyWith(search: s.trim())),
            ),
          ),
          // Bölmeli seçici sığmadığında (büyük yazı) aynı seçim çiplerle yapılır.
          if (isLargeText(context))
            FilterChips<FinanceStatusFilter>(
              options: [
                for (final s in FinanceStatusFilter.values)
                  FilterOption(value: s, label: s.label),
              ],
              selected: {?q.status},
              onChanged: (s) => setState(
                () => _query = _query.copyWith(
                  status: () => s.isEmpty ? null : s.first,
                ),
              ),
            )
          else
            AknSegmented<FinanceStatusFilter?>(
              segments: [
                const FilterOption(value: null, label: FinanceCopy.allStatuses),
                for (final s in FinanceStatusFilter.values)
                  FilterOption(value: s, label: s.label),
              ],
              value: q.status,
              onChanged: (s) =>
                  setState(() => _query = _query.copyWith(status: () => s)),
            ),
          const SizedBox(height: 4),
          _RiskChips(
            risk: q.risk,
            reviewOverdue: q.reviewOverdue,
            onRisk: (r) => setState(
              () =>
                  _query = _query.copyWith(risk: () => q.risk == r ? null : r),
            ),
            onReviewOverdue: () => setState(
              () => _query = _query.copyWith(reviewOverdue: !q.reviewOverdue),
            ),
          ),
        ],
        itemBuilder: (context, item, i) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (i > 0) const AknLedgerDivider(),
            FinanceRowCard(
              item: item,
              onTap: () => context.push(
                AppRoutes.financeCustomer(item.stationCustomerId),
              ),
            ),
          ],
        ),
        empty: q.isFiltered
            ? EmptyState(
                title: FinanceCopy.filteredTitle,
                message: FinanceCopy.filteredMessage,
                illustration: AknIllustration.search,
                actionLabel: FinanceCopy.clearFilters,
                onAction: () => setState(() {
                  _query = const FinanceQuery();
                  _searchCtrl.clear();
                }),
              )
            : const EmptyState(
                title: FinanceCopy.emptyTitle,
                message: FinanceCopy.emptyMessage,
                illustration: AknIllustration.customers,
              ),
      ),
    );
  }
}

/// Risk sınıfı çipleri (tek seçim) ve "Gözden geçirmesi geçen", tek satırda bir ayraçla.
class _RiskChips extends StatelessWidget {
  const _RiskChips({
    required this.risk,
    required this.reviewOverdue,
    required this.onRisk,
    required this.onReviewOverdue,
  });

  final RiskClass? risk;
  final bool reviewOverdue;
  final ValueChanged<RiskClass> onRisk;
  final VoidCallback onReviewOverdue;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final scaler = MediaQuery.textScalerOf(context);
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final stop = rect.width <= 0
            ? 1.0
            : (1 - AknSpace.page / rect.width).clamp(0.0, 1.0);
        return LinearGradient(
          colors: const [Colors.black, Colors.black, Colors.transparent],
          stops: [0, stop, 1],
        ).createShader(rect);
      },
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: AknSpace.pagePadding,
        child: Row(
          children: [
            for (final r in const [
              RiskClass.a,
              RiskClass.b,
              RiskClass.c,
              RiskClass.d,
            ]) ...[
              AknChip(
                label: riskShort(r),
                selected: risk == r,
                onTap: () => onRisk(r),
              ),
              const SizedBox(width: 8),
            ],
            const SizedBox(width: 4),
            ExcludeSemantics(
              child: SizedBox(
                width: 1,
                height: scaler.scale(20).clamp(20.0, 36.0),
                child: ColoredBox(color: c.line),
              ),
            ),
            const SizedBox(width: 12),
            AknChip(
              label: FinanceCopy.reviewOverdue,
              selected: reviewOverdue,
              onTap: onReviewOverdue,
            ),
          ],
        ),
      ),
    );
  }
}

/// Kart durumunun lambası. Finans onayı bekleyen kart finans ekibinin sırasıdır (Pas).
StatusStyle financeProfileLamp(FinanceProfileStatus s) {
  final base = AknStatus.financeProfile(s);
  return s == FinanceProfileStatus.pending
      ? base.copyWith(tone: AknTone.brand)
      : base;
}

/// "Risk A" (etiketin harfi).
String riskShort(RiskClass r) => 'Risk ${r.label.split(' ').first}';

/// Risk sınıfının lambası: A iyi, B süreçte, C uyarı, D tehlike (her zaman "Risk X" sözüyle).
StatusStyle riskLamp(RiskClass r) => AknStatus.risk(r).withLabel(riskShort(r));

/// Finans kartı satırı (tasarım v2 §6.8): cari, sağda limit; ikinci satırda VKN ve risk sınıfı, sağda
/// kullanım oranı; durum satırında kart durumu ve (varsa) sorunlar; altta ince limit ölçeri.
class FinanceRowCard extends StatelessWidget {
  const FinanceRowCard({super.key, required this.item, required this.onTap});

  final FinanceListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final today = TrTime.todayStart();
    final status = item.status == null
        ? const StatusStyle(
            tone: AknTone.neutral,
            icon: Icons.history_rounded,
            label: 'Kart yok (eski cari)',
          )
        : financeProfileLamp(item.status!);
    final usage = item.usage;
    final liters = const {'L', 'l'}.contains(item.limitUnit?.trim());
    String amount(double? v) => liters ? Fmt.liters(v) : Fmt.moneyWhole(v);
    final reviewOverdue = item.reviewOverdue(today);
    final overdue = (item.overdueAmount ?? 0) > 0;
    final dangers = [
      if (overdue) 'Gecikme ${Fmt.moneyWhole(item.overdueAmount)}',
      if (item.hasBouncedCheque) 'Karşılıksız çek',
      if (item.hasProtestedNote) 'Protestolu senet',
    ];
    final warns = [if (reviewOverdue) 'Gözden geçirme geçti'];
    final problems = [...dangers, ...warns];
    final hasRisk =
        item.riskClass != RiskClass.none && !item.riskClass.isUnknown;
    final second = [
      if (item.taxNumber != null) 'VKN ${item.taxNumber}',
      if (hasRisk) riskShort(item.riskClass),
    ].join(', ');
    final Widget? trailing;
    if (problems.isNotEmpty) {
      final color = dangers.isNotEmpty ? c.danger.fg : c.warn.fg;
      trailing = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            dangers.isNotEmpty ? Icons.error_rounded : Icons.event_busy_rounded,
            size: MediaQuery.textScalerOf(context).scale(17).clamp(17.0, 30.0),
            color: color,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              problems.join(', '),
              style: t.bodySmall.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    } else if (item.nextReviewDate != null) {
      trailing = Text(
        'gözden geçirme ${Fmt.dayMonth(item.nextReviewDate)}',
        style: t.bodySmall.copyWith(color: c.dim),
      );
    } else {
      trailing = null;
    }
    final semantic = [
      item.customerTitle,
      status.label,
      if (item.taxNumber != null) 'VKN ${item.taxNumber}',
      if (hasRisk) riskShort(item.riskClass),
      if (usage != null)
        'limit kullanımı yüzde ${(usage * 100).round()}, ${amount(item.limitUsed)} / ${amount(item.limitAmount)}',
      ...problems,
      if (item.isStrategicPricing) 'stratejik fiyat',
      if (item.nextReviewDate != null && !reviewOverdue)
        'gözden geçirme ${Fmt.date(item.nextReviewDate)}',
    ].join(', ');
    return AknListTile(
      title: item.customerTitle,
      subtitle: second.isEmpty ? null : second,
      amount: item.limitAmount == null ? null : amount(item.limitAmount),
      amountMeta: usage == null
          ? (item.limitAmount == null ? 'limitsiz' : null)
          : '${Fmt.percent(usage * 100, maxFraction: 0)} kullanıldı',
      status: AknStatusLine(lamp: AknLamp.style(status), trailing: trailing),
      footer: usage == null
          ? null
          : ExcludeSemantics(child: UsageBar(value: usage, height: 4)),
      semanticLabel: semantic,
      onTap: onTap,
    );
  }
}

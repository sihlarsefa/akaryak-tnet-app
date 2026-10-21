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

/// Finans (spec A.4 A5): cari finans kartları, durum / risk süzgeçleri, gözden geçirmesi geçenler.
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
    return AppScaffold(
      title: FinanceCopy.title,
      subtitle: FinanceCopy.subtitle,
      refreshing: state.refreshing,
      body: A5PagedListView<FinanceListItem>(
        state: state,
        staggerKey: _query,
        onRefresh: ctrl.refresh,
        onLoadMore: () => unawaited(ctrl.loadMore()),
        header: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SearchField(
              controller: _searchCtrl,
              hint: FinanceCopy.searchHint,
              onChanged: (q) =>
                  setState(() => _query = _query.copyWith(search: q.trim())),
            ),
          ),
          FilterChips<FinanceStatusFilter>(
            options: [
              for (final s in FinanceStatusFilter.values)
                FilterOption(value: s, label: s.label),
            ],
            selected: {?_query.status},
            onChanged: (s) => setState(
              () => _query = _query.copyWith(
                status: () => s.isEmpty ? null : s.first,
              ),
            ),
          ),
          FilterChips<Object>(
            options: [
              for (final r in const [
                RiskClass.a,
                RiskClass.b,
                RiskClass.c,
                RiskClass.d,
              ])
                FilterOption<Object>(
                  value: r,
                  label: riskShort(r),
                  icon: AknStatus.risk(r).icon,
                ),
              const FilterOption<Object>(
                value: 'overdue',
                label: 'Gözden geçirmesi geçen',
                icon: Icons.event_busy_rounded,
              ),
            ],
            multi: true,
            selected: {?_query.risk, if (_query.reviewOverdue) 'overdue'},
            onChanged: (s) => setState(() {
              final risks = s.whereType<RiskClass>().toList();
              // Tek risk sınıfı seçilir: yeni seçim öncekinin yerine geçer.
              final risk = risks.isEmpty
                  ? null
                  : (risks.length == 1
                        ? risks.first
                        : risks.firstWhere((r) => r != _query.risk));
              _query = _query.copyWith(
                risk: () => risk,
                reviewOverdue: s.contains('overdue'),
              );
            }),
          ),
        ],
        itemBuilder: (context, item, _) => FinanceRowCard(
          item: item,
          onTap: () =>
              context.push(AppRoutes.financeCustomer(item.stationCustomerId)),
        ),
        empty: _query.isFiltered
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

/// "Risk A" (etiketin harfi).
String riskShort(RiskClass r) => 'Risk ${r.label.split(' ').first}';

/// Finans kartı satırı: ünvan, durum, limit kullanımı, risk ve uyarı çipleri.
class FinanceRowCard extends StatelessWidget {
  const FinanceRowCard({super.key, required this.item, required this.onTap});

  final FinanceListItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final today = TrTime.todayStart();
    final status = item.status == null
        ? const StatusStyle(
            tone: AknTone.neutral,
            icon: Icons.history_rounded,
            label: 'Kart yok (eski cari)',
          )
        : AknStatus.financeProfile(item.status!);
    final usage = item.usage;
    final unit = const {'L', 'l'}.contains(item.limitUnit?.trim()) ? 'L' : '₺';
    String amount(double? v) => unit == 'L' ? Fmt.liters(v) : Fmt.moneyWhole(v);
    final reviewOverdue = item.reviewOverdue(today);
    final overdue = (item.overdueAmount ?? 0) > 0;
    final danger = item.hasBouncedCheque || item.hasProtestedNote || overdue;
    final chips = <StatusStyle>[
      if (item.riskClass != RiskClass.none && !item.riskClass.isUnknown)
        AknStatus.risk(item.riskClass).withLabel(riskShort(item.riskClass)),
      if (reviewOverdue)
        const StatusStyle(
          tone: AknTone.warn,
          icon: Icons.event_busy_rounded,
          label: 'Gözden geçirme geçti',
        ),
      if (overdue)
        StatusStyle(
          tone: AknTone.danger,
          icon: Icons.schedule_rounded,
          label: 'Gecikme ${Fmt.moneyWhole(item.overdueAmount)}',
        ),
      if (item.hasBouncedCheque)
        const StatusStyle(
          tone: AknTone.danger,
          icon: Icons.money_off_rounded,
          label: 'Karşılıksız çek',
        ),
      if (item.hasProtestedNote)
        const StatusStyle(
          tone: AknTone.danger,
          icon: Icons.gavel_rounded,
          label: 'Protestolu senet',
        ),
      if (item.isStrategicPricing)
        const StatusStyle(
          tone: AknTone.info,
          icon: Icons.star_rounded,
          label: 'Stratejik fiyat',
        ),
    ];
    final semantic = [
      item.customerTitle,
      status.label,
      if (usage != null)
        'limit kullanımı yüzde ${(usage * 100).round()}, ${amount(item.limitUsed)} / ${amount(item.limitAmount)}',
      for (final c in chips) c.label,
      if (item.nextReviewDate != null)
        'gözden geçirme ${Fmt.date(item.nextReviewDate)}',
    ].join(', ');
    return AknCard(
      onTap: onTap,
      accent: danger ? AknTone.danger : (reviewOverdue ? AknTone.warn : null),
      semanticLabel: semantic,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AknAvatar(name: item.customerTitle, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.customerTitle,
                        style: t.bodyStrong,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (item.taxNumber != null)
                        Text('VKN ${item.taxNumber}', style: t.caption),
                    ],
                  ),
                ),
              ],
            ),
            if (usage != null) ...[
              const SizedBox(height: 12),
              UsageBar(
                value: usage,
                label: 'Limit kullanımı',
                valueLabel: Fmt.percent(usage * 100, maxFraction: 0),
              ),
              const SizedBox(height: 4),
              // Tutarlar ayrı satırda: dar ekranda ve büyük yazıda kayar.
              Text(
                '${amount(item.limitUsed)} / ${amount(item.limitAmount)}',
                style: t.caption,
              ),
            ],
            const SizedBox(height: 10),
            // Durum her zaman ilk çip (ünvanın yanında uzun durum adı sığmaz).
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final c in [status, ...chips])
                  Shrinkable(
                    child: StatusChip.style(c, size: StatusChipSize.small),
                  ),
                if (item.nextReviewDate != null && !reviewOverdue)
                  Text(
                    'Gözden geçirme ${Fmt.date(item.nextReviewDate)}',
                    style: t.caption,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

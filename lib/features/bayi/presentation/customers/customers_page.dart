import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/permissions.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/bayi_grants.dart';
import '../../application/customers_controller.dart';
import '../../copy.dart';
import '../../data/customer_models.dart';
import '../widgets/bayi_widgets.dart';
import '../widgets/paged_list_body.dart';

/// Cariler (spec A.4): arama, limit kullanımı, finans durumu, açık sipariş; saha satış temsilcisi yalnızca
/// portföyünü görür. Satıra dokununca cari kartı (360-lite).
class BayiCustomersPage extends ConsumerWidget {
  const BayiCustomersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(bayiCustomersProvider);
    final c = ref.read(bayiCustomersProvider.notifier);
    final g = ref.watch(bayiGrantsProvider);
    final portfolio = !g.policy.can(Pg.stationCustomers) && g.isFieldSales;
    return AppScaffold(
      title: portfolio ? 'Portföyüm' : 'Cariler',
      subtitle: s.list.loading
          ? null
          : '${Fmt.integer(s.list.totalCount)} cari',
      refreshing: s.list.refreshing,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchField(
              hint: 'Ünvan, vergi no, kod, şehir',
              onChanged: c.setQuery,
            ),
          ),
          Expanded(
            child: PagedListBody<BayiCustomerRow>(
              list: s.list,
              onRefresh: () => c.reload(silent: true),
              onLoadMore: () => unawaited(c.loadMore()),
              filtered: s.query.isNotEmpty,
              onClearFilters: () => c.setQuery(''),
              empty: EmptyState(
                title: BayiCopy.customersEmptyTitle,
                message: portfolio
                    ? BayiCopy.portfolioEmptyMessage
                    : BayiCopy.customersEmptyMessage,
                illustration: AknIllustration.customers,
              ),
              itemBuilder: (context, row, _) => CustomerRowCard(row: row),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cari satırı.
class CustomerRowCard extends StatelessWidget {
  const CustomerRowCard({super.key, required this.row});

  final BayiCustomerRow row;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final r = row;
    final pct = r.limitUsagePct;
    return AknCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      onTap: () => GoRouter.of(context).push(AppRoutes.customer(r.customerId)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AknAvatar(name: r.title, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.title, style: t.bodyStrong),
                Text([?r.code, ?r.place].join(' · '), style: t.bodySmall),
                if (pct != null) ...[
                  const SizedBox(height: 8),
                  BayiUsageBar(
                    value: pct / 100,
                    label: 'Limit kullanımı',
                    valueLabel: Fmt.percent(pct),
                    tone: limitTone(r.limitTone),
                    height: 6,
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (r.financeStatus != null)
                      FitStart(
                        child: StatusChip.style(
                          r.financeStatus!.statusStyle.withLabel(
                            r.financeStatusLabel,
                          ),
                          size: StatusChipSize.small,
                        ),
                      ),
                    if (r.openOrders > 0)
                      ToneTag(
                        label: '${r.openOrders} açık sipariş',
                        tone: AknTone.info,
                        icon: Icons.receipt_long_outlined,
                      ),
                  ],
                ),
                if (r.lastOrderAt != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Son sipariş ${Fmt.relative(r.lastOrderAt)}',
                    style: t.caption,
                  ),
                ],
              ],
            ),
          ),
          if (r.phone != null)
            AknIconButton(
              icon: Icons.call_outlined,
              semanticLabel: '${r.title} ara',
              onPressed: () => callPhone(context, r.phone!),
            ),
        ],
      ),
    );
  }
}

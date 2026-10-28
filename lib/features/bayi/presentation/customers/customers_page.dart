import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/permissions.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../application/bayi_grants.dart';
import '../../application/customers_controller.dart';
import '../../copy.dart';
import '../../data/customer_models.dart';
import '../widgets/bayi_widgets.dart';
import '../widgets/paged_list_body.dart';

/// Cariler (spec A.4, tasarım v3 "Akış"): kök başlık, arama kuyusu, cari kartları (limit kullanımı
/// sağda, finans durumu çipi, açık sipariş sayısı, limite yaklaşanda dolarak gelen kullanım çubuğu);
/// saha satış temsilcisi yalnızca portföyünü görür. Karta dokununca cari kartı (360-lite).
class BayiCustomersPage extends ConsumerWidget {
  const BayiCustomersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(bayiCustomersProvider);
    final c = ref.read(bayiCustomersProvider.notifier);
    final g = ref.watch(bayiGrantsProvider);
    final portfolio = !g.policy.can(Pg.stationCustomers) && g.isFieldSales;
    final total = s.list.totalCount;
    return AppScaffold(
      title: portfolio ? 'Portföyüm' : 'Cariler',
      refreshing: s.list.refreshing,
      body: PagedListBody<BayiCustomerRow>(
        list: s.list,
        header: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 2),
            child: SearchField(
              hint: 'Ünvan, vergi no, kod ya da şehir',
              onChanged: c.setQuery,
            ),
          ),
        ],
        onRefresh: () => c.reload(silent: true),
        onLoadMore: () => unawaited(c.loadMore()),
        filtered: s.query.isNotEmpty,
        // Satır kendi basılı hâlini çizer (içeride küçülür); kart sabit kalır.
        pressableCards: false,
        onClearFilters: () => c.setQuery(''),
        empty: EmptyState(
          title: BayiCopy.customersEmptyTitle,
          message: portfolio
              ? BayiCopy.portfolioEmptyMessage
              : BayiCopy.customersEmptyMessage,
          illustration: AknIllustration.customers,
        ),
        footer: total <= 0
            ? null
            : ListFooterNote(
                portfolio
                    ? 'Portföyünüzde ${Fmt.integer(total)} cari var.'
                    : 'Toplam ${Fmt.integer(total)} cari. Pasif cariler de listede, kartında "Pasif" yazar.',
              ),
        itemBuilder: (context, row, _) => CustomerRowCard(row: row),
      ),
    );
  }
}

/// Cari kartı (tasarım v3 liste kartı; kartı [PagedListBody] çizer): ünvan, kod ve yer; sağda limit
/// kullanımı ("%62", "limit kullanımı", tablo rakamları); durum satırında finans kartı çipi ve açık
/// sipariş sayısı; limite yaklaşan ya da aşan caride dolarak gelen kullanım çubuğu; son sipariş zamanı;
/// arama düğmesi.
class CustomerRowCard extends StatelessWidget {
  const CustomerRowCard({super.key, required this.row});

  final BayiCustomerRow row;

  @override
  Widget build(BuildContext context) {
    final r = row;
    final pct = r.limitUsagePct;
    final t = context.aknText;
    final k = context.akn;
    final tone = limitTone(r.limitTone);
    final status = r.financeStatus;
    final last = r.lastOrderAt == null
        ? null
        : 'son sipariş ${TurkishText.lower(Fmt.relative(r.lastOrderAt))}';
    final near = tone == AknTone.warn || tone == AknTone.danger;
    return AknListTile(
      padding: kCardRowPadding,
      title: r.title,
      subtitle: [?r.code, ?r.place, ?last].join(', '),
      amount: pct == null ? null : Fmt.percent(pct),
      amountMeta: pct == null ? null : 'limit kullanımı',
      status: status == null && r.openOrders == 0 && tone == null
          ? null
          : AknStatusLine(
              lamp: status != null
                  ? AknLamp.style(
                      status.statusStyle.withLabel(r.financeStatusLabel),
                    )
                  : (tone == AknTone.warn || tone == AknTone.danger)
                  ? AknLamp(
                      label: tone == AknTone.danger
                          ? 'Limit aşıldı'
                          : 'Limite yakın',
                      tone: tone!,
                    )
                  : null,
              trailing: r.openOrders > 0
                  ? Text(
                      '${r.openOrders} açık sipariş',
                      style: t.bodySmall.copyWith(
                        color: k.ink,
                        fontWeight: FontWeight.w600,
                        fontFeatures: AknNumerals.tabular,
                      ),
                    )
                  : null,
            ),
      footer: near && pct != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: BayiUsageBar(value: pct / 100, tone: tone, height: 6),
                ),
                if (status != null) ...[
                  const SizedBox(height: 8),
                  RowNote(
                    icon: PhosphorIconsFill.gauge,
                    tone: tone,
                    text: tone == AknTone.danger
                        ? 'Limit aşıldı, yeni sipariş finans onayına gider.'
                        : 'Limite yakın, limitin ${Fmt.percent(pct)} kadarı kullanıldı.',
                  ),
                ],
              ],
            )
          : status != null && near
          ? RowNote(
              icon: PhosphorIconsFill.gauge,
              tone: tone,
              text: tone == AknTone.danger
                  ? 'Limit aşıldı, yeni sipariş finans onayına gider.'
                  : 'Limite yakın, limitin ${Fmt.percent(pct)} kadarı kullanıldı.',
            )
          : null,
      trailing: r.phone == null
          ? null
          : AknIconButton(
              icon: PhosphorIconsRegular.phone,
              semanticLabel: '${r.title} ara',
              onPressed: () => callPhone(context, r.phone!),
            ),
      onTap: () => GoRouter.of(context).push(AppRoutes.customer(r.customerId)),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/permissions.dart';
import '../../../../core/models/models.dart';
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

/// Cariler (tasarım v4 "Sade" §3.2): bant "Cariler" + canlı durum satırı ("24 cari · 3'ü limitine
/// yakın") + ⌕ (arama şeridi bandın altında açılır); cariler tek defter kartında (limit kullanımı
/// sağda, finans durumu yalnızca istisnada, limite yaklaşanda dolarak gelen kullanım çubuğu); saha
/// satış temsilcisi yalnızca portföyünü görür. Satıra dokununca cari kartı (360-lite).
class BayiCustomersPage extends ConsumerStatefulWidget {
  const BayiCustomersPage({super.key});

  @override
  ConsumerState<BayiCustomersPage> createState() => _BayiCustomersPageState();
}

class _BayiCustomersPageState extends ConsumerState<BayiCustomersPage> {
  late bool _searching = ref.read(bayiCustomersProvider).query.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(bayiCustomersProvider);
    final c = ref.read(bayiCustomersProvider.notifier);
    final g = ref.watch(bayiGrantsProvider);
    final portfolio = !g.policy.can(Pg.stationCustomers) && g.isFieldSales;
    final total = s.list.totalCount;
    // "24 cari · 3'ü limitine yakın" (yakın sayısı yüklenen satırlardan; liste bitmişse tam).
    final near = s.list.items.where((r) {
      final tone = limitTone(r.limitTone);
      return tone == AknTone.warn || tone == AknTone.danger;
    }).length;
    final Object? status = total <= 0
        ? null
        : [
            AknStatusClause('${Fmt.integer(total)} cari'),
            if (near > 0 && !s.list.hasMore)
              AknStatusClause('${_possessive(near)} limitine yakın'),
          ];
    return AppScaffold(
      title: portfolio ? 'Portföyüm' : 'Cariler',
      bandIcon: PhosphorIconsRegular.usersThree,
      status: status,
      refreshing: s.list.refreshing,
      actions: [
        AknSearchReveal.button(
          semanticLabel: 'Cari ara',
          onPressed: () => setState(() => _searching = true),
        ),
      ],
      body: Column(
        children: [
          AknSearchReveal(
            open: _searching,
            hint: 'Ünvan, vergi no, kod ya da şehir',
            onChanged: c.setQuery,
            onClose: () => setState(() => _searching = false),
          ),
          Expanded(
            child: PagedListBody<BayiCustomerRow>(
              list: s.list,
              ledger: true,
              header: const [SizedBox(height: 4)],
              onRefresh: () => c.reload(silent: true),
              onLoadMore: () => unawaited(c.loadMore()),
              filtered: s.query.isNotEmpty,
              query: s.query,
              onClearFilters: () {
                c.setQuery('');
                setState(() => _searching = false);
              },
              empty: EmptyState(
                compact: true,
                title: BayiCopy.customersEmptyTitle,
                message: portfolio
                    ? BayiCopy.portfolioEmptyMessage
                    : BayiCopy.customersEmptyMessage,
                illustration: AknIllustration.customers,
              ),
              footer: total <= 0
                  ? null
                  : const ListFooterNote(
                      'Pasif cariler de listede; satırında "Pasif" yazar.',
                    ),
              itemBuilder: (context, row, _) => CustomerRowCard(row: row),
            ),
          ),
        ],
      ),
    );
  }

  /// "3'ü", "2'si", "1'i".
  static String _possessive(int n) {
    const suffix = ['', 'i', 'si', 'ü', 'ü', 'i', 'sı', 'si', 'i', 'u'];
    final ones = n % 10;
    if (ones != 0) return "$n'${suffix[ones]}";
    const tens = ['', 'u', 'si', 'u', 'ı', 'si', 'ı', 'i', 'i', 'ı'];
    final t = (n ~/ 10) % 10;
    if (t != 0) return "$n'${tens[t]}";
    return (n ~/ 100) % 10 != 0 ? "$n'ü" : "$n'i";
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
    // v4 P4: cari kodu satırda yok (arama yine bulur); olağan finans durumu ("Onaylı") yazılmaz.
    final exception = status != null && status != FinanceProfileStatus.approved;
    return AknListTile(
      title: r.title,
      subtitle: [?r.place, ?last].join(' · '),
      amount: pct == null ? null : Fmt.percent(pct),
      amountMeta: pct == null ? null : 'limit kullanımı',
      status: !exception && r.openOrders == 0 && !near
          ? null
          : AknStatusLine(
              lamp: exception
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

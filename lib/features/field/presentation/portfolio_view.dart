import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/external_activity.dart';
import '../../../core/utils/format.dart';
import '../application/field_access.dart';
import '../application/field_lists.dart';
import '../copy.dart';
import '../data/field_models.dart';
import '../data/field_repository.dart';
import 'widgets/field_widgets.dart';

/// Portföy (temsilcinin carileri; `me/portfolio` skip/take, arama). İlk sayfa çevrimdışı açılış için
/// saklanır. Kart dokununca cari kartı açılır.
class FieldPortfolioView extends ConsumerStatefulWidget {
  const FieldPortfolioView({super.key});

  @override
  ConsumerState<FieldPortfolioView> createState() => _FieldPortfolioViewState();
}

class _FieldPortfolioViewState extends ConsumerState<FieldPortfolioView> {
  final _scroll = ScrollController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 480) {
        unawaited(
          ref.read(fieldPortfolioProvider(_search).notifier).loadMore(),
        );
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fieldPortfolioProvider(_search));
    final header = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: SearchField(
          hint: 'Portföyünüzde arayın',
          onChanged: (s) => setState(() => _search = s),
        ),
      ),
      if (state.cachedAt != null) FieldCachedNote(at: state.cachedAt!),
    ];

    Widget list;
    if (state.firstLoading && state.items.isEmpty) {
      list = ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: [...header, const FieldSkeletonCards(count: 6)],
      );
    } else if (state.items.isEmpty) {
      list = ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ...header,
          FieldListState(
            error: state.error,
            onRetry: () =>
                ref.read(fieldPortfolioProvider(_search).notifier).refresh(),
            emptyTitle: FieldCopy.portfolioEmptyTitle,
            emptyMessage: FieldCopy.portfolioEmptyMessage,
            filtered: _search.isNotEmpty,
            illustration: AknIllustration.customers,
          ),
        ],
      );
    } else {
      final items = state.items;
      list = StaggerScope(
        key: ValueKey(_search),
        child: ListView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 96),
          itemCount: header.length + items.length + 1,
          itemBuilder: (context, i) {
            if (i < header.length) return header[i];
            final index = i - header.length;
            if (index == items.length) {
              return FieldListFooter(
                loading: state.loadingMore,
                error: state.moreError,
                onRetry: () => ref
                    .read(fieldPortfolioProvider(_search).notifier)
                    .loadMore(),
                total: state.total,
                shown: items.length,
              );
            }
            final row = items[index];
            return Padding(
              padding: EdgeInsets.fromLTRB(16, index == 0 ? 12 : 0, 16, 8),
              child: StaggerItem(
                index: index,
                child: _PortfolioTile(row: row),
              ),
            );
          },
        ),
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: PullToRefresh(
            onRefresh: () =>
                ref.read(fieldPortfolioProvider(_search).notifier).refresh(),
            child: list,
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: TopProgressBar(active: state.refreshing),
        ),
      ],
    );
  }
}

class _PortfolioTile extends ConsumerWidget {
  const _PortfolioTile({required this.row});

  final PortfolioRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.aknText;
    final access = ref.watch(fieldAccessProvider);
    return AknCard(
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: [
                row.customerTitle,
                if (row.customerCode.isNotEmpty) 'Kod ${row.customerCode}',
                ?row.city,
                'Cari kartını aç',
              ].join(', '),
              excludeSemantics: true,
              child: InkWell(
                borderRadius: AknRadius.card,
                onTap: () => showFieldCustomerCard(context, row),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AknSpace.minTap),
                  child: Row(
                    children: [
                      AknAvatar(name: row.customerTitle, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              row.customerTitle,
                              style: t.bodyStrong,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              [
                                if (row.customerCode.isNotEmpty)
                                  row.customerCode,
                                ?row.city,
                              ].join(' · '),
                              style: t.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (access.canCreateForm)
            AknIconButton(
              icon: Icons.post_add_rounded,
              semanticLabel: '${row.customerTitle} için saha formu',
              onPressed: () => context.push(_newFormPath(row)),
            ),
        ],
      ),
    );
  }
}

String _newFormPath(PortfolioRow row) => Uri(
  path: AppRoutes.fieldFormNew,
  queryParameters: {
    'customerId': '${row.customerId}',
    'customerTitle': row.customerTitle,
  },
).toString();

/// Cari kartı (spec A.4 A6 "Portföy with search and the cari card"): limit göstergesi, teslimat
/// noktaları, önerilen fiyatlar (`field-orders/options-v2`) ve varsa bayi cari özeti (finans durumu,
/// açık formlar, yetkililer; `bayi/customers/{id}/summary`).
Future<void> showFieldCustomerCard(BuildContext context, PortfolioRow row) =>
    showAppSheet<void>(
      context: context,
      title: row.customerTitle,
      subtitle: [
        if (row.customerCode.isNotEmpty) row.customerCode,
        ?row.city,
      ].join(' · '),
      builder: (_) => _CustomerCard(row: row, rootContext: context),
    );

final _cardOptionsProvider = FutureProvider.autoDispose
    .family<FieldOptions, int>(
      (ref, customerId) =>
          ref.read(fieldRepositoryProvider).options(customerId),
    );

final _cardSummaryProvider = FutureProvider.autoDispose
    .family<FieldCustomerSummary, int>(
      (ref, customerId) =>
          ref.read(fieldRepositoryProvider).customerSummary(customerId),
    );

class _CustomerCard extends ConsumerWidget {
  const _CustomerCard({required this.row, required this.rootContext});

  final PortfolioRow row;
  final BuildContext rootContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.aknText;
    final c = context.akn;
    final access = ref.watch(fieldAccessProvider);
    final options = ref.watch(_cardOptionsProvider(row.customerId));
    final summary = ref.watch(_cardSummaryProvider(row.customerId));
    final s = summary.valueOrNull;

    void go(String path) {
      Navigator.of(context).pop();
      GoRouter.of(rootContext).push(path);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (s != null) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (s.financeLabel != null)
                StatusChip(
                  label: s.financeLabel!,
                  tone: s.canOrder ? AknTone.ok : AknTone.warn,
                  icon: s.canOrder
                      ? Icons.verified_outlined
                      : Icons.hourglass_top_rounded,
                  size: StatusChipSize.small,
                ),
              if (!s.isActive)
                const StatusChip(
                  label: 'Pasif cari',
                  tone: AknTone.neutral,
                  icon: Icons.block_rounded,
                  size: StatusChipSize.small,
                ),
            ],
          ),
          if (s.blockReason != null) ...[
            const SizedBox(height: 8),
            AknBanner(tone: AknTone.warn, message: s.blockReason!),
          ],
          const SizedBox(height: 12),
        ],
        options.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: LoadingView(message: 'Cari bilgileri yükleniyor'),
          ),
          error: (e, _) => AknBanner(
            tone: AknTone.warn,
            message: 'Cari bilgileri şu an yüklenemedi.',
            actionLabel: FieldCopy.retry,
            onAction: () =>
                ref.invalidate(_cardOptionsProvider(row.customerId)),
          ),
          data: (o) => _OptionsBlock(options: o),
        ),
        if (s != null && s.openForms.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Açık formlar', style: t.bodyStrong),
          const SizedBox(height: 4),
          for (final f in s.openForms)
            AknListTile(
              title: f.formNumber,
              subtitle: Fmt.liters(f.totalLiters),
              trailing: StatusChip.style(
                f.status.statusStyle,
                size: StatusChipSize.small,
              ),
              padding: const EdgeInsets.symmetric(vertical: 6),
              onTap: () => go(AppRoutes.fieldForm(f.id)),
            ),
        ],
        if (s != null && s.contacts.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Yetkililer', style: t.bodyStrong),
          for (final p in s.contacts)
            AknListTile(
              title: p.name,
              subtitle: [
                ?p.role,
                if (p.phone != null) Fmt.phone(p.phone),
              ].join(' · '),
              padding: const EdgeInsets.symmetric(vertical: 6),
              trailing: p.phone == null
                  ? null
                  : AknIconButton(
                      icon: Icons.call_rounded,
                      semanticLabel: '${p.name} kişisini ara',
                      onPressed: () =>
                          launchExternal(Uri(scheme: 'tel', path: p.phone)),
                    ),
            ),
        ],
        const SizedBox(height: 20),
        if (access.canCreateForm)
          AknButton(
            label: 'Saha formu oluştur',
            icon: Icons.post_add_rounded,
            expand: true,
            onPressed: () => go(_newFormPath(row)),
          ),
        if (access.canOpenCustomerCard) ...[
          const SizedBox(height: 4),
          AknButton.ghost(
            label: 'Cari kartını aç',
            expand: true,
            onPressed: () => go(AppRoutes.customer(row.customerId)),
          ),
        ],
        Text(
          'Fiyat ve limit bilgisi cari ile paylaşmanız için değil, görüşmeye hazırlık içindir.',
          style: t.caption.copyWith(color: c.dim),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _OptionsBlock extends StatelessWidget {
  const _OptionsBlock({required this.options});

  final FieldOptions options;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final limit = options.limit;
    final ratio = limit.usedRatio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ratio != null)
          UsageBar(
            value: ratio,
            label: '${limit.limitPeriod ?? 'Dönem'} limit kullanımı',
            valueLabel: '%${(ratio * 100).round()}',
          ),
        if (limit.message.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(limit.message, style: t.bodySmall),
        ],
        if (options.products.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Önerilen fiyatlar', style: t.bodyStrong),
          for (final p in options.products)
            FactRow(
              label: p.name,
              value: [
                Fmt.unitPrice(p.suggestedUnitPrice),
                ?p.suggestedSourceLabel,
              ].join(' · '),
            ),
        ],
        if (options.points.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Teslimat noktaları', style: t.bodyStrong),
          for (final p in options.points)
            AknListTile(
              title: p.name,
              subtitle: p.place.isEmpty ? p.address : p.place,
              leadingIcon: Icons.place_outlined,
              dense: true,
              padding: const EdgeInsets.symmetric(vertical: 6),
            ),
        ],
      ],
    );
  }
}

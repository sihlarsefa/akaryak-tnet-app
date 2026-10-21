import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/offline/connectivity.dart';
import '../../../../core/ui/ui.dart';
import '../../application/bayi_grants.dart';
import '../../application/desk_controller.dart';
import '../../copy.dart';
import '../../data/desk_models.dart';
import '../widgets/bayi_widgets.dart';
import '../widgets/paged_list_body.dart';
import 'desk_row_card.dart';
import 'desk_sheets.dart';

/// Teklif masası (spec A.4 / A.3 adım 3): `bayi/quote-desk*` üzerinde satır içi ₺/L ve teslim günü,
/// "Önerileri uygula", "Seçilenlere aynı fiyat/tarih", çoklu seçim ve toplu gönderim; satır başına sonuç
/// (finansa gidenler uyarı tonunda), gönderim sonrası masa ve sayılar tazelenir. Geri sayım yalnızca
/// süre dolumu açıkken; `quotingBlocked` iken masa salt okunur.
class QuoteDeskPage extends ConsumerStatefulWidget {
  const QuoteDeskPage({super.key, this.initialCustomerId});

  /// `?customerId=` (cari kartındaki "Teklif ver").
  final int? initialCustomerId;

  @override
  ConsumerState<QuoteDeskPage> createState() => _QuoteDeskPageState();
}

class _QuoteDeskPageState extends ConsumerState<QuoteDeskPage> {
  @override
  void initState() {
    super.initState();
    final id = widget.initialCustomerId;
    if (id != null) {
      Future.microtask(
        () => ref.read(quoteDeskProvider.notifier).setCustomer(id),
      );
    }
  }

  @override
  void didUpdateWidget(QuoteDeskPage old) {
    super.didUpdateWidget(old);
    final id = widget.initialCustomerId;
    if (id != null && id != old.initialCustomerId) {
      Future.microtask(
        () => ref.read(quoteDeskProvider.notifier).setCustomer(id),
      );
    }
  }

  Future<void> _submit() async {
    final desk = ref.read(quoteDeskProvider.notifier);
    try {
      final summary = await desk.submit();
      if (!mounted) return;
      if (summary == null) {
        final errors = ref.read(quoteDeskProvider).rowErrors.length;
        if (errors > 0) {
          AppToast.warning(
            '$errors satırda eksik ya da hatalı bilgi var.',
            context: context,
          );
        }
        return;
      }
      final view = View.maybeOf(context);
      if (view != null) {
        unawaited(
          SemanticsService.sendAnnouncement(
            view,
            '${summary.quoted} teklif gönderildi'
            '${summary.routedToFinance > 0 ? ', ${summary.routedToFinance} finans onayına gitti' : ''}'
            '${summary.failed > 0 ? ', ${summary.failed} gönderilemedi' : ''}',
            TextDirection.ltr,
          ),
        );
      }
      await showDeskResultsSheet(context, summary);
    } catch (e) {
      if (mounted) showActionFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(quoteDeskProvider);
    final c = ref.read(quoteDeskProvider.notifier);
    final grants = ref.watch(bayiGrantsProvider);
    final online = ref.watch(isOnlineProvider);
    final header = s.header;
    final blocked = header?.quotingBlocked ?? false;
    final editable =
        grants.quoteOnDesk && (header?.canSubmit ?? false) && !blocked;
    final today = s.today;
    final subtitle = [
      '${today.ordersToday} yeni sipariş',
      '${today.quotedToday} teklif',
      if (today.avgFirstQuoteMinutes != null)
        'ilk teklif ort. ${today.avgFirstQuoteMinutes} dk',
    ].join(' · ');
    final views = [
      DeskView.all,
      DeskView.awaitingQuote,
      DeskView.revision,
      if (s.expiryEnabled) DeskView.expiringSoon,
    ];
    final filterCount =
        (s.customerId == null ? 0 : 1) + (s.productId == null ? 0 : 1);
    return AppScaffold(
      title: 'Teklif masası',
      subtitle: header == null ? null : 'Bugün $subtitle',
      refreshing: s.list.refreshing,
      actions: [
        FilterButton(
          label: 'Süzgeç ve sıralama',
          count: filterCount,
          onPressed: () => showDeskFilterSheet(context),
        ),
      ],
      actionBar: editable && s.rows.isNotEmpty
          ? _DeskActionBar(online: online, onSubmit: () => unawaited(_submit()))
          : null,
      body: PagedListBody<DeskRow>(
        list: s.list,
        onRefresh: () => c.reload(silent: true),
        onLoadMore: () => unawaited(c.loadMore()),
        filtered: s.isFiltered || s.view != DeskView.all,
        onClearFilters: () {
          c.clearFilters();
          c.setView(DeskView.all);
        },
        empty: const EmptyState(
          title: BayiCopy.deskEmptyTitle,
          message: BayiCopy.deskEmptyMessage,
          illustration: AknIllustration.orders,
        ),
        header: [
          UpdatedCaption(
            updatedAt: s.list.updatedAt,
            fromCache: s.fromCache,
            error: s.list.error,
          ),
          if (blocked)
            _Pad(
              AknBanner(
                tone: AknTone.danger,
                icon: Icons.block_rounded,
                title: 'Yeni teklif verilemez',
                message:
                    header?.quotingBlockedReason ??
                    'Bekleyen siparişleri yalnızca görüntüleyebilirsiniz.',
              ),
            ),
          if (header?.epdkWarning != null)
            _Pad(
              AknBanner(
                tone: AknTone.warn,
                icon: Icons.verified_user_outlined,
                message: header!.epdkWarning!,
              ),
            ),
          if ((header?.financeHeld ?? 0) > 0)
            _Pad(
              AknBanner(
                tone: AknTone.info,
                icon: Icons.account_balance_rounded,
                message:
                    '${header!.financeHeld} sipariş finans onayında; finans onaylayınca masaya düşer.',
              ),
            ),
          if (!grants.quoteOnDesk && header != null)
            const _Pad(
              AknBanner(
                tone: AknTone.neutral,
                icon: Icons.visibility_outlined,
                message:
                    'Teklif masasını görüntüleyebilirsiniz; teklif verme yetkiniz yok.',
              ),
            ),
          const SizedBox(height: 8),
          FilterChips<DeskView>(
            allowEmpty: false,
            options: [
              for (final v in views)
                FilterOption(value: v, label: v.label, count: s.counts.of(v)),
            ],
            selected: {s.view},
            onChanged: (v) => c.setView(v.first),
          ),
          if (s.isFiltered)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (s.customerId != null)
                    InputChip(
                      label: Text(
                        s.facets.customers
                                .where((f) => f.id == s.customerId)
                                .firstOrNull
                                ?.title ??
                            'Cari #${s.customerId}',
                      ),
                      onDeleted: () => c.setCustomer(null),
                      deleteButtonTooltipMessage: 'Cari süzgecini kaldır',
                    ),
                  if (s.productId != null)
                    InputChip(
                      label: Text(
                        s.facets.products
                                .where((f) => f.id == s.productId)
                                .firstOrNull
                                ?.title ??
                            'Ürün #${s.productId}',
                      ),
                      onDeleted: () => c.setProduct(null),
                      deleteButtonTooltipMessage: 'Ürün süzgecini kaldır',
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
        itemBuilder: (context, row, _) => DeskRowCard(
          key: ValueKey(row.orderId),
          row: row,
          draft: s.draftOf(row.orderId),
          selected: s.selected.contains(row.orderId),
          editable: editable,
          deadline: s.expiryEnabled ? s.deadlines[row.orderId] : null,
          outcome: s.outcomes[row.orderId],
          error: s.rowErrors[row.orderId],
        ),
      ),
    );
  }
}

class _Pad extends StatelessWidget {
  const _Pad(this.child);

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: child);
}

/// Alt eylem çubuğu: seçim özeti, "Önerileri uygula", "Aynı fiyat/tarih", "Teklifleri gönder".
class _DeskActionBar extends ConsumerWidget {
  const _DeskActionBar({required this.online, required this.onSubmit});

  final bool online;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(quoteDeskProvider);
    final c = ref.read(quoteDeskProvider.notifier);
    final t = context.aknText;
    final selected = s.selected.length;
    final ready = c.readyCount;
    final allSelected = selected > 0 && selected == s.rows.length;
    // Büyük yazı ölçeğinde öğeler alt alta dizilir (yan yana sıkışıp ekranı kaplamasın).
    final large = isLargeText(context);
    final status = Semantics(
      liveRegion: true,
      child: Text(
        selected == 0
            ? BayiCopy.deskSubmitHint
            : '$selected seçili · $ready hazır',
        style: t.label,
      ),
    );
    final selectAll = TextButton(
      onPressed: allSelected ? c.clearSelection : c.selectAll,
      child: Text(allSelected ? 'Seçimi kaldır' : 'Tümünü seç'),
    );
    final suggest = AknButton.secondary(
      label: 'Önerileri uygula',
      icon: Icons.auto_fix_high_rounded,
      size: AknButtonSize.small,
      expand: true,
      onPressed: () {
        final n = c.applySuggestions();
        AppToast.info(
          n == 0
              ? 'Önerisi olan satır yok.'
              : '$n satıra önerilen fiyat yazıldı.',
          context: context,
        );
      },
    );
    final same = AknButton.secondary(
      label: 'Aynı fiyat/tarih',
      icon: Icons.copy_all_rounded,
      size: AknButtonSize.small,
      expand: true,
      onPressed: selected == 0 ? null : () => showBulkSameSheet(context, ref),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (large) ...[
          status,
          Align(alignment: AlignmentDirectional.centerStart, child: selectAll),
          suggest,
          const SizedBox(height: 6),
          same,
        ] else ...[
          Row(
            children: [
              Expanded(child: status),
              selectAll,
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(child: suggest),
              const SizedBox(width: 8),
              Expanded(child: same),
            ],
          ),
        ],
        if (selected > 0) ...[
          const SizedBox(height: 6),
          AknButton(
            label: s.checking
                ? 'Kontrol ediliyor'
                : 'Teklifleri gönder ($selected)',
            icon: Icons.send_rounded,
            expand: true,
            loading: s.submitting,
            loadingLabel: s.checking ? BayiCopy.checking : 'Gönderiliyor',
            onPressed: online && ready > 0 ? onSubmit : null,
          ),
          if (!online)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                BayiCopy.deskOffline,
                style: t.caption,
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ],
    );
  }
}

/// Rota kurucusu: `/quote-desk?customerId=`.
Widget buildQuoteDeskPage(BuildContext context, GoRouterState state) =>
    QuoteDeskPage(
      initialCustomerId: int.tryParse(
        state.uri.queryParameters['customerId'] ?? '',
      ),
    );

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

/// Teklif masası (spec A.4 / A.3 adım 3, tasarım v3 "Akış"): kök başlık, finans bekleyenler için kuyu,
/// sayılı çipler (Tümü, Yeni, Revize, Süresi yaklaşan), her sipariş beyaz bir kart (kart içi ₺/L ve
/// teslim günü; seçilince turuncu yumuşak zemin), "Önerileri uygula", "Aynı fiyatı uygula", çoklu
/// seçim ve toplu gönderim; kart başına sonuç çipi süzülerek gelir (finansa gidenler uyarı tonunda),
/// gönderim sonrası masa ve sayılar tazelenir. Kartlar art arda yükselerek gelir (görünüm ya da süzgeç
/// değişince yeniden). Geri sayım yalnızca süre dolumu açıkken; `quotingBlocked` iken masa salt
/// okunur.
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
            errors == 1
                ? '1 satırda eksik ya da hatalı bilgi var. Satırı düzeltip tekrar gönderin.'
                : '$errors satırda eksik ya da hatalı bilgi var. Satırları düzeltip tekrar gönderin.',
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
    final views = [
      DeskView.all,
      DeskView.awaitingQuote,
      DeskView.revision,
      if (s.expiryEnabled) DeskView.expiringSoon,
    ];
    final filterCount =
        (s.customerId == null ? 0 : 1) + (s.productId == null ? 0 : 1);
    final todayLine = header == null
        ? null
        : [
            'Bugün ${today.ordersToday} yeni sipariş, ${today.quotedToday} teklif',
            if (today.avgFirstQuoteMinutes != null)
              'ilk teklif ortalama ${today.avgFirstQuoteMinutes} dk',
          ].join(', ');
    return AppScaffold(
      title: 'Teklif masası',
      bandIcon: PhosphorIconsRegular.invoice,
      eyebrow: 'Bayi',
      description: 'Teklif bekleyen siparişler',
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
        // Kartta fiyat alanı ve onay kutusu var: kart dokununca küçülmez.
        pressableCards: false,
        staggerKey: (s.view, s.customerId, s.productId),
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
        footer: const ListFooterNote(
          'Teklif verdiğiniz siparişler müşterinin kararına gider; Siparişler sayfasında izlenir.',
        ),
        header: [
          UpdatedCaption(
            updatedAt: s.list.updatedAt,
            fromCache: s.fromCache,
            error: s.list.error,
          ),
          if (blocked)
            PageWell(
              tone: AknTone.danger,
              icon: PhosphorIconsRegular.prohibit,
              title: 'Yeni teklif verilemez',
              message:
                  header?.quotingBlockedReason ??
                  'Bekleyen siparişleri yalnızca görüntüleyebilirsiniz.',
            ),
          if (header?.epdkWarning != null)
            PageWell(
              tone: AknTone.warn,
              icon: PhosphorIconsRegular.shieldCheck,
              message: header!.epdkWarning!,
            ),
          if ((header?.financeHeld ?? 0) > 0)
            PageWell(
              tone: AknTone.info,
              icon: PhosphorIconsRegular.bank,
              message:
                  '${header!.financeHeld} sipariş finans onayında; finans onaylayınca masaya düşer.',
            ),
          if (!grants.quoteOnDesk && header != null)
            const PageWell(
              tone: AknTone.neutral,
              icon: PhosphorIconsRegular.eye,
              message:
                  'Teklif masasını görüntüleyebilirsiniz; teklif verme yetkiniz yok.',
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
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
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
          if (editable && s.rows.isNotEmpty && !isLargeText(context))
            const _SelectAllRow()
          else if (todayLine != null)
            ListFooterNote(todayLine),
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

/// Listenin üstünde "Tümünü seç" satırı: satırların seçim kutularıyla aynı hizada üç durumlu kutu ve
/// sağda bugünün özeti.
class _SelectAllRow extends ConsumerWidget {
  const _SelectAllRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(quoteDeskProvider);
    final c = ref.read(quoteDeskProvider.notifier);
    final t = context.aknText;
    final k = context.akn;
    final selected = s.selected.length;
    final all = selected > 0 && selected == s.rows.length;
    final value = all ? true : (selected == 0 ? false : null);
    final today = s.today;
    void toggle() => all || selected > 0 ? c.clearSelection() : c.selectAll();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 20, 0),
      child: Row(
        children: [
          Semantics(
            label: all || selected > 0 ? 'Seçimi kaldır' : 'Tümünü seç',
            button: true,
            excludeSemantics: true,
            onTap: toggle,
            child: InkWell(
              onTap: toggle,
              borderRadius: AknRadius.button,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 48,
                      child: IgnorePointer(
                        child: Checkbox(
                          tristate: true,
                          value: value,
                          onChanged: (_) {},
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      all || selected > 0 ? 'Seçimi kaldır' : 'Tümünü seç',
                      style: t.bodyStrong.copyWith(color: k.ink),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              'Bugün ${today.ordersToday} yeni, ${today.quotedToday} teklif',
              textAlign: TextAlign.end,
              maxLines: 2,
              style: t.label.copyWith(
                fontWeight: FontWeight.w400,
                color: k.dim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Alt eylem çubuğu (§7.7): seçim yokken ipucu + "Önerileri uygula" (hayalet); seçim varken
/// "3 sipariş seçildi" + "Önerileri uygula", altında "Aynı fiyatı uygula" (ikincil) ve
/// "Teklifleri gönder (3)" (birincil). Büyük yazıda toplu araçlar tek düğmeyle açılan sayfada.
class _DeskActionBar extends ConsumerWidget {
  const _DeskActionBar({required this.online, required this.onSubmit});

  final bool online;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(quoteDeskProvider);
    final c = ref.read(quoteDeskProvider.notifier);
    final t = context.aknText;
    final k = context.akn;
    final selected = s.selected.length;
    final ready = c.readyCount;
    // Büyük yazı ölçeğinde öğeler alt alta dizilir (yan yana sıkışıp ekranı kaplamasın).
    final large = isLargeText(context);
    void suggest() {
      final n = c.applySuggestions();
      AppToast.info(
        n == 0
            ? 'Önerisi olan satır yok.'
            : '$n satıra önerilen fiyat yazıldı.',
        context: context,
      );
    }

    final status = Semantics(
      liveRegion: true,
      child: Text(
        selected == 0
            ? BayiCopy.deskSubmitHint
            : ready == selected
            ? '$selected sipariş seçildi'
            : '$selected sipariş seçildi, $ready hazır',
        style: selected == 0
            ? t.bodySmall.copyWith(color: k.dim)
            : t.bodyStrong.copyWith(color: k.ink),
      ),
    );
    final send = AknButton(
      label: s.checking ? 'Kontrol ediliyor' : 'Teklifleri gönder ($selected)',
      expand: true,
      size: AknButtonSize.medium,
      loading: s.submitting,
      loadingLabel: s.checking ? BayiCopy.checking : 'Gönderiliyor',
      onPressed: online && ready > 0 ? onSubmit : null,
    );
    final same = AknButton.secondary(
      label: 'Aynı fiyatı uygula',
      expand: true,
      size: AknButtonSize.medium,
      onPressed: selected == 0 ? null : () => showBulkSameSheet(context, ref),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (large) ...[
          // Büyük yazıda çubuk listeyi örtmesin: seçim ve toplu araçlar tek düğmeyle açılan sayfada;
          // ipucu metni o sayfanın alt başlığındadır (seçim yokken burada gösterilmez).
          if (selected > 0) ...[status, const SizedBox(height: 6)],
          AknButton.secondary(
            label: 'Toplu işlemler',
            icon: PhosphorIconsRegular.listChecks,
            size: AknButtonSize.small,
            expand: true,
            onPressed: () => _showDeskTools(context, ref),
          ),
          if (selected > 0) ...[const SizedBox(height: 8), send],
        ] else ...[
          Row(
            children: [
              Expanded(child: status),
              const SizedBox(width: 8),
              AknButton.ghost(
                label: 'Önerileri uygula',
                size: AknButtonSize.small,
                onPressed: suggest,
              ),
            ],
          ),
          if (selected > 0) ...[
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final half = (constraints.maxWidth - 10) / 2;
                final fits =
                    AknButton.fitsOneLine(
                      context,
                      'Aynı fiyatı uygula',
                      half,
                      bordered: true,
                    ) &&
                    AknButton.fitsOneLine(
                      context,
                      'Teklifleri gönder ($selected)',
                      half,
                    );
                if (!fits) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [same, const SizedBox(height: 8), send],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: same),
                    const SizedBox(width: 10),
                    Expanded(child: send),
                  ],
                );
              },
            ),
          ],
        ],
        if (selected > 0 && !online)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              BayiCopy.deskOffline,
              style: t.label.copyWith(color: k.dim),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

/// Büyük yazı ölçeğinde alt çubuğun toplu araçları: tümünü seç / seçimi kaldır, önerileri uygula,
/// seçilenlere aynı fiyat.
Future<void> _showDeskTools(BuildContext context, WidgetRef ref) =>
    showAppSheet<void>(
      context: context,
      title: 'Toplu işlemler',
      subtitle: BayiCopy.deskSubmitHint,
      builder: (sheet) => Consumer(
        builder: (sheet, sheetRef, _) {
          final s = sheetRef.watch(quoteDeskProvider);
          final c = sheetRef.read(quoteDeskProvider.notifier);
          final selected = s.selected.length;
          final allSelected = selected > 0 && selected == s.rows.length;
          void close() => Navigator.of(sheet).pop();
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AknButton.secondary(
                label: allSelected ? 'Seçimi kaldır' : 'Tümünü seç',
                icon: allSelected
                    ? PhosphorIconsRegular.selectionSlash
                    : PhosphorIconsRegular.selectionAll,
                expand: true,
                onPressed: () {
                  allSelected ? c.clearSelection() : c.selectAll();
                  close();
                },
              ),
              const SizedBox(height: 8),
              AknButton.secondary(
                label: 'Önerileri uygula',
                icon: PhosphorIconsRegular.magicWand,
                expand: true,
                onPressed: () {
                  final n = c.applySuggestions();
                  close();
                  AppToast.info(
                    n == 0
                        ? 'Önerisi olan satır yok.'
                        : '$n satıra önerilen fiyat yazıldı.',
                    context: context,
                  );
                },
              ),
              const SizedBox(height: 8),
              AknButton.secondary(
                label: 'Aynı fiyatı uygula',
                icon: PhosphorIconsRegular.copy,
                expand: true,
                onPressed: selected == 0
                    ? null
                    : () {
                        close();
                        unawaited(showBulkSameSheet(context, ref));
                      },
              ),
            ],
          );
        },
      ),
    );

/// Rota kurucusu: `/quote-desk?customerId=`.
Widget buildQuoteDeskPage(BuildContext context, GoRouterState state) =>
    QuoteDeskPage(
      initialCustomerId: int.tryParse(
        state.uri.queryParameters['customerId'] ?? '',
      ),
    );

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/offline/connectivity.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/bayi_grants.dart';
import '../../application/desk_controller.dart';
import '../../copy.dart';
import '../../data/desk_models.dart';
import '../widgets/bayi_widgets.dart';
import '../widgets/paged_list_body.dart';
import 'desk_row_card.dart';
import 'desk_sheets.dart';

/// Teklifler (tasarım v4 "Sade" §5 13; teklif masası).
///
/// * Bant: "Teklifler", canlı durum satırı ("6 sipariş teklif bekliyor · en yakını 41 dk") ve Filtre
///   (süresi yaklaşan, cari, ürün, sıralama; rozet açık filtre sayısı). Zil yok.
/// * Tek anahtar: `AknSegmented` [Tümü | Yeni | Revize] (sayılar metin olarak), altında "Tümünü seç".
/// * Satırlar kart (içlerinde alan var): seçim kutusu + müşteri + geri sayım; "Motorin · 10.000 L ·
///   Körfez Garaj"; birim fiyat (ipucu öneri, "Öneri" doldurur) ve teslim günü; "≈ 415.500 ₺" (yazdıkça
///   sayar) ve "Son: 41,55 ₺/L · 27 Eki" (dokununca son alımlar).
/// * Finans onayında bekleyenler notu listenin sonunda.
/// * Alt çubuk: çerçeveli "Önerilen fiyatları yaz"; bir satıra fiyat yazılınca birincil "Teklifleri
///   gönder (3) · 1.245.000 ₺" 16 dp yükselerek üstüne gelir.
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
    final expiring = s.view == DeskView.expiringSoon;
    final filterCount =
        (s.customerId == null ? 0 : 1) +
        (s.productId == null ? 0 : 1) +
        (expiring ? 1 : 0);
    final segment = expiring ? DeskView.all : s.view;

    // Durum satırı: "6 sipariş teklif bekliyor · en yakını 41 dk".
    final waiting = s.counts.of(DeskView.all) ?? 0;
    Object? status;
    if (header != null) {
      if (waiting <= 0) {
        status = 'Teklif bekleyen sipariş yok';
      } else {
        final first = '${Fmt.integer(waiting)} sipariş teklif bekliyor';
        DateTime? nearest;
        for (final d in s.deadlines.values) {
          if (!d.isAfter(DateTime.now().toUtc())) continue;
          if (nearest == null || d.isBefore(nearest)) nearest = d;
        }
        final left = nearest?.difference(DateTime.now().toUtc());
        status = [
          if (editable)
            AknStatusClause.yourMove(first)
          else
            AknStatusClause(first),
          if (left != null)
            AknStatusClause(
              'en yakını ${Fmt.countdown(left)}',
              tone: left <= const Duration(minutes: 30) ? AknTone.danger : null,
            ),
        ];
      }
    }

    return AppScaffold(
      title: 'Teklifler',
      bandIcon: PhosphorIconsRegular.invoice,
      status: status,
      refreshing: s.list.refreshing,
      actions: [
        AknFilterButton(
          count: filterCount,
          onPressed: () => showDeskFilterSheet(context),
        ),
      ],
      actionBar: editable && s.rows.isNotEmpty
          ? ActionBar(
              child: _DeskDock(
                online: online,
                onSubmit: () => unawaited(_submit()),
              ),
            )
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
          compact: true,
          title: 'Teklif verilecek sipariş yok',
          message: 'Yeni sipariş gelince bildirim alırsınız.',
          illustration: AknIllustration.orders,
        ),
        footer: (header?.financeHeld ?? 0) > 0
            ? ListFooterNote(
                '${header!.financeHeld} sipariş finans onayında; finans onaylayınca buraya düşer.',
              )
            : null,
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
            )
          else if (header?.epdkWarning != null)
            PageWell(
              tone: AknTone.warn,
              icon: PhosphorIconsRegular.shieldCheck,
              message: header!.epdkWarning!,
            ),
          if (!grants.quoteOnDesk && header != null)
            const ListFooterNote(
              'Teklifleri görüntüleyebilirsiniz; teklif verme yetkiniz yok.',
            ),
          const SizedBox(height: 8),
          AknSegmented<DeskView>(
            segments: [
              for (final v in const [
                DeskView.all,
                DeskView.awaitingQuote,
                DeskView.revision,
              ])
                FilterOption(value: v, label: v.label, count: s.counts.of(v)),
            ],
            value: segment,
            onChanged: c.setView,
          ),
          if (s.isFiltered || expiring)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (expiring)
                    InputChip(
                      label: Text(DeskView.expiringSoon.label),
                      onDeleted: () => c.setView(DeskView.all),
                      deleteButtonTooltipMessage:
                          'Süresi yaklaşan filtresini kaldır',
                    ),
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
          else
            const SizedBox(height: 4),
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

/// Listenin üstünde "Tümünü seç": satırların seçim kutularıyla aynı hizada üç durumlu kutu.
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
    void toggle() => all || selected > 0 ? c.clearSelection() : c.selectAll();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 20, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Semantics(
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
      ),
    );
  }
}

/// Alt çubuk (v4 §5 13): çerçeveli "Önerilen fiyatları yaz" (seçim varken yanında "Aynı fiyatı
/// uygula"); fiyatı yazılmış seçili satır varsa birincil "Teklifleri gönder (3) · 1.245.000 ₺" 16 dp
/// yükselerek üstte belirir. Büyük yazıda toplu araçlar tek düğmeyle açılan sayfada.
class _DeskDock extends ConsumerWidget {
  const _DeskDock({required this.online, required this.onSubmit});

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
    var total = 0.0;
    for (final r in s.rows) {
      if (!s.selected.contains(r.orderId)) continue;
      final p = s.draftOf(r.orderId).price ?? 0;
      if (p > 0) total += p * r.quantityLiters;
    }
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

    final sendLabel = s.checking
        ? 'Kontrol ediliyor'
        : 'Teklifleri gönder ($selected)${total > 0 ? ' · ${Fmt.moneyWhole(total)}' : ''}';
    final send = AknButton(
      key: const ValueKey('desk-send'),
      label: sendLabel,
      semanticLabel: 'Teklifleri gönder, $selected sipariş',
      expand: true,
      loading: s.submitting,
      loadingLabel: s.checking ? BayiCopy.checking : 'Gönderiliyor',
      onPressed: online
          ? onSubmit
          : () => AppToast.info(BayiCopy.deskOffline, context: context),
    );
    final Widget tools;
    if (large) {
      // Büyük yazıda çubuk listeyi örtmesin: toplu araçlar tek düğmeyle açılan sayfada.
      tools = AknButton.secondary(
        label: 'Toplu işlemler',
        icon: PhosphorIconsRegular.listChecks,
        size: AknButtonSize.small,
        expand: true,
        onPressed: () => _showDeskTools(context, ref),
      );
    } else {
      // Simgeli, çerçeveli ikinciller: alttaki açıklamanın başlığı gibi değil, düğme gibi
      // okunur (üstteki birincil tek dolu düğme kalır, P5).
      tools = Row(
        children: [
          Expanded(
            child: AknButton.secondary(
              label: 'Önerilen fiyatları yaz',
              icon: selected > 0 ? null : PhosphorIconsRegular.magicWand,
              size: AknButtonSize.medium,
              onPressed: suggest,
            ),
          ),
          if (selected > 0) ...[
            const SizedBox(width: 12),
            Expanded(
              child: AknButton.secondary(
                label: 'Aynı fiyatı uygula',
                size: AknButtonSize.medium,
                onPressed: () => showBulkSameSheet(context, ref),
              ),
            ),
          ],
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Bir satıra fiyat yazılınca birincil 16 dp yükselerek gelir.
        AknAnimatedSize(
          duration: AknMotion.sheet,
          curve: AknMotion.emphasizedCurve,
          alignment: Alignment.bottomCenter,
          child: ready > 0 || s.submitting
              ? FadeUp(
                  key: const ValueKey('send-on'),
                  offset: 16,
                  duration: AknMotion.sheet,
                  curve: AknMotion.emphasizedCurve,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: send,
                  ),
                )
              : const SizedBox(
                  key: ValueKey('send-off'),
                  width: double.infinity,
                ),
        ),
        tools,
        if (selected == 0 && !large)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              BayiCopy.deskSubmitHint,
              textAlign: TextAlign.center,
              style: t.label.copyWith(
                fontWeight: FontWeight.w500,
                color: k.dim,
              ),
            ),
          ),
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

/// Büyük yazı ölçeğinde alt çubuğun toplu araçları: tümünü seç / seçimi kaldır, önerilen fiyatları
/// yaz, seçilenlere aynı fiyat.
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
                label: 'Önerilen fiyatları yaz',
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

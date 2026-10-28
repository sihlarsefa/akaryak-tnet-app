import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../application/bayi_runtime.dart';
import '../../copy.dart';
import 'bayi_widgets.dart';

/// Liste tarifi (spec C.5, tasarım v3 "Akış"): ilk yüklemede kart iskeleti, aşağı çekerek yenileme,
/// sonsuz kaydırma, boş / süzgeçli boş / hata durumları. [header] liste öğelerinden önce kayar (süzgeç
/// özeti, uyarılar).
///
/// [cards] (varsayılan) her öğe sayfa zemininde süzülen beyaz bir karttır ([BayiCard]: 20 köşe, kart
/// gölgesi, dokununca 0,97 ve yay); kartlar ilk açılışta art arda yükselerek gelir, sonra kaydırdıkça
/// görünen her kart kayarak girer ([StaggerScope] + [StaggerItem]). [staggerKey] değişince (yeni
/// süzgeç) giriş yeniden oynar. [cards] false iken eski tam genişlik defter satırları: [divided] iken
/// aralarına 20 px içeriden ince çizgi. [footer] listenin sonunda, başka sayfa kalmadığında görünür
/// (öğelerin nereye gittiğini söyleyen cümle).
class PagedListBody<T> extends StatelessWidget {
  const PagedListBody({
    super.key,
    required this.list,
    required this.itemBuilder,
    required this.onRefresh,
    required this.onLoadMore,
    required this.empty,
    this.header = const [],
    this.filtered = false,
    this.onClearFilters,
    this.skeletonLines = 3,
    this.padding = const EdgeInsets.only(top: 4, bottom: 24),
    this.controller,
    this.divided = true,
    this.footer,
    this.cards = true,
    this.pressableCards = true,
    this.staggerKey,
  });

  final PagedList<T> list;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;

  /// Süzgeçsiz boş liste (izinli eylemiyle).
  final Widget empty;
  final List<Widget> header;
  final bool filtered;
  final VoidCallback? onClearFilters;
  final int skeletonLines;
  final EdgeInsetsGeometry padding;
  final ScrollController? controller;

  /// Satırlar arasına defter çizgisi.
  final bool divided;

  /// Liste sonu (tüm sayfalar yüklendiğinde).
  final Widget? footer;

  /// Öğeler beyaz kartlarda (tasarım v3); false: tam genişlik defter satırları.
  final bool cards;

  /// Kartlar dokununca küçülür (satırın tamamı bir eylemse); satırında alan / onay kutusu olan
  /// listelerde (teklif masası) false.
  final bool pressableCards;

  /// Değişince kartların giriş dizisi yeniden oynar (ör. süzgeç, sekme).
  final Object? staggerKey;

  /// Kartlar arası boşluk 12 (her kartın üstü ve altı 6), sayfa kenarı 20.
  static const EdgeInsets cardMargin = EdgeInsets.fromLTRB(
    AknSpace.page,
    6,
    AknSpace.page,
    6,
  );

  @override
  Widget build(BuildContext context) {
    final items = list.items;
    if (list.loading && items.isEmpty) {
      return ListView(
        controller: controller,
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        children: [
          ...header,
          if (cards)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < 5; i++)
                    BayiCard(
                      margin: cardMargin,
                      pressable: false,
                      child: Shimmer(
                        semanticLabel: i == 0 ? 'Yükleniyor' : null,
                        child: SkeletonCard(
                          lines: skeletonLines.clamp(2, 3),
                          margin: kCardRowPadding,
                        ),
                      ),
                    ),
                ],
              ),
            )
          else
            SkeletonList(
              itemCount: 5,
              lines: skeletonLines.clamp(2, 3),
              shrinkWrap: true,
            ),
        ],
      );
    }
    if (items.isEmpty) {
      final f = list.error;
      final Widget body = f != null
          ? FailureView(failure: f, onRetry: onRefresh)
          : filtered
          ? EmptyState(
              title: BayiCopy.filteredEmptyTitle,
              message: BayiCopy.filteredEmptyMessage,
              illustration: AknIllustration.search,
              actionLabel: onClearFilters == null
                  ? null
                  : BayiCopy.clearFilters,
              onAction: onClearFilters,
            )
          : empty;
      return PullToRefresh(
        onRefresh: onRefresh,
        child: ListView(
          controller: controller,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          children: [
            ...header,
            // Boş / hata durumu hafifçe yükselip büyüyerek gelir.
            FadeUp(
              key: ValueKey<Object?>(('empty', staggerKey, f != null)),
              offset: 18,
              scale: 0.96,
              duration: AknMotion.slow,
              child: body,
            ),
          ],
        ),
      );
    }
    final count = header.length + items.length + 1;
    return PullToRefresh(
      onRefresh: onRefresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.axis == Axis.vertical &&
              n.metrics.extentAfter < 480 &&
              list.hasMore &&
              !list.loadingMore &&
              list.moreError == null) {
            onLoadMore();
          }
          return false;
        },
        child: StaggerScope(
          key: ValueKey<Object?>(staggerKey),
          child: ListView.builder(
            controller: controller,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: padding,
            itemCount: count,
            itemBuilder: (context, i) {
              if (i < header.length) return header[i];
              final index = i - header.length;
              if (index >= items.length) {
                final end = footer;
                if (end != null &&
                    !list.hasMore &&
                    !list.loadingMore &&
                    list.moreError == null) {
                  return end;
                }
                return LoadMoreFooter(
                  loading: list.loadingMore,
                  error: list.moreError,
                  onRetry: onLoadMore,
                );
              }
              final row = itemBuilder(context, items[index], index);
              final Widget item;
              if (cards) {
                item = BayiCard(
                  margin: index == 0
                      ? cardMargin.copyWith(top: 10)
                      : cardMargin,
                  pressable: pressableCards,
                  child: row,
                );
              } else {
                item = divided && index > 0
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [const AknLedgerDivider(), row],
                      )
                    : row;
              }
              return StaggerItem(index: index, child: item);
            },
          ),
        ),
      ),
    );
  }
}

/// Ayrıntı tarifi: ilk yüklemede iskelet, hata / kayıt yok durumu, sonra içerik. Tasarım v3: iskelet
/// içeriğe (ya da hataya) solup büyüyerek geçer ([FadeThroughSwitcher]); veri geldikten sonraki
/// tazelemeler içeriği yerinde günceller.
class LoadableBody<T> extends StatelessWidget {
  const LoadableBody({
    super.key,
    required this.state,
    required this.builder,
    required this.onRetry,
    this.skeleton,
  });

  final Loadable<T> state;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback onRetry;
  final Widget? skeleton;

  @override
  Widget build(BuildContext context) {
    final data = state.data;
    final f = state.error;
    final Widget child;
    if (data != null) {
      child = KeyedSubtree(
        key: const ValueKey('data'),
        child: builder(context, data),
      );
    } else if (f != null) {
      child = ListView(
        key: const ValueKey('error'),
        padding: const EdgeInsets.only(top: 24),
        children: [
          FadeUp(
            offset: 18,
            scale: 0.96,
            duration: AknMotion.slow,
            child: FailureView(failure: f, onRetry: onRetry),
          ),
        ],
      );
    } else {
      child = KeyedSubtree(
        key: const ValueKey('loading'),
        child: skeleton ?? const SkeletonList(itemCount: 4, lines: 3),
      );
    }
    return FadeThroughSwitcher(child: child);
  }
}

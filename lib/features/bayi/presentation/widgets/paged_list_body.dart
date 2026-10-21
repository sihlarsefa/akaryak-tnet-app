import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../application/bayi_runtime.dart';
import '../../copy.dart';
import 'bayi_widgets.dart';

/// Liste tarifi (spec C.5, tasarım v2 §7.7): ilk yüklemede defter satırı iskeleti, aşağı çekerek
/// yenileme, sonsuz kaydırma, boş / süzgeçli boş / hata durumları. [header] liste öğelerinden önce kayar
/// (süzgeç özeti, uyarılar). Öğeler tam genişlik defter satırlarıdır: [divided] iken aralarına 20 px
/// içeriden ince çizgi çizilir (ilkinin üstüne, sonuncunun altına değil). [footer] listenin sonunda,
/// başka sayfa kalmadığında görünür (öğelerin nereye gittiğini söyleyen cümle).
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
          children: [...header, body],
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
              return StaggerItem(
                index: index,
                child: divided && index > 0
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [const AknLedgerDivider(), row],
                      )
                    : row,
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Ayrıntı tarifi: ilk yüklemede iskelet, hata / kayıt yok durumu, sonra içerik.
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
    if (data != null) return builder(context, data);
    final f = state.error;
    if (f != null) {
      return ListView(
        padding: const EdgeInsets.only(top: 24),
        children: [FailureView(failure: f, onRetry: onRetry)],
      );
    }
    return skeleton ?? const SkeletonList(itemCount: 4, lines: 3);
  }
}

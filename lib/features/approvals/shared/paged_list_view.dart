import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/network/app_failure.dart';
import '../../../core/ui/ui.dart';
import 'failure_view.dart';
import 'paged_list.dart';

/// Spec C.5 liste tarifi: başlık parçaları (arama, çipler) içerikle birlikte kayar; ilk yüklemede
/// iskelet, aşağı çekip yenileme (» döner), sonsuz kaydırma alt satırı, boş / hata durumları.
///
/// [ledger] (tasarım v2 §4.4 "beyaz defter"): öğeler tam genişlik defter satırlarıdır; yatay boşluk ve
/// öğe aralığı yerine satırlar arasında 20 px içeriden ince çizgi, iskelet de defter satırı biçiminde.
/// Kapalıyken eski düzen (kenar boşluklu, aralıklı öğeler) sürer.
class A5PagedListView<T> extends StatefulWidget {
  const A5PagedListView({
    super.key,
    required this.state,
    required this.itemBuilder,
    required this.onRefresh,
    required this.onLoadMore,
    required this.empty,
    this.header = const [],
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 24),
    this.itemSpacing = 10,
    this.skeletonLines = 3,
    this.staggerKey,
    this.footer,
    this.ledger = false,
  });

  final PagedState<T> state;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;

  /// Liste boşken (filtreli ya da filtresiz).
  final Widget empty;

  /// Listenin üstündeki parçalar (kenar boşluğunu kendileri verir).
  final List<Widget> header;
  final EdgeInsetsGeometry padding;
  final double itemSpacing;
  final int skeletonLines;

  /// Değişince giriş animasyonu yeni veri kümesi için yeniden oynar (ör. filtre).
  final Object? staggerKey;

  /// Listenin sonuna eklenen parça (ör. açıklama).
  final Widget? footer;

  /// Tam genişlik defter satırları, aralarında ince çizgi.
  final bool ledger;

  @override
  State<A5PagedListView<T>> createState() => _A5PagedListViewState<T>();
}

class _A5PagedListViewState<T> extends State<A5PagedListView<T>> {
  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    if (n.metrics.extentAfter < 480 && widget.state.hasMore) {
      final s = widget.state;
      if (!s.loadingMore && s.moreError == null) widget.onLoadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final children = <Widget>[...widget.header];

    if (s.isFirstLoad && widget.ledger) {
      children.add(
        SkeletonList(
          itemCount: 5,
          lines: widget.skeletonLines.clamp(2, 3),
          padding: const EdgeInsets.only(top: 4),
          shrinkWrap: true,
        ),
      );
    } else if (s.isFirstLoad) {
      children.add(
        Padding(
          padding: widget.padding,
          child: Shimmer(
            child: Column(
              children: [
                for (var i = 0; i < 5; i++)
                  SkeletonCard(
                    lines: widget.skeletonLines,
                    margin: const EdgeInsets.only(bottom: 12),
                  ),
              ],
            ),
          ),
        ),
      );
    } else if (s.error != null && s.items.isEmpty) {
      children.add(
        A5FailureView(
          failure: s.error!,
          onRetry: () => unawaited(widget.onRefresh()),
        ),
      );
    } else if (s.isEmpty) {
      children.add(widget.empty);
    } else {
      if (s.error != null) {
        children.add(
          Padding(
            padding: EdgeInsets.fromLTRB(
              widget.ledger ? 20 : 16,
              8,
              widget.ledger ? 20 : 16,
              0,
            ),
            child: AknBanner(
              tone: AknTone.warn,
              message: failureText(s.error!),
              actionLabel: 'Tekrar dene',
              onAction: () => unawaited(widget.onRefresh()),
            ),
          ),
        );
      }
      final resolved = widget.padding.resolve(Directionality.of(context));
      if (widget.ledger) {
        children.add(
          AknLedger(
            children: [
              for (var i = 0; i < s.items.length; i++)
                widget.itemBuilder(context, s.items[i], i),
            ],
          ),
        );
      } else {
        children.add(
          StaggerScope(
            key: ValueKey(widget.staggerKey),
            child: Padding(
              padding: resolved.copyWith(bottom: 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < s.items.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: i == s.items.length - 1
                            ? 0
                            : widget.itemSpacing,
                      ),
                      child: StaggerItem(
                        index: i,
                        child: widget.itemBuilder(context, s.items[i], i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }
      children.add(
        _Footer(
          loading: s.loadingMore,
          error: s.moreError,
          hasMore: s.hasMore,
          onRetry: widget.onLoadMore,
          bottomPadding: resolved.bottom,
        ),
      );
      if (widget.footer != null) children.add(widget.footer!);
    }

    return PullToRefresh(
      onRefresh: widget.onRefresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewPaddingOf(context).bottom,
          ),
          children: children,
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.loading,
    required this.error,
    required this.hasMore,
    required this.onRetry,
    required this.bottomPadding,
  });

  final bool loading;
  final AppFailure? error;
  final bool hasMore;
  final VoidCallback onRetry;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (loading) {
      child = Semantics(
        label: 'Daha fazla yükleniyor',
        liveRegion: true,
        child: const SizedBox(
          height: 48,
          child: Center(child: ChevronSpinner(size: 18, semanticLabel: null)),
        ),
      );
    } else if (error != null) {
      child = Column(
        children: [
          Text(
            'Daha fazlası yüklenemedi.',
            style: context.aknText.bodySmall,
            textAlign: TextAlign.center,
          ),
          AknButton.ghost(
            label: 'Tekrar dene',
            semanticLabel: 'Daha fazlası yüklenemedi, tekrar dene',
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
          ),
        ],
      );
    } else if (hasMore) {
      child = Center(
        child: AknButton.ghost(label: 'Daha fazla göster', onPressed: onRetry),
      );
    } else {
      child = const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding),
      child: child,
    );
  }
}

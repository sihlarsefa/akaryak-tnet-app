import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../application/bayi_runtime.dart';
import '../../copy.dart';
import 'bayi_widgets.dart';

/// Liste tarifi (spec C.5, tasarım v3 "Akış"): ilk yüklemede kart iskeleti, aşağı çekerek yenileme,
/// sonsuz kaydırma, boş / süzgeçli boş / hata durumları. [header] liste öğelerinden önce kayar (süzgeç
/// özeti, uyarılar).
///
/// [ledger] (v4 "Sade" P6: bir grup = bir kart): öğeler tek bir defter kartının satırlarıdır — kart
/// 20 köşe, yalnızca ince çizgi (koyu temada 1 px çizgi), satırlar arasında 20 px içeriden ince çizgi.
/// Kart tembel kurulur: her satır kartın bir dilimini çizer (ilk satır üst köşeleri, son satır alt
/// köşeleri). Satırlar ilk açılışta bir kez akarak gelir (8 dp, 40 ms arayla; [AknRowPour]).
///
/// [cards] (ledger kapalıyken varsayılan) her öğe sayfa zemininde süzülen beyaz bir karttır
/// ([BayiCard]: 20 köşe, kart gölgesi, dokununca 0,97 ve yay) — içinde alan olan satırlar için (teklif
/// masası); kartlar art arda yükselerek gelir ([StaggerScope] + [StaggerItem]). [staggerKey] değişince
/// (yeni süzgeç) giriş yeniden oynar. [cards] false iken eski tam genişlik defter satırları: [divided]
/// iken aralarına 20 px içeriden ince çizgi. [footer] listenin sonunda, başka sayfa kalmadığında
/// görünür (öğelerin nereye gittiğini söyleyen cümle).
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
    this.ledger = false,
    this.query,
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

  /// Öğeler tek bir defter kartında (v4); [cards] yok sayılır.
  final bool ledger;

  /// Aramadaki metin: süzgeçli boş durum "'…' için sonuç yok" der (v4 §3.6).
  final String? query;

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
          if (ledger)
            _LedgerSkeleton(lines: skeletonLines.clamp(2, 3))
          else if (cards)
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
              compact: ledger,
              title: (query ?? '').trim().isEmpty
                  ? BayiCopy.filteredEmptyTitle
                  : "'${query!.trim()}' için sonuç yok",
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
              if (ledger) {
                // İlk ekranın satırları bir kez akar; kaydırınca gelenler yerinde durur.
                return LedgerSlice(
                  first: index == 0,
                  last: index == items.length - 1,
                  child: index < 8 ? AknRowPour(index: index, child: row) : row,
                );
              }
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

/// Tembel kurulan defter kartının bir dilimi (v4 P6): sayfa kenarında (20) beyaz yüzey; [first]
/// kartın üst köşelerini ve 4 dp iç boşluğunu, [last] alt köşelerini taşır; aradaki dilimler düzdür
/// ve üstlerinde 20 px içeriden ince çizgi vardır. Kartın çizgisi açık temada dışta 1 px ince çizgi
/// (`AknShadows.hairline` gibi), koyu temada içte 1 px `line`; dilimlerin birleştiği yerde çizgi
/// yoktur. İçerik kartta olduğunu bilir ([AknCardScope]).
class LedgerSlice extends StatelessWidget {
  const LedgerSlice({
    super.key,
    required this.first,
    required this.last,
    required this.child,
  });

  final bool first;
  final bool last;
  final Widget child;

  static const double _radius = 20;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    const r = Radius.circular(_radius);
    final radius = BorderRadius.vertical(
      top: first ? r : Radius.zero,
      bottom: last ? r : Radius.zero,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AknSpace.page,
        first ? 4 : 0,
        AknSpace.page,
        last ? 4 : 0,
      ),
      child: CustomPaint(
        painter: _SlicePainter(
          fill: c.surface,
          line: c.line,
          dark: c.isDark,
          first: first,
          last: last,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: AknCardScope(
            child: Padding(
              padding: EdgeInsets.only(
                top: first ? 4 : 0,
                bottom: last ? 4 : 0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [if (!first) const AknLedgerDivider(), child],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SlicePainter extends CustomPainter {
  const _SlicePainter({
    required this.fill,
    required this.line,
    required this.dark,
    required this.first,
    required this.last,
  });

  final Color fill;
  final Color line;
  final bool dark;
  final bool first;
  final bool last;

  @override
  void paint(Canvas canvas, Size size) {
    const r = Radius.circular(LedgerSlice._radius);
    final rr = RRect.fromRectAndCorners(
      Offset.zero & size,
      topLeft: first ? r : Radius.zero,
      topRight: first ? r : Radius.zero,
      bottomLeft: last ? r : Radius.zero,
      bottomRight: last ? r : Radius.zero,
    );
    canvas.drawRRect(rr, Paint()..color = fill);
    // Açık tema: kartın dışında 1 px halka; koyu tema: içte 1 px çizgi. Birleşim yerleri kırpılır.
    final outline = dark ? rr.deflate(0.5) : rr.inflate(0.5);
    final top = first ? -2.0 : (dark ? 1.0 : 0.0);
    final bottom = last
        ? size.height + 2
        : (dark ? size.height - 1 : size.height);
    canvas
      ..save()
      ..clipRect(Rect.fromLTRB(-2, top, size.width + 2, bottom))
      ..drawRRect(
        outline,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      )
      ..restore();
    if (dark) {
      // Koyu temada kırpılan birleşim piksellerini yan çizgilerde kapat.
      final p = Paint()..color = line;
      if (!first) {
        canvas
          ..drawRect(const Rect.fromLTWH(0, 0, 1, 1), p)
          ..drawRect(Rect.fromLTWH(size.width - 1, 0, 1, 1), p);
      }
      if (!last) {
        canvas
          ..drawRect(Rect.fromLTWH(0, size.height - 1, 1, 1), p)
          ..drawRect(Rect.fromLTWH(size.width - 1, size.height - 1, 1, 1), p);
      }
    }
  }

  @override
  bool shouldRepaint(_SlicePainter old) =>
      old.fill != fill ||
      old.line != line ||
      old.dark != dark ||
      old.first != first ||
      old.last != last;
}

/// Defter kartının iskeleti: tek kartta parıltılı satırlar.
class _LedgerSkeleton extends StatelessWidget {
  const _LedgerSkeleton({required this.lines});

  final int lines;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < 6; i++)
        LedgerSlice(
          first: i == 0,
          last: i == 5,
          child: Shimmer(
            semanticLabel: i == 0 ? 'Yükleniyor' : null,
            child: SkeletonCard(lines: lines, margin: kCardRowPadding),
          ),
        ),
    ],
  );
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

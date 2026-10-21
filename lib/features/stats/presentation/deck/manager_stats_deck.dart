import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/network/app_failure.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/storage/prefs_store.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/stats_providers.dart';
import '../../application/stats_scope.dart';
import '../../copy.dart';
import '../../data/stats_models.dart';
import '../../data/stats_repository.dart';
import '../widgets/stats_palette.dart';
import 'deck_cards.dart';

/// Ana sayfadaki yönetici istatistik destesi (spec R1 §3; F2GO `KazancKartDestesi` uyarlaması,
/// turuncu / beyaz). Kendi kendini yönetir: kapsamı olmayan kullanıcıda, sunucu reddettiğinde (403) ya
/// da uç henüz yokken (404) hiçbir şey çizmez (`SizedBox.shrink`). Yüklenirken iskelet kartlar,
/// yüklenemezse kısa bir hata kartı gösterir; çevrimdışıyken son kayıt "Son güncelleme" ile görünür.
///
/// Ana sayfalar yalnızca `const ManagerStatsDeck()` ekler. Varsayılan dış boşluk `16, 16, 16, 0`'dır;
/// sarmalayan bir dolgu varsa `padding: EdgeInsets.zero` verin.
class ManagerStatsDeck extends ConsumerStatefulWidget {
  const ManagerStatsDeck({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 0),
  });

  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<ManagerStatsDeck> createState() => _ManagerStatsDeckState();
}

class _ManagerStatsDeckState extends ConsumerState<ManagerStatsDeck>
    with WidgetsBindingObserver {
  bool _tickerEnabled = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Sekmeye geri dönülünce (FadeThroughIndexedStack sekmeyi susturur) eskiyse tazele.
    final enabled = TickerMode.valuesOf(context).enabled;
    if (enabled && !_tickerEnabled) _refreshIfStale();
    _tickerEnabled = enabled;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshIfStale();
  }

  void _refreshIfStale() {
    final scope = ref.read(statsScopeProvider);
    if (scope == StatsScope.none) return;
    if (scope.isBayi) {
      unawaited(
        ref
            .read(bayiStatsProvider(StatsPeriod.month).notifier)
            .refreshIfStale(),
      );
    } else {
      unawaited(
        ref
            .read(customerStatsProvider(StatsPeriod.month).notifier)
            .refreshIfStale(),
      );
    }
  }

  Future<void> _refresh() => refreshManagerStats(ref);

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(statsScopeProvider);
    if (scope == StatsScope.none) return const SizedBox.shrink();
    final uid = ref.watch(currentUserIdProvider);

    Object? data;
    AppFailure? error;
    bool loading;
    DateTime? updatedAt;
    bool fromCache;
    List<DeckCardSpec> cards = const [];
    if (scope.isBayi) {
      final s = ref.watch(bayiStatsProvider(StatsPeriod.month));
      final d = s.data;
      (data, error, loading, updatedAt, fromCache) = (
        d,
        s.error,
        s.loading,
        s.updatedAt,
        s.fromCache,
      );
      if (d != null) {
        final own = d.isOwn || scope == StatsScope.own;
        StatsFieldSummary? summary;
        if (own && !_hasSelfRow(d, uid)) {
          summary = ref.watch(statsFieldSummaryProvider).valueOrNull;
        }
        cards = bayiDeckCards(
          context,
          d,
          own: own,
          userId: uid,
          fieldSummary: summary,
        );
      }
    } else {
      final s = ref.watch(customerStatsProvider(StatsPeriod.month));
      final d = s.data;
      (data, error, loading, updatedAt, fromCache) = (
        d,
        s.error,
        s.loading,
        s.updatedAt,
        s.fromCache,
      );
      if (d != null) cards = customerDeckCards(context, d);
    }

    if (data == null) {
      if (statsDenied(error)) return const SizedBox.shrink();
      if (error != null && !loading) {
        if (error is UnknownFailure && error.cancelled) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: widget.padding,
          child: _DeckError(failure: error, onRetry: _refresh),
        );
      }
      return Padding(padding: widget.padding, child: const _DeckSkeleton());
    }
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: widget.padding,
      child: SwipeDeck(
        cards: cards,
        onRefresh: _refresh,
        staleNote: fromCache || error != null ? updatedAt : null,
      ),
    );
  }

  static bool _hasSelfRow(BayiStats d, String? uid) =>
      d.team.length == 1 || d.team.any((m) => uid != null && m.userId == uid);
}

// ============================================================== deste

/// Kart içeriğinin en büyük yazı ölçeği (kart yüksekliği de bu ölçeğe kadar büyür).
const _maxTextScale = 1.6;

/// Kart yüksekliği: 256, yazı ölçeğiyle 1,6×'e kadar büyür (F2GO).
double deckCardHeight(BuildContext context) {
  final scale = MediaQuery.textScalerOf(
    context,
  ).scale(1).clamp(1.0, _maxTextScale);
  return 256 + 200 * (scale - 1);
}

/// Kaydırılan kart destesi: en üstteki kart sürüklenir (kayma + hafif dönüş), arkadaki iki kart .95 / .90
/// ölçekte durur ve üstteki sürüklendikçe öne gelir. Genişliğin %28'ini ya da 700 px/s'yi geçen atış kartı
/// uçurur (260 ms easeIn) ve kart arkaya geçer; aksi hâlde yaylanarak yerine döner (600 ms elasticOut).
/// İlk gösterimde bir kez hafifçe sallanır (tercih anahtarı [StatsKeys.deckHint]). Her kart değişiminde
/// hafif titreşim. Hareket azaltmada sallanma yok, uçuş yerine kısa bir geçiş.
class SwipeDeck extends ConsumerStatefulWidget {
  const SwipeDeck({
    super.key,
    required this.cards,
    required this.onRefresh,
    this.staleNote,
  });

  final List<DeckCardSpec> cards;
  final Future<void> Function() onRefresh;

  /// Önbellekten / tazelenemeyen veride son güncelleme anı.
  final DateTime? staleNote;

  @override
  ConsumerState<SwipeDeck> createState() => _SwipeDeckState();
}

class _SwipeDeckState extends ConsumerState<SwipeDeck>
    with SingleTickerProviderStateMixin {
  /// Kartların sabit sırası (noktalar).
  List<String> _ids = const [];

  /// Destedeki sıra: ilk eleman en üstteki kart; her zaman [_ids]'in döndürülmüşü.
  List<String> _order = const [];

  double _dx = 0;
  double _width = 360;
  late final AnimationController _anim = AnimationController(vsync: this);
  Animation<double>? _dxAnim;
  bool _flying = false;
  Timer? _hintTimer;
  bool _hintTried = false;

  static const _flingThreshold = 0.28;
  static const _flingVelocity = 700.0;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      final a = _dxAnim;
      if (a != null && mounted) setState(() => _dx = a.value);
    });
    _sync(widget.cards);
  }

  @override
  void didUpdateWidget(SwipeDeck old) {
    super.didUpdateWidget(old);
    _sync(widget.cards);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hintTried) {
      _hintTried = true;
      _scheduleHint();
    }
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _anim.dispose();
    super.dispose();
  }

  /// Kart listesi değişince sıra yeni listenin döndürülmüşü olur; üstteki kart korunur.
  void _sync(List<DeckCardSpec> cards) {
    final ids = [for (final c in cards) c.id];
    if (listEquals(ids, _ids)) return;
    final top = _order.isEmpty ? null : _order.first;
    final i = top == null ? -1 : ids.indexOf(top);
    _ids = ids;
    _order = i < 0 ? ids : [...ids.skip(i), ...ids.take(i)];
  }

  PrefsStore? _prefs() {
    try {
      return ref.read(prefsStoreProvider);
    } catch (_) {
      return null;
    }
  }

  /// İlk kez görülünce üstteki kart hafifçe sallanır: "kaydırılabilir" olduğu anlaşılsın.
  void _scheduleHint() {
    if (_ids.length < 2 || AknMotion.reduced(context)) return;
    final prefs = _prefs();
    if (prefs == null || prefs.getBool(StatsKeys.deckHint)) return;
    unawaited(prefs.setBool(StatsKeys.deckHint, true));
    _hintTimer = Timer(const Duration(milliseconds: 700), _nudge);
  }

  void _nudge() {
    if (!mounted || _flying || _dx != 0) return;
    _dxAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: -56,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: -56,
          end: 0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 65,
      ),
    ]).animate(_anim);
    _anim.duration = const Duration(milliseconds: 1300);
    unawaited(_anim.forward(from: 0));
  }

  // ---------------------------------------------------------------- kaydırma

  void _onDragUpdate(DragUpdateDetails d) {
    if (_flying || _ids.length < 2) return;
    _anim.stop();
    _dxAnim = null;
    setState(() => _dx += d.delta.dx);
  }

  void _onDragEnd(DragEndDetails d) {
    if (_flying || _ids.length < 2) return;
    final v = d.velocity.pixelsPerSecond.dx;
    if (_dx.abs() > _width * _flingThreshold || v.abs() > _flingVelocity) {
      final dir = _dx.abs() > 4 ? _dx.sign : v.sign;
      unawaited(_fly(dir == 0 ? -1 : dir));
    } else {
      _settle();
    }
  }

  /// Yaylanarak ortaya dönüş.
  void _settle() {
    if (_flying || _dx == 0) return;
    if (AknMotion.reduced(context)) {
      setState(() => _dx = 0);
      return;
    }
    _dxAnim = Tween<double>(
      begin: _dx,
      end: 0,
    ).chain(CurveTween(curve: Curves.elasticOut)).animate(_anim);
    _anim.duration = const Duration(milliseconds: 600);
    unawaited(_anim.forward(from: 0));
  }

  /// Üstteki kartı [dir] yönüne uçurur, arkaya alır.
  Future<void> _fly(double dir) async {
    if (_flying || _ids.length < 2) return;
    if (AknMotion.reduced(context)) {
      _rotate(1);
      return;
    }
    _flying = true;
    _dxAnim = Tween<double>(
      begin: _dx,
      end: dir * _width * 1.4,
    ).chain(CurveTween(curve: Curves.easeIn)).animate(_anim);
    _anim.duration = const Duration(milliseconds: 260);
    try {
      await _anim.forward(from: 0).orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted) return;
    _rotate(1);
  }

  /// Sırayı döndürür: 1 = sonraki kart üste, -1 = önceki kart üste.
  void _rotate(int step) {
    if (_order.length < 2) return;
    AknHaptics.selection();
    setState(() {
      _order = step > 0
          ? [..._order.skip(1), _order.first]
          : [_order.last, ..._order.take(_order.length - 1)];
      _dx = 0;
      _dxAnim = null;
      _flying = false;
    });
  }

  void _next() => unawaited(_fly(-1));

  /// Noktaya dokununca o karta kadar kartlar sırayla uçar (hareket azaltmada doğrudan).
  Future<void> _goTo(String id) async {
    if (_flying || _order.isEmpty || _order.first == id) return;
    if (AknMotion.reduced(context)) {
      final i = _ids.indexOf(id);
      if (i < 0) return;
      AknHaptics.selection();
      setState(() {
        _order = [..._ids.skip(i), ..._ids.take(i)];
        _dx = 0;
      });
      return;
    }
    var guard = 0;
    while (mounted && _order.first != id && guard++ < _ids.length) {
      await _fly(-1);
      // Bir sonraki uçuştan önce kartın yerine oturduğu kare.
      await SchedulerBinding.instance.endOfFrame;
    }
  }

  // ---------------------------------------------------------------- görünüm

  @override
  Widget build(BuildContext context) {
    final byId = {for (final c in widget.cards) c.id: c};
    final height = deckCardHeight(context);
    final reduced = AknMotion.reduced(context);
    final topId = _order.first;
    final top = byId[topId]!;
    final index = _ids.indexOf(topId);
    final n = _ids.length;

    Widget stack = LayoutBuilder(
      builder: (context, cons) {
        _width = cons.maxWidth.isFinite ? cons.maxWidth : 360;
        final progress = (_dx.abs() / (_width * _flingThreshold)).clamp(
          0.0,
          1.0,
        );
        final visible = _order.take(3).toList();
        return SizedBox(
          height: height + 26,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var depth = visible.length - 1; depth >= 0; depth--)
                _layer(byId[visible[depth]]!, depth, progress, height),
            ],
          ),
        );
      },
    );
    // Kart yüksekliği yazıyla en fazla 1,6× büyür; içerik de bu ölçekte kalır ki 2,0× yazıda taşmasın
    // (aynı bilgiler tam ölçekle /stats sayfasında).
    stack = MediaQuery.withClampedTextScaling(
      maxScaleFactor: _maxTextScale,
      child: stack,
    );
    if (reduced) {
      // Hareket azaltma: uçuş yerine kısa geçiş.
      stack = AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(key: ValueKey(topId), child: stack),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          label: StatsCopy.deckCardSemantics(index + 1, n, top.title),
          customSemanticsActions: n < 2
              ? null
              : {
                  const CustomSemanticsAction(label: StatsCopy.deckNext): () =>
                      _rotate(1),
                  const CustomSemanticsAction(
                    label: StatsCopy.deckPrevious,
                  ): () =>
                      _rotate(-1),
                },
          child: stack,
        ),
        const SizedBox(height: 4),
        if (n > 1) _navRow(index, n),
        SizedBox(height: n > 1 ? 4 : 8),
        const _DetailsLink(),
        if (widget.staleNote != null) _StaleNote(at: widget.staleNote!),
      ],
    );
  }

  Widget _layer(DeckCardSpec card, int depth, double progress, double height) {
    final isTop = depth == 0;
    // Arkadaki kartlar üstteki sürüklendikçe bir kademe öne gelir.
    final d = isTop ? 0.0 : depth - progress;
    final scale = 1 - 0.05 * d;
    final down = 13.0 * d;
    final opacity = (1 - 0.25 * (d - 1).clamp(0.0, 1.0)).clamp(0.0, 1.0);
    final dx = isTop ? _dx : 0.0;
    final angle = isTop ? _dx / _width * 0.30 : 0.0;
    // Yapı her derinlikte aynıdır: kart sıra değiştirirken öğesi korunur (sayaç yeniden saymaz).
    return Positioned(
      key: ValueKey(card.id),
      left: 0,
      right: 0,
      top: 0,
      child: Opacity(
        opacity: opacity,
        child: Transform.translate(
          offset: Offset(0, down),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.bottomCenter,
            child: IgnorePointer(
              ignoring: !isTop,
              child: ExcludeSemantics(
                excluding: !isTop,
                child: GestureDetector(
                  onHorizontalDragUpdate: isTop ? _onDragUpdate : null,
                  onHorizontalDragEnd: isTop ? _onDragEnd : null,
                  onHorizontalDragCancel: isTop ? _settle : null,
                  child: Transform.translate(
                    offset: Offset(dx, dx.abs() * 0.05),
                    child: Transform.rotate(
                      angle: angle,
                      alignment: Alignment.bottomCenter,
                      child: DeckCardView(
                        card: card,
                        height: height,
                        raised: isTop,
                        onRefresh: widget.onRefresh,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _navRow(int active, int n) {
    final c = context.akn;
    final t = context.aknText;
    return Row(
      children: [
        const Spacer(),
        // Noktalar: konumu "n / N" düğmesi ve deste duyurur; dokunulan karta gider.
        ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < n; i++)
                GestureDetector(
                  key: ValueKey('deck-dot-$i'),
                  behavior: HitTestBehavior.opaque,
                  onTap: () => unawaited(_goTo(_ids[i])),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 12,
                    ),
                    child: AnimatedContainer(
                      duration: AknMotion.of(
                        context,
                        const Duration(milliseconds: 250),
                      ),
                      curve: AknMotion.standard,
                      width: i == active ? 20 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == active ? c.logo : c.lineStrong,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Semantics(
              button: true,
              label: '${StatsCopy.deckNext}, ${active + 1} / $n',
              excludeSemantics: true,
              onTap: _next,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  key: const ValueKey('deck-next'),
                  onTap: _next,
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AknSpace.minTap,
                      minWidth: AknSpace.minTap,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Dar ekranda büyük yazıda küçülür (noktalarla çakışmaz).
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                StatsCopy.deckPosition(active + 1, n),
                                maxLines: 1,
                                style: t.caption.copyWith(
                                  color: c.dim,
                                  fontWeight: FontWeight.w600,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.swipe_rounded, size: 16, color: c.dim),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Destenin altındaki "Detaylı istatistikler" satırı → `/stats`.
class _DetailsLink extends StatelessWidget {
  const _DetailsLink();

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Semantics(
      button: true,
      label: StatsCopy.deckDetails,
      excludeSemantics: true,
      onTap: () => context.push(AppRoutes.stats),
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('deck-details'),
          onTap: () {
            AknHaptics.selection();
            context.push(AppRoutes.stats);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AknSpace.minTap),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.bar_chart_rounded, size: 20, color: c.brand),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      StatsCopy.deckDetails,
                      style: t.label.copyWith(
                        color: c.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios_rounded, size: 15, color: c.dim),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Son güncelleme 14:20" (çevrimdışı ya da tazelenemedi).
class _StaleNote extends StatelessWidget {
  const _StaleNote({required this.at});

  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(Icons.history_rounded, size: 15, color: c.dim),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Son güncelleme ${Fmt.time(at)} · ${Fmt.relative(at)}',
              style: t.caption.copyWith(color: c.dim),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================== kart parçaları

/// Kart kabuğu (F2GO `_KartKabuk`): yüzey rengi, 22 köşe, üstte kart renginin %7'si (yarı yükseklikte
/// yüzeye erir), renge çalan ince çizgi; üstteki kartta daha belirgin gölge.
class DeckCardShell extends StatelessWidget {
  const DeckCardShell({
    super.key,
    required this.tint,
    required this.raised,
    required this.child,
    this.height,
    this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 14),
  });

  final Color tint;
  final bool raised;
  final Widget child;
  final double? height;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final surface = c.surface;
    final a = c.shadow.a;
    return Container(
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.alphaBlend(tint.withValues(alpha: 0.07), surface),
            surface,
          ],
          stops: const [0, 0.5],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Color.alphaBlend(tint.withValues(alpha: 0.10), c.line),
        ),
        boxShadow: [
          BoxShadow(
            color: c.shadow.withValues(
              alpha: (a * (raised ? 1.6 : 0.5)).clamp(0.0, 1.0),
            ),
            blurRadius: raised ? 20 : 8,
            offset: Offset(0, raised ? 8 : 3),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Kart başlığı: 38×38 renkli ikon kutusu, başlık (w800 15,5), alt başlık (12) ve isteğe bağlı menü.
class DeckCardHeader extends StatelessWidget {
  const DeckCardHeader({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyStrong.copyWith(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    letterSpacing: -0.2,
                    color: c.ink,
                  ),
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.caption.copyWith(
                  color: c.dim,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Destedeki tek kart (kabuk + başlık + menü + içerik).
class DeckCardView extends StatelessWidget {
  const DeckCardView({
    super.key,
    required this.card,
    required this.height,
    required this.raised,
    required this.onRefresh,
  });

  final DeckCardSpec card;
  final double height;
  final bool raised;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final hue = StatsHue.of(context.akn, card.tone);
    return DeckCardShell(
      height: height,
      tint: hue.tint,
      raised: raised,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DeckCardHeader(
            icon: card.icon,
            color: hue.glyph,
            title: card.title,
            subtitle: card.subtitle,
            trailing: _CardMenu(card: card, onRefresh: onRefresh),
          ),
          const SizedBox(height: 8),
          Expanded(child: card.body),
        ],
      ),
    );
  }
}

/// "⋯": Yenile · Nasıl hesaplanır?
class _CardMenu extends StatelessWidget {
  const _CardMenu({required this.card, required this.onRefresh});

  final DeckCardSpec card;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return PopupMenuButton<String>(
      key: ValueKey('deck-menu-${card.id}'),
      tooltip: StatsCopy.deckMenu,
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (v) {
        if (v == 'refresh') unawaited(onRefresh());
        if (v == 'how') unawaited(_showHowTo(context));
      },
      itemBuilder: (ctx) => const [
        PopupMenuItem(
          value: 'refresh',
          child: _MenuRow(Icons.refresh_rounded, StatsCopy.deckRefresh),
        ),
        PopupMenuItem(
          value: 'how',
          child: _MenuRow(Icons.info_outline_rounded, StatsCopy.deckHowTo),
        ),
      ],
      child: SizedBox(
        width: AknSpace.minTap,
        height: AknSpace.minTap,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.more_horiz_rounded, color: c.dim, size: 20),
          ),
        ),
      ),
    );
  }

  Future<void> _showHowTo(BuildContext context) => showAppSheet<void>(
    context: context,
    title: card.title,
    subtitle: StatsCopy.deckHowTo,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(card.howTo, style: ctx.aknText.body),
    ),
  );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20, color: context.akn.brand),
      const SizedBox(width: 12),
      Flexible(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis)),
    ],
  );
}

// ============================================================== yükleniyor / hata

class _DeckSkeleton extends StatelessWidget {
  const _DeckSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final height = deckCardHeight(context);
    return Shimmer(
      semanticLabel: StatsCopy.deckLoading,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: height + 26,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var d = 2; d >= 0; d--)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: Transform.translate(
                      offset: Offset(0, 13.0 * d),
                      child: Transform.scale(
                        scale: 1 - 0.05 * d,
                        alignment: Alignment.bottomCenter,
                        child: DeckCardShell(
                          height: height,
                          tint: c.line,
                          raised: d == 0,
                          child: d == 0
                              ? const _SkeletonCardBody()
                              : const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SkeletonBox(width: 20, height: 7, radius: 4),
              SizedBox(width: 6),
              SkeletonBox(width: 7, height: 7, radius: 4),
              SizedBox(width: 6),
              SkeletonBox(width: 7, height: 7, radius: 4),
            ],
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _SkeletonCardBody extends StatelessWidget {
  const _SkeletonCardBody();

  @override
  Widget build(BuildContext context) {
    const heights = [0.35, 0.5, 0.42, 0.66, 0.58, 0.9];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            SkeletonBox(width: 38, height: 38, radius: 12),
            SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLine(widthFactor: 0.5, height: 14),
                  SizedBox(height: 6),
                  SkeletonLine(widthFactor: 0.32, height: 10),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const SkeletonBox(width: 150, height: 28, radius: 8),
        const SizedBox(height: 8),
        const SkeletonBox(width: 110, height: 16, radius: 8),
        const SizedBox(height: 12),
        Expanded(
          child: LayoutBuilder(
            builder: (context, cons) => Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final h in heights)
                  Expanded(
                    child: Center(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: SkeletonBox(
                          width: 20,
                          height: (cons.maxHeight * h).clamp(4.0, 400.0),
                          radius: 4,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DeckError extends StatelessWidget {
  const _DeckError({required this.failure, required this.onRetry});

  final AppFailure failure;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final offline = failure is OfflineFailure || failure is TimeoutFailure;
    final icon = AknIconBox(
      icon: offline ? Icons.cloud_off_rounded : Icons.query_stats_rounded,
      tone: offline ? AknTone.neutral : AknTone.warn,
      size: 40,
    );
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          offline ? StatsCopy.deckOfflineTitle : StatsCopy.deckFailedTitle,
          style: t.bodyStrong.copyWith(color: c.ink),
        ),
        const SizedBox(height: 2),
        Text(
          offline ? StatsCopy.deckOfflineHint : StatsCopy.deckFailedHint,
          style: t.caption.copyWith(color: c.dim),
        ),
      ],
    );
    final button = AknButton.secondary(
      label: StatsCopy.retry,
      size: AknButtonSize.small,
      onPressedAsync: onRetry,
      showSuccess: false,
    );
    // Büyük yazıda düğme metnin altına iner (metin dar bir sütuna sıkışmasın).
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return DeckCardShell(
      tint: c.line,
      raised: true,
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    const SizedBox(width: 12),
                    Expanded(child: texts),
                  ],
                ),
                const SizedBox(height: 12),
                Align(alignment: AlignmentDirectional.centerEnd, child: button),
              ],
            )
          : Row(
              children: [
                icon,
                const SizedBox(width: 12),
                Expanded(child: texts),
                const SizedBox(width: 8),
                button,
              ],
            ),
    );
  }
}

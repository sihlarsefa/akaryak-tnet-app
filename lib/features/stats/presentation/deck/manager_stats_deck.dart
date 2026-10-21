import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/network/app_failure.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/storage/prefs_store.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../application/stats_providers.dart';
import '../../application/stats_scope.dart';
import '../../copy.dart';
import '../../data/stats_models.dart';
import '../../data/stats_repository.dart';
import 'deck_cards.dart';

/// Ana sayfadaki yönetici istatistik destesi (tasarım v2 §5.3, "plaka bir konumdur"). Kendi kendini
/// yönetir: kapsamı olmayan kullanıcıda, sunucu reddettiğinde (403) ya da uç henüz yokken (404) hiçbir
/// şey çizmez (`SizedBox.shrink`). Yüklenirken Beton iskeletli bir kâğıt, yüklenemezse kısa bir hata
/// kâğıdı gösterir; çevrimdışıyken son kayıt "Son güncelleme" ile görünür.
///
/// Ana sayfalar yalnızca `const ManagerStatsDeck()` ekler. Varsayılan dış boşluk `20, 8, 20, 0`'dır
/// (sayfa kenarı 20); sarmalayan bir dolgu varsa `padding: EdgeInsets.zero` verin.
class ManagerStatsDeck extends ConsumerStatefulWidget {
  const ManagerStatsDeck({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 0),
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

/// Kart içeriğinin en büyük yazı ölçeği; bu ölçekte ve üstünde büyük yazı düzeni.
const _maxTextScale = 1.6;

/// Kart yüksekliği (tasarım v2 §5.3): 1,0×'te 300, yazıyla 1,6×'e kadar `300 + 170 × (s − 1)`;
/// 1,6× ve üstünde büyük yazı düzeni ve 320.
double deckCardHeight(BuildContext context) {
  final s = MediaQuery.textScalerOf(context).scale(1);
  if (s >= _maxTextScale) return 320;
  return 300 + 170 * (s.clamp(1.0, _maxTextScale) - 1);
}

/// Büyük yazı düzeninde kart yüksekliği: destedeki en uzun kartın başlık + rakam + satır yüksekliği
/// (yazı 1,6×'te sınırlı; en çok 320). Kart içeriği gerçek ölçülerle hesaplanır ki 2,0× yazıda ana
/// sayfanın ilk ekranında karar satırı da görünsün (pano ekranı 9).
double deckCompactHeight(
  BuildContext context,
  List<DeckCardSpec> cards,
  double width,
) {
  final scaler = MediaQuery.textScalerOf(
    context,
  ).clamp(maxScaleFactor: _maxTextScale);
  final s = scaler.scale(10) / 10;
  final t = context.aknText;
  final inner = math.max(1.0, width - 36);
  double measure(
    InlineSpan span,
    double maxWidth, {
    int? maxLines,
    List<PlaceholderDimensions>? placeholders,
  }) {
    final tp = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: maxLines,
    );
    if (placeholders != null) tp.setPlaceholderDimensions(placeholders);
    tp.layout(maxWidth: math.max(1.0, maxWidth));
    final h = tp.height;
    tp.dispose();
    return h;
  }

  final lineStyle = t.bodySmall.copyWith(fontWeight: FontWeight.w500);
  final chipStyle = t.bodySmall.copyWith(
    fontSize: 14,
    height: 24 / 14,
    fontWeight: FontWeight.w700,
  );
  var best = 0.0;
  for (final card in cards) {
    // Başlık satırı: 8 üst boşluk, ikon, başlık (en çok 2 satır), ⋯ (44).
    final titleRoom = width - 18 - 4 - 20 * math.min(s, 1.3) - 8 - 46;
    final titleH = measure(
      TextSpan(text: card.title, style: t.headline),
      titleRoom,
      maxLines: 2,
    );
    var h = 8 + math.max(40.0, titleH) + 58 * math.min(s, 1.3);
    final line = card.compactLine;
    if (line != null) {
      h += 8;
      final chip = line.chip;
      if (chip != null) {
        final tp = TextPainter(
          text: TextSpan(text: chip, style: chipStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        final chipW = (16 + 9 + 5 + tp.width + 10) * s;
        tp.dispose();
        h += measure(
          TextSpan(
            style: lineStyle,
            children: [
              const WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: SizedBox.shrink(),
              ),
              TextSpan(text: line.text),
            ],
          ),
          inner,
          placeholders: [
            PlaceholderDimensions(
              size: Size(chipW, 24 * s),
              alignment: PlaceholderAlignment.middle,
            ),
          ],
        );
      } else {
        final bang = line.bang ? 18 * s + 8 : 0.0;
        h += measure(TextSpan(text: line.text, style: lineStyle), inner - bang);
      }
    }
    best = math.max(best, h + 14);
  }
  return (best + 6).clamp(200.0, 320.0).toDouble();
}

/// Büyük yazı düzeni (başlık, rakam, çip ve cümle; çubuk ve okuma yok).
bool deckCompactLayout(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1) >= _maxTextScale;

/// Kaydırılan kart destesi (tasarım v2 §5.3, §8): plaka bir konumdur — en üstteki kart plakayı giyer
/// (plaka mürekkebi), arkadakiler beyaz kâğıttır (1 px çizgi, r20; hemen arkadaki Beton). Üstteki
/// kart sürüklenirken arkadaki kâğıdın renkleri sürükleme oranıyla plakaya geçer, bırakınca devir
/// 200 ms'de tamamlanır; sürüklenen kart kalkık gölge alır, dinlenirken gölge yok. Genişliğin %28'ini
/// ya da 700 px/s'yi geçen atış kartı uçurur (240 ms) ve kart arkaya geçer; aksi hâlde yaylanarak
/// yerine döner. Oturumun ilk gösteriminde plaka yanar (180 ms), rakam sayaç gibi döner (900 ms) ve
/// çubuklar yükselir; deste ilk kez görülünce üst kart bir kez ±10 px sallanır. Hareket azaltmada
/// hepsi son kareden çizilir. Her kart değişiminde hafif titreşim.
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
    with TickerProviderStateMixin {
  /// Kartların sabit sırası (şerit).
  List<String> _ids = const [];

  /// Destedeki sıra: ilk eleman en üstteki kart; her zaman [_ids]'in döndürülmüşü.
  List<String> _order = const [];

  double _dx = 0;
  double _width = 350;
  late final AnimationController _anim = AnimationController(vsync: this);
  Animation<double>? _dxAnim;
  bool _flying = false;
  bool _nudging = false;
  Timer? _hintTimer;
  bool _started = false;

  /// Üst kartın plakaya geçişi (ilk gösterimde 180 ms, şeritten atlamada 200 ms).
  late final AnimationController _light = AnimationController(
    vsync: this,
    duration: AknMotion.plateLight,
    value: 1,
  );

  /// Oturumun sayaç dönüşünü yapacak kart (ilk üst kart; dönüş başlayınca null).
  String? _rollId;

  /// Büyük yazı düzeni yüksekliği (kartlar, genişlik ve yazı ölçeği değişmedikçe yeniden ölçülmez).
  (List<DeckCardSpec>, double, double, double)? _compactCache;

  double _compactHeight(BuildContext context, double width) {
    final scale = MediaQuery.textScalerOf(context).scale(10);
    final c = _compactCache;
    if (c != null &&
        identical(c.$1, widget.cards) &&
        c.$2 == width &&
        c.$3 == scale) {
      return c.$4;
    }
    final h = deckCompactHeight(context, widget.cards, width);
    _compactCache = (widget.cards, width, scale, h);
    return h;
  }

  static const _flingThreshold = 0.28;
  static const _flingVelocity = 700.0;

  /// Sürüklerken en çok 6° eğim.
  static const _maxTilt = 0.105;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      final a = _dxAnim;
      if (a != null && mounted) setState(() => _dx = a.value);
    });
    _light.addListener(() {
      if (mounted) setState(() {});
    });
    _sync(widget.cards);
    if (!ref.read(plateRollSeenProvider) && _order.isNotEmpty) {
      _rollId = _order.first;
    }
  }

  @override
  void didUpdateWidget(SwipeDeck old) {
    super.didUpdateWidget(old);
    _sync(widget.cards);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduced = AknMotion.reduced(context);
    final rolls = _rollId != null && !reduced;
    if (rolls) {
      // Plaka kâğıttan turuncuya yanar, sonra rakam döner (rakamın gecikmesi `plateLight`).
      _light.value = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_light.forward());
      });
    }
    _scheduleHint(afterRoll: rolls);
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _anim.dispose();
    _light.dispose();
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

  /// Oturumun sayaç dönüşü başladı (hareket azaltmada son kare çizildi): bir daha oynamaz.
  void _markRollSeen() {
    if (!mounted) return;
    final seen = ref.read(plateRollSeenProvider.notifier);
    if (!seen.state) seen.state = true;
    if (_rollId != null) setState(() => _rollId = null);
  }

  /// Deste ilk kez görülünce üst kart bir kez sallanır ("kaydırılabilir"); sayaç dönüşünden sonra.
  void _scheduleHint({required bool afterRoll}) {
    if (_ids.length < 2 || AknMotion.reduced(context)) return;
    final prefs = _prefs();
    if (prefs == null || prefs.getBool(StatsKeys.deckHint)) return;
    unawaited(prefs.setBool(StatsKeys.deckHint, true));
    final wait = afterRoll
        ? AknMotion.plateLight +
              AknMotion.plateRoll +
              const Duration(milliseconds: 150)
        : const Duration(milliseconds: 700);
    _hintTimer = Timer(wait, _nudge);
  }

  void _nudge() {
    if (!mounted || _flying || _dx != 0) return;
    _nudging = true;
    _dxAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: 10,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 10,
          end: -10,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: -10,
          end: 0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 25,
      ),
    ]).animate(_anim);
    _anim.duration = AknMotion.nudge;
    _anim.forward(from: 0).whenCompleteOrCancel(() {
      if (mounted) setState(() => _nudging = false);
    });
  }

  // ---------------------------------------------------------------- kaydırma

  void _onDragUpdate(DragUpdateDetails d) {
    if (_flying || _ids.length < 2) return;
    _anim.stop();
    _dxAnim = null;
    _nudging = false;
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

  /// Üstteki kartı [dir] yönüne uçurur, arkaya alır; sıradaki kart plakayı devralır.
  Future<void> _fly(double dir, {bool haptic = true}) async {
    if (_flying || _ids.length < 2) return;
    if (AknMotion.reduced(context)) {
      _rotate(1, haptic: haptic);
      return;
    }
    _flying = true;
    _dxAnim = Tween<double>(
      begin: _dx,
      end: dir * _width * 1.4,
    ).chain(CurveTween(curve: AknMotion.fly)).animate(_anim);
    _anim.duration = AknMotion.deckFly;
    try {
      await _anim.forward(from: 0).orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted) return;
    _rotate(1, haptic: haptic);
  }

  /// Sırayı döndürür: 1 = sonraki kart üste, -1 = önceki kart üste.
  void _rotate(int step, {bool haptic = true}) {
    if (_order.length < 2) return;
    if (haptic) AknHaptics.selection();
    setState(() {
      _order = step > 0
          ? [..._order.skip(1), _order.first]
          : [_order.last, ..._order.take(_order.length - 1)];
      _dx = 0;
      _dxAnim = null;
      _flying = false;
    });
  }

  /// "1 / 8" düğmesi: sonraki kart (titreşimi şerit verir).
  void _next() => unawaited(_fly(-1, haptic: false));

  /// Şeritteki çizgiye dokununca o kart doğrudan üste gelir ve plakayı 200 ms'de yakar.
  void _goTo(String id) {
    if (_flying || _order.isEmpty || _order.first == id) return;
    final i = _ids.indexOf(id);
    if (i < 0) return;
    setState(() {
      _order = [..._ids.skip(i), ..._ids.take(i)];
      _dx = 0;
      _dxAnim = null;
    });
    if (!AknMotion.reduced(context)) {
      _light.duration = AknMotion.plateHandoff;
      unawaited(_light.forward(from: 0));
    }
  }

  // ---------------------------------------------------------------- menü

  Future<void> _openMenu(DeckCardSpec card, BuildContext anchor) async {
    final box = anchor.findRenderObject();
    final overlay = Navigator.of(context).overlay?.context.findRenderObject();
    if (box is! RenderBox || overlay is! RenderBox) return;
    final rect = Rect.fromPoints(
      box.localToGlobal(Offset.zero, ancestor: overlay),
      box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
    );
    final c = context.akn;
    // Menü desteyi açan sayfanın temasıyla açılır (plakanın turuncusu menüye geçmez).
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      color: c.surfaceRaised,
      shape: const RoundedRectangleBorder(borderRadius: AknRadius.card),
      items: const [
        PopupMenuItem(
          value: 'details',
          child: _MenuRow(Icons.bar_chart_rounded, StatsCopy.deckDetails),
        ),
        PopupMenuItem(
          value: 'refresh',
          child: _MenuRow(Icons.refresh_rounded, StatsCopy.deckRefresh),
        ),
        PopupMenuItem(
          value: 'how',
          child: _MenuRow(Icons.info_outline_rounded, StatsCopy.deckHowTo),
        ),
      ],
    );
    if (!mounted) return;
    switch (v) {
      case 'details':
        unawaited(context.push(AppRoutes.stats));
      case 'refresh':
        unawaited(widget.onRefresh());
      case 'how':
        unawaited(_showHowTo(context, card));
    }
  }

  // ---------------------------------------------------------------- görünüm

  @override
  Widget build(BuildContext context) {
    final byId = {for (final c in widget.cards) c.id: c};
    final compact = deckCompactLayout(context);
    final reduced = AknMotion.reduced(context);
    final topId = _order.first;
    final top = byId[topId]!;
    final index = _ids.indexOf(topId);
    final n = _ids.length;
    final theme = Theme.of(context);
    final paper = context.akn;
    final text = context.aknText;
    final plate = paper.plateInk();

    Widget stack = LayoutBuilder(
      builder: (context, cons) {
        _width = cons.maxWidth.isFinite ? cons.maxWidth : 350;
        final height = compact
            ? _compactHeight(context, _width)
            : deckCardHeight(context);
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
                _layer(
                  card: byId[visible[depth]]!,
                  depth: depth,
                  progress: progress,
                  height: height,
                  compact: compact,
                  theme: theme,
                  paper: paper,
                  plate: plate,
                  text: text,
                ),
            ],
          ),
        );
      },
    );
    // İçerik yazıyla en fazla 1,6× büyür (rakam 1,3×); tam ölçek /stats sayfasında.
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
          label: StatsCopy.deckCardSemantics(
            index + 1,
            n,
            top.title,
            top.summary,
          ),
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
        const SizedBox(height: 2),
        LanePager(
          count: n < 2 ? 0 : n,
          index: index,
          onSelect: n < 2 ? null : (i) => _goTo(_ids[i]),
          showPosition: n >= 2,
          onPositionTap: n < 2 ? null : _next,
          positionSemanticLabel:
              '${StatsCopy.deckNext}, ${StatsCopy.deckPosition(index + 1, n)}',
          actionLabel: StatsCopy.deckStatsLink,
          onAction: () => unawaited(context.push(AppRoutes.stats)),
          padding: EdgeInsets.zero,
        ),
        if (widget.staleNote != null) _StaleNote(at: widget.staleNote!),
      ],
    );
  }

  Widget _layer({
    required DeckCardSpec card,
    required int depth,
    required double progress,
    required double height,
    required bool compact,
    required ThemeData theme,
    required AknColors paper,
    required AknColors plate,
    required AknTextStyles text,
  }) {
    final isTop = depth == 0;
    // Arkadaki kartlar üstteki sürüklendikçe bir kademe öne gelir.
    final d = isTop ? 0.0 : depth - progress;
    final scale = 1 - 0.05 * d;
    final down = 13.0 * d;
    final opacity = (1 - 0.25 * (d - 1).clamp(0.0, 1.0)).clamp(0.0, 1.0);
    final dx = isTop ? _dx : 0.0;
    final angle = isTop
        ? (_dx / _width * 0.30).clamp(-_maxTilt, _maxTilt)
        : 0.0;
    // Plaka bir konumdur: üst kart plaka, hemen arkadaki sürükleme oranıyla plakaya geçer.
    final t = isTop
        ? _light.value
        : depth == 1
        ? progress
        : 0.0;
    final slip = isTop
        ? paper.surface
        : depth == 1
        ? paper.surfaceAlt
        : Color.lerp(paper.surface, paper.surfaceAlt, progress)!;
    final base = paper.copyWith(surface: slip, bg: slip);
    final colors = t <= 0
        ? base
        : t >= 1
        ? plate
        : base.lerp(plate, t);
    final themed = theme.copyWith(
      extensions: [
        for (final e in theme.extensions.values)
          if (e is! AknColors && e is! AknTextStyles) e,
        colors,
        text.recolor(colors),
      ],
    );
    final dragged = isTop && !_nudging && _dx.abs() > 0.5;
    // Yapı her derinlikte aynıdır: kart sıra değiştirirken öğesi korunur (sayaç yeniden dönmez).
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
                      child: Theme(
                        data: themed,
                        child: DeckCardScope(
                          compact: compact,
                          roll: card.id == _rollId,
                          onRollStart: _markRollSeen,
                          // Sahip kararı G: değişim çipi açık turuncu zemin + pas yazı.
                          chipFill: Color.lerp(
                            paper.surfaceAlt,
                            paper.deltaFill,
                            t,
                          ),
                          chipInk: Color.lerp(paper.ink, paper.brandInk, t),
                          child: DeckCardView(
                            card: card,
                            height: height,
                            raised: isTop,
                            plate: t,
                            onRefresh: widget.onRefresh,
                            outline: paper.line,
                            shadow: dragged
                                ? AknShadows.dragged(paper)
                                : const [],
                            onMenu: _openMenu,
                          ),
                        ),
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
}

/// "Nasıl hesaplanır?" sayfası (sayfanın temasıyla).
Future<void> _showHowTo(BuildContext context, DeckCardSpec card) =>
    showAppSheet<void>(
      context: context,
      title: card.title,
      subtitle: StatsCopy.deckHowTo,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          card.howTo,
          style: ctx.aknText.body.copyWith(color: ctx.akn.text),
        ),
      ),
    );

/// "Son güncelleme 14:20, 5 dk önce" (çevrimdışı ya da tazelenemedi).
class _StaleNote extends StatelessWidget {
  const _StaleNote({required this.at});

  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Row(
        children: [
          Icon(Icons.history_rounded, size: 16, color: c.dim),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              StatsCopy.lastUpdate(
                Fmt.time(at),
                TurkishText.lower(Fmt.relative(at)),
              ),
              style: t.caption.copyWith(color: c.dim),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================== kart parçaları

/// Kart kabuğu (tasarım v2 §5.3): r20, düz renk; üstteki kart plaka rengi, arkadakiler kâğıt
/// (1 px çizgi). Gölge yalnızca sürüklenen kartta ([shadow]). [tint] ve [raised] artık rengi
/// değiştirmez (API uyumu için duruyor).
class DeckCardShell extends StatelessWidget {
  const DeckCardShell({
    super.key,
    required this.tint,
    required this.raised,
    required this.child,
    this.height,
    this.padding = AknSpace.plate,
    this.color,
    this.borderColor,
    this.shadow = const [],
    this.plate,
  });

  final Color tint;
  final bool raised;
  final Widget child;
  final double? height;
  final EdgeInsetsGeometry padding;

  /// Zemin; varsayılan `surface` (üst kartta plaka paleti `surface` = plaka).
  final Color? color;

  /// 1 px kenar; varsayılan `line`.
  final Color? borderColor;

  /// Ek gölge (sürüklenen kart kalkık gölge alır); verilmezse kartın kendi gölgesi.
  final List<BoxShadow> shadow;

  /// Plaka kartı oranı (0–1; varsayılan [raised] ise 1). Sahip kararı G: üst kart beyaz kart +
  /// yumuşak turuncu tonu (üstte `plateTint`, %55'te beyaz), `plateBorder` kenar ve plaka
  /// gölgesi; arkadaki kartlar kâğıt + hafif gölge. Vurgu turuncu dolgu değil, gölge ve ölçektir.
  final double? plate;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final p = (plate ?? (raised ? 1.0 : 0.0)).clamp(0.0, 1.0);
    final base = color ?? c.surface;
    final shadows = shadow.isNotEmpty
        ? shadow
        : p >= 0.5
        ? AknShadows.plate(c)
        : AknShadows.plateBehind(c);
    return Container(
      height: height,
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p <= 0 ? base : null,
        gradient: p <= 0
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.lerp(base, c.plateTint, p)!,
                  Color.lerp(base, c.plate, p)!,
                ],
                stops: const [0, 0.55],
              ),
        borderRadius: AknRadius.plate,
        border: Border.all(
          color: Color.lerp(borderColor ?? c.line, c.plateBorder, p)!,
        ),
        boxShadow: shadows,
      ),
      child: child,
    );
  }
}

/// Kart başlık satırı (tasarım v2 §5.1): 20 px mürekkep ikonu, başlık (`headline`), sağda yalnızca
/// dönem ("1–21 Ekim") ve ⋯. Renkli ikon kutusu yok; [color] yok sayılır.
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

  /// Dönem.
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => PlateHead(
    icon: icon,
    title: title,
    period: subtitle.isEmpty ? null : subtitle,
    trailing: trailing,
  );
}

/// Destedeki tek kart: kabuk + başlık satırı (⋯ menüsü) + içerik. Renkler bağlamdan gelir (deste
/// üst karta plaka paletini, arkadakilere kâğıt paletini verir).
class DeckCardView extends StatelessWidget {
  const DeckCardView({
    super.key,
    required this.card,
    required this.height,
    required this.raised,
    required this.onRefresh,
    this.outline,
    this.shadow = const [],
    this.onMenu,
    this.plate,
  });

  /// Plaka kartı oranı (üst kart 1; devir sırasında arkadaki kart 0→1).
  final double? plate;

  final DeckCardSpec card;
  final double height;

  /// En üstteki kart (plakayı giyen).
  final bool raised;
  final Future<void> Function() onRefresh;
  final Color? outline;
  final List<BoxShadow> shadow;

  /// ⋯ menüsünü açar (deste sayfanın temasıyla açar); verilmezse kartın kendi bağlamıyla.
  final void Function(DeckCardSpec card, BuildContext anchor)? onMenu;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return DeckCardShell(
      height: height,
      tint: c.line,
      raised: raised,
      color: c.surface,
      borderColor: outline,
      shadow: shadow,
      plate: plate,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 4, 0),
            child: DeckCardHeader(
              icon: card.icon,
              color: c.ink,
              title: card.title,
              subtitle: card.subtitle,
              trailing: _MenuButton(
                card: card,
                onOpen: (anchor) {
                  final open = onMenu;
                  if (open != null) {
                    open(card, anchor);
                  } else {
                    unawaited(_fallbackMenu(anchor));
                  }
                },
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
              child: card.body,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _fallbackMenu(BuildContext anchor) async {
    final v = await showMenu<String>(
      context: anchor,
      position: const RelativeRect.fromLTRB(1000, 80, 16, 0),
      items: const [
        PopupMenuItem(
          value: 'refresh',
          child: _MenuRow(Icons.refresh_rounded, StatsCopy.deckRefresh),
        ),
        PopupMenuItem(
          value: 'how',
          child: _MenuRow(Icons.info_outline_rounded, StatsCopy.deckHowTo),
        ),
      ],
    );
    if (!anchor.mounted) return;
    if (v == 'refresh') unawaited(onRefresh());
    if (v == 'how') unawaited(_showHowTo(anchor, card));
  }
}

/// ⋯ düğmesi (48 px hedef, mürekkep ikon; başlık satırında 44 × 40 yer kaplar).
class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.card, required this.onOpen});

  final DeckCardSpec card;
  final void Function(BuildContext anchor) onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return IconButton(
      key: ValueKey('deck-menu-${card.id}'),
      onPressed: () => onOpen(context),
      tooltip: StatsCopy.deckMenu,
      icon: Icon(Icons.more_horiz_rounded, size: 22, color: c.ink),
      style: IconButton.styleFrom(
        minimumSize: const Size(AknSpace.minTap, AknSpace.minTap),
        fixedSize: const Size(AknSpace.minTap, AknSpace.minTap),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        highlightColor: c.ink.withValues(alpha: 0.12),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return Row(
      children: [
        Icon(icon, size: 20, color: c.ink),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.aknText.body.copyWith(color: c.ink),
          ),
        ),
      ],
    );
  }
}

// ============================================================== yükleniyor / hata

/// Yüklenirken: Beton iskeletli kâğıt (turuncu yok); veri gelince plaka yanar.
class _DeckSkeleton extends StatelessWidget {
  const _DeckSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final height = deckCardHeight(context);
    final compact = deckCompactLayout(context);
    Widget slip(int d) => Positioned(
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
            color: d == 1 ? c.surfaceAlt : c.surface,
            padding: AknSpace.plate,
            child: d == 0
                ? _SkeletonCardBody(compact: compact)
                : const SizedBox.expand(),
          ),
        ),
      ),
    );
    return Shimmer(
      semanticLabel: StatsCopy.deckLoading,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: height + 26,
            child: Stack(
              clipBehavior: Clip.none,
              children: [slip(2), slip(1), slip(0)],
            ),
          ),
          const SizedBox(
            height: 50,
            child: Row(
              children: [
                SkeletonBox(width: 24, height: 4, radius: 2),
                SizedBox(width: 6),
                SkeletonBox(width: 10, height: 4, radius: 2),
                SizedBox(width: 6),
                SkeletonBox(width: 10, height: 4, radius: 2),
                SizedBox(width: 6),
                SkeletonBox(width: 10, height: 4, radius: 2),
                SizedBox(width: 12),
                SkeletonBox(width: 30, height: 14, radius: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkeletonCardBody extends StatelessWidget {
  const _SkeletonCardBody({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    const heights = [0.6, 0.66, 0.8, 0.72, 0.9, 0.55];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            SkeletonBox(width: 20, height: 20, radius: 6),
            SizedBox(width: 8),
            SkeletonBox(width: 96, height: 16, radius: 6),
            Spacer(),
            SkeletonBox(width: 64, height: 14, radius: 6),
          ],
        ),
        const SizedBox(height: 16),
        const Align(
          alignment: AlignmentDirectional.centerStart,
          child: SkeletonBox(width: 200, height: 48, radius: 12),
        ),
        const SizedBox(height: 10),
        const Row(
          children: [
            SkeletonBox(width: 64, height: 24, radius: 6),
            SizedBox(width: 10),
            Expanded(child: SkeletonLine(widthFactor: 0.8, height: 14)),
          ],
        ),
        if (!compact) ...[
          const Spacer(),
          SizedBox(
            height: 38,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final h in heights)
                  SkeletonBox(width: 16, height: 38 * h, radius: 4),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const SkeletonBox(height: 3, radius: 2),
          const SizedBox(height: 10),
          const Row(
            children: [
              Expanded(child: SkeletonBox(height: 36, radius: 6)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 36, radius: 6)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 36, radius: 6)),
            ],
          ),
        ],
      ],
    );
  }
}

/// Yüklenemedi / çevrimdışı: kâğıt, ne olduğu ve "Tekrar dene".
class _DeckError extends StatelessWidget {
  const _DeckError({required this.failure, required this.onRetry});

  final AppFailure failure;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final offline = failure is OfflineFailure || failure is TimeoutFailure;
    final icon = Icon(
      offline ? Icons.cloud_off_outlined : Icons.error_outline_rounded,
      size: 24,
      color: c.dim,
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
          style: t.bodySmall.copyWith(color: c.dim),
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
      raised: false,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
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
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: button,
                ),
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

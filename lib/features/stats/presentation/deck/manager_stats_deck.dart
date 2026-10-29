import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
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

/// Ana sayfadaki yönetici istatistik destesi (tasarım v3 "Akış", §4 hero kartı): üstte beyaz, sıcak
/// tonlu plaka kartı (r26, plaka gölgesi), arkasında iki kart daha. Kendi kendini yönetir: kapsamı
/// olmayan kullanıcıda, sunucu reddettiğinde (403) ya da uç henüz yokken (404) hiçbir şey çizmez
/// (`SizedBox.shrink`). Yüklenirken parıltılı iskelet, yüklenemezse kısa bir hata kartı gösterir;
/// iskeletten desteye ve hatadan desteye yumuşak bir geçişle (solarak, hafif büyüyerek) geçer.
/// Çevrimdışıyken son kayıt "Son güncelleme" ile görünür.
///
/// Ana sayfalar yalnızca `const ManagerStatsDeck()` ekler. Varsayılan dış boşluk `20, 8, 20, 0`'dır
/// (sayfa kenarı 20); sarmalayan bir dolgu varsa `padding: EdgeInsets.zero` verin.
///
/// v4 "Sade" (§4): `raised: false` — destenin altında durduğu ana sayfalarda kahraman "Sıra sizde"
/// kartıdır; üst kart düz beyaz kalır ve arkadaki kartın hafif gölgesini (`plateBehind`) taşır. ⋯
/// menüsü yok ("Detaylı" sayfa bağlantısında, "Yenile" aşağı çekince, "Nasıl hesaplanır?"
/// /stats'ta); fark çipi başlığın sağında; kart 248 dp, arkada tek 8 dp kâğıt kenarı.
class ManagerStatsDeck extends ConsumerStatefulWidget {
  const ManagerStatsDeck({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 0),
    this.raised = true,
  });

  final EdgeInsetsGeometry padding;

  /// False: the deck is not the hero (it sits under "Sıra sizde").
  final bool raised;

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

    final Widget child;
    final String state;
    if (data == null) {
      if (statsDenied(error)) return const SizedBox.shrink();
      if (error != null && !loading) {
        if (error is UnknownFailure && error.cancelled) {
          return const SizedBox.shrink();
        }
        state = 'error';
        child = _DeckError(failure: error, onRetry: _refresh);
      } else {
        state = 'loading';
        child = const _DeckSkeleton();
      }
    } else {
      if (cards.isEmpty) return const SizedBox.shrink();
      state = 'deck';
      child = SwipeDeck(
        cards: cards,
        onRefresh: _refresh,
        staleNote: fromCache || error != null ? updatedAt : null,
        raised: widget.raised,
      );
    }
    // İskelet → deste, hata → deste: eski içerik solarken yenisi hafifçe büyüyerek belirir.
    return Padding(
      padding: widget.padding,
      child: AnimatedSwitcher(
        duration: AknMotion.of(context, AknMotion.slow),
        switchInCurve: AknMotion.emphasizedCurve,
        switchOutCurve: AknMotion.exit,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          fit: StackFit.passthrough,
          children: [...previous, ?current],
        ),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1).animate(animation),
            alignment: Alignment.topCenter,
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(state), child: child),
      ),
    );
  }

  static bool _hasSelfRow(BayiStats d, String? uid) =>
      d.team.length == 1 || d.team.any((m) => uid != null && m.userId == uid);
}

// ============================================================== deste

/// Kart içeriğinin en büyük yazı ölçeği; bu ölçekte ve üstünde büyük yazı düzeni.
const _maxTextScale = 1.6;

/// Kart yüksekliği (v4): 1,0×'te 248, yazıyla 1,6×'e kadar `248 + 170 × (s − 1)`; 1,6× ve üstünde
/// büyük yazı düzeni ve 320.
double deckCardHeight(BuildContext context) {
  final s = MediaQuery.textScalerOf(context).scale(1);
  if (s >= _maxTextScale) return 320;
  return 248 + 170 * (s.clamp(1.0, _maxTextScale) - 1);
}

/// Kartın başlık satırının iç boşlukları (soldan, üstten, sağdan) ve başlıkla içerik arası.
const _headPad = EdgeInsets.fromLTRB(20, 12, 6, 0);
const _headGap = 10.0;

/// Kart içeriğinin iç boşlukları.
const _bodyPad = EdgeInsets.fromLTRB(20, 0, 20, 14);

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
  final inner = math.max(1.0, width - _bodyPad.horizontal);
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

  // Başlık satırı ([PlateHead]): 40 px simge kutusu (en çok 1,3×), başlık 16/20 700 (en çok 2 satır)
  // ve altında dönem 12/16 500, sağda ⋯ (48).
  // v4: no icon tile and no ⋯; the title 16/20 700 and the period 13/18 on one baseline (at most
  // two lines), the delta chip (≈ 72) on the right.
  final titleStyle = t.headline.copyWith(
    fontSize: 16,
    height: 20 / 16,
    fontWeight: FontWeight.w700,
  );
  final periodStyle = t.label.copyWith(fontWeight: FontWeight.w500);
  final lineStyle = deckSentenceStyle(context);
  final chipStyle = deckChipStyle(context);
  final titleRoom = width - _headPad.horizontal - 10 - 72;
  var best = 0.0;
  for (final card in cards) {
    final head = measure(
      TextSpan(
        text: card.title,
        style: titleStyle,
        children: [
          if (card.subtitle.isNotEmpty)
            TextSpan(text: '  ${card.subtitle}', style: periodStyle),
        ],
      ),
      titleRoom,
      maxLines: 2,
    );
    // Rakam: `plateFigure` 46/52, en çok 1,3× yazı.
    var h = _headPad.top + head + _headGap + 52 * math.min(s, 1.3);
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
        final style = line.bang
            ? lineStyle.copyWith(fontWeight: FontWeight.w700)
            : lineStyle;
        h += measure(TextSpan(text: line.text, style: style), inner - bang);
      }
    }
    best = math.max(best, h + _bodyPad.bottom);
  }
  return (best + 6).clamp(200.0, 320.0).toDouble();
}

/// Büyük yazı düzeni (başlık, rakam, çip ve cümle; çubuk ve okuma yok).
bool deckCompactLayout(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1) >= _maxTextScale;

/// Kaydırılan kart destesi (tasarım v3 §4–5): üstteki kart plaka kartıdır — beyaz, üstte sıcak tonlu,
/// r26, plaka gölgesi; arkadakiler kâğıttır (hemen arkadaki `surfaceAlt`, en arkadaki `surface`) ve
/// arkadaki kartın hafif gölgesini taşır (`plateBehind`).
///
/// Fiziksel hareket: kart parmağı izler ve sürükleme yönüne 6°'ye kadar eğilir, hafifçe kalkar;
/// arkadaki kartlar sürükleme oranıyla bir kademe öne gelir ve renkleri plakaya geçer. Genişliğin
/// %28'ini ya da 700 px/s'yi geçen atış kartı uçurur (240 ms); bu sırada arkadaki kart yaylanarak öne
/// çıkar (hafifçe aşıp yerine oturur), uçan kart destenin arkasına süzülerek girer. Aksi hâlde kart
/// bırakıldığı hızla gerçek bir yay benzetimiyle yerine döner.
///
/// Kart öne gelirken (üste çıkınca ya da sürüklemede açılmaya başlayınca) içeriği yeniden kurulur:
/// rakam sayaç gibi döner, çubuklar yükselir, okumalar yerine oturur. Oturumun ilk gösteriminde plaka
/// yanar (180 ms) ve rakam uzun sayaç dönüşünü yapar; deste ilk kez görülünce üst kart bir kez ±10 px
/// sallanır. Hareket azaltmada hepsi son kareden çizilir. Her kart değişiminde hafif titreşim.
class SwipeDeck extends ConsumerStatefulWidget {
  const SwipeDeck({
    super.key,
    required this.cards,
    required this.onRefresh,
    this.staleNote,
    this.raised = true,
  });

  final List<DeckCardSpec> cards;
  final Future<void> Function() onRefresh;

  /// Önbellekten / tazelenemeyen veride son güncelleme anı.
  final DateTime? staleNote;

  /// False (v4): the top card stays flat white with the light shadow.
  final bool raised;

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

  /// Uçuş ve ipucu sallanması (0–1, [_dxAnim] ile).
  late final AnimationController _anim = AnimationController(vsync: this);
  Animation<double>? _dxAnim;

  /// Yerine dönüş: sınırsız denetleyici, yay benzetimiyle [_dx]'i sürer.
  late final AnimationController _spring = AnimationController.unbounded(
    vsync: this,
  );
  bool _springing = false;

  bool _flying = false;
  bool _nudging = false;

  /// Uçuş başladığında arkadaki kartın öne gelme oranı (yay buradan 1'e sürer).
  double _flightFrom = 0;
  Timer? _hintTimer;
  bool _started = false;

  /// Üst kartın plakaya geçişi (ilk gösterimde 180 ms, şeritten atlamada 200 ms).
  late final AnimationController _light = AnimationController(
    vsync: this,
    duration: AknMotion.plateLight,
    value: 1,
  );

  /// Destenin arkasına yeni giren kartın süzülüşü.
  late final AnimationController _tuck = AnimationController(
    vsync: this,
    duration: AknMotion.slow,
    value: 1,
  );
  String? _tuckId;

  /// Oturumun sayaç dönüşünü yapacak kart (ilk üst kart; dönüş başlayınca null).
  String? _rollId;

  /// İçerik kuşağı: kart öne gelirken içeriği yeniden kurulur (rakam döner, çubuklar yükselir).
  final Map<String, int> _gen = {};

  /// İçeriği şu an kurulu kartlar (üstteki ve sürüklemede açılan).
  final Set<String> _live = {};

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

  /// Yerine dönüşün yayı: hafif aşan (≈ %8), 0,45 s'de duran yumuşak yay.
  static final _springDesc = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 420,
    ratio: 0.62,
  );

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      final a = _dxAnim;
      if (a != null && mounted) setState(() => _dx = a.value);
    });
    _spring.addListener(() {
      if (_springing && mounted) setState(() => _dx = _spring.value);
    });
    _light.addListener(() {
      if (mounted) setState(() {});
    });
    _tuck.addListener(() {
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
      // Plaka kâğıttan plakaya yanar, sonra rakam döner (rakamın gecikmesi `plateLight`).
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
    _spring.dispose();
    _light.dispose();
    _tuck.dispose();
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

  void _stopSpring() {
    if (!_springing) return;
    _springing = false;
    _spring.stop();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_flying || _ids.length < 2) return;
    _anim.stop();
    _stopSpring();
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
      _settle(v);
    }
  }

  /// Bırakıldığı hızla yerine dönüş (yay benzetimi; hafifçe aşar ve oturur).
  void _settle([double velocity = 0]) {
    if (_flying || _dx == 0) return;
    if (AknMotion.reduced(context)) {
      setState(() => _dx = 0);
      return;
    }
    _anim.stop();
    _dxAnim = null;
    _springing = true;
    _spring.value = _dx;
    _spring
        .animateWith(SpringSimulation(_springDesc, _dx, 0, velocity))
        .whenCompleteOrCancel(() {
          if (!mounted || !_springing) return;
          setState(() {
            _springing = false;
            _dx = 0;
          });
        });
  }

  /// Sürükleme oranı (arkadaki kartın öne gelişi, 0–1).
  double get _dragProgress =>
      (_dx.abs() / (_width * _flingThreshold)).clamp(0.0, 1.0);

  /// Arkadaki kartın öne gelme oranı: sürüklerken parmağa bağlı, uçuşta yayla 1'e (hafifçe aşarak).
  double get _stepProgress {
    if (!_flying) return _dragProgress;
    final t = AknMotion.spring.transform(_anim.value.clamp(0.0, 1.0));
    return _flightFrom + (1 - _flightFrom) * t;
  }

  /// Üstteki kartı [dir] yönüne uçurur, arkaya alır; sıradaki kart plakayı devralır.
  Future<void> _fly(double dir, {bool haptic = true}) async {
    if (_flying || _ids.length < 2) return;
    if (AknMotion.reduced(context)) {
      _rotate(1, haptic: haptic);
      return;
    }
    _stopSpring();
    _flightFrom = _dragProgress;
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
    _stopSpring();
    setState(() {
      _order = step > 0
          ? [..._order.skip(1), _order.first]
          : [_order.last, ..._order.take(_order.length - 1)];
      _dx = 0;
      _dxAnim = null;
      _flying = false;
      // Uçan kart (ya da yeni görünen kart) destenin arkasına süzülerek girer.
      final visible = math.min(3, _order.length);
      _tuckId = step > 0 && visible > 1 ? _order[visible - 1] : null;
    });
    if (step < 0 && !AknMotion.reduced(context)) {
      // Önceki kart arkadan öne alınır: plaka 200 ms'de yanar.
      _light.duration = AknMotion.plateHandoff;
      unawaited(_light.forward(from: 0));
    }
    if (_tuckId != null) {
      if (AknMotion.reduced(context)) {
        _tuck.value = 1;
      } else {
        unawaited(_tuck.forward(from: 0));
      }
    }
  }

  /// Şeritteki çizgiye dokununca o kart doğrudan üste gelir ve plakayı 200 ms'de yakar.
  void _goTo(String id) {
    if (_flying || _order.isEmpty || _order.first == id) return;
    final i = _ids.indexOf(id);
    if (i < 0) return;
    _stopSpring();
    setState(() {
      _order = [..._ids.skip(i), ..._ids.take(i)];
      _dx = 0;
      _dxAnim = null;
      _tuckId = null;
    });
    if (!AknMotion.reduced(context)) {
      _light.duration = AknMotion.plateHandoff;
      unawaited(_light.forward(from: 0));
    }
  }

  /// [id] kartının içeriği bu karede kurulu mu: üstteki kart her zaman; hemen arkadaki, sürüklemede
  /// açılmaya başlayınca (ya da uçuşta) ve deste yeniden durulana kadar. Kart yeniden açılırken
  /// içerik yeni bir kuşakla kurulur ki giriş hareketi baştan oynasın.
  bool _bodyLive(String id, int depth, double progress) {
    final moving = _flying || _springing || _nudging || _dx != 0;
    final live =
        depth == 0 ||
        (depth == 1 &&
            (_flying || progress > 0.02 || (moving && _live.contains(id))));
    if (live) {
      if (_live.add(id)) _gen[id] = (_gen[id] ?? 0) + 1;
    } else {
      _live.remove(id);
    }
    return live;
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
        final progress = _stepProgress;
        // v4: one 8 dp paper edge behind the top card (the third card
        // fades in only while the deck turns).
        final visible = _order
            .take(progress > 0 || _tuck.isAnimating ? 3 : 2)
            .toList();
        _live.removeWhere((id) => !visible.contains(id));
        return SizedBox(
          height: height + 8,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var depth = visible.length - 1; depth >= 0; depth--)
                _layer(
                  card: byId[visible[depth]]!,
                  depth: depth,
                  last: depth == visible.length - 1,
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
          actionLabel: StatsCopy.deckStatsLink,
          onAction: () => unawaited(context.push(AppRoutes.stats)),
          padding: EdgeInsets.zero,
        ),
        AknAnimatedSize(
          alignment: Alignment.topCenter,
          child: widget.staleNote == null
              ? const SizedBox(width: double.infinity)
              : _StaleNote(at: widget.staleNote!),
        ),
      ],
    );
  }

  Widget _layer({
    required DeckCardSpec card,
    required int depth,
    required bool last,
    required double progress,
    required double height,
    required bool compact,
    required ThemeData theme,
    required AknColors paper,
    required AknColors plate,
    required AknTextStyles text,
  }) {
    final isTop = depth == 0;
    // Arkadaki kartlar üstteki sürüklendikçe bir kademe öne gelir (uçuşta yayla, hafifçe aşarak).
    final d = isTop ? 0.0 : depth - progress;
    var scale = 1 - 0.04 * d;
    var down = 8.0 * d;
    // Only one paper edge shows at rest: the card behind it fades away.
    var opacity = (1 - (d - 1).clamp(0.0, 1.0)).clamp(0.0, 1.0);
    // Destenin arkasına yeni giren kart küçükten ve saydamdan süzülür.
    if (!isTop && last && card.id == _tuckId && _tuck.value < 1) {
      final k = AknMotion.emphasizedCurve.transform(_tuck.value);
      opacity *= k;
      scale -= 0.05 * (1 - k);
      down += 10 * (1 - k);
    }
    final dx = isTop ? _dx : 0.0;
    final angle = isTop
        ? (_dx / _width * 0.30).clamp(-_maxTilt, _maxTilt)
        : 0.0;
    // Sürüklenen kart parmağın altında hafifçe kalkar.
    final lift = isTop && !_nudging
        ? 1 + 0.015 * (dx.abs() / 60).clamp(0.0, 1.0)
        : 1.0;
    // Plaka bir konumdur: üst kart plaka, hemen arkadaki sürükleme oranıyla plakaya geçer.
    final t = isTop
        ? _light.value
        : depth == 1
        ? progress.clamp(0.0, 1.0)
        : 0.0;
    final slip = isTop
        ? paper.surface
        : depth == 1
        ? paper.surfaceAlt
        : Color.lerp(paper.surface, paper.surfaceAlt, progress.clamp(0, 1))!;
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
    final live = _bodyLive(card.id, depth, progress);
    // Yapı her derinlikte aynıdır: kart sıra değiştirirken öğesi korunur.
    return Positioned(
      key: ValueKey(card.id),
      left: 0,
      right: 0,
      top: 0,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
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
                      child: Transform.scale(
                        scale: lift,
                        child: Theme(
                          data: themed,
                          child: DeckCardScope(
                            compact: compact,
                            roll: card.id == _rollId,
                            onRollStart: _markRollSeen,
                            // Fark çipi: plakada açık turuncu zemin + pas yazı, kâğıtta sakin kuyu.
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
                              flat: !widget.raised,
                              onRefresh: widget.onRefresh,
                              outline: paper.line,
                              shadow: dragged
                                  ? AknShadows.dragged(paper)
                                  : const [],
                              showBody: live,
                              bodyKey: ValueKey('${card.id}#${_gen[card.id]}'),
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
      ),
    );
  }
}

/// "Son güncelleme 14:20, 5 dk önce" (çevrimdışı ya da tazelenemedi): saat simgesi ve soluk yazı.
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
          Icon(
            PhosphorIconsRegular.clockCounterClockwise,
            size: 16,
            color: c.dim,
          ),
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

/// Kart kabuğu (tasarım v3 §4 hero kartı): r26; üstteki kart plaka kartıdır — `plateTint` → `plate`
/// dikey sıcak ton (%55'te beyaz), 1 px `plateBorder` ve plaka gölgesi; arkadakiler düz kâğıt, 1 px
/// çizgi ve arkadaki kartın hafif gölgesi (`plateBehind`). Kart öne gelirken ton, kenar ve gölge
/// birlikte [plate] oranıyla geçer. Sürüklenen kart kalkık gölge alır ([shadow]). [tint] ve [raised]
/// rengi değiştirmez (API uyumu için duruyor).
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
    this.flat = false,
  });

  /// v4: no warm wash and the light `plateBehind` shadow (the deck under
  /// "Sıra sizde").
  final bool flat;

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

  /// Plaka kartı oranı (0–1; varsayılan [raised] ise 1).
  final double? plate;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final p = flat ? 0.0 : (plate ?? (raised ? 1.0 : 0.0)).clamp(0.0, 1.0);
    final base = color ?? c.surface;
    final shadows = shadow.isNotEmpty
        ? shadow
        : p <= 0
        ? AknShadows.plateBehind(c)
        : p >= 1
        ? AknShadows.plate(c)
        : BoxShadow.lerpList(
                AknShadows.plateBehind(c),
                AknShadows.plate(c),
                p,
              ) ??
              AknShadows.plate(c);
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

/// Kart başlık satırı (tasarım v3 §4): 40 px turuncu tonlu simge kutusu (simge yerine "pop" ile
/// oturur), başlık 16/20 700 ve altında dönem ("1–21 Ekim"), sağda ⋯. [color] yok sayılır.
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

  /// v4: no icon tile (the [icon] is kept for API stability); the title
  /// and the period on one baseline, [trailing] (the delta chip) on the
  /// right.
  @override
  Widget build(BuildContext context) => PlateHead(
    title: title,
    period: subtitle.isEmpty ? null : subtitle,
    trailing: trailing,
  );
}

/// Destedeki tek kart: kabuk + başlık satırı (v4: sağda fark çipi, ⋯ yok) + içerik. Renkler bağlamdan
/// gelir (deste üst karta plaka paletini, arkadakilere kâğıt paletini verir). İçerik yalnızca
/// [showBody] iken kurulur; [bodyKey] değişince içerik yeniden kurulur ve giriş hareketini baştan
/// oynar. İçerikteki fark çipi başlığın sağına taşınır ([DeckHeadChip]).
class DeckCardView extends StatefulWidget {
  const DeckCardView({
    super.key,
    required this.card,
    required this.height,
    required this.raised,
    required this.onRefresh,
    this.outline,
    this.shadow = const [],
    this.plate,
    this.flat = false,
    this.showBody = true,
    this.bodyKey,
  });

  /// Plaka kartı oranı (üst kart 1; devir sırasında arkadaki kart 0→1).
  final double? plate;

  /// v4: düz beyaz kart ve hafif gölge (deste kahraman değil).
  final bool flat;

  final DeckCardSpec card;
  final double height;

  /// En üstteki kart (plakayı giyen).
  final bool raised;

  /// Kept for API stability (v4: refresh is pull-to-refresh).
  final Future<void> Function() onRefresh;
  final Color? outline;
  final List<BoxShadow> shadow;

  /// İçerik kurulsun mu (arkada duran kartın içeriği görünmez; deste kurmaz).
  final bool showBody;

  /// İçeriğin anahtarı (kart öne gelince yeni anahtar → içerik baştan canlanır).
  final Key? bodyKey;

  @override
  State<DeckCardView> createState() => _DeckCardViewState();
}

class _DeckCardViewState extends State<DeckCardView> {
  final DeckChipSlot _chip = DeckChipSlot();

  @override
  void dispose() {
    _chip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final w = widget;
    return DeckCardShell(
      height: w.height,
      tint: c.line,
      raised: w.raised,
      color: c.surface,
      borderColor: w.outline,
      shadow: w.shadow,
      plate: w.plate,
      flat: w.flat,
      padding: EdgeInsets.zero,
      child: DeckHeadChip(
        sink: _chip,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: _headPad,
              child: DeckCardHeader(
                icon: w.card.icon,
                color: c.ink,
                title: w.card.title,
                subtitle: w.card.subtitle,
                trailing: ValueListenableBuilder<Widget?>(
                  valueListenable: _chip,
                  builder: (context, chip, _) => chip == null
                      ? const SizedBox.shrink()
                      : ExcludeSemantics(child: chip),
                ),
              ),
            ),
            const SizedBox(height: _headGap),
            Expanded(
              child: w.showBody
                  ? KeyedSubtree(
                      key: w.bodyKey,
                      child: Padding(padding: _bodyPad, child: w.card.body),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================== yükleniyor / hata

/// Yüklenirken: destenin biçiminde iskelet kartlar (parıltı süpürür); veri gelince deste belirir.
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
        offset: Offset(0, 8.0 * d),
        child: Transform.scale(
          scale: 1 - 0.04 * d,
          alignment: Alignment.bottomCenter,
          child: DeckCardShell(
            height: height,
            tint: c.line,
            raised: false,
            color: d == 1 ? c.surfaceAlt : c.surface,
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
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
                SkeletonBox(width: 20, height: 6, radius: 3),
                SizedBox(width: 10),
                SkeletonBox(width: 6, height: 6, radius: 3),
                SizedBox(width: 10),
                SkeletonBox(width: 6, height: 6, radius: 3),
                SizedBox(width: 10),
                SkeletonBox(width: 6, height: 6, radius: 3),
                SizedBox(width: 14),
                SkeletonBox(width: 34, height: 14, radius: 7),
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
        // v4 head: the title and the period on one line, the chip on the right.
        const Row(
          children: [
            SkeletonBox(width: 150, height: 14, radius: 7),
            Spacer(),
            SkeletonBox(width: 56, height: 22, radius: 8),
          ],
        ),
        const SizedBox(height: 14),
        const Align(
          alignment: AlignmentDirectional.centerStart,
          child: SkeletonBox(width: 210, height: 44, radius: 12),
        ),
        const SizedBox(height: 10),
        const SkeletonLine(widthFactor: 0.7, height: 12),
        if (!compact) ...[
          const Spacer(),
          SizedBox(
            height: 32,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final h in heights)
                  SkeletonBox(width: 22, height: 32 * h, radius: 8),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const SkeletonBox(height: 2, radius: 1),
          const SizedBox(height: 8),
          const Row(
            children: [
              Expanded(child: SkeletonBox(height: 36, radius: 10)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 36, radius: 10)),
              SizedBox(width: 10),
              Expanded(child: SkeletonBox(height: 36, radius: 10)),
            ],
          ),
        ],
      ],
    );
  }
}

/// Yüklenemedi / çevrimdışı: kâğıt kart, yumuşak kuyuda simge, ne olduğu ve "Tekrar dene".
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
      icon: offline
          ? PhosphorIconsRegular.cloudSlash
          : PhosphorIconsRegular.warningCircle,
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

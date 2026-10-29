import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Motion kit — design v3 §5: **a lively, moving app.** Everything that
/// appears, changes or is touched moves; the brand surfaces breathe.
///
/// * Every touch answers: press = scale [pressScale] (0.97) in [press]
///   100 ms, release springs back over [pressOut] 260 ms on [spring];
///   selection indicators (bottom-bar pill, segmented thumb, tab bar) slide
///   on [spring]; icons swap outline → filled with a [pop].
/// * Entrances: [StaggerItem] brings every list item and card in — fade +
///   rise + scale over [stagger] — one after another ([staggerStep]) when a
///   [StaggerScope] opens, and again as items scroll into view (scroll
///   reveal).
/// * Ambient life ([ambient]): the header band's light drifts, "your move"
///   lamps and badges breathe, empty-state art floats, the Sipariş ver key
///   glows — looping through [AknAmbient].
/// * The home moment: the hero card rises ([heroRise] 520 ms), its figure
///   rolls like a pump register ([plateRoll] 900 ms on [roll]), the bars
///   grow ([barsRise], [barsStagger] 40 ms) and the sections stagger in.
/// * Transitions: iOS Cupertino pages (swipe-back), Android predictive back /
///   fade-forwards, tabs fade through; sheets [sheet] 360 ms emphasized,
///   dialogs [dialog] 220 ms, toasts [toastIn] 320 ms on [spring].
/// * Numbers count between values ([count] 600 ms); tabular figures keep
///   their width.
/// * Scroll: the band and large titles react to scrolling (collapse, fade,
///   parallax).
/// * Reduce motion — only when the phone's accessibility setting asks for it
///   (`MediaQuery.disableAnimations`): [of] collapses durations to zero,
///   [animateTo] jumps, ambient loops stop.
abstract final class AknMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
  static const Duration emphasized = Duration(milliseconds: 600);

  // ── The home moment (§5) ──

  /// The deck's top card fades from the paper palette to the plate palette.
  static const Duration plateLight = Duration(milliseconds: 180);

  /// The hero card rises into place on the first home render.
  static const Duration heroRise = Duration(milliseconds: 520);

  /// The plate figure's register roll ([roll] curve).
  static const Duration plateRoll = Duration(milliseconds: 900);

  /// Plate bars rise during the last 300 ms of the roll.
  static const Duration barsRise = Duration(milliseconds: 300);

  /// Delay between two rising bars (see [barDelay]).
  static const Duration barsStagger = Duration(milliseconds: 40);

  /// The dashed projection outline draws in (trim path).
  static const Duration projectionDraw = Duration(milliseconds: 200);

  /// The first-run deck nudge (±10 px wiggle, once, never under reduce
  /// motion).
  static const Duration nudge = Duration(milliseconds: 600);

  // ── Feedback ──

  /// Press in: scale [pressScale].
  static const Duration press = Duration(milliseconds: 100);

  /// Press out (release), on [spring].
  static const Duration pressOut = Duration(milliseconds: 260);

  /// Scale of a pressed row, card, button or key.
  static const double pressScale = 0.97;

  /// A released deck card flies out (easeIn, [fly]).
  static const Duration deckFly = Duration(milliseconds: 240);

  /// The next deck card steps forward.
  static const Duration deckStep = Duration(milliseconds: 260);

  /// The depth-1 card completes its lerp to the plate palette on release.
  static const Duration plateHandoff = Duration(milliseconds: 200);

  /// Approve: the plate stamps 1.02 → 1.
  static const Duration stamp = Duration(milliseconds: 180);

  /// The StageStrip's current ring slides one stop.
  static const Duration stageStep = Duration(milliseconds: 280);

  /// The bottom bar's active pill slides between items ([spring]).
  static const Duration needle = Duration(milliseconds: 320);

  /// The segmented control's thumb and the tab indicator slide ([spring]).
  static const Duration thumb = Duration(milliseconds: 280);

  /// An icon swaps outline → filled (cross-fade + [pop]).
  static const Duration iconSwap = Duration(milliseconds: 180);

  /// The route-line vehicle glides to new progress.
  static const Duration routeGlide = Duration(milliseconds: 400);

  /// Driver: the delivered stop's load-bar segment empties.
  static const Duration loadBarEmpty = Duration(milliseconds: 300);

  /// Driver: the next stop slides into the plate (shared axis).
  static const Duration stopSlide = Duration(milliseconds: 300);

  /// Sheets slide up ([emphasizedCurve]).
  static const Duration sheet = Duration(milliseconds: 360);

  /// Dialogs scale in from 0.94 and fade.
  static const Duration dialog = Duration(milliseconds: 220);

  /// Modal scrim fade.
  static const Duration scrim = Duration(milliseconds: 220);

  /// Toast in (slide + fade, [spring]).
  static const Duration toastIn = Duration(milliseconds: 320);

  /// Toast out.
  static const Duration toastOut = Duration(milliseconds: 200);

  /// The slide-to-confirm knob turns into the ok check.
  static const Duration slideDone = Duration(milliseconds: 300);

  /// The splash draws the logo chevrons in.
  static const Duration logoDraw = Duration(milliseconds: 600);

  /// Skeleton opacity pulse (kept for API stability; see [shimmer]).
  static const Duration skeletonPulse = Duration(milliseconds: 1200);

  /// One sweep of the skeleton shimmer highlight (repeats while loading).
  static const Duration shimmer = Duration(milliseconds: 1400);

  /// A tapped bar's value bubble stays this long.
  static const Duration bubbleHold = Duration(seconds: 2);

  // ── Curves ──

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasizedCurve = Cubic(0.2, 0, 0, 1);
  static const Curve exit = Curves.easeInCubic;

  /// A soft spring: settles with a ~5 % overshoot (indicators, thumbs,
  /// pills, the press release).
  static const Curve spring = Cubic(0.34, 1.36, 0.64, 1);

  /// An icon or badge pops into place (overshoot, then settle).
  static const Curve pop = Curves.easeOutBack;

  /// The register roll: `v(t) = 1 − (1 − t)^3.2`.
  static const Curve roll = RegisterRollCurve();

  /// A released deck card flies out.
  static const Curve fly = Curves.easeIn;

  /// Numbers count between two values ([AnimatedNumber]).
  static const Duration count = Duration(milliseconds: 600);

  /// One staggered entrance ([StaggerItem]).
  static const Duration stagger = Duration(milliseconds: 520);

  /// Delay between two staggered items.
  static const Duration staggerStep = Duration(milliseconds: 55);

  /// Items past this index enter together with the last stepped one (v4
  /// §6: the stagger stops after 6 items).
  static const int staggerMaxItems = 6;

  /// Ambient looping motion ([AknAmbient]): on in the app. The test
  /// configuration switches it off so `pumpAndSettle` can settle.
  static bool ambient = true;

  /// True when ambient loops may run at [context] ([ambient] and no reduce
  /// motion).
  static bool ambientOf(BuildContext context) => ambient && !reduced(context);

  /// One cycle of the band's drifting light.
  static const Duration bandDrift = Duration(seconds: 9);

  /// One breath of a live lamp, badge or the Sipariş ver glow.
  static const Duration breathe = Duration(milliseconds: 1800);

  /// One float cycle of empty-state art.
  static const Duration float = Duration(milliseconds: 3200);

  // ── v4 "Sade" (§6) ──

  /// A `?focus=` arrival: the block scrolls into view…
  static const Duration focusScroll = Duration(milliseconds: 400);

  /// …then, after [focusDelay], a `brandSoft` wash fades out over
  /// [focusFlash] (reduce motion: a static tint for [focusStatic]).
  static const Duration focusFlash = Duration(milliseconds: 900);
  static const Duration focusDelay = Duration(milliseconds: 120);
  static const Duration focusStatic = Duration(seconds: 1);

  /// Task done: the tile stamps its check…
  static const Duration taskStamp = Duration(milliseconds: 180);

  /// …then the row folds away (size) while it fades ([taskFade]).
  static const Duration taskFold = Duration(milliseconds: 400);
  static const Duration taskFade = Duration(milliseconds: 250);

  /// A primary's label morph: the old label leaves upward, the new one
  /// springs in from below.
  static const Duration labelOut = Duration(milliseconds: 120);
  static const Duration labelIn = Duration(milliseconds: 220);

  /// The » line's first draw (emphasized) and its hop to the next stop.
  static const Duration flowDraw = Duration(milliseconds: 600);
  static const Duration flowHop = Duration(milliseconds: 420);

  /// A ledger's rows pour in after it rises: 8 dp, this far apart.
  static const Duration rowPour = Duration(milliseconds: 40);

  /// The band status line and the search strip fade through.
  static const Duration statusFade = Duration(milliseconds: 250);

  /// True when the platform asks for reduced motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [d], or zero under reduce motion.
  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;

  /// [curve], or [Curves.linear] under reduce motion (a zero-length
  /// animation needs no easing; keeps spring overshoot out of jumps).
  static Curve curveOf(BuildContext context, Curve curve) =>
      reduced(context) ? Curves.linear : curve;

  /// Drives [controller] to [target] over [duration] on [curve]; under reduce
  /// motion it jumps there at once (the final frame is drawn immediately).
  static TickerFuture animateTo(
    BuildContext context,
    AnimationController controller,
    double target, {
    Duration? duration,
    Curve curve = standard,
  }) {
    if (reduced(context)) {
      controller.value = target;
      return TickerFuture.complete();
    }
    return controller.animateTo(target, duration: duration, curve: curve);
  }

  /// Delay of the plate bar at [index] (0-based) within [barsRise].
  static Duration barDelay(int index) => barsStagger * (index < 0 ? 0 : index);

  /// The register-roll progress at linear time [t] (0–1): `1 − (1 − t)^3.2`.
  static double rollProgress(double t) => roll.transform(t.clamp(0.0, 1.0));

  /// Delay of the staggered item at [index] (0-based).
  static Duration staggerDelay(int index) =>
      staggerStep * index.clamp(0, staggerMaxItems);
}

/// The pump-register easing of the plate figure (§8.1): `1 − (1 − t)^e`
/// with e = 3.2 — a fast start and a long mechanical settle.
class RegisterRollCurve extends Curve {
  const RegisterRollCurve([this.exponent = 3.2]);

  final double exponent;

  @override
  double transformInternal(double t) =>
      1 - math.pow(1 - t, exponent).toDouble();
}

/// [AnimatedSize] that respects reduce motion: under `disableAnimations` the
/// child is laid out directly (a zero-duration `AnimatedSize` trips Flutter's
/// "RenderAnimatedSize was mutated in its own performLayout" assertion when the
/// child changes size).
class AknAnimatedSize extends StatelessWidget {
  const AknAnimatedSize({
    super.key,
    required this.child,
    this.duration = AknMotion.base,
    this.curve = AknMotion.standard,
    this.alignment = Alignment.center,
  });

  final Widget child;
  final Duration duration;
  final Curve curve;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    if (AknMotion.reduced(context) || duration == Duration.zero) return child;
    return AnimatedSize(
      duration: duration,
      curve: curve,
      alignment: alignment,
      child: child,
    );
  }
}

/// Haptic vocabulary. Soft by design: light taps for presses, selection
/// clicks for tabs and chips, a medium impact for confirmed success.
abstract final class AknHaptics {
  /// Tests and the dev gallery may switch haptics off.
  static bool enabled = true;

  static void light() => _run(HapticFeedback.lightImpact);
  static void selection() => _run(HapticFeedback.selectionClick);
  static void medium() => _run(HapticFeedback.mediumImpact);

  /// Success (order sent, delivery confirmed): one soft medium impact.
  static void success() => _run(HapticFeedback.mediumImpact);

  /// Validation error or blocked action.
  static void warning() => _run(HapticFeedback.heavyImpact);

  static void _run(Future<void> Function() f) {
    if (!enabled) return;
    unawaited(f());
  }
}

/// Fades its child in while lifting it by [offset] px and growing it from
/// [scale]. Plays once, when first built; under reduce motion the child is
/// shown at once.
class FadeUp extends StatefulWidget {
  const FadeUp({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 320),
    this.offset = 12,
    this.curve = AknMotion.standard,
    this.scale = 1,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;
  final Curve curve;

  /// Starting scale (1 = no scale), e.g. 0.96 for the hero card.
  final double scale;

  @override
  State<FadeUp> createState() => _FadeUpState();
}

class _FadeUpState extends State<FadeUp> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final CurvedAnimation _t = CurvedAnimation(
    parent: _c,
    curve: widget.curve,
  );
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // One fixed structure from the first frame to the last, so the child
    // keeps its state when the entrance ends.
    return FadeTransition(
      opacity: _t,
      child: AnimatedBuilder(
        animation: _t,
        child: widget.child,
        builder: (context, child) {
          final v = _t.value;
          return Transform.translate(
            offset: Offset(0, widget.offset * (1 - v)),
            child: Transform.scale(
              scale: widget.scale + (1 - widget.scale) * v,
              child: child,
            ),
          );
        },
      ),
    );
  }
}

/// Marks the moment a list appeared (v3 §5): [StaggerItem]s first built
/// within [window] of the scope's first build enter one after another
/// ([AknMotion.staggerStep] apart); items built later (scrolling, the next
/// page) still slide in, at once, as they scroll into view. Give the scope a
/// new key to replay the cascade (e.g. a new filter).
///
/// ```dart
/// StaggerScope(
///   child: ListView.builder(
///     itemBuilder: (context, i) => StaggerItem(index: i, child: OrderCard(...)),
///   ),
/// )
/// ```
class StaggerScope extends StatefulWidget {
  const StaggerScope({
    super.key,
    required this.child,
    this.window = const Duration(milliseconds: 700),
  });

  final Widget child;

  /// How long after the first build new items still enter.
  final Duration window;

  @override
  State<StaggerScope> createState() => _StaggerScopeState();
}

class _StaggerScopeState extends State<StaggerScope> {
  Timer? _timer;
  bool _open = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.window, () => _open = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _StaggerScopeMarker(scope: this, child: widget.child);
}

class _StaggerScopeMarker extends InheritedWidget {
  const _StaggerScopeMarker({required this.scope, required super.child});

  final _StaggerScopeState scope;

  @override
  bool updateShouldNotify(_StaggerScopeMarker old) => old.scope != scope;
}

/// One list item or card (v3 §5): when first built it fades in, rises 24 px
/// and grows from 0.96 over [AknMotion.stagger] on the emphasized curve.
/// Inside an open [StaggerScope] (or with no scope) it waits [index] ×
/// [AknMotion.staggerStep] (capped at [AknMotion.staggerMaxItems]); after the
/// scope's window it enters at once — the scroll reveal. Under reduce motion
/// it renders its child directly.
class StaggerItem extends StatefulWidget {
  const StaggerItem({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<StaggerItem> createState() => _StaggerItemState();
}

class _StaggerItemState extends State<StaggerItem>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;
  CurvedAnimation? _t;
  Timer? _timer;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (AknMotion.reduced(context)) return;
    final scope = context
        .getInheritedWidgetOfExactType<_StaggerScopeMarker>()
        ?.scope;
    final cascade = scope == null || scope._open;
    final c = AnimationController(vsync: this, duration: AknMotion.stagger);
    _c = c;
    _t = CurvedAnimation(parent: c, curve: AknMotion.emphasizedCurve);
    final delay = cascade
        ? AknMotion.staggerDelay(widget.index)
        : Duration.zero;
    if (delay == Duration.zero) {
      c.forward();
    } else {
      _timer = Timer(delay, () {
        if (mounted) c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _t?.dispose();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t == null) return widget.child;
    // One fixed structure until disposed, so the child keeps its state when
    // the entrance ends.
    return FadeTransition(
      opacity: t,
      child: AnimatedBuilder(
        animation: t,
        child: widget.child,
        builder: (context, child) {
          final v = t.value;
          return Transform.translate(
            offset: Offset(0, 24 * (1 - v)),
            child: Transform.scale(scale: 0.96 + 0.04 * v, child: child),
          );
        },
      ),
    );
  }
}

/// What an ambient loop is for (v4 §6 "loop budget"): a viewport holds the
/// band light, decorative life and **one** focus loop; an urgent loop always
/// runs and pauses the focus loop while it is on screen.
enum AknAmbientRole {
  /// Decorative life (the band light, floating empty-state art, the key
  /// glow): never budgeted.
  decorative,

  /// The one "your move" loop of the viewport: the halo on the home's lead
  /// tile, the » ping on a detail page, a focus lamp. Only the first focus
  /// loop that joins an [AknAmbientBudget] runs; the others hold their rest
  /// value until it leaves.
  focus,

  /// A countdown at 30 min or less: always breathes and pauses the focus
  /// loop of its budget while it is mounted.
  urgent,
}

/// A looping ambient animation (v3 §5): rebuilds [builder] with `t` going
/// 0 → 1 every [period] ([reverse]: 0 → 1 → 0). Paused offstage (ticker
/// mode); when [AknMotion.ambientOf] is false (tests, reduce motion) it
/// holds `t` = [restValue].
///
/// * [role] (v4 §6): a [AknAmbientRole.focus] or [AknAmbientRole.urgent]
///   loop joins the nearest [AknAmbientBudget] (`AppScaffold` installs one
///   per page), which lets one focus loop run per viewport.
/// * [cycles]: breathe that many times, then rest ([restValue]); a new
///   [replay] value plays the cycles again (badges: "pop, breathe 3 cycles,
///   then rest").
///
/// ```dart
/// AknAmbient(
///   period: AknMotion.breathe,
///   reverse: true,
///   builder: (context, t, child) => Transform.scale(scale: 1 + 0.06 * t, child: child),
///   child: badge,
/// )
/// ```
class AknAmbient extends StatefulWidget {
  const AknAmbient({
    super.key,
    required this.period,
    required this.builder,
    this.child,
    this.reverse = false,
    this.curve = Curves.easeInOut,
    this.restValue = 0,
    this.role = AknAmbientRole.decorative,
    this.cycles,
    this.replay,
  });

  final Duration period;
  final Widget Function(BuildContext context, double t, Widget? child) builder;
  final Widget? child;
  final bool reverse;
  final Curve curve;

  /// The value shown while ambient motion is off.
  final double restValue;

  /// Decorative, focus or urgent (see [AknAmbientBudget]).
  final AknAmbientRole role;

  /// Breathe this many cycles, then rest (null: loop while shown; 0: rest).
  final int? cycles;

  /// A new value replays the [cycles].
  final Object? replay;

  /// Number of ambient loops animating right now (tests: the loop budget).
  @visibleForTesting
  static int get debugRunningCount => _AknAmbientState._running.length;

  @override
  State<AknAmbient> createState() => _AknAmbientState();
}

class _AknAmbientState extends State<AknAmbient>
    with SingleTickerProviderStateMixin {
  static final Set<_AknAmbientState> _running = <_AknAmbientState>{};

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  );
  late final CurvedAnimation _t = CurvedAnimation(
    parent: _c,
    curve: widget.curve,
  );
  AknAmbientBudgetState? _budget;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener(_onStatus);
  }

  void _onStatus(AnimationStatus status) {
    // A finite run ([AknAmbient.cycles]) ended: rest. (A repeat reports its
    // first direction before its ticker starts, so only an end counts.)
    if (status.isCompleted || status.isDismissed) _running.remove(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final budget = AknAmbientBudget._of(context);
    if (!identical(budget, _budget)) {
      _budget?._leave(this);
      _budget = budget;
      budget?._join(this);
    }
    _sync();
  }

  @override
  void didUpdateWidget(AknAmbient old) {
    super.didUpdateWidget(old);
    if (old.period != widget.period) _c.duration = widget.period;
    if (old.curve != widget.curve) _t.curve = widget.curve;
    if (old.role != widget.role) {
      _budget?._leave(this);
      _budget?._join(this);
    }
    final replay = old.replay != widget.replay || old.cycles != widget.cycles;
    if (old.reverse != widget.reverse || replay) {
      _c.stop();
      _running.remove(this);
      _sync(restart: replay);
    } else {
      _sync();
    }
  }

  /// Called by the budget when the focus holder changes.
  void _budgetChanged() {
    if (mounted) _sync();
  }

  bool get _allowed =>
      AknMotion.ambientOf(context) &&
      (widget.cycles == null || widget.cycles! > 0) &&
      (_budget?._allows(this) ?? true);

  bool _played = false;

  void _sync({bool restart = false}) {
    if (_allowed) {
      if (_c.isAnimating) return;
      final cycles = widget.cycles;
      if (cycles != null) {
        if (_played && !restart) return;
        _played = true;
        _c.value = 0;
        _c.repeat(
          reverse: widget.reverse,
          count: widget.reverse ? cycles * 2 : cycles,
        );
        _running.add(this);
        return;
      }
      _c.repeat(reverse: widget.reverse);
      _running.add(this);
    } else {
      _running.remove(this);
      _c.stop();
      _c.value = widget.restValue;
    }
  }

  @override
  void dispose() {
    _running.remove(this);
    _budget?._leave(this);
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    child: widget.child,
    builder: (context, child) => widget.builder(context, _t.value, child),
  );
}

/// The loop budget of one viewport (v4 §6): installed by `AppScaffold`
/// around each page. Decorative loops always run; the **first** focus loop
/// that joins runs and the others rest until it leaves; while an urgent
/// loop is mounted the focus loop rests too. Nothing runs under reduce
/// motion (see [AknMotion.ambientOf]).
class AknAmbientBudget extends StatefulWidget {
  const AknAmbientBudget({super.key, required this.child});

  final Widget child;

  static AknAmbientBudgetState? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AmbientBudgetScope>()?.state;

  /// True when [context] sits under a budget.
  static bool isIn(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_AmbientBudgetScope>() != null;

  @override
  State<AknAmbientBudget> createState() => AknAmbientBudgetState();
}

class AknAmbientBudgetState extends State<AknAmbientBudget> {
  final List<_AknAmbientState> _focus = <_AknAmbientState>[];
  final Set<_AknAmbientState> _urgent = <_AknAmbientState>{};
  bool _scheduled = false;

  void _join(_AknAmbientState s) {
    switch (s.widget.role) {
      case AknAmbientRole.decorative:
        return;
      case AknAmbientRole.focus:
        if (!_focus.contains(s)) _focus.add(s);
      case AknAmbientRole.urgent:
        _urgent.add(s);
    }
    _changed();
  }

  void _leave(_AknAmbientState s) {
    final removed = _focus.remove(s) | _urgent.remove(s);
    if (removed) _changed();
  }

  bool _allows(_AknAmbientState s) => switch (s.widget.role) {
    AknAmbientRole.decorative || AknAmbientRole.urgent => true,
    AknAmbientRole.focus =>
      _urgent.isEmpty && _focus.isNotEmpty && identical(_focus.first, s),
  };

  /// Re-syncs the focus loops after the frame (joins happen while building).
  void _changed() {
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      for (final s in List<_AknAmbientState>.of(_focus)) {
        s._budgetChanged();
      }
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) =>
      _AmbientBudgetScope(state: this, child: widget.child);
}

class _AmbientBudgetScope extends InheritedWidget {
  const _AmbientBudgetScope({required this.state, required super.child});

  final AknAmbientBudgetState state;

  @override
  bool updateShouldNotify(_AmbientBudgetScope old) => old.state != state;
}

/// Wraps [children] (e.g. of a Column) in [StaggerItem]s.
List<Widget> staggered(List<Widget> children) => [
  for (var i = 0; i < children.length; i++)
    StaggerItem(index: i, child: children[i]),
];

/// Scales its child to [AknMotion.pressScale] (0.97) while pressed: 100 ms
/// in, a 260 ms spring back on release (v3 §5). Uses raw pointer events, so it never competes with the
/// child's gestures. Static under reduce motion.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.scale = AknMotion.pressScale,
  });

  final Widget child;
  final bool enabled;
  final double scale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool v) {
    if (!widget.enabled || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AknMotion.reduced(context);
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down && !reduced ? widget.scale : 1,
        duration: _down ? AknMotion.press : AknMotion.pressOut,
        curve: _down ? AknMotion.standard : AknMotion.spring,
        child: widget.child,
      ),
    );
  }
}

// ───────────────────────── Transitions ─────────────────────────

final Animatable<double> _sharedAxisFadeIn = CurveTween(
  curve: const Interval(0.3, 1, curve: Curves.easeOut),
);
final Animatable<double> _sharedAxisFadeOut = CurveTween(
  curve: const Interval(0, 0.3, curve: Curves.easeIn),
);
final Animatable<double> _fadeThroughIn = CurveTween(
  curve: const Interval(0.35, 1, curve: Curves.easeOut),
);
final Animatable<double> _fadeThroughOut = CurveTween(
  curve: const Interval(0, 0.35, curve: Curves.easeIn),
);

/// Material shared-axis X transition (drill-down): the incoming page slides
/// 30 px in from the trailing side and fades in; the outgoing page slides
/// 30 px out and fades out first. Ported from the `animations` package
/// pattern on top of the SDK's [DualTransitionBuilder].
class AknSharedAxisTransition extends StatelessWidget {
  const AknSharedAxisTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
    this.fillColor,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  /// Painted behind the outgoing page so nothing shows through the fade.
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    final fill = fillColor ?? Theme.of(context).scaffoldBackgroundColor;
    // The page below (secondary animation) keeps an opaque fill outside its
    // fade, so the gap between fade-out and fade-in never shows the window.
    return DualTransitionBuilder(
      animation: animation,
      forwardBuilder: (context, a, child) =>
          _AxisEnter(animation: a, reverse: false, child: child),
      reverseBuilder: (context, a, child) =>
          _AxisExit(animation: a, reverse: true, child: child),
      child: DualTransitionBuilder(
        animation: ReverseAnimation(secondaryAnimation),
        forwardBuilder: (context, a, child) => ColoredBox(
          color: fill,
          child: _AxisEnter(animation: a, reverse: true, child: child),
        ),
        reverseBuilder: (context, a, child) => ColoredBox(
          color: fill,
          child: _AxisExit(animation: a, reverse: false, child: child),
        ),
        child: child,
      ),
    );
  }
}

class _AxisEnter extends StatelessWidget {
  const _AxisEnter({
    required this.animation,
    required this.reverse,
    required this.child,
  });

  final Animation<double> animation;
  final bool reverse;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final dir = Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
    final from = (reverse ? -30.0 : 30.0) * dir;
    return FadeTransition(
      opacity: _sharedAxisFadeIn.animate(animation),
      child: AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final t = AknMotion.emphasizedCurve.transform(animation.value);
          return Transform.translate(
            offset: Offset(from * (1 - t), 0),
            child: child,
          );
        },
      ),
    );
  }
}

class _AxisExit extends StatelessWidget {
  const _AxisExit({
    required this.animation,
    required this.reverse,
    required this.child,
  });

  final Animation<double> animation;
  final bool reverse;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final dir = Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
    final to = (reverse ? 30.0 : -30.0) * dir;
    return FadeTransition(
      opacity: ReverseAnimation(_sharedAxisFadeOut.animate(animation)),
      child: AnimatedBuilder(
        animation: animation,
        child: child,
        builder: (context, child) {
          final t = AknMotion.emphasizedCurve.transform(animation.value);
          return Transform.translate(offset: Offset(to * t, 0), child: child);
        },
      ),
    );
  }
}

/// Page transitions for [PageTransitionsTheme] on Android: shared axis X,
/// 400 ms in, 300 ms back. Under reduce motion pages switch instantly.
///
/// iOS keeps [CupertinoPageTransitionsBuilder] so the edge swipe-back gesture
/// keeps working (see `AknTheme`).
class AknSharedAxisPageTransitionsBuilder extends PageTransitionsBuilder {
  const AknSharedAxisPageTransitionsBuilder();

  @override
  Duration get transitionDuration => AknMotion.slow;

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AknMotion.reduced(context)) return child;
    return AknSharedAxisTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

/// Android page transitions (spec D.7): Flutter's predictive back (Android 14+
/// back gesture previews the previous page; `enableOnBackInvokedCallback` is on
/// in the manifest), Android's fade-forwards for button navigation. Under
/// reduce motion pages switch instantly.
class AknPredictiveBackPageTransitionsBuilder extends PageTransitionsBuilder {
  const AknPredictiveBackPageTransitionsBuilder();

  static const _platform = PredictiveBackPageTransitionsBuilder();

  @override
  Duration get transitionDuration => _platform.transitionDuration;

  @override
  Duration get reverseTransitionDuration => _platform.reverseTransitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AknMotion.reduced(context)) return child;
    return _platform.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}

/// Material fade-through: the outgoing child fades out in the first 35 %,
/// the incoming one fades in and settles from 92 % scale. For swapping
/// unrelated content (tabs, loading → content).
class AknFadeThroughTransition extends StatelessWidget {
  const AknFadeThroughTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
    this.fillColor,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;
  final Color? fillColor;

  @override
  Widget build(BuildContext context) {
    final fill = fillColor ?? Theme.of(context).scaffoldBackgroundColor;
    return DualTransitionBuilder(
      animation: animation,
      forwardBuilder: (context, a, child) =>
          _ZoomedFadeIn(animation: a, child: child),
      reverseBuilder: (context, a, child) =>
          _FadeOut(animation: a, child: child),
      child: DualTransitionBuilder(
        animation: ReverseAnimation(secondaryAnimation),
        forwardBuilder: (context, a, child) => ColoredBox(
          color: fill,
          child: _ZoomedFadeIn(animation: a, child: child),
        ),
        reverseBuilder: (context, a, child) => ColoredBox(
          color: fill,
          child: _FadeOut(animation: a, child: child),
        ),
        child: child,
      ),
    );
  }
}

class _ZoomedFadeIn extends StatelessWidget {
  const _ZoomedFadeIn({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final fade = _fadeThroughIn.animate(animation);
    return FadeTransition(
      opacity: fade,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1).animate(fade),
        child: child,
      ),
    );
  }
}

class _FadeOut extends StatelessWidget {
  const _FadeOut({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: ReverseAnimation(_fadeThroughOut.animate(animation)),
      child: child,
    );
  }
}

/// Page transitions builder that fades through (used for top-level swaps).
class AknFadeThroughPageTransitionsBuilder extends PageTransitionsBuilder {
  const AknFadeThroughPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (AknMotion.reduced(context)) return child;
    return AknFadeThroughTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

/// An [IndexedStack] that fades through when [index] changes (tab switch).
///
/// Every child keeps its state; inactive children are offstage with tickers
/// muted. Built for `StatefulShellRoute`'s `navigatorContainerBuilder`:
///
/// ```dart
/// navigatorContainerBuilder: (context, shell, children) =>
///     FadeThroughIndexedStack(index: shell.currentIndex, children: children),
/// ```
class FadeThroughIndexedStack extends StatefulWidget {
  const FadeThroughIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 300),
  });

  final int index;
  final List<Widget> children;
  final Duration duration;

  @override
  State<FadeThroughIndexedStack> createState() =>
      _FadeThroughIndexedStackState();
}

class _FadeThroughIndexedStackState extends State<FadeThroughIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );
  int? _previous;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed && _previous != null) {
        setState(() => _previous = null);
      }
    });
  }

  @override
  void didUpdateWidget(FadeThroughIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      if (AknMotion.reduced(context)) {
        _previous = null;
        _c.value = 1;
      } else {
        _previous = old.index;
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fadeIn = _fadeThroughIn.animate(_c);
    final scaleIn = Tween<double>(begin: 0.96, end: 1).animate(fadeIn);
    final fadeOut = ReverseAnimation(_fadeThroughOut.animate(_c));
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.children.length; i++)
          _slot(i, fadeIn, scaleIn, fadeOut),
      ],
    );
  }

  Widget _slot(
    int i,
    Animation<double> fadeIn,
    Animation<double> scaleIn,
    Animation<double> fadeOut,
  ) {
    final current = i == widget.index;
    final previous = i == _previous;
    final visible = current || previous;
    // The widget structure stays identical for every slot and every state,
    // so switching tabs never rebuilds a branch from scratch.
    return KeyedSubtree(
      key: ValueKey<int>(i),
      child: Offstage(
        offstage: !visible,
        child: TickerMode(
          enabled: visible,
          child: IgnorePointer(
            ignoring: !current,
            child: ExcludeSemantics(
              excluding: !current,
              child: FadeTransition(
                opacity: current
                    ? fadeIn
                    : previous
                    ? fadeOut
                    : kAlwaysCompleteAnimation,
                child: ScaleTransition(
                  scale: current ? scaleIn : kAlwaysCompleteAnimation,
                  child: widget.children[i],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated swap of one child for another along the X axis: wizard steps,
/// month pages. Set [reverse] when going back.
class SharedAxisSwitcher extends StatelessWidget {
  const SharedAxisSwitcher({
    super.key,
    required this.child,
    this.reverse = false,
    this.duration = const Duration(milliseconds: 360),
    this.alignment = Alignment.topCenter,
  });

  /// Give each step a distinct key.
  final Widget child;
  final bool reverse;
  final Duration duration;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AknMotion.of(context, duration),
      layoutBuilder: (current, previous) =>
          Stack(alignment: alignment, children: [...previous, ?current]),
      transitionBuilder: (c, animation) {
        final incoming = c.key == child.key;
        final dir = reverse ? -1.0 : 1.0;
        return AnimatedBuilder(
          animation: animation,
          child: c,
          builder: (context, c) {
            final v = animation.value;
            if (incoming) {
              final t = AknMotion.emphasizedCurve.transform(v);
              return Opacity(
                opacity: _sharedAxisFadeIn.transform(v),
                child: Transform.translate(
                  offset: Offset(30 * dir * (1 - t), 0),
                  child: c,
                ),
              );
            }
            final p = 1 - v;
            final t = AknMotion.emphasizedCurve.transform(p);
            return Opacity(
              opacity: 1 - _sharedAxisFadeOut.transform(p),
              child: Transform.translate(
                offset: Offset(-30 * dir * t, 0),
                child: c,
              ),
            );
          },
        );
      },
      child: child,
    );
  }
}

/// Fade-through swap of one child for another (loading → content, filters).
class FadeThroughSwitcher extends StatelessWidget {
  const FadeThroughSwitcher({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 300),
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final Duration duration;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AknMotion.of(context, duration),
      layoutBuilder: (current, previous) =>
          Stack(alignment: alignment, children: [...previous, ?current]),
      transitionBuilder: (c, animation) {
        final incoming = c.key == child.key;
        return AnimatedBuilder(
          animation: animation,
          child: c,
          builder: (context, c) {
            final v = animation.value;
            if (incoming) {
              final f = _fadeThroughIn.transform(v);
              return Opacity(
                opacity: f,
                child: Transform.scale(scale: 0.96 + 0.04 * f, child: c),
              );
            }
            return Opacity(
              opacity: 1 - _fadeThroughOut.transform(1 - v),
              child: c,
            );
          },
        );
      },
      child: child,
    );
  }
}

// ───────────────────────── Heroes ─────────────────────────

/// Hero tags shared by list cards and detail screens (container transform).
abstract final class AknHeroTags {
  static String orderCard(Object id) => 'akn-order-card-$id';
  static String orderNumber(Object id) => 'akn-order-number-$id';
  static String orderStatus(Object id) => 'akn-order-status-$id';
  static String shipmentCard(Object id) => 'akn-shipment-card-$id';
  static String shipmentStatus(Object id) => 'akn-shipment-status-$id';
  static String approvalCard(Object id) => 'akn-approval-card-$id';
  static String approvalStatus(Object id) => 'akn-approval-status-$id';
}

/// Container-transform-style hero: the card's surface morphs into the detail
/// header (size, colour, radius) while the two contents cross-fade. Put the
/// same [tag] on the list card and on the detail header.
///
/// Heroes fly only between routes of the same navigator. For a detail page
/// pushed on the root navigator from a tab, use `AknOpenContainer` instead.
class MorphHero extends StatelessWidget {
  const MorphHero({
    super.key,
    required this.tag,
    required this.child,
    this.color,
    this.radius = AknMorphRadius.card,
  });

  final Object tag;
  final Widget child;

  /// Surface colour of this end of the morph (defaults to the card colour).
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (AknMotion.reduced(context)) return child;
    final surface = color ?? Theme.of(context).cardColor;
    return Hero(
      tag: tag,
      flightShuttleBuilder: _shuttle,
      child: _MorphEnd(color: surface, radius: radius, child: child),
    );
  }

  static Widget _shuttle(
    BuildContext flightContext,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromContext,
    BuildContext toContext,
  ) {
    final fromHero = fromContext.widget as Hero;
    final toHero = toContext.widget as Hero;
    final fromEnd = fromHero.child;
    final toEnd = toHero.child;
    final fromSize = (fromContext.findRenderObject() as RenderBox?)?.size;
    final toSize = (toContext.findRenderObject() as RenderBox?)?.size;
    if (fromEnd is! _MorphEnd ||
        toEnd is! _MorphEnd ||
        fromSize == null ||
        toSize == null) {
      return toHero.child;
    }
    // `animation` always tracks the upper (detail) route: 0 = list, 1 = detail.
    final push = direction == HeroFlightDirection.push;
    final listEnd = push ? fromEnd : toEnd;
    final detailEnd = push ? toEnd : fromEnd;
    final Size listSize = push ? fromSize : toSize;
    final Size detailSize = push ? toSize : fromSize;

    Widget frozen(_MorphEnd end, Size size) => ClipRect(
      child: FittedBox(
        fit: BoxFit.fitWidth,
        alignment: Alignment.topCenter,
        child: SizedBox.fromSize(size: size, child: end.child),
      ),
    );

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final v = animation.value;
        final t = AknMotion.emphasizedCurve.transform(v);
        return Material(
          type: MaterialType.transparency,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color.lerp(listEnd.color, detailEnd.color, t),
              borderRadius: BorderRadius.circular(
                listEnd.radius + (detailEnd.radius - listEnd.radius) * t,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: 1 - _fadeThroughOut.transform(v),
                  child: frozen(listEnd, listSize),
                ),
                Opacity(
                  opacity: _fadeThroughIn.transform(v),
                  child: frozen(detailEnd, detailSize),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Corner radii understood by [MorphHero].
abstract final class AknMorphRadius {
  static const double card = 12;
  static const double header = 0;

  /// The plate (r20).
  static const double hero = 20;
}

class _MorphEnd extends StatelessWidget {
  const _MorphEnd({
    required this.color,
    required this.radius,
    required this.child,
  });

  final Color color;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Material(type: MaterialType.transparency, child: child);
}

/// Hero for small pieces that travel between list and detail (order number,
/// status chip). Keeps text styling intact during the flight.
class AknHero extends StatelessWidget {
  const AknHero({super.key, required this.tag, required this.child});

  final Object tag;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AknMotion.reduced(context)) return child;
    return Hero(
      tag: tag,
      flightShuttleBuilder: (flight, animation, direction, fromCtx, toCtx) {
        final push = direction == HeroFlightDirection.push;
        final target = (push ? toCtx : fromCtx).widget as Hero;
        final source = (push ? fromCtx : toCtx).widget as Hero;
        return Material(
          type: MaterialType.transparency,
          child: DefaultTextStyle(
            style: DefaultTextStyle.of(toCtx).style,
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, _) => Stack(
                fit: StackFit.passthrough,
                children: [
                  Opacity(
                    opacity: 1 - _fadeThroughOut.transform(animation.value),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: source.child,
                    ),
                  ),
                  Opacity(
                    opacity: _fadeThroughIn.transform(animation.value),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: target.child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

// ───────────────────────── v4 "Sade" motion (§6) ─────────────────────────

/// The `?focus=` arrival (v4 §6 Add 5): when [active] (on the first build
/// or when it turns true) the block scrolls into view
/// ([AknMotion.focusScroll]), then after [AknMotion.focusDelay] a `brandSoft`
/// wash over it fades from 100 % to 0 over [AknMotion.focusFlash]. Under
/// reduce motion it jumps into view and holds a static tint for one second.
///
/// ```dart
/// AknFocusFlash(active: focusParamOf(context) == 'quote', child: quotePlate)
/// ```
class AknFocusFlash extends StatefulWidget {
  const AknFocusFlash({
    super.key,
    required this.child,
    this.active = false,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.color,
    this.alignment = 0.08,
  });

  final Widget child;

  /// Play the arrival (once per activation).
  final bool active;
  final BorderRadius borderRadius;

  /// The wash (default `brandSoft`).
  final Color? color;

  /// Where the block lands in the viewport (0 = top).
  final double alignment;

  @override
  State<AknFocusFlash> createState() => _AknFocusFlashState();
}

class _AknFocusFlashState extends State<AknFocusFlash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AknMotion.focusFlash,
    value: 1,
  );
  Timer? _timer;
  bool _played = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.active && !_played) _schedule();
  }

  @override
  void didUpdateWidget(AknFocusFlash old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _played = false;
      _schedule();
    }
  }

  void _schedule() {
    _played = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  Future<void> _play() async {
    if (!mounted) return;
    final reduced = AknMotion.reduced(context);
    _c.value = 0;
    setState(() => _flashing = true);
    try {
      await Scrollable.ensureVisible(
        context,
        alignment: widget.alignment,
        duration: reduced ? Duration.zero : AknMotion.focusScroll,
        curve: AknMotion.emphasizedCurve,
      );
    } on Object {
      // Not in a scrollable: the wash still plays.
    }
    if (!mounted) return;
    _timer?.cancel();
    if (reduced) {
      _timer = Timer(AknMotion.focusStatic, () {
        if (mounted) setState(() => _flashing = false);
      });
      return;
    }
    _timer = Timer(AknMotion.focusDelay, () {
      if (!mounted) return;
      _c.forward(from: 0).whenComplete(() {
        if (mounted) setState(() => _flashing = false);
      });
    });
  }

  bool _flashing = false;

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wash =
        widget.color ??
        Theme.of(context).extension<AknColors>()?.brandSoft ??
        const Color(0xFFFFF1E8);
    // One fixed structure (the block keeps its state); the wash is clear
    // at rest.
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final v = _flashing ? (1 - _c.value) : 0.0;
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            color: wash.withValues(alpha: wash.a * 0.85 * v),
            borderRadius: widget.borderRadius,
          ),
          child: child,
        );
      },
    );
  }
}

/// The task-done fold (v4 §6 Add 2): when [done] turns true it waits for the
/// row's check stamp ([AknMotion.taskStamp]), then folds the row away — its
/// height closes over [AknMotion.taskFold] while it fades over
/// [AknMotion.taskFade] — with a success haptic, and calls [onFolded].
/// Under reduce motion it calls [onFolded] at once.
class AknTaskFold extends StatefulWidget {
  const AknTaskFold({
    super.key,
    required this.child,
    this.done = false,
    this.onFolded,
    this.haptic = true,
  });

  final Widget child;
  final bool done;
  final VoidCallback? onFolded;
  final bool haptic;

  @override
  State<AknTaskFold> createState() => _AknTaskFoldState();
}

class _AknTaskFoldState extends State<AknTaskFold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AknMotion.taskStamp + AknMotion.taskFold,
  );
  late final Animation<double> _size = CurvedAnimation(
    parent: _c,
    curve: Interval(
      AknMotion.taskStamp.inMilliseconds /
          (AknMotion.taskStamp + AknMotion.taskFold).inMilliseconds,
      1,
      curve: AknMotion.emphasizedCurve,
    ),
  ).drive(Tween<double>(begin: 1, end: 0));
  late final Animation<double> _fade = CurvedAnimation(
    parent: _c,
    curve: Interval(
      AknMotion.taskStamp.inMilliseconds /
          (AknMotion.taskStamp + AknMotion.taskFold).inMilliseconds,
      (AknMotion.taskStamp + AknMotion.taskFade).inMilliseconds /
          (AknMotion.taskStamp + AknMotion.taskFold).inMilliseconds,
      curve: Curves.easeOut,
    ),
  ).drive(Tween<double>(begin: 1, end: 0));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.done && !_c.isAnimating && _c.value == 0) _start();
  }

  @override
  void didUpdateWidget(AknTaskFold old) {
    super.didUpdateWidget(old);
    if (widget.done && !old.done) _start();
  }

  void _start() {
    if (widget.haptic) AknHaptics.success();
    if (AknMotion.reduced(context)) {
      _c.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onFolded?.call();
      });
      return;
    }
    _c.forward(from: 0).whenComplete(() {
      if (mounted) widget.onFolded?.call();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizeTransition(
    sizeFactor: _size,
    axisAlignment: -1,
    child: FadeTransition(opacity: _fade, child: widget.child),
  );
}

/// Rows that pour into a ledger once it has risen (v4 §6 Entrances): each
/// row fades in and rises 8 dp, [AknMotion.rowPour] apart, at most six
/// steps; only on the first build (never on a tab return or a refresh).
/// Static under reduce motion.
class AknRowPour extends StatefulWidget {
  const AknRowPour({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<AknRowPour> createState() => _AknRowPourState();
}

class _AknRowPourState extends State<AknRowPour>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;
  Timer? _timer;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (AknMotion.reduced(context)) return;
    final c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _c = c;
    final delay =
        const Duration(milliseconds: 120) +
        AknMotion.rowPour * widget.index.clamp(0, AknMotion.staggerMaxItems);
    _timer = Timer(delay, () {
      if (mounted) c.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) return widget.child;
    return AnimatedBuilder(
      animation: c,
      child: widget.child,
      // One fixed structure until disposed (the row keeps its state).
      builder: (context, child) {
        final v = AknMotion.standard.transform(c.value);
        return Opacity(
          opacity: v,
          alwaysIncludeSemantics: true,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - v)),
            child: child,
          ),
        );
      },
    );
  }
}

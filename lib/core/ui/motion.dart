import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Motion kit — design v2 §8: **one orchestrated moment; everything else
/// moves only in answer to a touch.**
///
/// * The moment ("sayaç dönüşü", the first home render of a session): the
///   plate lights ([plateLight] 180 ms, easeOutCubic), its figure rolls like
///   a mechanical pump register ([plateRoll] 900 ms on the [roll] curve),
///   then the bars rise during the last 300 ms ([barsRise], [barsStagger]
///   40 ms) and the projection outline draws in ([projectionDraw]).
/// * Feedback: press = pressed fill + scale 0.98 ([press] 90 ms in,
///   [pressOut] 120 ms out); deck fly-out [deckFly] 240 ms ([fly]), the next
///   card steps forward [deckStep] 220 ms, plate hand-off [plateHandoff]
///   200 ms; tab needle [needle] 200 ms ([spring]); segmented thumb [thumb]
///   220 ms; approve stamp [stamp] 160 ms then the stage ring slides
///   [stageStep] 240 ms; route vehicle glides [routeGlide] 400 ms; sheets
///   [sheet] 250 ms (emphasized) with a [scrim] 200 ms fade; toasts
///   [toastIn] 200 ms / [toastOut] 150 ms.
/// * Never (§8.3): section fade-ups or staggered list entrances
///   ([StaggerItem] renders its child directly), shimmer on loaded content,
///   parallax, auto-advancing carousels, count-ups on numbers, loops other
///   than loading spinners.
/// * Reduce motion (`MediaQuery.disableAnimations`): [of] collapses every
///   duration to zero, [animateTo] jumps to the target, and the roll draws
///   its final frame at once.
abstract final class AknMotion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
  static const Duration emphasized = Duration(milliseconds: 600);

  // ── The one orchestrated moment (§8.1) ──

  /// The deck's top card fades from the paper palette to the plate palette.
  static const Duration plateLight = Duration(milliseconds: 180);

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

  // ── Feedback (§8.2) ──

  /// Press in: pressed fill + scale [pressScale].
  static const Duration press = Duration(milliseconds: 90);

  /// Press out (release).
  static const Duration pressOut = Duration(milliseconds: 120);

  /// Scale of a pressed row, button or key.
  static const double pressScale = 0.98;

  /// A released deck card flies out (easeIn, [fly]).
  static const Duration deckFly = Duration(milliseconds: 240);

  /// The next deck card steps forward.
  static const Duration deckStep = Duration(milliseconds: 220);

  /// The depth-1 card completes its lerp to the plate palette on release.
  static const Duration plateHandoff = Duration(milliseconds: 200);

  /// Approve: the plate stamps 1.02 → 1.
  static const Duration stamp = Duration(milliseconds: 160);

  /// The StageStrip's current ring slides one stop.
  static const Duration stageStep = Duration(milliseconds: 240);

  /// The bottom bar's needle slides between items ([spring]).
  static const Duration needle = Duration(milliseconds: 200);

  /// The segmented control's thumb slides.
  static const Duration thumb = Duration(milliseconds: 220);

  /// The route-line vehicle glides to new progress.
  static const Duration routeGlide = Duration(milliseconds: 400);

  /// Driver: the delivered stop's load-bar segment empties.
  static const Duration loadBarEmpty = Duration(milliseconds: 300);

  /// Driver: the next stop slides into the plate (shared axis).
  static const Duration stopSlide = Duration(milliseconds: 280);

  /// Sheets slide up ([emphasizedCurve]).
  static const Duration sheet = Duration(milliseconds: 250);

  /// Modal scrim fade.
  static const Duration scrim = Duration(milliseconds: 200);

  /// Toast in (slide up + fade).
  static const Duration toastIn = Duration(milliseconds: 200);

  /// Toast out.
  static const Duration toastOut = Duration(milliseconds: 150);

  /// The slide-to-confirm knob turns into the ok check.
  static const Duration slideDone = Duration(milliseconds: 300);

  /// The splash draws the logo chevrons in.
  static const Duration logoDraw = Duration(milliseconds: 600);

  /// Skeleton opacity pulse 1 → 0.55 → 1 (static under reduce motion).
  static const Duration skeletonPulse = Duration(milliseconds: 1200);

  /// A tapped bar's value bubble stays this long.
  static const Duration bubbleHold = Duration(seconds: 2);

  // ── Curves ──

  static const Curve standard = Curves.easeOutCubic;
  static const Curve emphasizedCurve = Cubic(0.2, 0, 0, 1);
  static const Curve exit = Curves.easeInCubic;

  /// A soft spring: settles with a ~3 % overshoot (the bottom bar needle,
  /// selection thumbs). Calm, never bouncy.
  static const Curve spring = Cubic(0.32, 1.28, 0.58, 1);

  /// The register roll: `v(t) = 1 − (1 − t)^3.2` (§8.1).
  static const Curve roll = RegisterRollCurve();

  /// A released deck card flies out.
  static const Curve fly = Curves.easeIn;

  /// Deprecated: count-ups are gone in v2 (`AnimatedNumber` renders the
  /// final value; only the plate rolls). Kept for API stability.
  static const Duration count = Duration(milliseconds: 700);

  /// Deprecated: list entrances are gone in v2 ([StaggerItem] renders its
  /// child directly). Kept for API stability.
  static const Duration staggerStep = Duration(milliseconds: 30);
  static const int staggerMaxItems = 8;

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

  /// Delay of the list item at [index] (0-based). Deprecated with
  /// [staggerStep].
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

/// Fades its child in while lifting it by [offset] px. Plays once, when first
/// built; under reduce motion the child is shown at once.
class FadeUp extends StatefulWidget {
  const FadeUp({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 320),
    this.offset = 12,
    this.curve = AknMotion.standard,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;
  final Curve curve;

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
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) {
        final v = _t.value;
        if (v >= 1) return child!;
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - v)),
            child: child,
          ),
        );
      },
    );
  }
}

/// Marks the moment a list appeared. v2 (§8.3): list entrances are gone, so
/// nothing animates under it any more ([StaggerItem] renders its child
/// directly); kept so existing call sites compile.
///
/// ```dart
/// StaggerScope(
///   child: ListView.builder(
///     itemBuilder: (context, i) => StaggerItem(index: i, child: OrderCard(...)),
///   ),
/// )
/// ```
class StaggerScope extends StatelessWidget {
  const StaggerScope({
    super.key,
    required this.child,
    this.window = const Duration(milliseconds: 700),
  });

  final Widget child;

  /// Deprecated: no entrance window any more (kept for API stability).
  final Duration window;

  @override
  Widget build(BuildContext context) => child;
}

/// One list item. v2 (§8.3): no staggered list entrances — it renders its
/// child directly. Kept so existing call sites compile.
class StaggerItem extends StatelessWidget {
  const StaggerItem({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Wraps [children] (e.g. of a Column) in [StaggerItem]s.
List<Widget> staggered(List<Widget> children) => [
  for (var i = 0; i < children.length; i++)
    StaggerItem(index: i, child: children[i]),
];

/// Scales its child to [AknMotion.pressScale] (0.98) while pressed: 90 ms in,
/// 120 ms out (§8.2). Uses raw pointer events, so it never competes with the
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
        curve: AknMotion.standard,
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

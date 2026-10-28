import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';

/// Pull-to-refresh (design v3 §5) with an orange ring in a white puck: the
/// ring winds up as you pull, the puck pops when the pull is far enough,
/// stretches like a drop if you keep pulling, springs to its resting place
/// on release and spins while [onRefresh] works, then fades. Gesture
/// handling is Flutter's own [RefreshIndicator] (both bouncing and clamping
/// physics); only the visual is ours. Reduce motion: no pop, no stretch, a
/// still ring while refreshing.
///
/// The child must be a scrollable that can always scroll
/// (`physics: const AlwaysScrollableScrollPhysics()` for short lists).
class PullToRefresh extends StatefulWidget {
  const PullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.edgeOffset = 0,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  /// Space above the list's first item (e.g. a pinned header).
  final double edgeOffset;

  @override
  State<PullToRefresh> createState() => _PullToRefreshState();
}

class _PullToRefreshState extends State<PullToRefresh>
    with TickerProviderStateMixin {
  RefreshIndicatorStatus? _status;
  double _drag = 0;
  double _viewport = 600;
  bool _tracking = false;

  /// The spinner while refreshing (only while it works, and only when
  /// looping motion is allowed).
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// The pop when the pull arms: 1 → 1.16 → 1 on the spring.
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );

  static final Animatable<double> _popScale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1,
        end: 1.16,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 30,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.16,
        end: 1,
      ).chain(CurveTween(curve: AknMotion.spring)),
      weight: 70,
    ),
  ]);

  bool get _active =>
      _status == RefreshIndicatorStatus.drag ||
      _status == RefreshIndicatorStatus.armed;

  bool get _refreshing =>
      _status == RefreshIndicatorStatus.refresh ||
      _status == RefreshIndicatorStatus.snap;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    _viewport = n.metrics.viewportDimension;
    if (n is ScrollStartNotification) {
      _tracking = n.dragDetails != null && n.metrics.extentBefore == 0;
      if (_tracking) _drag = 0;
    } else if (n is ScrollUpdateNotification && _tracking && _active) {
      if (n.metrics.pixels < 0) {
        setState(() => _drag = -n.metrics.pixels);
      } else if (n.scrollDelta != null && n.scrollDelta! > 0) {
        setState(() => _drag = (_drag - n.scrollDelta!).clamp(0, 9999));
      }
    } else if (n is OverscrollNotification && _tracking && _active) {
      setState(() => _drag = (_drag - n.overscroll).clamp(0, 9999));
    } else if (n is ScrollEndNotification) {
      _tracking = false;
    }
    return false;
  }

  Future<void> _refresh() async {
    AknHaptics.light();
    await widget.onRefresh();
  }

  void _onStatus(RefreshIndicatorStatus? s) {
    if (!mounted) return;
    final wasArmed = _status == RefreshIndicatorStatus.armed;
    setState(() {
      _status = s;
      if (s == null ||
          s == RefreshIndicatorStatus.done ||
          s == RefreshIndicatorStatus.canceled) {
        _drag = 0;
      }
    });
    final reduced = AknMotion.reduced(context);
    if (s == RefreshIndicatorStatus.armed && !wasArmed && !reduced) {
      AknHaptics.selection();
      _pop.forward(from: 0);
    }
    if (_refreshing && AknMotion.ambientOf(context)) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final reduced = AknMotion.reduced(context);
    final armDistance = _viewport / 6;
    final progress = (_drag / armDistance).clamp(0.0, 1.0);
    final over = reduced
        ? 0.0
        : ((_drag - armDistance) / armDistance).clamp(0.0, 1.0);
    final refreshing = _refreshing;
    final visible = _active || refreshing;
    final armed = _status == RefreshIndicatorStatus.armed;
    // The puck follows the finger (damped); on release it springs home.
    final offset = refreshing
        ? 28.0
        : (_drag * 0.5).clamp(0.0, 72.0).toDouble();
    final fast = AknMotion.of(context, AknMotion.fast);

    final puck = DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        shape: BoxShape.circle,
        border: c.isDark ? Border.all(color: c.line) : null,
        boxShadow: [
          ...AknShadows.card(c),
          if (!c.isDark)
            const BoxShadow(
              color: Color(0x1415171A),
              offset: Offset(0, 6),
              blurRadius: 14,
              spreadRadius: -4,
            ),
        ],
      ),
      child: SizedBox.square(
        dimension: 40,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: CustomPaint(
            painter: _RingPainter(
              spin: _spin,
              progress: refreshing ? 1 : progress,
              refreshing: refreshing,
              color: c.brand,
              track: c.brandSoft,
            ),
          ),
        ),
      ),
    );

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: RefreshIndicator.noSpinner(
            onRefresh: _refresh,
            onStatusChange: _onStatus,
            child: widget.child,
          ),
        ),
        Positioned(
          top: widget.edgeOffset,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Semantics(
              label: refreshing ? 'Yenileniyor' : null,
              liveRegion: refreshing,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: offset),
                duration: _active
                    ? Duration.zero
                    : AknMotion.of(context, const Duration(milliseconds: 420)),
                curve: AknMotion.spring,
                builder: (context, dy, child) =>
                    Transform.translate(offset: Offset(0, dy), child: child),
                child: AnimatedOpacity(
                  opacity: visible ? (refreshing ? 1 : progress) : 0,
                  duration: fast,
                  child: AnimatedScale(
                    scale: visible
                        ? (armed || refreshing ? 1 : 0.6 + 0.4 * progress)
                        : 0.7,
                    duration: _active
                        ? Duration.zero
                        : AknMotion.of(context, AknMotion.base),
                    curve: AknMotion.spring,
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _pop,
                        child: puck,
                        builder: (context, child) {
                          final pop = _popScale.evaluate(_pop);
                          // Pulled past the arming point the puck stretches
                          // down like a drop.
                          return Transform(
                            alignment: Alignment.topCenter,
                            transform: Matrix4.diagonal3Values(
                              pop * (1 - 0.07 * over),
                              pop * (1 + 0.14 * over),
                              1,
                            ),
                            child: child,
                          );
                        },
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

/// The puck's ring: a `brandSoft` track and a logo-orange arc that winds up
/// with [progress] (and turns with it), or a 270° arc spinning with [spin]
/// while [refreshing].
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.spin,
    required this.progress,
    required this.refreshing,
    required this.color,
    required this.track,
  }) : super(repaint: spin);

  final Animation<double> spin;
  final double progress;
  final bool refreshing;
  final Color color;
  final Color track;

  static const double _stroke = 2.6;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final ring = rect.deflate(_stroke / 2);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawOval(ring, line..color = track);
    const turn = math.pi * 2;
    final double start;
    final double sweep;
    if (refreshing) {
      start = -math.pi / 2 + spin.value * turn;
      sweep = turn * 0.72;
    } else {
      if (progress <= 0) return;
      start = -math.pi / 2 + progress * math.pi * 0.6;
      sweep = turn * 0.86 * progress;
    }
    canvas.drawArc(ring, start, sweep, false, line..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.spin != spin ||
      old.progress != progress ||
      old.refreshing != refreshing ||
      old.color != color ||
      old.track != track;
}

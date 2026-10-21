import 'package:flutter/material.dart';

import '../motion.dart';
import '../painters/chevron_spinner.dart';
import '../theme.dart';
import '../tokens.dart';

/// Pull-to-refresh with the brand » chevrons: they draw in as you pull, run
/// while [onRefresh] works, then fade. Gesture handling is Flutter's own
/// [RefreshIndicator] (both bouncing and clamping physics); only the visual
/// is ours.
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

class _PullToRefreshState extends State<PullToRefresh> {
  RefreshIndicatorStatus? _status;
  double _drag = 0;
  double _viewport = 600;
  bool _tracking = false;

  bool get _active =>
      _status == RefreshIndicatorStatus.drag ||
      _status == RefreshIndicatorStatus.armed;

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

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final armDistance = _viewport / 6;
    final progress = (_drag / armDistance).clamp(0.0, 1.0);
    final refreshing =
        _status == RefreshIndicatorStatus.refresh ||
        _status == RefreshIndicatorStatus.snap;
    final visible = _active || refreshing;
    final armed = _status == RefreshIndicatorStatus.armed;
    final offset = refreshing
        ? 28.0
        : (_drag * 0.5).clamp(0.0, 64.0).toDouble();
    final duration = AknMotion.of(context, AknMotion.fast);

    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: RefreshIndicator.noSpinner(
            onRefresh: _refresh,
            onStatusChange: (s) {
              if (!mounted) return;
              setState(() {
                _status = s;
                if (s == null ||
                    s == RefreshIndicatorStatus.done ||
                    s == RefreshIndicatorStatus.canceled) {
                  _drag = 0;
                }
              });
            },
            child: widget.child,
          ),
        ),
        Positioned(
          top: widget.edgeOffset,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: visible ? (refreshing ? 1 : progress) : 0,
              duration: duration,
              child: Transform.translate(
                offset: Offset(0, offset),
                child: Center(
                  child: Semantics(
                    label: refreshing ? 'Yenileniyor' : null,
                    liveRegion: refreshing,
                    child: AnimatedScale(
                      scale: armed || refreshing ? 1 : 0.9,
                      duration: duration,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: c.surfaceRaised,
                          shape: BoxShape.circle,
                          border: Border.all(color: c.line),
                          boxShadow: AknShadows.raised(c),
                        ),
                        alignment: Alignment.center,
                        child: refreshing
                            ? const ChevronSpinner(
                                size: 18,
                                semanticLabel: null,
                              )
                            : CustomPaint(
                                size: ChevronRowPainter.sizeFor(18, 3),
                                painter: ChevronRowPainter(
                                  color: c.brand,
                                  progress: progress,
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
      ],
    );
  }
}

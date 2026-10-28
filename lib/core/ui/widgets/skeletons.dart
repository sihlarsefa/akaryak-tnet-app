import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';

/// Loading area (design v3 §4): a soft diagonal highlight sweeps across the
/// skeleton blocks inside — one slanted band of light for the whole area,
/// so lower blocks light a moment after the upper ones (one calm wave every
/// [AknMotion.shimmer], 1.4 s, repeating while loading). The sweep is
/// ambient motion: it runs only when [AknMotion.ambientOf] allows it, so
/// tests settle and reduce motion shows still blocks. Use it on first load
/// only; a refetch keeps the old content ([RefreshingContent]) and shows
/// [TopProgressBar].
class Shimmer extends StatefulWidget {
  const Shimmer({
    super.key,
    required this.child,
    this.semanticLabel = 'Yükleniyor',
  });

  final Widget child;
  final String? semanticLabel;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  /// Created the first time the sweep may run.
  AnimationController? _c;
  bool _running = false;

  /// The area the band sweeps across (this widget's box).
  RenderBox? get _box {
    if (!mounted) return null;
    final box = context.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize ? box : null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final run = AknMotion.ambientOf(context);
    if (run == _running) return;
    _running = run;
    if (run) {
      (_c ??= AnimationController(
        vsync: this,
        duration: AknMotion.shimmer,
      )).repeat();
    } else {
      _c
        ?..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget child = _ShimmerScope(
      sweep: _running ? _c : null,
      area: this,
      child: RepaintBoundary(child: widget.child),
    );
    final label = widget.semanticLabel;
    if (label == null) return ExcludeSemantics(child: child);
    return Semantics(
      label: label,
      liveRegion: true,
      excludeSemantics: true,
      child: child,
    );
  }
}

class _ShimmerScope extends InheritedWidget {
  const _ShimmerScope({
    required this.sweep,
    required this.area,
    required super.child,
  });

  /// The running sweep (0..1, repeating), or null while still.
  final Animation<double>? sweep;
  final _ShimmerState area;

  @override
  bool updateShouldNotify(_ShimmerScope old) =>
      old.sweep != sweep || old.area != area;
}

/// A skeleton placeholder block (design v3 §4): `skeleton` fill (one step
/// lighter in dark mode, so it reads on dark cards), radius 12 by default
/// (text lines become soft capsules), 20 for a card-sized block; [circle]
/// for avatars. Inside a [Shimmer] the sweeping light passes over it;
/// elsewhere it is still.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 12,
    this.circle = false,
  });

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final scope = context.dependOnInheritedWidgetOfExactType<_ShimmerScope>();
    // Dark cards sit close to the well colour: the blocks take one step up
    // (the highlight tone) so they still read as soft content shapes.
    final base = c.isDark ? c.skeletonHighlight : c.skeleton;
    final light = c.isDark
        ? Color.lerp(c.skeletonHighlight, c.ink, 0.08)!
        : c.skeletonHighlight;
    return SizedBox(
      width: circle ? height : width,
      height: height,
      child: _SkeletonBlock(
        color: base,
        highlight: light,
        radius: radius,
        circle: circle,
        sweep: scope?.sweep,
        area: scope?.area,
      ),
    );
  }
}

class _SkeletonBlock extends LeafRenderObjectWidget {
  const _SkeletonBlock({
    required this.color,
    required this.highlight,
    required this.radius,
    required this.circle,
    required this.sweep,
    required this.area,
  });

  final Color color;
  final Color highlight;
  final double radius;
  final bool circle;
  final Animation<double>? sweep;
  final _ShimmerState? area;

  @override
  _RenderSkeletonBlock createRenderObject(BuildContext context) =>
      _RenderSkeletonBlock(
        color: color,
        highlight: highlight,
        radius: radius,
        circle: circle,
        sweep: sweep,
        area: area,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSkeletonBlock renderObject,
  ) {
    renderObject
      ..color = color
      ..highlight = highlight
      ..radius = radius
      ..circle = circle
      ..sweep = sweep
      ..area = area;
  }
}

/// Paints one block; while a sweep runs it repaints on every tick with the
/// band placed in the [Shimmer] area's coordinates, so the light runs
/// continuously across neighbouring blocks.
class _RenderSkeletonBlock extends RenderBox {
  _RenderSkeletonBlock({
    required Color color,
    required Color highlight,
    required double radius,
    required bool circle,
    Animation<double>? sweep,
    _ShimmerState? area,
  }) : _color = color,
       _highlight = highlight,
       _radius = radius,
       _circle = circle,
       _sweep = sweep,
       _area = area;

  /// The band leans 20° (it moves to the right and a little down).
  static final Offset _dir = Offset.fromDirection(20 * math.pi / 180);

  Color _color;
  set color(Color v) {
    if (v == _color) return;
    _color = v;
    markNeedsPaint();
  }

  Color _highlight;
  set highlight(Color v) {
    if (v == _highlight) return;
    _highlight = v;
    markNeedsPaint();
  }

  double _radius;
  set radius(double v) {
    if (v == _radius) return;
    _radius = v;
    markNeedsPaint();
  }

  bool _circle;
  set circle(bool v) {
    if (v == _circle) return;
    _circle = v;
    markNeedsPaint();
  }

  Animation<double>? _sweep;
  set sweep(Animation<double>? v) {
    if (v == _sweep) return;
    if (attached) _sweep?.removeListener(markNeedsPaint);
    _sweep = v;
    if (attached) _sweep?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  _ShimmerState? _area;
  set area(_ShimmerState? v) {
    if (v == _area) return;
    _area = v;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _sweep?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _sweep?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.constrain(
        Size(
          constraints.hasBoundedWidth ? constraints.maxWidth : 0,
          constraints.hasBoundedHeight ? constraints.maxHeight : 0,
        ),
      );

  /// The band's shader in canvas coordinates, or null when still.
  Shader? _band(Offset offset) {
    final sweep = _sweep;
    final area = _area?._box;
    if (sweep == null || area == null) return null;
    final origin = localToGlobal(Offset.zero, ancestor: area);
    final extent = area.size.width * _dir.dx + area.size.height * _dir.dy;
    final band = (extent * 0.4).clamp(140.0, 280.0);
    // The band crosses during the first 85 % of the cycle, then rests
    // off-screen for a beat.
    final t = Curves.easeInOutSine.transform(
      (sweep.value / 0.85).clamp(0.0, 1.0),
    );
    final q = -band + (extent + band) * t;
    final shift = offset - origin;
    return ui.Gradient.linear(
      shift + _dir * q,
      shift + _dir * (q + band),
      [_color, _highlight, _highlight, _color],
      const [0, 0.42, 0.58, 1],
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;
    final paint = Paint()..color = _color;
    final shader = _band(offset);
    if (shader != null) paint.shader = shader;
    final rect = offset & size;
    if (_circle) {
      context.canvas.drawOval(rect, paint);
    } else {
      final r = math.min(_radius, size.shortestSide / 2);
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(r)),
        paint,
      );
    }
  }
}

/// One text line placeholder (width as a fraction of the available width).
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, this.widthFactor = 1, this.height = 12});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: widthFactor,
      child: SkeletonBox(height: height),
    );
  }
}

/// A list-card placeholder (design v3 §4): a white card (radius 20, the card
/// shadow; a 1 px `line` border in dark) holding a title capsule 58 % and an
/// amount capsule 22 % on the right, then shorter meta lines; [leading] adds
/// the 40 px rounded-square icon box of a real row.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({
    super.key,
    this.lines = 3,
    this.leading = false,
    this.margin = AknSpace.row,
  });

  /// 1 = title only, 2 = title + meta, 3+ = more meta lines.
  final int lines;

  /// A 40 px leading block (rows with a leading icon box).
  final bool leading;

  /// Outer padding: the row padding (20 / 12) by default.
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: AknRadius.card,
          border: c.isDark ? Border.all(color: c.line) : null,
          boxShadow: AknShadows.card(c),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (leading) ...[
                const SkeletonBox(width: 40, height: 40, radius: 12),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) {
                    final w = box.maxWidth;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            SkeletonBox(width: w * 0.58, height: 14),
                            const Spacer(),
                            SkeletonBox(width: w * 0.22, height: 14),
                          ],
                        ),
                        for (var i = 1; i < lines; i++) ...[
                          SizedBox(height: i == 1 ? 12 : 10),
                          Row(
                            children: [
                              SkeletonBox(
                                width: w * (i == 1 ? 0.4 : 0.28),
                                height: 11,
                              ),
                              if (i == 1) ...[
                                const Spacer(),
                                SkeletonBox(width: w * 0.14, height: 11),
                              ],
                            ],
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A shimmering list of card placeholders ([SkeletonCard]s 12 px apart on
/// the 20 px page edge) for first loads.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.itemCount = 6,
    this.lines = 2,
    this.leading = false,
    this.padding = const EdgeInsets.only(top: 4),
    this.header,
    this.shrinkWrap = false,
  });

  final int itemCount;
  final int lines;
  final bool leading;
  final EdgeInsetsGeometry padding;

  /// Optional placeholder above the rows (e.g. a plate slip).
  final Widget? header;

  /// True inside another scrollable (a list section, a sheet): lays the rows
  /// out in a plain column instead of a `ListView` (no unbounded height
  /// error).
  final bool shrinkWrap;

  static const EdgeInsets _cardMargin = EdgeInsets.fromLTRB(
    AknSpace.page,
    6,
    AknSpace.page,
    6,
  );

  @override
  Widget build(BuildContext context) {
    final children = [
      ?header,
      for (var i = 0; i < itemCount; i++)
        SkeletonCard(lines: lines, leading: leading, margin: _cardMargin),
    ];
    return Shimmer(
      child: shrinkWrap
          ? Padding(
              padding: padding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            )
          : ListView(
              padding: padding,
              physics: const NeverScrollableScrollPhysics(),
              children: children,
            ),
    );
  }
}

/// Keeps the old content visible while it refetches (design v3 §4): it eases
/// to 60 % opacity, no skeleton flash. Pair it with [TopProgressBar].
class RefreshingContent extends StatelessWidget {
  const RefreshingContent({
    super.key,
    required this.refreshing,
    required this.child,
  });

  final bool refreshing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: refreshing ? 0.6 : 1,
      duration: AknMotion.of(context, AknMotion.base),
      curve: AknMotion.standard,
      child: child,
    );
  }
}

/// Thin progress bar for background refreshes and uploads (design v3 §4): a
/// 3 px logo-orange bar with rounded ends that fades in and out.
/// Indeterminate while [active] — the sliding segment runs as ambient motion
/// (still tests and reduce motion show a quiet full-width line); with
/// [value] it shows that share on the chart track and glides to new values.
class TopProgressBar extends StatelessWidget {
  const TopProgressBar({
    super.key,
    required this.active,
    this.height = 3,
    this.value,
  });

  final bool active;
  final double height;

  /// 0..1 for a determinate bar; null = indeterminate.
  final double? value;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final radius = BorderRadius.circular(height);
    final Widget bar;
    final v = value;
    if (v == null) {
      final looping = AknMotion.ambientOf(context);
      // Still: a quiet full-width line (announced without a percentage).
      bar = Semantics(
        label: 'Yenileniyor',
        excludeSemantics: true,
        child: LinearProgressIndicator(
          value: looping ? null : 1,
          minHeight: height,
          color: looping ? c.logo : c.logo.withValues(alpha: 0.45),
          backgroundColor: Colors.transparent,
          borderRadius: radius,
        ),
      );
    } else {
      bar = TweenAnimationBuilder<double>(
        tween: Tween<double>(end: v.clamp(0.0, 1.0)),
        duration: AknMotion.of(context, AknMotion.base),
        curve: AknMotion.standard,
        builder: (context, p, _) => LinearProgressIndicator(
          value: p,
          minHeight: height,
          color: c.logo,
          backgroundColor: c.chartTrack,
          borderRadius: radius,
          semanticsLabel: 'Yükleniyor',
        ),
      );
    }
    return AnimatedSwitcher(
      duration: AknMotion.of(context, AknMotion.base),
      switchInCurve: AknMotion.standard,
      switchOutCurve: AknMotion.exit,
      child: active
          ? SizedBox(key: const ValueKey('on'), height: height, child: bar)
          : SizedBox(key: const ValueKey('off'), height: height),
    );
  }
}

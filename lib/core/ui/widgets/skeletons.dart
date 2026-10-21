import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';

/// Shimmer area: every [SkeletonBox] inside shares one light sweep, so the
/// whole placeholder reads as one surface. Use on first load only; a refresh
/// keeps the content and shows [TopProgressBar] instead.
///
/// Reduce motion: static placeholders, no sweep.
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
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
  );
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = AknMotion.reduced(context);
    if (_reduced) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(
        min: -0.6,
        max: 1.6,
        period: const Duration(milliseconds: 1500),
      );
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Size? get _size {
    final box = context.findRenderObject() as RenderBox?;
    return box != null && box.hasSize ? box.size : null;
  }

  Offset _offsetOf(RenderBox descendant) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    return descendant.localToGlobal(Offset.zero, ancestor: box);
  }

  @override
  Widget build(BuildContext context) {
    final child = _ShimmerScope(state: this, child: widget.child);
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
  const _ShimmerScope({required this.state, required super.child});

  final _ShimmerState state;

  @override
  bool updateShouldNotify(_ShimmerScope old) => old.state != state;
}

/// Placeholder block. Shimmers inside a [Shimmer], static elsewhere.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 6,
    this.circle = false,
  });

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final box = Container(
      width: circle ? height : width,
      height: height,
      decoration: BoxDecoration(
        color: c.skeleton,
        borderRadius: circle ? null : BorderRadius.circular(radius),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
      ),
    );
    final scope = context.dependOnInheritedWidgetOfExactType<_ShimmerScope>();
    if (scope == null || scope.state._reduced) return box;
    return _ShimmerMask(state: scope.state, colors: c, child: box);
  }
}

class _ShimmerMask extends StatelessWidget {
  const _ShimmerMask({
    required this.state,
    required this.colors,
    required this.child,
  });

  final _ShimmerState state;
  final AknColors colors;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: state._c,
      child: child,
      builder: (context, child) {
        final area = state._size;
        final me = context.findRenderObject() as RenderBox?;
        if (area == null || me == null || !me.hasSize || !me.attached) {
          return child!;
        }
        final offset = state._offsetOf(me);
        final gradient = LinearGradient(
          begin: const Alignment(-1, -0.25),
          end: const Alignment(1, 0.25),
          colors: [colors.skeleton, colors.skeletonHighlight, colors.skeleton],
          stops: const [0.25, 0.42, 0.6],
          transform: _Slide(state._c.value),
        );
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => gradient.createShader(
            Rect.fromLTWH(-offset.dx, -offset.dy, area.width, area.height),
          ),
          child: child,
        );
      },
    );
  }
}

class _Slide extends GradientTransform {
  const _Slide(this.percent);

  final double percent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * percent, 0, 0);
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

/// Card-shaped placeholder: optional leading block and a few lines.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({
    super.key,
    this.lines = 3,
    this.leading = true,
    this.margin = const EdgeInsets.fromLTRB(16, 0, 16, 12),
  });

  final int lines;
  final bool leading;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return Padding(
      padding: margin,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: AknRadius.card,
          border: Border.all(color: c.line),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading) ...[
              const SkeletonBox(width: 40, height: 40, radius: 12),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < lines; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    SkeletonLine(
                      widthFactor: i == 0 ? 0.62 : (i.isOdd ? 0.9 : 0.45),
                      height: i == 0 ? 14 : 11,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A shimmering list of [SkeletonCard]s for first loads.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.itemCount = 6,
    this.lines = 3,
    this.leading = true,
    this.padding = const EdgeInsets.only(top: 12),
    this.header,
    this.shrinkWrap = false,
  });

  final int itemCount;
  final int lines;
  final bool leading;
  final EdgeInsetsGeometry padding;

  /// Optional placeholder above the cards (e.g. a KPI row).
  final Widget? header;

  /// True inside another scrollable (a list section, a sheet): lays the
  /// cards out in a plain column instead of a `ListView` (no unbounded
  /// height error).
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final children = [
      ?header,
      for (var i = 0; i < itemCount; i++)
        SkeletonCard(lines: lines, leading: leading),
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

/// Thin brand progress bar for background refreshes: content stays, the bar
/// slides in at the top while [active].
class TopProgressBar extends StatelessWidget {
  const TopProgressBar({super.key, required this.active, this.height = 2.5});

  final bool active;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return AnimatedSwitcher(
      duration: AknMotion.of(context, AknMotion.base),
      child: active
          ? SizedBox(
              key: const ValueKey('on'),
              height: height,
              child: LinearProgressIndicator(
                minHeight: height,
                color: c.brand,
                backgroundColor: c.brandSoft,
                semanticsLabel: 'Yenileniyor',
              ),
            )
          : SizedBox(key: const ValueKey('off'), height: height),
    );
  }
}

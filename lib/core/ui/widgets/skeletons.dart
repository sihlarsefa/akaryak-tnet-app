import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';

/// Loading area (design v2 §6.23): the Beton blocks inside pulse together —
/// opacity 1 → 0.55 → 1 over 1200 ms — with no sweeping gradient. Static
/// under reduce motion. Use it on first load only; a refetch keeps the old
/// content ([RefreshingContent]) and shows [TopProgressBar].
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
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AknMotion.skeletonPulse,
  );
  late final Animation<double> _opacity = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 0.55,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 1,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 0.55,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 1,
    ),
  ]).animate(_c);
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = AknMotion.reduced(context);
    if (_reduced) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget child = _reduced
        ? widget.child
        : FadeTransition(opacity: _opacity, child: widget.child);
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

/// A Beton placeholder block: radius 6 for text lines, 12 for blocks, 20 for
/// a deck slip. It pulses inside a [Shimmer] and is static elsewhere.
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
    return Container(
      width: circle ? height : width,
      height: height,
      decoration: BoxDecoration(
        color: c.skeleton,
        borderRadius: circle ? null : BorderRadius.circular(radius),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
      ),
    );
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

/// A ledger-row placeholder (§6.23): title line 60 %, meta line 40 % and an
/// amount block 25 % on the right; extra [lines] add shorter meta lines. No
/// card, no border (the name is kept for old call sites).
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({
    super.key,
    this.lines = 3,
    this.leading = false,
    this.margin = AknSpace.row,
  });

  /// 1 = title only, 2 = title + meta, 3+ = more meta lines.
  final int lines;

  /// A 24 px leading block (rows with a leading icon).
  final bool leading;

  /// Outer padding: the row padding (20 / 12) by default.
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (leading) ...[
            const SkeletonBox(width: 24, height: 24, radius: 6),
            const SizedBox(width: 16),
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
                        SkeletonBox(width: w * 0.6, height: 16),
                        const Spacer(),
                        SkeletonBox(width: w * 0.25, height: 16),
                      ],
                    ),
                    for (var i = 1; i < lines; i++) ...[
                      const SizedBox(height: 10),
                      SkeletonBox(width: w * (i == 1 ? 0.4 : 0.3), height: 12),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A pulsing list of ledger-row placeholders (inset hairlines between rows)
/// for first loads.
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

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final children = [
      ?header,
      for (var i = 0; i < itemCount; i++) ...[
        if (i > 0)
          Divider(
            height: 1,
            thickness: 1,
            indent: AknSpace.page,
            endIndent: AknSpace.page,
            color: c.line,
          ),
        SkeletonCard(lines: lines, leading: leading),
      ],
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

/// Keeps the old content visible while it refetches (§6.23): 60 % opacity,
/// no skeleton flash. Pair it with [TopProgressBar].
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
      duration: AknMotion.of(context, AknMotion.fast),
      child: child,
    );
  }
}

/// Thin progress bar for background refreshes and uploads (§6.23): 2.5 px
/// logo orange. Indeterminate while [active]; with [value] it shows that
/// share on the chart track (an upload inside an attachment row).
class TopProgressBar extends StatelessWidget {
  const TopProgressBar({
    super.key,
    required this.active,
    this.height = 2.5,
    this.value,
  });

  final bool active;
  final double height;

  /// 0..1 for a determinate bar; null = indeterminate.
  final double? value;

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
                value: value?.clamp(0.0, 1.0),
                minHeight: height,
                color: c.logo,
                backgroundColor: value == null
                    ? Colors.transparent
                    : c.chartTrack,
                borderRadius: BorderRadius.zero,
                semanticsLabel: value == null ? 'Yenileniyor' : 'Yükleniyor',
              ),
            )
          : SizedBox(key: const ValueKey('off'), height: height),
    );
  }
}

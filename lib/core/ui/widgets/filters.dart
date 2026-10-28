import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../driver_mode.dart';
import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';
import '../typography.dart';

/// One choice of [FilterChips] or [AknSegmented].
@immutable
class FilterOption<T> {
  const FilterOption({
    required this.value,
    required this.label,
    this.count,
    this.icon,
  });

  final T value;
  final String label;

  /// Small count next to the label (null hides it).
  final int? count;
  final IconData? icon;
}

/// [a] → [b] at [t], exact at both ends.
Color _mix(Color a, Color b, double t) =>
    t <= 0 ? a : (t >= 1 ? b : Color.lerp(a, b, t)!);

/// A single v3 chip (§4 Chips, the panel's `.chip`): a 36 px pill in a 48 px
/// touch target (driver mode: 44 in 64), white (`surface`) with a 1 px `line`
/// border, ink 14/18 600 label and a small count pill. Selected = the
/// panel's "you are here": the soft orange well (`brandSoft`) with its orange
/// line, a Pas label, and a check that slides in and pops before the label
/// (it takes the place of [icon]); [tonal] is kept for API stability (every
/// selected chip is tonal now). Selection animates the fill (~300 ms)
/// and springs the check in; a press scales the chip down a touch with a
/// selection haptic. Icons grow with the label at large text sizes.
///
/// Used by [FilterChips], the [DateField] quick picks and any quick-pick row
/// ("5.000 L", "Yarın", "08:00–12:00").
class AknChip extends StatelessWidget {
  const AknChip({
    super.key,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.count,
    this.icon,
    this.semanticLabel,
    this.enabled = true,
    this.tonal = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final int? count;
  final IconData? icon;

  /// Defaults to "label, count".
  final String? semanticLabel;
  final bool enabled;

  /// Selected in the soft orange well (`brandSoft` + `brandInk`) instead of
  /// ink: the "your move" flavour.
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final active = enabled && onTap != null;
    return Semantics(
      button: true,
      selected: selected,
      enabled: active,
      label: semanticLabel ?? (count == null ? label : '$label, $count'),
      excludeSemantics: true,
      onTap: active ? onTap : null,
      // 48 dp touch target around the 36 dp chip (64 in driver mode).
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: active
            ? () {
                AknHaptics.selection();
                onTap!();
              }
            : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: context.minTap),
          child: Center(
            widthFactor: 1,
            child: PressScale(
              enabled: active,
              scale: 0.94,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: selected ? 1 : 0),
                duration: AknMotion.of(
                  context,
                  const Duration(milliseconds: 300),
                ),
                builder: (context, s, _) => _ChipBody(
                  label: label,
                  count: count,
                  icon: icon,
                  active: active,
                  tonal: tonal,
                  progress: s,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The chip's pill at selection [progress] (0 rest → 1 selected): colours
/// ease, the check springs in.
class _ChipBody extends StatelessWidget {
  const _ChipBody({
    required this.label,
    required this.count,
    required this.icon,
    required this.active,
    required this.tonal,
    required this.progress,
  });

  final String label;
  final int? count;
  final IconData? icon;
  final bool active;
  final bool tonal;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final driver = context.isDriverMode;
    // The glyphs grow with the label (clamped) so a check never looks lost.
    final scaler = MediaQuery.textScalerOf(context);
    final checkSize = scaler.scale(14).clamp(14.0, 20.0);
    final iconSize = scaler.scale(16).clamp(16.0, 22.0);
    final f = AknMotion.standard.transform(progress.clamp(0.0, 1.0));
    final k = progress <= 0
        ? 0.0
        : progress >= 1
        ? 1.0
        : AknMotion.spring.transform(progress);
    final rest = active ? c.surface : c.surfaceAlt;
    // Selected: the panel's soft orange chip (every chip; [tonal] kept).
    final fill = _mix(rest, c.brandSoft, f);
    final border = _mix(active ? c.line : c.surfaceAlt, c.brandLine, f);
    final fg = _mix(active ? c.ink : c.faint, c.brandInk, f);
    final check = Icon(PhosphorIconsBold.check, size: checkSize, color: fg);
    final Widget lead;
    if (icon != null) {
      // The check takes the icon's place: one shrinks away, the other pops.
      lead = Padding(
        padding: const EdgeInsetsDirectional.only(end: 6),
        child: SizedBox.square(
          dimension: iconSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: 1 - f,
                child: Transform.scale(
                  scale: 1 - 0.5 * f,
                  child: Icon(icon, size: iconSize, color: fg),
                ),
              ),
              Opacity(
                opacity: f,
                child: Transform.scale(scale: k, child: check),
              ),
            ],
          ),
        ),
      );
    } else {
      // The check slides in from the leading edge, opening room for itself.
      final slot = checkSize + 6;
      lead = SizedBox(
        width: slot * k,
        height: checkSize + 2,
        child: OverflowBox(
          alignment: AlignmentDirectional.centerStart,
          // The spring overshoots the slot (k > 1): never inherit a minimum
          // wider than the check itself.
          minWidth: 0,
          maxWidth: slot,
          child: Opacity(
            opacity: f,
            child: Transform.scale(
              scale: 0.4 + 0.6 * k,
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: check,
              ),
            ),
          ),
        ),
      );
    }
    final n = count;
    // 14/18 600 (driver mode: the 15/20 label in a 44 px pill).
    final labelStyle = driver
        ? t.label
        : t.label.copyWith(fontSize: 14, height: 18 / 14);
    return Container(
      constraints: BoxConstraints(minHeight: driver ? 44 : 36),
      padding: EdgeInsetsDirectional.only(
        start: 14 - 2 * f,
        end: 14,
        top: 6,
        bottom: 6,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: AknRadius.chip,
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          lead,
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyle.copyWith(
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
          if (n != null) ...[
            const SizedBox(width: 6),
            _CountPill(
              count: n,
              background: _mix(
                c.surfaceAlt,
                c.surface.withValues(alpha: 0.8),
                f,
              ),
              color: _mix(c.dim, c.brandInk, f),
            ),
          ],
        ],
      ),
    );
  }
}

/// A small count pill (§4 Chips: "count pills inside"): 12/16 700 tabular.
class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.count,
    required this.background,
    required this.color,
  });

  final int count;
  final Color background;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: AknRadius.pillAll,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Text(
          '$count',
          style: context.aknText.captionStrong.copyWith(
            color: color,
            fontFeatures: AknNumerals.tabular,
          ),
        ),
      ),
    );
  }
}

/// Horizontally scrolling filter chips (status, type, segment): v3 [AknChip]s
/// with 20 px side padding and a soft fade at both edges when they scroll.
/// The chips pour in one after another when the row first appears, and a
/// chip that is tapped half-hidden glides into view.
///
/// Single-select by default (tapping the selected chip clears it when
/// [allowEmpty]); [multi] toggles independently. Selected = the soft orange
/// chip and a check, never colour alone (the screen reader hears "seçili").
class FilterChips<T> extends StatelessWidget {
  const FilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.multi = false,
    this.allowEmpty = true,
    this.padding = const EdgeInsets.symmetric(horizontal: AknSpace.page),
    this.tonal = false,
  });

  final List<FilterOption<T>> options;
  final Set<T> selected;
  final ValueChanged<Set<T>> onChanged;
  final bool multi;
  final bool allowEmpty;
  final EdgeInsetsGeometry padding;

  /// The "your move" flavour of [AknChip.tonal] for every chip.
  final bool tonal;

  void _tap(T value) {
    final next = Set<T>.of(selected);
    if (multi) {
      if (!next.remove(value)) next.add(value);
      if (next.isEmpty && !allowEmpty) return;
    } else {
      if (next.contains(value)) {
        if (!allowEmpty) return;
        next.clear();
      } else {
        next
          ..clear()
          ..add(value);
      }
    }
    onChanged(next);
  }

  /// Scrolls the tapped [chip] fully into view (clear of the edge fade).
  static void _reveal(BuildContext chip, double margin) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!chip.mounted) return;
      final box = chip.findRenderObject() as RenderBox?;
      final scrollable = Scrollable.maybeOf(chip);
      final viewport = scrollable?.context.findRenderObject() as RenderBox?;
      if (box == null || scrollable == null || viewport == null) return;
      final position = scrollable.position;
      final left = box.localToGlobal(Offset.zero, ancestor: viewport).dx;
      final right = left + box.size.width;
      final width = viewport.size.width;
      double delta = 0;
      if (right > width - margin) {
        delta = right - (width - margin);
      } else if (left < margin) {
        delta = left - margin;
      }
      if (delta.abs() < 1) return;
      final target = (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (AknMotion.reduced(chip)) {
        position.jumpTo(target);
      } else {
        unawaited(
          position.animateTo(
            target,
            duration: const Duration(milliseconds: 360),
            curve: AknMotion.emphasizedCurve,
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dir = Directionality.of(context);
    final insets = padding.resolve(dir);
    final fadeStart = insets.left.clamp(0.0, 24.0);
    final fadeEnd = insets.right.clamp(0.0, 24.0);
    final row = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _Entrance(
              index: i,
              child: Builder(
                builder: (chip) => AknChip(
                  label: options[i].label,
                  count: options[i].count,
                  icon: options[i].icon,
                  tonal: tonal,
                  selected: selected.contains(options[i].value),
                  onTap: () {
                    _tap(options[i].value);
                    _reveal(chip, math.max(fadeStart, fadeEnd) + 8);
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
    if (fadeStart <= 0 && fadeEnd <= 0) return row;
    // Edge fades over the gutters: invisible at rest, they soften chips that
    // scroll under either edge.
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final w = rect.width <= 0 ? 1.0 : rect.width;
        final a = (fadeStart / w).clamp(0.0, 0.5);
        final b = (1 - fadeEnd / w).clamp(0.5, 1.0);
        return LinearGradient(
          colors: const [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0, a, b, 1],
        ).createShader(rect);
      },
      child: row,
    );
  }
}

/// A chip's entrance: fades in, rises 8 px and grows from 0.9, 40 ms after
/// its left neighbour. Once, when first built; shown at once under reduce
/// motion. The tree shape never changes, so the chip keeps its state.
class _Entrance extends StatefulWidget {
  const _Entrance({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
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
      return;
    }
    final delay = const Duration(milliseconds: 40) * widget.index.clamp(0, 8);
    if (delay == Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final v = AknMotion.emphasizedCurve.transform(_c.value);
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          // Screen readers find the chip from its first frame.
          alwaysIncludeSemantics: true,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - v)),
            child: Transform.scale(scale: 0.9 + 0.1 * v, child: child),
          ),
        );
      },
    );
  }
}

/// Segmented control (§4 Segmented): a `surfaceAlt` pill track (padding 3,
/// 40 high; 36 with [dense]; 48 in driver mode) with a white pill thumb
/// carrying the card shadow (dark: a lighter graphite) that slides on the
/// spring curve and stretches a little in flight. Labels 14/18: selected Pas
/// w700 (the panel's `.seg-btn`), others dim w600 — weight and colour
/// animate; a count pill follows
/// the label. Each segment is a screen-reader button with a tap action, a
/// 48 dp touch target (64 in driver mode) and a press scale.
class AknSegmented<T> extends StatelessWidget {
  const AknSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.margin = const EdgeInsets.symmetric(horizontal: AknSpace.page),
    this.dense = false,
  });

  final List<FilterOption<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final EdgeInsetsGeometry margin;

  /// 36 px track (inside sections) instead of 40.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final n = segments.length;
    final index = segments.indexWhere((s) => s.value == value);
    final duration = AknMotion.of(context, AknMotion.thumb);
    final driver = context.isDriverMode;
    final minTap = context.minTap;
    final trackHeight = driver ? 48.0 : (dense ? 36.0 : 40.0);
    final labelSize = driver ? 15.0 : 14.0;
    final labelLine = driver ? 20.0 : 18.0;
    // The track grows with the text and stays 40 (driver 48) at 1.0×.
    final height =
        trackHeight -
        labelLine +
        MediaQuery.textScalerOf(context).scale(labelLine);
    final box = height < minTap ? minTap : height;
    final thumb = DecoratedBox(
      decoration: BoxDecoration(
        color: c.isDark
            ? Color.alphaBlend(c.ink.withValues(alpha: 0.1), c.surfaceRaised)
            : c.surface,
        borderRadius: AknRadius.pillAll,
        boxShadow: AknShadows.card(c),
      ),
    );
    final label = t.label.copyWith(
      fontSize: labelSize,
      height: labelLine / labelSize,
    );
    return Padding(
      padding: margin,
      child: SizedBox(
        height: box,
        child: Stack(
          children: [
            Positioned.fill(
              child: Center(
                child: Container(
                  height: height,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: c.surfaceAlt,
                    borderRadius: AknRadius.pillAll,
                  ),
                  child: index < 0
                      ? null
                      : TweenAnimationBuilder<double>(
                          tween: Tween<double>(end: index.toDouble()),
                          duration: duration,
                          curve: AknMotion.spring,
                          child: FractionallySizedBox(
                            widthFactor: 1 / n,
                            heightFactor: 1,
                            child: thumb,
                          ),
                          builder: (context, pos, child) {
                            // The spring may overshoot between segments but
                            // never through the track's ends.
                            final p = pos.clamp(0.0, (n - 1).toDouble());
                            final x = n <= 1 ? 0.0 : -1 + 2 * p / (n - 1);
                            // A little stretch while the thumb travels.
                            final d = (p - p.round()).abs();
                            return Align(
                              alignment: Alignment(x, 0),
                              child: Transform.scale(
                                scaleX: 1 + 0.14 * d,
                                scaleY: 1 - 0.04 * d,
                                child: child,
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
            // Labels and 48 dp touch targets over the whole box.
            Positioned.fill(
              left: 3,
              right: 3,
              child: Row(
                children: [
                  for (var i = 0; i < n; i++)
                    Expanded(
                      child: _Segment(
                        option: segments[i],
                        selected: i == index,
                        duration: duration,
                        minTap: minTap,
                        style: label.copyWith(
                          fontWeight: i == index
                              ? FontWeight.w700
                              : FontWeight.w600,
                          // The panel's `.seg-btn` "you are here": Pas.
                          color: i == index ? c.brandInk : c.dim,
                        ),
                        onTap: () {
                          if (i == index) return;
                          AknHaptics.selection();
                          onChanged(segments[i].value);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.option,
    required this.selected,
    required this.duration,
    required this.minTap,
    required this.style,
    required this.onTap,
  });

  final FilterOption<Object?> option;
  final bool selected;
  final Duration duration;

  /// The touch target height (48; 64 in driver mode).
  final double minTap;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final count = option.count;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: count == null ? option.label : '${option.label}, $count',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          // 48 dp touch target (the track itself is 40).
          constraints: BoxConstraints(minHeight: minTap),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: PressScale(
              scale: 0.94,
              // A label that does not fit (large text) shrinks to its
              // segment instead of losing letters to "…".
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: duration,
                        curve: AknMotion.standard,
                        style: style,
                        child: Text(
                          option.label,
                          maxLines: 1,
                          softWrap: false,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      if ((count ?? 0) > 0) ...[
                        const SizedBox(width: 5),
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(end: selected ? 1 : 0),
                          duration: duration,
                          builder: (context, s, _) => _CountPill(
                            count: count!,
                            background: _mix(c.line, c.brandSoft, s),
                            color: _mix(c.dim, c.brandInk, s),
                          ),
                        ),
                      ],
                    ],
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

/// Top tabs (design v3 §4 Tabs, board "Siparişlerim"): start-aligned labels
/// on the 20 px edge with 28 px between them — 16/20 w700, selected ink,
/// others dim, a count pill after the label ([AknTab]) — a 3 px logo-orange
/// bar with round ends the width of the label that follows the selection on
/// a spring ([AknTabIndicator]: it stretches in flight, overshoots a touch
/// and settles; still under reduce motion), a selection haptic, and a
/// hairline under the whole bar (from `tabBarTheme`). Scrolls when the
/// labels do not fit (large text). Use it as `AppScaffold.bottom`.
///
/// ```dart
/// AppScaffold(
///   title: 'Siparişlerim',
///   bottom: const AknTabBar(tabs: [
///     AknTab(label: 'Aktif', count: 4),
///     AknTab(label: 'Geçmiş', count: 28),
///   ]),
///   body: …,
/// )
/// ```
class AknTabBar extends StatelessWidget implements PreferredSizeWidget {
  const AknTabBar({super.key, required this.tabs, this.controller, this.onTap});

  /// [AknTab]s (or stock `Tab`s).
  final List<Widget> tabs;

  /// Defaults to the enclosing `DefaultTabController`.
  final TabController? controller;
  final ValueChanged<int>? onTap;

  TabBar _bar([Decoration? indicator]) => TabBar(
    controller: controller,
    tabs: tabs,
    onTap: (i) {
      AknHaptics.selection();
      onTap?.call(i);
    },
    isScrollable: true,
    tabAlignment: TabAlignment.start,
    indicator: indicator,
    // The theme's label padding is 14 a side: 6 + 14 puts the first label
    // on the 20 px edge and keeps 28 between labels.
    padding: const EdgeInsetsDirectional.only(start: AknSpace.page - 14),
  );

  @override
  Size get preferredSize => _bar().preferredSize;

  @override
  Widget build(BuildContext context) => _bar(
    AknTabIndicator(
      color: context.akn.brand,
      animate: !AknMotion.reduced(context),
    ),
  );
}

/// One top tab: the label and an optional count pill ("Aktif ④") whose
/// figures follow the tab's colour (ink when selected, dim otherwise).
/// Screen readers hear "Aktif, 4".
class AknTab extends StatelessWidget {
  const AknTab({super.key, required this.label, this.count});

  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final n = count;
    final c = context.akn;
    return Tab(
      child: Semantics(
        label: n == null ? label : '$label, $n',
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, maxLines: 1, softWrap: false),
            if (n != null) ...[
              const SizedBox(width: 6),
              _CountPill(
                count: n,
                background: c.surfaceAlt,
                color: DefaultTextStyle.of(context).style.color ?? c.dim,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

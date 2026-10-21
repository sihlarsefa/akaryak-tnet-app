import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';

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

/// A single v2 chip (§6.11): 36 px visual in a 48 px touch target, r10,
/// Beton fill, ink 14/18 600 label and a 500 dim count. Selected = an ink
/// fill with a page-coloured label — no checkmark, no orange.
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
  });

  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final int? count;
  final IconData? icon;

  /// Defaults to "label, count".
  final String? semanticLabel;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final active = enabled && onTap != null;
    final fill = selected ? c.ink : c.surfaceAlt;
    final fg = selected ? c.bg : (active ? c.ink : c.faint);
    final countColor = selected ? c.bg.withValues(alpha: 0.8) : c.dim;
    final duration = AknMotion.of(context, AknMotion.fast);
    return Semantics(
      button: true,
      selected: selected,
      enabled: active,
      label: semanticLabel ?? (count == null ? label : '$label, $count'),
      excludeSemantics: true,
      onTap: active ? onTap : null,
      // 48 dp touch target around the 36 dp chip.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: active
            ? () {
                AknHaptics.selection();
                onTap!();
              }
            : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AknSpace.minTap),
          child: Center(
            widthFactor: 1,
            child: AnimatedContainer(
              duration: duration,
              curve: AknMotion.standard,
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: AknRadius.chip,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: fg),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.label.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                  ),
                  if (count != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '$count',
                      style: t.label.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: countColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontally scrolling filter chips (status, type, segment): v2 [AknChip]s
/// with 20 px side padding and a fade at the trailing edge when they scroll.
///
/// Single-select by default (tapping the selected chip clears it when
/// [allowEmpty]); [multi] toggles independently. Selected = ink fill, never
/// colour alone (the screen reader hears "seçili").
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

  /// Deprecated: v2 has one chip style (ink selection); ignored.
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

  @override
  Widget build(BuildContext context) {
    final end = padding.resolve(Directionality.of(context)).right;
    final fade = end.clamp(0.0, 24.0);
    final row = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            AknChip(
              label: options[i].label,
              count: options[i].count,
              icon: options[i].icon,
              selected: selected.contains(options[i].value),
              onTap: () => _tap(options[i].value),
            ),
          ],
        ],
      ),
    );
    if (fade <= 0) return row;
    // End fade over the trailing gutter: invisible at rest, it softens chips
    // that scroll under the edge.
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final stop = rect.width <= 0
            ? 1.0
            : (1 - fade / rect.width).clamp(0.0, 1.0);
        return LinearGradient(
          colors: const [Colors.black, Colors.black, Colors.transparent],
          stops: [0, stop, 1],
        ).createShader(rect);
      },
      child: row,
    );
  }
}

/// Segmented control (§6.11): a Beton track (r12, padding 3, 40 high; 36
/// with [dense]) with a white thumb (r9, 1 px hairline; dark: raised) that
/// slides in 220 ms. Labels 14/18 600: selected ink, others dim; a count
/// follows the label in 500. Each segment is a screen-reader button with a
/// tap action and a 48 dp touch target.
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
    final x = n <= 1 || index < 0 ? -1.0 : -1 + 2 * index / (n - 1);
    final trackHeight = dense ? 36.0 : 40.0;
    // The track grows with the text (14/18 label) and stays 40 at 1.0×.
    final height =
        trackHeight - 18 + MediaQuery.textScalerOf(context).scale(18);
    final box = height < AknSpace.minTap ? AknSpace.minTap : height;
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
                    borderRadius: AknRadius.button,
                  ),
                  child: index < 0
                      ? null
                      : AnimatedAlign(
                          duration: duration,
                          curve: AknMotion.emphasizedCurve,
                          alignment: Alignment(x, 0),
                          child: FractionallySizedBox(
                            widthFactor: 1 / n,
                            heightFactor: 1,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: c.isDark ? c.surfaceRaised : c.surface,
                                borderRadius: const BorderRadius.all(
                                  Radius.circular(9),
                                ),
                                border: c.isDark
                                    ? null
                                    : Border.all(color: c.line),
                              ),
                            ),
                          ),
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
                        style: t.label.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: i == index ? c.ink : c.dim,
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
    required this.style,
    required this.onTap,
  });

  final FilterOption<Object?> option;
  final bool selected;
  final Duration duration;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
          constraints: const BoxConstraints(minHeight: AknSpace.minTap),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: AnimatedDefaultTextStyle(
                    duration: duration,
                    style: style,
                    child: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                if ((count ?? 0) > 0) ...[
                  const SizedBox(width: 5),
                  Text(
                    '$count',
                    style: style.copyWith(fontWeight: FontWeight.w500),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Top tabs (design v2 §6.11, board "Siparişlerim"): start-aligned labels on
/// the 20 px edge with 28 px between them — 16/20 600, selected ink, others
/// dim, a count after the label in 500 ([AknTab]) — a 3 px logo-orange
/// indicator the width of the label (top-rounded 2) and a 1 px hairline
/// under the whole bar (from `tabBarTheme`). Scrolls when the labels do not
/// fit (large text). Use it as `AppScaffold.bottom`.
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

  TabBar get _bar => TabBar(
    controller: controller,
    tabs: tabs,
    onTap: onTap,
    isScrollable: true,
    tabAlignment: TabAlignment.start,
    // The theme's label padding is 14 a side: 6 + 14 puts the first label
    // on the 20 px edge and keeps 28 between labels.
    padding: const EdgeInsetsDirectional.only(start: AknSpace.page - 14),
  );

  @override
  Size get preferredSize => _bar.preferredSize;

  @override
  Widget build(BuildContext context) => _bar;
}

/// One top tab: the label and an optional count in 500 ("Aktif 4"). Screen
/// readers hear "Aktif, 4".
class AknTab extends StatelessWidget {
  const AknTab({super.key, required this.label, this.count});

  final String label;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final n = count;
    return Tab(
      child: Semantics(
        label: n == null ? label : '$label, $n',
        excludeSemantics: true,
        child: Text.rich(
          TextSpan(
            text: label,
            children: [
              if (n != null)
                TextSpan(
                  text: '\u00A0$n',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
            ],
          ),
          maxLines: 1,
          softWrap: false,
        ),
      ),
    );
  }
}

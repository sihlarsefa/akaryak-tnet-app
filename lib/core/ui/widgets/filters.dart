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

/// Horizontally scrolling filter chips (status, type, segment).
///
/// Single-select by default (tapping the selected chip clears it when
/// [allowEmpty]); [multi] toggles independently. Selection uses a check icon
/// and a tint, never colour alone.
class FilterChips<T> extends StatelessWidget {
  const FilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.multi = false,
    this.allowEmpty = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final List<FilterOption<T>> options;
  final Set<T> selected;
  final ValueChanged<Set<T>> onChanged;
  final bool multi;
  final bool allowEmpty;
  final EdgeInsetsGeometry padding;

  void _tap(T value) {
    AknHaptics.selection();
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _FilterChip<T>(
              option: options[i],
              selected: selected.contains(options[i].value),
              onTap: () => _tap(options[i].value),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip<T> extends StatelessWidget {
  const _FilterChip({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final FilterOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final duration = AknMotion.of(context, AknMotion.fast);
    final fg = selected ? c.brandInk : c.text;
    final count = option.count;
    return Semantics(
      button: true,
      selected: selected,
      label: count == null ? option.label : '${option.label}, $count',
      excludeSemantics: true,
      onTap: onTap,
      // 48 dp touch target around the 36 dp chip.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AknSpace.minTap),
          child: Center(
            widthFactor: 1,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                borderRadius: AknRadius.pillAll,
                child: AnimatedContainer(
                  duration: duration,
                  curve: AknMotion.standard,
                  constraints: const BoxConstraints(minHeight: 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? c.brandSoft : c.surface,
                    borderRadius: AknRadius.pillAll,
                    border: Border.all(
                      color: selected ? c.brandLine : c.lineStrong,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AknAnimatedSize(
                        duration: AknMotion.fast,
                        child: selected
                            ? Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: fg,
                                ),
                              )
                            : option.icon != null
                            ? Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Icon(
                                  option.icon,
                                  size: 16,
                                  color: c.dim,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      Text(option.label, style: t.label.copyWith(color: fg)),
                      if (count != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: selected ? c.surface : c.surfaceAlt,
                            borderRadius: AknRadius.pillAll,
                          ),
                          child: Text(
                            '$count',
                            style: t.captionStrong.copyWith(
                              color: fg,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
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

/// Segmented tabs with a sliding thumb (Bende / Taleplerim / Tümü,
/// Karar bekleyen / Aktif / Geçmiş). Equal-width segments, 48 dp tall; the
/// unselected label uses `text` (AA on `surfaceAlt`); each segment is a
/// screen-reader button with a tap action.
class AknSegmented<T> extends StatelessWidget {
  const AknSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
  });

  final List<FilterOption<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final n = segments.length;
    final index = segments.indexWhere((s) => s.value == value);
    final duration = AknMotion.of(context, AknMotion.base);
    final x = n <= 1 || index < 0 ? -1.0 : -1 + 2 * index / (n - 1);
    return Padding(
      padding: margin,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: c.isDark ? c.surface : c.surfaceAlt,
          borderRadius: BorderRadius.circular(AknRadius.md),
          border: Border.all(color: c.lineSoft),
        ),
        child: Stack(
          children: [
            if (index >= 0)
              Positioned.fill(
                child: AnimatedAlign(
                  duration: duration,
                  curve: AknMotion.emphasizedCurve,
                  alignment: Alignment(x, 0),
                  child: FractionallySizedBox(
                    widthFactor: 1 / n,
                    heightFactor: 1,
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.isDark ? c.surfaceAlt : c.surface,
                        borderRadius: BorderRadius.circular(AknRadius.sm + 1),
                        boxShadow: AknShadows.card(c),
                      ),
                    ),
                  ),
                ),
              ),
            Row(
              children: [
                for (var i = 0; i < n; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: i == index,
                      inMutuallyExclusiveGroup: true,
                      label: segments[i].count == null
                          ? segments[i].label
                          : '${segments[i].label}, ${segments[i].count}',
                      excludeSemantics: true,
                      onTap: () {
                        if (i != index) onChanged(segments[i].value);
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (i == index) return;
                          AknHaptics.selection();
                          onChanged(segments[i].value);
                        },
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: AknSpace.minTap,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: AnimatedDefaultTextStyle(
                                    duration: duration,
                                    style: t.label.copyWith(
                                      color: i == index ? c.ink : c.text,
                                      fontWeight: i == index
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                    ),
                                    child: Text(
                                      segments[i].label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                                if ((segments[i].count ?? 0) > 0) ...[
                                  const SizedBox(width: 5),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: i == index
                                          ? c.brandFill
                                          : c.lineStrong,
                                      borderRadius: AknRadius.pillAll,
                                    ),
                                    child: Text(
                                      '${segments[i].count}',
                                      style: TextStyle(
                                        color: i == index
                                            ? c.onBrandFill
                                            : c.ink,
                                        fontSize: 11,
                                        height: 16 / 11,
                                        fontWeight: FontWeight.w700,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}

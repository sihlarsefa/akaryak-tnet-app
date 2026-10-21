import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

/// Bugün / Yaklaşan / Geçmiş sekmeleri: kayan seçim zemini, sayı rozeti, her bölüm en az 48 dp
/// (spec C.7 dokunma hedefi). Görünüm tasarım sistemindeki segmentli denetimle aynıdır.
class DriverTabs<T> extends StatelessWidget {
  const DriverTabs({
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
                      label: (segments[i].count ?? 0) > 0
                          ? '${segments[i].label}, ${segments[i].count}'
                          : segments[i].label,
                      onTap: () => _select(i, index),
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _select(i, index),
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
                                  const SizedBox(width: 6),
                                  _CountPill(
                                    count: segments[i].count!,
                                    selected: i == index,
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

  void _select(int i, int current) {
    if (i == current) return;
    AknHaptics.selection();
    onChanged(segments[i].value);
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count, required this.selected});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return AnimatedContainer(
      duration: AknMotion.of(context, AknMotion.base),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: selected ? c.brandFill : c.lineStrong,
        borderRadius: AknRadius.pillAll,
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          color: selected ? c.onBrandFill : c.ink,
          fontSize: 11,
          height: 16 / 11,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

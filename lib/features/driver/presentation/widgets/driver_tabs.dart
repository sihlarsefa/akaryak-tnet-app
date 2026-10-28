import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

/// Bugün / Yaklaşan / Geçmiş (tasarım v3 §4 bölümlü denetim): `surfaceAlt` hap iz (4 px iç boşluk),
/// seçili bölümde beyaz hap başparmak (kart gölgesiyle; koyu temada yükseltilmiş yüzey) yaylı
/// eğriyle kayar; seçili etiket mürekkep 700, diğerleri soluk 600. Sayı etiketin yanında küçük bir
/// hapta (seçilince yumuşak turuncu zemin, Pas yazı) ve değişince yaylanarak yenilenir. Hareket
/// azaltılınca anında. Sürücü kipinde her bölümün dokunma alanı 64 yüksek.
class DriverTabs<T> extends StatelessWidget {
  const DriverTabs({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.margin = const EdgeInsets.symmetric(horizontal: AknSpace.page),
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
    final duration = AknMotion.of(context, AknMotion.thumb);
    final x = n <= 1 || index < 0 ? -1.0 : -1 + 2 * index / (n - 1);
    final hit = context.minTap;
    const inset = 4.0;
    final labelStyle = t.label.copyWith(fontWeight: FontWeight.w600);
    return Padding(
      padding: margin,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: hit),
        child: Stack(
          children: [
            Positioned.fill(
              // Yaylı kayışın taşması izin içinde kalır (hap biçiminde kırpılır).
              child: Container(
                padding: const EdgeInsets.all(inset),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: AknRadius.pillAll,
                ),
                child: index < 0
                    ? null
                    : AnimatedAlign(
                        duration: duration,
                        curve: AknMotion.curveOf(context, AknMotion.spring),
                        alignment: Alignment(x, 0),
                        child: FractionallySizedBox(
                          widthFactor: 1 / n,
                          heightFactor: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.isDark ? c.surfaceRaised : c.surface,
                              borderRadius: AknRadius.pillAll,
                              boxShadow: AknShadows.card(c),
                            ),
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
                          constraints: BoxConstraints(minHeight: hit),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: inset + 8,
                            ),
                            child: Center(
                              child: AnimatedDefaultTextStyle(
                                duration: duration,
                                style: labelStyle.copyWith(
                                  color: i == index ? c.ink : c.dim,
                                  fontWeight: i == index
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        segments[i].label,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if ((segments[i].count ?? 0) > 0) ...[
                                      const SizedBox(width: 6),
                                      _CountPill(
                                        count: segments[i].count!,
                                        selected: i == index,
                                        duration: duration,
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

/// Bölümdeki sayı hapı: seçiliyken yumuşak turuncu (Pas yazı), değilken beyaz; sayı değişince yeni
/// değer yaylanarak gelir.
class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.count,
    required this.selected,
    required this.duration,
  });

  final int count;
  final bool selected;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return AnimatedContainer(
      duration: duration,
      curve: AknMotion.standard,
      constraints: const BoxConstraints(minWidth: 22),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: selected
            ? c.brandSoft
            : (c.isDark ? c.surfaceRaised : c.surface),
        borderRadius: AknRadius.pillAll,
      ),
      child: AnimatedSwitcher(
        duration: AknMotion.of(context, AknMotion.iconSwap),
        switchInCurve: AknMotion.pop,
        transitionBuilder: (child, a) => ScaleTransition(
          scale: a,
          child: FadeTransition(opacity: a, child: child),
        ),
        child: Text(
          '$count',
          key: ValueKey(count),
          maxLines: 1,
          textAlign: TextAlign.center,
          style: t.captionStrong.copyWith(
            fontFeatures: AknNumerals.tabular,
            color: selected ? c.brandInk : c.dim,
          ),
        ),
      ),
    );
  }
}

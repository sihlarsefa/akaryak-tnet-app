import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

/// Bugün / Yaklaşan / Geçmiş (tasarım v2 §6.11 segmentli denetim): Beton iz (r12, 3 px iç boşluk),
/// seçili bölümde beyaz başparmak (r9, 1 px çizgi) ve mürekkep etiket; diğerleri soluk. Sayı etiketin
/// ardından 500 soluk ("Bugün 3"). Başparmak 220 ms kayar (hareket azaltılınca anında). Sürücü
/// kipinde her bölümün dokunma alanı 64 yüksek (iz 56 + üst/alt 4).
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
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: inset),
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: BorderRadius.circular(AknRadius.md),
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
                          child: Container(
                            decoration: BoxDecoration(
                              color: c.isDark ? c.surfaceRaised : c.surface,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(color: c.line),
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
                                    if ((segments[i].count ?? 0) > 0)
                                      Text(
                                        ' ${segments[i].count}',
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          color: c.dim,
                                        ),
                                      ),
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

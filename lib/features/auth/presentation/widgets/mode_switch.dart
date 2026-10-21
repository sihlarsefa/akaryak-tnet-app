import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

/// İki seçenekli kayan anahtar ("Şifreyle" / "Telefonla"). Her bölüm en az 48 dp; seçili bölüm
/// sesli okumada "seçili" duyurulur, ayrıca kalın yazı ve beyaz zeminle ayrılır (yalnızca renk değil).
class ModeSwitch<T> extends StatelessWidget {
  const ModeSwitch({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final List<({T value, String label, IconData icon})> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final n = options.length;
    final index = options.indexWhere((o) => o.value == value);
    final duration = AknMotion.of(context, AknMotion.base);
    final x = n <= 1 || index < 0 ? -1.0 : -1 + 2 * index / (n - 1);
    return Semantics(
      container: true,
      label: semanticLabel,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: c.isDark ? c.surface : c.surfaceAlt,
          borderRadius: BorderRadius.circular(AknRadius.md + 2),
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
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: c.isDark ? c.surfaceAlt : c.surface,
                        borderRadius: BorderRadius.circular(AknRadius.md - 2),
                        boxShadow: AknShadows.card(c),
                        border: Border.all(color: c.line),
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
                      label: options[i].label,
                      excludeSemantics: true,
                      onTap: i == index ? null : () => _select(i),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _select(i),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: AknSpace.minTap,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  options[i].icon,
                                  size: 18,
                                  color: i == index ? c.brand : c.text,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: AnimatedDefaultTextStyle(
                                    duration: duration,
                                    style: t.label.copyWith(
                                      // dim, surfaceAlt üzerinde AA değil (spec C.5).
                                      color: i == index ? c.ink : c.text,
                                      fontWeight: i == index
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                    ),
                                    child: Text(
                                      options[i].label,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
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

  void _select(int i) {
    final v = options[i].value;
    if (v == value) return;
    AknHaptics.selection();
    onChanged(v);
  }
}

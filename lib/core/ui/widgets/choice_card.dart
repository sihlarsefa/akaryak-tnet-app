import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';
import 'cards.dart';

/// Selectable card for one-of-many choices with more than a label: payment
/// method, delivery point, driver, vehicle. Selection shows a brand border,
/// a soft tint and a filled check (never colour alone).
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.leading,
    this.leadingIcon,
    this.tag,
    this.trailing,
    this.enabled = true,
    this.margin,
  });

  final String title;
  final String? subtitle;
  final bool selected;

  /// Null or [enabled] false disables the card.
  final VoidCallback? onTap;
  final Widget? leading;
  final IconData? leadingIcon;

  /// Small pill next to the title ("Önerilen", "Son kullanılan").
  final String? tag;

  /// Extra content on the right (amount, due date).
  final Widget? trailing;
  final bool enabled;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final active = enabled && onTap != null;
    final duration = AknMotion.of(context, AknMotion.base);
    final lead =
        leading ??
        (leadingIcon == null
            ? null
            : AknIconBox(
                icon: leadingIcon!,
                tone: selected ? AknTone.brand : null,
              ));
    Widget card = Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      enabled: active,
      label: [title, ?subtitle, ?tag].join(', '),
      excludeSemantics: trailing == null,
      // Ekran okuyucu seçebilsin (iç InkWell'in eylemi dışlanıyor).
      onTap: active ? onTap : null,
      child: AnimatedContainer(
        duration: duration,
        curve: AknMotion.standard,
        decoration: BoxDecoration(
          color: selected ? c.brandSoft : c.surface,
          borderRadius: AknRadius.card,
          border: Border.all(
            color: selected ? c.brand : c.line,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: AknRadius.card,
            onTap: active
                ? () {
                    AknHaptics.selection();
                    onTap!();
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  if (lead != null) ...[lead, const SizedBox(width: 12)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              title,
                              style: t.bodyStrong.copyWith(
                                color: active ? c.ink : c.faint,
                              ),
                            ),
                            if (tag != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: c.brandTone.bg,
                                  borderRadius: AknRadius.pillAll,
                                  border: Border.all(color: c.brandTone.line),
                                ),
                                child: Text(
                                  tag!,
                                  style: t.captionStrong.copyWith(
                                    color: c.brandTone.fg,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(subtitle!, style: t.bodySmall),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    trailing!,
                  ],
                  const SizedBox(width: 12),
                  _CheckMark(selected: selected, colors: c),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (margin != null) card = Padding(padding: margin!, child: card);
    return card;
  }
}

class _CheckMark extends StatelessWidget {
  const _CheckMark({required this.selected, required this.colors});

  final bool selected;
  final AknColors colors;

  @override
  Widget build(BuildContext context) {
    final duration = AknMotion.of(context, AknMotion.fast);
    return AnimatedContainer(
      duration: duration,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? colors.brandFill : const Color(0x00000000),
        border: Border.all(
          color: selected ? colors.brandFill : colors.lineStrong,
          width: 2,
        ),
      ),
      child: AnimatedSwitcher(
        duration: duration,
        child: selected
            ? Icon(
                Icons.check_rounded,
                key: const ValueKey('on'),
                size: 14,
                color: colors.onBrandFill,
              )
            : const SizedBox.shrink(key: ValueKey('off')),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';

/// Selectable tile for one-of-many choices with more than a label (§6.25):
/// product, payment method, delivery point, driver, vehicle.
///
/// White, 1 px hairline, r12, padding 14 / 16; the title is 17/22 600 and
/// the subtitle 14/20 dim ("son alım 42,35 ₺/L"). Selected = a 2 px ink
/// border and a filled ink check top-right — never an orange fill, never
/// colour alone. Pressed = Beton. Disabled = Beton fill and faint text.
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

  /// A plain 24 px dim icon before the texts (never in a tinted box).
  final IconData? leadingIcon;

  /// Small tag next to the title ("Önerilen", "Son kullanılan"): a Beton
  /// label, r6.
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
    final duration = AknMotion.of(context, AknMotion.fast);
    final lead =
        leading ??
        (leadingIcon == null
            ? null
            : Icon(
                leadingIcon,
                size: 24,
                color: active ? (selected ? c.ink : c.dim) : c.faint,
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
        foregroundDecoration: BoxDecoration(
          borderRadius: AknRadius.card,
          border: Border.all(
            color: selected ? c.ink : c.line,
            width: selected ? 2 : 1,
          ),
        ),
        decoration: BoxDecoration(
          color: active ? c.surface : c.surfaceAlt,
          borderRadius: AknRadius.card,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: AknRadius.card,
            splashFactory: NoSplash.splashFactory,
            highlightColor: c.surfaceAlt,
            onTap: active
                ? () {
                    AknHaptics.selection();
                    onTap!();
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (lead != null) ...[lead, const SizedBox(width: 14)],
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
                              style: t.headline.copyWith(
                                color: active ? c.ink : c.faint,
                              ),
                            ),
                            if (tag != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: c.surfaceAlt,
                                  borderRadius: AknRadius.tag,
                                ),
                                child: Text(
                                  tag!,
                                  style: t.captionStrong.copyWith(
                                    color: active ? c.ink : c.faint,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: t.bodySmall.copyWith(
                              color: active ? c.dim : c.faint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    trailing!,
                  ],
                  const SizedBox(width: 10),
                  _CheckMark(selected: selected, colors: c, enabled: active),
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

/// Top-right selection mark: a filled ink check when selected, an empty
/// control ring otherwise.
class _CheckMark extends StatelessWidget {
  const _CheckMark({
    required this.selected,
    required this.colors,
    required this.enabled,
  });

  final bool selected;
  final AknColors colors;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final duration = AknMotion.of(context, AknMotion.fast);
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: SizedBox.square(
        dimension: 20,
        child: AnimatedSwitcher(
          duration: duration,
          child: selected
              ? Icon(
                  Icons.check_circle_rounded,
                  key: const ValueKey('on'),
                  size: 20,
                  color: colors.ink,
                )
              : Container(
                  key: const ValueKey('off'),
                  margin: const EdgeInsets.all(1.5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: enabled ? colors.lineStrong : colors.line,
                      width: 1.5,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

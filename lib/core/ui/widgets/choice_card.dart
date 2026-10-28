import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';

/// Selectable tile for one-of-many choices with more than a label (§4,
/// v2 §6.25): product, payment method, delivery point, driver, vehicle.
///
/// A white card (r20) floating on the page with the soft card shadow (dark: a
/// 1 px `line`), padding 16; an optional 40 px icon tile ([leadingIcon]),
/// the title 16/22 700 and the subtitle 14/20 dim ("son alım 42,35 ₺/L").
/// Selected = a 2 px orange border, a soft orange wash over the card, the
/// icon tile turning white with an orange glyph and a filled orange check
/// that pops in top-right — never colour alone (the check and the screen
/// reader's "seçili"). The change animates (~280 ms); a press scales the card
/// to 0.98 with a selection haptic. Disabled = `surfaceAlt` fill, faint text.
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

  /// An icon in a 40 px rounded tile before the texts (`surfaceAlt` with an
  /// ink glyph; white with an orange glyph when selected).
  final IconData? leadingIcon;

  /// Small tag next to the title ("Önerilen", "Son kullanılan"): a
  /// `surfaceAlt` label, r8.
  final String? tag;

  /// Extra content on the right (amount, due date); it moves under the
  /// texts at large text sizes.
  final Widget? trailing;
  final bool enabled;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final active = enabled && onTap != null;
    Widget card = Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: selected,
      enabled: active,
      label: [title, ?subtitle, ?tag].join(', '),
      excludeSemantics: trailing == null,
      // Ekran okuyucu seçebilsin (iç InkWell'in eylemi dışlanıyor).
      onTap: active ? onTap : null,
      child: PressScale(
        enabled: active,
        scale: 0.98,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: selected ? 1 : 0),
          duration: AknMotion.of(context, const Duration(milliseconds: 280)),
          curve: AknMotion.standard,
          builder: (context, s, _) =>
              _ChoiceBody(card: this, active: active, progress: s),
        ),
      ),
    );
    if (margin != null) card = Padding(padding: margin!, child: card);
    return card;
  }
}

/// The card at selection [progress] (0 rest → 1 selected).
class _ChoiceBody extends StatelessWidget {
  const _ChoiceBody({
    required this.card,
    required this.active,
    required this.progress,
  });

  final ChoiceCard card;
  final bool active;
  final double progress;

  static Color _mix(Color a, Color b, double t) =>
      t <= 0 ? a : (t >= 1 ? b : Color.lerp(a, b, t)!);

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final s = progress.clamp(0.0, 1.0);
    final base = active ? c.surface : c.surfaceAlt;
    // The soft orange wash: brandSoft at the top easing into the card.
    final wash = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        _mix(base, c.brandSoft, s),
        _mix(base, Color.lerp(c.brandSoft, base, 0.45)!, s),
      ],
    );
    final restBorder = c.isDark ? c.line : base.withValues(alpha: 0);
    final border = BorderSide(
      color: _mix(restBorder, c.brand, s),
      width: c.isDark ? 1 + s : 2,
      strokeAlign: BorderSide.strokeAlignInside,
    );
    final title = active ? c.ink : c.faint;
    final lead =
        card.leading ??
        (card.leadingIcon == null
            ? null
            : _IconTile(icon: card.leadingIcon!, active: active, progress: s));
    // The trailing content (an amount, a due date) sits on the right at
    // normal text sizes, never wider than ~40 % of the screen; at large text
    // sizes it moves under the texts so the title keeps its width.
    final trailing = card.trailing;
    final stacked =
        trailing != null && MediaQuery.textScalerOf(context).scale(10) >= 13;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: wash,
        borderRadius: AknRadius.card,
        border: Border.fromBorderSide(border),
        boxShadow: active && !c.isDark ? AknShadows.card(c) : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: AknRadius.card,
          splashFactory: NoSplash.splashFactory,
          highlightColor: c.ink.withValues(alpha: 0.04),
          onTap: active
              ? () {
                  AknHaptics.selection();
                  card.onTap!();
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
                            card.title,
                            style: t.headline.copyWith(
                              fontSize: 16,
                              height: 22 / 16,
                              color: title,
                            ),
                          ),
                          if (card.tag != null)
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: _mix(c.surfaceAlt, c.surface, s),
                                borderRadius: AknRadius.tag,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                child: Text(
                                  card.tag!,
                                  style: t.captionStrong.copyWith(
                                    color: active
                                        ? _mix(c.ink, c.brandInk, s)
                                        : c.faint,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (card.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          card.subtitle!,
                          style: t.bodySmall.copyWith(
                            color: active ? c.dim : c.faint,
                          ),
                        ),
                      ],
                      if (stacked) ...[const SizedBox(height: 8), trailing],
                    ],
                  ),
                ),
                if (trailing != null && !stacked) ...[
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.4,
                    ),
                    child: trailing,
                  ),
                ],
                const SizedBox(width: 10),
                _CheckMark(selected: card.selected, colors: c, enabled: active),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The 40 px icon tile: `surfaceAlt` with an ink glyph at rest; selected it
/// turns white (dark: the card) with an orange glyph and a tiny lift.
class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.icon,
    required this.active,
    required this.progress,
  });

  final IconData icon;
  final bool active;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final s = progress;
    final fill = Color.lerp(c.surfaceAlt, c.isDark ? c.surface : c.plate, s)!;
    final glyph = active ? Color.lerp(c.ink, c.plateAccent, s)! : c.faint;
    return Transform.scale(
      scale: 1 + 0.04 * s,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? fill : c.surfaceAlt,
          borderRadius: const BorderRadius.all(Radius.circular(AknRadius.sm)),
          boxShadow: s > 0 && active && !c.isDark
              ? [
                  BoxShadow(
                    color: c.plateAccent.withValues(alpha: 0.16 * s),
                    offset: Offset(0, 3 * s),
                    blurRadius: 8 * s,
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: Icon(icon, size: 22, color: glyph),
      ),
    );
  }
}

/// Top-right selection mark: a filled orange check that pops in when
/// selected, an empty control ring otherwise.
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
    final duration = AknMotion.of(context, const Duration(milliseconds: 320));
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: SizedBox.square(
        dimension: 22,
        child: AnimatedSwitcher(
          duration: duration,
          reverseDuration: AknMotion.of(context, AknMotion.fast),
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a.drive(CurveTween(curve: Curves.easeOut)),
            child: ScaleTransition(
              scale: a.drive(
                Tween<double>(
                  begin: 0.3,
                  end: 1,
                ).chain(CurveTween(curve: AknMotion.pop)),
              ),
              child: child,
            ),
          ),
          child: selected
              ? Icon(
                  PhosphorIconsFill.checkCircle,
                  key: const ValueKey('on'),
                  size: 22,
                  color: colors.brandFill,
                )
              : Container(
                  key: const ValueKey('off'),
                  margin: const EdgeInsets.all(2),
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

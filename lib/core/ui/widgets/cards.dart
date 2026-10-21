import 'package:flutter/material.dart';

import '../motion.dart';
import '../painters/hero_backdrop.dart';
import '../status.dart';
import '../theme.dart';
import '../tokens.dart';
import '../typography.dart';

/// White content card: 12 px radius, 1 px line, soft shadow. With [onTap]
/// it gets an ink response and a subtle press scale.
class AknCard extends StatelessWidget {
  const AknCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = AknSpace.cardPadding,
    this.margin,
    this.color,
    this.borderColor,
    this.radius = AknRadius.md,
    this.accent,
    this.shadow = true,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Color? borderColor;
  final double radius;

  /// A 3 px stripe on the leading edge in this tone (needs attention).
  final AknTone? accent;
  final bool shadow;

  /// Read as one node by screen readers (whole card is one action).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: borderColor ?? c.line),
    );
    Widget content = Padding(padding: padding, child: child);
    if (accent != null) {
      content = Stack(
        children: [
          content,
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: ColoredBox(color: c.tone(accent!).fg),
          ),
        ],
      );
    }
    final interactive = onTap != null || onLongPress != null;
    Widget card = interactive
        ? _PressableSurface(
            color: color ?? c.surface,
            shape: shape,
            onTap: onTap,
            onLongPress: onLongPress,
            child: content,
          )
        : Material(
            color: color ?? c.surface,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: content,
          );
    if (shadow) {
      card = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: AknShadows.card(c),
        ),
        child: card,
      );
    }
    if (semanticLabel != null) {
      card = Semantics(
        label: semanticLabel,
        button: interactive,
        container: true,
        child: card,
      );
    }
    if (margin != null) card = Padding(padding: margin!, child: card);
    return card;
  }
}

/// Material surface with ink and a subtle press scale that follows the ink
/// highlight, so it releases as soon as a scroll takes over the gesture.
class _PressableSurface extends StatefulWidget {
  const _PressableSurface({
    required this.color,
    required this.shape,
    required this.child,
    this.onTap,
    this.onLongPress,
  });

  final Color color;
  final ShapeBorder shape;
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<_PressableSurface> createState() => _PressableSurfaceState();
}

class _PressableSurfaceState extends State<_PressableSurface> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed && !AknMotion.reduced(context) ? 0.985 : 1,
      duration: AknMotion.fast,
      curve: AknMotion.standard,
      child: Material(
        color: widget.color,
        shape: widget.shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          onHighlightChanged: (v) {
            if (v != _pressed) setState(() => _pressed = v);
          },
          child: widget.child,
        ),
      ),
    );
  }
}

/// Navy hero panel with a subtle diagonal light (home headers, status hero).
///
/// Inside, the theme switches to an on-navy palette: `context.akn.ink` is
/// white, `dim` is a soft slate, surfaces become raised navy. So text styles,
/// KPI tiles and cards placed in the hero just work — as long as they read
/// the styles from a context inside the panel (a child widget or a
/// `Builder`); styles captured above the panel keep the page colours.
class AknHeroPanel extends StatelessWidget {
  const AknHeroPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 20),
    this.borderRadius = AknRadius.hero,
    this.watermark = true,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final bool watermark;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    Widget panel = ClipRRect(
      borderRadius: borderRadius,
      child: CustomPaint(
        painter: HeroBackdropPainter(navy: c.navy, watermark: watermark),
        child: Padding(
          padding: padding,
          child: OnNavy(child: child),
        ),
      ),
    );
    if (margin != null) panel = Padding(padding: margin!, child: panel);
    return panel;
  }
}

/// Re-themes its subtree for content placed on navy.
class OnNavy extends StatelessWidget {
  const OnNavy({super.key, required this.child});

  final Widget child;

  static AknColors palette(AknColors base) => base.copyWith(
    ink: const Color(0xFFFFFFFF),
    text: const Color(0xFFE2E8F0),
    dim: base.onNavyDim,
    faint: const Color(0xFF8A97A8),
    line: const Color(0x1FFFFFFF),
    lineSoft: const Color(0x14FFFFFF),
    lineStrong: const Color(0x33FFFFFF),
    surface: base.navyRaised,
    surfaceAlt: const Color(0xFF334155),
    surfaceRaised: base.navyRaised,
    bg: base.navy,
    brand: const Color(0xFFF08A55),
    brandInk: const Color(0xFFF5A372),
    brandSoft: const Color(0x29FF5001),
    brandLine: const Color(0x52FF5001),
    shadow: const Color(0x00000000),
    skeleton: const Color(0x1AFFFFFF),
    skeletonHighlight: const Color(0x2EFFFFFF),
    link: const Color(0xFF93C5FD),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = context.akn;
    final navy = palette(base);
    final text = AknTextStyles.from(navy);
    return Theme(
      data: theme.copyWith(
        extensions: theme.extensions.values
            .where((e) => e is! AknColors && e is! AknTextStyles)
            .followedBy([navy, text]),
        textTheme: AknTextStyles.textTheme(navy),
        iconTheme: const IconThemeData(color: Color(0xFFFFFFFF), size: 22),
        iconButtonTheme: IconButtonThemeData(
          style: (theme.iconButtonTheme.style ?? const ButtonStyle()).copyWith(
            foregroundColor: const WidgetStatePropertyAll<Color>(
              Color(0xFFFFFFFF),
            ),
            overlayColor: const WidgetStatePropertyAll<Color>(
              Color(0x1FFFFFFF),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: (theme.textButtonTheme.style ?? const ButtonStyle()).copyWith(
            foregroundColor: WidgetStatePropertyAll<Color>(navy.brandInk),
            overlayColor: const WidgetStatePropertyAll<Color>(
              Color(0x1FFFFFFF),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: (theme.outlinedButtonTheme.style ?? const ButtonStyle())
              .copyWith(
                foregroundColor: const WidgetStatePropertyAll<Color>(
                  Color(0xFFFFFFFF),
                ),
                backgroundColor: WidgetStatePropertyAll<Color>(navy.surface),
                side: WidgetStatePropertyAll<BorderSide>(
                  BorderSide(color: navy.lineStrong),
                ),
              ),
        ),
        colorScheme: theme.colorScheme.copyWith(
          onSurface: const Color(0xFFFFFFFF),
          onSurfaceVariant: base.onNavyDim,
          surface: base.navyRaised,
        ),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: navy.text),
        child: IconTheme.merge(
          data: const IconThemeData(color: Color(0xFFFFFFFF)),
          child: child,
        ),
      ),
    );
  }
}

/// Rounded square holding an icon (list leading, KPI icon).
class AknIconBox extends StatelessWidget {
  const AknIconBox({
    super.key,
    required this.icon,
    this.tone,
    this.size = 40,
    this.iconSize,
  });

  final IconData icon;
  final AknTone? tone;
  final double size;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = tone == null ? null : c.tone(tone!);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: t?.bg ?? c.surfaceAlt,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: iconSize ?? size * 0.5, color: t?.fg ?? c.text),
    );
  }
}

/// List row: leading, title/subtitle, meta text and/or trailing, chevron
/// when tappable. Wraps at large text sizes (no fixed height).
class AknListTile extends StatelessWidget {
  const AknListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.leadingIcon,
    this.leadingTone,
    this.trailing,
    this.meta,
    this.onTap,
    this.onLongPress,
    this.showChevron,
    this.dense = false,
    this.titleMaxLines = 2,
    this.subtitleMaxLines = 2,
    this.padding,
    this.semanticLabel,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;

  /// Shorthand for an [AknIconBox] leading.
  final IconData? leadingIcon;
  final AknTone? leadingTone;
  final Widget? trailing;

  /// Small right-aligned text (time, amount).
  final String? meta;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Defaults to true when [onTap] is set and there is no [trailing].
  final bool? showChevron;
  final bool dense;
  final int titleMaxLines;
  final int subtitleMaxLines;
  final EdgeInsetsGeometry? padding;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final chevron = showChevron ?? (onTap != null && trailing == null);
    final lead =
        leading ??
        (leadingIcon == null
            ? null
            : AknIconBox(
                icon: leadingIcon!,
                tone: leadingTone,
                size: dense ? 36 : 40,
              ));
    // Büyük yazıda (≥ 1,3×) sağdaki kısa metin ve ek öğe başlığın altına iner: dar ekranda taşmaz
    // (spec C.7).
    final stack = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final metaText = meta == null
        ? null
        : Text(
            meta!,
            style: t.caption.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          );
    final row = Padding(
      padding:
          padding ??
          EdgeInsets.symmetric(horizontal: 16, vertical: dense ? 8 : 12),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: dense ? 32 : 40),
        child: Row(
          children: [
            if (lead != null) ...[lead, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: t.bodyStrong,
                    maxLines: stack ? titleMaxLines + 1 : titleMaxLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: t.bodySmall,
                      maxLines: stack ? subtitleMaxLines + 1 : subtitleMaxLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (stack && metaText != null) ...[
                    const SizedBox(height: 2),
                    metaText,
                  ],
                  if (stack && trailing != null) ...[
                    const SizedBox(height: 6),
                    trailing!,
                  ],
                ],
              ),
            ),
            if (!stack && metaText != null) ...[
              const SizedBox(width: 12),
              metaText,
            ],
            if (!stack && trailing != null) ...[
              const SizedBox(width: 12),
              trailing!,
            ],
            if (chevron) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, color: c.faint, size: 22),
            ],
          ],
        ),
      ),
    );
    final interactive = onTap != null || onLongPress != null;
    Widget tile = interactive
        ? InkWell(onTap: onTap, onLongPress: onLongPress, child: row)
        : row;
    if (semanticLabel != null) {
      tile = Semantics(
        label: semanticLabel,
        button: interactive,
        excludeSemantics: true,
        onTap: onTap,
        child: tile,
      );
    }
    return tile;
  }
}

/// Section title with an optional count and a trailing action ("Tümü").
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.count,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(16, 24, 8, 8),
  });

  final String title;
  final String? subtitle;
  final int? count;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text.rich(
                    TextSpan(
                      text: title,
                      children: [
                        if (count != null)
                          TextSpan(
                            text: '  $count',
                            style: t.label.copyWith(color: c.dim),
                          ),
                      ],
                    ),
                    style: t.bodyStrong.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: t.caption),
                ],
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            // Esnek: büyük yazıda eylem metni kısalır, başlığı taşırmaz.
            Flexible(
              child: TextButton(
                onPressed: onAction,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        actionLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right_rounded, size: 18),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A label / value pair (server facts, summaries). Values use tabular
/// figures; [tone] colours the value and adds a dot (never colour alone:
/// the value text carries the meaning).
class FactRow extends StatelessWidget {
  const FactRow({
    super.key,
    required this.label,
    required this.value,
    this.tone,
    this.icon,
    this.valueStyle,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  final String label;
  final String value;
  final AknTone? tone;
  final IconData? icon;
  final TextStyle? valueStyle;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final tc = tone == null || tone == AknTone.neutral ? null : c.tone(tone!);
    final vStyle = (valueStyle ?? t.amount).copyWith(
      color: tc?.fg,
      fontSize: 14,
    );
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Padding(
        padding: padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: c.dim),
              const SizedBox(width: 8),
            ],
            Expanded(
              flex: 5,
              child: Text(label, style: t.bodySmall.copyWith(fontSize: 14)),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 6,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (tc != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Icon(
                        AknStatus.toneIcon(tone!),
                        size: 12,
                        color: tc.fg,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(value, style: vStyle, textAlign: TextAlign.end),
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

/// Inline notice: tinted box with icon, optional title, message and action.
class AknBanner extends StatelessWidget {
  const AknBanner({
    super.key,
    required this.message,
    this.title,
    this.tone = AknTone.info,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.onClose,
    this.margin,
  });

  final String message;
  final String? title;
  final AknTone tone;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onClose;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final tc = c.tone(tone);
    Widget banner = Container(
      decoration: BoxDecoration(
        color: tc.bg,
        borderRadius: AknRadius.card,
        border: Border.all(color: tc.line),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              icon ?? AknStatus.toneIcon(tone),
              color: tc.fg,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null) ...[
                    Text(title!, style: t.bodyStrong.copyWith(color: tc.fg)),
                    const SizedBox(height: 2),
                  ],
                  Text(message, style: t.body.copyWith(color: c.text)),
                  if (actionLabel != null && onAction != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: TextButton(
                        onPressed: onAction,
                        style: TextButton.styleFrom(
                          foregroundColor: tc.fg,
                          padding: const EdgeInsets.symmetric(horizontal: 0),
                          alignment: Alignment.centerLeft,
                        ),
                        child: Text(actionLabel!),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (onClose != null)
            // 48 dp dokunma hedefi (spec C.7); simge küçük kalır.
            Transform.translate(
              offset: const Offset(8, -12),
              child: IconButton(
                iconSize: 18,
                constraints: const BoxConstraints(
                  minWidth: AknSpace.minTap,
                  minHeight: AknSpace.minTap,
                ),
                tooltip: 'Kapat',
                onPressed: onClose,
                icon: Icon(Icons.close_rounded, color: c.dim),
              ),
            ),
        ],
      ),
    );
    if (margin != null) banner = Padding(padding: margin!, child: banner);
    return Semantics(container: true, liveRegion: true, child: banner);
  }
}

/// Horizontal usage meter (limit usage). Brand below [warnAt], warn up to
/// [dangerAt], danger beyond; the fill animates on change.
class UsageBar extends StatelessWidget {
  const UsageBar({
    super.key,
    required this.value,
    this.label,
    this.valueLabel,
    this.warnAt = 0.8,
    this.dangerAt = 1.0,
    this.height = 8,
    this.tone,
  });

  /// 0..1 (values above 1 show a full danger bar).
  final double value;
  final String? label;
  final String? valueLabel;
  final double warnAt;
  final double dangerAt;
  final double height;

  /// Overrides the threshold colour.
  final AknTone? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final v = value.isNaN ? 0.0 : value;
    final effective =
        tone ??
        (v >= dangerAt
            ? AknTone.danger
            : v >= warnAt
            ? AknTone.warn
            : AknTone.brand);
    final color = effective == AknTone.brand ? c.brand : c.tone(effective).fg;
    return Semantics(
      label: label,
      value: valueLabel ?? '%${(v * 100).round()}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null || valueLabel != null) ...[
            // Büyük yazıda değer etiketin altına iner (spec C.7).
            Flex(
              direction: MediaQuery.textScalerOf(context).scale(10) >= 13
                  ? Axis.vertical
                  : Axis.horizontal,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (MediaQuery.textScalerOf(context).scale(10) >= 13)
                  Text(label ?? '', style: t.caption)
                else
                  Expanded(child: Text(label ?? '', style: t.caption)),
                if (valueLabel != null)
                  Text(
                    valueLabel!,
                    style: t.captionStrong.copyWith(
                      color: effective == AknTone.brand ? c.ink : color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          ClipRRect(
            borderRadius: AknRadius.pillAll,
            child: SizedBox(
              height: height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: c.lineSoft),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: v.clamp(0.0, 1.0)),
                    duration: AknMotion.of(context, AknMotion.slow),
                    curve: AknMotion.emphasizedCurve,
                    builder: (context, f, _) => FractionallySizedBox(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: f,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: AknRadius.pillAll,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Amount text with tabular figures (`1.234,56 ₺`). Format with `Fmt`
/// (`core/utils/format.dart`); the app never computes money except
/// "tahmini" values.
class AmountText extends StatelessWidget {
  const AmountText(
    this.text, {
    super.key,
    this.large = false,
    this.color,
    this.style,
    this.textAlign,
  });

  final String text;
  final bool large;
  final Color? color;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final base = style ?? (large ? t.amountLarge : t.amount);
    return Text(
      text,
      textAlign: textAlign,
      style: base.copyWith(
        color: color,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

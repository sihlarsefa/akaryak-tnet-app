import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion.dart';
import '../painters/hero_backdrop.dart';
import '../status.dart';
import '../theme.dart';
import '../tokens.dart';
import '../typography.dart';

/// White content card: 20 px radius, soft diffuse shadow, no hard border
/// (a barely visible `lineSoft` hairline in light mode, `line` in dark).
///
/// With [onTap] it gets an ink response, a selection haptic and a press
/// that scales to 0.985 while the shadow settles closer to the surface.
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
    this.radius = AknRadius.lg,
    this.accent,
    this.shadow = true,
    this.semanticLabel,
    this.haptic = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final Color? borderColor;
  final double radius;

  /// A 4 px stripe on the leading edge in this tone (needs attention).
  final AknTone? accent;
  final bool shadow;

  /// Read as one node by screen readers (whole card is one action).
  final String? semanticLabel;

  /// Selection haptic on tap (primary cards); false for dense lists.
  final bool haptic;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: borderColor ?? (c.isDark ? c.line : c.lineSoft)),
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
            width: 4,
            child: ColoredBox(color: c.tone(accent!).fg),
          ),
        ],
      );
    }
    final interactive = onTap != null || onLongPress != null;
    Widget card = _CardSurface(
      color: color ?? c.surface,
      shape: shape,
      radius: radius,
      shadow: shadow,
      onTap: onTap == null
          ? null
          : () {
              if (haptic) AknHaptics.selection();
              onTap!();
            },
      onLongPress: onLongPress,
      child: content,
    );
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

/// Material surface with the card shadow; when tappable, ink plus a subtle
/// press (scale 0.985, shadow down) that follows the ink highlight, so it
/// releases as soon as a scroll takes over the gesture.
class _CardSurface extends StatefulWidget {
  const _CardSurface({
    required this.color,
    required this.shape,
    required this.radius,
    required this.shadow,
    required this.child,
    this.onTap,
    this.onLongPress,
  });

  final Color color;
  final ShapeBorder shape;
  final double radius;
  final bool shadow;
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<_CardSurface> createState() => _CardSurfaceState();
}

class _CardSurfaceState extends State<_CardSurface> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final interactive = widget.onTap != null || widget.onLongPress != null;
    final reduced = AknMotion.reduced(context);
    final pressed = _pressed && !reduced;
    final material = Material(
      color: widget.color,
      shape: widget.shape,
      clipBehavior: Clip.antiAlias,
      child: interactive
          ? InkWell(
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
              onHighlightChanged: (v) {
                if (v != _pressed) setState(() => _pressed = v);
              },
              child: widget.child,
            )
          : widget.child,
    );
    final shadows = !widget.shadow
        ? const <BoxShadow>[]
        : pressed
        ? AknShadows.pressed(c)
        : AknShadows.card(c);
    Widget card = shadows.isEmpty && !interactive
        ? material
        : AnimatedContainer(
            duration: AknMotion.of(context, AknMotion.fast),
            curve: AknMotion.standard,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              boxShadow: shadows,
            ),
            child: material,
          );
    if (interactive) {
      card = AnimatedScale(
        scale: pressed ? 0.985 : 1,
        duration: AknMotion.fast,
        curve: AknMotion.standard,
        child: card,
      );
    }
    return card;
  }
}

/// Orange hero panel (home headers, status heroes on detail screens): the
/// hero gradient (light from the top-right corner, deepening toward the
/// text), a soft white highlight, a faint » watermark and a warm glow under
/// it. 24 px radius.
///
/// Inside, the theme switches to the on-hero palette ([OnHero]):
/// `context.akn.ink`, `text` and `dim` are white, surfaces are dark glass,
/// primary buttons are white with an orange label. Text styles, KPI tiles
/// and cards placed in the hero just work — as long as they read the styles
/// from a context inside the panel (a child widget or a `Builder`).
class AknHeroPanel extends StatelessWidget {
  const AknHeroPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 18, 18, 20),
    this.borderRadius = AknRadius.hero,
    this.watermark = true,
    this.margin,
    this.highlight = true,
    this.glow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final bool watermark;
  final EdgeInsetsGeometry? margin;

  /// Soft white light in the top-right corner.
  final bool highlight;

  /// Warm shadow under the panel.
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    Widget panel = ClipRRect(
      borderRadius: borderRadius,
      child: AknHeroBackground(
        watermark: watermark,
        highlight: highlight,
        child: Padding(
          padding: padding,
          child: OnHero(child: child),
        ),
      ),
    );
    if (glow) {
      panel = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: AknShadows.hero(c),
        ),
        child: panel,
      );
    }
    if (margin != null) panel = Padding(padding: margin!, child: panel);
    return panel;
  }
}

/// Re-themes its subtree for content placed on the orange hero (hero panel,
/// header strip, hero app bar).
///
/// * Text: `ink`, `text` and `dim` are all white — on orange only white
///   keeps 4.5:1 for small text, so hierarchy comes from size and weight.
///   `faint` (white 70 %) is decorative only.
/// * Surfaces (`surface`, `surfaceAlt`, `brandSoft`): dark glass (black 14–
///   18 %), where white text keeps ≥ 4.5:1 — never white glass under text.
/// * Accents (`brand`, `brandBright`, `brandInk`, `link`): white.
/// * Buttons: primary = white fill with an orange label, secondary = dark
///   glass with a white label, text buttons and icons white.
/// * Status tones keep their opaque tints (chips read well on orange).
///
/// DS widgets that need to know (logo, badges) ask [OnHero.isOn].
class OnHero extends StatelessWidget {
  const OnHero({super.key, required this.child});

  final Widget child;

  static const _white = Color(0xFFFFFFFF);

  /// Orange label on white controls placed on the hero (5.2:1).
  static const Color onWhite = Color(0xFFC2410C);

  /// Dark glass (cards, tiles, secondary buttons on the hero).
  static const Color glass = Color(0x24000000);

  /// Deeper dark glass (pills with small text anywhere on the hero).
  static const Color glassStrong = Color(0x2E000000);

  /// The on-hero palette derived from [base] (hero tokens are kept).
  static AknColors palette(AknColors base) => base.copyWith(
    ink: _white,
    text: _white,
    dim: _white,
    faint: const Color(0xB3FFFFFF),
    line: const Color(0x33FFFFFF),
    lineSoft: const Color(0x1FFFFFFF),
    lineStrong: const Color(0x5CFFFFFF),
    surface: glass,
    surfaceAlt: glassStrong,
    surfaceRaised: glass,
    bg: base.heroEnd,
    brand: _white,
    brandPressed: const Color(0xE6FFFFFF),
    brandBright: _white,
    brandInk: _white,
    brandSoft: glass,
    brandLine: const Color(0x4DFFFFFF),
    brandFill: _white,
    brandFillPressed: const Color(0xFFFFEDE3),
    onBrandFill: onWhite,
    shadow: const Color(0x00000000),
    skeleton: const Color(0x26FFFFFF),
    skeletonHighlight: const Color(0x40FFFFFF),
    link: _white,
  );

  /// True inside a hero surface.
  static bool isOn(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_OnHeroScope>() != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // [palette] is idempotent: a hero inside a hero keeps the same palette.
    final base = context.akn;
    final p = palette(base);
    final text = AknTextStyles.from(p);
    const white = _white;
    const overlay = WidgetStatePropertyAll<Color>(Color(0x1FFFFFFF));
    ButtonStyle filled(ButtonStyle? s) => (s ?? const ButtonStyle()).copyWith(
      backgroundColor: WidgetStateProperty.resolveWith(
        (st) => st.contains(WidgetState.disabled)
            ? const Color(0x1FFFFFFF)
            : st.contains(WidgetState.pressed)
            ? p.brandFillPressed
            : white,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (st) => st.contains(WidgetState.disabled) ? p.faint : onWhite,
      ),
      overlayColor: const WidgetStatePropertyAll<Color>(Color(0x14C2410C)),
    );
    return Theme(
      data: theme.copyWith(
        extensions: theme.extensions.values
            .where((e) => e is! AknColors && e is! AknTextStyles)
            .followedBy([p, text]),
        textTheme: AknTextStyles.textTheme(p),
        iconTheme: const IconThemeData(color: white, size: 22),
        primaryIconTheme: const IconThemeData(color: white, size: 22),
        splashColor: const Color(0x1FFFFFFF),
        highlightColor: const Color(0x14FFFFFF),
        hoverColor: const Color(0x0FFFFFFF),
        focusColor: const Color(0x33FFFFFF),
        dividerColor: p.line,
        dividerTheme: theme.dividerTheme.copyWith(color: p.line),
        iconButtonTheme: IconButtonThemeData(
          style: (theme.iconButtonTheme.style ?? const ButtonStyle()).copyWith(
            foregroundColor: const WidgetStatePropertyAll<Color>(white),
            overlayColor: overlay,
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: (theme.textButtonTheme.style ?? const ButtonStyle()).copyWith(
            foregroundColor: const WidgetStatePropertyAll<Color>(white),
            overlayColor: overlay,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: (theme.outlinedButtonTheme.style ?? const ButtonStyle())
              .copyWith(
                foregroundColor: const WidgetStatePropertyAll<Color>(white),
                backgroundColor: const WidgetStatePropertyAll<Color>(glass),
                side: WidgetStatePropertyAll<BorderSide>(
                  BorderSide(color: p.lineStrong),
                ),
                overlayColor: overlay,
              ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: filled(theme.filledButtonTheme.style),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: filled(theme.elevatedButtonTheme.style),
        ),
        progressIndicatorTheme: theme.progressIndicatorTheme.copyWith(
          color: white,
          linearTrackColor: const Color(0x38FFFFFF),
          circularTrackColor: const Color(0x00000000),
        ),
        tabBarTheme: theme.tabBarTheme.copyWith(
          labelColor: white,
          unselectedLabelColor: white,
          indicator: const UnderlineTabIndicator(
            borderSide: BorderSide(color: white, width: 3),
            borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
          ),
          dividerColor: const Color(0x00000000),
          overlayColor: overlay,
        ),
        appBarTheme: theme.appBarTheme.copyWith(
          backgroundColor: const Color(0x00000000),
          foregroundColor: white,
          iconTheme: const IconThemeData(color: white, size: 24),
          actionsIconTheme: const IconThemeData(color: white, size: 24),
          titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
            color: white,
          ),
          systemOverlayStyle: AknTheme.overlayOnHero,
        ),
        chipTheme: theme.chipTheme.copyWith(
          backgroundColor: glass,
          labelStyle: text.label.copyWith(color: white),
          side: BorderSide(color: p.line),
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: white,
          selectionColor: Color(0x4DFFFFFF),
          selectionHandleColor: white,
        ),
        colorScheme: theme.colorScheme.copyWith(
          primary: white,
          onPrimary: onWhite,
          secondary: white,
          onSecondary: onWhite,
          onSurface: white,
          onSurfaceVariant: white,
          surface: base.heroEnd,
          outline: p.lineStrong,
          outlineVariant: p.line,
        ),
      ),
      child: _OnHeroScope(
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: white),
          child: IconTheme.merge(
            data: const IconThemeData(color: white),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Kept for call-sites written for the navy identity: identical to
/// [OnHero] (the hero is orange now).
class OnNavy extends OnHero {
  const OnNavy({super.key, required super.child});

  /// Same as [OnHero.palette].
  static AknColors palette(AknColors base) => OnHero.palette(base);
}

class _OnHeroScope extends InheritedWidget {
  const _OnHeroScope({required super.child});

  @override
  bool updateShouldNotify(_OnHeroScope old) => false;
}

/// Glass pill for small text on the hero (role chips, "Bugün" summary,
/// weather): dark glass with a white hairline, white 13 px label — AA
/// anywhere on the gradient. Optional icon and tap.
class AknHeroChip extends StatelessWidget {
  const AknHeroChip({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.semanticLabel,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    const white = Color(0xFFFFFFFF);
    final pill = Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: EdgeInsets.fromLTRB(icon == null ? 12 : 9, 5, 12, 5),
      decoration: BoxDecoration(
        color: OnHero.glassStrong,
        borderRadius: AknRadius.pillAll,
        border: Border.all(color: const Color(0x38FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: white),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.label.copyWith(color: white),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) {
      return Semantics(
        label: semanticLabel ?? label,
        excludeSemantics: true,
        child: pill,
      );
    }
    return Semantics(
      label: semanticLabel ?? label,
      button: true,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AknHaptics.selection();
          onTap!();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AknSpace.minTap),
          child: Center(widthFactor: 1, child: PressScale(child: pill)),
        ),
      ),
    );
  }
}

/// Rounded square holding an icon (list leading, KPI icon, quick actions).
/// [tone] tints it (brand = orange tile with an orange glyph).
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
    final glyph = tone == AknTone.brand ? c.brand : (t?.fg ?? c.text);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: t?.bg ?? c.surfaceAlt,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: iconSize ?? size * 0.5, color: glyph),
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

/// Section title (17 w800) with an optional count and a trailing orange
/// action ("Tümü").
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
                      fontSize: 17,
                      height: 22 / 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
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

/// Inline notice: soft tinted box (16 px radius) with icon, optional title,
/// message and action.
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
        borderRadius: BorderRadius.circular(AknRadius.lg - 4),
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
              color: tone == AknTone.brand ? c.brand : tc.fg,
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

/// Horizontal usage meter (limit usage). Logo orange below [warnAt], warn up
/// to [dangerAt], danger beyond; the fill animates on change.
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
    final color = effective == AknTone.brand
        ? c.brandBright
        : c.tone(effective).fg;
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
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
              direction: large ? Axis.vertical : Axis.horizontal,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (large)
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
                  ColoredBox(color: c.isDark ? c.line : c.surfaceAlt),
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

/// Status-bar style for a hero surface that reaches the top of the screen
/// (light icons). Most screens get it from `AppScaffold(hero: true)`.
class HeroStatusBar extends StatelessWidget {
  const HeroStatusBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: AknTheme.overlayOnHero,
    child: child,
  );
}

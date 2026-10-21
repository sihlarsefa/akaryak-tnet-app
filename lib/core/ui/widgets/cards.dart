import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion.dart';
import '../status.dart';
import '../theme.dart';
import '../tokens.dart';
import 'buttons.dart';
import 'plate.dart';

export 'plate.dart';

/// The group box (design v2 §6.6): `surface`, a 1 px `line` border, radius
/// 12, padding 16, **no shadow** in either theme.
///
/// Use it for groups in forms and settings and for document tiles only — a
/// list of `AknCard`s is a bug (collections are ledger rows,
/// [AknListTile]). With [onTap] it presses: `surfaceAlt` fill and scale 0.98
/// (90 ms in, 120 ms out), a selection haptic, and the 3 px focus ring for
/// keyboard and switch users.
///
/// [accent] (the old left stripe) and [shadow] are ignored in v2.
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

  /// Deprecated: v2 has no coloured accent strips (ignored).
  final AknTone? accent;

  /// Deprecated: resting cards are flat in v2 (ignored).
  final bool shadow;

  /// Read as one node by screen readers (whole card is one action).
  final String? semanticLabel;

  /// Selection haptic on tap; false for dense lists.
  final bool haptic;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final interactive = onTap != null || onLongPress != null;
    Widget card = _CardSurface(
      color: color ?? c.surface,
      border: borderColor ?? c.line,
      radius: radius,
      onTap: onTap == null
          ? null
          : () {
              if (haptic) AknHaptics.selection();
              onTap!();
            },
      onLongPress: onLongPress,
      child: Padding(padding: padding, child: child),
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

/// The group-box surface: flat, hairline border; when tappable a pressed
/// fill and scale that follow the ink highlight (so a scroll that takes over
/// the gesture releases it) and the focus ring.
class _CardSurface extends StatefulWidget {
  const _CardSurface({
    required this.color,
    required this.border,
    required this.radius,
    required this.child,
    this.onTap,
    this.onLongPress,
  });

  final Color color;
  final Color border;
  final double radius;
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<_CardSurface> createState() => _CardSurfaceState();
}

class _CardSurfaceState extends State<_CardSurface> {
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final interactive = widget.onTap != null || widget.onLongPress != null;
    final reduced = AknMotion.reduced(context);
    final pressed = _pressed && interactive;
    final radius = BorderRadius.circular(widget.radius);
    final duration = pressed ? AknMotion.press : AknMotion.pressOut;
    Widget surface = AnimatedContainer(
      duration: AknMotion.of(context, duration),
      curve: AknMotion.standard,
      decoration: BoxDecoration(
        color: pressed ? c.surfaceAlt : widget.color,
        borderRadius: radius,
        border: Border.all(color: widget.border),
      ),
      foregroundDecoration: _focused
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.fromBorderSide(AknTheme.focusRing(c)),
            )
          : null,
      child: interactive
          ? Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: widget.onTap,
                onLongPress: widget.onLongPress,
                borderRadius: radius,
                splashFactory: NoSplash.splashFactory,
                highlightColor: Colors.transparent,
                hoverColor: Colors.transparent,
                focusColor: Colors.transparent,
                onHighlightChanged: (v) {
                  if (v != _pressed) setState(() => _pressed = v);
                },
                onFocusChange: (v) {
                  if (v != _focused) setState(() => _focused = v);
                },
                child: widget.child,
              ),
            )
          : widget.child,
    );
    if (interactive) {
      surface = AnimatedScale(
        scale: pressed && !reduced ? AknMotion.pressScale : 1,
        duration: duration,
        curve: AknMotion.standard,
        child: surface,
      );
    }
    return surface;
  }
}

/// Deprecated name of the plate (§5.2, §6.28): renders an [AknPlate] — flat
/// plate colour, r20, everything inside printed in plate ink (black) through
/// [OnHero]. [watermark], [highlight] and [glow] are ignored in v2.
///
/// One plate per screen: list pages, settings, profile and onboarding use a
/// plain white header instead.
class AknHeroPanel extends StatelessWidget {
  const AknHeroPanel({
    super.key,
    required this.child,
    this.padding = AknSpace.plate,
    this.borderRadius = AknRadius.hero,
    this.watermark = true,
    this.margin,
    this.highlight = true,
    this.glow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;

  /// Ignored (no watermark chevrons anywhere in v2).
  final bool watermark;
  final EdgeInsetsGeometry? margin;

  /// Ignored (the plate is flat).
  final bool highlight;

  /// Ignored (the plate has no shadow).
  final bool glow;

  @override
  Widget build(BuildContext context) => AknPlate(
    padding: padding.resolve(
      Directionality.maybeOf(context) ?? TextDirection.ltr,
    ),
    borderRadius: borderRadius,
    margin: margin,
    child: child,
  );
}

/// Re-themes its subtree for content printed ON the plate (§2.2, §6.28):
/// the palette is `AknColors.plateInk()` — every ink, mark and link black,
/// hairlines `plateLine`, surfaces the plate, tones without colour — the
/// text styles keep their sizes in black, and stock controls follow the
/// plate rule ("on orange, ink is black": a primary is a black key with a
/// plate-coloured label, outline and text buttons are black).
///
/// [AknPlate] and [AknHeroPanel] apply it; DS widgets that need to know
/// (logo, badges, chips) ask [OnHero.isOn].
class OnHero extends StatelessWidget {
  const OnHero({super.key, required this.child});

  final Widget child;

  /// Deprecated: there are no white controls on the plate in v2 (black).
  static const Color onWhite = Colors.black;

  /// Deprecated: no glass on the plate in v2 (black 12 %).
  static const Color glass = Colors.black12;

  /// Deprecated: no glass on the plate in v2 (black 26 %).
  static const Color glassStrong = Colors.black26;

  /// The plate palette derived from [base] (= `base.plateInk()`).
  static AknColors palette(AknColors base) => base.plateInk();

  /// True inside a plate surface.
  static bool isOn(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_OnHeroScope>() != null;

  @override
  Widget build(BuildContext context) {
    final theme = AknTheme.onPlate(Theme.of(context));
    final ink = theme.extension<AknColors>()?.ink ?? Colors.black;
    return Theme(
      data: theme,
      child: _OnHeroScope(
        child: DefaultTextStyle.merge(
          style: TextStyle(color: ink),
          child: IconTheme.merge(
            data: IconThemeData(color: ink),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Kept for call-sites written for the navy identity: identical to
/// [OnHero].
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

/// A small chip (§6.28): on the plate a black chip with plate-coloured text
/// (like the delta chip); elsewhere it renders as a lamp ([AknLamp], ink).
/// Optional icon and tap (48 px target).
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
    final c = context.akn;
    final t = context.aknText;
    final onPlate = OnHero.isOn(context);
    final Widget visual;
    if (onPlate) {
      final style = t.bodySmall.copyWith(
        height: 24 / 14,
        fontWeight: FontWeight.w700,
        color: c.plate,
      );
      visual = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: c.onPlate,
          borderRadius: AknRadius.tag,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: c.plate),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ],
        ),
      );
    } else {
      visual = AknLamp(label: label, tone: AknTone.info);
    }
    if (onTap == null) {
      return Semantics(
        label: semanticLabel ?? label,
        excludeSemantics: true,
        child: visual,
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
          constraints: const BoxConstraints(
            minHeight: AknSpace.minTap,
            minWidth: AknSpace.minTap,
          ),
          child: Center(widthFactor: 1, child: PressScale(child: visual)),
        ),
      ),
    );
  }
}

/// An icon in its box (§6.28): the icon only — 24 px, dim (or the tone's
/// colour when it carries status) — never a tinted square. [size] keeps the
/// old footprint so layouts do not jump.
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
    final tn = tone;
    final color = tn == null || tn == AknTone.neutral ? c.dim : c.tone(tn).fg;
    final glyph = iconSize ?? (size < 24 ? size : 24.0);
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Icon(icon, size: glyph, color: color),
      ),
    );
  }
}

/// The ledger row (design v2 §6.8) — every item of a collection (orders,
/// quotes, approvals, stops, payments, customers, notifications, documents):
///
/// ```
/// Title (headline 17/22 600)                    338.800,00 ₺  (amount)
/// Second line (bodySmall 14/20 dim)                42,35 ₺/L  (amountMeta)
/// ● Lamp label                           ⏱ 2 sa 57 dk kaldı   (status, +8)
/// [footer, e.g. the route line, +10]
/// ```
///
/// Full-bleed (padding 12/20, min height 64), pressed = `surfaceAlt` across
/// the whole row (90 ms). No leading by default; [leadingIcon] is a plain
/// 24 px dim icon with a 16 px gap. A chevron only on navigation / settings
/// rows (`showChevron: true`). Separate rows with [AknLedgerDivider] (or
/// build the list with [AknLedger]).
///
/// **Reflow**: below 340 px or at text scale ≥ 1.3 the right column moves
/// under the title (title, amount, status, second line, meta) and nothing is
/// cut (titles up to 2 lines, more when stacked).
class AknListTile extends StatefulWidget {
  const AknListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.leadingIcon,
    this.leadingTone,
    this.trailing,
    this.meta,
    this.amount,
    this.amountMeta,
    this.status,
    this.footer,
    this.onTap,
    this.onLongPress,
    this.showChevron,
    this.dense = false,
    this.titleMaxLines = 2,
    this.subtitleMaxLines = 2,
    this.padding,
    this.semanticLabel,
    this.titleStyle,
  });

  final String title;

  /// Second line ("Tuzla Şantiye, 22 Ekim").
  final String? subtitle;
  final Widget? leading;

  /// A plain 24 px icon in front (dim, or the [leadingTone]'s colour).
  final IconData? leadingIcon;
  final AknTone? leadingTone;

  /// A control at the end (switch, small button).
  final Widget? trailing;

  /// Right-aligned text on the title line in `bodySmall` dim (time) — or,
  /// with [amount], the text under it.
  final String? meta;

  /// Right column, line 1: `amount` 17/22 600, never wraps
  /// ("338.800,00 ₺").
  final String? amount;

  /// Right column, line 2: `bodySmall` dim ("42,35 ₺/L", "tahmini").
  final String? amountMeta;

  /// The full-width status line (+8): a lamp and, on the right, a countdown
  /// or a note — see [AknStatusLine].
  final Widget? status;

  /// Under everything (+10): the route line.
  final Widget? footer;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Navigation and settings rows only; collection rows have none.
  final bool? showChevron;
  final bool dense;
  final int titleMaxLines;
  final int subtitleMaxLines;
  final EdgeInsetsGeometry? padding;
  final String? semanticLabel;

  /// Overrides the title style (default `headline` 17/22 600).
  final TextStyle? titleStyle;

  @override
  State<AknListTile> createState() => _AknListTileState();
}

class _AknListTileState extends State<AknListTile> {
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final c = context.akn;
    final t = context.aknText;
    final chevron = w.showChevron ?? false;
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final leadTone = w.leadingTone;
    final lead =
        w.leading ??
        (w.leadingIcon == null
            ? null
            : Icon(
                w.leadingIcon,
                size: 24,
                color: leadTone == null || leadTone == AknTone.neutral
                    ? c.dim
                    : c.tone(leadTone).fg,
              ));
    final titleStyle = (w.titleStyle ?? (w.dense ? t.bodyStrong : t.headline))
        .copyWith(color: (w.titleStyle?.color) ?? c.ink);
    final amountStyle = t.amount.copyWith(color: c.ink);
    final metaStyle = t.bodySmall.copyWith(color: c.dim);
    final rightTop = w.amount ?? (w.amountMeta == null ? w.meta : null);
    final rightBottom = w.amount != null
        ? (w.amountMeta ?? w.meta)
        : w.amountMeta;
    final rightTopStyle = w.amount != null ? amountStyle : metaStyle;

    Widget rowContent(bool stack) {
      final titleText = Text(
        w.title,
        style: titleStyle,
        maxLines: stack ? w.titleMaxLines + 2 : w.titleMaxLines,
        overflow: TextOverflow.ellipsis,
      );
      final sub = w.subtitle;
      final subText = sub == null || sub.isEmpty
          ? null
          : Text(
              sub,
              style: metaStyle,
              maxLines: stack ? w.subtitleMaxLines + 2 : w.subtitleMaxLines,
              overflow: TextOverflow.ellipsis,
            );
      final List<Widget> lines;
      if (stack) {
        lines = [
          titleText,
          if (rightTop != null) ...[
            const SizedBox(height: 2),
            Text(rightTop, style: rightTopStyle),
          ],
          if (w.status != null) ...[const SizedBox(height: 6), w.status!],
          if (subText != null) ...[const SizedBox(height: 4), subText],
          if (rightBottom != null) ...[
            const SizedBox(height: 2),
            Text(rightBottom, style: metaStyle),
          ],
          if (w.footer != null) ...[const SizedBox(height: 10), w.footer!],
          if (w.trailing != null) ...[const SizedBox(height: 8), w.trailing!],
        ];
      } else {
        lines = [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: titleText),
              if (rightTop != null) ...[
                const SizedBox(width: 12),
                Text(
                  rightTop,
                  style: rightTopStyle,
                  maxLines: 1,
                  softWrap: false,
                ),
              ],
            ],
          ),
          if (subText != null || rightBottom != null) ...[
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(child: subText ?? const SizedBox.shrink()),
                if (rightBottom != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    rightBottom,
                    style: metaStyle,
                    maxLines: 1,
                    softWrap: false,
                  ),
                ],
              ],
            ),
          ],
          if (w.status != null) ...[const SizedBox(height: 8), w.status!],
        ];
      }
      final row = Row(
        crossAxisAlignment: stack || w.status != null || w.footer != null
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          if (lead != null) ...[lead, const SizedBox(width: 16)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: lines,
            ),
          ),
          if (!stack && w.trailing != null) ...[
            const SizedBox(width: 12),
            w.trailing!,
          ],
          if (chevron) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, color: c.dim, size: 22),
          ],
        ],
      );
      // The footer (route line) runs under both columns, full width (after
      // the leading icon), +10.
      if (stack || w.footer == null) return row;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          row,
          const SizedBox(height: 10),
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: w.leading == null && w.leadingIcon != null ? 40 : 0,
            ),
            child: w.footer,
          ),
        ],
      );
    }

    final interactive = w.onTap != null || w.onLongPress != null;
    final pad =
        w.padding ??
        (w.dense
            ? const EdgeInsets.symmetric(horizontal: 20, vertical: 8)
            : AknSpace.row);
    final pressed = _pressed && interactive;
    Widget tile = LayoutBuilder(
      builder: (context, constraints) {
        var stack = large || constraints.maxWidth < 340;
        if (!stack && (rightTop != null || rightBottom != null)) {
          // Measured reflow: when the right column would leave the title
          // less than 96 px, it moves under the title instead (nothing
          // truncates, nothing overflows).
          double width(String? text, TextStyle style) {
            if (text == null) return 0;
            final tp = TextPainter(
              text: TextSpan(text: text, style: style),
              textDirection: TextDirection.ltr,
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 1,
            )..layout();
            final w = tp.width;
            tp.dispose();
            return w;
          }

          final resolved = pad.resolve(Directionality.of(context));
          final content =
              constraints.maxWidth -
              resolved.horizontal -
              (lead == null ? 0 : 40) -
              (chevron ? 26 : 0);
          final right = math.max(
            width(rightTop, rightTopStyle),
            width(rightBottom, metaStyle),
          );
          stack = right + 12 > content - 96;
        }
        return AnimatedContainer(
          duration: AknMotion.of(
            context,
            pressed ? AknMotion.press : AknMotion.pressOut,
          ),
          curve: AknMotion.standard,
          color: pressed ? c.surfaceAlt : Colors.transparent,
          foregroundDecoration: _focused
              ? BoxDecoration(
                  border: Border.fromBorderSide(
                    AknTheme.focusRing(
                      c,
                    ).copyWith(strokeAlign: BorderSide.strokeAlignInside),
                  ),
                )
              : null,
          constraints: BoxConstraints(minHeight: w.dense ? 48 : 64),
          padding: pad,
          alignment: AlignmentDirectional.centerStart,
          child: rowContent(stack),
        );
      },
    );
    if (interactive) {
      tile = Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: w.onTap,
          onLongPress: w.onLongPress,
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          onHighlightChanged: (v) {
            if (v != _pressed) setState(() => _pressed = v);
          },
          onFocusChange: (v) {
            if (v != _focused) setState(() => _focused = v);
          },
          child: tile,
        ),
      );
    }
    if (w.semanticLabel != null) {
      tile = Semantics(
        label: w.semanticLabel,
        button: interactive,
        excludeSemantics: true,
        onTap: w.onTap,
        child: tile,
      );
    }
    return tile;
  }
}

/// The ledger row's status line: a lamp on the left and, on the right, a
/// countdown or a short note ("Burak Yılmaz’ın talebi", "varış 11:20").
/// When both do not fit on one line the right part moves under the lamp.
class AknStatusLine extends StatelessWidget {
  const AknStatusLine({super.key, this.lamp, this.trailing});

  final Widget? lamp;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final l = lamp;
    final r = trailing;
    if (l == null && r == null) return const SizedBox.shrink();
    if (l == null) {
      return Align(alignment: AlignmentDirectional.centerEnd, child: r);
    }
    if (r == null) {
      return Align(alignment: AlignmentDirectional.centerStart, child: l);
    }
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 4,
      children: [l, r],
    );
  }
}

/// The hairline between two ledger rows: 1 px `line`, inset 20 on both
/// sides.
class AknLedgerDivider extends StatelessWidget {
  const AknLedgerDivider({super.key, this.indent = AknSpace.page});

  final double indent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: indent),
    child: SizedBox(
      height: 1,
      width: double.infinity,
      child: ColoredBox(color: context.akn.line),
    ),
  );
}

/// A ledger: [children] (usually [AknListTile]s) with inset hairlines
/// between them — never above the first or below the last.
class AknLedger extends StatelessWidget {
  const AknLedger({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const AknLedgerDivider(),
        children[i],
      ],
    ],
  );
}

/// Section title (design v2 §6.7): `title` 20/26 600 ink with an optional
/// count after it (500 dim), an optional `bodySmall` subtitle, and on the
/// right either an action (ink 15/20 600 + chevron — never orange) or a
/// [caption] ("şu an, 10:42", "bugün 06:00, ₺/L"). Sentence case, never
/// upper case.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.count,
    this.actionLabel,
    this.onAction,
    this.caption,
    this.padding = const EdgeInsets.fromLTRB(20, 24, 12, 8),
  });

  final String title;
  final String? subtitle;
  final int? count;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Right-aligned note (13/18 dim) when there is no action.
  final String? caption;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final titleStyle = t.title.copyWith(color: c.ink);
    final hasAction = actionLabel != null && onAction != null;
    final cap = caption;
    // Section titles are already large (20/26): they clamp at 1.6× text
    // (32 px) like the bar titles, so at 2.0× the content under them still
    // reaches the first viewport (§12, board screen 9).
    final heading = Semantics(
      header: true,
      child: Text.rich(
        TextSpan(
          text: title,
          children: [
            if (count != null)
              TextSpan(
                // A no-break space keeps the count with the last word.
                text: '\u00A0$count',
                style: titleStyle.copyWith(
                  fontWeight: FontWeight.w500,
                  color: c.dim,
                ),
              ),
          ],
        ),
        style: titleStyle,
        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.6),
      ),
    );
    // The title takes what is left; the action / caption keeps its natural
    // width (at most 55 % of the row) and sits on the right edge.
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  heading,
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: t.bodySmall.copyWith(color: c.dim)),
                  ],
                ],
              ),
            ),
            if (hasAction)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth.isFinite
                      ? constraints.maxWidth * 0.55
                      : double.infinity,
                ),
                child: Semantics(
                  button: true,
                  label: actionLabel,
                  excludeSemantics: true,
                  onTap: onAction,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      AknHaptics.selection();
                      onAction!();
                    },
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: AknSpace.minTap,
                      ),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(start: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                actionLabel!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.bodyStrong.copyWith(
                                  height: 20 / 15,
                                  color: c.ink,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: c.ink,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
            else if (cap != null && cap.isNotEmpty)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth.isFinite
                      ? constraints.maxWidth * 0.55
                      : double.infinity,
                ),
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 12, end: 8),
                  child: Text(
                    cap,
                    textAlign: TextAlign.end,
                    style: t.label.copyWith(
                      fontWeight: FontWeight.w400,
                      color: c.dim,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A label / value pair (server facts, summaries): label `bodySmall` dim on
/// the left, value 15/22 600 ink on the right. A [tone] adds a lamp dot in
/// front of the value and colours it (never colour alone: the value text
/// carries the meaning). Proportional figures.
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
    final tn = tone;
    final tc = tn == null || tn == AknTone.neutral || tn == AknTone.info
        ? null
        : c.tone(tn);
    final vStyle = t.bodyStrong
        .merge(valueStyle)
        .copyWith(color: tc?.fg ?? valueStyle?.color ?? c.ink);
    final scaler = MediaQuery.textScalerOf(context);
    final labelStyle = t.bodySmall.copyWith(color: c.dim);
    Widget? dot;
    if (tc != null) {
      dot = SizedBox(
        height: scaler.scale(15) * 22 / 15,
        child: Center(
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: tc.solid, shape: BoxShape.circle),
          ),
        ),
      );
    }
    final iconWidth = icon == null ? 0.0 : 30.0;
    return Semantics(
      label: '$label: $value',
      excludeSemantics: true,
      child: Padding(
        padding: padding,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Reflow (like the ledger row): when the value does not fit on
            // one line in its column, the value moves under the label,
            // left-aligned, and wraps there — a long note or address never
            // becomes a narrow right-aligned column.
            final tp = TextPainter(
              text: TextSpan(text: value, style: vStyle),
              textDirection: TextDirection.ltr,
              textScaler: scaler,
              maxLines: 1,
            )..layout();
            final valueWidth = tp.width + (dot == null ? 0 : 16);
            tp.dispose();
            final room = constraints.maxWidth - iconWidth - 12;
            final stack =
                constraints.maxWidth.isFinite && valueWidth > room * 6 / 11;
            final leadIcon = icon == null
                ? null
                : Padding(
                    padding: const EdgeInsetsDirectional.only(top: 1, end: 10),
                    child: Icon(icon, size: 20, color: c.dim),
                  );
            if (stack) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ?leadIcon,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label, style: labelStyle),
                        const SizedBox(height: 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (dot != null) ...[dot, const SizedBox(width: 8)],
                            Flexible(child: Text(value, style: vStyle)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ?leadIcon,
                Expanded(flex: 5, child: Text(label, style: labelStyle)),
                const SizedBox(width: 12),
                Expanded(
                  flex: 6,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (dot != null) ...[dot, const SizedBox(width: 8)],
                      Flexible(
                        child: Text(
                          value,
                          style: vStyle,
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A well (design v2 §4.5): a Beton box (r12, padding 12/14) with the
/// tone's icon and ink text — callouts and blocking notices ("Onaylamak
/// için çek görselini yükleyin"). No pastel tints, no border. The action is
/// a small secondary button (right, or under the text when there is no
/// room).
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
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final hasAction = actionLabel != null && onAction != null;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null) ...[
          Text(title!, style: t.bodyStrong.copyWith(color: c.ink)),
          const SizedBox(height: 2),
        ],
        Text(message, style: t.bodySmall.copyWith(color: c.ink)),
      ],
    );
    final action = hasAction
        ? AknButton.secondary(
            label: actionLabel!,
            size: AknButtonSize.small,
            onPressed: onAction,
          )
        : null;
    Widget banner = Container(
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: AknRadius.card,
      ),
      padding: EdgeInsetsDirectional.fromSTEB(
        14,
        12,
        onClose == null ? 14 : 4,
        12,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The action sits beside the text only when both fit: the
          // small button's label (15 px, padding 14 a side) and at least
          // 140 px of text; otherwise it goes under the text.
          var side = false;
          if (action != null && !large) {
            final tp = TextPainter(
              text: TextSpan(
                text: actionLabel,
                style: t.button.copyWith(fontSize: 15),
              ),
              textDirection: TextDirection.ltr,
              textScaler: MediaQuery.textScalerOf(context),
              maxLines: 1,
            )..layout();
            final actionWidth = tp.width + 30;
            tp.dispose();
            final closeWidth = onClose == null ? 0 : AknSpace.minTap;
            side =
                constraints.maxWidth - 30 - 12 - actionWidth - closeWidth >=
                140;
          }
          return Row(
            crossAxisAlignment: side
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Icon(icon ?? AknStatus.toneIcon(tone), color: tc.fg, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: side || action == null
                    ? text
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [text, const SizedBox(height: 8), action],
                      ),
              ),
              if (side) ...[const SizedBox(width: 12), action!],
              if (onClose != null)
                // 48 dp dokunma hedefi; simge küçük kalır.
                Transform.translate(
                  offset: const Offset(4, -10),
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
          );
        },
      ),
    );
    if (margin != null) banner = Padding(padding: margin!, child: banner);
    return Semantics(container: true, liveRegion: true, child: banner);
  }
}

/// Horizontal usage meter (limit usage): ink fill on the chart track below
/// [warnAt], the warn colour up to [dangerAt], danger beyond. The fill caps
/// at 100 % (the label still says the real share, "%112"). It renders the
/// final value at once and only glides when the value changes.
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
            : null);
    final color = effective == null || effective == AknTone.info
        ? c.ink
        : effective == AknTone.brand
        ? c.brandBright
        : c.tone(effective).solid;
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final shown = valueLabel ?? '%${(v * 100).round()}';
    final capped = v.clamp(0.0, 1.0);
    return Semantics(
      label: label,
      value: shown,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != null || valueLabel != null) ...[
            // Büyük yazıda değer etiketin altına iner.
            Flex(
              direction: large ? Axis.vertical : Axis.horizontal,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (large)
                  Text(label ?? '', style: t.label.copyWith(color: c.dim))
                else
                  Expanded(
                    child: Text(
                      label ?? '',
                      style: t.label.copyWith(color: c.dim),
                    ),
                  ),
                if (valueLabel != null)
                  Text(
                    valueLabel!,
                    style: t.label.copyWith(
                      fontWeight: FontWeight.w600,
                      color: effective == null || effective == AknTone.info
                          ? c.ink
                          : c.tone(effective).fg,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          ClipRRect(
            borderRadius: BorderRadius.circular(height / 2),
            child: SizedBox(
              height: height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: c.chartTrack),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: capped, end: capped),
                    duration: AknMotion.of(context, AknMotion.slow),
                    curve: AknMotion.emphasizedCurve,
                    builder: (context, f, _) => FractionallySizedBox(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: f.clamp(0.0, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(height / 2),
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

/// An amount in the ledger voice (`amount` 17/22 600, or `amountLarge`
/// Condensed 28/32 700 with [large]); proportional figures, aligned by the
/// right edge. Format with `Fmt` (`core/utils/format.dart`); the app never
/// computes money except "tahmini" values.
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
      style: base.copyWith(color: color),
    );
  }
}

/// Status-bar style for a plate surface that reaches the top of the screen
/// (the login band): dark status icons on orange.
class HeroStatusBar extends StatelessWidget {
  const HeroStatusBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: AknTheme.overlayOnHero,
    child: child,
  );
}

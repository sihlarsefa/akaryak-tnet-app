import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../motion.dart';
import '../status.dart';
import '../theme.dart';
import '../tokens.dart';
import '../typography.dart';
import 'animated_number.dart';
import 'buttons.dart';
import 'plate.dart';

export 'plate.dart';

/// Marks content that already sits on a card surface (design v3 §3): an
/// [AknCard], a ledger card ([AknLedger]), a KPI cell — or any custom card
/// container that wraps its content in it. The building blocks read it to
/// stay flat on a card: a ledger keeps its rows without a second card,
/// dividers turn `lineSoft`, KPI tiles become quiet wells.
class AknCardScope extends InheritedWidget {
  const AknCardScope({super.key, required super.child});

  /// True inside an [AknCardScope].
  static bool isOn(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AknCardScope>() != null;

  /// True when content already sits on a raised surface: a card
  /// ([isOn]), the hero card ([OnHero]), the orange band, or a sheet or
  /// dialog (a non-opaque route).
  static bool onSurface(BuildContext context) =>
      isOn(context) ||
      OnHero.isOn(context) ||
      context.akn.isBandPalette ||
      ModalRoute.opaqueOf(context) == false;

  @override
  bool updateShouldNotify(AknCardScope oldWidget) => false;
}

/// The card (design v3 §3–4): white (`surface`) floating on the off-white
/// page — radius 20, the soft card shadow ([AknShadows.card]; dark mode adds
/// a 1 px `line`), padding 16. Rows inside are separated by inset hairlines
/// ([AknLedgerDivider]); the content knows it sits on a card
/// ([AknCardScope]).
///
/// With [onTap] it presses: scale 0.97 (100 ms in, a 260 ms spring back),
/// the shadow settles onto the page ([AknShadows.pressed]) and the fill dims
/// to `surfaceAlt`; a selection haptic, and the 3 px focus ring for keyboard
/// and switch users.
///
/// [shadow] false gives a flat card; [accent] (the old left stripe) is
/// ignored.
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
    this.radius = 20,
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

  /// A 1 px border in both themes (default: none in light, `line` in dark).
  final Color? borderColor;
  final double radius;

  /// Deprecated: no coloured accent strips (ignored).
  final AknTone? accent;

  /// The soft card shadow; false for a flat card.
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
      border: borderColor ?? (c.isDark ? c.line : null),
      radius: radius,
      shadow: shadow,
      onTap: onTap == null
          ? null
          : () {
              if (haptic) AknHaptics.selection();
              onTap!();
            },
      onLongPress: onLongPress,
      child: AknCardScope(
        child: Padding(padding: padding, child: child),
      ),
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

/// The card surface: shadow, radius, optional border; when tappable a
/// pressed fill, a settling shadow and a scale that follow the ink highlight
/// (so a scroll that takes over the gesture releases it), and the focus
/// ring.
class _CardSurface extends StatefulWidget {
  const _CardSurface({
    required this.color,
    required this.border,
    required this.radius,
    required this.shadow,
    required this.child,
    this.onTap,
    this.onLongPress,
  });

  final Color color;
  final Color? border;
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
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final interactive = widget.onTap != null || widget.onLongPress != null;
    final reduced = AknMotion.reduced(context);
    final pressed = _pressed && interactive;
    final radius = BorderRadius.circular(widget.radius);
    final duration = pressed ? AknMotion.press : AknMotion.pressOut;
    final border = widget.border;
    final fill = pressed
        ? (widget.color == c.surface
              ? c.surfaceAlt
              : Color.alphaBlend(c.ink.withValues(alpha: 0.05), widget.color))
        : widget.color;
    Widget content = widget.child;
    if (interactive) {
      content = Material(
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
          child: content,
        ),
      );
    }
    Widget surface = AnimatedContainer(
      duration: AknMotion.of(context, duration),
      curve: AknMotion.standard,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: border == null ? null : Border.all(color: border),
        boxShadow: !widget.shadow
            ? null
            : pressed
            ? AknShadows.pressed(c)
            : AknShadows.card(c),
      ),
      foregroundDecoration: _focused
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.fromBorderSide(AknTheme.focusRing(c)),
            )
          : null,
      child: ClipRRect(borderRadius: radius, child: content),
    );
    if (interactive) {
      surface = AnimatedScale(
        scale: pressed && !reduced ? AknMotion.pressScale : 1,
        duration: duration,
        curve: pressed ? AknMotion.standard : AknMotion.spring,
        child: surface,
      );
    }
    return surface;
  }
}

/// Deprecated name of the hero card: renders an [AknPlate] — the white card
/// with its warm top wash, radius 26, the warm plate shadow (owner decision
/// G) — with everything inside printed in the plate palette through
/// [OnHero]. [watermark], [highlight] and [glow] are ignored.
///
/// One hero card per screen: list pages, settings, profile and onboarding
/// use a plain header instead.
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

  /// Ignored (no watermark chevrons).
  final bool watermark;
  final EdgeInsetsGeometry? margin;

  /// Ignored (the hero card carries its own wash).
  final bool highlight;

  /// Ignored (the hero card carries its own shadow).
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

/// Re-themes its subtree for content printed ON the hero card (owner
/// decision G): the palette is `AknColors.plateInk()` — ink stays ink,
/// hairlines `plateLine`, quiet wells the warm `deltaFill`, charts in the
/// orange accent — and the text styles are re-coloured (sizes kept). Status
/// tones keep their colours (the card is white), so pills, buttons and
/// fields keep their normal looks.
///
/// [AknPlate] and [AknHeroPanel] apply it; building blocks that need to
/// know (logo, chips, KPI wells, ledgers) ask [OnHero.isOn].
class OnHero extends StatelessWidget {
  const OnHero({super.key, required this.child});

  final Widget child;

  /// Deprecated: there are no white controls on the hero card (black).
  static const Color onWhite = Colors.black;

  /// Deprecated: no glass on the hero card (black 12 %).
  static const Color glass = Colors.black12;

  /// Deprecated: no glass on the hero card (black 26 %).
  static const Color glassStrong = Colors.black26;

  /// The hero-card palette derived from [base] (= `base.plateInk()`).
  static AknColors palette(AknColors base) => base.plateInk();

  /// True inside a hero-card surface.
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

/// A small chip (design v3 §4): on the hero card a warm pill (`plateIconFill`
/// with Pas 12/16 700 text and an optional 14 px icon); elsewhere it renders
/// as a status pill ([AknLamp], ink). Optional tap (48 px target, press
/// scale, selection haptic).
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
      final style = t.captionStrong.copyWith(
        fontSize: 12,
        height: 16 / 12,
        color: c.brandInk,
      );
      visual = Container(
        constraints: const BoxConstraints(minHeight: 28),
        padding: EdgeInsets.fromLTRB(icon == null ? 11 : 9, 6, 11, 6),
        decoration: BoxDecoration(
          color: c.plateIconFill,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: c.brandInk),
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
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: 1,
          heightFactor: 1,
          child: visual,
        ),
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

/// An icon in a soft squircle (design v3 §4): 40 px, radius 12 (scales with
/// [size]), `surfaceAlt` with an ink glyph on a card (white on the light
/// page, so it still reads there) — or, with a [tone], the tone's well and
/// colour ("your move" = soft orange with a Pas glyph). On the hero card the
/// well turns warm, on the band it turns to glass.
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
    final tc = tn == null ? null : c.tone(tn);
    final glyph = iconSize ?? (size * 0.55).roundToDouble();
    final well = c.isDark || AknCardScope.onSurface(context)
        ? c.surfaceAlt
        : c.surface;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: tc?.bg ?? well,
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(size * 0.3),
          ),
        ),
        child: Center(
          child: Icon(icon, size: glyph, color: tc?.fg ?? c.ink),
        ),
      ),
    );
  }
}

/// The list row (design v3 §4) — every item of a collection (orders,
/// quotes, approvals, stops, payments, customers, notifications, documents):
///
/// ```
/// [□] Title (15/20 600)                         338.800,00 ₺  (amount)
///     Second line (bodySmall 14/20 dim)            42,35 ₺/L  (meta)
///     (●) Lamp pill                       ⏱ 2 sa 57 dk kaldı  (status, +10)
///     [footer, e.g. the route line, +12]
/// ```
///
/// Min height 64 (dense 48), padding 12/20. [leadingIcon] sits in a 40 px
/// soft squircle ([AknIconBox]; [leadingTone] tints it); [leading] takes any
/// widget (an avatar). Figures on the right are tabular. A chevron
/// (`caretRight` 18 dim) only on navigation / settings rows
/// (`showChevron: true`). Pressed: a rounded `surfaceAlt` fill and the row
/// scales to 0.97 (spring release); the chevron nudges forward.
///
/// It looks right on a card (inside [AknLedger] or an [AknCard]) and alone
/// on the page. Separate rows with [AknLedgerDivider] (or build the group
/// with [AknLedger], which floats it as a card).
///
/// **Reflow**: at text scale ≥ 1.3, or when the right column would leave the
/// title less than 96 px, the right column moves under the title (title,
/// amount, status, second line, meta) and nothing is cut (titles up to 2
/// lines, more when stacked).
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

  /// An icon in a 40 px soft squircle in front (ink, or the [leadingTone]'s
  /// colour on its well).
  final IconData? leadingIcon;
  final AknTone? leadingTone;

  /// A control at the end (switch, small button).
  final Widget? trailing;

  /// Right-aligned text on the title line in `bodySmall` dim (time) — or,
  /// with [amount], the text under it.
  final String? meta;

  /// Right column, line 1: `amount` 17/22 700 tabular, never wraps
  /// ("338.800,00 ₺").
  final String? amount;

  /// Right column, line 2: `bodySmall` dim ("42,35 ₺/L", "tahmini").
  final String? amountMeta;

  /// The full-width status line (+10): a status pill and, on the right, a
  /// countdown or a note — see [AknStatusLine].
  final Widget? status;

  /// Under everything (+12): the route line.
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

  /// Overrides the title style (default 15/20 600 ink; dense 14/20).
  final TextStyle? titleStyle;

  @override
  State<AknListTile> createState() => _AknListTileState();
}

class _AknListTileState extends State<AknListTile> {
  bool _pressed = false;
  bool _focused = false;

  /// Gap between the leading box and the texts.
  static const double _leadGap = 14;

  /// The pressed fill's corners.
  static const BorderRadius _radius = BorderRadius.all(Radius.circular(16));

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final c = context.akn;
    final t = context.aknText;
    final chevron = w.showChevron ?? false;
    final scaler = MediaQuery.textScalerOf(context);
    final large = scaler.scale(10) >= 13;
    final reduced = AknMotion.reduced(context);
    final interactive = w.onTap != null || w.onLongPress != null;
    final pressed = _pressed && interactive;
    final boxSize = w.dense ? 36.0 : 40.0;
    final lead =
        w.leading ??
        (w.leadingIcon == null
            ? null
            : AknIconBox(
                icon: w.leadingIcon!,
                tone: w.leadingTone,
                size: boxSize,
              ));
    final leadWidth = lead == null ? 0.0 : boxSize + _leadGap;
    final defaultTitle = w.dense
        ? t.bodyStrong.copyWith(fontSize: 14, height: 20 / 14)
        : t.bodyStrong.copyWith(height: 20 / 15);
    final titleStyle = (w.titleStyle ?? defaultTitle).copyWith(
      color: (w.titleStyle?.color) ?? c.ink,
    );
    final amountStyle = t.amount.copyWith(color: c.ink);
    final metaStyle = t.bodySmall.copyWith(color: c.dim);
    final rightMetaStyle = metaStyle.copyWith(
      fontFeatures: AknNumerals.tabular,
    );
    final rightTop = w.amount ?? (w.amountMeta == null ? w.meta : null);
    final rightBottom = w.amount != null
        ? (w.amountMeta ?? w.meta)
        : w.amountMeta;
    final rightTopStyle = w.amount != null ? amountStyle : rightMetaStyle;
    final motion = pressed ? AknMotion.press : AknMotion.pressOut;

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
          if (w.status != null) ...[const SizedBox(height: 8), w.status!],
          if (subText != null) ...[const SizedBox(height: 4), subText],
          if (rightBottom != null) ...[
            const SizedBox(height: 2),
            Text(rightBottom, style: rightMetaStyle),
          ],
          if (w.footer != null) ...[const SizedBox(height: 12), w.footer!],
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
                    style: rightMetaStyle,
                    maxLines: 1,
                    softWrap: false,
                  ),
                ],
              ],
            ),
          ],
          if (w.status != null) ...[const SizedBox(height: 10), w.status!],
        ];
      }
      final row = Row(
        crossAxisAlignment: stack || w.status != null || w.footer != null
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          if (lead != null) ...[lead, const SizedBox(width: _leadGap)],
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
            const SizedBox(width: 6),
            AnimatedSlide(
              offset: Offset(pressed && !reduced ? 0.2 : 0, 0),
              duration: AknMotion.of(context, motion),
              curve: pressed ? AknMotion.standard : AknMotion.spring,
              child: Icon(
                PhosphorIconsRegular.caretRight,
                color: c.dim,
                size: 18,
              ),
            ),
          ],
        ],
      );
      // The footer (route line) runs under both columns, full width (after
      // the leading box), +12.
      if (stack || w.footer == null) return row;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          row,
          const SizedBox(height: 12),
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: w.leading == null && w.leadingIcon != null ? leadWidth : 0,
            ),
            child: w.footer,
          ),
        ],
      );
    }

    final pad =
        w.padding ??
        (w.dense
            ? const EdgeInsets.symmetric(horizontal: 20, vertical: 8)
            : AknSpace.row);
    // On a card the pressed fill is the quiet well; on the page a shade
    // deeper so it still shows on the off-white.
    final pressFill = c.isDark || AknCardScope.onSurface(context)
        ? c.surfaceAlt
        : c.line;
    Widget tile = LayoutBuilder(
      builder: (context, constraints) {
        var stack = large;
        if (!stack && (rightTop != null || rightBottom != null)) {
          // Measured reflow: when the right column would leave the title
          // less than 96 px, it moves under the title instead (nothing
          // truncates, nothing overflows).
          double width(String? text, TextStyle style) {
            if (text == null) return 0;
            final tp = TextPainter(
              text: TextSpan(text: text, style: style),
              textDirection: TextDirection.ltr,
              textScaler: scaler,
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
              leadWidth -
              (chevron ? 24 : 0);
          final right = math.max(
            width(rightTop, rightTopStyle),
            width(rightBottom, rightMetaStyle),
          );
          stack = right + 12 > content - 96;
        }
        return AnimatedContainer(
          duration: AknMotion.of(context, motion),
          curve: AknMotion.standard,
          decoration: BoxDecoration(
            color: pressed ? pressFill : pressFill.withValues(alpha: 0),
            borderRadius: _radius,
          ),
          foregroundDecoration: _focused
              ? BoxDecoration(
                  borderRadius: _radius,
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
      tile = AnimatedScale(
        scale: pressed && !reduced ? AknMotion.pressScale : 1,
        duration: motion,
        curve: pressed ? AknMotion.standard : AknMotion.spring,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: w.onTap,
            onLongPress: w.onLongPress,
            borderRadius: _radius,
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

/// A row's status line: a status pill on the left and, on the right, a
/// countdown or a short note ("Burak Yılmaz’ın talebi", "varış 11:20").
/// When both do not fit on one line the right part moves under the pill.
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
      runSpacing: 6,
      children: [l, r],
    );
  }
}

/// The hairline between two rows: 1 px, inset [indent] (20) on both sides —
/// `lineSoft` on a card, `line` on the page.
class AknLedgerDivider extends StatelessWidget {
  const AknLedgerDivider({super.key, this.indent = AknSpace.page});

  final double indent;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final onCard = AknCardScope.isOn(context) || OnHero.isOn(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: indent),
      child: SizedBox(
        height: 1,
        width: double.infinity,
        child: ColoredBox(color: onCard ? c.lineSoft : c.line),
      ),
    );
  }
}

/// A group of rows (design v3 §3–4): [children] (usually [AknListTile]s)
/// with inset `lineSoft` hairlines between them — never above the first or
/// below the last.
///
/// On the page it floats as a white card: the 20 px page gutter, radius
/// 20, the soft card shadow (dark: a 1 px `line`), 4 px of air inside above
/// the first and below the last row. Where it already sits on a surface — an
/// [AknCard] or another [AknCardScope], the hero card, a sheet or dialog —
/// or inside a parent that already insets it, the rows stay flat.
class AknLedger extends StatelessWidget {
  const AknLedger({super.key, required this.children});

  final List<Widget> children;

  /// The card's margin on the page.
  static const EdgeInsets _margin = EdgeInsets.fromLTRB(
    AknSpace.page,
    4,
    AknSpace.page,
    4,
  );

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    final rows = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const AknLedgerDivider(),
          children[i],
        ],
      ],
    );
    if (AknCardScope.onSurface(context)) return rows;
    return LayoutBuilder(
      builder: (context, box) {
        // Full-bleed on the page (or a wide layout): float as a card. A
        // parent that already insets the rows keeps them flat.
        final screen = MediaQuery.maybeSizeOf(context)?.width ?? box.maxWidth;
        final pageLevel =
            box.hasBoundedWidth &&
            (box.maxWidth >= screen - 0.5 || box.maxWidth >= 600);
        if (!pageLevel) return rows;
        return Padding(
          padding: _margin,
          child: _LedgerCard(
            child: AknCardScope(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: rows,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The white card of a page-level [AknLedger] (not an [AknCard]: a ledger is
/// a group of rows, not a group box).
class _LedgerCard extends StatelessWidget {
  const _LedgerCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AknRadius.card,
        border: c.isDark ? Border.all(color: c.line) : null,
        boxShadow: AknShadows.card(c),
      ),
      child: ClipRRect(borderRadius: AknRadius.card, child: child),
    );
  }
}

/// Section title (design v3 §4): 18/24 800 ink (−0.3) with an optional
/// count in a soft pill (12/16 700, tabular; it pops when the count
/// changes), an optional `bodySmall` subtitle, and on the right either a
/// link ("Tümü": 13/18 600 ink + `caretRight` 16, a soft pill and a press
/// scale while pressed, a selection haptic) or a [caption] ("şu an, 10:42",
/// "bugün 06:00, ₺/L"). Sentence case, never upper case.
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
    final titleStyle = t.title.copyWith(
      fontSize: 18,
      height: 24 / 18,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
      color: c.ink,
    );
    final hasAction = actionLabel != null && onAction != null;
    final cap = caption;
    // Section titles clamp at 1.6× text like the bar titles, so at 2.0× the
    // content under them still reaches the first viewport.
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.6);
    final n = count;
    final Widget heading = n == null
        ? Semantics(
            header: true,
            child: Text(title, style: titleStyle, textScaler: scaler),
          )
        : Semantics(
            header: true,
            // A no-break space keeps the count with the last word.
            label: '$title $n',
            excludeSemantics: true,
            child: Text.rich(
              TextSpan(
                text: title,
                children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8),
                      child: _CountPill(count: n, textScaler: scaler),
                    ),
                  ),
                ],
              ),
              style: titleStyle,
              textScaler: scaler,
            ),
          );
    // The title takes what is left; the action / caption keeps its natural
    // width (at most 55 % of the row) and sits on the right edge.
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxSide = constraints.maxWidth.isFinite
              ? constraints.maxWidth * 0.55
              : double.infinity;
          return Row(
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
                      Text(
                        subtitle!,
                        style: t.bodySmall.copyWith(color: c.dim),
                      ),
                    ],
                  ],
                ),
              ),
              if (hasAction)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxSide),
                  child: _SectionAction(label: actionLabel!, onTap: onAction!),
                )
              else if (cap != null && cap.isNotEmpty)
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxSide),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 12,
                      end: 8,
                    ),
                    child: Text(
                      cap,
                      textAlign: TextAlign.end,
                      style: t.label.copyWith(
                        fontWeight: FontWeight.w500,
                        color: c.dim,
                        fontFeatures: AknNumerals.tabular,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// The count after a section title: a soft pill that pops when the count
/// changes.
class _CountPill extends StatelessWidget {
  const _CountPill({required this.count, required this.textScaler});

  final int count;
  final TextScaler textScaler;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final style = t.captionStrong.copyWith(color: c.ink);
    return AnimatedSwitcher(
      duration: AknMotion.of(context, const Duration(milliseconds: 320)),
      switchInCurve: AknMotion.pop,
      switchOutCurve: AknMotion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      layoutBuilder: (current, previous) =>
          Stack(alignment: Alignment.center, children: [...previous, ?current]),
      // No `alignment` here: an Align would stretch the pill across the
      // line inside the WidgetSpan. The min width centres the digits.
      child: Container(
        key: ValueKey<int>(count),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.ink.withValues(alpha: c.isDark ? 0.12 : 0.07),
          borderRadius: AknRadius.pillAll,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 8),
          child: Text(
            '$count',
            style: style,
            textScaler: textScaler,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// The section link ("Tümü ›"): a soft pill shows and the link scales a
/// touch while pressed; a selection haptic on tap; a 48 px target.
class _SectionAction extends StatefulWidget {
  const _SectionAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  State<_SectionAction> createState() => _SectionActionState();
}

class _SectionActionState extends State<_SectionAction> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final reduced = AknMotion.reduced(context);
    final duration = _down ? AknMotion.press : AknMotion.pressOut;
    // Like the title, the link clamps at 1.6× text; the caret grows with it.
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.6);
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            AknHaptics.selection();
            widget.onTap();
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AknSpace.minTap),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 12),
              child: Center(
                widthFactor: 1,
                child: AnimatedScale(
                  scale: _down && !reduced ? 0.94 : 1,
                  duration: duration,
                  curve: _down ? AknMotion.standard : AknMotion.spring,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      PositionedDirectional(
                        start: -10,
                        end: -6,
                        top: -6,
                        bottom: -6,
                        child: AnimatedOpacity(
                          opacity: _down ? 1 : 0,
                          duration: AknMotion.of(context, duration),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.ink.withValues(
                                alpha: c.isDark ? 0.12 : 0.07,
                              ),
                              borderRadius: AknRadius.pillAll,
                            ),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              widget.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textScaler: scaler,
                              style: t.label.copyWith(color: c.ink),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            PhosphorIconsRegular.caretRight,
                            size: scaler.scale(16),
                            color: c.ink,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A label / value pair (server facts, summaries): label `bodySmall` dim on
/// the left, value 15/22 600 ink on the right with tabular figures. A
/// [tone] adds a status dot (with its halo) in front of the value and
/// colours it (never colour alone: the value text carries the meaning).
/// Rows of facts on a card are separated by inset hairlines.
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
        .copyWith(fontFeatures: AknNumerals.tabular)
        .merge(valueStyle)
        .copyWith(color: tc?.fg ?? valueStyle?.color ?? c.ink);
    final scaler = MediaQuery.textScalerOf(context);
    final labelStyle = t.bodySmall.copyWith(color: c.dim);
    Widget? dot;
    if (tc != null) {
      dot = SizedBox(
        height: scaler.scale(15) * 22 / 15,
        child: Center(
          child: CustomPaint(
            size: const Size.square(8),
            painter: LampDotPainter(
              color: tc.solid,
              halo: Color.alphaBlend(tc.solid.withValues(alpha: 0.2), tc.bg),
            ),
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
            // Reflow (like the list row): when the value does not fit on
            // one line in its column, the value moves under the label,
            // left-aligned, and wraps there — a long note or address never
            // becomes a narrow right-aligned column.
            final tp = TextPainter(
              text: TextSpan(text: value, style: vStyle),
              textDirection: TextDirection.ltr,
              textScaler: scaler,
              maxLines: 1,
            )..layout();
            final valueWidth = tp.width + (dot == null ? 0 : 18);
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
                            if (dot != null) ...[
                              dot,
                              const SizedBox(width: 10),
                            ],
                            Flexible(child: Text(value, style: vStyle)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }
            // Label and value share a baseline (14/20 beside 15/22).
            final pair = Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(flex: 5, child: Text(label, style: labelStyle)),
                const SizedBox(width: 12),
                Expanded(
                  flex: 6,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (dot != null) ...[dot, const SizedBox(width: 10)],
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
            if (leadIcon == null) return pair;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                leadIcon,
                Expanded(child: pair),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A tinted well (design v3 §4): the tone's soft well (`ToneColors.bg`,
/// 1 px `ToneColors.line`, radius 16) with the tone's icon in a 32 px disc,
/// a 700 title and the message — callouts and blocking notices ("Onaylamak
/// için çek görselini yükleyin"). It opens in (height + fade) when it first
/// appears. The action is a small secondary button (right, or under the
/// text when there is no room).
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

  /// The banner's corners.
  static const BorderRadius _radius = BorderRadius.all(Radius.circular(16));

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final tc = c.tone(tone);
    final scaler = MediaQuery.textScalerOf(context);
    final large = scaler.scale(10) >= 13;
    final hasAction = actionLabel != null && onAction != null;
    final hasTitle = title != null;
    final titleStyle = t.bodyStrong.copyWith(
      fontWeight: FontWeight.w700,
      color: c.ink,
    );
    final messageStyle = t.bodySmall.copyWith(color: hasTitle ? c.dim : c.ink);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasTitle) ...[
          Text(title!, style: titleStyle),
          const SizedBox(height: 2),
        ],
        Text(message, style: messageStyle),
      ],
    );
    // The first line's centre meets the disc's centre at every text size:
    // a short line drops to the disc's middle, a tall one lowers the disc.
    final first = hasTitle ? titleStyle : messageStyle;
    final firstSize = first.fontSize ?? 14;
    final firstLine = scaler.scale(firstSize) * (first.height ?? 20 / 14);
    final textTop = math.max(0.0, (32 - firstLine) / 2);
    final discTop = math.max(0.0, (firstLine - 32) / 2);
    final action = hasAction
        ? AknButton.secondary(
            label: actionLabel!,
            size: AknButtonSize.small,
            onPressed: onAction,
          )
        : null;
    final disc = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: tc.line, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(icon ?? AknStatus.toneIcon(tone), color: tc.fg, size: 18),
    );
    Widget banner = AnimatedContainer(
      duration: AknMotion.of(context, AknMotion.base),
      curve: AknMotion.standard,
      decoration: BoxDecoration(
        color: tc.bg,
        borderRadius: _radius,
        border: Border.all(color: tc.line),
      ),
      padding: EdgeInsetsDirectional.fromSTEB(
        12,
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
                constraints.maxWidth - 44 - 12 - actionWidth - closeWidth >=
                140;
          }
          final body = Padding(
            padding: EdgeInsets.only(top: side ? 0 : textTop),
            child: side || action == null
                ? text
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [text, const SizedBox(height: 10), action],
                  ),
          );
          return Row(
            crossAxisAlignment: side
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: side ? 0 : discTop),
                child: disc,
              ),
              const SizedBox(width: 12),
              Expanded(child: body),
              if (side) ...[const SizedBox(width: 12), action!],
              if (onClose != null)
                // 48 dp dokunma hedefi; simge küçük kalır ve diskle aynı
                // hizada durur.
                Transform.translate(
                  offset: Offset(4, side ? -8 : discTop - 8),
                  child: IconButton(
                    iconSize: 18,
                    constraints: const BoxConstraints(
                      minWidth: AknSpace.minTap,
                      minHeight: AknSpace.minTap,
                    ),
                    tooltip: 'Kapat',
                    onPressed: onClose,
                    icon: Icon(PhosphorIconsRegular.x, color: c.dim),
                  ),
                ),
            ],
          );
        },
      ),
    );
    banner = _Reveal(handoff: ('AknBanner', title, message), child: banner);
    if (margin != null) banner = Padding(padding: margin!, child: banner);
    return Semantics(container: true, liveRegion: true, child: banner);
  }
}

/// Opens its child once, when first built: the height grows from zero and
/// the content fades in (emphasized, 380 ms). Static under reduce motion.
/// The widget structure never changes, so the child keeps its state.
class _Reveal extends StatefulWidget {
  const _Reveal({required this.child, required this.handoff});

  final Widget child;

  /// Names the content for [AknEntranceHandoff].
  final Object handoff;

  @override
  State<_Reveal> createState() => _RevealState();
}

class _RevealState extends State<_Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  late final CurvedAnimation _size = CurvedAnimation(
    parent: _c,
    curve: AknMotion.emphasizedCurve,
  );
  late final CurvedAnimation _fade = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.3, 1, curve: Curves.easeOut),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final handed = AknEntranceHandoff.take(widget.handoff);
    if (handed != null) _c.value = handed;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else if (_c.value < 1) {
      _c.forward();
    }
  }

  @override
  void deactivate() {
    AknEntranceHandoff.put(widget.handoff, _c.value);
    super.deactivate();
  }

  @override
  void dispose() {
    _size.dispose();
    _fade.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizeTransition(
    sizeFactor: _size,
    axisAlignment: -1,
    child: FadeTransition(opacity: _fade, child: widget.child),
  );
}

/// Horizontal usage meter (limit usage): a rounded `chartTrack` with the
/// orange fill (owner decision G: orange marks progress; the button
/// gradient) below [warnAt], the warn colour up to [dangerAt], danger
/// beyond. The fill caps at 100 % (the label still says the real share,
/// "%112"). It grows from empty when it first appears and glides to a new
/// value when it changes, blending the colour when it crosses a threshold
/// (jumps under reduce motion).
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
    final Gradient fill = switch (effective) {
      null => LinearGradient(colors: [c.brandFillStart, c.plateAccent]),
      AknTone.info => LinearGradient(colors: [c.ink, c.ink]),
      AknTone.brand => LinearGradient(colors: [c.brandFillStart, c.brand]),
      final AknTone tn => LinearGradient(
        colors: [
          Color.lerp(c.tone(tn).solid, c.surface, 0.18)!,
          c.tone(tn).solid,
        ],
      ),
    };
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
                      fontWeight: FontWeight.w700,
                      fontFeatures: AknNumerals.tabular,
                      color: effective == null || effective == AknTone.info
                          ? c.ink
                          : c.tone(effective).fg,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            height: height,
            child: _UsageTrack(
              value: capped,
              track: c.chartTrack,
              fill: fill,
              handoff: ('UsageBar', label, capped),
            ),
          ),
        ],
      ),
    );
  }
}

/// The track and fill of a [UsageBar]: the fill grows from empty when it
/// first appears (900 ms, emphasized) and glides to a new share when it
/// changes ([AknMotion.count], in step with a counting figure beside it);
/// it jumps under reduce motion. A remount mid-way (a wrapper's entrance
/// ending) resumes from the fill on screen ([AknEntranceHandoff]).
class _UsageTrack extends StatefulWidget {
  const _UsageTrack({
    required this.value,
    required this.track,
    required this.fill,
    required this.handoff,
  });

  /// 0..1.
  final double value;
  final Color track;
  final Gradient fill;

  /// Names the bar for [AknEntranceHandoff].
  final Object handoff;

  @override
  State<_UsageTrack> createState() => _UsageTrackState();
}

class _UsageTrackState extends State<_UsageTrack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    value: 1,
  );
  late final CurvedAnimation _t = CurvedAnimation(
    parent: _c,
    curve: AknMotion.emphasizedCurve,
  );
  double _from = 0;
  late double _to = widget.value;
  bool _started = false;

  /// The fill's colours when the threshold colour last changed (null: no
  /// blend running).
  Gradient? _fromFill;

  /// The fill on screen right now.
  double get _shown => _from + (_to - _from) * _t.value;

  /// The colours on screen right now, blending from [_fromFill] to [target].
  Gradient _fillAt(Gradient target) {
    final from = _fromFill;
    if (from == null) return target;
    return Gradient.lerp(from, target, _t.value) ?? target;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final handed = AknEntranceHandoff.take(widget.handoff);
    _glide(
      from: handed ?? 0,
      duration: handed == null
          ? const Duration(milliseconds: 900)
          : AknMotion.slow,
    );
  }

  @override
  void didUpdateWidget(_UsageTrack old) {
    super.didUpdateWidget(old);
    final fillChanged = old.fill != widget.fill;
    if (old.value == widget.value && !fillChanged) return;
    // Crossing a threshold (orange → ochre → red) blends the colours along
    // the glide instead of switching them.
    _fromFill = fillChanged || _c.isAnimating ? _fillAt(old.fill) : null;
    _glide(from: _shown, duration: AknMotion.count);
  }

  void _glide({required double from, required Duration duration}) {
    _from = from;
    _to = widget.value;
    final d = AknMotion.of(context, duration);
    final moves = (_to - from).abs() >= 0.001 || _fromFill != null;
    if (d == Duration.zero || !moves) {
      _fromFill = null;
      _c.value = 1;
      return;
    }
    _c.duration = d;
    _c.forward(from: 0);
  }

  @override
  void deactivate() {
    AknEntranceHandoff.put(widget.handoff, _shown);
    super.deactivate();
  }

  @override
  void dispose() {
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    builder: (context, _) => CustomPaint(
      size: Size.infinite,
      painter: _UsagePainter(
        value: _shown,
        track: widget.track,
        fill: _fillAt(widget.fill),
      ),
    ),
  );
}

/// The usage bar: a rounded track and the rounded fill (at least a dot
/// when the share is above zero).
class _UsagePainter extends CustomPainter {
  const _UsagePainter({
    required this.value,
    required this.track,
    required this.fill,
  });

  final double value;
  final Color track;
  final Gradient fill;

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    final radius = Radius.circular(h / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = track,
    );
    final v = value.clamp(0.0, 1.0);
    if (v <= 0) return;
    final w = math.max(size.width * v, h);
    final rect = Rect.fromLTWH(0, 0, math.min(w, size.width), h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..shader = fill.createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_UsagePainter old) =>
      old.value != value || old.track != track || old.fill != fill;
}

/// An amount in the row voice (`amount` 17/22 700, or `amountLarge` 28/34
/// 800 with [large]); tabular figures, aligned by the right edge. Format
/// with `Fmt` (`core/utils/format.dart`); the app never computes money
/// except "tahmini" values.
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
      style: base.copyWith(color: color, fontFeatures: AknNumerals.tabular),
    );
  }
}

/// Status-bar style for the orange band when it reaches the top of the
/// screen (homes, the login band): light status icons on orange.
class HeroStatusBar extends StatelessWidget {
  const HeroStatusBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: AknTheme.overlayOnHero,
    child: child,
  );
}

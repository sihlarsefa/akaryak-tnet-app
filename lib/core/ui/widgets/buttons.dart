import 'dart:async';

import 'package:flutter/material.dart';

import '../driver_mode.dart';
import '../motion.dart';
import '../painters/chevron_spinner.dart';
import '../theme.dart';
import '../tokens.dart';
import 'cards.dart' show OnHero;

/// Button looks (design v2 §6.5):
/// * primary — `brandFill` (#FF5001, dark #E64800) with a BLACK label ("on
///   orange, ink is black"); one per screen region;
/// * secondary / outline — white (`surface`) with a 1.5 px `lineStrong`
///   border and an ink label;
/// * ghost — no fill, an underlined ink label (tertiary: "Vazgeç", "Atla");
/// * danger — white with the border and a red label (the page-level
///   "Reddet"; a sheet's destructive confirm is `DestructiveButton`).
enum AknButtonVariant { primary, secondary, ghost, danger, outline }

/// Heights: small 40 (r10, 15 px label), medium 48, large 52 (the default);
/// every size keeps a 48 dp touch target. Driver mode makes every button 64
/// (r14, 18/22 label).
enum AknButtonSize { small, medium, large }

/// The AkaryakıtNet button (radius 12, `button` 16/20 600 label).
///
/// * Press: pressed fill and scale 0.98 (90 ms in, 120 ms out) with a light
///   haptic; a primary also drops its content 1 px.
/// * [loading] shows a spinner in the label colour and keeps the width;
///   [success] a check. With [onPressedAsync] the button manages both by
///   itself (spinner while the future runs, then a short check when
///   [showSuccess]).
/// * Disabled (both callbacks null): Beton fill, faint label, no border.
/// * On the plate (inside `AknPlate` / `OnHero`) it follows the plate rule: a
///   primary is a black key with a plate-coloured label, the others are
///   black.
/// * Keyboard / switch focus: the 3 px brand ring 2 px outside.
/// * A full-width ([expand]) button never breaks a word or cuts its label:
///   when the label does not fit on one line it first tightens the padding,
///   then drops the icons, then wraps onto two lines at word boundaries and,
///   as a last resort, scales the single line down ([AknButton.fitsOneLine]
///   lets a parent choose a roomier layout before that happens).
/// * Labels are verb + object; no arrow glyphs.
class AknButton extends StatefulWidget {
  const AknButton({
    super.key,
    required this.label,
    this.onPressed,
    this.onPressedAsync,
    this.variant = AknButtonVariant.primary,
    this.size = AknButtonSize.large,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.success = false,
    this.showSuccess = true,
    this.expand = false,
    this.haptic = true,
    this.semanticLabel,
    this.loadingLabel = 'Gönderiliyor',
  });

  const AknButton.secondary({
    super.key,
    required this.label,
    this.onPressed,
    this.onPressedAsync,
    this.size = AknButtonSize.large,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.success = false,
    this.showSuccess = true,
    this.expand = false,
    this.haptic = true,
    this.semanticLabel,
    this.loadingLabel = 'Gönderiliyor',
  }) : variant = AknButtonVariant.secondary;

  const AknButton.ghost({
    super.key,
    required this.label,
    this.onPressed,
    this.onPressedAsync,
    this.size = AknButtonSize.large,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.success = false,
    this.showSuccess = true,
    this.expand = false,
    this.haptic = true,
    this.semanticLabel,
    this.loadingLabel = 'Gönderiliyor',
  }) : variant = AknButtonVariant.ghost;

  const AknButton.danger({
    super.key,
    required this.label,
    this.onPressed,
    this.onPressedAsync,
    this.size = AknButtonSize.large,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.success = false,
    this.showSuccess = true,
    this.expand = false,
    this.haptic = true,
    this.semanticLabel,
    this.loadingLabel = 'Gönderiliyor',
  }) : variant = AknButtonVariant.danger;

  /// Neutral bordered button (ink label on white): cancel / back.
  const AknButton.outline({
    super.key,
    required this.label,
    this.onPressed,
    this.onPressedAsync,
    this.size = AknButtonSize.large,
    this.icon,
    this.trailingIcon,
    this.loading = false,
    this.success = false,
    this.showSuccess = true,
    this.expand = false,
    this.haptic = true,
    this.semanticLabel,
    this.loadingLabel = 'Gönderiliyor',
  }) : variant = AknButtonVariant.outline;

  final String label;
  final VoidCallback? onPressed;

  /// Async action: the button shows a spinner until it completes.
  final Future<void> Function()? onPressedAsync;
  final AknButtonVariant variant;
  final AknButtonSize size;
  final IconData? icon;
  final IconData? trailingIcon;
  final bool loading;
  final bool success;

  /// After [onPressedAsync] succeeds, show a check for a moment.
  final bool showSuccess;

  /// Full width. Otherwise the button keeps its natural width (centred when
  /// the parent forces a width, as in a ListView; wrap it in an `Align` to
  /// place it elsewhere).
  final bool expand;
  final bool haptic;
  final String? semanticLabel;
  final String loadingLabel;

  /// Icon + gap beside the label.
  static const double _iconSpace = 30;

  /// Rounding tolerance when deciding whether a label fits.
  static const double _fitSlack = 1;

  /// Horizontal padding (full / tightened).
  static double _padding(AknButtonSize size) =>
      size == AknButtonSize.small ? 14 : 18;
  static double _tightPadding(AknButtonSize size) =>
      size == AknButtonSize.small ? 6 : 8;

  /// Whether [label] fits on one line with the full padding (and [icon] when
  /// true) in a button [width] wide. Measured with the button's own text style
  /// and the current text scale. Parents use it to pick a layout (row vs.
  /// stacked) so that labels stay whole and readable.
  static bool fitsOneLine(
    BuildContext context,
    String label,
    double width, {
    bool icon = false,
    bool bordered = false,
    AknButtonSize size = AknButtonSize.medium,
  }) {
    final w = _labelWidth(context, label, labelStyle(context, size));
    return w +
            (icon ? _iconSpace : 0) +
            2 * _padding(size) +
            (bordered ? 3 : 0) <=
        width - _fitSlack;
  }

  /// The label style as rendered (inherited style, bold-text setting): the
  /// `button` style (16/20 600; driver mode 18/22), 15 px when small.
  static TextStyle labelStyle(BuildContext context, AknButtonSize size) {
    final button = context.aknText.button;
    var style = DefaultTextStyle.of(context).style.merge(
      size == AknButtonSize.small && !context.isDriverMode
          ? button.copyWith(fontSize: 15, height: 20 / 15)
          : button,
    );
    if (MediaQuery.boldTextOf(context)) {
      style = style.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    return style;
  }

  static double _labelWidth(
    BuildContext context,
    String text,
    TextStyle style,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final w = tp.width;
    tp.dispose();
    return w;
  }

  static int _lineCount(
    BuildContext context,
    String text,
    TextStyle style,
    double maxWidth,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      textAlign: TextAlign.center,
    )..layout(maxWidth: maxWidth);
    final n = tp.computeLineMetrics().length;
    tp.dispose();
    return n;
  }

  @override
  State<AknButton> createState() => _AknButtonState();
}

/// How the label is laid out in the available width.
enum _LabelFit {
  /// Width unknown (natural-width button): label up to two lines.
  natural,

  /// One line, full padding, icons.
  full,

  /// One line, tightened padding, icons.
  tight,

  /// One line, tightened padding, no icons.
  noIcon,

  /// Two lines broken at word boundaries, tightened padding, no icons.
  twoLines,

  /// One line scaled down to fit (last resort), tightened padding, no icons.
  scaled;

  bool get showsIcons => this == natural || this == full || this == tight;
  bool get tightPadding => index >= tight.index;
}

class _AknButtonState extends State<AknButton> {
  bool _pressed = false;
  bool _busy = false;
  bool _done = false;
  bool _focused = false;
  Timer? _doneTimer;

  bool get _loading => widget.loading || _busy;
  bool get _success => (widget.success || _done) && !_loading;
  bool get _enabled =>
      (widget.onPressed != null || widget.onPressedAsync != null) &&
      !_loading &&
      !_success;

  double _height(AknDriverMode? driver) {
    if (driver != null) return driver.buttonHeight;
    return switch (widget.size) {
      AknButtonSize.small => 40,
      AknButtonSize.medium => 48,
      AknButtonSize.large => 52,
    };
  }

  double _radius(AknDriverMode? driver) {
    if (driver != null) return driver.buttonRadius;
    return widget.size == AknButtonSize.small ? AknRadius.sm : AknRadius.md;
  }

  @override
  void dispose() {
    _doneTimer?.cancel();
    super.dispose();
  }

  Future<void> _tap() async {
    if (!_enabled) return;
    if (widget.haptic) AknHaptics.light();
    final sync = widget.onPressed;
    if (sync != null) {
      sync();
      return;
    }
    final run = widget.onPressedAsync;
    if (run == null) return;
    setState(() => _busy = true);
    var ok = false;
    try {
      await run();
      ok = true;
    } catch (e, st) {
      // The action owns its error UI (toast, inline error); never crash here.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: e,
          stack: st,
          library: 'akn ui',
          context: ErrorDescription('AknButton "${widget.label}" action'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _done = ok && widget.showSuccess;
        });
        if (_done) {
          AknHaptics.success();
          _doneTimer = Timer(const Duration(milliseconds: 1200), () {
            if (mounted) setState(() => _done = false);
          });
        }
      }
    }
  }

  void _setPressed(bool v) {
    if (_pressed == v) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final driver = context.driverMode;
    final enabled = _enabled;
    final busyLook = _loading || _success;
    final onPlate = OnHero.isOn(context);
    final pressed = _pressed && enabled;
    final (bg, fg, border) = _colors(c, enabled || busyLook, pressed, onPlate);
    final height = _height(driver);
    final radius = BorderRadius.circular(_radius(driver));
    final labelStyle = AknButton.labelStyle(context, widget.size).copyWith(
      color: fg,
      decoration: widget.variant == AknButtonVariant.ghost
          ? TextDecoration.underline
          : null,
      decorationColor: fg,
      decorationThickness: 1.5,
    );
    final iconSize =
        driver?.buttonIconSize ??
        (widget.size == AknButtonSize.small ? 20.0 : 22.0);
    final drop = pressed && widget.variant == AknButtonVariant.primary;

    Widget label(_LabelFit fit) => Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (fit.showsIcons && widget.icon != null) ...[
          Icon(widget.icon, size: iconSize, color: fg),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: switch (fit) {
            _LabelFit.natural || _LabelFit.twoLines => Text(
              widget.label,
              style: labelStyle,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
            // One line that is known to fit; the scale-down only absorbs
            // rounding (and is the last resort for [_LabelFit.scaled]).
            _ => FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.label,
                style: labelStyle,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
              ),
            ),
          },
        ),
        if (fit.showsIcons && widget.trailingIcon != null) ...[
          const SizedBox(width: 8),
          Icon(widget.trailingIcon, size: iconSize, color: fg),
        ],
      ],
    );

    // The label keeps its place while loading (the width never changes);
    // the spinner / check sits over it.
    Widget content(_LabelFit fit) => Stack(
      alignment: Alignment.center,
      children: [
        AnimatedOpacity(
          opacity: busyLook ? 0 : 1,
          duration: AknMotion.of(context, AknMotion.fast),
          // A pressed primary drops its content 1 px.
          child: Transform.translate(
            offset: Offset(0, drop ? 1 : 0),
            child: label(fit),
          ),
        ),
        if (_loading)
          ChevronSpinner(
            key: const ValueKey('loading'),
            size: height * 0.38,
            color: fg,
            semanticLabel: null,
          )
        else if (_success)
          Icon(
            Icons.check_rounded,
            key: const ValueKey('success'),
            color: fg,
            size: height * 0.46,
          ),
      ],
    );

    Widget surface(double? width, _LabelFit fit) => AnimatedContainer(
      duration: AknMotion.of(
        context,
        pressed ? AknMotion.press : AknMotion.pressOut,
      ),
      curve: AknMotion.standard,
      width: width,
      constraints: BoxConstraints(minHeight: height, minWidth: height),
      padding: EdgeInsets.symmetric(
        horizontal: fit.tightPadding
            ? AknButton._tightPadding(widget.size)
            : AknButton._padding(widget.size),
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: radius,
        border: border == null
            ? null
            : Border.all(
                color: border,
                width: 1.5,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
      ),
      foregroundDecoration: _focused
          ? BoxDecoration(
              borderRadius: radius,
              border: Border.fromBorderSide(AknTheme.focusRing(c)),
            )
          : null,
      // Shrink-wraps unless the width is forced ([AknButton.expand]).
      child: Center(widthFactor: 1, heightFactor: 1, child: content(fit)),
    );

    final Widget visual = widget.expand
        ? LayoutBuilder(
            builder: (context, constraints) => Align(
              heightFactor: 1,
              child: surface(
                constraints.hasBoundedWidth ? constraints.maxWidth : null,
                constraints.hasBoundedWidth
                    ? _fit(context, constraints.maxWidth, border != null)
                    : _LabelFit.natural,
              ),
            ),
          )
        : surface(null, _LabelFit.natural);

    final minTap = driver?.minTap ?? AknSpace.minTap;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.label,
      value: _loading
          ? widget.loadingLabel
          : _success
          ? 'Tamamlandı'
          : null,
      onTap: enabled ? () => unawaited(_tap()) : null,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: enabled,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              unawaited(_tap());
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => _setPressed(true) : null,
          onTapUp: enabled ? (_) => _setPressed(false) : null,
          onTapCancel: enabled ? () => _setPressed(false) : null,
          onTap: enabled ? () => unawaited(_tap()) : null,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minTap, minWidth: minTap),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: AnimatedScale(
                scale: pressed && !context.reduceMotion
                    ? AknMotion.pressScale
                    : 1,
                duration: pressed ? AknMotion.press : AknMotion.pressOut,
                curve: AknMotion.standard,
                child: visual,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Label measurements for the current label / style / text scale.
  ({String label, TextStyle style, TextScaler scaler, double one, double word})?
  _measured;

  /// Picks the label layout for a button [maxWidth] wide (see [_LabelFit]).
  _LabelFit _fit(BuildContext context, double maxWidth, bool bordered) {
    final style = AknButton.labelStyle(context, widget.size);
    final scaler = MediaQuery.textScalerOf(context);
    var m = _measured;
    if (m == null ||
        m.label != widget.label ||
        m.style != style ||
        m.scaler != scaler) {
      final words = widget.label.split(RegExp(r'\s+'));
      var word = 0.0;
      for (final w in words) {
        if (w.isEmpty) continue;
        final width = AknButton._labelWidth(context, w, style);
        if (width > word) word = width;
      }
      m = (
        label: widget.label,
        style: style,
        scaler: scaler,
        one: AknButton._labelWidth(context, widget.label, style),
        word: word,
      );
      _measured = m;
    }
    final border = bordered ? 3.0 : 0.0;
    final room = maxWidth - AknButton._fitSlack - border;
    final icons =
        (widget.icon != null ? AknButton._iconSpace : 0) +
        (widget.trailingIcon != null ? AknButton._iconSpace : 0);
    final pad = AknButton._padding(widget.size);
    final tight = AknButton._tightPadding(widget.size);
    if (m.one + icons + 2 * pad <= room) return _LabelFit.full;
    if (m.one + icons + 2 * tight <= room) return _LabelFit.tight;
    final text = room - 2 * tight;
    if (m.one <= text) return _LabelFit.noIcon;
    if (m.word <= text &&
        AknButton._lineCount(context, widget.label, style, text) <= 2) {
      return _LabelFit.twoLines;
    }
    return _LabelFit.scaled;
  }

  (Color, Color, Color?) _colors(
    AknColors c,
    bool enabled,
    bool pressed,
    bool onPlate,
  ) {
    if (onPlate) {
      // The plate rule: black key with a plate-coloured label; the rest is
      // black on orange.
      final ink = c.onPlate;
      final press = Color.alphaBlend(ink.withValues(alpha: 0.16), c.plate);
      if (!enabled) {
        return (c.plateLine, ink.withValues(alpha: 0.55), null);
      }
      return switch (widget.variant) {
        AknButtonVariant.primary => (
          pressed
              ? Color.alphaBlend(c.plate.withValues(alpha: 0.12), ink)
              : ink,
          c.plate,
          null,
        ),
        AknButtonVariant.ghost => (
          pressed ? press : Colors.transparent,
          ink,
          null,
        ),
        _ => (pressed ? press : Colors.transparent, ink, ink),
      };
    }
    if (!enabled) {
      return switch (widget.variant) {
        AknButtonVariant.ghost => (Colors.transparent, c.faint, null),
        _ => (c.surfaceAlt, c.faint, null),
      };
    }
    return switch (widget.variant) {
      AknButtonVariant.primary => (
        pressed ? c.brandFillPressed : c.brandFill,
        c.onBrandFill,
        null,
      ),
      AknButtonVariant.danger => (
        pressed ? c.surfaceAlt : c.surface,
        c.danger.fg,
        c.lineStrong,
      ),
      AknButtonVariant.secondary || AknButtonVariant.outline => (
        pressed ? c.surfaceAlt : c.surface,
        c.ink,
        c.lineStrong,
      ),
      AknButtonVariant.ghost => (
        pressed ? c.surfaceAlt : Colors.transparent,
        c.ink,
        null,
      ),
    };
  }
}

/// Round icon button (§6.5): icon 24 in ink, a 48 dp target (64 in driver
/// mode), a `surfaceAlt` circle when pressed, a required screen-reader label
/// and an optional count badge.
class AknIconButton extends StatelessWidget {
  const AknIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.color,
    this.background,
    this.size = 24,
    this.badgeCount = 0,
    this.showDot = false,
    this.tooltip = true,
    this.badgeSemantics,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final Color? color;
  final Color? background;
  final double size;
  final int badgeCount;
  final bool showDot;
  final bool tooltip;

  /// What the badge means for a screen reader: `(n) => '$n okunmamış'`
  /// (default "N yeni").
  final String Function(int count)? badgeSemantics;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final minTap = context.minTap;
    final Widget glyph = Icon(icon, size: size, color: color ?? c.ink);
    final Widget withBadge = badgeCount > 0 || showDot
        ? _BadgeOverlay(count: badgeCount, dot: showDot, child: glyph)
        : glyph;
    final button = IconButton(
      onPressed: onPressed == null
          ? null
          : () {
              AknHaptics.selection();
              onPressed!();
            },
      icon: withBadge,
      style:
          IconButton.styleFrom(
            backgroundColor: background,
            minimumSize: Size(minTap, minTap),
            highlightColor: c.surfaceAlt,
          ).copyWith(
            overlayColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.pressed)
                  ? c.surfaceAlt
                  : s.contains(WidgetState.focused)
                  ? c.brand.withValues(alpha: 0.24)
                  : Colors.transparent,
            ),
          ),
    );
    final label = badgeCount > 0
        ? '$semanticLabel, ${badgeSemantics?.call(badgeCount) ?? '$badgeCount yeni'}'
        : semanticLabel;
    return Semantics(
      label: label,
      button: true,
      excludeSemantics: true,
      onTap: onPressed,
      child: tooltip
          ? Tooltip(
              message: semanticLabel,
              excludeFromSemantics: true,
              child: button,
            )
          : button,
    );
  }
}

/// Count badge / dot over an icon (shared with the bottom bar and bell):
/// the count sits at top −2, right −12 of the icon box (§6.3).
class _BadgeOverlay extends StatelessWidget {
  const _BadgeOverlay({
    required this.count,
    required this.dot,
    required this.child,
  });

  final int count;
  final bool dot;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: count > 0 ? -12 : -2,
          top: count > 0 ? -4 : -1,
          child: AknCountBadge(count: count, dot: count <= 0 && dot),
        ),
      ],
    );
  }
}

/// The count badge (§6.3): an Asfalt pill (dark: #F1F2F4 with #16191D
/// digits), min 18 × 18, 11/18 700, with a 2 px ring in the colour behind it
/// ([ringColor]: the bar or page). Red is reserved for danger. Without a
/// count, [dot] shows an 8 px logo-orange dot. It pops in when it appears.
class AknCountBadge extends StatelessWidget {
  const AknCountBadge({
    super.key,
    required this.count,
    this.dot = false,
    this.max = 99,
    this.color,
    this.ringColor,
  });

  final int count;
  final bool dot;
  final int max;

  /// Badge fill (default `ink`; black on the plate).
  final Color? color;

  /// The 2 px cut-out ring (default the page colour; the plate on it).
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final visible = count > 0 || dot;
    final onPlate = OnHero.isOn(context);
    final fill = color ?? (onPlate ? c.onPlate : c.ink);
    final digits = onPlate ? c.plate : c.bg;
    final ring = ringColor ?? (onPlate ? c.plate : c.bg);
    final Widget body = count > 0
        ? Container(
            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            padding: const EdgeInsets.symmetric(horizontal: 7),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: AknRadius.pillAll,
              border: Border.all(color: ring, width: 2),
            ),
            child: Text(
              count > max ? '$max+' : '$count',
              textScaler: TextScaler.noScaling,
              style: context.aknText.label.copyWith(
                color: digits,
                fontSize: 11,
                height: 14 / 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        : Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: onPlate ? c.onPlate : c.logo,
              shape: BoxShape.circle,
              border: Border.all(color: ring, width: 2),
            ),
          );
    return ExcludeSemantics(
      child: AnimatedScale(
        scale: visible ? 1 : 0,
        duration: AknMotion.of(context, AknMotion.base),
        curve: visible ? AknMotion.emphasizedCurve : AknMotion.exit,
        child: visible ? body : const SizedBox(width: 12, height: 12),
      ),
    );
  }
}

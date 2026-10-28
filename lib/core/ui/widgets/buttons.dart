import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../driver_mode.dart';
import '../motion.dart';
import '../painters/chevron_spinner.dart';
import '../theme.dart';
import '../tokens.dart';
import '../typography.dart';

/// Button looks (design v3 §4 Buttons), all superellipses (r16; small r12,
/// driver r18):
/// * primary — the orange gradient `brandFillStart` → `brandFill` (#FF7B35 →
///   #E5530A) with a WHITE 16 px w700 label and a warm orange glow under it
///   (owner decision G); one per screen region;
/// * secondary / outline — white (`surface`) with a 1.5 px `lineStrong` 60 %
///   border and an ink label (dark: a `surfaceAlt` fill, no border);
/// * ghost — no fill, an ink label; pressed `surfaceAlt` (tertiary: "Vazgeç",
///   "Atla");
/// * danger — the secondary look with a red label (the page-level
///   "Reddet"; a sheet's destructive confirm is `DestructiveButton`).
enum AknButtonVariant { primary, secondary, ghost, danger, outline }

/// Heights: small 40 (r12, 15 px label), medium 48, large 52 (the default);
/// every size keeps a 48 dp touch target. Driver mode makes every button 64
/// (r18, 18/22 label).
enum AknButtonSize { small, medium, large }

/// The AkaryakıtNet button (design v3 §4 Buttons, §5 Press): a superellipse
/// with the `button` 16/20 w700 label.
///
/// * Press: the button scales to 0.97 the moment a finger lands (100 ms in,
///   a 260 ms spring back — the `PressScale` press) with a light haptic on
///   the tap; the fill deepens and the primary's glow settles onto the page
///   while it is held. A press that turns into a scroll lets go at once.
/// * [loading] cross-fades the label (it also shrinks a little) into a
///   spinner in the label colour; the width never changes. [success] pops a
///   check in. With [onPressedAsync] the button manages both by itself
///   (spinner while the future runs, then a short check when
///   [showSuccess]).
/// * Disabled (both callbacks null): `surfaceAlt` fill, faint label, no
///   border, no glow — the change animates.
/// * On the plate card (inside `AknPlate` / `OnHero`) every variant keeps
///   its normal look (the card is white).
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

  /// Gap between an icon and the label.
  static const double _iconGap = 8;

  /// Rounding tolerance when deciding whether a label fits.
  static const double _fitSlack = 1;

  /// Horizontal padding (full / tightened).
  static double _padding(AknButtonSize size) =>
      size == AknButtonSize.small ? 14 : 18;
  static double _tightPadding(AknButtonSize size) =>
      size == AknButtonSize.small ? 6 : 8;

  /// Icon size: 20 (small 18; driver mode 24).
  static double _iconSizeOf(BuildContext context, AknButtonSize size) =>
      context.driverMode?.buttonIconSize ??
      (size == AknButtonSize.small ? 18.0 : 20.0);

  /// Icon + gap beside the label.
  static double _iconSpaceOf(BuildContext context, AknButtonSize size) =>
      _iconSizeOf(context, size) + _iconGap;

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
            (icon ? _iconSpaceOf(context, size) : 0) +
            2 * _padding(size) +
            (bordered ? 3 : 0) <=
        width - _fitSlack;
  }

  /// The label style as rendered (inherited style, bold-text setting): the
  /// `button` style 16/20 w700 (driver mode 18/22), 15 px when small. Every
  /// variant shares it; [primary] is kept for API stability.
  static TextStyle labelStyle(
    BuildContext context,
    AknButtonSize size, {
    bool primary = false,
  }) {
    final button = context.aknText.button;
    final driver = context.isDriverMode;
    final base = size == AknButtonSize.small && !driver
        ? button.copyWith(fontSize: 15, height: 20 / 15)
        : button;
    var style = DefaultTextStyle.of(
      context,
    ).style.merge(base.copyWith(fontWeight: FontWeight.w700));
    if (MediaQuery.boldTextOf(context)) {
      style = style.merge(const TextStyle(fontWeight: FontWeight.w800));
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

/// One state of a button's surface: its fill (always a gradient, so every
/// change lerps smoothly), label colour, border and glow.
typedef _Look = ({
  LinearGradient fill,
  Color fg,
  BorderSide side,
  List<BoxShadow> glow,
});

class _AknButtonState extends State<AknButton> {
  bool _pressed = false;
  bool _busy = false;
  bool _done = false;
  bool _focused = false;
  Offset? _downAt;
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
    return widget.size == AknButtonSize.small
        ? AknRadius.sm
        : AknRadius.button.topLeft.x;
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
    if (_pressed == v || !mounted) return;
    setState(() => _pressed = v);
  }

  /// A press that travels past the touch slop is a scroll: let go.
  void _moved(PointerMoveEvent e) {
    final from = _downAt;
    if (from != null && (e.position - from).distance > kTouchSlop) {
      _downAt = null;
      _setPressed(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final driver = context.driverMode;
    final reduced = AknMotion.reduced(context);
    final enabled = _enabled;
    final busyLook = _loading || _success;
    final pressed = _pressed && enabled;
    final look = _look(c, enabled || busyLook, pressed);
    final height = _height(driver);
    final radius = BorderRadius.all(Radius.circular(_radius(driver)));
    final style = AknButton.labelStyle(context, widget.size);
    final iconSize = AknButton._iconSizeOf(context, widget.size);
    final pressDuration = pressed ? AknMotion.press : AknMotion.pressOut;

    Widget label(_LabelFit fit, Color fg) {
      final labelStyle = style.copyWith(color: fg);
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (fit.showsIcons && widget.icon != null) ...[
            Icon(widget.icon, size: iconSize, color: fg),
            const SizedBox(width: AknButton._iconGap),
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
            const SizedBox(width: AknButton._iconGap),
            Icon(widget.trailingIcon, size: iconSize, color: fg),
          ],
        ],
      );
    }

    // The label keeps its place while loading (the width never changes): it
    // fades and shrinks away while the spinner / check pops in over it.
    Widget content(_LabelFit fit) => Stack(
      alignment: Alignment.center,
      children: [
        AnimatedOpacity(
          opacity: busyLook ? 0 : 1,
          duration: AknMotion.of(context, AknMotion.fast),
          curve: AknMotion.standard,
          child: AnimatedScale(
            scale: busyLook && !reduced ? 0.86 : 1,
            duration: AknMotion.of(context, AknMotion.base),
            curve: AknMotion.emphasizedCurve,
            child: TweenAnimationBuilder<Color?>(
              tween: ColorTween(end: look.fg),
              duration: AknMotion.of(context, AknMotion.fast),
              builder: (context, fg, _) => label(fit, fg ?? look.fg),
            ),
          ),
        ),
        Positioned.fill(
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: AnimatedSwitcher(
              duration: AknMotion.of(context, AknMotion.base),
              reverseDuration: AknMotion.of(context, AknMotion.fast),
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a.drive(CurveTween(curve: Curves.easeOut)),
                child: ScaleTransition(
                  scale: a.drive(
                    Tween<double>(
                      begin: 0.4,
                      end: 1,
                    ).chain(CurveTween(curve: AknMotion.pop)),
                  ),
                  child: child,
                ),
              ),
              child: _loading
                  ? ChevronSpinner(
                      key: const ValueKey('loading'),
                      size: height * 0.38,
                      color: look.fg,
                      semanticLabel: null,
                    )
                  : _success
                  ? Icon(
                      PhosphorIconsRegular.check,
                      key: const ValueKey('success'),
                      color: look.fg,
                      size: height * 0.48,
                    )
                  : const SizedBox.shrink(key: ValueKey('idle')),
            ),
          ),
        ),
      ],
    );

    Widget surface(double? width, _LabelFit fit) => AnimatedContainer(
      duration: AknMotion.of(context, pressDuration),
      curve: AknMotion.standard,
      width: width,
      constraints: BoxConstraints(minHeight: height, minWidth: height),
      padding: EdgeInsets.symmetric(
        horizontal: fit.tightPadding
            ? AknButton._tightPadding(widget.size)
            : AknButton._padding(widget.size),
        vertical: 6,
      ),
      decoration: ShapeDecoration(
        gradient: look.fill,
        shadows: look.glow,
        shape: RoundedSuperellipseBorder(borderRadius: radius, side: look.side),
      ),
      foregroundDecoration: _focused
          ? ShapeDecoration(
              shape: RoundedSuperellipseBorder(
                borderRadius: radius,
                side: AknTheme.focusRing(c),
              ),
            )
          : null,
      // Shrink-wraps unless the width is forced ([AknButton.expand]).
      child: Center(widthFactor: 1, heightFactor: 1, child: content(fit)),
    );

    final bordered = look.side.width > 0;
    final Widget visual = widget.expand
        ? LayoutBuilder(
            builder: (context, constraints) => Align(
              heightFactor: 1,
              child: surface(
                constraints.hasBoundedWidth ? constraints.maxWidth : null,
                constraints.hasBoundedWidth
                    ? _fit(context, constraints.maxWidth, bordered)
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
        // The press lands with the finger (raw pointer events, like
        // `PressScale`); the tap itself still goes through the arena.
        child: Listener(
          onPointerDown: enabled
              ? (e) {
                  _downAt = e.position;
                  _setPressed(true);
                }
              : null,
          onPointerMove: _moved,
          onPointerUp: (_) => _setPressed(false),
          onPointerCancel: (_) => _setPressed(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? () => unawaited(_tap()) : null,
            onTapCancel: () => _setPressed(false),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minTap, minWidth: minTap),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: AnimatedScale(
                  scale: pressed && !reduced ? AknMotion.pressScale : 1,
                  duration: pressDuration,
                  curve: pressed ? AknMotion.standard : AknMotion.spring,
                  child: visual,
                ),
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
    final space = AknButton._iconSpaceOf(context, widget.size);
    final icons =
        (widget.icon != null ? space : 0) +
        (widget.trailingIcon != null ? space : 0);
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

  /// The surface for [variant] in palette [c]: [live] (enabled, or busy
  /// with the enabled look) and [pressed].
  _Look _look(AknColors c, bool live, bool pressed) {
    final g = c.buttonGradient;
    LinearGradient flat(Color color) =>
        LinearGradient(begin: g.begin, end: g.end, colors: [color, color]);
    final variant = widget.variant;
    final bordered =
        !c.isDark &&
        (variant == AknButtonVariant.secondary ||
            variant == AknButtonVariant.outline ||
            variant == AknButtonVariant.danger);
    // A constant border width keeps the label still when the state changes.
    final rim = bordered ? 1.5 : 0.0;
    BorderSide side(Color color) =>
        rim == 0 ? BorderSide.none : BorderSide(color: color, width: rim);
    final clear = c.surfaceAlt.withValues(alpha: 0);
    if (!live) {
      return (
        fill: flat(variant == AknButtonVariant.ghost ? clear : c.surfaceAlt),
        fg: c.faint,
        side: side(AknTheme.secondaryBorder(c).withValues(alpha: 0)),
        glow: const <BoxShadow>[],
      );
    }
    return switch (variant) {
      AknButtonVariant.primary => (
        fill: _brandGradient(c, pressed),
        fg: c.onBrandFill,
        side: BorderSide.none,
        glow: _glow(c, pressed),
      ),
      AknButtonVariant.secondary ||
      AknButtonVariant.outline ||
      AknButtonVariant.danger => (
        fill: flat(
          c.isDark
              ? (pressed
                    ? Color.alphaBlend(
                        c.ink.withValues(alpha: 0.08),
                        c.surfaceAlt,
                      )
                    : c.surfaceAlt)
              : (pressed ? c.surfaceAlt : c.surface),
        ),
        fg: variant == AknButtonVariant.danger ? c.danger.fg : c.ink,
        side: side(AknTheme.secondaryBorder(c)),
        glow: const <BoxShadow>[],
      ),
      AknButtonVariant.ghost => (
        fill: flat(pressed ? c.surfaceAlt : clear),
        fg: c.ink,
        side: BorderSide.none,
        glow: const <BoxShadow>[],
      ),
    };
  }

  /// The primary fill. A subtree that re-themes `brandFill` alone (a red
  /// destructive confirm) does not inherit the orange start: it paints its
  /// fill flat instead.
  static LinearGradient _brandGradient(AknColors c, bool pressed) {
    final g = pressed ? c.buttonGradientPressed : c.buttonGradient;
    if (_sameHue(c.brandFillStart, c.brandFill)) return g;
    final fill = pressed ? c.brandFillPressed : c.brandFill;
    return LinearGradient(begin: g.begin, end: g.end, colors: [fill, fill]);
  }

  static bool _sameHue(Color a, Color b) {
    final d = (HSVColor.fromColor(a).hue - HSVColor.fromColor(b).hue).abs();
    return math.min(d, 360 - d) <= 10;
  }

  /// The warm glow under the primary ([AknShadows.button]) in the colour of
  /// the fill; it settles closer and dimmer while pressed.
  static List<BoxShadow> _glow(AknColors c, bool pressed) => [
    for (final s in AknShadows.button(c))
      BoxShadow(
        color: c.brandFill.withValues(alpha: s.color.a * (pressed ? 0.6 : 1)),
        offset: pressed ? s.offset * 0.4 : s.offset,
        blurRadius: pressed ? s.blurRadius * 0.55 : s.blurRadius,
        spreadRadius: s.spreadRadius,
      ),
  ];
}

/// Round icon button (§4, §5 Press): icon 24 in ink, a 48 dp target (64 in
/// driver mode), a required screen-reader label and an optional count
/// badge. Pressing it scales the icon down (0.9, spring back) over a soft
/// `surfaceAlt` circle that fades in, with a light haptic. [tonal] keeps a
/// 40 px `surfaceAlt` circle behind the icon (white 20 % glass on the band).
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
    this.tonal = false,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final Color? color;

  /// A fill behind the icon (overrides [tonal]'s circle colour).
  final Color? background;
  final double size;
  final int badgeCount;
  final bool showDot;
  final bool tooltip;

  /// What the badge means for a screen reader: `(n) => '$n okunmamış'`
  /// (default "N yeni").
  final String Function(int count)? badgeSemantics;

  /// A soft circle behind the icon (40 px; 56 in driver mode).
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final active = onPressed != null;
    final Widget glyph = Icon(
      icon,
      size: size,
      color: active
          ? (color ?? c.ink)
          : (color?.withValues(alpha: 0.5) ?? c.faint),
    );
    final Widget withBadge = badgeCount > 0 || showDot
        ? _BadgeOverlay(count: badgeCount, dot: showDot, child: glyph)
        : glyph;
    final button = _IconPress(
      onPressed: onPressed,
      background: background ?? (tonal ? c.surfaceAlt : null),
      circle: tonal ? context.minTap - 8 : context.minTap,
      child: withBadge,
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

/// The press of [AknIconButton]: a [circle] px disc ([background], or none
/// at rest) that deepens while pressed, the content scaling to 0.9 and
/// springing back; keyboard focus shows the brand ring. The touch target is
/// the full minimum tap size.
class _IconPress extends StatefulWidget {
  const _IconPress({
    required this.onPressed,
    required this.background,
    required this.circle,
    required this.child,
  });

  final VoidCallback? onPressed;
  final Color? background;
  final double circle;
  final Widget child;

  @override
  State<_IconPress> createState() => _IconPressState();
}

class _IconPressState extends State<_IconPress> {
  bool _down = false;
  bool _focused = false;

  void _set(bool v) {
    if (_down == v || !mounted) return;
    setState(() => _down = v);
  }

  void _activate() {
    final cb = widget.onPressed;
    if (cb == null) return;
    AknHaptics.light();
    cb();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final active = widget.onPressed != null;
    final down = _down && active;
    final reduced = AknMotion.reduced(context);
    final rest = widget.background;
    final fill = down
        ? (rest == null
              ? c.surfaceAlt
              : Color.alphaBlend(c.ink.withValues(alpha: 0.08), rest))
        : (rest ?? c.surfaceAlt.withValues(alpha: 0));
    final duration = down ? AknMotion.press : AknMotion.pressOut;
    final minTap = context.minTap;
    return FocusableActionDetector(
      enabled: active,
      mouseCursor: active ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _activate();
            return null;
          },
        ),
      },
      child: Listener(
        onPointerDown: active ? (_) => _set(true) : null,
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: active ? _activate : null,
          onTapCancel: () => _set(false),
          child: SizedBox(
            width: math.max(minTap, widget.circle),
            height: math.max(minTap, widget.circle),
            child: Center(
              child: AnimatedContainer(
                duration: AknMotion.of(context, duration),
                curve: AknMotion.standard,
                width: widget.circle,
                height: widget.circle,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: fill,
                  shape: BoxShape.circle,
                  border: _focused
                      ? Border.fromBorderSide(AknTheme.focusRing(c))
                      : null,
                ),
                child: AnimatedScale(
                  scale: down && !reduced ? 0.9 : 1,
                  duration: duration,
                  curve: down ? AknMotion.standard : AknMotion.spring,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Count badge / dot over an icon (shared with the bottom bar and bell):
/// the count sits at top −4, right −12 of the icon box (§4).
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

/// The count badge (v3 §4): a deep-orange pill (`brandFillPressed`, #CC4708;
/// white figures 4.70:1, AA) with white 10 w800 tabular figures, min 18 × 18
/// inside a 2 px ring in the colour behind it
/// ([ringColor], default `surface`); on the orange band it flips to a white
/// pill with deep-orange figures. Without a count, [dot] shows an 8 px dot.
///
/// Motion: it pops in (and out) on a spring, bumps when the count changes
/// (the new figures roll up), and breathes gently — a soft glow and a 6 %
/// swell — while it shows (ambient; still in tests and under reduce motion).
class AknCountBadge extends StatelessWidget {
  const AknCountBadge({
    super.key,
    required this.count,
    this.dot = false,
    this.max = 99,
    this.color,
    this.ringColor,
    this.textColor,
  });

  final int count;
  final bool dot;
  final int max;

  /// Badge fill (default deep orange `brandFillPressed`; white on the header
  /// band).
  final Color? color;

  /// The 2 px cut-out ring (default `surface`; the band on it).
  final Color? ringColor;

  /// The figures (default white; deep orange on the band).
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final band = c.isBandPalette;
    final visible = count > 0 || dot;
    final fill = color ?? (band ? c.onHero : c.brandFillPressed);
    final digits = textColor ?? (band ? c.brandFillPressed : c.onBrandFill);
    final ring = ringColor ?? c.surface;
    final text = count > max ? '$max+' : '$count';
    final Widget body = count > 0
        ? Container(
            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            padding: const EdgeInsets.symmetric(horizontal: 5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: AknRadius.pillAll,
              border: Border.all(color: ring, width: 2),
            ),
            child: _BadgeFigures(
              text: text,
              style: context.aknText.label.copyWith(
                color: digits,
                fontSize: 10,
                height: 12 / 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
                fontFeatures: AknNumerals.tabular,
              ),
            ),
          )
        : Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: Border.all(color: ring, width: 2),
            ),
          );
    return ExcludeSemantics(
      child: _BadgeMotion(
        visible: visible,
        count: count,
        glow: fill,
        child: visible ? body : const SizedBox(width: 12, height: 12),
      ),
    );
  }
}

/// The badge figures: a new count rolls up from below while the old one
/// leaves upwards; the pill's width follows smoothly.
class _BadgeFigures extends StatelessWidget {
  const _BadgeFigures({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return AknAnimatedSize(
      duration: AknMotion.fast,
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: AknMotion.of(context, AknMotion.base),
          transitionBuilder: (child, a) {
            final incoming = child.key == ValueKey(text);
            final slide = Tween<Offset>(
              begin: Offset(0, incoming ? 0.8 : -0.8),
              end: Offset.zero,
            ).chain(CurveTween(curve: AknMotion.emphasizedCurve));
            return FadeTransition(
              opacity: a,
              child: SlideTransition(position: a.drive(slide), child: child),
            );
          },
          child: Text(
            text,
            key: ValueKey(text),
            textScaler: TextScaler.noScaling,
            style: style,
          ),
        ),
      ),
    );
  }
}

/// [AknCountBadge]'s motion: pop in / out ([visible]), a bump when [count]
/// changes and an ambient breath ([glow] halo + 6 % swell) while visible.
class _BadgeMotion extends StatefulWidget {
  const _BadgeMotion({
    required this.visible,
    required this.count,
    required this.glow,
    required this.child,
  });

  final bool visible;
  final int count;
  final Color glow;
  final Widget child;

  @override
  State<_BadgeMotion> createState() => _BadgeMotionState();
}

class _BadgeMotionState extends State<_BadgeMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bump = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(_BadgeMotion old) {
    super.didUpdateWidget(old);
    if (old.count != widget.count &&
        old.count > 0 &&
        widget.count > 0 &&
        !AknMotion.reduced(context)) {
      _bump.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.visible;
    Widget badge = AnimatedBuilder(
      animation: _bump,
      child: widget.child,
      builder: (context, child) {
        final t = _bump.value;
        // Up 22 % and back, with a little settle.
        final s = t == 0 || t == 1
            ? 1.0
            : 1 + 0.22 * math.sin(math.pi * Curves.easeOut.transform(t));
        return Transform.scale(scale: s, child: child);
      },
    );
    if (visible) {
      badge = AknAmbient(
        period: AknMotion.breathe,
        reverse: true,
        child: badge,
        builder: (context, t, child) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: AknRadius.pillAll,
            boxShadow: [
              BoxShadow(
                color: widget.glow.withValues(alpha: 0.4 * t),
                blurRadius: 8 * t,
                spreadRadius: 0.5 * t,
              ),
            ],
          ),
          child: Transform.scale(scale: 1 + 0.06 * t, child: child),
        ),
      );
    }
    return AnimatedScale(
      scale: visible ? 1 : 0,
      duration: AknMotion.of(context, AknMotion.base),
      curve: visible ? AknMotion.pop : AknMotion.exit,
      child: badge,
    );
  }
}

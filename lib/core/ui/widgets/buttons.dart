import 'dart:async';

import 'package:flutter/material.dart';

import '../motion.dart';
import '../painters/chevron_spinner.dart';
import '../theme.dart';
import '../tokens.dart';

enum AknButtonVariant { primary, secondary, ghost, danger }

/// Visual heights 40 / 48 / 56; every size keeps a 48 dp touch target.
enum AknButtonSize { small, medium, large }

/// The AkaryakıtNet button.
///
/// * Variants: primary (orange), secondary (outlined), ghost (text), danger.
/// * Press: scales to 0.97 with a light haptic.
/// * [loading] morphs the button into a compact spinner; [success] into a
///   check. With [onPressedAsync] the button manages both by itself:
///   spinner while the future runs, then a short check (when [showSuccess]).
/// * Disabled when both callbacks are null.
class AknButton extends StatefulWidget {
  const AknButton({
    super.key,
    required this.label,
    this.onPressed,
    this.onPressedAsync,
    this.variant = AknButtonVariant.primary,
    this.size = AknButtonSize.medium,
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
    this.size = AknButtonSize.medium,
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
    this.size = AknButtonSize.medium,
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
    this.size = AknButtonSize.medium,
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

  @override
  State<AknButton> createState() => _AknButtonState();
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

  double get _height => switch (widget.size) {
    AknButtonSize.small => 40,
    AknButtonSize.medium => 48,
    AknButtonSize.large => 56,
  };

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
    final t = context.aknText;
    final enabled = _enabled;
    final busyLook = _loading || _success;
    final (bg, fg, border) = _colors(c, enabled || busyLook, _pressed);
    final height = _height;
    final compact = busyLook;
    final radius = compact ? height / 2 : AknRadius.md;
    final duration = AknMotion.of(context, AknMotion.base);
    final textStyle = t.button.copyWith(
      color: fg,
      fontSize: widget.size == AknButtonSize.small ? 14 : 15,
    );

    final Widget content = AnimatedSwitcher(
      duration: AknMotion.of(context, AknMotion.fast),
      switchInCurve: AknMotion.standard,
      switchOutCurve: AknMotion.exit,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.85, end: 1).animate(a),
          child: child,
        ),
      ),
      child: _loading
          ? SizedBox(
              key: const ValueKey('loading'),
              height: height * 0.42,
              child: Center(
                child: ChevronSpinner(
                  size: height * 0.38,
                  color: fg,
                  semanticLabel: null,
                ),
              ),
            )
          : _success
          ? Icon(
              Icons.check_rounded,
              key: const ValueKey('success'),
              color: fg,
              size: height * 0.5,
            )
          : Row(
              key: const ValueKey('label'),
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 20, color: fg),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    style: textStyle,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.trailingIcon != null) ...[
                  const SizedBox(width: 8),
                  Icon(widget.trailingIcon, size: 20, color: fg),
                ],
              ],
            ),
    );

    Widget surface(double? width) => AnimatedContainer(
      duration: duration,
      curve: AknMotion.emphasizedCurve,
      width: width,
      constraints: BoxConstraints(minHeight: height, minWidth: height),
      padding: EdgeInsets.symmetric(
        horizontal: compact
            ? 0
            : widget.size == AknButtonSize.small
            ? 14
            : 20,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: border == null ? null : Border.all(color: border),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: c.brand.withValues(alpha: 0.45),
                  spreadRadius: 3,
                ),
              ]
            : null,
      ),
      // Shrink-wraps unless the width is forced ([AknButton.expand]).
      child: Center(widthFactor: 1, heightFactor: 1, child: content),
    );

    // Width is only ever animated between two finite values: the expanded
    // button morphs from the full width to a [height]-wide circle; a natural
    // width button never gets an explicit width (its compact content and
    // `minWidth: height` give the circle) and resizes through AknAnimatedSize.
    // `heightFactor: 1` keeps an expanded button at its own height in a bounded
    // slot (e.g. `AppScaffold.actionBar`).
    final Widget visual = widget.expand
        ? LayoutBuilder(
            builder: (context, constraints) => Align(
              heightFactor: 1,
              child: surface(
                constraints.hasBoundedWidth
                    ? (compact ? height : constraints.maxWidth)
                    : null,
              ),
            ),
          )
        : AknAnimatedSize(
            duration: duration,
            curve: AknMotion.emphasizedCurve,
            child: surface(null),
          );

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
            constraints: const BoxConstraints(
              minHeight: AknSpace.minTap,
              minWidth: AknSpace.minTap,
            ),
            child: Center(
              widthFactor: 1,
              heightFactor: 1,
              child: AnimatedScale(
                scale: _pressed && !context.reduceMotion ? 0.97 : 1,
                duration: AknMotion.fast,
                curve: AknMotion.standard,
                child: visual,
              ),
            ),
          ),
        ),
      ),
    );
  }

  (Color, Color, Color?) _colors(AknColors c, bool enabled, bool pressed) {
    if (!enabled) {
      return switch (widget.variant) {
        AknButtonVariant.primary || AknButtonVariant.danger => (
          c.isDark ? c.surfaceAlt : c.lineSoft,
          c.faint,
          null,
        ),
        AknButtonVariant.secondary => (c.surface, c.faint, c.line),
        AknButtonVariant.ghost => (const Color(0x00000000), c.faint, null),
      };
    }
    return switch (widget.variant) {
      AknButtonVariant.primary => (
        pressed ? c.brandFillPressed : c.brandFill,
        c.onBrandFill,
        null,
      ),
      AknButtonVariant.danger => (
        pressed
            ? Color.lerp(c.dangerFill, const Color(0xFF000000), 0.14)!
            : c.dangerFill,
        c.onDangerFill,
        null,
      ),
      AknButtonVariant.secondary => (
        pressed ? c.surfaceAlt : c.surface,
        c.ink,
        c.lineStrong,
      ),
      AknButtonVariant.ghost => (
        pressed ? c.brandSoft : const Color(0x00000000),
        c.brandInk,
        null,
      ),
    };
  }
}

/// Round icon button with a required screen-reader label, 48 dp target and
/// an optional count badge.
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
      style: background == null
          ? null
          : IconButton.styleFrom(backgroundColor: background),
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

/// Count bubble / dot over an icon (shared with the bottom bar and bell).
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
          right: count > 0 ? -8 : -2,
          top: count > 0 ? -6 : -1,
          child: AknCountBadge(count: count, dot: count <= 0 && dot),
        ),
      ],
    );
  }
}

/// Count bubble ("3", "99+") or dot that pops in when it appears and pulses
/// softly when the count changes. Hidden when there is nothing to show.
class AknCountBadge extends StatefulWidget {
  const AknCountBadge({
    super.key,
    required this.count,
    this.dot = false,
    this.max = 99,
    this.color,
  });

  final int count;
  final bool dot;
  final int max;
  final Color? color;

  @override
  State<AknCountBadge> createState() => _AknCountBadgeState();
}

class _AknCountBadgeState extends State<AknCountBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );

  @override
  void didUpdateWidget(AknCountBadge old) {
    super.didUpdateWidget(old);
    if (widget.count > old.count &&
        old.count > 0 &&
        !AknMotion.reduced(context)) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final visible = widget.count > 0 || widget.dot;
    final color = widget.color ?? c.brandFill;
    final Widget body = widget.count > 0
        ? Container(
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            padding: const EdgeInsets.symmetric(horizontal: 5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              borderRadius: AknRadius.pillAll,
              border: Border.all(color: c.surface, width: 1.5),
            ),
            child: Text(
              widget.count > widget.max ? '${widget.max}+' : '${widget.count}',
              textScaler: TextScaler.noScaling,
              style: const TextStyle(
                color: Color(0xFFFFFFFF),
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          )
        : Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: c.surface, width: 1.5),
            ),
          );
    return ExcludeSemantics(
      child: AnimatedScale(
        scale: visible ? 1 : 0,
        duration: AknMotion.of(context, AknMotion.base),
        curve: visible ? AknMotion.emphasizedCurve : AknMotion.exit,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final v = _pulse.value;
            final s = v == 0 ? 1.0 : 1 + 0.18 * (1 - (2 * v - 1).abs());
            return Transform.scale(scale: s, child: child);
          },
          child: visible ? body : const SizedBox(width: 9, height: 9),
        ),
      ),
    );
  }
}

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';
import 'buttons.dart';

/// Opens a bottom sheet in the v3 style (§4): a `surfaceRaised` sheet with
/// 28 px squircle top corners, a 40 × 5 pill handle, 20 px padding, an
/// optional title (`title` 20/26 700) with a round close button, the body,
/// and optional sticky [actionsBuilder] actions at the bottom (primary full
/// width first, then secondary / ghost). Keyboard-aware.
///
/// Motion: the sheet slides up over [AknMotion.sheet] (360 ms, emphasized)
/// while the scrim darkens and the page behind softly blurs (σ 6); the
/// title, body and actions rise into place one after another (40 ms apart).
/// Closing is quicker (240 ms). Reduce motion: no slide, no rise.
///
/// [backgroundColor] tints the sheet (e.g. `bg`, so white grouped cards
/// float on it); default `surfaceRaised`.
///
/// A sheet is for a decision that needs input (revize, red, teslim kanıtı,
/// filtre). Dialogs ([showAknDialog]) are only for blocking errors and
/// irreversible confirmations.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  String? subtitle,
  bool showClose = true,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = true,
  bool scrollable = true,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(20, 0, 20, 20),
  double maxHeightFactor = 0.92,
  WidgetBuilder? actionsBuilder,
  Color? backgroundColor,
}) {
  assert(debugCheckHasMaterialLocalizations(context));
  final reduced = AknMotion.reduced(context);
  final c = context.akn;
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final l = MaterialLocalizations.of(context);
  return navigator.push(
    _AknSheetRoute<T>(
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: l.scrimLabel,
      barrierOnTapHint: l.scrimOnTapHint(l.bottomSheetLabel),
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragHandle: false,
      backgroundColor: backgroundColor ?? c.surfaceRaised,
      elevation: 0,
      modalBarrierColor: c.scrim,
      shape: const RoundedSuperellipseBorder(borderRadius: AknRadius.sheet),
      clipBehavior: Clip.antiAlias,
      sheetAnimationStyle: reduced
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: AknMotion.sheet,
              reverseDuration: Duration(milliseconds: 240),
              curve: AknMotion.emphasizedCurve,
              reverseCurve: AknMotion.exit,
            ),
      builder: (ctx) => AppSheet(
        title: title,
        subtitle: subtitle,
        showClose: showClose,
        scrollable: scrollable,
        padding: padding,
        maxHeightFactor: maxHeightFactor,
        dismissible: isDismissible,
        actions: actionsBuilder == null
            ? null
            : Builder(builder: actionsBuilder),
        child: Builder(builder: builder),
      ),
    ),
  );
}

/// The sheet route: a Material modal bottom sheet whose scrim also blurs
/// the page behind it (σ 6), following the sheet's slide (and its drag).
class _AknSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _AknSheetRoute({
    required super.builder,
    required super.isScrollControlled,
    super.capturedThemes,
    super.barrierLabel,
    super.barrierOnTapHint,
    super.backgroundColor,
    super.elevation,
    super.shape,
    super.clipBehavior,
    super.modalBarrierColor,
    super.isDismissible,
    super.enableDrag,
    super.showDragHandle,
    super.useSafeArea,
    super.sheetAnimationStyle,
  });

  @override
  Widget buildModalBarrier() => _BlurredScrim(
    animation: animation,
    enabled: !offstage,
    child: super.buildModalBarrier(),
  );
}

/// Blurs what lies behind a modal scrim, up to σ 6, in step with the route
/// [animation] (so a dragged-down sheet un-blurs as it goes).
class _BlurredScrim extends StatelessWidget {
  const _BlurredScrim({
    required this.animation,
    required this.child,
    this.enabled = true,
  });

  final Animation<double>? animation;
  final bool enabled;
  final Widget child;

  static const double _sigma = 6;

  @override
  Widget build(BuildContext context) {
    final a = animation;
    if (a == null) return child;
    return AnimatedBuilder(
      animation: a,
      child: child,
      builder: (context, child) {
        final s = _sigma * Curves.easeOut.transform(a.value.clamp(0.0, 1.0));
        return BackdropFilter(
          enabled: enabled && s > 0.05,
          filter: ui.ImageFilter.blur(
            sigmaX: math.max(s, 0.05),
            sigmaY: math.max(s, 0.05),
          ),
          child: child,
        );
      },
    );
  }
}

/// Sheet body layout used by [showAppSheet]: the pill handle, the title row,
/// the (scrollable) body and optional sticky [actions]. The title, body and
/// actions rise in (fade + 12 px, 40 ms apart) when the sheet opens. Usable
/// on its own inside custom sheets.
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.showClose = true,
    this.scrollable = true,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 20, 20),
    this.maxHeightFactor = 0.92,
    this.actions,
    this.showHandle = true,
    this.dismissible = true,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final bool showClose;
  final bool scrollable;
  final EdgeInsetsGeometry padding;
  final double maxHeightFactor;

  /// Sticky actions under the body (primary full width, then secondary /
  /// ghost); they stay visible while the body scrolls, under a soft fade.
  final Widget? actions;
  final bool showHandle;

  /// The handle closes the sheet for screen-reader users when true.
  final bool dismissible;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final mq = MediaQuery.of(context);
    final maxH = mq.size.height * maxHeightFactor;
    final keyboard = mq.viewInsets.bottom > 0;
    // The sheet's own colour (grouped sheets are `bg`): the close button and
    // the fade over the actions are drawn from it.
    final sheet = Material.maybeOf(context)?.color ?? c.surfaceRaised;
    final Widget body = Padding(padding: padding, child: child);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showHandle)
              _DragHandle(dismissible: dismissible)
            else
              const SizedBox(height: 14),
            if (title != null)
              _Rise(
                delay: Duration.zero,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 4, showClose ? 12 : 20, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(top: showClose ? 8 : 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Semantics(
                                header: true,
                                child: Text(title!, style: t.title),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 4),
                                Text(subtitle!, style: t.bodySmall),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (showClose) ...[
                        const SizedBox(width: 8),
                        _SheetClose(sheet: sheet),
                      ],
                    ],
                  ),
                ),
              ),
            Flexible(
              child: _Rise(
                delay: const Duration(milliseconds: 40),
                child: scrollable ? SingleChildScrollView(child: body) : body,
              ),
            ),
            if (actions != null)
              _Rise(
                delay: const Duration(milliseconds: 80),
                child: _StickyActions(
                  sheet: sheet,
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    12 + (keyboard ? 0 : mq.padding.bottom),
                  ),
                  child: actions!,
                ),
              )
            else
              SizedBox(height: keyboard ? 0 : mq.padding.bottom),
          ],
        ),
      ),
    );
  }
}

/// One step of a sheet's entrance: fades in and rises 12 px over 360 ms
/// (emphasized) after [delay]. The widget tree never changes shape, so the
/// content (fields, scroll positions) keeps its state.
class _Rise extends StatefulWidget {
  const _Rise({required this.delay, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<_Rise> createState() => _RiseState();
}

class _RiseState extends State<_Rise> with SingleTickerProviderStateMixin {
  static const Duration _run = Duration(milliseconds: 360);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: _run + widget.delay,
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(
      widget.delay.inMicroseconds / (_run + widget.delay).inMicroseconds,
      1,
      curve: AknMotion.emphasizedCurve,
    ),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    child: widget.child,
    builder: (context, child) {
      final v = _t.value;
      return Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - v)),
          child: child,
        ),
      );
    },
  );
}

/// The round close button of a sheet title: a 36 px well a shade darker
/// than the sheet with a 18 px ✕, a 48 px target, "Kapat".
class _SheetClose extends StatelessWidget {
  const _SheetClose({required this.sheet});

  final Color sheet;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final well = Color.alphaBlend(
      c.ink.withValues(alpha: c.isDark ? 0.08 : 0.06),
      sheet,
    );
    return PressScale(
      scale: 0.9,
      child: IconButton(
        tooltip: 'Kapat',
        onPressed: () => Navigator.of(context).maybePop(),
        style: IconButton.styleFrom(
          backgroundColor: well,
          fixedSize: const Size(36, 36),
          minimumSize: const Size(36, 36),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: const CircleBorder(),
          highlightColor: Colors.transparent,
        ),
        icon: Icon(PhosphorIconsRegular.x, size: 18, color: c.ink),
      ),
    );
  }
}

/// Sticky actions of a sheet: no hairline — the body fades out under a
/// 20 px wash of the sheet colour above them.
class _StickyActions extends StatelessWidget {
  const _StickyActions({
    required this.sheet,
    required this.padding,
    required this.child,
  });

  final Color sheet;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(padding: padding, child: child),
        Positioned(
          top: -20,
          left: 0,
          right: 0,
          height: 20,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [sheet.withValues(alpha: 0), sheet],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 40 × 5 pill handle (`lineStrong` at 50 %) in a 23 px band; a "Kapat"
/// button for screen readers.
class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.dismissible});

  final bool dismissible;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return Semantics(
      button: dismissible,
      label: dismissible ? 'Kapat' : null,
      onTap: dismissible ? () => Navigator.of(context).maybePop() : null,
      child: SizedBox(
        height: 23,
        child: Align(
          alignment: const Alignment(0, 0.15),
          child: Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: c.lineStrong.withValues(alpha: 0.5),
              borderRadius: AknRadius.pillAll,
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for confirmation in a bottom sheet. Returns true only on confirm.
///
/// Destructive actions ([destructive]) get the red confirm button with a
/// white label; the cancel is a ghost "Vazgeç".
Future<bool> showConfirmSheet(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Onayla',
  String cancelLabel = 'Vazgeç',
  bool destructive = false,
  IconData? icon,
  AknTone? tone,
  Widget? content,
}) async {
  final result = await showAppSheet<bool>(
    context: context,
    showClose: false,
    builder: (ctx) => ConfirmSheet(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
      icon: icon,
      tone: tone,
      content: content,
    ),
  );
  return result ?? false;
}

/// Body of [showConfirmSheet]: the icon in its tinted circle, the title,
/// the sentence, optional content, then the confirm button (full width)
/// and a ghost cancel under it.
class ConfirmSheet extends StatelessWidget {
  const ConfirmSheet({
    super.key,
    required this.title,
    this.message,
    this.confirmLabel = 'Onayla',
    this.cancelLabel = 'Vazgeç',
    this.destructive = false,
    this.icon,
    this.tone,
    this.content,
  });

  final String title;
  final String? message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;

  /// Optional icon above the title, in a 56 px circle of its tone's soft
  /// well (it pops in with a single soft ring).
  final IconData? icon;

  /// Colours [icon] and its circle (the confirm button follows
  /// [destructive]); default danger when destructive, else ink.
  final AknTone? tone;
  final Widget? content;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final iconTone = tone ?? (destructive ? AknTone.danger : AknTone.info);
    final glyph = icon;
    final confirm = destructive
        ? DestructiveButton(
            label: confirmLabel,
            onPressed: () => Navigator.of(context).pop(true),
          )
        : AknButton(
            label: confirmLabel,
            expand: true,
            onPressed: () => Navigator.of(context).pop(true),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        if (glyph != null) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: _ToneBadge(icon: glyph, tone: c.tone(iconTone)),
          ),
          const SizedBox(height: 16),
        ],
        Semantics(header: true, child: Text(title, style: t.title)),
        if (message != null) ...[
          const SizedBox(height: 8),
          Text(message!, style: t.body.copyWith(color: c.dim)),
        ],
        if (content != null) ...[const SizedBox(height: 16), content!],
        const SizedBox(height: 24),
        confirm,
        const SizedBox(height: 8),
        AknButton.ghost(
          label: cancelLabel,
          expand: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}

/// A 56 px circle in the tone's soft well (`bg`, 1 px `line`) with the
/// 28 px glyph in the tone's colour. It pops in (0.6 → 1, overshoot) and
/// sends out one soft ring; static under reduce motion.
class _ToneBadge extends StatefulWidget {
  const _ToneBadge({required this.icon, required this.tone});

  final IconData icon;
  final ToneColors tone;

  @override
  State<_ToneBadge> createState() => _ToneBadgeState();
}

class _ToneBadgeState extends State<_ToneBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _started = false;

  static const Interval _pop = Interval(0.1, 0.55);
  static const Interval _ring = Interval(0.3, 1, curve: Curves.easeOutCubic);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tone = widget.tone;
    final circle = DecoratedBox(
      decoration: BoxDecoration(
        color: tone.bg,
        shape: BoxShape.circle,
        border: Border.all(color: tone.line),
      ),
      child: SizedBox.square(
        dimension: 56,
        child: Center(child: Icon(widget.icon, size: 28, color: tone.fg)),
      ),
    );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 56,
        child: AnimatedBuilder(
          animation: _c,
          child: circle,
          builder: (context, child) {
            final v = _c.value;
            final pop = AknMotion.pop.transform(_pop.transform(v));
            final ring = _ring.transform(v);
            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // One soft ring goes out as the circle lands.
                Opacity(
                  opacity: v >= 1 ? 0 : (1 - ring) * 0.5,
                  child: Transform.scale(
                    scale: 1 + 0.45 * ring,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: tone.solid, width: 1.5),
                      ),
                      child: const SizedBox.square(dimension: 56),
                    ),
                  ),
                ),
                Opacity(
                  opacity: _pop.transform(v),
                  child: Transform.scale(scale: 0.6 + 0.4 * pop, child: child),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The destructive confirm of a sheet or dialog ("Teklifi reddet", "Çıkış
/// yap"): the primary button re-dressed in red — a `dangerFill` gradient
/// (a touch lighter at the leading edge) with a white label (5.94:1), the
/// same press, haptic and loading behaviour. Use it only as the confirm
/// button of a sheet or dialog; on pages the danger action is the outlined
/// `AknButton.danger`.
class DestructiveButton extends StatelessWidget {
  const DestructiveButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.akn;
    final red = c.copyWith(
      brandFillStart: Color.lerp(c.dangerFill, Colors.white, 0.14),
      brandFill: c.dangerFill,
      brandFillPressed: Color.lerp(c.dangerFill, Colors.black, 0.12),
      onBrandFill: c.onDangerFill,
    );
    return Theme(
      data: theme.copyWith(
        extensions: [
          for (final e in theme.extensions.values)
            if (e is! AknColors) e,
          red,
        ],
      ),
      child: AknButton(
        label: label,
        icon: icon,
        expand: expand,
        onPressed: onPressed,
      ),
    );
  }
}

/// Centered confirmation dialog for moments that must interrupt — leaving a
/// wizard with unsaved changes, a blocking error. Returns true only on
/// confirm.
///
/// v3: a `surfaceRaised` card with 28 px squircle corners and the raised
/// shadow; the title (`title`), the sentence (dim) and two full buttons —
/// the cancel (secondary) and the confirm (primary, or red when
/// [destructive]) side by side, stacked at large text. It scales in from
/// 0.9 on the spring and fades over [AknMotion.dialog] (out in 160 ms) over
/// the blurred scrim.
Future<bool> showAknDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Tamam',
  String? cancelLabel = 'Vazgeç',
  bool destructive = false,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final result = await navigator.push<bool>(
    _AknDialogRoute<bool>(
      context: context,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierColor: context.akn.scrim,
      reduced: AknMotion.reduced(context),
      builder: (ctx) => _AknDialog(
        title: title,
        message: message,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
      ),
    ),
  );
  return result ?? false;
}

/// The dialog route: scale 0.9 → 1 on the spring + fade in, a quick fade
/// and settle out, the scrim blurring the page (σ 6).
class _AknDialogRoute<T> extends DialogRoute<T> {
  _AknDialogRoute({
    required super.context,
    required super.builder,
    required this.reduced,
    super.themes,
    super.barrierColor,
  }) : super(
         barrierDismissible: true,
         traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
         animationStyle: AnimationStyle(
           duration: reduced ? Duration.zero : AknMotion.dialog,
         ),
       );

  final bool reduced;

  @override
  Duration get reverseTransitionDuration =>
      reduced ? Duration.zero : const Duration(milliseconds: 160);

  @override
  Widget buildModalBarrier() => _BlurredScrim(
    animation: animation,
    enabled: !offstage,
    child: super.buildModalBarrier(),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduced) return child;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final v = animation.value;
        final closing = animation.status == AnimationStatus.reverse;
        final scale = closing
            ? 0.95 + 0.05 * v
            : 0.9 + 0.1 * AknMotion.spring.transform(v);
        final opacity = closing
            ? v
            : const Interval(0, 0.6, curve: Curves.easeOut).transform(v);
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(scale: scale, child: child),
        );
      },
    );
  }
}

class _AknDialog extends StatelessWidget {
  const _AknDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.destructive,
  });

  final String title;
  final String? message;
  final String confirmLabel;
  final String? cancelLabel;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final large = MediaQuery.textScalerOf(context).scale(10) > 13;
    void close(bool value) => Navigator.of(context).pop(value);
    final Widget confirm = destructive
        ? DestructiveButton(label: confirmLabel, onPressed: () => close(true))
        : AknButton(
            label: confirmLabel,
            expand: true,
            onPressed: () => close(true),
          );
    final cancelText = cancelLabel;
    final Widget? cancel = cancelText == null
        ? null
        : AknButton.secondary(
            label: cancelText,
            expand: true,
            onPressed: () => close(false),
          );
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: c.surfaceRaised,
          shape: RoundedSuperellipseBorder(
            borderRadius: AknRadius.dialog,
            side: c.isDark ? BorderSide(color: c.line) : BorderSide.none,
          ),
          shadows: AknShadows.raised(c),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(header: true, child: Text(title, style: t.title)),
                if (message != null) ...[
                  const SizedBox(height: 8),
                  Text(message!, style: t.body.copyWith(color: c.dim)),
                ],
                const SizedBox(height: 24),
                if (cancel == null)
                  confirm
                else if (large) ...[
                  confirm,
                  const SizedBox(height: 10),
                  cancel,
                ] else
                  Row(
                    children: [
                      Expanded(child: cancel),
                      const SizedBox(width: 10),
                      Expanded(child: confirm),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

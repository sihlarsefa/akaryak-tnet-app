import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';

enum AppToastType { success, error, warning, info }

/// Result and error toast (design v3 §4): an inverse card at the top of the
/// screen, under the status bar — the tone icon in a 28 px tinted circle
/// and white text ("Teklif onaylandı. Bayi sevkiyatı planlayacak."). The
/// text repeats the button's verb.
///
/// * 4 s; errors 6 s, with an underlined "Tekrar dene" when [error] gets an
///   `onAction`.
/// * Motion: it drops in from the top on [AknMotion.spring]
///   ([AknMotion.toastIn], a small overshoot), its icon pops; it leaves
///   upward in [AknMotion.toastOut]. A toast with an action (or `onTap`)
///   follows the finger: swipe it up to dismiss, let go to spring back.
///   Reduce motion: it simply appears and goes.
/// * Haptics: success → [AknHaptics.success], error → [AknHaptics.warning].
/// * A new toast replaces the old one; screen readers hear the message.
/// * A toast without an action never blocks taps on what is under it.
///
/// Context-free calls (from interceptors) need [navigatorKey] — set it to
/// the router's root key:
///
/// ```dart
/// AppToast.navigatorKey = rootNavigatorKey;
/// AppToast.error('Bu işlem için yetkiniz yok.');
/// ```
abstract final class AppToast {
  static GlobalKey<NavigatorState>? navigatorKey;
  static OverlayEntry? _entry;

  /// How long a toast stays (errors: [errorDuration]).
  static const Duration defaultDuration = Duration(seconds: 4);
  static const Duration errorDuration = Duration(seconds: 6);

  /// Gap between the toast and the edge it hangs from (the status bar).
  static const double gap = 12;

  /// Shows a toast. [onTap] makes the whole toast an action (a foreground
  /// push banner opening its route); [icon] replaces the tone icon;
  /// [actionLabel] + [onAction] add an underlined action on the right.
  static void show(
    String message, {
    String? title,
    AppToastType type = AppToastType.info,
    Duration? duration,
    BuildContext? context,
    String? actionLabel,
    VoidCallback? onAction,
    VoidCallback? onTap,
    IconData? icon,
  }) {
    final overlay = context != null
        ? Overlay.maybeOf(context, rootOverlay: true)
        : navigatorKey?.currentState?.overlay;
    if (overlay == null) return;
    dismiss();
    switch (type) {
      case AppToastType.success:
        AknHaptics.success();
      case AppToastType.error:
        AknHaptics.warning();
      case AppToastType.warning:
      case AppToastType.info:
        break;
    }
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastView(
        message: message,
        title: title,
        type: type,
        duration:
            duration ??
            (type == AppToastType.error ? errorDuration : defaultDuration),
        actionLabel: actionLabel,
        onAction: onAction,
        onTap: onTap,
        icon: icon,
        onDone: () {
          if (identical(_entry, entry)) dismiss();
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  static void success(String message, {String? title, BuildContext? context}) =>
      show(message, title: title, type: AppToastType.success, context: context);

  /// Error toast (6 s). With [onAction] it carries an underlined action,
  /// "Tekrar dene" unless [actionLabel] says otherwise.
  static void error(
    String message, {
    String? title,
    BuildContext? context,
    String? actionLabel,
    VoidCallback? onAction,
  }) => show(
    message,
    title: title,
    type: AppToastType.error,
    context: context,
    actionLabel: onAction == null ? null : (actionLabel ?? 'Tekrar dene'),
    onAction: onAction,
  );

  static void warning(String message, {String? title, BuildContext? context}) =>
      show(message, title: title, type: AppToastType.warning, context: context);

  static void info(String message, {String? title, BuildContext? context}) =>
      show(message, title: title, type: AppToastType.info, context: context);

  /// Standard 403 answer (spec A.1).
  static void forbidden({BuildContext? context}) =>
      error('Bu işlem için yetkiniz yok.', context: context);

  static void dismiss() {
    final e = _entry;
    _entry = null;
    if (e == null) return;
    e.remove();
    e.dispose();
  }

  /// Whether a toast is on screen (tests).
  static bool get isShowing => _entry != null;

  /// Scaffold slots counted as bars by [barTopUnder].
  static const _barSlots = {'bottomNavigationBar', 'persistentFooter'};

  /// Global y of the top edge of the highest visible bar under [root]
  /// (scaffold bottom bars and [AppToastClearance] boxes), or null. Walks
  /// the render tree the way semantics does, so offstage routes, inactive
  /// tabs and covered pages are skipped. (The v3 toast hangs from the top;
  /// this stays for overlays that sit above the bottom bars.)
  static double? barTopUnder(RenderObject root) {
    double? top;
    void visit(RenderObject o) {
      if (o is RenderBox && o.attached && o.hasSize) {
        final data = o.parentData;
        final id = data is MultiChildLayoutParentData ? data.id : null;
        final bar =
            o is _RenderToastClearance ||
            (id is Enum && _barSlots.contains(id.name));
        if (bar) {
          if (o.size.height > 0) {
            final y = o.localToGlobal(Offset.zero).dy;
            top = top == null ? y : math.min(top!, y);
          }
          return;
        }
      }
      o.visitChildrenForSemantics(visit);
    }

    visit(root);
    return top;
  }
}

/// Marks a bar that bottom overlays must stay above (a custom sticky dock
/// that is not a `Scaffold.bottomNavigationBar`); see
/// [AppToast.barTopUnder]. Scaffold bottom bars are found automatically.
class AppToastClearance extends SingleChildRenderObjectWidget {
  const AppToastClearance({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderToastClearance();
}

class _RenderToastClearance extends RenderProxyBox {}

class _ToastView extends StatefulWidget {
  const _ToastView({
    required this.message,
    required this.title,
    required this.type,
    required this.duration,
    required this.onDone,
    this.actionLabel,
    this.onAction,
    this.onTap,
    this.icon,
  });

  final String message;
  final String? title;
  final AppToastType type;
  final Duration duration;
  final VoidCallback onDone;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Tapping the toast runs this (e.g. open a pushed route), then closes it.
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with TickerProviderStateMixin {
  /// In (spring) and out (exit).
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AknMotion.toastIn,
    reverseDuration: AknMotion.toastOut,
  );

  /// The finger's pull (px, up is negative); springs back to 0.
  late final AnimationController _drag = AnimationController.unbounded(
    vsync: this,
  );
  Timer? _timer;
  bool _closing = false;
  bool _started = false;

  /// The finger's raw travel; down is damped into [_drag].
  double _raw = 0;

  /// How far the toast travels in from above.
  static const double _travel = 56;

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
    _timer = Timer(widget.duration, _close);
    final view = View.maybeOf(context);
    if (view != null) {
      unawaited(
        SemanticsService.sendAnnouncement(view, _spoken, TextDirection.ltr),
      );
    }
  }

  String get _spoken => widget.title == null
      ? widget.message
      : '${widget.title}. ${widget.message}';

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    if (!AknMotion.reduced(context)) await _c.reverse();
    widget.onDone();
  }

  void _onDragStart(DragStartDetails _) {
    if (_closing) return;
    _timer?.cancel();
    _drag.stop();
    _raw = _drag.value;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_closing) return;
    _raw += d.delta.dy;
    // Up follows the finger; down only gives a little (rubber band).
    _drag.value = _raw > 0 ? 16 * (1 - math.exp(-_raw / 48)) : _raw;
  }

  void _onDragEnd(DragEndDetails d) {
    if (_closing) return;
    final v = d.primaryVelocity ?? 0;
    if (_drag.value < -28 || v < -350) {
      unawaited(_close());
      return;
    }
    if (AknMotion.reduced(context)) {
      _drag.value = 0;
    } else {
      unawaited(
        _drag.animateTo(
          0,
          duration: AknMotion.pressOut,
          curve: AknMotion.spring,
        ),
      );
    }
    _timer = Timer(const Duration(seconds: 2), _close);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _drag.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final hasAction = widget.actionLabel != null && widget.onAction != null;
    // Eylemsiz bildirim dokunmayı engellemez: altındaki düğmeler çalışmaya devam eder (ekran okuyucu
    // yine duyurur). Eylemli bildirim (aç, tekrar dene) dokunulabilir kalır ve yukarı kaydırılarak
    // kapatılır.
    final interactive = widget.onTap != null || hasAction;
    final top = math.max(mq.viewPadding.top, mq.padding.top) + AppToast.gap;
    final body = AppToastCard(
      message: widget.message,
      title: widget.title,
      type: widget.type,
      icon: widget.icon,
      actionLabel: widget.actionLabel,
      onAction: widget.onAction == null
          ? null
          : () {
              widget.onAction!();
              unawaited(_close());
            },
    );

    return Positioned(
      left: 16,
      right: 16,
      top: top,
      child: AnimatedBuilder(
        animation: Listenable.merge([_c, _drag]),
        builder: (context, child) {
          final v = _c.value;
          final leaving = _c.status == AnimationStatus.reverse;
          // In: the spring's overshoot carries it a hair past its place.
          // Out: it accelerates away upward.
          final p = leaving
              ? 1 - AknMotion.exit.transform(1 - v)
              : AknMotion.spring.transform(v);
          final opacity = leaving
              ? v
              : const Interval(0, 0.45, curve: Curves.easeOut).transform(v);
          final pull = _drag.value;
          return Opacity(
            opacity: (opacity * (pull < 0 ? 1 + pull / 160 : 1)).clamp(
              0.0,
              1.0,
            ),
            child: Transform.translate(
              offset: Offset(0, -_travel * (1 - p) + pull),
              child: Transform.scale(
                scale: 0.94 + 0.06 * p,
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
          );
        },
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: IgnorePointer(
              ignoring: !interactive,
              child: GestureDetector(
                onTap: () {
                  widget.onTap?.call();
                  unawaited(_close());
                },
                onVerticalDragStart: _onDragStart,
                onVerticalDragUpdate: _onDragUpdate,
                onVerticalDragEnd: _onDragEnd,
                child: Semantics(
                  container: true,
                  button: widget.onTap != null,
                  label: _spoken,
                  excludeSemantics: !hasAction,
                  child: body,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The toast itself (v3 §4), without the overlay and the motion: an inverse
/// card (`inverse` #1B1D21; dark #2C2F35), radius 18, the raised shadow,
/// padding 12/14; the tone icon (filled, 18 px) in a 28 px circle of its
/// tone (night palette: mint, coral, amber, white) that pops in; white
/// 15/20 500 text (an optional 700 title line) and an optional underlined
/// white action at the end (under the message at large text). [AppToast]
/// shows it; the gallery prints it as is.
class AppToastCard extends StatelessWidget {
  const AppToastCard({
    super.key,
    required this.message,
    this.title,
    this.type = AppToastType.info,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? title;
  final AppToastType type;

  /// Replaces the tone icon.
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    // The toast is dark in both themes: tone icons use the night palette.
    const night = AknColors.dark;
    final (IconData toneIcon, Color tone) = switch (type) {
      AppToastType.success => (PhosphorIconsFill.checkCircle, night.ok.solid),
      AppToastType.error => (
        PhosphorIconsFill.warningCircle,
        night.danger.solid,
      ),
      AppToastType.warning => (PhosphorIconsFill.warning, night.warn.solid),
      AppToastType.info => (PhosphorIconsFill.info, c.onInverse),
    };
    final head = title;
    final hasAction = actionLabel != null && onAction != null;
    // Large text (≥ 1.3×): the action moves under the message, so the
    // sentence keeps the card's width instead of breaking letter by letter.
    final stacked =
        hasAction && MediaQuery.textScalerOf(context).scale(10) > 13;
    final text = t.body.copyWith(
      height: 20 / 15,
      fontWeight: FontWeight.w500,
      color: c.onInverse,
    );
    final strong = text.copyWith(fontWeight: FontWeight.w700);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.inverse,
        borderRadius: const BorderRadius.all(Radius.circular(18)),
        boxShadow: AknShadows.raised(c),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: hasAction && !stacked ? 0 : 16,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _ToneIcon(icon: icon ?? toneIcon, color: tone),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 12, bottom: stacked ? 0 : 12),
                child: ConstrainedBox(
                  // One line of text centres on the 28 px icon.
                  constraints: const BoxConstraints(minHeight: 28),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    widthFactor: 1,
                    child: Material(
                      type: MaterialType.transparency,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (head != null) Text(head, style: strong),
                          Text(message, style: text),
                          if (stacked)
                            _ToastAction(
                              label: actionLabel!,
                              style: strong,
                              onPressed: onAction!,
                              padding: const EdgeInsetsDirectional.fromSTEB(
                                0,
                                8,
                                16,
                                10,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (hasAction && !stacked)
              _ToastAction(
                label: actionLabel!,
                style: strong,
                onPressed: onAction!,
              ),
          ],
        ),
      ),
    );
  }
}

/// The toast's tone mark: a 28 px circle of [color] at 18 % with a 1 px
/// ring at 30 % and the 18 px glyph in [color]; it pops in once (0.5 → 1 on
/// [AknMotion.pop]) when the toast appears.
class _ToneIcon extends StatefulWidget {
  const _ToneIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  State<_ToneIcon> createState() => _ToneIconState();
}

class _ToneIconState extends State<_ToneIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
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
  Widget build(BuildContext context) {
    final color = widget.color;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: 28,
        child: AnimatedBuilder(
          animation: _c,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.18),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Center(child: Icon(widget.icon, size: 18, color: color)),
          ),
          builder: (context, child) {
            final v = const Interval(0.15, 1).transform(_c.value);
            final s = 0.5 + 0.5 * AknMotion.pop.transform(v);
            return Transform.scale(scale: s, child: child);
          },
        ),
      ),
    );
  }
}

/// Underlined white action on the toast ("Tekrar dene", "Aç"): at the end
/// of the card, or under the message at large text; a 48 px target either
/// way.
class _ToastAction extends StatelessWidget {
  const _ToastAction({
    required this.label,
    required this.style,
    required this.onPressed,
    this.padding = const EdgeInsets.fromLTRB(12, 14, 16, 12),
  });

  final String label;
  final TextStyle style;
  final VoidCallback onPressed;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Padding(
            padding: padding,
            child: Text(
              label,
              style: style.copyWith(
                decoration: TextDecoration.underline,
                decorationColor: style.color,
                decorationThickness: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

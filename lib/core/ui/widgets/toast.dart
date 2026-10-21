import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';

enum AppToastType { success, error, warning, info }

/// Result and error toast (design v2 §6.22): an inverse (Asfalt) bar with a
/// filled tone icon and white text, 12 px above the bottom bar or the sticky
/// action dock ("Teklif onaylandı. Bayi sevkiyatı planlayacak."). The text
/// repeats the button's verb.
///
/// * 4 s; errors 6 s, with an underlined "Tekrar dene" when [error] gets an
///   `onAction`.
/// * Slides up and fades in (200 ms), out in 150 ms; reduce motion: no
///   slide. Swipe down or tap (when [show] has `onTap`) to close.
/// * A new toast replaces the old one; screen readers hear the message.
/// * A toast without an action never blocks taps on what is under it.
///
/// It finds the bar it must clear on its own: every visible
/// `Scaffold.bottomNavigationBar` (the shell's bottom bar, `AppScaffold`'s
/// action bar) and every [AppToastClearance]. Context-free calls (from
/// interceptors) need [navigatorKey] — set it to the router's root key:
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

  /// Gap between the toast and the bar (or the screen edge) under it.
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
    if (type == AppToastType.error) AknHaptics.warning();
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

  /// Scaffold slots a toast keeps clear of.
  static const _barSlots = {'bottomNavigationBar', 'persistentFooter'};

  /// Global y of the top edge of the highest visible bar under [root]
  /// (scaffold bottom bars and [AppToastClearance] boxes), or null. Walks
  /// the render tree the way semantics does, so offstage routes, inactive
  /// tabs and covered pages are skipped.
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

/// Marks a bar a toast must stay above (a custom sticky dock that is not a
/// `Scaffold.bottomNavigationBar`). Scaffold bottom bars are found
/// automatically.
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

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AknMotion.toastIn,
    reverseDuration: AknMotion.toastOut,
  );
  late final CurvedAnimation _t = CurvedAnimation(
    parent: _c,
    curve: AknMotion.standard,
    reverseCurve: AknMotion.exit,
  );
  Timer? _timer;
  bool _closing = false;
  bool _started = false;

  /// Global top of the bar under the toast (re-read after the first frame,
  /// when a page pushed together with the toast has been laid out).
  double? _barTop;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _barTop = _readBarTop();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
    _timer = Timer(widget.duration, _close);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final top = _readBarTop();
      if (top != _barTop) setState(() => _barTop = top);
    });
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

  double? _readBarTop() {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final root = overlay?.context.findRenderObject();
    if (root == null) return null;
    try {
      return AppToast.barTopUnder(root);
    } on Object {
      return null;
    }
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    if (!AknMotion.reduced(context)) await _c.reverse();
    widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _t.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final hasAction = widget.actionLabel != null && widget.onAction != null;
    // Eylemsiz bildirim dokunmayı engellemez: altındaki çubuk düğmeleri çalışmaya devam eder
    // (ekran okuyucu yine duyurur). Eylemli bildirim (aç, tekrar dene) dokunulabilir kalır.
    final interactive = widget.onTap != null || hasAction;
    final barTop = _barTop;
    final aboveBar = barTop == null
        ? 0.0
        : math.max(0.0, mq.size.height - barTop);
    final bottom =
        math.max(
          aboveBar,
          math.max(mq.viewInsets.bottom, mq.viewPadding.bottom),
        ) +
        AppToast.gap;
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
      left: AknSpace.page,
      right: AknSpace.page,
      bottom: bottom,
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, child) => Opacity(
          opacity: _t.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - _t.value)),
            child: child,
          ),
        ),
        child: Align(
          alignment: Alignment.bottomCenter,
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
                onVerticalDragEnd: (d) {
                  if ((d.primaryVelocity ?? 0) > 0) unawaited(_close());
                },
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

/// The toast itself (§6.22), without the overlay and the motion: an inverse
/// bar (`#1E2227`; dark `#3A3F46`), r12, padding 12/14, a filled 20 px tone
/// icon (ok `#5CC98A`, error `#FF7A70`, warn `#F5B83D`, info white), white
/// 15/20 500 text (an optional 600 title line) and an optional underlined
/// white action. [AppToast] shows it; the gallery prints it as is.
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
    final (IconData toneIcon, Color iconColor) = switch (type) {
      AppToastType.success => (Icons.check_circle_rounded, night.ok.fg),
      AppToastType.error => (Icons.error_rounded, night.danger.fg),
      AppToastType.warning => (Icons.warning_rounded, night.warn.fg),
      AppToastType.info => (Icons.info_rounded, c.onInverse),
    };
    final head = title;
    final hasAction = actionLabel != null && onAction != null;
    final text = t.body.copyWith(
      height: 20 / 15,
      fontWeight: FontWeight.w500,
      color: c.onInverse,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.inverse,
        borderRadius: AknRadius.card,
        boxShadow: AknShadows.raised(c),
      ),
      child: Padding(
        padding: EdgeInsets.only(left: 14, right: hasAction ? 0 : 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Icon(icon ?? toneIcon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (head != null)
                        Text(
                          head,
                          style: text.copyWith(fontWeight: FontWeight.w600),
                        ),
                      Text(message, style: text),
                    ],
                  ),
                ),
              ),
            ),
            if (hasAction)
              _ToastAction(
                label: actionLabel!,
                style: text.copyWith(fontWeight: FontWeight.w600),
                onPressed: onAction!,
              ),
          ],
        ),
      ),
    );
  }
}

/// Underlined white action on the toast ("Tekrar dene", "Aç").
class _ToastAction extends StatelessWidget {
  const _ToastAction({
    required this.label,
    required this.style,
    required this.onPressed,
  });

  final String label;
  final TextStyle style;
  final VoidCallback onPressed;

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
          constraints: const BoxConstraints(minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
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

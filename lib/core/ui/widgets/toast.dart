import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../motion.dart';
import '../status.dart';
import '../theme.dart';
import '../tokens.dart';

enum AppToastType { success, error, warning, info }

/// Top toast for results and errors ("Teklif gönderildi", "Bu işlem için
/// yetkiniz yok."). Slides down, dismisses itself, closes on tap or swipe
/// up; a new toast replaces the old one. Screen readers hear the message.
///
/// Ported from F2GO's `AppToast`, recoloured. Context-free calls (from
/// interceptors) need [navigatorKey] — set it to the router's root key:
///
/// ```dart
/// AppToast.navigatorKey = rootNavigatorKey;
/// AppToast.error('Bu işlem için yetkiniz yok.');
/// ```
abstract final class AppToast {
  static GlobalKey<NavigatorState>? navigatorKey;
  static OverlayEntry? _entry;

  /// Shows a toast. [onTap] makes the whole toast an action (a foreground
  /// push banner opening its route); [icon] replaces the tone icon.
  static void show(
    String message, {
    String? title,
    AppToastType type = AppToastType.info,
    Duration duration = const Duration(milliseconds: 3200),
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
        duration: duration,
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

  static void error(String message, {String? title, BuildContext? context}) =>
      show(
        message,
        title: title,
        type: AppToastType.error,
        context: context,
        duration: const Duration(milliseconds: 4200),
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
}

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
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 200),
  );
  late final CurvedAnimation _t = CurvedAnimation(
    parent: _c,
    curve: AknMotion.emphasizedCurve,
    reverseCurve: AknMotion.exit,
  );
  Timer? _timer;
  bool _closing = false;
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
    _timer = Timer(widget.duration, _close);
    final view = View.maybeOf(context);
    if (view != null) {
      final text = widget.title == null
          ? widget.message
          : '${widget.title}. ${widget.message}';
      unawaited(
        SemanticsService.sendAnnouncement(view, text, TextDirection.ltr),
      );
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
    final c = context.akn;
    final t = context.aknText;
    final tone = switch (widget.type) {
      AppToastType.success => AknTone.ok,
      AppToastType.error => AknTone.danger,
      AppToastType.warning => AknTone.warn,
      AppToastType.info => AknTone.info,
    };
    final tc = c.tone(tone);
    final title = widget.title;
    // Eylemsiz bildirim dokunmayı engellemez: altındaki uygulama çubuğu düğmeleri çalışmaya devam
    // eder (ekran okuyucu yine duyurur). Eylemli bildirim (aç, geri al) dokunulabilir kalır.
    final interactive =
        widget.onTap != null ||
        (widget.actionLabel != null && widget.onAction != null);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: _t,
          builder: (context, child) => Opacity(
            opacity: _t.value.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, -24 * (1 - _t.value)),
              child: child,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: IgnorePointer(
                  ignoring: !interactive,
                  child: GestureDetector(
                    onTap: () {
                      widget.onTap?.call();
                      unawaited(_close());
                    },
                    onVerticalDragEnd: (d) {
                      if ((d.primaryVelocity ?? 0) < 0) unawaited(_close());
                    },
                    child: Semantics(
                      container: true,
                      button: widget.onTap != null,
                      label: title == null
                          ? widget.message
                          : '$title. ${widget.message}',
                      excludeSemantics: widget.actionLabel == null,
                      child: Container(
                        decoration: BoxDecoration(
                          color: c.surfaceRaised,
                          borderRadius: BorderRadius.circular(AknRadius.md + 2),
                          border: Border.all(
                            color: c.isDark ? c.line : c.lineSoft,
                          ),
                          boxShadow: AknShadows.raised(c),
                        ),
                        padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: tc.bg,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                widget.icon ?? AknStatus.toneIcon(tone),
                                size: 19,
                                color: tc.fg,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Material(
                                type: MaterialType.transparency,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (title != null)
                                      Text(title, style: t.bodyStrong),
                                    Text(
                                      widget.message,
                                      style: title == null
                                          ? t.bodyStrong.copyWith(
                                              fontWeight: FontWeight.w500,
                                            )
                                          : t.bodySmall.copyWith(fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (widget.actionLabel != null &&
                                widget.onAction != null)
                              Material(
                                type: MaterialType.transparency,
                                child: TextButton(
                                  onPressed: () {
                                    widget.onAction!();
                                    unawaited(_close());
                                  },
                                  child: Text(widget.actionLabel!),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
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

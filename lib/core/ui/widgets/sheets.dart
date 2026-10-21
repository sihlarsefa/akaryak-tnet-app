import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';
import 'buttons.dart';

/// Opens a bottom sheet in the v2 style (§6.21): a raised surface with a
/// 20 px top radius, a 36 × 4 drag handle, 20 px padding, an optional title
/// (`title` 20/26) with a close button, the body, and optional sticky
/// [actionsBuilder] actions at the bottom (primary full width first, then
/// secondary / ghost). Keyboard-aware; slides up in 250 ms over the scrim.
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
}) {
  final reduced = AknMotion.reduced(context);
  final c = context.akn;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: false,
    backgroundColor: c.surfaceRaised,
    elevation: 0,
    barrierColor: c.scrim,
    shape: const RoundedRectangleBorder(borderRadius: AknRadius.sheet),
    clipBehavior: Clip.antiAlias,
    sheetAnimationStyle: reduced
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: AknMotion.sheet,
            reverseDuration: AknMotion.scrim,
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
      actions: actionsBuilder == null ? null : Builder(builder: actionsBuilder),
      child: Builder(builder: builder),
    ),
  );
}

/// Sheet body layout used by [showAppSheet]: drag handle, title row, the
/// (scrollable) body and optional sticky [actions]. Usable on its own inside
/// custom sheets.
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
  /// ghost); they stay visible while the body scrolls.
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
              const SizedBox(height: 12),
            if (title != null)
              Padding(
                padding: EdgeInsets.fromLTRB(20, 2, showClose ? 8 : 20, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(top: showClose ? 11 : 0),
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
                    if (showClose)
                      IconButton(
                        tooltip: 'Kapat',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: Icon(Icons.close_rounded, size: 24, color: c.ink),
                      ),
                  ],
                ),
              ),
            Flexible(
              child: scrollable ? SingleChildScrollView(child: body) : body,
            ),
            if (actions != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.line)),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    12,
                    20,
                    12 + (keyboard ? 0 : mq.padding.bottom),
                  ),
                  child: actions,
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

/// 36 × 4 handle (control-border colour) in a 24 px band; a "Kapat" button
/// for screen readers.
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
        height: 24,
        child: Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: c.lineStrong,
              borderRadius: const BorderRadius.all(Radius.circular(2)),
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

/// Body of [showConfirmSheet]: title, sentence, optional content, then the
/// confirm button (full width) and a ghost cancel under it.
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

  /// Optional plain icon above the title (never in a tinted circle).
  final IconData? icon;

  /// Colours [icon] (the confirm button follows [destructive]).
  final AknTone? tone;
  final Widget? content;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final iconTone = tone ?? (destructive ? AknTone.danger : AknTone.info);
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
        if (icon != null) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Icon(
              icon,
              size: 28,
              color: iconTone == AknTone.brand ? c.ink : c.tone(iconTone).fg,
            ),
          ),
          const SizedBox(height: 12),
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

/// The destructive confirm of a sheet ("Teklifi reddet", "Çıkış yap"):
/// `dangerFill` with a white label (§6.5), full width. Use it only as the
/// confirm button of a sheet or dialog; on pages the danger action is the
/// outlined `AknButton.danger`.
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
      brandFill: c.dangerFill,
      brandFillPressed: Color.lerp(c.dangerFill, Colors.black, 0.08),
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

/// Centered confirmation dialog (r20) for moments that must interrupt —
/// leaving a wizard with unsaved changes, a blocking error. Returns true
/// only on confirm.
Future<bool> showAknDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Tamam',
  String? cancelLabel = 'Vazgeç',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: context.akn.scrim,
    builder: (ctx) {
      final c = ctx.akn;
      final t = ctx.aknText;
      return AlertDialog(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: AknRadius.dialog),
        title: Text(title, style: t.title),
        content: message == null
            ? null
            : Text(message, style: t.body.copyWith(color: c.dim)),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          if (cancelLabel != null)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: TextButton.styleFrom(foregroundColor: c.ink),
              child: Text(cancelLabel),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: destructive ? c.danger.fg : c.ink,
            ),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

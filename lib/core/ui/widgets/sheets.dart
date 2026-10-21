import 'package:flutter/material.dart';

import '../motion.dart';
import '../status.dart';
import '../theme.dart';
import '../tokens.dart';
import 'buttons.dart';

/// Opens a bottom sheet in the AkaryakıtNet style: 16 px top radius, drag
/// handle, optional title row with a close button, keyboard-aware padding.
/// Slides up (320 ms emphasized) over a fading scrim.
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
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  double maxHeightFactor = 0.92,
}) {
  final reduced = AknMotion.reduced(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: true,
    sheetAnimationStyle: reduced
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: Duration(milliseconds: 320),
            reverseDuration: Duration(milliseconds: 220),
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
      child: Builder(builder: builder),
    ),
  );
}

/// Sheet body layout used by [showAppSheet]. Usable on its own inside custom
/// sheets.
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.showClose = true,
    this.scrollable = true,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
    this.maxHeightFactor = 0.92,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final bool showClose;
  final bool scrollable;
  final EdgeInsetsGeometry padding;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final mq = MediaQuery.of(context);
    final maxH = mq.size.height * maxHeightFactor;
    final Widget body = Padding(padding: padding, child: child);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 4, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              child: Text(title!, style: t.headline),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 2),
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
                        icon: const Icon(Icons.close_rounded),
                      ),
                  ],
                ),
              ),
            Flexible(
              child: scrollable ? SingleChildScrollView(child: body) : body,
            ),
            SizedBox(height: mq.viewInsets.bottom > 0 ? 0 : mq.padding.bottom),
          ],
        ),
      ),
    );
  }
}

/// Asks for confirmation in a bottom sheet. Returns true only on confirm.
///
/// Destructive actions use the danger button and tone.
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

/// Body of [showConfirmSheet].
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
  final IconData? icon;
  final AknTone? tone;
  final Widget? content;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final effectiveTone =
        tone ?? (destructive ? AknTone.danger : AknTone.brand);
    final tc = c.tone(effectiveTone);
    final stacked = MediaQuery.textScalerOf(context).scale(15) > 20;
    final cancel = AknButton.secondary(
      label: cancelLabel,
      expand: true,
      onPressed: () => Navigator.of(context).pop(false),
    );
    final confirm = destructive
        ? AknButton.danger(
            label: confirmLabel,
            expand: true,
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
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: tc.bg, shape: BoxShape.circle),
            child: Icon(
              icon ?? AknStatus.toneIcon(effectiveTone),
              color: tc.fg,
              size: 28,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(title, style: t.headline, textAlign: TextAlign.center),
        ),
        if (message != null) ...[
          const SizedBox(height: 8),
          Text(message!, style: t.body, textAlign: TextAlign.center),
        ],
        if (content != null) ...[const SizedBox(height: 16), content!],
        const SizedBox(height: 24),
        if (stacked) ...[
          confirm,
          const SizedBox(height: 4),
          cancel,
        ] else
          Row(
            children: [
              Expanded(child: cancel),
              const SizedBox(width: 12),
              Expanded(child: confirm),
            ],
          ),
      ],
    );
  }
}

/// Centered confirmation dialog (for moments that must interrupt, e.g.
/// leaving a wizard with unsaved changes). Returns true only on confirm.
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
    builder: (ctx) {
      final c = ctx.akn;
      return AlertDialog(
        title: Text(title),
        content: message == null ? null : Text(message),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          if (cancelLabel != null)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: TextButton.styleFrom(foregroundColor: c.text),
              child: Text(cancelLabel),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: destructive
                ? TextButton.styleFrom(foregroundColor: c.danger.fg)
                : null,
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

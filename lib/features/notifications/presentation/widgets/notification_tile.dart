import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../copy.dart';
import '../../data/notification_models.dart';

/// Gelen kutusu satırı: kategori ikonu (önem tonunda), başlık (okunmamışsa kalın), metin, göreli
/// zaman ve okunmamış noktası. Okunmamış satır sağa kaydırınca okundu olur (satır yerinde kalır);
/// ekran okuyucuda "Okundu işaretle" özel eylemi vardır.
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    required this.onTap,
    required this.onMarkRead,
    this.now,
  });

  final UserNotification notification;
  final VoidCallback onTap;
  final VoidCallback onMarkRead;

  /// Göreli zaman için (testler).
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final n = notification;
    final unread = !n.isRead;
    final when = Fmt.relative(n.createdAt, now: now);
    final tc = c.tone(n.tone);
    final semantics = [
      if (unread) NotificationsCopy.unreadPrefix,
      n.title,
      if (n.body.isNotEmpty) n.body,
      n.label,
      when,
    ].join('. ');

    final Widget row = Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tc.bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tc.line),
            ),
            alignment: Alignment.center,
            child: Icon(
              NotificationCategory.icon(n.category),
              size: 20,
              color: tc.fg,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  n.title,
                  style: unread
                      ? t.bodyStrong.copyWith(color: c.ink)
                      : t.body.copyWith(
                          color: c.text,
                          fontWeight: FontWeight.w500,
                        ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (n.body.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    n.body,
                    style: t.bodySmall.copyWith(color: c.text),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  '${n.label} · $when',
                  style: t.caption.copyWith(color: c.dim),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: AnimatedScale(
              scale: unread ? 1 : 0,
              duration: AknMotion.of(context, AknMotion.base),
              curve: AknMotion.emphasizedCurve,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: c.brandFill,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final Widget tappable = Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      onTap: onTap,
      customSemanticsActions: unread
          ? {
              const CustomSemanticsAction(label: NotificationsCopy.markRead):
                  onMarkRead,
            }
          : null,
      child: Material(
        color: unread ? c.surface : c.bg,
        child: InkWell(onTap: onTap, child: row),
      ),
    );

    if (!unread) return tappable;
    return Dismissible(
      key: ValueKey('notification-${n.id}'),
      direction: DismissDirection.startToEnd,
      dismissThresholds: const {DismissDirection.startToEnd: 0.3},
      confirmDismiss: (_) async {
        AknHaptics.selection();
        onMarkRead();
        return false;
      },
      background: _SwipeBackground(),
      child: tappable,
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Container(
      color: c.ok.bg,
      alignment: AlignmentDirectional.centerStart,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mark_email_read_rounded, color: c.ok.fg, size: 22),
          const SizedBox(width: 8),
          Text(
            NotificationsCopy.markedRead,
            style: t.label.copyWith(color: c.ok.fg),
          ),
        ],
      ),
    );
  }
}

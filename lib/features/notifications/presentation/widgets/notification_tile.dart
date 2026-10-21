import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../copy.dart';
import '../../data/notification_models.dart';

/// Gelen kutusu satırı (tasarım v2 §6.8, §7.17): tam genişlikte defter satırı — okunmamışsa başlıktan
/// önce 8 px turuncu nokta ve 600 başlık; sağda saat, altında metin ve kategori (uyarı / tehlike
/// bildirimlerinde lamba). Renkli ikon kutusu yok. Okunmamış satır sağa kaydırınca okundu olur (satır
/// yerinde kalır); ekran okuyucuda "Okundu işaretle" özel eylemi vardır.
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
    final semantics = [
      if (unread) NotificationsCopy.unreadPrefix,
      n.title,
      if (n.body.isNotEmpty) n.body,
      n.label,
      when,
    ].join('. ');
    final titleStyle = t.headline.copyWith(
      fontSize: 16,
      height: 22 / 16,
      color: c.ink,
      fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
    );
    final statusTone = n.tone == AknTone.danger || n.tone == AknTone.warn;
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final time = Text(when, style: t.bodySmall.copyWith(color: c.dim));

    final Widget row = Padding(
      // Nokta sol boşlukta asılı durur; başlık 20 px kenarda (ince çizgilerle aynı hizada).
      padding: const EdgeInsets.fromLTRB(6, 12, AknSpace.page, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Okunmamış: başlığın ilk satırının ortasında 8 px logo turuncusu nokta.
          SizedBox(
            width: 8,
            height: MediaQuery.textScalerOf(context).scale(22),
            child: Center(
              child: AnimatedScale(
                scale: unread ? 1 : 0,
                duration: AknMotion.of(context, AknMotion.base),
                curve: AknMotion.emphasizedCurve,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: c.logo,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (large) ...[
                  Text(n.title, style: titleStyle),
                  time,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          n.title,
                          style: titleStyle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: time,
                      ),
                    ],
                  ),
                if (n.body.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    n.body,
                    style: t.bodySmall.copyWith(color: c.text),
                    maxLines: large ? 8 : 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 6),
                if (statusTone)
                  AknLamp(label: n.label, tone: n.tone, size: AknLampSize.small)
                else
                  Text(n.label, style: t.caption.copyWith(color: c.dim)),
              ],
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
        color: c.bg,
        child: InkWell(
          onTap: onTap,
          splashFactory: NoSplash.splashFactory,
          highlightColor: c.surfaceAlt,
          child: row,
        ),
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
          Icon(Icons.mark_email_read_outlined, color: c.ok.fg, size: 22),
          const SizedBox(width: 8),
          Text(
            NotificationsCopy.markedRead,
            style: t.label.copyWith(color: c.ink),
          ),
        ],
      ),
    );
  }
}

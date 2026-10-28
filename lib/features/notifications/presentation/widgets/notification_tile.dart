import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../copy.dart';
import '../../data/notification_models.dart';

/// Gelen kutusu satırı (tasarım v3): sayfanın üstünde yüzen beyaz kart (r20, kart gölgesi). Solda 40 px
/// kategori karosu, başlık ve sağda saat (eş genişlikte rakamlar), altında metin ve kategori (uyarı /
/// tehlike bildirimlerinde lamba). Okunmamış kartın zemininde çok hafif sıcak bir ışık, karosu turuncu ve
/// başlık kalındır; sağ üstte turuncu nokta yavaşça nefes alır. Okundu olunca hepsi yumuşakça sakinleşir
/// (ışık söner, karo griye döner, nokta küçülerek kaybolur). Okunmamış kart sağa kaydırınca okundu olur
/// (kart yerinde kalır); ekran okuyucuda "Okundu işaretle" özel eylemi vardır. Basınca kart hafifçe içe
/// çöker.
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    required this.onTap,
    required this.onMarkRead,
    this.now,
    this.revealIndex,
  });

  final UserNotification notification;
  final VoidCallback onTap;
  final VoidCallback onMarkRead;

  /// Göreli zaman için (testler).
  final DateTime? now;

  /// Sıralı giriş (tasarım v3 §5): verilirse kart en yakın [StaggerScope]'a göre bu sırayla (ve
  /// kaydırınca) kayarak gelir. Kaydırma hareketi girişin dışında kalır: giriş sürerken de kart
  /// sağa kaydırılabilir.
  final int? revealIndex;

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
    final duration = AknMotion.of(context, AknMotion.slow);
    final titleStyle = t.bodyStrong.copyWith(
      fontSize: 16,
      height: 22 / 16,
      color: c.ink,
      fontWeight: unread ? FontWeight.w700 : FontWeight.w600,
    );
    final statusTone = n.tone == AknTone.danger || n.tone == AknTone.warn;
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final time = Text(
      when,
      style: t.caption.copyWith(
        color: unread ? c.brandInk : c.dim,
        fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
        fontFeatures: AknNumerals.tabular,
      ),
    );
    final radius = AknRadius.card;
    final warm = Color.lerp(c.surface, c.brandSoft, c.isDark ? 0.55 : 0.5)!;

    final Widget content = Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CategoryTile(
            icon: NotificationCategory.icon(n.category),
            tone: statusTone ? n.tone : null,
            unread: unread,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (large) ...[
                  AnimatedPadding(
                    duration: duration,
                    curve: AknMotion.emphasizedCurve,
                    padding: EdgeInsetsDirectional.only(end: unread ? 18 : 0),
                    child: AnimatedDefaultTextStyle(
                      duration: duration,
                      style: titleStyle,
                      child: Text(n.title),
                    ),
                  ),
                  const SizedBox(height: 2),
                  time,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AnimatedDefaultTextStyle(
                          duration: duration,
                          style: titleStyle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          child: Text(n.title),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: time,
                      ),
                      // Okunmamış noktasının yeri (saatle çakışmaz).
                      AnimatedContainer(
                        duration: duration,
                        curve: AknMotion.emphasizedCurve,
                        width: unread ? 16 : 0,
                      ),
                    ],
                  ),
                if (n.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    n.body,
                    style: t.bodySmall.copyWith(color: c.text),
                    maxLines: large ? 8 : 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
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

    final Widget card = AnimatedContainer(
      duration: duration,
      curve: AknMotion.standard,
      decoration: BoxDecoration(
        color: unread ? warm : c.surface,
        borderRadius: radius,
        border: c.isDark
            ? Border.all(color: unread ? c.brandLine : c.line)
            : null,
        boxShadow: AknShadows.card(c),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          splashFactory: NoSplash.splashFactory,
          highlightColor: c.surfaceAlt.withValues(alpha: 0.8),
          child: Stack(
            children: [
              content,
              // Okunmamış: sağ üstte nefes alan turuncu nokta.
              PositionedDirectional(
                top: 18,
                end: 14,
                child: _UnreadDot(visible: unread),
              ),
            ],
          ),
        ),
      ),
    );

    final index = revealIndex;
    final Widget pressable = PressScale(child: card);
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
      child: index == null
          ? pressable
          : StaggerItem(index: index, child: pressable),
    );

    // Okunmuş kartta kaydırma kapalı; yapı aynı kalır, böylece okundu geçişi yumuşak oynar.
    return Dismissible(
      key: ValueKey('notification-${n.id}'),
      direction: unread ? DismissDirection.startToEnd : DismissDirection.none,
      dismissThresholds: const {DismissDirection.startToEnd: 0.3},
      confirmDismiss: (_) async {
        AknHaptics.selection();
        onMarkRead();
        return false;
      },
      background: ClipRRect(borderRadius: radius, child: _SwipeBackground()),
      child: tappable,
    );
  }
}

/// Kategori karosu: 40 px, r12. Okunmamışta yumuşak turuncu zemin ve turuncu simge, okunmuşta kuyu ve
/// soluk simge; uyarı / tehlike bildiriminde tonun kuyusu. Renk değişimi yumuşak.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.icon,
    required this.tone,
    required this.unread,
  });

  final IconData icon;
  final AknTone? tone;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final tc = tone == null ? null : c.tone(tone!);
    final bg = tc?.bg ?? (unread ? c.brandSoft : c.surfaceAlt);
    final fg = tc?.fg ?? (unread ? c.brandInk : c.dim);
    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: AknMotion.of(context, AknMotion.slow),
        curve: AknMotion.standard,
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AknRadius.buttonSmall,
        ),
        alignment: Alignment.center,
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: fg),
          duration: AknMotion.of(context, AknMotion.slow),
          builder: (context, color, _) => Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}

/// Okunmamış noktası: 8 px logo turuncusu; çevresinde yumuşak bir hale nefes alır
/// ([AknMotion.breathe]). Okundu olunca küçülerek kaybolur.
class _UnreadDot extends StatelessWidget {
  const _UnreadDot({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return ExcludeSemantics(
      child: AnimatedScale(
        scale: visible ? 1 : 0,
        duration: AknMotion.of(context, AknMotion.slow),
        curve: visible ? AknMotion.pop : AknMotion.exit,
        child: SizedBox.square(
          dimension: 16,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Hale: yalnızca ölçek ve opaklık değişir (yeniden yerleşim yok).
              AknAmbient(
                period: AknMotion.breathe,
                reverse: true,
                builder: (context, t, child) => Opacity(
                  opacity: 0.85 - 0.6 * t,
                  child: Transform.scale(scale: 0.5 + 0.5 * t, child: child),
                ),
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.brand.withValues(alpha: 0.3),
                  ),
                ),
              ),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: c.logo,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      ),
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
          Icon(
            PhosphorIconsRegular.envelopeSimpleOpen,
            color: c.ok.fg,
            size: 22,
          ),
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

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/announcements.dart';
import '../../application/notification_display.dart';
import '../../copy.dart';
import '../../data/notification_models.dart';

/// Gelen kutusu satırı (tasarım v4 §5 10): günün defterinde ([AknLedger]) bir satır — kart değil,
/// satırlar arasında ince çizgi.
///
/// * Solda 36 dp nötr karo (yalnızca uyarı / tehlike bildiriminde tonlu), olayın simgesi.
/// * Başlık 15/20 (okunmamış 700, okunmuş 500), sağda saat 13/18 soluk (eş genişlikte rakamlar).
/// * Altında metin 14/20 soluk, en çok 2 satır; iç kodlar gösterilmez ([NotificationDisplay.clean]).
/// * Sıra görüntüleyendeyse tek eylem satırı: "Talebi incele ›" (13/18 600 ink). Okunmamışken
///   her zaman; okunduktan sonra da iş hâlâ görüntüleyeni bekliyorsa ([waiting]: görev kutusunda) —
///   eylem satırı "yeni" değil "sıra sizde" demektir (v4 A9, B17).
/// * Okunmamış: saatin önünde 8 dp sabit marka noktası (satırdaki tek turuncu; nefes almaz —
///   listeler durgun durur, v4 §6).
///
/// * Merkez duyurusu ([Announcements]; panelden gönderilen push): karoda megafon, başlık ve metin
///   yazıldığı gibi (iç kod temizliği yok) ve metnin altında duyurunun türü ("Kampanya", 13/18 600
///   soluk; hap ya da renk değil). Eylem satırı yoktur; dokununca tam metin açılır.
///
/// Okundu olunca satır sakinleşir: nokta küçülerek kaybolur, başlık incelir; iş artık görüntüleyeni
/// beklemiyorsa eylem satırı katlanır.
/// Okunmamış satır sağa kaydırınca okundu olur (satır yerinde kalır); ekran okuyucuda "Okundu işaretle"
/// özel eylemi vardır. Basınca satır hafifçe içe çöker ve zemini koyulaşır.
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    required this.onTap,
    required this.onMarkRead,
    this.now,
    this.revealIndex,
    this.waiting = false,
    this.canQuote = true,
  });

  final UserNotification notification;
  final VoidCallback onTap;
  final VoidCallback onMarkRead;

  /// Bildirimin işi hâlâ görüntüleyeni bekliyor (görev kutusunda): eylem satırı okunduktan sonra da
  /// kalır.
  final bool waiting;

  /// Görüntüleyen teklif verebilir: "Yeni sipariş" satırı "Teklif ver" der (izleyicide eylem yok).
  final bool canQuote;

  /// Satırın eylem satırı ("Teklifi aç"); sıra görüntüleyende değilse null.
  static String? actionFor(
    UserNotification n, {
    bool waiting = false,
    bool canQuote = true,
  }) => !n.isRead || waiting
      ? NotificationDisplay.actionOf(n, canQuote: canQuote)
      : null;

  /// Göreli zaman için (testler).
  final DateTime? now;

  /// Kullanılmıyor (v4: satırlar defterle birlikte bir kez dökülür, [AknLedger.pour]); API için.
  final int? revealIndex;

  /// Satırın simgesi: duyuruda megafon, diğerlerinde olayın kategorisi (uyarı / tehlikede tonlu karo).
  static IconData iconOf(UserNotification n) => Announcements.isAnnouncement(n)
      ? PhosphorIconsFill.megaphone
      : NotificationCategory.icon(n.category);

  /// Görünen okunmamış noktası (testler: satır başına bir nokta).
  static const unreadDotKey = ValueKey<String>('notification.unreadDot');

  /// Eylem satırı ("Talebi incele ›").
  static const actionKey = ValueKey<String>('notification.action');

  /// Duyurunun tür satırı ("Kampanya").
  static const kindKey = ValueKey<String>('notification.kind');

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final n = notification;
    final unread = !n.isRead;
    final announcement = Announcements.isAnnouncement(n);
    // Duyuru merkezin yazdığı gibi kalır ("YAZ-25" bir kampanya kodu olabilir, iç kod değil).
    final title = announcement
        ? n.title.trim()
        : NotificationDisplay.clean(n.title);
    final body = announcement
        ? n.body.trim()
        : NotificationDisplay.clean(n.body);
    final kind = announcement ? Announcements.kindOf(n.eventCode).label : null;
    final action = actionFor(n, waiting: waiting, canQuote: canQuote);
    final when = Fmt.relative(n.createdAt, now: now);
    final semantics = [
      if (unread) NotificationsCopy.unreadPrefix,
      ?kind,
      title,
      if (body.isNotEmpty) body,
      when,
      ?action,
    ].join('. ');
    final duration = AknMotion.of(context, AknMotion.slow);
    final titleStyle = t.bodyStrong.copyWith(
      height: 20 / 15,
      color: c.ink,
      fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
    );
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final timeStyle = t.label.copyWith(
      fontWeight: FontWeight.w500,
      color: c.dim,
      fontFeatures: AknNumerals.tabular,
    );
    final time = Text(
      when,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: timeStyle,
    );
    final tinted = n.tone == AknTone.danger || n.tone == AknTone.warn;
    final tone = tinted ? c.tone(n.tone) : null;
    final tile = ExcludeSemantics(
      child: SizedBox.square(
        dimension: 36,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: tone?.bg ?? c.surfaceAlt,
            shape: const RoundedSuperellipseBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
          child: Center(
            child: Icon(iconOf(n), size: 20, color: tone?.fg ?? c.ink),
          ),
        ),
      ),
    );
    final titleText = AnimatedDefaultTextStyle(
      duration: duration,
      curve: AknMotion.standard,
      style: titleStyle,
      maxLines: large ? 4 : 2,
      overflow: TextOverflow.ellipsis,
      child: Text(title),
    );
    // Başlık satırı: başlık, (okunmamış) nokta ve saat. Saat başlığa yer bırakmıyorsa (büyük yazı, dar
    // ekran) başlığın altına iner; hiçbir şey kesilmez, taşmaz.
    final head = LayoutBuilder(
      builder: (context, box) {
        final tp = TextPainter(
          text: TextSpan(text: when, style: timeStyle),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final timeWidth = tp.width;
        tp.dispose();
        final stacked = large || timeWidth + 24 > box.maxWidth * 0.45;
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleText,
              const SizedBox(height: 2),
              Row(
                children: [
                  _UnreadDot(visible: unread),
                  Flexible(child: time),
                ],
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titleText),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _UnreadDot(visible: unread),
                  time,
                ],
              ),
            ),
          ],
        );
      },
    );

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: AknSpace.row,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            tile,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  head,
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: t.bodySmall.copyWith(color: c.dim),
                      maxLines: large ? 6 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (kind != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      kind,
                      key: NotificationTile.kindKey,
                      style: t.label.copyWith(color: c.dim),
                      maxLines: large ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // Eylem satırı okununca katlanarak kaybolur.
                  AknAnimatedSize(
                    alignment: Alignment.topCenter,
                    duration: duration,
                    curve: AknMotion.emphasizedCurve,
                    child: action == null
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: _ActionLine(label: action),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final row = PressScale(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          splashFactory: NoSplash.splashFactory,
          highlightColor: c.surfaceAlt,
          child: content,
        ),
      ),
    );

    final tappable = Semantics(
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
      child: row,
    );

    // Okunmuş satırda kaydırma kapalı; yapı aynı kalır, böylece okundu geçişi yumuşak oynar.
    return Dismissible(
      key: ValueKey('notification-${n.id}'),
      direction: unread ? DismissDirection.startToEnd : DismissDirection.none,
      dismissThresholds: const {DismissDirection.startToEnd: 0.3},
      confirmDismiss: (_) async {
        AknHaptics.selection();
        onMarkRead();
        return false;
      },
      background: const _SwipeBackground(),
      child: tappable,
    );
  }
}

/// Eylem satırı: "Talebi incele ›" — ink 13/18 600 ve küçük ok (turuncu değil: satırın tek turuncusu
/// okunmamış noktasıdır).
class _ActionLine extends StatelessWidget {
  const _ActionLine({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Row(
      key: NotificationTile.actionKey,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            label,
            style: t.label.copyWith(color: c.ink),
            maxLines: 2,
          ),
        ),
        const SizedBox(width: 2),
        Icon(PhosphorIconsBold.caretRight, size: 12, color: c.ink),
      ],
    );
  }
}

/// Okunmamış noktası: 8 dp logo turuncusu, sabit (nefes almaz). Okundu olunca küçülerek kaybolur ve
/// yeri kapanır; yeni geldiğinde zıplayarak belirir.
class _UnreadDot extends StatelessWidget {
  const _UnreadDot({required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final duration = AknMotion.of(context, AknMotion.slow);
    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: duration,
        curve: AknMotion.emphasizedCurve,
        width: visible ? 14 : 0,
        height: 16,
        alignment: AlignmentDirectional.centerStart,
        child: AnimatedScale(
          scale: visible ? 1 : 0,
          duration: duration,
          curve: visible ? AknMotion.pop : AknMotion.exit,
          child: Container(
            key: visible ? NotificationTile.unreadDotKey : null,
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c.logo, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground();

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

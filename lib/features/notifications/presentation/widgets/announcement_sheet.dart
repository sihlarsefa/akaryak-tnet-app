import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../application/announcements.dart';
import '../../copy.dart';
import '../../data/notification_models.dart';

/// Merkez duyurusunun tam metni (yönetim panelinde Yönetim > Push bildirimleri): bildirim satırına ya
/// da duyuru push'una dokununca Bildirimler'de alttan açılır. Üstte megafon karosu, duyurunun türü
/// ("Kampanya") ve tam tarihi; altında başlığın ve metnin tamamı (satırda metin 2 satırda kesilir,
/// kilit ekranında da kısalır). Okuma sayfasıdır: ✕ yok (v4 §4); "Tamam", tutamak, aşağı kaydırma ya
/// da arka plan kapatır. Hareket uygulamanın sayfa hareketidir (kayarak açılır, arka plan bulanır,
/// içerik yükselir; hareket azaltılınca yok).
Future<void> showAnnouncementSheet(BuildContext context, UserNotification n) =>
    showAppSheet<void>(
      context: context,
      showClose: false,
      builder: (_) => AnnouncementBody(notification: n),
      actionsBuilder: (ctx) => AknButton.secondary(
        label: NotificationsCopy.announcementDone,
        expand: true,
        onPressed: () => Navigator.of(ctx).pop(),
      ),
    );

/// Duyuru sayfasının gövdesi: tür ve tarih, başlık (sayfa başlığı olarak okunur), metin.
class AnnouncementBody extends StatelessWidget {
  const AnnouncementBody({super.key, required this.notification, this.now});

  final UserNotification notification;

  /// Tarihteki yılın karşılaştırıldığı "şimdi" (testler).
  final DateTime? now;

  /// Sayfanın gövdesi (testler).
  static const bodyKey = ValueKey<String>('announcement.sheet');

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final n = notification;
    final kind = Announcements.kindOf(n.eventCode);
    final when = Announcements.fullDate(n.createdAt, now: now);
    // Merkezin yazdığı gibi: iç kod temizliği yok ("YAZ-25" bir kampanya kodu olabilir).
    final title = n.title.trim();
    final body = n.body.trim();
    // Karo satırdakiyle aynı: yalnızca uyarı / tehlikede tonlu (sunucu bakım duyurusunu uyarı yazar).
    final tinted = n.tone == AknTone.warn || n.tone == AknTone.danger;
    final tone = tinted ? c.tone(n.tone) : null;
    return Column(
      key: bodyKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            ExcludeSemantics(
              child: SizedBox.square(
                dimension: 44,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: tone?.bg ?? c.surfaceAlt,
                    shape: const RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      PhosphorIconsFill.megaphone,
                      size: 22,
                      color: tone?.fg ?? c.ink,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(kind.label, style: t.label.copyWith(color: c.ink)),
                  const SizedBox(height: 2),
                  Text(
                    when,
                    style: t.label.copyWith(
                      fontWeight: FontWeight.w500,
                      color: c.dim,
                      fontFeatures: AknNumerals.tabular,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (title.isNotEmpty)
          Semantics(
            header: true,
            child: Text(title, style: t.title.copyWith(color: c.ink)),
          ),
        if (body.isNotEmpty) ...[
          if (title.isNotEmpty) const SizedBox(height: 8),
          Text(body, style: t.body.copyWith(color: c.ink)),
        ],
      ],
    );
  }
}

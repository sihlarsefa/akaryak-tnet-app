import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/push/push_payload.dart';
import '../../../core/push/push_providers.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import '../copy.dart';
import '../data/notification_models.dart';

/// Merkez duyurusunun türü: yönetim panelindeki "Bildirim tipi" (Yönetim > Push bildirimleri). Olay
/// kodunun son parçasıdır: `system.announcement.<tür>`.
enum AnnouncementKind {
  general(NotificationsCopy.kindGeneral),
  notice(NotificationsCopy.kindNotice),
  campaign(NotificationsCopy.kindCampaign),
  maintenance(NotificationsCopy.kindMaintenance),
  price(NotificationsCopy.kindPrice);

  const AnnouncementKind(this.label);

  /// Paneldeki adı ("Kampanya").
  final String label;
}

/// Merkezin panelden gönderdiği duyurular (push kampanyası). Sunucu her alıcıya bir gelen kutusu satırı
/// yazar: kategori `system`, olay kodu `system.announcement.<tür>`, rota yok (`entityType`
/// `PushCampaign`). Satırın sayfası yoktur; dokununca Bildirimler'de duyurunun tam metni açılır.
abstract final class Announcements {
  /// Duyuru olay kodlarının ortak başı.
  static const eventPrefix = 'system.announcement';

  /// Push dokunuşu en çok bu kadar eskiyse duyuruyu açar (soğuk açılış, giriş ve kilit açma dahil).
  static const tapMaxAge = Duration(minutes: 10);

  /// Olay kodu bir duyurunun mu (kod ASCII'dir; büyük harf farkı önemsiz).
  static bool isEventCode(String? code) =>
      code != null && code.trim().asciiLower.startsWith(eventPrefix);

  /// Bildirim bir merkez duyurusu mu.
  static bool isAnnouncement(UserNotification n) => isEventCode(n.eventCode);

  /// Olay kodundaki tür ("system.announcement.campaign" → Kampanya). Sunucunun İngilizce ya da
  /// Türkçe adlarını, büyük harf ve ayırıcı farkını tanır ("price_update", "Bakım-Kesinti"); paneldeki
  /// sırayla numara da olabilir (0 Genel … 4 Fiyat güncellemesi). Bilinmeyen ya da boş tür "Duyuru"dur.
  static AnnouncementKind kindOf(String? code) {
    final raw = (code ?? '').trim();
    if (!isEventCode(raw)) return AnnouncementKind.notice;
    final slug = _fold(raw.substring(eventPrefix.length));
    if (slug.isEmpty) return AnnouncementKind.notice;
    final index = int.tryParse(slug);
    if (index != null) {
      return index >= 0 && index < _panelOrder.length
          ? _panelOrder[index]
          : AnnouncementKind.notice;
    }
    for (final (kind, names) in _names) {
      if (names.any(slug.startsWith)) return kind;
    }
    return AnnouncementKind.notice;
  }

  /// Paneldeki seçim sırası.
  static const _panelOrder = [
    AnnouncementKind.general,
    AnnouncementKind.notice,
    AnnouncementKind.campaign,
    AnnouncementKind.maintenance,
    AnnouncementKind.price,
  ];

  /// Türün sunucudaki olası adları (katlanmış: küçük harf, Türkçe harfsiz, ayırıcısız; baştan eşleşir).
  static const _names = <(AnnouncementKind, List<String>)>[
    (AnnouncementKind.price, ['price', 'pricing', 'fiyat', 'tariff']),
    (
      AnnouncementKind.maintenance,
      ['maintenance', 'maint', 'bakim', 'kesinti', 'outage', 'downtime'],
    ),
    (
      AnnouncementKind.campaign,
      ['campaign', 'kampanya', 'promo', 'promotion', 'offer', 'firsat'],
    ),
    (AnnouncementKind.general, ['general', 'genel', 'default']),
    (
      AnnouncementKind.notice,
      ['announcement', 'announce', 'duyuru', 'notice', 'news', 'info'],
    ),
  ];

  static final _nonAlnum = RegExp('[^a-z0-9]');

  /// ".Bakım-Kesinti" → "bakimkesinti" (Türkçe küçük harf, aksansız, ayırıcısız).
  static String _fold(String s) =>
      TurkishText.searchKey(s).replaceAll(_nonAlnum, '');

  /// Duyurunun tam tarihi (Türkiye saati): "29 Ekim Perşembe, 13:10"; başka bir yıldaysa yılıyla
  /// ("30 Aralık 2025 Salı, 09:10").
  static String fullDate(DateTime at, {DateTime? now}) {
    final w = TrTime.wall(at);
    final thisYear = TrTime.wall(now ?? TrTime.now()).year;
    final year = w.year == thisYear ? '' : ' ${w.year}';
    return '${w.day} ${Fmt.monthNames[w.month - 1]}$year '
        '${Fmt.weekday(at)}, ${Fmt.time(at)}';
  }

  /// Dokunulan push'un duyurusu, gelen kutusunda bulunamazsa (çevrimdışı, liste yüklenemedi): başlık
  /// ve metin push'tan. Kimlik ya da metin yoksa null.
  static UserNotification? fromPush(PushPayload p) {
    final id = p.notificationId;
    final title = p.title?.trim() ?? '';
    final body = p.body?.trim() ?? '';
    if (id == null || (title.isEmpty && body.isEmpty)) return null;
    return UserNotification(
      id: id,
      category: p.category ?? NotificationCategory.system,
      eventCode: p.type ?? eventPrefix,
      title: title,
      body: body,
      entityType: p.entityType,
      entityId: p.entityId,
      createdAt: p.receivedAt ?? DateTime.now().toUtc(),
    );
  }
}

/// Push'una dokunulan duyuru: Bildirimler sayfası açılınca (ya da açıkken) duyurunun tam metnini açar.
///
/// Duyurunun rotası yoktur; push'un rotası `/notifications`tır ve dokunuş uygulamayı Bildirimler'e
/// götürür (çekirdek `PushCoordinator`). Hangi duyuruya dokunulduğunu push olayı söyler. Uygulama son
/// push olayını açılıştan beri tutar ([pushEventsProvider]; soğuk açılıştaki ilk dokunuş da kalır): bu
/// sağlayıcı ilk okunduğunda o olaya, sonra yeni olaylara bakar ve dokunulan duyuruyu bir kez
/// bekletir. Aynı olay iki kez açılmaz; [Announcements.tapMaxAge]'den eski dokunuş açılmaz.
final announcementTapProvider =
    NotifierProvider<AnnouncementTapController, PushPayload?>(
      AnnouncementTapController.new,
    );

class AnnouncementTapController extends Notifier<PushPayload?> {
  /// Son bakılan olay (aynı olay bir kez işlenir; sağlayıcı yeniden kurulsa da).
  PushEvent? _seen;

  @override
  PushPayload? build() {
    ref.listen<AsyncValue<PushEvent>>(pushEventsProvider, (_, next) {
      final tap = _accept(next.valueOrNull);
      if (tap != null) state = tap;
    });
    // Dokunuş bu sağlayıcıdan önce geldiyse (sayfa dokunuşla açıldı): son olay.
    return _accept(ref.read(pushEventsProvider).valueOrNull);
  }

  PushPayload? _accept(PushEvent? e) {
    if (e == null || identical(e, _seen)) return null;
    _seen = e;
    if (e.origin != PushOrigin.tap) return null;
    final p = e.payload;
    if (!Announcements.isEventCode(p.type) || p.notificationId == null) {
      return null;
    }
    return _stale(p) ? null : p;
  }

  /// Dokunuş [Announcements.tapMaxAge]'den eski mi (saat: [TrTime.now]).
  static bool _stale(PushPayload p) {
    final at = p.receivedAt;
    return at != null &&
        TrTime.now().difference(at.toUtc()) > Announcements.tapMaxAge;
  }

  /// Bekleyen dokunuşu alır ve temizler (sayfa duyuruyu açar). Bildirimler o arada
  /// açılmadıysa ve dokunuş [Announcements.tapMaxAge]'den eskiyse açılmaz (geç açılan
  /// sayfa eski bir duyuruyu kendiliğinden açmasın).
  PushPayload? take() {
    final p = state;
    if (p == null) return null;
    state = null;
    return _stale(p) ? null : p;
  }
}

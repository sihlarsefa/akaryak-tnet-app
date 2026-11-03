import 'dart:convert';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/log.dart';
import 'push_payload.dart';

/// Android bildirim kanalı (spec B.4: sunucu `channel_id` kategoriye göre seçer).
@immutable
class AknNotificationChannel {
  const AknNotificationChannel(
    this.id,
    this.name,
    this.description, {
    this.category,
    this.importance = Importance.high,
  });

  final String id;

  /// Kullanıcının Android ayarlarında gördüğü ad.
  final String name;
  final String description;

  /// Push `data.category` (`orders`, `quotes` …); yedek kanalda null.
  final String? category;
  final Importance importance;

  AndroidNotificationChannel get android => AndroidNotificationChannel(
    id,
    name,
    description: description,
    importance: importance,
  );
}

/// Android bildirim kanalları ve yerel bildirimler (spec C.4, B.4, D.7).
///
/// Kategori kanalları açılışta bir kez oluşturulur; kullanıcı Android ayarlarından her kategoriyi ayrı
/// kapatabilir. FCM'in kanalsız gelen bildirimleri yedek kanala ([fallback], `akn_default`; sunucu
/// `Push:AndroidChannelId`) düşer. Küçük simge `ic_stat_akn` (beyaz » işareti).
///
/// Android'de FCM uygulama açıkken bildirim göstermez: ön planda gelen push burada yerel bildirim olur
/// ([showPush]; sunucunun kategori kanalı, gelen kutusu satırından kararlı kimlik, dokunuş verisi
/// push'un kendisi).
abstract final class LocalNotifications {
  /// Sunucunun kategori → kanal tablosu (`NotificationPushDelivery`).
  static const channels = <AknNotificationChannel>[
    AknNotificationChannel(
      'akn_orders',
      'Siparişler',
      'Yeni sipariş, sipariş durumu ve finans onayı',
      category: 'orders',
    ),
    AknNotificationChannel(
      'akn_quotes',
      'Teklifler',
      'Teklif hazır, süresi doluyor, onay ve revize',
      category: 'quotes',
    ),
    AknNotificationChannel(
      'akn_shipments',
      'Teslimatlar',
      'Sevkiyat planı, yola çıkış, teslim ve itiraz',
      category: 'shipments',
    ),
    AknNotificationChannel(
      'akn_approvals',
      'Onaylar',
      'Kararınızı bekleyen onaylar ve ek bilgi istekleri',
      category: 'approvals',
    ),
    AknNotificationChannel(
      'akn_payments',
      'Tahsilat',
      'Ödeme belgesi, tahsilat ve vade hatırlatmaları',
      category: 'payments',
    ),
    AknNotificationChannel(
      'akn_field',
      'Saha',
      'Saha formu ve ön kayıt kararları',
      category: 'field',
    ),
    AknNotificationChannel(
      'akn_system',
      'Sistem',
      'Hesap ve uygulama bildirimleri',
      category: 'system',
      importance: Importance.defaultImportance,
    ),
  ];

  /// Kanalsız gelen bildirimler (sunucu `Push:AndroidChannelId` varsayılanı).
  static const fallback = AknNotificationChannel(
    'akn_default',
    'Diğer bildirimler',
    'Kategorisi olmayan bildirimler',
  );

  /// Eski adlar (uyumluluk).
  static const channelId = 'akn_default';
  static const channelName = 'Diğer bildirimler';
  static const channelDescription = 'Kategorisi olmayan bildirimler';

  /// Bildirim küçük simgesi (`android/app/src/main/res/drawable*/ic_stat_akn.png`).
  static const smallIcon = '@drawable/ic_stat_akn';

  /// Başlıksız push'un başlığı (FCM de uygulama adını koyar).
  static const appName = 'AkaryakıtNet';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static bool _launchTaken = false;

  /// Yerel bildirime dokununca çağrılır. Veri ön plan push'unun kopyasında push verisinin JSON'u
  /// ([PushPayload.toLocalPayload]), diğer yerel bildirimlerde (ve eski kopyalarda) uygulama rotasıdır;
  /// [PushPayload.fromLocalPayload] ikisini de okur.
  static void Function(String? payload)? onTap;

  /// Push kopyalarının kimlik aralığı (negatif sayılar; diğer yerel bildirimler 0 ve üstü). Android'de
  /// kimlik dokunuş niyetinin de anahtarıdır: iki bildirim aynı kimliği taşısa eskisine dokunmak
  /// yenisinin rotasını açardı.
  static const _pushRowSpan = 0x40000000;

  /// Sunucunun özet push'u ("12 yeni bildirim"; sunucuda "System:summary" ile daraltılır).
  static const summaryType = 'system.summary';

  /// Özet push kopyasının tek kimliği: yeni özet eskisinin yerine geçer (uygulama kapalıyken olduğu
  /// gibi). Satır aralığının hemen altında; içerik özetleri bunun da altında.
  static const _summaryId = -_pushRowSpan - 1;

  /// Kategori için kanal (bilinmeyen kategori → [fallback]).
  static AknNotificationChannel channelFor(String? category) {
    for (final c in channels) {
      if (c.category == category) return c;
    }
    return fallback;
  }

  static Future<void> init() async {
    if (_ready || kIsWeb) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(smallIcon),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) {
          // Kaydırıp kapatmak dokunuş değildir (bildirilmesi istenmez; yine de süzülür).
          if (r.notificationResponseType ==
              NotificationResponseType.notificationDismissed) {
            return;
          }
          onTap?.call(r.payload);
        },
      );
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        for (final c in [...channels, fallback]) {
          await android?.createNotificationChannel(c.android);
        }
      }
      _ready = true;
    } catch (e) {
      AppLog.warn('Yerel bildirimler hazırlanamadı', error: e);
    }
  }

  /// Yerel bildirim gösterir (ör. bekleyen işlem tamamlandı); dokunuş [route]'u açar. [id] 0 ya da
  /// üstü (negatifler push kopyalarına ayrılmıştır, [pushIdOf]). Hata fırlatmaz; döner: gösterildi mi.
  static Future<bool> show({
    required int id,
    required String title,
    required String body,
    String? route,
    String? category,
  }) {
    assert(id >= 0, 'Negatif kimlikler push kopyalarına ayrılmıştır.');
    return _show(
      id: id,
      title: title,
      body: body,
      payload: route,
      category: category,
    );
  }

  /// Ön planda gelen push'un sistem bildirimi (yalnızca Android; iOS'ta bandı sistem gösterir).
  /// Push'un başlığı ve metni, kategorisinin kanalı (sunucunun seçtiği kanal), [pushIdOf] kimliği
  /// (yeniden denenen push yalnızca kendi kopyasının yerine geçer; siparişin her adımı ayrı kalır) ve
  /// dokunuşta kilit ekranındaki push'la aynı rotayı ve `?focus=` bloğunu açan veri
  /// ([PushPayload.toLocalPayload]). Döner: gösterildi mi (false ise çağıran uygulama içi balonu
  /// gösterir).
  static Future<bool> showPush(PushPayload p) async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    final body = p.body ?? '';
    return _show(
      id: pushIdOf(p),
      title: p.title ?? appName,
      body: body,
      payload: p.toLocalPayload(),
      category: p.category,
      // Siparişin uzun adım metni açılınca tam okunur (FCM'in arka plan bildirimi gibi).
      style: body.isEmpty ? null : BigTextStyleInformation(body),
    );
  }

  /// Push kopyasının kararlı kimliği; cihazdaki kimliği sunucu gibi seçer (Android `tag` /
  /// `apns-collapse-id`):
  /// - iş bildirimi: gelen kutusu satırının eksisi (`notificationId` 4711 → -4711; -1 … -2^30):
  ///   yeniden denenen push yalnızca kendi kopyasının yerine geçer, siparişin her adımı ayrı kalır;
  /// - özet push ([summaryType]): tek kimlik (-2^30-1), yeni özet eskisinin yerine geçer;
  /// - satır yoksa: olay, varlık, rota ve metnin kararlı özetinden (-2^30-2 … -(2^31-1)).
  ///
  /// Aynı push aynı kimliği alır; aralıklar birbiriyle ve diğer yerel bildirimlerin kimlikleriyle (0 ve
  /// üstü) çakışmaz; hepsi 32 bitlik Android kimliğine sığar.
  static int pushIdOf(PushPayload p) {
    if (p.type == summaryType) return _summaryId;
    final row = p.notificationId;
    if (row != null && row > 0) return -1 - (row - 1) % _pushRowSpan;
    final key = [
      p.type,
      p.entityType,
      p.entityId,
      p.route,
      p.title,
      p.body,
    ].join('|');
    return _summaryId - 1 - _stableHash(key) % (_pushRowSpan - 2);
  }

  /// FNV-1a (32 bit): süreçten sürece aynı (`String.hashCode` bunu garanti etmez).
  static int _stableHash(String s) {
    var h = 0x811c9dc5;
    for (final b in utf8.encode(s)) {
      h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  static Future<bool> _show({
    required int id,
    required String title,
    required String body,
    String? payload,
    String? category,
    StyleInformation? style,
  }) async {
    if (!_ready || kIsWeb) return false;
    final channel = channelFor(category);
    try {
      // Bu platformun eklentisi kayıtlı değilse gösterim sessizce hiçbir şey yapmazdı.
      final registered = switch (defaultTargetPlatform) {
        TargetPlatform.android =>
          _plugin
                  .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin
                  >() !=
              null,
        TargetPlatform.iOS =>
          _plugin
                  .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin
                  >() !=
              null,
        _ => false,
      };
      if (!registered) return false;
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: channel.importance,
            priority: Priority.high,
            icon: smallIcon,
            color: const Color(0xFFC94C0C),
            styleInformation: style,
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
      return true;
    } catch (e) {
      AppLog.warn('Yerel bildirim gösterilemedi', error: e);
      return false;
    }
  }

  /// Kapalı uygulamayı açan yerel bildirim dokunuşunun verisi (FCM'in ilk mesajı gibi; Android'de ön
  /// planda gösterilmiş bir push kopyası olabilir). Süreç başına bir kez okunur; dokunuş yoksa null.
  static Future<String?> takeLaunchPayload() async {
    if (!_ready || _launchTaken) return null;
    _launchTaken = true;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details == null || !details.didNotificationLaunchApp) return null;
      return details.notificationResponse?.payload;
    } catch (e) {
      AppLog.debug('Açılış bildirimi okunamadı: ${e.runtimeType}');
      return null;
    }
  }

  /// Testler: hazırlığı, açılış dokunuşunu ve dokunuş dinleyicisini sıfırlar.
  @visibleForTesting
  static void debugReset() {
    _ready = false;
    _launchTaken = false;
    onTap = null;
  }

  /// Bildirim merkezindeki bu uygulamanın bildirimlerini kaldırır (çıkış). Hata fırlatmaz.
  static Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      AppLog.debug('Bildirimler kaldırılamadı: ${e.runtimeType}');
    }
  }

  /// Android 13+ bildirim izni (iOS izni FCM üzerinden istenir).
  static Future<bool?> requestAndroidPermission() async {
    try {
      return await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (_) {
      return null;
    }
  }
}

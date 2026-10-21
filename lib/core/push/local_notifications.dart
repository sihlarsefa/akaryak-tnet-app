import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/log.dart';

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

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Yerel bildirime dokununca çağrılır (payload = uygulama rotası).
  static void Function(String? route)? onTap;

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
        onDidReceiveNotificationResponse: (r) => onTap?.call(r.payload),
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

  /// Yerel bildirim gösterir (ör. bekleyen işlem tamamlandı). Hata fırlatmaz.
  static Future<void> show({
    required int id,
    required String title,
    required String body,
    String? route,
    String? category,
  }) async {
    if (!_ready) return;
    final channel = channelFor(category);
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: route,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: channel.importance,
            priority: Priority.high,
            icon: smallIcon,
            color: const Color(0xFFC94C0C),
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      AppLog.warn('Yerel bildirim gösterilemedi', error: e);
    }
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

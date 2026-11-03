// Ön plan push'u testleri için sahteler: FCM'in uygulama içi uçları ([FakeMessaging]) ve
// flutter_local_notifications'ın Android eklentisi ([FakeAndroidNotifications]; gerçek
// `LocalNotifications` → eklenti cephesi → bu sahte). Ağ ve platform yok.
import 'dart:async';

import 'package:akaryakitnet/core/push/push_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart'
    show RemoteMessage, RemoteNotification;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// FCM: testin verdiği ön plan / dokunuş mesajları; iOS sunum seçeneklerini kaydeder.
class FakeMessaging implements PushMessagingPlatform {
  final messages = StreamController<RemoteMessage>.broadcast();
  final opened = StreamController<RemoteMessage>.broadcast();
  final tokens = StreamController<String>.broadcast();

  /// Kapalı uygulamayı açan push.
  RemoteMessage? initial;

  /// Son `setForegroundNotificationPresentationOptions` çağrısı.
  ({bool alert, bool badge, bool sound})? presentation;
  int presentationCalls = 0;

  /// Sunum seçenekleri kaydedilemesin (platform hatası).
  bool failPresentation = false;

  @override
  Stream<RemoteMessage> get onMessage => messages.stream;

  @override
  Stream<RemoteMessage> get onMessageOpenedApp => opened.stream;

  @override
  Stream<String> get onTokenRefresh => tokens.stream;

  @override
  Future<RemoteMessage?> getInitialMessage() async => initial;

  @override
  Future<void> setForegroundPresentation({
    required bool alert,
    required bool badge,
    required bool sound,
  }) async {
    presentationCalls++;
    if (failPresentation) throw StateError('sunum seçenekleri kaydedilemedi');
    presentation = (alert: alert, badge: badge, sound: sound);
  }

  Future<void> close() async {
    await messages.close();
    await opened.close();
    await tokens.close();
  }
}

/// Sunucunun gönderdiği gibi bildirimli push (`notification` + `data`, hepsi metin).
RemoteMessage businessPush({
  String type = 'order.finance_approved',
  int? notificationId = 4711,
  String route = '/bayi/orders/12',
  String category = 'orders',
  String? title = 'Yeni sipariş: SIP-20261102-12',
  String? body =
      'Marmara İnşaat · Motorin 30.000 L — finans onaylı, teklif bekliyor.',
}) => RemoteMessage(
  messageId: 'm-$notificationId',
  notification: RemoteNotification(title: title, body: body),
  data: {
    'type': type,
    'notificationId': ?notificationId?.toString(),
    'route': route,
    'entityType': 'Order',
    'entityId': '12',
    'category': category,
    'audience': 'bayi',
  },
);

/// Sessiz yenileme sinyali (yalnızca `data` + content-available; başlık ve metin yok).
RemoteMessage silentPush() => const RemoteMessage(
  messageId: 'm-silent',
  contentAvailable: true,
  data: {
    'type': 'order.updated',
    'notificationId': '4800',
    'route': '/orders/12',
    'entityType': 'Order',
    'entityId': '12',
    'category': 'orders',
  },
);

/// Gösterilen yerel bildirim.
class ShownNotification {
  ShownNotification(this.id, this.title, this.body, this.details, this.payload);
  final int id;
  final String? title;
  final String? body;
  final AndroidNotificationDetails? details;
  final String? payload;

  String? get channelId => details?.channelId;
}

/// flutter_local_notifications'ın Android eklentisi: gösterimleri ve kanalları kaydeder, dokunuşu ve
/// soğuk açılışı taklit eder.
class FakeAndroidNotifications extends AndroidFlutterLocalNotificationsPlugin {
  final shown = <ShownNotification>[];
  final channels = <String>[];
  int cancelAllCalls = 0;

  /// Uygulamayı açan bildirim (soğuk açılış).
  NotificationAppLaunchDetails? launch;

  DidReceiveNotificationResponseCallback? _onResponse;

  @override
  Future<bool> initialize({
    required AndroidInitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    _onResponse = onDidReceiveNotificationResponse;
    return true;
  }

  @override
  Future<void> createNotificationChannel(
    AndroidNotificationChannel notificationChannel,
  ) async => channels.add(notificationChannel.id);

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    AndroidNotificationDetails? notificationDetails,
    String? payload,
  }) async {
    shown.add(ShownNotification(id, title, body, notificationDetails, payload));
  }

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async => launch;

  @override
  Future<void> cancelAll() async => cancelAllCalls++;

  /// Bildirime dokunuş (uygulama açık ya da arka planda).
  void tap(
    String? payload, {
    NotificationResponseType type =
        NotificationResponseType.selectedNotification,
  }) => _onResponse?.call(
    NotificationResponse(notificationResponseType: type, payload: payload),
  );
}

// Uygulama açıkken gelen push (sahip, 2026-11-02: siparişin her adımı push olarak görünsün): her adım
// uygulama kapalıyken olduğu gibi sistem bildirimi olur ve Bildirim Merkezi'nde kalır.
//
// - iOS: bandı sistem gösterir (sunum seçenekleri bant + rozet + ses); yerel kopya çıkmaz (çift olurdu).
// - Android: FCM uygulama açıkken bildirim göstermez; yerel bildirim — push'un başlığı ve metni,
//   kategorisinin kanalı (sunucunun kanalı), gelen kutusu satırından kararlı kimlik (yeniden denenen push
//   yalnızca kendi kopyasının yerine geçer), dokunuşta rota + olay.
// - İzin yoksa sistem gösteremez: olay "gösterilmedi" gider (koordinatör balonu açar).
// - Sessiz / yalnızca veri push'u hiçbir şey göstermez.
// - Yerel bildirime dokunuş (yeni veri ve eski düz rota) ve soğuk açılış: kilit ekranı dokunuşuyla aynı
//   olay.
import 'package:akaryakitnet/core/push/local_notifications.dart';
import 'package:akaryakitnet/core/push/push_payload.dart';
import 'package:akaryakitnet/core/push/push_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart'
    show AuthorizationStatus, RemoteMessage, RemoteNotification;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_push.dart';
import 'push_test_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeAndroidNotifications plugin;
  late FakeMessaging fcm;

  setUp(() {
    LocalNotifications.debugReset();
    plugin = FakeAndroidNotifications();
    FlutterLocalNotificationsPlatform.instance = plugin;
    fcm = FakeMessaging();
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    LocalNotifications.debugReset();
    await fcm.close();
  });

  /// Firebase'li PushService ([platform], izin [status]); olaylar listede.
  Future<List<PushEvent>> start({
    TargetPlatform platform = TargetPlatform.android,
    AuthorizationStatus status = AuthorizationStatus.authorized,
    bool available = true,
  }) async {
    debugDefaultTargetPlatformOverride = platform;
    final push = PushService(
      available: available,
      permissions: FakePushPlatform(current: status),
      messaging: fcm,
    );
    final events = <PushEvent>[];
    final sub = push.events.listen(events.add);
    addTearDown(() async {
      await sub.cancel();
      await push.dispose();
    });
    await push.start();
    return events;
  }

  Future<void> deliver(RemoteMessage m) async {
    fcm.messages.add(m);
    await pumpEventQueue();
  }

  group('iOS', () {
    test(
      'sunum seçenekleri bant + rozet + ses; bildirimli push sistemde gösterilmiş sayılır, '
      'yerel kopya çıkmaz',
      () async {
        final events = await start(platform: TargetPlatform.iOS);
        expect(fcm.presentationCalls, 1);
        expect(fcm.presentation, (alert: true, badge: true, sound: true));

        await deliver(businessPush());
        expect(events, hasLength(1));
        final e = events.single;
        expect(e.origin, PushOrigin.foreground);
        expect(e.presented, isTrue);
        expect(e.payload.type, 'order.finance_approved');
        expect(e.payload.route, '/bayi/orders/12');
        expect(plugin.shown, isEmpty, reason: 'iOS: bandı sistem gösterir');
      },
    );

    test(
      'izin yoksa gösterilmemiş sayılır (balon); yerel kopya yine yok',
      () async {
        final events = await start(
          platform: TargetPlatform.iOS,
          status: AuthorizationStatus.denied,
        );
        await deliver(businessPush());
        expect(events.single.presented, isFalse);
        expect(plugin.shown, isEmpty);
      },
    );

    test(
      'sunum seçenekleri kaydedilemezse gösterilmemiş sayılır (balon); dinleyiciler yine bağlı',
      () async {
        fcm.failPresentation = true;
        final events = await start(platform: TargetPlatform.iOS);
        expect(fcm.messages.hasListener, isTrue);
        await deliver(businessPush());
        expect(events.single.presented, isFalse);
        expect(plugin.shown, isEmpty);
      },
    );
  });

  group('Android', () {
    test(
      'sunum seçeneği ayarlanmaz; push yerel bildirim olur: bir kez, satırdan kimlik, kategori '
      'kanalı, başlık ve metin, dokunuş verisinde rota + olay',
      () async {
        final events = await start();
        expect(fcm.presentationCalls, 0);
        expect(plugin.channels, contains('akn_orders'));

        await deliver(businessPush());
        expect(plugin.shown, hasLength(1));
        final n = plugin.shown.single;
        expect(n.id, -4711, reason: 'satır 4711 → -4711');
        expect(
          n.id,
          LocalNotifications.pushIdOf(const PushPayload(notificationId: 4711)),
        );
        expect(n.channelId, 'akn_orders');
        expect(n.details?.importance, Importance.high);
        expect(n.title, 'Yeni sipariş: SIP-20261102-12');
        expect(
          n.body,
          'Marmara İnşaat · Motorin 30.000 L — finans onaylı, teklif bekliyor.',
        );
        final tap = PushPayload.fromLocalPayload(n.payload);
        expect(tap.route, '/bayi/orders/12');
        expect(tap.type, 'order.finance_approved');
        expect(tap.notificationId, 4711);
        expect(tap.entityType, 'Order');
        expect(tap.entityId, 12);
        expect(tap.category, 'orders');

        expect(events.single.origin, PushOrigin.foreground);
        expect(events.single.presented, isTrue);
      },
    );

    test(
      'aynı push yeniden gelirse aynı kimlik (kendi kopyasının yerine geçer); başka adım ayrı kalır',
      () async {
        final events = await start();
        await deliver(businessPush());
        await deliver(businessPush());
        await deliver(
          businessPush(
            type: 'order.approved',
            notificationId: 4790,
            title: 'Teklif onaylandı: SIP-20261102-12',
            body: 'Müşteri teklifi onayladı; sevkiyatı planlayın.',
          ),
        );
        expect(plugin.shown.map((n) => n.id), [-4711, -4711, -4790]);
        expect(events.every((e) => e.presented), isTrue);
      },
    );

    test(
      'özet push\'u tek kopya: yeni özet eskisinin yerine geçer (sunucudaki daraltma gibi)',
      () async {
        await start();
        await deliver(
          businessPush(
            type: LocalNotifications.summaryType,
            notificationId: 9001,
            route: '/notifications',
            category: 'system',
            title: '12 yeni bildirim',
            body: 'Hepsi Bildirimler sayfasında.',
          ),
        );
        await deliver(
          businessPush(
            type: LocalNotifications.summaryType,
            notificationId: 9050,
            route: '/notifications',
            category: 'system',
            title: '13 yeni bildirim',
            body: 'Hepsi Bildirimler sayfasında.',
          ),
        );
        expect(plugin.shown, hasLength(2));
        expect(plugin.shown.first.id, plugin.shown.last.id);
        expect(plugin.shown.last.channelId, 'akn_system');
      },
    );

    test(
      'kanal push kategorisinden; bilinmeyen kategori yedek kanala',
      () async {
        await start();
        await deliver(
          businessPush(
            type: 'shipment.dispatched',
            notificationId: 5001,
            route: '/shipments/7',
            category: 'shipments',
          ),
        );
        await deliver(businessPush(notificationId: 5002, category: 'yeni'));
        expect(plugin.shown.map((n) => n.channelId), [
          'akn_shipments',
          'akn_default',
        ]);
      },
    );

    test('izin yoksa gösterilmez (balon); izin hiç sorulmadıysa da', () async {
      final events = await start(status: AuthorizationStatus.denied);
      await deliver(businessPush());
      expect(plugin.shown, isEmpty);
      expect(events.single.presented, isFalse);

      final asked = await start(status: AuthorizationStatus.notDetermined);
      await deliver(businessPush(notificationId: 4712));
      expect(plugin.shown, isEmpty);
      expect(asked.single.presented, isFalse);
    });

    test(
      'yerel bildirimler hazır değilse ya da Android eklentisi yoksa gösterilmemiş sayılır (balon)',
      () async {
        final events = await start();
        // Hazırlık başarısız (ör. eklenti açılışta hata verdi).
        LocalNotifications.debugReset();
        await deliver(businessPush());
        // Eklenti bu platformun değil: gösterim sessizce hiçbir şey yapmazdı.
        await LocalNotifications.init();
        FlutterLocalNotificationsPlatform.instance =
            IOSFlutterLocalNotificationsPlugin();
        await deliver(businessPush(notificationId: 4712));
        expect(plugin.shown, isEmpty);
        expect(events, hasLength(2));
        expect(events.every((e) => !e.presented), isTrue);
      },
    );
  });

  test(
    'sessiz ya da yalnızca veri push\'u hiçbir şey göstermez; olay yine gider (tazeleme)',
    () async {
      final events = await start();
      await deliver(silentPush());
      // Veride başlık / metin olsa da bildirimsiz push sistemde gösterilmez (kapalıyken de çıkmaz).
      await deliver(
        const RemoteMessage(
          data: {
            'type': 'order.updated',
            'title': 'Veri başlığı',
            'body': 'Veri metni',
            'route': '/orders/12',
          },
        ),
      );
      expect(plugin.shown, isEmpty);
      expect(events, hasLength(2));
      expect(events.every((e) => !e.presented), isTrue);
      expect(events.first.payload.title, isNull);
      expect(events.first.payload.body, isNull);
    },
  );

  test('başlıksız push uygulama adıyla gösterilir', () async {
    await start();
    await deliver(
      const RemoteMessage(
        notification: RemoteNotification(body: 'Sevkiyat yola çıktı.'),
        data: {'type': 'shipment.dispatched', 'notificationId': '61'},
      ),
    );
    expect(plugin.shown.single.title, LocalNotifications.appName);
    expect(plugin.shown.single.body, 'Sevkiyat yola çıktı.');
  });

  test(
    'Firebase yoksa ön plan push\'u yok; yerel dokunuş yine çalışır',
    () async {
      final events = await start(available: false);
      expect(fcm.messages.hasListener, isFalse);
      plugin.tap('/orders/5');
      await pumpEventQueue();
      expect(events.single.origin, PushOrigin.tap);
      expect(events.single.payload.route, '/orders/5');
    },
  );

  group('yerel bildirime dokunuş', () {
    test(
      'push kopyası: kilit ekranı dokunuşu gibi rota + olay + satır; eski düz rota da açılır; '
      'kaydırıp kapatma dokunuş değildir',
      () async {
        final events = await start();
        await deliver(businessPush());
        final copy = plugin.shown.single.payload;
        events.clear();

        plugin.tap(copy);
        plugin.tap('/orders/12002');
        plugin.tap(copy, type: NotificationResponseType.notificationDismissed);
        await pumpEventQueue();

        expect(events, hasLength(2));
        expect(events.every((e) => e.origin == PushOrigin.tap), isTrue);
        final p = events.first.payload;
        expect(p.route, '/bayi/orders/12');
        expect(p.type, 'order.finance_approved');
        expect(p.notificationId, 4711);
        expect(p.receivedAt, isNotNull);
        final old = events.last.payload;
        expect(old.route, '/orders/12002');
        expect(old.type, isNull);
      },
    );

    test(
      'kapalı uygulamayı açan kopya: açılışta bir kez dokunuş olayı (FCM ilk mesajı gibi)',
      () async {
        final copy = const PushPayload(
          type: 'order.finance_approved',
          notificationId: 4711,
          route: '/bayi/orders/12',
          category: 'orders',
          title: 'Yeni sipariş: SIP-20261102-12',
        ).toLocalPayload();
        plugin.launch = NotificationAppLaunchDetails(
          true,
          notificationResponse: NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            payload: copy,
          ),
        );
        final events = await start();
        expect(events, hasLength(1));
        expect(events.single.origin, PushOrigin.tap);
        expect(events.single.payload.route, '/bayi/orders/12');
        expect(events.single.payload.type, 'order.finance_approved');

        // Aynı süreçte ikinci kez okunmaz.
        final again = await start();
        expect(again, isEmpty);
      },
    );

    test(
      'FCM\'in ilk mesajı ve arka planda dokunulan push: dokunuş olayı',
      () async {
        fcm.initial = businessPush(notificationId: 9);
        final events = await start();
        fcm.opened.add(businessPush(notificationId: 10));
        await pumpEventQueue();
        expect(events.map((e) => e.origin), [PushOrigin.tap, PushOrigin.tap]);
        expect(events.map((e) => e.payload.notificationId), [9, 10]);
        expect(plugin.shown, isEmpty, reason: 'dokunuş bildirim göstermez');
      },
    );
  });

  test(
    'çıkış: bildirim merkezindeki kopyalar kaldırılır (cancelAll eklentiye gider)',
    () async {
      await start();
      await LocalNotifications.cancelAll();
      expect(plugin.cancelAllCalls, 1);
    },
  );
}

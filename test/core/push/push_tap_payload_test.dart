// Yerel bildirim kopyasının dokunuş verisi ve bayinin yeni "Yeni sipariş" olayı.
//
// - Veri push'un JSON'udur (rota, olay, satır, varlık, kategori, başlık, metin); eski bildirimlerde (bildirim
//   merkezinde kalmış olabilir) düz rota — ikisi de okunur, biçimsiz veri gelen kutusuna düşer.
// - Kopyanın kimliği gelen kutusu satırından kararlıdır; satırsız push için içerikten kararlı özet. İki
//   aralık da negatiftir: diğer yerel bildirimlerin kimlikleriyle (0 ve üstü) çakışmaz.
// - Finans kapısı açıkken bayiye ilk push `order.finance_approved` ("Yeni sipariş: …", rota
//   `/bayi/orders/{id}`): `order.created` gibi teklif bloğunu açar ve Bildirimler'de "Teklif ver" der —
//   teklif veremeyen için bilgidir; müşterinin finans onayı ve başka rota odaksızdır.
import 'package:akaryakitnet/core/push/local_notifications.dart';
import 'package:akaryakitnet/core/push/push_focus.dart';
import 'package:akaryakitnet/core/push/push_payload.dart';
import 'package:akaryakitnet/core/routing/route_access.dart';
import 'package:akaryakitnet/features/notifications/application/notification_display.dart';
import 'package:akaryakitnet/features/notifications/data/notification_models.dart';
import 'package:flutter_test/flutter_test.dart';

UserNotification _n(String code, String route) => UserNotification(
  id: 1,
  category: 'orders',
  eventCode: code,
  title: 'Yeni sipariş: SIP-20261102-12',
  body: 'Marmara İnşaat · Motorin 30.000 L — finans onaylı, teklif bekliyor.',
  route: route,
  createdAt: DateTime.utc(2026, 11, 2, 9),
);

void main() {
  group('dokunuş verisi', () {
    test('yeni biçim: push verisi gidip gelir (varış zamanı dokunuşta)', () {
      const p = PushPayload(
        type: 'order.finance_approved',
        notificationId: 4711,
        route: '/bayi/orders/12',
        entityType: 'Order',
        entityId: 12,
        category: 'orders',
        title: 'Yeni sipariş: SIP-20261102-12',
        body: 'Marmara İnşaat · teklif bekliyor.',
      );
      final raw = p.toLocalPayload();
      expect(raw, startsWith('{'));
      final back = PushPayload.fromLocalPayload(raw);
      expect(back.type, p.type);
      expect(back.notificationId, p.notificationId);
      expect(back.route, p.route);
      expect(back.entityType, p.entityType);
      expect(back.entityId, p.entityId);
      expect(back.category, p.category);
      expect(back.title, p.title);
      expect(back.body, p.body);
      expect(back.receivedAt, isNotNull);
      // Eksik alanlar yazılmaz; okunurken null.
      final bare = PushPayload.fromLocalPayload(
        const PushPayload(route: '/orders/5').toLocalPayload(),
      );
      expect(bare.route, '/orders/5');
      expect(bare.type, isNull);
      expect(bare.notificationId, isNull);
    });

    test(
      'eski biçim: düz rota olduğu gibi; boş ve biçimsiz veri gelen kutusuna',
      () {
        final old = PushPayload.fromLocalPayload('/orders/12002');
        expect(old.route, '/orders/12002');
        expect(old.type, isNull);
        expect(old.receivedAt, isNotNull);
        expect(
          PushPayload.fromLocalPayload('/bayi/orders/12?focus=quote').route,
          '/bayi/orders/12?focus=quote',
        );
        for (final raw in [null, '', '   ', '{bozuk', '{"route": 5']) {
          expect(
            RouteAccess.sanitizePushRoute(
              PushPayload.fromLocalPayload(raw).route,
            ),
            '/notifications',
            reason: '$raw',
          );
        }
        // JSON'da rota yoksa da gelen kutusu.
        expect(
          RouteAccess.sanitizePushRoute(
            PushPayload.fromLocalPayload('{"type":"system.test"}').route,
          ),
          '/notifications',
        );
      },
    );
  });

  group('kopya kimliği', () {
    test(
      'satırın eksisi: kararlı; farklı satır farklı kimlik; hepsi negatif',
      () {
        int id(int row) =>
            LocalNotifications.pushIdOf(PushPayload(notificationId: row));
        expect(id(1), -1);
        expect(id(4711), -4711);
        expect(id(4711), id(4711));
        expect(id(4711), isNot(id(4712)));
        // Olay ve metin kimliği değiştirmez (aynı satırın yeniden denemesi kendi kopyasının yerine geçer).
        expect(
          LocalNotifications.pushIdOf(
            const PushPayload(
              notificationId: 4711,
              type: 'order.approved',
              title: 'Başka metin',
            ),
          ),
          -4711,
        );
        for (final row in [1, 2, 999999, 0x3FFFFFFF, 0x40000000, 0x7FFFFFFF]) {
          expect(id(row), inInclusiveRange(-0x40000000, -1), reason: '$row');
        }
      },
    );

    test(
      'özet push (sunucuda daraltılır): tek kimlik, yenisi eskisinin yerine geçer',
      () {
        const a = PushPayload(
          type: LocalNotifications.summaryType,
          notificationId: 9001,
          route: '/notifications',
          title: '12 yeni bildirim',
          body: 'Bildirimler sayfasında.',
        );
        const b = PushPayload(
          type: LocalNotifications.summaryType,
          notificationId: 9050,
          route: '/notifications',
          title: '13 yeni bildirim',
          body: 'Bildirimler sayfasında.',
        );
        expect(LocalNotifications.pushIdOf(a), -0x40000001);
        expect(LocalNotifications.pushIdOf(b), LocalNotifications.pushIdOf(a));
      },
    );

    test(
      'satırsız push: içerikten kararlı özet, satır ve özet kimliklerinin dışında; içerik değişince '
      'değişir',
      () {
        const a = PushPayload(
          type: 'shipment.dispatched',
          route: '/shipments/7',
          title: 'Sevkiyat yola çıktı',
          body: '34 ABC 123 yolda.',
        );
        const b = PushPayload(
          type: 'shipment.dispatched',
          route: '/shipments/7',
          title: 'Sevkiyat yola çıktı',
          body: '34 ABC 124 yolda.',
        );
        final ia = LocalNotifications.pushIdOf(a);
        expect(ia, LocalNotifications.pushIdOf(a));
        expect(ia, isNot(LocalNotifications.pushIdOf(b)));
        for (final p in [
          a,
          b,
          const PushPayload(),
          const PushPayload(notificationId: 0),
          const PushPayload(notificationId: -5),
        ]) {
          expect(
            LocalNotifications.pushIdOf(p),
            inInclusiveRange(-0x7FFFFFFF, -0x40000002),
            reason: '$p',
          );
        }
      },
    );
  });

  group('bayinin "Yeni sipariş"i: order.finance_approved', () {
    test('push dokunuşu ve balon: teklif verebilene teklif bloğu', () {
      expect(
        withPushFocus('/bayi/orders/12', 'order.finance_approved'),
        '/bayi/orders/12?focus=quote',
      );
      expect(
        withPushFocus(
          '/bayi/orders/12',
          'order.finance_approved',
          canQuote: false,
        ),
        '/bayi/orders/12',
      );
      // Müşterinin finans onayı bilgi verir (teklif bloğu müşteride "Teklif hazır"la açılır).
      expect(
        withPushFocus('/orders/12', 'order.finance_approved'),
        '/orders/12',
      );
      expect(
        withPushFocus('/notifications', 'order.finance_approved'),
        '/notifications',
      );
      // Rotada odak zaten varsa korunur.
      expect(
        withPushFocus(
          '/bayi/orders/12?focus=history',
          'order.finance_approved',
        ),
        '/bayi/orders/12?focus=history',
      );
      // order.created aynı kalır.
      expect(
        withPushFocus('/bayi/orders/12', 'order.created'),
        '/bayi/orders/12?focus=quote',
      );
    });

    test('Bildirimler: "Teklif ver" ve satıra dokunuş teklif bloğunu açar', () {
      final bayi = _n('order.finance_approved', '/bayi/orders/12');
      expect(NotificationDisplay.actionOf(bayi), 'Teklif ver');
      expect(NotificationDisplay.actionOf(bayi, canQuote: false), isNull);
      expect(NotificationDisplay.focusOf(bayi), 'quote');
      expect(
        NotificationDisplay.withFocus(bayi, '/bayi/orders/12'),
        '/bayi/orders/12?focus=quote',
      );
      final customer = _n('order.finance_approved', '/orders/12');
      expect(NotificationDisplay.actionOf(customer), isNull);
      expect(NotificationDisplay.focusOf(customer), isNull);
      expect(
        NotificationDisplay.withFocus(customer, '/orders/12'),
        '/orders/12',
      );
      // order.created aynı kalır.
      expect(
        NotificationDisplay.actionOf(_n('order.created', '/bayi/orders/12')),
        'Teklif ver',
      );
    });
  });
}

// v4 tur 2 (A9, B17): bildirimin eylem satırı "yeni" değil "sıra sizde" demektir — okunduktan sonra
// da iş görüntüleyeni bekliyorsa kalır; bayinin "Yeni sipariş"i "Teklif ver" der ve dokunuş teklif
// bloğunu açar (`?focus=quote`).
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/notifications/application/notification_display.dart';
import 'package:akaryakitnet/features/notifications/data/notification_models.dart';
import 'package:akaryakitnet/features/notifications/presentation/widgets/notification_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

UserNotification _n(String code, String route, {bool read = false}) =>
    UserNotification(
      id: 1,
      category: 'orders',
      eventCode: code,
      title: 'Başlık',
      body: 'Metin',
      route: route,
      createdAt: DateTime.utc(2026, 10, 29, 6),
      readAt: read ? DateTime.utc(2026, 10, 29, 7) : null,
    );

Future<void> _pumpTile(
  WidgetTester tester,
  UserNotification n, {
  bool waiting = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AknTheme.light(),
      home: Scaffold(
        body: AknLedger(
          children: [
            NotificationTile(
              notification: n,
              waiting: waiting,
              onTap: () {},
              onMarkRead: () {},
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('eylem ve odak', () {
    test('bayinin "Yeni sipariş"i: "Teklif ver" (B17)', () {
      expect(
        NotificationDisplay.actionOf(_n('order.created', '/bayi/orders/12009')),
        'Teklif ver',
      );
      // Rota bayi siparişi değilse eylem yok.
      expect(
        NotificationDisplay.actionOf(_n('order.created', '/orders/12009')),
        isNull,
      );
      // Teklif veremeyen (izleyici) için "Yeni sipariş" bilgidir: eylemsiz sayfaya çağırmaz.
      expect(
        NotificationDisplay.actionOf(
          _n('order.created', '/bayi/orders/12009'),
          canQuote: false,
        ),
        isNull,
      );
    });

    // v4 tur 2 (M3): saha temsilcisinin "Ön kayıt ek bilgi istendi" bildirimi (sunucu: uyarı tonu,
    // rota ön kaydın kendisi) "Bilgi gönder" der; onay, ret ve dönüşüm bilgi verir.
    test(
      'ön kayıt için ek bilgi: "Bilgi gönder"; diğer ön kayıt olayları bilgi',
      () {
        UserNotification lead(int severity) => UserNotification(
          id: 2,
          category: 'field',
          eventCode: 'lead.updated',
          title: 'Ön kayıt ek bilgi istendi',
          body: 'Başkent Yapı Market ön kaydı için finans ek bilgi istedi.',
          severity: severity,
          route: '/field/leads/8001',
          createdAt: DateTime.utc(2026, 10, 29, 6),
        );
        expect(NotificationDisplay.actionOf(lead(2)), 'Bilgi gönder');
        expect(NotificationDisplay.actionOf(lead(1)), isNull);
        expect(NotificationDisplay.actionOf(lead(3)), isNull);
      },
    );

    test('dokunuş eylemin bloğunu açar (?focus=)', () {
      String? focus(String code, String route) =>
          NotificationDisplay.focusOf(_n(code, route));
      expect(focus('order.created', '/bayi/orders/12009'), 'quote');
      expect(focus('order.quote_ready', '/orders/12002'), 'quote');
      expect(focus('shipment.reported', '/shipments/5003'), 'delivery');
      expect(focus('approval.pending', '/approvals/9003'), 'request');
      // Bilgi veren olay: odak yok.
      expect(focus('shipment.dispatched', '/orders/12003'), isNull);
      final n = _n('order.created', '/bayi/orders/12009');
      expect(
        NotificationDisplay.withFocus(n, '/bayi/orders/12009'),
        '/bayi/orders/12009?focus=quote',
      );
      // Rotada odak zaten varsa korunur.
      expect(
        NotificationDisplay.withFocus(n, '/bayi/orders/12009?focus=history'),
        '/bayi/orders/12009?focus=history',
      );
    });
  });

  group('okunmuş bildirimde eylem satırı (A9)', () {
    testWidgets('iş hâlâ bekliyorsa okunmuş satırda da kalır', (tester) async {
      await _pumpTile(
        tester,
        _n('order.quote_ready', '/orders/12002', read: true),
        waiting: true,
      );
      expect(find.byKey(NotificationTile.actionKey), findsOneWidget);
      expect(find.text('Teklifi aç'), findsOneWidget);
      // Okunmuş: nokta yok (tek turuncu işaret okunmamışlık içindir).
      expect(find.byKey(NotificationTile.unreadDotKey), findsNothing);
    });

    testWidgets('iş artık beklemiyorsa okununca katlanır', (tester) async {
      await _pumpTile(
        tester,
        _n('order.quote_ready', '/orders/12002', read: true),
      );
      expect(find.byKey(NotificationTile.actionKey), findsNothing);
    });

    testWidgets('okunmamışken her zaman', (tester) async {
      await _pumpTile(tester, _n('order.created', '/bayi/orders/12009'));
      expect(find.text('Teklif ver'), findsOneWidget);
      expect(find.byKey(NotificationTile.unreadDotKey), findsOneWidget);
    });

    test('bilgi veren olayın eylemi yok, beklese de', () {
      expect(
        NotificationTile.actionFor(
          _n('shipment.dispatched', '/orders/12003', read: true),
          waiting: true,
        ),
        isNull,
      );
    });
  });
}

// Bildirimler (spec A.4 A8, B.4): sayfalama, okunmamış süzgeci, okundu işaretleme (iyimser, rozet),
// tümünü okundu say, derin bağlantı (erişim yoksa burada kalır), kaydırınca okundu, tercihler,
// test bildirimi, boş / çevrimdışı durumlar, erişilebilirlik (C.7).
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/env/app_config_controller.dart';
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/push/unread_count_provider.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:akaryakitnet/features/notifications/application/inbox_controller.dart';
import 'package:akaryakitnet/features/notifications/application/preferences_controller.dart';
import 'package:akaryakitnet/features/notifications/data/notification_models.dart';
import 'package:akaryakitnet/features/notifications/presentation/notifications_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../profile/a8_kit.dart';

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 400 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// Personaya [n] adet bildirim ekler (yeni önce).
void seed(
  A8Harness h,
  String persona,
  int n, {
  String route = '/orders/12',
  DateTime? from,
}) {
  // Sahte dünyanın tohum bildirimleri gerçek saate göre (ör. "30 dk önce") üretilir; testin
  // bildirimleri her zaman en yenisi olsun diye varsayılan an gerçek "şimdi"dir (a8Now sabit bir
  // sabah saatidir; gün ilerleyince tohumlar ondan yeni kalıyordu).
  final start = from ?? DateTime.now().toUtc();
  for (var i = n - 1; i >= 0; i--) {
    h.server.world.addNotification(
      userId: 'u-$persona',
      category: NotificationCategory.quotes,
      eventCode: 'order.quote_ready',
      title: 'Teklif hazır $i',
      body: 'AYN-$i için teklif verildi.',
      route: route,
      entityType: 'Order',
      entityId: 12,
      at: start.subtract(Duration(minutes: i)),
    );
  }
}

int unreadOf(A8Harness h, String persona) =>
    h.server.world.unreadNotifications('u-$persona');

Future<ProviderContainer> signedInContainer(A8Harness h, String persona) async {
  final c = h.container();
  await c.read(appConfigProvider.notifier).load();
  await c
      .read(sessionControllerProvider.notifier)
      .loginWithPassword(persona, 'demo');
  return c;
}

void main() {
  group('model', () {
    test('UserNotificationDto: UTC tarihler, okunmamış, etiket ve ton', () {
      final n = UserNotification.fromJson(
        JsonReader.of({
          'id': 7,
          'category': 'shipments',
          'categoryLabel': 'Teslimatlar',
          'eventCode': 'shipment.reported',
          'title': 'Teslimatı onaylayın',
          'body': 'AYN-1 için teslim bildirildi.',
          'severity': 2,
          'route': '/shipments/3',
          'entityType': 'Shipment',
          'entityId': 3,
          'createdAt': '2026-10-21T07:00:00+00:00',
          'readAt': null,
        }),
      );
      expect(n.isRead, isFalse);
      expect(n.createdAt, DateTime.utc(2026, 10, 21, 7));
      expect(n.label, 'Teslimatlar');
      expect(n.route, '/shipments/3');
      expect(n.markedRead(DateTime.utc(2026)).isRead, isTrue);
    });

    test('gün başlıkları: Bugün, Dün, gün adı, tarih', () {
      final now = TrTime.fromWall(2026, 10, 21, 10);
      expect(dayLabel(TrTime.fromWall(2026, 10, 21, 1), now: now), 'Bugün');
      expect(dayLabel(TrTime.fromWall(2026, 10, 20, 23), now: now), 'Dün');
      expect(dayLabel(TrTime.fromWall(2026, 10, 18, 9), now: now), 'Pazar');
      expect(dayLabel(TrTime.fromWall(2026, 10, 2, 9), now: now), '2 Ekim');
      expect(
        dayLabel(TrTime.fromWall(2025, 12, 30, 9), now: now),
        '30 Aralık 2025',
      );
    });
  });

  group('gelen kutusu denetleyicisi', () {
    test(
      'ilk sayfa 25, devamı sonsuz kaydırmayla; okunmamış süzgeci',
      () async {
        final h = await A8Harness.create();
        seed(h, 'onay', 40);
        final c = await signedInContainer(h, 'onay');
        addTearDown(c.dispose);
        c.listen(inboxControllerProvider, (_, _) {});
        await until(() => !c.read(inboxControllerProvider).loading);
        var s = c.read(inboxControllerProvider);
        expect(s.items, hasLength(25));
        expect(s.hasMore, isTrue);
        expect(s.items.first.title, 'Teklif hazır 0', reason: 'yeni önce');

        await c.read(inboxControllerProvider.notifier).loadMore();
        s = c.read(inboxControllerProvider);
        expect(s.items.length, s.totalCount);
        expect(s.hasMore, isFalse);

        // Bir tanesini okundu yap, sonra "Okunmamış".
        await c
            .read(inboxControllerProvider.notifier)
            .markRead(s.items.first.id);
        await c.read(inboxControllerProvider.notifier).setUnreadOnly(true);
        await until(() => !c.read(inboxControllerProvider).loading);
        s = c.read(inboxControllerProvider);
        expect(s.unreadOnly, isTrue);
        expect(s.items.every((n) => !n.isRead), isTrue);
        expect(s.totalCount, unreadOf(h, 'onay'));
      },
    );

    test('okundu işaretleme: iyimser, sunucuya gider, rozet düşer', () async {
      final h = await A8Harness.create();
      seed(h, 'onay', 3);
      final c = await signedInContainer(h, 'onay');
      addTearDown(c.dispose);
      c.listen(inboxControllerProvider, (_, _) {});
      await until(() => !c.read(inboxControllerProvider).loading);
      await c.read(unreadCountProvider.notifier).refresh();
      final before = c.read(unreadCountProvider).notifications;
      final first = c.read(inboxControllerProvider).items.first;
      final f = await c
          .read(inboxControllerProvider.notifier)
          .markRead(first.id);
      expect(f, isNull);
      expect(c.read(inboxControllerProvider).items.first.isRead, isTrue);
      expect(c.read(unreadCountProvider).notifications, before - 1);
      expect(h.notifications.readCalls, 1);
      expect(unreadOf(h, 'onay'), before - 1);
    });

    test('okundu işaretleme hatası: geri alınır', () async {
      final h = await A8Harness.create();
      seed(h, 'onay', 2);
      final c = await signedInContainer(h, 'onay');
      addTearDown(c.dispose);
      c.listen(inboxControllerProvider, (_, _) {});
      await until(() => !c.read(inboxControllerProvider).loading);
      final first = c.read(inboxControllerProvider).items.first;
      h.server.failureMode = FakeFailureMode.serverError;
      final f = await c
          .read(inboxControllerProvider.notifier)
          .markRead(first.id);
      h.server.failureMode = FakeFailureMode.none;
      expect(f, isNotNull);
      expect(c.read(inboxControllerProvider).items.first.isRead, isFalse);
    });

    test('tümünü okundu say: liste ve rozet sıfırlanır', () async {
      final h = await A8Harness.create();
      seed(h, 'onay', 5);
      final c = await signedInContainer(h, 'onay');
      addTearDown(c.dispose);
      c.listen(inboxControllerProvider, (_, _) {});
      await until(() => !c.read(inboxControllerProvider).loading);
      await c.read(unreadCountProvider.notifier).refresh();
      expect(c.read(unreadCountProvider).notifications, greaterThan(0));
      final f = await c.read(inboxControllerProvider.notifier).markAllRead();
      expect(f, isNull);
      expect(c.read(inboxControllerProvider).unreadCount, 0);
      await until(() => c.read(unreadCountProvider).notifications == 0);
      expect(c.read(unreadCountProvider).notifications, 0);
      expect(unreadOf(h, 'onay'), 0);
    });

    test('artık olmayan bildirim (404) listeden çıkar', () async {
      final h = await A8Harness.create();
      seed(h, 'onay', 2);
      final c = await signedInContainer(h, 'onay');
      addTearDown(c.dispose);
      c.listen(inboxControllerProvider, (_, _) {});
      await until(() => !c.read(inboxControllerProvider).loading);
      final first = c.read(inboxControllerProvider).items.first;
      h.server.world.notifications.removeWhere((n) => n['id'] == first.id);
      final f = await c
          .read(inboxControllerProvider.notifier)
          .markRead(first.id);
      expect(f, isNull);
      expect(
        c.read(inboxControllerProvider).items.any((n) => n.id == first.id),
        isFalse,
      );
    });

    test('çevrimdışı: son kaydedilen ilk sayfa gösterilir', () async {
      final h = await A8Harness.create();
      seed(h, 'onay', 3);
      final c = await signedInContainer(h, 'onay');
      addTearDown(c.dispose);
      final sub = c.listen(inboxControllerProvider, (_, _) {});
      await until(() => !c.read(inboxControllerProvider).loading);
      final count = c.read(inboxControllerProvider).items.length;
      sub.close();
      await until(() => !c.exists(inboxControllerProvider));
      h.server.failureMode = FakeFailureMode.offline;
      c.listen(inboxControllerProvider, (_, _) {});
      await until(() => !c.read(inboxControllerProvider).loading);
      final s = c.read(inboxControllerProvider);
      expect(s.fromCache, isTrue);
      expect(s.items, hasLength(count));
      h.server.failureMode = FakeFailureMode.none;
    });
  });

  group('tercihler', () {
    test(
      'kategori anahtarı PUT ile kaydedilir; görüntüleyicide sipariş/teklif kapalı',
      () async {
        final h = await A8Harness.create();
        final c = await signedInContainer(h, 'izleyici');
        addTearDown(c.dispose);
        c.listen(preferencesControllerProvider, (_, _) {});
        await until(() => !c.read(preferencesControllerProvider).loading);
        var items = c.read(preferencesControllerProvider).items;
        expect(items.map((p) => p.category), NotificationCategory.all);
        bool on(String cat) => c
            .read(preferencesControllerProvider)
            .items
            .firstWhere((p) => p.category == cat)
            .pushEnabled;
        expect(on('orders'), isFalse);
        expect(on('quotes'), isFalse);
        expect(on('shipments'), isTrue);
        final f = await c
            .read(preferencesControllerProvider.notifier)
            .toggle('shipments', false);
        expect(f, isNull);
        expect(on('shipments'), isFalse);
        // Sunucu kaydetti mi: yeniden okunur.
        await c.read(preferencesControllerProvider.notifier).reload();
        expect(on('shipments'), isFalse);
        items = c.read(preferencesControllerProvider).items;
        expect(
          items.firstWhere((p) => p.category == 'payments').label,
          'Ödemeler',
        );
      },
    );

    test('kaydetme hatasında anahtar geri döner', () async {
      final h = await A8Harness.create();
      final c = await signedInContainer(h, 'musteri');
      addTearDown(c.dispose);
      c.listen(preferencesControllerProvider, (_, _) {});
      await until(() => !c.read(preferencesControllerProvider).loading);
      h.server.failureMode = FakeFailureMode.serverError;
      final f = await c
          .read(preferencesControllerProvider.notifier)
          .toggle('quotes', false);
      h.server.failureMode = FakeFailureMode.none;
      expect(f, isNotNull);
      expect(
        c
            .read(preferencesControllerProvider)
            .items
            .firstWhere((p) => p.category == 'quotes')
            .pushEnabled,
        isTrue,
      );
    });
  });

  group('ekran', () {
    setUp(fixClock);

    a11yMatrix('bildirimler', (tester, scale, b) async {
      fixClock();
      final h = await A8Harness.create();
      seed(h, 'onay', 6);
      await pumpA8(
        tester,
        '/notifications',
        harness: h,
        persona: 'onay',
        textScale: scale,
        brightness: b,
      );
      expect(find.text('Bildirimler'), findsWidgets);
      expect(find.text('Bugün'), findsOneWidget);
    });

    a11yMatrix('bildirim ayarları', (tester, scale, b) async {
      await pumpA8(
        tester,
        '/notifications/settings',
        textScale: scale,
        brightness: b,
      );
      expect(find.text('Anlık bildirimler kapalı'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Teklifler'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(find.text('Teklifler'), findsOneWidget);
    });

    testWidgets('dokununca okundu olur ve rotasına gider', (tester) async {
      setPhoneSize(tester);
      final h = await A8Harness.create();
      seed(h, 'onay', 1, route: '/orders/77');
      final c = await pumpA8(
        tester,
        '/notifications',
        harness: h,
        persona: 'onay',
      );
      await tester.tap(find.text('Teklif hazır 0'));
      await pumpFor(tester, const Duration(milliseconds: 800));
      expect(find.text('SİPARİŞ 77'), findsOneWidget);
      expect(h.notifications.readCalls, 1);
      expect(c.read(inboxControllerProvider).items.first.isRead, isTrue);
      await finish(tester);
    });

    testWidgets('erişilemeyen rota: sayfada kalır ve açıklar', (tester) async {
      setPhoneSize(tester);
      final h = await A8Harness.create();
      // Müşteri bayi sipariş sayfasını açamaz (RouteAccess).
      seed(h, 'onay', 1, route: '/bayi/orders/5');
      await pumpA8(tester, '/notifications', harness: h, persona: 'onay');
      await tester.tap(find.text('Teklif hazır 0'));
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.text('BAYİ SİPARİŞ 5'), findsNothing);
      expect(
        find.text('Bu bildirimin sayfası hesabınızda açık değil.'),
        findsOneWidget,
      );
      await finish(tester);
    });

    testWidgets('sağa kaydırınca okundu olur, satır yerinde kalır', (
      tester,
    ) async {
      setPhoneSize(tester);
      final h = await A8Harness.create();
      seed(h, 'onay', 2);
      final c = await pumpA8(
        tester,
        '/notifications',
        harness: h,
        persona: 'onay',
      );
      final unread = unreadOf(h, 'onay');
      await tester.drag(find.text('Teklif hazır 0'), const Offset(260, 0));
      await pumpFor(tester, const Duration(milliseconds: 800));
      expect(find.text('Teklif hazır 0'), findsOneWidget);
      expect(unreadOf(h, 'onay'), unread - 1);
      final n = c
          .read(inboxControllerProvider)
          .items
          .firstWhere((x) => x.title == 'Teklif hazır 0');
      expect(n.isRead, isTrue);
      await finish(tester);
    });

    testWidgets('tümünü okundu say + "Okunmamış" boş durumu', (tester) async {
      setPhoneSize(tester);
      final h = await A8Harness.create();
      seed(h, 'onay', 3);
      await pumpA8(tester, '/notifications', harness: h, persona: 'onay');
      await tester.tap(find.byTooltip('Tümünü okundu say'));
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(unreadOf(h, 'onay'), 0);
      await tester.tap(find.text('Okunmamış'));
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.text('Okunmamış bildiriminiz yok'), findsOneWidget);
      await tester.tap(find.text('Tümünü göster'));
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.text('Teklif hazır 0'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('hiç bildirim yoksa boş durum', (tester) async {
      setPhoneSize(tester);
      final h = await A8Harness.create();
      h.server.world.notifications.clear();
      await pumpA8(tester, '/notifications', harness: h, persona: 'onay');
      expect(find.text('Henüz bildiriminiz yok'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('ayarlar: anahtar ve test bildirimi', (tester) async {
      setPhoneSize(tester, const Size(390, 844));
      final h = await A8Harness.create();
      await pumpA8(
        tester,
        '/notifications/settings',
        harness: h,
        persona: 'musteri',
      );
      final before = unreadOf(h, 'musteri');
      final teklif = find.ancestor(
        of: find.text('Teklifler'),
        matching: find.byType(InkWell),
      );
      await tester.tap(teklif.first);
      await pumpFor(tester, const Duration(milliseconds: 400));
      final sw = tester.widget<Switch>(
        find.descendant(of: teklif.first, matching: find.byType(Switch)),
      );
      expect(sw.value, isFalse);
      await tester.scrollUntilVisible(
        find.text('Gönder'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tapVisible(tester, find.text('Gönder'));
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(
        find.text(
          'Test bildirimi bildirim kutunuza eklendi. Bu cihazda anlık bildirim açık değil.',
        ),
        findsOneWidget,
      );
      expect(unreadOf(h, 'musteri'), before + 1);
      await finish(tester);
    });
  });
}

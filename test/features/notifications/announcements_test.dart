// Merkez duyuruları (yönetim paneli: Yönetim > Push bildirimleri): sunucu her alıcıya
// `system.announcement.<tür>` olay kodlu, rotasız bir gelen kutusu satırı yazar ve push gönderir.
// Bildirimler'de megafon simgesi ve tür etiketiyle görünür; dokununca tam metin alttan açılır; duyuru
// push'una dokunan kişi Bildirimler'e gelir ve aynı sayfa kendiliğinden açılır. Demo dünyasında her
// personanın gelen kutusunda bir (okunmuş) duyuru vardır.
import 'dart:async';

import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/app/fakes.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/env/app_config_controller.dart';
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/models/paged_result.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/push/push_payload.dart';
import 'package:akaryakitnet/core/push/push_providers.dart';
import 'package:akaryakitnet/core/push/push_service.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:akaryakitnet/features/notifications/application/announcements.dart';
import 'package:akaryakitnet/features/notifications/application/inbox_controller.dart';
import 'package:akaryakitnet/features/notifications/data/notification_models.dart';
import 'package:akaryakitnet/features/notifications/data/notifications_repository.dart';
import 'package:akaryakitnet/features/notifications/notifications_fake.dart';
import 'package:akaryakitnet/features/notifications/presentation/notifications_page.dart';
import 'package:akaryakitnet/features/notifications/presentation/widgets/announcement_sheet.dart';
import 'package:akaryakitnet/features/notifications/presentation/widgets/notification_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';
import '../profile/a8_kit.dart';

const _long =
    'Cumhuriyet Bayramı nedeniyle 29 Ekim Perşembe günü teslimatlar 14:00\'e kadar '
    'yapılacaktır. Siparişlerinizi bir gün önceden vermenizi öneririz. Sorularınız için '
    'bayinizi arayabilirsiniz. Bayramınızı kutlarız.';

/// [persona]nın gelen kutusuna sunucunun yazdığı gibi bir duyuru satırı ekler (en yeni).
JsonMap _announce(
  FakeWorld w,
  String persona, {
  String code = 'system.announcement.announcement',
  String title = 'Bayram çalışma saatleri',
  String body = _long,
  int severity = 0,
  bool read = false,
}) => w.addNotification(
  userId: 'u-$persona',
  category: NotificationCategory.system,
  eventCode: code,
  title: title,
  body: body,
  severity: severity,
  entityType: 'PushCampaign',
  entityId: 41,
  read: read,
);

/// Satırın push'una dokunuş (sunucunun push verisi: rota `/notifications`).
PushEvent _tapOn(
  JsonMap row, {
  PushOrigin origin = PushOrigin.tap,
  DateTime? at,
}) => PushEvent(
  PushPayload(
    type: row['eventCode'] as String,
    notificationId: row['id'] as int,
    route: '/notifications',
    entityType: 'PushCampaign',
    entityId: 41,
    category: NotificationCategory.system,
    title: row['title'] as String,
    body: row['body'] as String,
    receivedAt: at ?? DateTime.now().toUtc(),
  ),
  origin,
);

PushEvent _event({
  String? type = 'system.announcement.campaign',
  int? id = 7,
  PushOrigin origin = PushOrigin.tap,
  DateTime? at,
}) => PushEvent(
  PushPayload(
    type: type,
    notificationId: id,
    route: '/notifications',
    title: 'Hafta sonu kampanyası',
    body: 'Cumartesi ve pazar teslimatlarında indirim.',
    receivedAt: at ?? DateTime.now().toUtc(),
  ),
  origin,
);

Finder get _sheet => find.byKey(AnnouncementBody.bodyKey);

Finder _inSheet(String text) =>
    find.descendant(of: _sheet, matching: find.text(text));

Future<void> _pumpTile(WidgetTester tester, UserNotification n) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AknTheme.light(),
      home: Scaffold(
        body: AknLedger(
          children: [
            NotificationTile(notification: n, onTap: () {}, onMarkRead: () {}),
          ],
        ),
      ),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
}

/// Push olaylarını testin verdiği uygulama (FCM yok): dokunuşlar koordinatöre ve
/// `pushEventsProvider`'a gerçek uygulamadaki gibi gider.
class _TapPush extends PushService {
  _TapPush() : super(available: false);

  final _taps = StreamController<PushEvent>.broadcast();

  @override
  Stream<PushEvent> get events => _taps.stream;

  void send(PushEvent e) => _taps.add(e);

  @override
  Future<void> dispose() async {
    await _taps.close();
    await super.dispose();
  }
}

void main() {
  group('tür ve tanıma', () {
    test(
      'olay kodu "system.announcement" ile başlayan her bildirim duyurudur',
      () {
        expect(Announcements.isEventCode('system.announcement'), isTrue);
        expect(
          Announcements.isEventCode('system.announcement.campaign'),
          isTrue,
        );
        expect(
          Announcements.isEventCode(' System.Announcement.Price '),
          isTrue,
        );
        expect(Announcements.isEventCode('system.test'), isFalse);
        expect(Announcements.isEventCode('system.summary'), isFalse);
        expect(Announcements.isEventCode('order.quote_ready'), isFalse);
        expect(Announcements.isEventCode(''), isFalse);
        expect(Announcements.isEventCode(null), isFalse);
      },
    );

    test(
      'tür: sunucunun İngilizce ya da Türkçe adı, ayırıcı ve büyük harf farkı, panel sırası; '
      'bilinmeyen "Duyuru"',
      () {
        AnnouncementKind kind(String suffix) =>
            Announcements.kindOf('system.announcement$suffix');
        const cases = {
          '.general': AnnouncementKind.general,
          '.genel': AnnouncementKind.general,
          '.Genel': AnnouncementKind.general,
          '.announcement': AnnouncementKind.notice,
          '.duyuru': AnnouncementKind.notice,
          '.notice': AnnouncementKind.notice,
          '': AnnouncementKind.notice,
          '.': AnnouncementKind.notice,
          '.something_else': AnnouncementKind.notice,
          '.campaign': AnnouncementKind.campaign,
          '.kampanya': AnnouncementKind.campaign,
          '.Promo': AnnouncementKind.campaign,
          '.maintenance': AnnouncementKind.maintenance,
          '.bakim': AnnouncementKind.maintenance,
          '.Bakım-Kesinti': AnnouncementKind.maintenance,
          '.bakim_kesinti': AnnouncementKind.maintenance,
          '.kesinti': AnnouncementKind.maintenance,
          '.outage': AnnouncementKind.maintenance,
          '.price': AnnouncementKind.price,
          '.price_update': AnnouncementKind.price,
          '.priceUpdate': AnnouncementKind.price,
          '.fiyat': AnnouncementKind.price,
          '.fiyat-guncellemesi': AnnouncementKind.price,
          '.Fiyat güncellemesi': AnnouncementKind.price,
          '.0': AnnouncementKind.general,
          '.1': AnnouncementKind.notice,
          '.2': AnnouncementKind.campaign,
          '.3': AnnouncementKind.maintenance,
          '.4': AnnouncementKind.price,
          '.9': AnnouncementKind.notice,
        };
        cases.forEach((suffix, expected) {
          expect(kind(suffix), expected, reason: suffix);
        });
        // Duyuru olmayan kod: genel "Duyuru".
        expect(Announcements.kindOf('order.created'), AnnouncementKind.notice);
        // Paneldeki adlar.
        expect(AnnouncementKind.values.map((k) => k.label), [
          'Genel',
          'Duyuru',
          'Kampanya',
          'Bakım / Kesinti',
          'Fiyat güncellemesi',
        ]);
      },
    );

    test(
      'tercihlerde "Sistem" duyuruları anar (kapatılırsa duyuru push\'u gelmez, kutuda kalır)',
      () {
        expect(
          NotificationCategory.description(NotificationCategory.system),
          'Merkez duyuruları, kampanyalar ve hesap bildirimleri',
        );
      },
    );

    test('tam tarih: Türkiye saatiyle gün adı; başka yılda yılıyla', () {
      final now = DateTime.utc(2026, 10, 29, 12);
      expect(
        Announcements.fullDate(DateTime.utc(2026, 10, 29, 10, 10), now: now),
        '29 Ekim Perşembe, 13:10',
      );
      expect(
        Announcements.fullDate(DateTime.utc(2025, 12, 30, 6, 10), now: now),
        '30 Aralık 2025 Salı, 09:10',
      );
      // Gece yarısından sonra (UTC'de önceki gün) Türkiye'nin günü.
      expect(
        Announcements.fullDate(DateTime.utc(2026, 10, 28, 22, 5), now: now),
        '29 Ekim Perşembe, 01:05',
      );
    });

    test('push\'tan duyuru: kimlik ve metin gerekir; tür ve tarih korunur', () {
      final at = DateTime.utc(2026, 10, 29, 9);
      final n = Announcements.fromPush(
        PushPayload(
          type: 'system.announcement.maintenance',
          notificationId: 12,
          title: '  Planlı bakım ',
          body: 'Gece 02:00–04:00 arası.',
          entityType: 'PushCampaign',
          entityId: 3,
          receivedAt: at,
        ),
      )!;
      expect(n.id, 12);
      expect(n.title, 'Planlı bakım');
      expect(n.category, NotificationCategory.system);
      expect(n.createdAt, at);
      expect(Announcements.isAnnouncement(n), isTrue);
      expect(Announcements.kindOf(n.eventCode), AnnouncementKind.maintenance);
      expect(n.isRead, isFalse);
      expect(
        Announcements.fromPush(
          const PushPayload(type: 'system.announcement', title: 'Başlık'),
        ),
        isNull,
        reason: 'kimlik yok',
      );
      expect(
        Announcements.fromPush(
          const PushPayload(type: 'system.announcement', notificationId: 3),
        ),
        isNull,
        reason: 'metin yok',
      );
    });
  });

  group('push dokunuşu sağlayıcısı', () {
    ProviderContainer container(StreamController<PushEvent> events) {
      final c = ProviderContainer(
        overrides: [pushEventsProvider.overrideWith((ref) => events.stream)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test(
      'yalnızca duyuru push\'una dokunuş bekler (ön plan, başka olay, kimliksiz ve 10 dakikadan '
      'eski dokunuş beklemez); bekleyen dokunuşu sonraki olaylar silmez; bir kez alınır',
      () async {
        final events = StreamController<PushEvent>.broadcast();
        addTearDown(events.close);
        final c = container(events);
        c.listen(announcementTapProvider, (_, _) {});
        PushPayload? pending() => c.read(announcementTapProvider);
        expect(pending(), isNull);

        for (final e in [
          _event(origin: PushOrigin.foreground),
          _event(type: 'order.quote_ready'),
          _event(type: 'system.summary'),
          _event(type: null),
          _event(id: null),
          _event(
            at: DateTime.now().toUtc().subtract(const Duration(minutes: 11)),
          ),
        ]) {
          events.add(e);
          await pumpEventQueue();
          expect(pending(), isNull, reason: '${e.payload} ${e.origin}');
        }

        events.add(_event(id: 7));
        await pumpEventQueue();
        expect(pending()?.notificationId, 7);
        // Ardından gelen ön plan push'u bekleyen dokunuşu silmez.
        events.add(_event(id: 8, origin: PushOrigin.foreground));
        await pumpEventQueue();
        expect(pending()?.notificationId, 7);

        expect(
          c.read(announcementTapProvider.notifier).take()?.notificationId,
          7,
        );
        expect(pending(), isNull);
        expect(c.read(announcementTapProvider.notifier).take(), isNull);
      },
    );

    test(
      'sayfadan önce gelen dokunuş (soğuk açılış) ilk okumada alınır; aynı olay sağlayıcı yeniden '
      'kurulsa da ikinci kez açılmaz',
      () async {
        final events = StreamController<PushEvent>.broadcast();
        addTearDown(events.close);
        final c = container(events);
        // Uygulama push olaylarını açılıştan beri dinler (rozet sayacı).
        c.listen(pushEventsProvider, (_, _) {});
        events.add(_event(id: 9));
        await pumpEventQueue();

        c.listen(announcementTapProvider, (_, _) {});
        expect(c.read(announcementTapProvider)?.notificationId, 9);
        c.read(announcementTapProvider.notifier).take();

        c.invalidate(announcementTapProvider);
        expect(c.read(announcementTapProvider), isNull);

        // Yeni dokunuş yine açılır.
        events.add(_event(id: 10));
        await pumpEventQueue();
        expect(c.read(announcementTapProvider)?.notificationId, 10);
      },
    );

    test(
      'bekleyen dokunuş Bildirimler 10 dakikadan sonra açılırsa açılmaz ve silinir; süresi içinde '
      'alınan dokunuş açılır',
      () async {
        final real = TrTime.clock;
        addTearDown(() => TrTime.clock = real);
        final start = DateTime.utc(2026, 10, 29, 9);
        TrTime.clock = () => start;
        final events = StreamController<PushEvent>.broadcast();
        addTearDown(events.close);
        final c = container(events);
        c.listen(announcementTapProvider, (_, _) {});

        events.add(_event(id: 21, at: start));
        await pumpEventQueue();
        expect(c.read(announcementTapProvider)?.notificationId, 21);

        // Sayfa 11 dakika sonra açıldı: eski dokunuş kendiliğinden açılmaz.
        TrTime.clock = () => start.add(const Duration(minutes: 11));
        expect(c.read(announcementTapProvider.notifier).take(), isNull);
        expect(c.read(announcementTapProvider), isNull);

        // 9 dakikalık dokunuş hâlâ açılır.
        final later = start.add(const Duration(minutes: 12));
        TrTime.clock = () => later;
        events.add(_event(id: 22, at: later));
        await pumpEventQueue();
        TrTime.clock = () => later.add(const Duration(minutes: 9));
        expect(
          c.read(announcementTapProvider.notifier).take()?.notificationId,
          22,
        );
      },
    );
  });

  group('satır', () {
    testWidgets(
      'duyuru: megafon, metnin altında tür, yazıldığı gibi (kod temizlenmez); eylem satırı yok; '
      'ekran okuyucu türü de okur',
      (tester) async {
        final semantics = tester.ensureSemantics();
        await _pumpTile(
          tester,
          UserNotification(
            id: 1,
            category: NotificationCategory.system,
            eventCode: 'system.announcement.campaign',
            title: 'Kampanya kodu YAZ-25',
            body: 'YAZ-25 koduyla hafta sonu %5 indirim.',
            entityType: 'PushCampaign',
            entityId: 3,
            createdAt: DateTime.utc(2026, 10, 29, 6),
          ),
        );
        expect(find.byIcon(PhosphorIconsFill.megaphone), findsOneWidget);
        expect(find.byKey(NotificationTile.kindKey), findsOneWidget);
        expect(find.text('Kampanya'), findsOneWidget);
        final kind = tester.widget<Text>(find.byKey(NotificationTile.kindKey));
        final ctx = tester.element(find.byKey(NotificationTile.kindKey));
        expect(
          kind.style!.color,
          ctx.akn.dim,
          reason: 'soluk; hap ya da renk değil',
        );
        expect(find.text('Kampanya kodu YAZ-25'), findsOneWidget);
        expect(
          find.text('YAZ-25 koduyla hafta sonu %5 indirim.'),
          findsOneWidget,
        );
        expect(find.byKey(NotificationTile.actionKey), findsNothing);
        expect(find.byKey(NotificationTile.unreadDotKey), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            RegExp(r'^Okunmadı\. Kampanya\. Kampanya kodu YAZ-25\. YAZ-25'),
          ),
          findsOneWidget,
        );
        semantics.dispose();
      },
    );

    testWidgets('işlem bildiriminde tür satırı ve megafon yok', (tester) async {
      await _pumpTile(
        tester,
        UserNotification(
          id: 2,
          category: NotificationCategory.quotes,
          eventCode: 'order.quote_ready',
          title: 'Teklif hazır: SIP-20261028-12002',
          body: 'Demir Petrol teklifini gönderdi.',
          route: '/orders/12002',
          createdAt: DateTime.utc(2026, 10, 29, 6),
        ),
      );
      expect(find.byKey(NotificationTile.kindKey), findsNothing);
      expect(find.byIcon(PhosphorIconsFill.megaphone), findsNothing);
      expect(find.byIcon(PhosphorIconsFill.invoice), findsOneWidget);
      // İşlem bildiriminde iç kod yine çıkar.
      expect(find.text('Teklif hazır'), findsOneWidget);
    });
  });

  group('Bildirimler ekranı', () {
    testWidgets(
      'duyuruya dokununca okundu olur ve tam metni alttan açılır; sayfada kalınır; "Tamam" kapatır',
      (tester) async {
        setPhoneSize(tester, const Size(390, 844));
        final h = await A8Harness.create();
        final row = _announce(h.server.world, 'onay');
        final c = await pumpA8(
          tester,
          '/notifications',
          harness: h,
          persona: 'onay',
        );
        // Satırda metin iki satırda kesilir.
        final inRow = tester.widget<Text>(find.text(_long));
        expect(inRow.maxLines, 2);
        expect(find.byKey(NotificationTile.unreadDotKey), findsWidgets);

        await tester.tap(find.text('Bayram çalışma saatleri'));
        await pumpFor(tester, const Duration(milliseconds: 800));
        expect(_sheet, findsOneWidget);
        expect(_inSheet('Bayram çalışma saatleri'), findsOneWidget);
        expect(_inSheet('Duyuru'), findsOneWidget);
        // Bilgi önemindeki duyuruda karo nötr (renk yalnızca uyarı / tehlikede).
        final icon = find.descendant(
          of: _sheet,
          matching: find.byIcon(PhosphorIconsFill.megaphone),
        );
        expect(tester.widget<Icon>(icon).color, tester.element(icon).akn.ink);
        final full = tester.widget<Text>(_inSheet(_long));
        expect(full.maxLines, isNull, reason: 'tam metin');
        expect(find.byTooltip('Kapat'), findsNothing, reason: 'okuma sayfası');
        // Okundu: sunucu ve liste.
        expect(h.notifications.readCalls, 1);
        expect(row['readAt'], isNotNull);
        expect(
          c
              .read(inboxControllerProvider)
              .items
              .firstWhere((n) => n.id == row['id'])
              .isRead,
          isTrue,
        );
        // Sayfası yok: Bildirimler'de kalınır, uyarı yok.
        expect(find.byType(NotificationsPage), findsOneWidget);
        expect(
          find.text('Bu bildirimin sayfası hesabınızda açık değil.'),
          findsNothing,
        );

        await tester.tap(find.text('Tamam'));
        await pumpFor(tester, const Duration(milliseconds: 600));
        expect(_sheet, findsNothing);
        expect(find.byType(NotificationsPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await finish(tester);
      },
    );

    a11yMatrix('duyuru sayfası', (tester, scale, b) async {
      final h = await A8Harness.create();
      _announce(
        h.server.world,
        'musteri',
        code: 'system.announcement.price_update',
        title: 'Motorin fiyatı değişiyor',
        body: 'Yarın 06:00\'dan itibaren motorin litre fiyatı 0,40 TL artıyor.',
      );
      await pumpA8(
        tester,
        '/notifications',
        harness: h,
        persona: 'musteri',
        textScale: scale,
        brightness: b,
      );
      await tester.tap(find.text('Motorin fiyatı değişiyor'));
      await pumpFor(tester, const Duration(milliseconds: 800));
      expect(_sheet, findsOneWidget);
      expect(_inSheet('Fiyat güncellemesi'), findsOneWidget);
    });

    testWidgets('hareket azaltılınca sayfa hemen açılır', (tester) async {
      setPhoneSize(tester);
      final h = await A8Harness.create();
      _announce(h.server.world, 'musteri');
      await pumpA8(
        tester,
        '/notifications',
        harness: h,
        persona: 'musteri',
        reduceMotion: true,
      );
      await tester.tap(find.text('Bayram çalışma saatleri'));
      await tester.pump();
      await tester.pump();
      expect(_sheet, findsOneWidget);
      // Yükselme yok: içerik ilk karede yerinde ve tam görünür.
      final fades = find
          .ancestor(of: _sheet, matching: find.byType(Opacity))
          .evaluate()
          .map((e) => (e.widget as Opacity).opacity);
      expect(fades, everyElement(1.0));
      // Okundu isteği ve rozet tazelemesi biter.
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      await finish(tester);
    });

    testWidgets(
      'sayfa açıkken duyuru push\'una dokunuş: liste tazelenir, duyuru okundu olur ve tam metni '
      'açılır; kapatınca yeniden açılmaz',
      (tester) async {
        setPhoneSize(tester, const Size(390, 844));
        final events = StreamController<PushEvent>.broadcast();
        addTearDown(events.close);
        final h = await A8Harness.create();
        await pumpA8(
          tester,
          '/notifications',
          harness: h,
          persona: 'musteri',
          overrides: [pushEventsProvider.overrideWith((ref) => events.stream)],
        );
        expect(_sheet, findsNothing);
        // Panelden gönderildi: satır sunucuda, push'a dokunuldu.
        // Sunucu bakım duyurusunu uyarı önemiyle yazar.
        final row = _announce(
          h.server.world,
          'musteri',
          code: 'system.announcement.maintenance',
          title: 'Planlı bakım',
          body:
              'Uygulama bu gece 02:00–04:00 arasında kısa süre kapalı olacak.',
          severity: 2,
        );
        events.add(_tapOn(row));
        await pumpFor(tester, const Duration(milliseconds: 1200));
        expect(_sheet, findsOneWidget);
        expect(_inSheet('Planlı bakım'), findsOneWidget);
        expect(_inSheet('Bakım / Kesinti'), findsOneWidget);
        expect(row['readAt'], isNotNull);
        // Karo satırdakiyle aynı uyarı tonunda.
        final icon = find.descendant(
          of: _sheet,
          matching: find.byIcon(PhosphorIconsFill.megaphone),
        );
        final ctx = tester.element(icon);
        expect(tester.widget<Icon>(icon).color, ctx.akn.tone(AknTone.warn).fg);

        await tester.tap(find.text('Tamam'));
        await pumpFor(tester, const Duration(milliseconds: 600));
        expect(_sheet, findsNothing);
        // Başka push'lar (ön plan) ve liste tazelemesi aynı duyuruyu yeniden açmaz.
        events.add(_tapOn(row, origin: PushOrigin.foreground));
        await pumpFor(tester, const Duration(seconds: 1));
        expect(_sheet, findsNothing);
        expect(tester.takeException(), isNull);
        await finish(tester);
      },
    );

    testWidgets(
      'dokunuş sayfadan önce geldiyse (soğuk açılış) Bildirimler açılınca duyuru açılır',
      (tester) async {
        setPhoneSize(tester, const Size(390, 844));
        final events = StreamController<PushEvent>.broadcast();
        addTearDown(events.close);
        final h = await A8Harness.create();
        final row = _announce(
          h.server.world,
          'sofor',
          code: 'system.announcement.general',
          title: 'İyi yolculuklar',
          body: 'Bayram trafiğinde dikkatli olun; molalarınızı aksatmayın.',
        );
        await pumpA8(
          tester,
          '/notifications',
          harness: h,
          persona: 'sofor',
          overrides: [pushEventsProvider.overrideWith((ref) => events.stream)],
          beforeOpen: (c) async {
            // Uygulama push olaylarını açılıştan beri dinler (rozet sayacı).
            c.listen(pushEventsProvider, (_, _) {});
            events.add(_tapOn(row));
            await Future<void>.delayed(Duration.zero);
          },
        );
        await pumpFor(tester, const Duration(milliseconds: 600));
        expect(_sheet, findsOneWidget);
        expect(_inSheet('İyi yolculuklar'), findsOneWidget);
        expect(_inSheet('Genel'), findsOneWidget);
        expect(row['readAt'], isNotNull);
        await finish(tester);
      },
    );

    testWidgets(
      'listede bulunamayan duyuru (çevrimdışı) push\'taki başlık ve metinle açılır',
      (tester) async {
        setPhoneSize(tester, const Size(390, 844));
        final events = StreamController<PushEvent>.broadcast();
        addTearDown(events.close);
        final h = await A8Harness.create();
        await pumpA8(
          tester,
          '/notifications',
          harness: h,
          persona: 'musteri',
          overrides: [pushEventsProvider.overrideWith((ref) => events.stream)],
          beforeOpen: (c) async {
            c.listen(pushEventsProvider, (_, _) {});
            h.server.failureMode = FakeFailureMode.offline;
            events.add(_event(id: 987654));
            await Future<void>.delayed(Duration.zero);
          },
        );
        await pumpFor(tester, const Duration(milliseconds: 600));
        expect(find.text('Çevrimdışısınız'), findsOneWidget);
        expect(_sheet, findsOneWidget);
        expect(_inSheet('Hafta sonu kampanyası'), findsOneWidget);
        expect(
          _inSheet('Cumartesi ve pazar teslimatlarında indirim.'),
          findsOneWidget,
        );
        expect(_inSheet('Kampanya'), findsOneWidget);
        expect(h.notifications.readCalls, 0);
        h.server.failureMode = FakeFailureMode.none;
        await finish(tester);
      },
    );
  });

  group('uygulama kabuğu', () {
    Future<(ProviderContainer, TestHarness, _TapPush)> launch(
      WidgetTester tester,
      String persona,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      final h = await TestHarness.create(
        prefs: const {'akn.onboardingDone': true},
      );
      final push = _TapPush();
      addTearDown(push.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...h.overrides,
            pushServiceProvider.overrideWith((ref) => push),
          ],
          child: const AknApp(),
        ),
      );
      await pumpFor(tester, const Duration(seconds: 2));
      final c = ProviderScope.containerOf(tester.element(find.byType(AknApp)));
      await tester.runAsync(() async {
        final s = c.read(sessionControllerProvider.notifier);
        final outcome = await s.loginWithPassword(persona, 'demo');
        if (outcome is LoginNeedsCode) {
          await s.verifyCode(outcome.challenge.challengeId, '123456');
        }
      });
      await pumpFor(tester, const Duration(seconds: 2));
      return (c, h, push);
    }

    for (final persona in ['musteri', 'sofor']) {
      testWidgets(
        '$persona: duyuru push\'una dokununca Bildirimler açılır ve duyurunun tam metni gelir',
        (tester) async {
          final (c, h, push) = await launch(tester, persona);
          expect(
            c.read(sessionControllerProvider),
            isA<SessionAuthenticated>(),
          );
          expect(_sheet, findsNothing);
          final row = _announce(
            h.server.world,
            persona,
            code: 'system.announcement.campaign',
            title: 'Hafta sonu kampanyası',
          );
          push.send(_tapOn(row));
          await pumpFor(tester, const Duration(seconds: 2));
          expect(find.byType(NotificationsPage), findsOneWidget);
          expect(_sheet, findsOneWidget);
          expect(_inSheet('Hafta sonu kampanyası'), findsOneWidget);
          expect(_inSheet(_long), findsOneWidget);
          expect(_inSheet('Kampanya'), findsOneWidget);
          expect(row['readAt'], isNotNull);
          expect(tester.takeException(), isNull);

          await tester.tap(find.text('Tamam'));
          await pumpFor(tester, const Duration(seconds: 1));
          expect(_sheet, findsNothing);
          expect(find.byType(NotificationsPage), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  });

  group('demo dünyası', () {
    test(
      'her personanın gelen kutusunda bir okunmuş duyuru: rotasız, en eski satır, listenin sonunda; '
      'okunmamış sayısı değişmez',
      () {
        final server = buildFakeServer(latency: false);
        final plain = FakeWorld.seeded();
        for (final p in fakePersonas) {
          final mine = [
            for (final n in server.world.notifications)
              if (n['userId'] == p.userId) n,
          ];
          final demo = mine
              .where((n) => n['eventCode'] == DemoAnnouncement.eventCode)
              .toList();
          expect(demo, hasLength(1), reason: p.key);
          final d = demo.single;
          expect(Announcements.isEventCode(d['eventCode'] as String), isTrue);
          expect(
            Announcements.kindOf(d['eventCode'] as String),
            AnnouncementKind.notice,
          );
          expect(d['category'], NotificationCategory.system);
          expect(d['route'], isNull, reason: 'sayfası yok');
          expect(d['entityType'], 'PushCampaign');
          expect(d['readAt'], isNotNull, reason: p.key);
          expect(identical(mine.last, d), isTrue, reason: p.key);
          final at = DateTime.parse(d['createdAt'] as String);
          for (final n in mine) {
            if (identical(n, d)) continue;
            expect(
              DateTime.parse(n['createdAt'] as String).isAfter(at),
              isTrue,
              reason: '${p.key}: ${n['title']}',
            );
          }
          expect(
            server.world.unreadNotifications(p.userId),
            plain.unreadNotifications(p.userId),
            reason: p.key,
          );
        }
      },
    );

    test(
      'liste ucu duyuruyu bir kez verir; dünya baştan yüklenince yeniden eklenir',
      () async {
        final h = await A8Harness.create();
        final c = h.container();
        addTearDown(c.dispose);
        await c.read(appConfigProvider.notifier).load();
        await c
            .read(sessionControllerProvider.notifier)
            .loginWithPassword('onay', 'demo');
        final repo = c.read(notificationsRepositoryProvider);
        int count(PagedResult<UserNotification> p) =>
            p.items.where(Announcements.isAnnouncement).length;
        final first = await repo.list();
        expect(count(first), 1);
        final demo = first.items.firstWhere(Announcements.isAnnouncement);
        expect(demo.title, DemoAnnouncement.title);
        expect(demo.route, isNull);
        expect(demo.isRead, isTrue);
        expect(first.items.last.id, demo.id, reason: 'en eski');
        expect(count(await repo.list()), 1);

        h.server.resetWorld();
        expect(
          h.server.world.notifications.where(
            (n) => n['eventCode'] == DemoAnnouncement.eventCode,
          ),
          isEmpty,
        );
        expect(count(await repo.list()), 1);
        expect(count(await repo.list()), 1);
      },
    );
  });
}

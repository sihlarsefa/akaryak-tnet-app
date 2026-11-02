// Bildirimler listesinin dayanıklılığı (sahip bildirimi 2026-11-02: "liste yüklenemedi"). Liste gerçek
// depodan ([NotificationsRepository]) ve gerçek [ApiClient] üzerinden, ağsız sıralı adaptörle
// ([QueueAdapter]) okunur; yanıtlar canlı API'nin birebir çıktısıdır (yerel kum havuzu, panelden
// "Tüm müşteri kullanıcıları"na beş türde push: Genel, Duyuru, Kampanya, Bakım / Kesinti, Fiyat
// güncellemesi; Türkçe harfler, emoji, 400 karakterlik metin).
//
// * Tek bozuk satır listenin tamamını düşürmez: satır atlanır (kimliksiz, nesne olmayan) ya da
//   bozuk alanı varsayılana düşer ("NaN", "Infinity").
// * Geçici hata (429, zaman aşımı, 5xx) kesin hata değildir: kayıtlı ilk sayfa varsa o gösterilir,
//   yoksa "tekrar dene" durumu; liste ekrandayken yenileme başarısızsa liste kalır, üstünde not çıkar.
// * Kalıcı hata (403 …) "Bildirimler yüklenemedi" olarak kalır.
import 'dart:convert';
import 'dart:io';

import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/env/app_config_controller.dart';
import 'package:akaryakitnet/core/network/api_client.dart';
import 'package:akaryakitnet/core/network/app_failure.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/notifications/application/announcements.dart';
import 'package:akaryakitnet/features/notifications/application/inbox_controller.dart';
import 'package:akaryakitnet/features/notifications/data/notifications_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_adapter.dart';
import '../profile/a8_kit.dart';

/// Canlı API'nin yanıtı (GET notifications?page=1&pageSize=25, müşteri; panelden beş push).
final String campaignsPage1 = File(
  'test/features/notifications/fixtures/campaigns_page1.json',
).readAsStringSync();

/// Aynı kullanıcının 2. sayfası (canlı API: boş sayfa, toplam 5).
const campaignsPage2 =
    '{"items":[],"totalCount":5,"pageNumber":2,"pageSize":25,"totalPages":1}';

const _retryTitle = 'Bildirimler şu an yenilenemedi';
const _staleNote = 'Liste şu an yenilenemedi.';
const _hardTitle = 'Bildirimler yüklenemedi';

ResponseBody _raw(
  int status,
  String body, [
  Map<String, String> h = const {},
]) => ResponseBody.fromString(
  body,
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json; charset=utf-8'],
    for (final e in h.entries) e.key: [e.value],
  },
);

ResponseBody _rateLimited(RequestOptions _) => _raw(
  429,
  jsonEncode({
    'title': 'Çok fazla istek',
    'status': 429,
    'detail': 'Çok fazla istek gönderildi. 30 saniye sonra tekrar deneyin.',
    'code': 'rate_limited',
    'retryAfter': 30,
  }),
  {'retry-after': '30'},
);

/// IIS'in uygulama havuzu dururken (dağıtım, bakım) verdiği yanıt: 503 ve HTML gövde.
ResponseBody _iis503(RequestOptions _) => ResponseBody.fromString(
  '<!DOCTYPE html><html><body><h1>Service Unavailable</h1></body></html>',
  503,
  headers: {
    Headers.contentTypeHeader: ['text/html; charset=us-ascii'],
  },
);

ResponseBody _forbidden(RequestOptions _) => _raw(
  403,
  jsonEncode({
    'title': 'Yetkiniz yok',
    'status': 403,
    'detail': 'Bu işlem için yetkiniz yok.',
    'code': 'forbidden',
  }),
);

/// Gerçek depo + gerçek API istemcisi; yanıtlar sıradan gelir (sıra boşsa [QueueAdapter.fallback]).
({NotificationsRepository repo, QueueAdapter queue}) liveRepo() {
  final queue = QueueAdapter();
  final dio = Dio(
    BaseOptions(
      baseUrl: 'http://api.test/api/v1/',
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    ),
  )..httpClientAdapter = queue;
  return (repo: NotificationsRepository(ApiClient(dio)), queue: queue);
}

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 400 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// Demo personasıyla oturum açmış kapsayıcı; bildirim listesi [repo]'dan okunur.
Future<ProviderContainer> signedIn(
  A8Harness h,
  String persona,
  NotificationsRepository repo,
) async {
  final c = h.container(
    extra: [notificationsRepositoryProvider.overrideWithValue(repo)],
  );
  await c.read(appConfigProvider.notifier).load();
  await c
      .read(sessionControllerProvider.notifier)
      .loginWithPassword(persona, 'demo');
  return c;
}

/// [campaignsPage1]'e bozuk satırlar eklenmiş hâli.
String withBadRows() {
  final page = jsonDecode(campaignsPage1) as Map<String, dynamic>;
  final items = List<Object?>.of(page['items'] as List);
  final good = Map<String, dynamic>.of(items.first! as Map<String, dynamic>);
  items.insertAll(1, [
    // Sayısal alanda sayı olmayan değer: alan varsayılana düşer, satır kalır.
    {...good, 'id': 900, 'entityId': 'NaN', 'severity': 'Infinity'},
    // Kimliksiz satır: okundu işaretlenemez, atlanır.
    {...good, 'id': null, 'title': 'Kimliksiz'},
    // Nesne olmayan öğeler: atlanır.
    'bozuk',
    null,
  ]);
  page['items'] = items;
  page['totalCount'] = items.length;
  return jsonEncode(page);
}

void main() {
  group('depo: canlı API yanıtı', () {
    test(
      'beş tür duyuru: Türkçe metin, emoji, 400 karakter, rota yok',
      () async {
        final r = liveRepo();
        r.queue
          ..enqueue((_) => _raw(200, campaignsPage1))
          ..enqueue((_) => _raw(200, campaignsPage2))
          ..enqueue((_) => _raw(200, campaignsPage1));
        final p1 = await r.repo.list();
        expect(p1.items, hasLength(5));
        expect(p1.totalCount, 5);
        expect(p1.items.map((n) => Announcements.kindOf(n.eventCode)), [
          AnnouncementKind.price,
          AnnouncementKind.maintenance,
          AnnouncementKind.campaign,
          AnnouncementKind.notice,
          AnnouncementKind.general,
        ]);
        expect(p1.items.every(Announcements.isAnnouncement), isTrue);
        expect(p1.items[2].body, hasLength(400));
        expect(p1.items[3].body, contains('🚚'));
        expect(p1.items[4].title, 'Genel duyuru: İŞĞÜÇÖ ışğüçö');
        expect(p1.items[1].severity, 2);
        expect(p1.items.first.entityType, 'PushCampaign');
        final p2 = await r.repo.list(page: 2);
        expect(p2.items, isEmpty);
        expect(p2.hasMore, isFalse);
        final unread = await r.repo.list(unreadOnly: true);
        expect(unread.items, hasLength(5));
        expect(r.queue.requests.last.uri.queryParameters['unreadOnly'], 'true');
      },
    );

    test(
      'tek bozuk satır listeyi düşürmez: atlanır ya da alanı varsayılana düşer',
      () async {
        final r = liveRepo();
        r.queue.enqueue((_) => _raw(200, withBadRows()));
        final p = await r.repo.list();
        expect(p.items.map((n) => n.id), [182, 900, 139, 96, 53, 10]);
        final odd = p.items[1];
        expect(odd.entityId, isNull);
        expect(odd.severity, 0);
        expect(odd.title, 'Fiyat güncellemesi');
      },
    );
  });

  group('denetleyici: geçici hata kesin hata değildir', () {
    test(
      '429 ve kayıtlı ilk sayfa: liste kalır, hata "tekrar dene" notudur',
      () async {
        final h = await A8Harness.create();
        final r = liveRepo();
        final repo = await signedIn(h, 'musteri', r.repo);
        addTearDown(repo.dispose);
        // Okunmamış sayısı gelince liste bir kez daha istenebilir: her istek aynı yanıtı alır.
        r.queue.fallback = (_) => _raw(200, campaignsPage1);
        var sub = repo.listen(inboxControllerProvider, (_, _) {});
        await until(() => !repo.read(inboxControllerProvider).loading);
        expect(repo.read(inboxControllerProvider).items, hasLength(5));
        // Önbellek yazılsın, sonra ekran kapansın.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        sub.close();
        await until(() => !repo.exists(inboxControllerProvider));

        r.queue.fallback = _rateLimited;
        sub = repo.listen(inboxControllerProvider, (_, _) {});
        await until(() => !repo.read(inboxControllerProvider).loading);
        final s = repo.read(inboxControllerProvider);
        expect(s.items, hasLength(5), reason: 'kayıtlı liste gösterilir');
        expect(s.fromCache, isTrue);
        expect(s.error, isA<RateLimitedFailure>());
        sub.close();
      },
    );

    test('kalıcı hata (403) kesin hata olarak kalır', () async {
      final h = await A8Harness.create();
      final r = liveRepo();
      final repo = await signedIn(h, 'musteri', r.repo);
      addTearDown(repo.dispose);
      r.queue.fallback = _forbidden;
      repo.listen(inboxControllerProvider, (_, _) {});
      await until(() => !repo.read(inboxControllerProvider).loading);
      final s = repo.read(inboxControllerProvider);
      expect(s.items, isEmpty);
      expect(s.fromCache, isFalse);
      expect(s.error, isA<ForbiddenFailure>());
    });
  });

  group('ekran', () {
    testWidgets('429, kayıtlı liste yok: "tekrar dene" durumu ve bekleme süresi', (
      tester,
    ) async {
      setPhoneSize(tester, const Size(390, 844));
      fixClock(DateTime.utc(2026, 11, 2, 6));
      final h = await A8Harness.create();
      final r = liveRepo();
      // Sayfa açılınca okunmamış sayısı artar ve liste bir kez daha istenir: hepsi 429.
      r.queue.fallback = _rateLimited;
      await pumpA8(
        tester,
        '/notifications',
        harness: h,
        persona: 'musteri',
        overrides: [notificationsRepositoryProvider.overrideWithValue(r.repo)],
      );
      // Yine görünür bir hata durumu (QA: sunucu hatası "Tekrar dene" ile gösterilir), ama "şu an".
      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text(_hardTitle), findsNothing);
      expect(find.text(_retryTitle), findsOneWidget);
      expect(find.textContaining('30 sn sonra tekrar deneyin'), findsOneWidget);
      // Tekrar dene: liste gelir.
      r.queue.enqueue((_) => _raw(200, campaignsPage1));
      await tapVisible(tester, find.text('Tekrar dene'));
      await pumpFor(tester, const Duration(milliseconds: 800));
      expect(find.text(_retryTitle), findsNothing);
      expect(find.text('Kampanya: %10 indirim'), findsOneWidget);
      await finish(tester);
    });

    testWidgets(
      'liste ekrandayken yenileme başarısız (503): liste kalır, üstte not',
      (tester) async {
        setPhoneSize(tester, const Size(390, 844));
        fixClock(DateTime.utc(2026, 11, 2, 6));
        final h = await A8Harness.create();
        final r = liveRepo();
        r.queue.fallback = (_) => _raw(200, campaignsPage1);
        final c = await pumpA8(
          tester,
          '/notifications',
          harness: h,
          persona: 'musteri',
          overrides: [
            notificationsRepositoryProvider.overrideWithValue(r.repo),
          ],
        );
        expect(find.text('Kampanya: %10 indirim'), findsOneWidget);
        expect(find.text(_staleNote), findsNothing);
        r.queue.enqueue(_iis503);
        await tester.runAsync(
          () => c.read(inboxControllerProvider.notifier).refresh(),
        );
        await pumpFor(tester, const Duration(milliseconds: 400));
        expect(
          c.read(inboxControllerProvider).error,
          isA<ServerFailure>().having((f) => f.statusCode, 'status', 503),
        );
        expect(find.text('Kampanya: %10 indirim'), findsOneWidget);
        expect(find.text(_staleNote), findsOneWidget);
        expect(find.text(_hardTitle), findsNothing);
        // Tekrar dene başarılı: not kalkar.
        r.queue.enqueue((_) => _raw(200, campaignsPage1));
        await tapVisible(tester, find.text('Tekrar dene'));
        await pumpFor(tester, const Duration(milliseconds: 600));
        expect(find.text(_staleNote), findsNothing);
        await finish(tester);
      },
    );

    testWidgets('kalıcı hata (403): "Bildirimler yüklenemedi"', (tester) async {
      setPhoneSize(tester, const Size(390, 844));
      final h = await A8Harness.create();
      final r = liveRepo();
      r.queue.fallback = _forbidden;
      await pumpA8(
        tester,
        '/notifications',
        harness: h,
        persona: 'musteri',
        overrides: [notificationsRepositoryProvider.overrideWithValue(r.repo)],
      );
      expect(find.text(_hardTitle), findsOneWidget);
      expect(find.text(_retryTitle), findsNothing);
      await finish(tester);
    });
  });
}

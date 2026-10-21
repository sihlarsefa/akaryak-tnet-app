import '../../core/models/json.dart';
import '../../core/network/fake/fake_personas.dart';
import '../../core/network/fake/fake_server.dart';
import '../../core/network/fake/fake_world.dart';
import 'data/notification_models.dart';

/// Bildirim sahte uçlarının anahtarları (sunucu örneği başına; testler).
class NotificationsFakeControls {
  NotificationsFakeControls._();

  static final _byServer = Expando<NotificationsFakeControls>(
    'notificationsFakeControls',
  );

  static NotificationsFakeControls of(FakeServer server) =>
      _byServer[server] ??= NotificationsFakeControls._();

  /// Cihazında push açık sayılan personalar (test bildirimi `sent`).
  final Set<String> pushDevices = {};

  /// Test bildirimi sayacı (saatte 3 sınırı).
  final Map<String, List<DateTime>> _tests = {};

  int listCalls = 0;
  int readCalls = 0;
}

/// Bildirimler sahte uçları (sahibi A8; spec B.4). Ortak dünyadaki `world.notifications`
/// kayıtlarını okur ve günceller (çekirdeğin `notifications/unread-count` ucu aynı kayıtları sayar):
/// - `GET notifications?page&pageSize&unreadOnly` → `PagedResult<UserNotificationDto>` (yeni önce),
/// - `POST notifications/{id}/read`, `POST notifications/read-all` → 204,
/// - `GET|PUT notifications/preferences` → `[{category, label, pushEnabled}]` (görüntüleyicide
///   Siparişler ve Teklifler varsayılan kapalı),
/// - `POST notifications/test` → `{devices, sent}` (saatte 3; gelen kutusuna "Test bildirimi" düşer).
void registerNotificationsFakes(FakeServer s) {
  final ctl = NotificationsFakeControls.of(s);

  JsonMap dto(JsonMap n) {
    final category = '${n['category'] ?? NotificationCategory.system}';
    return {
      'id': n['id'],
      'category': category,
      'categoryLabel': NotificationCategory.label(category),
      'eventCode': n['eventCode'],
      'title': n['title'],
      'body': n['body'],
      'severity': n['severity'] ?? 0,
      'route': n['route'],
      'entityType': n['entityType'],
      'entityId': n['entityId'],
      'createdAt': n['createdAt'],
      'readAt': n['readAt'],
      'isRead': n['readAt'] != null,
    };
  }

  List<JsonMap> mine(FakeWorld w, String userId) {
    final list = [
      for (final n in w.notifications)
        if (n['userId'] == userId) n,
    ];
    list.sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'));
    return list;
  }

  s.get('notifications', (req) {
    final p = req.requireUser();
    ctl.listCalls++;
    final unreadOnly = req.queryBool('unreadOnly') ?? false;
    final all = [
      for (final n in mine(req.world, p.userId))
        if (!unreadOnly || n['readAt'] == null) dto(n),
    ];
    return req.paged(all);
  });

  s.post('notifications/{id:int}/read', (req) {
    final p = req.requireUser();
    ctl.readCalls++;
    final id = req.intParam('id');
    final n = req.world.notifications
        .where((x) => x['id'] == id && x['userId'] == p.userId)
        .firstOrNull;
    if (n == null) throw FakeResponse.notFound('Bildirim bulunamadı.');
    n['readAt'] ??= DateTime.now().toUtc().toIso8601String();
    return FakeResponse.noContent();
  });

  s.post('notifications/read-all', (req) {
    final p = req.requireUser();
    final now = DateTime.now().toUtc().toIso8601String();
    for (final n in req.world.notifications) {
      if (n['userId'] == p.userId) n['readAt'] ??= now;
    }
    return FakeResponse.noContent();
  });

  Map<String, bool> prefsOf(FakeWorld w, FakePersona p) {
    final all = w.bag<Map<String, Map<String, bool>>>(
      'notifications.prefs',
      () => {},
    );
    return all.putIfAbsent(p.userId, () {
      // Ekler / Düzenler yetkisi olmayan bayi kullanıcısında siparişler ve teklifler kapalı başlar.
      final passive =
          p.persona.code == 'bayi' &&
          !p.pages.any((g) => g.endsWith(':Ekler') || g.endsWith(':Duzenler'));
      return {
        for (final c in NotificationCategory.all)
          c:
              !(passive &&
                  (c == NotificationCategory.orders ||
                      c == NotificationCategory.quotes)),
      };
    });
  }

  List<JsonMap> prefsJson(Map<String, bool> prefs) => [
    for (final c in NotificationCategory.all)
      {
        'category': c,
        'label': NotificationCategory.label(c),
        'pushEnabled': prefs[c] ?? true,
      },
  ];

  s.get('notifications/preferences', (req) {
    final p = req.requireUser();
    return prefsJson(prefsOf(req.world, p));
  });

  s.put('notifications/preferences', (req) {
    final p = req.requireUser();
    final body = req.body;
    if (body is! List) {
      throw FakeResponse.validation({
        'preferences': ['Tercih listesi gerekli.'],
      });
    }
    final prefs = prefsOf(req.world, p);
    var known = 0;
    for (final e in body) {
      final r = JsonReader.of(e);
      final c = r.str('category');
      if (!NotificationCategory.all.contains(c)) continue;
      known++;
      prefs[c] = r.boolean('pushEnabled', true);
    }
    if (known == 0 && body.isNotEmpty) {
      throw FakeResponse.validation({
        'category': ['Bilinmeyen bildirim kategorisi.'],
      });
    }
    return prefsJson(prefs);
  });

  s.post('notifications/test', (req) {
    final p = req.requireUser();
    final now = DateTime.now().toUtc();
    final sent = ctl._tests.putIfAbsent(p.userId, () => [])
      ..removeWhere((t) => now.difference(t) >= const Duration(hours: 1));
    if (sent.length >= 3) {
      final wait = const Duration(hours: 1) - now.difference(sent.first);
      throw FakeResponse.problem(
        429,
        'rate_limited',
        'Saatte en fazla 3 test bildirimi gönderebilirsiniz. Biraz sonra tekrar deneyin.',
        headers: {'retry-after': '${wait.inSeconds.clamp(1, 3600)}'},
      );
    }
    sent.add(now);
    req.world.addNotification(
      userId: p.userId,
      category: NotificationCategory.system,
      eventCode: 'system.test',
      title: 'Test bildirimi',
      body: 'Bildirimler bu cihazda çalışıyor.',
      route: '/notifications',
    );
    final devices = ctl.pushDevices.contains(p.key) ? 1 : 0;
    return {'devices': devices, 'sent': devices};
  });
}

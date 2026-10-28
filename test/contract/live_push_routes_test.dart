// Bildirim dokunuşları canlı verilerle (spec C.4): sandbox'tan alınmış GERÇEK gelen kutusu yanıtlarındaki
// her rota, alıcısının GERÇEK `me/access` yetkileriyle uygulamada açılır mı? Push (FCM) yokken de
// gelen kutusundaki satıra dokunmak ve sistem bildirimine dokunmak aynı yoldan geçer
// (`RouteAccess.resolvePushRoute` → yönlendirici).
//
// - Varsayılan: `test/contract/fixtures` (bildirim listeleri + aynı kullanıcının `me/access` yanıtı,
//   eşleme `index.json` `user` alanından). Ağ gerekmez.
// - `--dart-define=AKN_LIVE_ROUTES=<dosya.json>`: sandbox'taki tüm rol kullanıcılarının gelen kutusu
//   dökümü de denetlenir (`{users: [{user, access, notifications: [{route, eventCode}]}]}`); açılamayan
//   rotalar ayrıca listelenir.
import 'dart:convert';
import 'dart:io';

import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/auth/access_policy.dart';
import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/routing/nav_keys.dart';
import 'package:akaryakitnet/core/routing/route_access.dart';
import 'package:akaryakitnet/features/notifications/data/notification_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _dir = 'test/contract/fixtures';
const _dump = String.fromEnvironment('AKN_LIVE_ROUTES');

Object? _read(String path) => jsonDecode(File(path).readAsStringSync());

/// (kullanıcı, `me/access`, gelen kutusundaki bildirimler).
typedef _Inbox = (String user, MeAccess access, List<UserNotification> items);

List<_Inbox> _fixtureInboxes() {
  final index = (_read('$_dir/index.json')! as Map)['fixtures'] as List;
  final accessByUser = <String, MeAccess>{};
  for (final f in index.cast<Map>()) {
    if ((f['name'] as String).startsWith('me-access') && f['status'] == 200) {
      accessByUser[f['user'] as String] = MeAccess.fromJson(
        _read('$_dir/${f['name']}.json'),
      );
    }
  }
  return [
    for (final f in index.cast<Map>())
      if (RegExp(r'^notifications(\.|$)').hasMatch(f['name'] as String) &&
          f['status'] == 200 &&
          accessByUser.containsKey(f['user']))
        (
          f['user'] as String,
          accessByUser[f['user']]!,
          PagedResult.fromJson(
            _read('$_dir/${f['name']}.json'),
            UserNotification.fromJson,
          ).items,
        ),
  ];
}

List<_Inbox> _dumpInboxes() {
  if (_dump.isEmpty) return const [];
  final users = (_read(_dump)! as Map)['users'] as List;
  return [
    for (final u in users.cast<Map>())
      (
        u['user'] as String,
        MeAccess.fromJson(u['access']),
        JsonReader.parseList(u['notifications'], UserNotification.fromJson),
      ),
  ];
}

void main() {
  final features = AppConfig.fromJson(
    _read('$_dir/app-config.ios.json'),
  ).features;

  /// Rotanın kullanıcının uygulamasında vardığı yer (izin yoksa `/notifications`) ve sayfası var mı.
  (String, bool) land(MeAccess access, String? route) {
    final policy = AccessPolicy(access);
    final to = RouteAccess.resolvePushRoute(route, policy, features);
    final router = GoRouter(
      navigatorKey: rootNavigatorKey,
      routes: buildAppRoutes(buildNavLayout(policy, features)),
    );
    final match = router.configuration.findMatch(Uri.parse(to));
    router.dispose();
    return (to, !match.isError && match.isNotEmpty);
  }

  test(
    'canlı gelen kutuları: her bildirim alıcısının uygulamasında kendi sayfasını açar',
    () {
      final inboxes = _fixtureInboxes();
      expect(inboxes.length, greaterThanOrEqualTo(6));
      final personas = {for (final (_, a, _) in inboxes) a.persona};
      expect(
        personas,
        containsAll([Persona.customer, Persona.bayi, Persona.platform]),
      );
      var checked = 0;
      for (final (user, access, items) in inboxes) {
        for (final n in items) {
          final (to, page) = land(access, n.route);
          expect(page, isTrue, reason: '$user ${n.route}: sayfa yok');
          expect(
            to,
            n.route,
            reason: '$user ${n.eventCode} ${n.route}: alıcı açamıyor',
          );
          checked++;
        }
      }
      expect(checked, greaterThan(15));
    },
  );

  test(
    'sandbox dökümü: tüm rol kullanıcılarının gelen kutusu',
    skip: _dump.isEmpty ? 'AKN_LIVE_ROUTES verilmedi' : false,
    () {
      final inboxes = _dumpInboxes();
      expect(inboxes, isNotEmpty);
      final noPage = <String>[];
      final fallback = <String, int>{};
      var checked = 0;
      for (final (user, access, items) in inboxes) {
        for (final n in items) {
          final (to, page) = land(access, n.route);
          checked++;
          if (!page) noPage.add('$user ${n.route}');
          if (to != n.route) {
            final key =
                '$user (${access.persona.name}) ${n.eventCode} '
                '${n.route?.replaceAll(RegExp(r'\d+'), '#')}';
            fallback[key] = (fallback[key] ?? 0) + 1;
          }
        }
      }
      // ignore: avoid_print
      print(
        'denetlenen $checked bildirim, ${inboxes.length} kullanıcı; '
        'açamayıp Bildirimler\'e düşen: ${fallback.isEmpty ? 'yok' : ''}\n'
        '${fallback.entries.map((e) => '  ${e.key} ×${e.value}').join('\n')}',
      );
      expect(noPage, isEmpty, reason: 'eşleşmeyen rotalar');
      expect(fallback, isEmpty, reason: 'alıcısının açamadığı bildirimler');
    },
  );
}

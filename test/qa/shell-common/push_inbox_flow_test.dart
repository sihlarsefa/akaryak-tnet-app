// QA shell-common: push derin bağlantıları ve bildirim gelen kutusu, her persona için gerçek uygulamada.
//
// 1. Personanın sahte dünyadaki bildirimlerinin rotaları ve sunucunun liste kökü yedekleri, oturum
//    açıkken dokunulan push gibi (`LocalNotifications.onTap`) açılır: konum `resolvePushRoute` ile aynı,
//    istisna / taşma yok, sayfa hata durumunda değil.
// 2. Gelen kutusu (zil) açılır, ilk bildirime dokunulur: rotası açılır ya da izin yoksa uyarı.
import 'dart:async';

import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/auth/access_policy.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/env/app_config_controller.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/push/local_notifications.dart';
import 'package:akaryakitnet/core/routing/route_access.dart';
import 'package:akaryakitnet/features/notifications/presentation/notifications_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_support.dart';

/// Sunucunun kimliksiz yedek rotaları ve ortak hedefler.
const _roots = [
  '/orders',
  '/bayi/orders',
  '/payments',
  '/approvals',
  '/driver',
  '/field',
  '/company/requests',
  '/shipments',
  '/notifications',
  '/stats',
  '/assistant',
];

/// Şu an bilinen hatayla düşen personalar (düzeltilince silin): skip 'QA SC-xx'.
// QA SC-02 düzeltildi (mix_chart.dart: değer sığmazsa adın altına iner).
const _knownIssues = <String, String>{};

void main() {
  for (final persona in fakePersonas) {
    // QA SC-02: bu personaların `/stats` sayfası 360 dp'de taşıyor (mix_chart.dart Row).
    final known = _knownIssues[persona.key];
    testWidgets(
      '${persona.key}: push dokunuşları ve gelen kutusu'
      '${known == null ? '' : ' [$known]'}',
      skip: known != null,
      (tester) async {
        final qa = QaProblems('push_${persona.key}');
        try {
          final app = await launchQa(tester);
          await qaSignIn(tester, app, persona.key);
          expect(app.session.access?.userName, persona.key);
          final world = app.harness.server.world;
          final routes = <String>{
            for (final n in world.notifications)
              if (n['userId'] == persona.userId && n['route'] is String)
                n['route'] as String,
            ..._roots,
          };
          final problems = qa.items;
          final router = app.container.read(routerProvider);
          final home = app.location;
          for (final route in routes) {
            final policy = AccessPolicy(
              app.container.read(sessionControllerProvider).access,
            );
            final features = app.container.read(appConfigProvider).features;
            final expected = RouteAccess.resolvePushRoute(
              route,
              policy,
              features,
            );
            expect(LocalNotifications.onTap, isNotNull);
            qa.where = 'push $route';
            LocalNotifications.onTap!(route);
            await pumpSteps(tester, const Duration(milliseconds: 1200));
            await settleIo(tester);
            await pumpSteps(tester, const Duration(milliseconds: 400));
            final e = tester.takeException();
            if (e != null) problems.add('$route → istisna: $e');
            final at = app.location;
            if (at != expected) {
              problems.add('$route → $at (beklenen $expected)');
            }
            final errors = qaErrorTexts();
            if (errors.isNotEmpty) {
              problems.add('$route → hata durumu: $errors');
            }
            // Geri: kök sekmeye dön.
            router.go(home);
            await pumpSteps(tester, const Duration(milliseconds: 600));
            tester.takeException();
          }

          // Gelen kutusu: zil yerine rota (zil her başlıkta olmayabilir), ilk bildirime dokun.
          qa.where = 'gelen kutusu';
          unawaited(router.push('/notifications'));
          await pumpSteps(tester, const Duration(milliseconds: 1200));
          await settleIo(tester);
          if (find.byType(NotificationsPage).evaluate().isEmpty) {
            problems.add('gelen kutusu açılmadı: konum ${app.location}');
          }
          final e = tester.takeException();
          if (e != null) problems.add('gelen kutusu → istisna: $e');
          final errors = qaErrorTexts();
          if (errors.isNotEmpty) problems.add('gelen kutusu → $errors');
          // Alt menü sekmesi olan rotalar (ör. `/payments`) gelen kutusundan açılınca uygulama çöküyor:
          // QA SC-01 (inbox_tab_route_test.dart). Burada yalnızca diğer rotalar denenir.
          final layout = app.container.read(navLayoutProvider);
          final mine = [
            for (final n in world.notifications)
              if (n['userId'] == persona.userId &&
                  !layout.bar.any((d) => d.path == n['route']))
                n,
          ];
          if (mine.isNotEmpty) {
            qa.where = 'bildirime dokun (${mine.first['route']})';
            final first = find.text(mine.first['title'] as String);
            if (first.evaluate().isEmpty) {
              problems.add(
                'gelen kutusu: ilk bildirim "${mine.first['title']}" yok',
              );
            } else {
              await qaTap(tester, first.first);
              await pumpSteps(tester, const Duration(milliseconds: 1200));
              await settleIo(tester);
              final e2 = tester.takeException();
              if (e2 != null) problems.add('bildirim dokunuşu → istisna: $e2');
              final errs = qaErrorTexts();
              if (errs.isNotEmpty) {
                problems.add(
                  'bildirim dokunuşu (${mine.first['route']}) → $errs @ ${app.location}',
                );
              }
            }
          }
          await tester.pumpWidget(const SizedBox());
        } catch (e, st) {
          qa.add(
            'beklenmeyen: ${e.toString().split('\n').take(8).join(' ')} @ '
            '${st.toString().split('\n').where((l) => l.contains('shell-common')).take(3).join(' | ')}',
          );
        } finally {
          qa.finish();
        }
      },
    );
  }
}

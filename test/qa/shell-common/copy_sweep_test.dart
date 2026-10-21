// QA shell-common: yazım kuralları gerçek uygulamada, her persona × her izinli sayfa (tasarım v2 §1
// kural 7). Ekrandaki her metinde:
// - " · " ayırıcısı yok ("A · B · C" yerine virgül ya da cümle),
// - "Lütfen" yok, genel hata metni yok ("Bir hata oluştu", "Beklenmeyen bir hata"),
// - programcı izi yok ("null", "Instance of", "Exception"),
// - ok işareti "→" yok.
//
// Sayfa ilk ekranı ve kaydırılmış hâliyle taranır (tembel listelerde aşağıdaki satırlar da).
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/auth/access_policy.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/env/app_config_controller.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/routing/route_access.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_support.dart';

List<String> _routes(QaApp app) {
  final w = app.harness.server.world;
  final customerOrder = w.ordersOfCustomer(101).first['id'];
  final bayiOrder = w.ordersOfStation(1).first['id'];
  final shipment = w.shipments.isEmpty ? 5 : w.shipments.first['id'];
  final approval = w.approvals.isEmpty ? 9001 : w.approvals.first['id'];
  return [
    '/home',
    '/notifications',
    '/notifications/settings',
    '/assistant',
    '/profile',
    '/profile/password',
    '/profile/edit',
    '/profile/sessions',
    '/profile/delete-account',
    '/stats',
    '/orders',
    '/orders/new',
    '/orders/$customerOrder',
    '/shipments',
    '/shipments/$shipment',
    '/company/requests',
    '/finance-info',
    '/documents',
    '/spending',
    '/delivery-points',
    '/templates',
    '/limits',
    '/company/users',
    '/quote-desk',
    '/bayi/orders',
    '/bayi/orders/$bayiOrder',
    '/customers',
    '/dispatch',
    '/bayi/staff',
    '/driver',
    '/driver/shipments/$shipment',
    '/approvals',
    '/approvals/$approval',
    '/finance',
    '/payments',
    '/payments/$bayiOrder',
    '/field',
    '/field/forms/new',
    '/field/leads/new',
  ];
}

/// Kural ihlali arayan desenler (ad → desen).
final _rules = <String, RegExp>{
  'ayırıcı " · "': RegExp('·'),
  '"Lütfen"': RegExp(r'\bLütfen\b|\blütfen\b'),
  'genel hata metni': RegExp(
    r'Bir hata oluştu|Beklenmeyen bir hata|Hata oluştu|Something went wrong',
  ),
  'programcı izi': RegExp(r'\bnull\b|Instance of|Exception|undefined'),
  'ok "→"': RegExp('→'),
};

/// Ekrandaki (sahne dışı dahil) tüm metinler.
Set<String> _visibleTexts() {
  final out = <String>{};
  for (final e in find.byType(RichText, skipOffstage: false).evaluate()) {
    final ro = e.renderObject;
    if (ro is RenderParagraph) {
      final s = ro.text.toPlainText(includeSemanticsLabels: false).trim();
      if (s.isNotEmpty) out.add(s);
    }
  }
  for (final e in find.byType(EditableText, skipOffstage: false).evaluate()) {
    final w = e.widget as EditableText;
    final s = w.controller.text.trim();
    if (s.isNotEmpty) out.add(s);
  }
  return out;
}

void _scan(String route, List<String> problems) {
  for (final text in _visibleTexts()) {
    _rules.forEach((name, re) {
      if (re.hasMatch(text)) {
        problems.add('$route: $name → "${text.replaceAll('\n', ' ')}"');
      }
    });
  }
}

void main() {
  for (final persona in fakePersonas) {
    testWidgets('${persona.key}: ekrandaki yazılar kurallara uyar', (
      tester,
    ) async {
      final qa = QaProblems('copy_${persona.key}');
      try {
        final app = await launchQa(tester);
        await qaSignIn(tester, app, persona.key);
        final router = app.container.read(routerProvider);
        final problems = <String>{};
        for (final route in _routes(app)) {
          final policy = AccessPolicy(
            app.container.read(sessionControllerProvider).access,
          );
          final features = app.container.read(appConfigProvider).features;
          if (!RouteAccess.isAllowed(route, policy, features)) continue;
          qa.where = route;
          router.go(route);
          await pumpSteps(tester, const Duration(milliseconds: 900));
          await settleIo(tester, rounds: 4);
          final found = <String>[];
          _scan(route, found);
          // Tembel listeler: ana listeyi aşağı kaydırıp bir kez daha tara.
          final lists = find.byType(Scrollable);
          if (lists.evaluate().isNotEmpty) {
            final main = qaMainList(tester);
            for (var i = 0; i < 4; i++) {
              await tester.drag(
                main,
                const Offset(0, -500),
                warnIfMissed: false,
              );
              await pumpSteps(tester, const Duration(milliseconds: 300));
              _scan(route, found);
            }
          }
          problems.addAll(found);
          final e = tester.takeException();
          if (e != null) problems.add('$route → istisna: $e');
        }
        qa.items.addAll(problems);
        await tester.pumpWidget(const SizedBox());
      } catch (e, st) {
        qa.add(
          'beklenmeyen: ${e.toString().split('\n').take(8).join(' ')} @ '
          '${st.toString().split('\n').where((l) => l.contains('shell-common')).take(3).join(' | ')}',
        );
      } finally {
        qa.finish();
      }
    });
  }
}

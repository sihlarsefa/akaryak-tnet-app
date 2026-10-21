// QA SC-01c: Bildirimler alt menüde bir sekme olan kullanıcıda (merkez, şoför) tam ekran bir ayrıntı
// sayfasındayken zil (`AppChrome.onOpenNotifications` → `router.push('/notifications')`) kabuk
// sayfasını kök gezginde ikinci kez oluşturur. Ayrıntı: inbox_tab_route_test.dart.
import 'dart:async';

import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_support.dart';

void main() {
  testWidgets(
    'SC-01c merkez: onay ayrıntısındayken zil (/notifications) [QA SC-01]',
    (tester) async {
      final qa = QaProblems('sc01_bell_merkez');
      try {
        final app = await launchQa(tester);
        await qaSignIn(tester, app, 'merkez');
        final router = app.container.read(routerProvider);
        final approval = app.harness.server.world.approvals.first['id'];
        unawaited(router.push('/approvals/$approval'));
        await pumpSteps(tester, const Duration(milliseconds: 1200));
        await settleIo(tester);
        qa.check(tester, 'onay ayrıntısı');
        qa.where = 'zil → /notifications';
        // Zilin kendi geri çağrısı (`_ChromeHost.onOpenNotifications`).
        final chrome = tester.widget<AppChrome>(find.byType(AppChrome).first);
        chrome.onOpenNotifications!();
        await pumpSteps(tester, const Duration(milliseconds: 1200));
        await settleIo(tester);
        qa.check(tester, 'zil');
        if (app.location != '/notifications') {
          qa.add('zil: konum ${app.location}');
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

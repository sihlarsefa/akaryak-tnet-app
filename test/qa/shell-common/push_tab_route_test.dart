// QA SC-01b: oturum açıkken, kabuğun üstünde tam ekran bir sayfa (gelen kutusu) açıkken gelen push
// dokunuşu alt menü sekmesi olan bir rotaya (`/dispatch`) gidiyor: `AppRouter._consumePendingLink`
// `router.push` kullanır ve kök gezginde kabuk sayfası ikinci kez oluşur. Ayrıntı: inbox_tab_route_test.
import 'dart:async';

import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/push/local_notifications.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_support.dart';

void main() {
  testWidgets(
    'SC-01b sevkiyat: tam ekran sayfadayken /dispatch push dokunuşu [QA SC-01]',
    (tester) async {
      final qa = QaProblems('sc01_push_sevkiyat');
      try {
        final app = await launchQa(tester);
        await qaSignIn(tester, app, 'sevkiyat');
        unawaited(app.container.read(routerProvider).push('/notifications'));
        await pumpSteps(tester, const Duration(milliseconds: 1200));
        await settleIo(tester);
        qa.where = 'push /dispatch (gelen kutusu açıkken)';
        LocalNotifications.onTap!('/dispatch');
        await pumpSteps(tester, const Duration(milliseconds: 1500));
        await settleIo(tester);
        qa.check(tester, 'push /dispatch');
        if (app.location != '/dispatch') {
          qa.add('push /dispatch: konum ${app.location}');
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

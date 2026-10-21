// QA SC-01: alt menü sekmesi olan bir rota (ör. muhasebe için `/payments`, sevkiyat için `/dispatch`),
// kabuğun üstünde tam ekran açılmış bir sayfadan (Bildirimler gelen kutusu) `push` ile açılınca kök
// gezginde aynı kabuk sayfası iki kez yer alır: "!keyReservation.contains(key)" / "A GlobalKey was used
// multiple times" ve uygulama bozulur. Bildirim satırına dokunma, oturum açıkken push dokunuşu
// (`_consumePendingLink`) ve uygulama içi bildirimin "Aç" düğmesi aynı yolu izler.
//
// Her senaryo kendi testinde; ilk hata kök gezgin anahtarını (genel `rootNavigatorKey`) bozduğu için
// aynı dosyadaki sonraki testleri de etkiler — bu yüzden her biri yalnızca kendi hatasını raporlar.
import 'dart:async';

import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/features/notifications/presentation/notifications_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_support.dart';

Future<void> _inboxTap(
  WidgetTester tester,
  String persona,
  String route,
) async {
  final qa = QaProblems('sc01_inbox_${persona}_${route.replaceAll('/', '_')}');
  try {
    final app = await launchQa(tester);
    await qaSignIn(tester, app, persona);
    final world = app.harness.server.world;
    final n = world.notifications.firstWhere(
      (n) => n['userId'] == 'u-$persona' && n['route'] == route,
    );
    qa.where = 'gelen kutusu';
    unawaited(app.container.read(routerProvider).push('/notifications'));
    await pumpSteps(tester, const Duration(milliseconds: 1200));
    await settleIo(tester);
    expect(find.byType(NotificationsPage), findsOneWidget);
    qa.where = 'bildirime dokun ($route)';
    await qaTap(tester, find.text(n['title'] as String).first);
    await pumpSteps(tester, const Duration(milliseconds: 1500));
    await settleIo(tester);
    qa.check(tester, 'bildirim → $route');
    if (app.location != route) {
      qa.add('bildirim → $route: konum ${app.location}');
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
}

void main() {
  testWidgets(
    'SC-01a muhasebe: gelen kutusunda /payments bildirimine dokunma [QA SC-01]',
    (tester) => _inboxTap(tester, 'muhasebe', '/payments'),
  );
}

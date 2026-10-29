// v4 B14 (QA SC-01): Profil › "Asistana sorun". Şoförde Asistan bir alt menü sekmesidir: satır
// sekmeye `go` ile geçer (`openAppLocation`); `push` sekme sayfasını sekmenin üstüne ikinci kez
// koyardı. Diğer rollerde Asistan sekme değildir: sayfa Profil'in üstüne açılır.
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/features/profile/copy.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../qa/shell-common/qa_support.dart';

Future<void> _askAssistant(
  WidgetTester tester,
  String persona, {
  required bool tab,
}) async {
  final qa = QaProblems('b14_profile_assistant_$persona');
  try {
    final app = await launchQa(tester);
    await qaSignIn(tester, app, persona);
    final router = app.container.read(routerProvider);
    router.go('/profile');
    await pumpSteps(tester, const Duration(milliseconds: 1200));
    await settleIo(tester);
    qa.check(tester, 'Profil');
    final row = find.text(ProfileCopy.askAssistant);
    await qaScrollTo(tester, row);
    qa.where = 'Asistana sorun';
    await qaTap(tester, row.first);
    await pumpSteps(tester, const Duration(milliseconds: 1500));
    await settleIo(tester);
    qa.check(tester, 'Asistana sorun');
    expect(app.location, '/assistant');
    expect(router.canPop(), tab ? isFalse : isTrue);
    await tester.pumpWidget(const SizedBox());
  } catch (e, st) {
    qa.add(
      'beklenmeyen: ${e.toString().split('\n').take(8).join(' ')} @ '
      '${st.toString().split('\n').where((l) => l.contains('profile')).take(3).join(' | ')}',
    );
  } finally {
    qa.finish();
  }
}

void main() {
  testWidgets(
    'şoför: Profil › "Asistana sorun" Asistan sekmesine geçer',
    (tester) => _askAssistant(tester, 'sofor', tab: true),
  );

  testWidgets(
    'şirket yöneticisi: Profil › "Asistana sorun" asistanı Profil\'in üstüne açar',
    (tester) => _askAssistant(tester, 'musteri', tab: false),
  );
}

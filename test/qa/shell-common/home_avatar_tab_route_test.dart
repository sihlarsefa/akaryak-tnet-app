// QA SC-01 kuralı (v4 tur 2, B14): ana sayfanın avatarı Profil'i açar; Profil bir rolün alt menü
// sekmesiyse (Merkez: Ana sayfa · Onaylar · Bildirim · Profil) `push` Profil'i ana sayfa sekmesinin
// üstüne iter — alt menü hâlâ "Ana sayfa" der, geri tuşu ile alt menü ayrı yerleri gösterir (tam ekran
// bir sayfadan aynı `push` kabuğu ikinci kez kurar). Avatar `openAppLocation` ile sekmeye geçer.
import 'package:akaryakitnet/app/shell/platform_home.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_support.dart';

void main() {
  testWidgets('SC-01 merkez: ana sayfa avatarı → Profil sekmesi [B14]', (
    tester,
  ) async {
    final qa = QaProblems('sc01_merkez_avatar_profile');
    try {
      final app = await launchQa(tester);
      await qaSignIn(tester, app, 'merkez');
      await pumpSteps(tester, const Duration(milliseconds: 1200));
      await settleIo(tester);
      expect(find.byType(PlatformHome), findsOneWidget);
      qa.where = 'avatar';
      await qaTap(tester, find.text(PlatformHome.company).first);
      await pumpSteps(tester, const Duration(milliseconds: 1500));
      await settleIo(tester);
      qa.check(tester, 'avatar → /profile');
      if (app.location != '/profile') {
        qa.add('avatar → /profile: konum ${app.location}');
      }
      // Sekmeye geçildi (Profil seçili; ana sayfanın üstüne itilmiş bir sayfa değil): geri tuşu
      // ve alt menü aynı yeri söyler.
      final bar = tester.widget<AnimatedBottomBar>(
        find.byType(AnimatedBottomBar),
      );
      if (bar.currentIndex != bar.items.length - 1) {
        qa.add('Profil sekmesi seçili değil: ${bar.currentIndex}');
      }
      expect(find.byType(PlatformHome, skipOffstage: false), findsOneWidget);
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

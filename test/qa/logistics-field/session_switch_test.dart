// QA logistics-field LF-3: aynı telefonda çıkış → başka kullanıcıyla giriş. Yönlendirici çıkışta
// bulunulan konumu "giriş sonrası açılacak" diye saklar (router.dart computeRedirect adım 3) ve
// yeni kullanıcı kendi ana sayfası yerine önceki kullanıcının son sayfasında açılır.
import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/routing/nav_keys.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'qa_kit.dart';

void main() {
  testWidgets('[QA LF-3] şoför Profil\'den çıkar, sevkiyat girer → sevkiyatın '
      'ilk sekmesi açılır (önceki kullanıcının sayfası değil)', (tester) async {
    final app = await QaApp.start(tester, persona: 'sofor');
    await tapTab(tester, 'Profil');
    noErrors(tester, 'profil');
    GoRouter router() => GoRouter.of(rootNavigatorKey.currentContext!);
    String where() => router().routerDelegate.currentConfiguration.uri.path;
    expect(where(), '/profile');
    await scrollTap(tester, find.text('Çıkış yap'));
    final confirm = find.descendant(
      of: find.byType(ConfirmSheet),
      matching: find.text('Çıkış yap'),
    );
    if (confirm.evaluate().isNotEmpty) {
      await scrollTap(tester, confirm.last);
    }
    await steps(tester, const Duration(seconds: 1));
    await io(tester);
    expect(
      app.container.read(sessionControllerProvider),
      isA<SessionUnauthenticated>(),
    );
    expect(find.text('Giriş yap'), findsWidgets);

    await tester.runAsync(() async {
      final s = app.container.read(sessionControllerProvider.notifier);
      await s.loginWithPassword('sevkiyat', 'demo');
    });
    await steps(tester, const Duration(seconds: 2));
    await io(tester);
    final layout = app.container.read(navLayoutProvider);
    final location = where();
    // ignore: avoid_print
    print(
      'QA LF-3 after login: $location (initial ${layout.initialLocation}) '
      'texts=${visibleTexts(tester).take(30).join(' | ')}',
    );
    expect(
      location,
      layout.initialLocation,
      reason: 'sevkiyat önceki kullanıcının sayfasında ($location) açıldı',
    );
    expect(find.byType(AnimatedBottomBar), findsOneWidget);
    await app.close(tester);
    // QA LF-3 düzeltildi: çıkışta konum saklanmaz.
  });
}

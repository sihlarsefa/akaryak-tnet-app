// QA shell-common: uygulama düzeyi hatalar gerçek uygulamada.
//
// - Sunucu 500: sekme kökü hata durumunu "Tekrar dene" ile gösterir (sonsuz iskelet yok); sunucu
//   düzelince "Tekrar dene" içeriği getirir.
// - Bağlantı yok (bağlantı sağlayıcısı çevrimdışı): çevrimdışı satırı görünür, sayfa çökmez.
// - Oturum sunucuda kapatıldı (tüm cihazlar): sonraki istek girişe düşürür, mesaj gösterilir.
// - Erişim belirteci süresi doldu: yenileme sessizce yapılır, kullanıcı oturumda kalır.
// - Giriş: hatalı şifre mesajı, boş alan doğrulaması, telefonla girişte geçersiz numara.
import 'dart:async';

import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/offline/connectivity.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_support.dart';

Future<void> _waitFor(WidgetTester tester, bool Function() cond) async {
  for (var k = 0; k < 40 && !cond(); k++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final key in const ['musteri', 'sahip', 'sofor', 'saha', 'merkez']) {
    testWidgets('$key: sunucu 500 → hata durumu + Tekrar dene → içerik', (
      tester,
    ) async {
      final qa = QaProblems('err500_$key');
      try {
        final app = await launchQa(tester);
        await qaSignIn(tester, app, key);
        final layout = app.container.read(navLayoutProvider);
        final router = app.container.read(routerProvider);
        app.harness.server.failureMode = FakeFailureMode.serverError;
        // İkinci sekme (taze yükleme) ve bildirimler.
        final target = layout.bar.length > 1
            ? layout.bar[1].path
            : '/notifications';
        router.go(target);
        await pumpSteps(tester, const Duration(milliseconds: 1500));
        await settleIo(tester);
        await pumpSteps(tester, const Duration(milliseconds: 1500));
        final e = tester.takeException();
        if (e != null) qa.add('500 $target → istisna: $e');
        final errorShown =
            find.byType(ErrorState).evaluate().isNotEmpty ||
            find.textContaining('ulaşılamıyor').evaluate().isNotEmpty ||
            find.textContaining('yüklenemedi').evaluate().isNotEmpty;
        if (!errorShown) {
          qa.add(
            '500 $target: hata durumu/uyarısı yok '
            '(iskelet: ${find.byType(Shimmer).evaluate().length}, '
            'spinner: ${qaHasSpinner()})',
          );
        }
        // Sunucu düzelir, Tekrar dene.
        app.harness.server.failureMode = FakeFailureMode.none;
        final retry = find.text('Tekrar dene');
        if (retry.evaluate().isNotEmpty) {
          await qaTap(tester, retry.first);
          await pumpSteps(tester, const Duration(milliseconds: 1200));
          await settleIo(tester);
          await pumpSteps(tester, const Duration(milliseconds: 800));
          final errs = qaErrorTexts();
          if (errs.isNotEmpty) qa.add('Tekrar dene sonrası hâlâ: $errs');
        } else {
          qa.add('500 $target: "Tekrar dene" yok');
        }
        qa.check(tester, 'tekrar dene');
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

  testWidgets('çevrimdışı: bant görünür, sekmeler çökmez (sahip)', (
    tester,
  ) async {
    final qa = QaProblems('offline_sahip');
    try {
      final online = StreamController<bool>.broadcast();
      final app = await launchQa(
        tester,
        overrides: [connectivityProvider.overrideWith((ref) => online.stream)],
      );
      online.add(true);
      await qaSignIn(tester, app, 'sahip');
      app.harness.server.failureMode = FakeFailureMode.offline;
      online.add(false);
      await pumpSteps(tester, const Duration(milliseconds: 800));
      final layout = app.container.read(navLayoutProvider);
      final bar = find.byType(AnimatedBottomBar);
      for (var t = 0; t < layout.bar.length; t++) {
        await tester.tap(
          find.descendant(of: bar, matching: find.text(layout.bar[t].barLabel)),
        );
        await pumpSteps(tester, const Duration(milliseconds: 1200));
        await settleIo(tester);
        final e = tester.takeException();
        if (e != null) qa.add('çevrimdışı ${layout.bar[t].label} → $e');
        if (find.textContaining('Çevrimdışı').evaluate().isEmpty &&
            find.textContaining('Bağlantı yok').evaluate().isEmpty &&
            find.textContaining('çevrimdışı').evaluate().isEmpty) {
          qa.add('çevrimdışı ${layout.bar[t].label}: çevrimdışı uyarısı yok');
        }
      }
      // Bağlantı gelir.
      app.harness.server.failureMode = FakeFailureMode.none;
      online.add(true);
      await pumpSteps(tester, const Duration(milliseconds: 1500));
      await settleIo(tester);
      final e = tester.takeException();
      if (e != null) qa.add('çevrimiçi dönüş → $e');
      await tester.pumpWidget(const SizedBox());
      await online.close();
    } catch (e, st) {
      qa.add(
        'beklenmeyen: ${e.toString().split('\n').take(8).join(' ')} @ '
        '${st.toString().split('\n').where((l) => l.contains('shell-common')).take(3).join(' | ')}',
      );
    } finally {
      qa.finish();
    }
  });

  // QA SC-03: demo derlemesinde "Oturumunuz kapatıldı" bandı demo kartlarının altında kalıyor.
  testWidgets('oturum sunucuda kapatıldı → giriş + mesaj (musteri) [QA SC-03]', (
    tester,
  ) async {
    final qa = QaProblems('revoked_musteri');
    try {
      final app = await launchQa(tester);
      await qaSignIn(tester, app, 'musteri');
      expect(app.session, isA<SessionAuthenticated>());
      app.harness.server.auth.revokeAll('musteri');
      // Sonraki istek: bildirimler sayfası.
      unawaited(app.container.read(routerProvider).push('/notifications'));
      await pumpSteps(tester, const Duration(milliseconds: 600));
      await _waitFor(tester, () => app.session is SessionUnauthenticated);
      await pumpSteps(tester, const Duration(seconds: 1));
      final s = app.session;
      if (s is! SessionUnauthenticated) {
        qa.add('kapatılan oturum: hâlâ ${s.runtimeType}');
      } else {
        if (app.location != '/login') {
          qa.add('kapatılan oturum: konum ${app.location}');
        }
        if (s.message == null) qa.add('kapatılan oturum: mesaj yok');
        // Mesaj ilk ekranda (kaydırmadan) görünmeli: kullanıcı neden çıkarıldığını görür.
        final msg = find.text(s.message ?? '—');
        final screenH =
            tester.view.physicalSize.height / tester.view.devicePixelRatio;
        final visible =
            msg.evaluate().isNotEmpty &&
            tester.getRect(msg.first).top < screenH;
        if (!visible) {
          try {
            await qaScrollTo(tester, msg);
          } catch (_) {}
          qa.add(
            msg.evaluate().isEmpty
                ? 'kapatılan oturum: giriş ekranında mesaj hiç yok'
                : 'kapatılan oturum: mesaj ilk ekranda görünmüyor, ancak '
                      'kaydırınca (demo kartlarının altında)',
          );
        }
      }
      final e = tester.takeException();
      if (e != null) qa.add('kapatılan oturum → $e');
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

  testWidgets('erişim belirteci süresi doldu → sessiz yenileme (sahip)', (
    tester,
  ) async {
    final qa = QaProblems('expired_sahip');
    try {
      final app = await launchQa(tester);
      await qaSignIn(tester, app, 'sahip');
      app.harness.server.auth.expireAllAccessTokens();
      unawaited(app.container.read(routerProvider).push('/notifications'));
      await pumpSteps(tester, const Duration(milliseconds: 600));
      await settleIo(tester);
      await pumpSteps(tester, const Duration(seconds: 1));
      if (app.session is! SessionAuthenticated) {
        qa.add('süresi dolan belirteç: oturum ${app.session.runtimeType}');
      }
      final errs = qaErrorTexts();
      if (errs.isNotEmpty) qa.add('süresi dolan belirteç: $errs');
      qa.check(tester, 'yenileme');
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

  testWidgets('giriş: boş alan, hatalı şifre, geçersiz telefon', (
    tester,
  ) async {
    final qa = QaProblems('login_errors');
    try {
      final app = await launchQa(tester);
      // Boş (demo derlemesinde form demo kartlarının altında: önce kaydır).
      await qaScrollTo(tester, find.widgetWithText(AknButton, 'Giriş yap'));
      await qaTap(tester, find.widgetWithText(AknButton, 'Giriş yap').first);
      await pumpSteps(tester, const Duration(milliseconds: 400));
      if (find
          .text('Kullanıcı adınızı ya da e-postanızı girin.')
          .evaluate()
          .isEmpty) {
        qa.add('boş giriş: kullanıcı adı hatası yok');
      }
      // Hatalı şifre.
      await tester.enterText(qaField('E-posta ya da kullanıcı adı'), 'musteri');
      await tester.enterText(qaField('Şifre'), 'yanlis');
      await qaTap(tester, find.widgetWithText(AknButton, 'Giriş yap').first);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await pumpSteps(tester, const Duration(seconds: 1));
      if (app.session is SessionAuthenticated) {
        qa.add('hatalı şifreyle giriş yapıldı');
      }
      if (find.text('Giriş yapılamadı').evaluate().isEmpty) {
        qa.add('hatalı şifre: "Giriş yapılamadı" bandı yok');
      }
      final pw = tester.widget<TextField>(qaField('Şifre'));
      if (pw.controller!.text.isNotEmpty) {
        qa.add('hatalı şifre: alan temizlenmedi');
      }
      // Telefon: geçersiz numara.
      final phoneMode = find.text('Numara ile');
      try {
        await qaScrollTo(tester, phoneMode);
      } catch (_) {}
      if (phoneMode.evaluate().isNotEmpty) {
        await qaTap(tester, phoneMode.first);
        await pumpSteps(tester, const Duration(milliseconds: 600));
        await qaScrollTo(tester, qaField('Cep telefonu'));
        await tester.enterText(qaField('Cep telefonu'), '0212 000 00 00');
        await qaTap(tester, find.widgetWithText(AknButton, 'Kod gönder').first);
        await pumpSteps(tester, const Duration(milliseconds: 600));
        if (app.location != '/login') {
          qa.add('geçersiz cep numarasıyla kod ekranına geçildi');
        }
        // Kayıtsız numara.
        await tester.enterText(qaField('Cep telefonu'), '0555 999 99 99');
        await qaTap(tester, find.widgetWithText(AknButton, 'Kod gönder').first);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await pumpSteps(tester, const Duration(seconds: 1));
        qa.add('BİLGİ kayıtsız numara sonrası konum: ${app.location}');
      }
      qa.check(tester, 'giriş hataları');
      qa.items.removeWhere((i) => i.startsWith('BİLGİ'));
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

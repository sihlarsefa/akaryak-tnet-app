// QA shell-common: Profil ayarları, asistan ve istatistik gerçek uygulamada (gerçek yönlendirici).
//
// - Şifre değiştir (başarı) → giriş ekranı + "Güvenlik bilgileriniz değişti" → yeniden giriş.
// - Hesabımı sil → onay → "Talebiniz alındı" → "Tamam" → giriş ekranı + "Hesabınız kapatıldı."
// - Telefonla giriş: Profil satırı → doğrulama sayfası açılır, geri dönülür.
// - Asistan: aydınlatma → "Kabul ediyorum" → soru gönderilir → yanıt gelir.
// - /stats: kitlede olan her persona için sayfa açılır, hata yok.
import 'dart:async';

import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/auth/access_policy.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/routing/route_access.dart';
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

Future<void> _openProfile(WidgetTester tester, QaApp app) async {
  app.container.read(routerProvider).go('/profile');
  await pumpSteps(tester, const Duration(milliseconds: 1200));
  await settleIo(tester);
}

void main() {
  testWidgets('şifre değiştir → giriş ekranı → yeniden giriş (musteri)', (
    tester,
  ) async {
    final qa = QaProblems('profile_password');
    try {
      final app = await launchQa(tester);
      await qaSignIn(tester, app, 'musteri');
      await _openProfile(tester, app);
      final pwRow = find.text('Şifreyi değiştir');
      await qaScrollTo(tester, pwRow);
      await qaTap(tester, pwRow.first);
      await pumpSteps(tester, const Duration(milliseconds: 1000));
      qa.check(tester, 'şifre sayfası');
      await tester.enterText(qaField('Mevcut şifre'), 'demo');
      await tester.enterText(qaField('Yeni şifre'), 'Yeni12345');
      await tester.enterText(qaField('Yeni şifre (tekrar)'), 'Yeni12345');
      await pumpSteps(tester, const Duration(milliseconds: 300));
      await qaTap(tester, find.widgetWithText(AknButton, 'Şifreyi değiştir'));
      await _waitFor(tester, () => app.session is SessionUnauthenticated);
      await pumpSteps(tester, const Duration(seconds: 1));
      if (app.session is! SessionUnauthenticated) {
        qa.add('şifre değişti ama oturum ${app.session.runtimeType}');
      }
      if (app.location != '/login') {
        qa.add('şifre değişti ama konum ${app.location}');
      }
      if (find
          .text('Güvenlik bilgileriniz değişti; yeniden giriş yapın.')
          .evaluate()
          .isEmpty) {
        qa.add('şifre değişti: giriş ekranında açıklama yok');
      }
      // Yeni şifreyle giriş.
      await tester.enterText(qaField('E-posta ya da kullanıcı adı'), 'musteri');
      // Sahte kipte şifre hep `demo` (QA SC-04: yeni şifre kabul edilmiyor; düşük önem).
      await tester.enterText(qaField('Şifre'), 'demo');
      await qaTap(tester, find.widgetWithText(AknButton, 'Giriş yap').first);
      await _waitFor(tester, () => app.session is SessionAuthenticated);
      if (app.session is! SessionAuthenticated) {
        qa.add('şifre değişikliğinden sonra yeniden giriş yapılamadı');
      }
      await pumpSteps(tester, const Duration(seconds: 2));
      await settleIo(tester);
      qa.check(tester, 'yeniden giriş');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    } catch (e, st) {
      qa.add(
        'beklenmeyen: ${e.toString().split('\n').take(8).join(' ')} @ '
        '${st.toString().split('\n').where((l) => l.contains('shell-common')).take(3).join(' | ')}',
      );
    } finally {
      qa.finish();
    }
  });

  // QA SC-04: sahte kipte şifre değişikliği "başarılı" görünür ama yeni şifreyle giriş reddedilir
  // (sahte giriş yalnızca `demo` kabul eder). Düzeltilince `skip` kaldırılır.
  testWidgets('şifre değiştir → yeni şifreyle giriş (musteri) [QA SC-04]', (
    tester,
  ) async {
    final qa = QaProblems('sc04_new_password');
    try {
      final app = await launchQa(tester);
      await qaSignIn(tester, app, 'musteri');
      await _openProfile(tester, app);
      final pwRow = find.text('Şifreyi değiştir');
      await qaScrollTo(tester, pwRow);
      await qaTap(tester, pwRow.first);
      await pumpSteps(tester, const Duration(milliseconds: 1000));
      await tester.enterText(qaField('Mevcut şifre'), 'demo');
      await tester.enterText(qaField('Yeni şifre'), 'Yeni12345');
      await tester.enterText(qaField('Yeni şifre (tekrar)'), 'Yeni12345');
      await qaTap(tester, find.widgetWithText(AknButton, 'Şifreyi değiştir'));
      await _waitFor(tester, () => app.session is SessionUnauthenticated);
      await pumpSteps(tester, const Duration(seconds: 1));
      await qaScrollTo(tester, qaField('E-posta ya da kullanıcı adı'));
      await tester.enterText(qaField('E-posta ya da kullanıcı adı'), 'musteri');
      await tester.enterText(qaField('Şifre'), 'Yeni12345');
      final login = find.widgetWithText(AknButton, 'Giriş yap');
      await qaScrollTo(tester, login);
      await qaTap(tester, login.first);
      await _waitFor(tester, () => app.session is SessionAuthenticated);
      if (app.session is! SessionAuthenticated) {
        qa.add('yeni şifreyle giriş yapılamadı');
      }
      await pumpSteps(tester, const Duration(seconds: 2));
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    } catch (e, st) {
      qa.add(
        'beklenmeyen: ${e.toString().split('\n').take(8).join(' ')} @ '
        '${st.toString().split('\n').where((l) => l.contains('shell-common')).take(3).join(' | ')}',
      );
    } finally {
      qa.finish();
    }
  });

  testWidgets('hesabımı sil → Talebiniz alındı → Tamam → giriş (talep)', (
    tester,
  ) async {
    final qa = QaProblems('profile_delete');
    try {
      final app = await launchQa(tester);
      await qaSignIn(tester, app, 'talep');
      await _openProfile(tester, app);
      final del = find.text('Hesabımı sil');
      await qaScrollTo(tester, del);
      await qaTap(tester, del.last);
      await pumpSteps(tester, const Duration(milliseconds: 1000));
      qa.check(tester, 'hesap silme sayfası');
      if (app.location != '/profile/delete-account') {
        qa.add('Hesabımı sil satırı açmadı: ${app.location}');
      }
      await qaScrollTo(tester, qaField('Onay için şifreniz'));
      await tester.enterText(qaField('Onay için şifreniz'), 'demo');
      final understand = find.text(
        'Hesabımın kapanacağını ve kişisel verilerimin silineceğini anladım.',
      );
      await qaScrollTo(tester, understand);
      await qaTap(tester, understand);
      await pumpSteps(tester, const Duration(milliseconds: 300));
      await qaTap(tester, find.widgetWithText(AknButton, 'Hesabımı sil').last);
      await pumpSteps(tester, const Duration(milliseconds: 800));
      if (find.text('Hesabınız kapatılsın mı?').evaluate().isEmpty) {
        qa.add('hesap silme: onay sorusu yok');
      } else {
        final confirm = find.descendant(
          of: find.byType(Dialog).evaluate().isNotEmpty
              ? find.byType(Dialog)
              : find.byType(BottomSheet),
          matching: find.text('Hesabımı sil'),
        );
        await tester.tap(confirm.last);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await pumpSteps(tester, const Duration(milliseconds: 1200));
        if (find.text('Talebiniz alındı').evaluate().isEmpty) {
          qa.add('hesap silme: "Talebiniz alındı" yok (konum ${app.location})');
        } else {
          await qaTap(tester, find.text('Tamam').last);
          await _waitFor(tester, () => app.session is SessionUnauthenticated);
          await pumpSteps(tester, const Duration(seconds: 1));
        }
        if (app.session is! SessionUnauthenticated) {
          qa.add('hesap silindi ama oturum ${app.session.runtimeType}');
        }
        if (app.location != '/login') {
          qa.add('hesap silindi ama konum ${app.location}');
        }
        if (find.text('Hesabınız kapatıldı.').evaluate().isEmpty) {
          qa.add('hesap silindi: giriş ekranında "Hesabınız kapatıldı." yok');
        }
      }
      qa.check(tester, 'hesap silme');
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

  testWidgets('telefonla giriş satırı → doğrulama sayfası → geri (sahip)', (
    tester,
  ) async {
    final qa = QaProblems('profile_phone');
    try {
      final app = await launchQa(tester);
      await qaSignIn(tester, app, 'sahip');
      await _openProfile(tester, app);
      final row = find.textContaining('Telefonla giriş');
      try {
        await qaScrollTo(tester, row);
      } catch (_) {}
      if (row.evaluate().isEmpty) {
        qa.add('Profil: telefonla giriş satırı yok');
      } else {
        await qaTap(tester, row.first);
        await pumpSteps(tester, const Duration(milliseconds: 1200));
        await settleIo(tester);
        qa.check(tester, 'telefon doğrulama');
        if (app.location != '/profile/phone') {
          qa.add('telefonla giriş satırı açmadı: ${app.location}');
        }
        app.container.read(routerProvider).pop();
        await pumpSteps(tester, const Duration(milliseconds: 800));
        if (app.location != '/profile') {
          qa.add('telefon doğrulamadan geri: ${app.location}');
        }
      }
      qa.check(tester, 'telefon');
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

  for (final key in const ['musteri', 'sahip', 'sofor']) {
    testWidgets('asistan: aydınlatma → kabul → soru → yanıt ($key)', (
      tester,
    ) async {
      final qa = QaProblems('assistant_$key');
      try {
        final app = await launchQa(tester);
        await qaSignIn(tester, app, key);
        unawaited(app.container.read(routerProvider).push('/assistant'));
        await pumpSteps(tester, const Duration(milliseconds: 1200));
        await settleIo(tester);
        qa.check(tester, 'asistan');
        final accept = find.text('Kabul ediyorum');
        if (accept.evaluate().isNotEmpty) {
          await qaTap(tester, accept.first);
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 60)),
          );
          await pumpSteps(tester, const Duration(milliseconds: 1200));
          await settleIo(tester);
        }
        final input = find.byType(TextField);
        if (input.evaluate().isEmpty) {
          qa.add('asistan: mesaj alanı yok');
        } else {
          await tester.enterText(input.last, 'Siparişim ne zaman gelir?');
          await pumpSteps(tester, const Duration(milliseconds: 200));
          final send = find.bySemanticsLabel('Gönder');
          if (send.evaluate().isNotEmpty) {
            await tester.tap(send.last);
          } else {
            await tester.testTextInput.receiveAction(TextInputAction.send);
          }
          for (var k = 0; k < 10; k++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 40)),
            );
            await tester.pump(const Duration(milliseconds: 400));
          }
          await pumpSteps(tester, const Duration(seconds: 3));
          if (find.text('Siparişim ne zaman gelir?').evaluate().isEmpty) {
            qa.add('asistan: gönderilen soru sohbette yok');
          }
          if (find.text('Yanıt yararlı oldu mu?').evaluate().isEmpty &&
              find.textContaining('Yararlı').evaluate().isEmpty) {
            qa.add('asistan: yanıt gelmedi (geri bildirim düğmeleri yok)');
          }
        }
        qa.check(tester, 'asistan yanıt');
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

  // QA SC-02: mix_chart.dart Row 360 dp'de taşıyor (sahip, mudur, satis, saha, onay "Bu yıl", …).
  testWidgets('/stats: kitledeki her persona sayfayı hatasız açar [QA SC-02]', (
    tester,
  ) async {
    final qa = QaProblems('stats_all');
    try {
      for (final p in fakePersonas) {
        final app = await launchQa(tester);
        await qaSignIn(tester, app, p.key);
        final policy = AccessPolicy(
          app.container.read(sessionControllerProvider).access,
        );
        final allowed = RouteAccess.statsAudience(policy);
        if (!allowed) {
          await tester.pumpWidget(const SizedBox());
          continue;
        }
        unawaited(app.container.read(routerProvider).push('/stats'));
        await pumpSteps(tester, const Duration(milliseconds: 1500));
        await settleIo(tester);
        await pumpSteps(tester, const Duration(milliseconds: 1500));
        qa.check(tester, '${p.key} /stats');
        if (app.location != '/stats') {
          qa.add('${p.key}: /stats açılmadı (${app.location})');
        }
        // Dönem seçimi: "Bu yıl" varsa dokun.
        for (final label in const ['Geçen ay', 'Çeyrek', 'Bu yıl', 'Yıl']) {
          final f = find.text(label);
          if (f.evaluate().isNotEmpty) {
            await qaTap(tester, f.first);
            await pumpSteps(tester, const Duration(milliseconds: 800));
            await settleIo(tester);
            qa.check(tester, '${p.key} /stats $label');
          }
        }
        await tester.pumpWidget(const SizedBox());
      }
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

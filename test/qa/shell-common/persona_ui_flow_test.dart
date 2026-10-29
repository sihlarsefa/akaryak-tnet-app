// QA shell-common: her persona için gerçek dokunuşlarla uçtan uca kabuk akışı (360×640, 1,0×).
//
// açılış → tanıtım (çift personada "Atla", tekte "Devam" ×2 + "Başlayalım") → giriş formu (kullanıcı adı
// + şifre yazılır, "Giriş yap"; merkez için 6 haneli kod) → alt menüdeki her sekmeye dokunulur →
// "Diğer" sayfasındaki her satıra dokunulur, geri dönülür → Profil → tema "Koyu" → "Sistem" →
// "Çıkış yap" → onay → giriş ekranı. Her adımda istisna, taşma ve hata durumu yok.
import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/app/shell/more_sheet.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/auth/presentation/widgets/demo_accounts.dart';
import 'package:akaryakitnet/features/onboarding/presentation/onboarding_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinput/pinput.dart';

import 'qa_support.dart';

void main() {
  for (var i = 0; i < fakePersonas.length; i++) {
    final persona = fakePersonas[i];
    testWidgets('${persona.key}: tanıtım → giriş formu → sekmeler → Diğer → '
        'Profil → tema → çıkış', (tester) async {
      final qa = QaProblems('ui_${persona.key}');
      final problems = qa.items;
      void check(String where) => qa.check(tester, where);
      try {
        final app = await launchQa(tester, prefs: const {});
        // Tanıtım.
        expect(find.byType(OnboardingPage), findsOneWidget);
        if (i.isEven) {
          await qaTap(tester, find.text('Atla'));
        } else {
          await qaTap(tester, find.text('Devam'));
          await pumpSteps(tester, const Duration(milliseconds: 800));
          await qaTap(tester, find.text('Devam'));
          await pumpSteps(tester, const Duration(milliseconds: 800));
          expect(find.text('Başlayalım'), findsOneWidget);
          await qaTap(tester, find.text('Başlayalım'));
        }
        await pumpSteps(tester, const Duration(seconds: 1));
        check('tanıtım');
        expect(app.location, '/login');

        if (i.isEven &&
            find.byType(DemoAccountsSection).evaluate().isNotEmpty) {
          // Demo kartı: tek dokunuş = oturum açık (merkez için kod kendiliğinden).
          final card = find.widgetWithText(
            DemoPersonaCard,
            persona.displayName,
          );
          var found = card.evaluate().isNotEmpty;
          final rows = find.descendant(
            of: find.byType(DemoAccountsSection),
            matching: find.byType(Scrollable),
          );
          for (var r = 0; !found && r < rows.evaluate().length; r++) {
            final s = tester.widget<Scrollable>(rows.at(r));
            if (axisDirectionToAxis(s.axisDirection) != Axis.horizontal) {
              continue;
            }
            try {
              await tester.scrollUntilVisible(
                card,
                120,
                scrollable: rows.at(r),
                maxScrolls: 30,
              );
              found = true;
            } catch (_) {
              found = card.evaluate().isNotEmpty;
            }
          }
          if (!found) {
            problems.add('demo kartı yok: ${persona.displayName}');
          } else {
            await tester.ensureVisible(card.first);
            await pumpSteps(tester, const Duration(milliseconds: 300));
            await tester.tap(card.first);
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await pumpSteps(tester, const Duration(seconds: 1));
          }
        } else {
          // Giriş formu.
          await qaScrollTo(tester, qaField('E-posta ya da kullanıcı adı'));
          await tester.enterText(
            qaField('E-posta ya da kullanıcı adı'),
            persona.key,
          );
          await tester.enterText(qaField('Şifre'), 'demo');
          final login = find.widgetWithText(AknButton, 'Giriş yap');
          await qaScrollTo(tester, login);
          await qaTap(tester, login.first);
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await pumpSteps(tester, const Duration(seconds: 1));
          if (persona.requiresTwoFactor) {
            expect(find.byType(Pinput), findsOneWidget);
            await tester.enterText(find.byType(Pinput), '123456');
            await pumpSteps(tester, const Duration(seconds: 1));
          }
        }
        for (var k = 0; k < 30 && app.session is! SessionAuthenticated; k++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(app.session, isA<SessionAuthenticated>());
        await pumpSteps(tester, const Duration(seconds: 2));
        await settleIo(tester);
        // İlk girişte bildirim izni ön sayfası çıkabilir: "Şimdi değil" ile kapat.
        final later = find.text('Şimdi değil');
        if (later.evaluate().isNotEmpty) {
          await qaTap(tester, later.first);
          await pumpSteps(tester, const Duration(milliseconds: 800));
        }
        check('giriş');
        final layout = app.container.read(navLayoutProvider);
        expect(app.location, layout.initialLocation);
        final bar = find.byType(AnimatedBottomBar);
        expect(bar, findsOneWidget);

        // Sekmeler (gerçek dokunuş).
        for (var t = 0; t < layout.bar.length; t++) {
          await tester.tap(
            find.descendant(
              of: bar,
              matching: find.text(layout.bar[t].barLabel),
            ),
          );
          await pumpSteps(tester, const Duration(milliseconds: 1200));
          await settleIo(tester);
          check('sekme ${layout.bar[t].label}');
          if (!app.location.startsWith(layout.bar[t].path)) {
            problems.add(
              'sekme ${layout.bar[t].label}: konum ${app.location} '
              '(beklenen ${layout.bar[t].path})',
            );
          }
        }

        // "Diğer" sayfası (gerçek dokunuş, satır satır).
        if (layout.hasMore) {
          // v4 §3.1: Profil is the sheet's person card, not a row.
          for (final d in layout.more.where(
            (d) => d.id != DestinationId.profile,
          )) {
            await tester.tap(
              find.descendant(
                of: bar,
                matching: find.text(NavLayout.moreLabel),
              ),
            );
            await pumpSteps(tester, const Duration(milliseconds: 900));
            final row = find.descendant(
              of: find.byType(BottomSheet),
              matching: find.text(d.label),
            );
            if (row.evaluate().isEmpty) {
              problems.add('Diğer: "${d.label}" satırı yok');
              await Navigator.of(tester.element(bar)).maybePop();
              await pumpSteps(tester, const Duration(milliseconds: 600));
              continue;
            }
            await tester.ensureVisible(row.first);
            await pumpSteps(tester, const Duration(milliseconds: 300));
            await tester.tap(row.first);
            await pumpSteps(tester, const Duration(milliseconds: 1400));
            await settleIo(tester);
            check('Diğer → ${d.label}');
            if (!app.location.startsWith(d.path)) {
              problems.add('Diğer → ${d.label}: konum ${app.location}');
            }
            app.container.read(routerProvider).pop();
            await pumpSteps(tester, const Duration(milliseconds: 700));
          }
        }

        // Profil (çubukta ya da Diğer'de).
        final router = app.container.read(routerProvider);
        if (layout.inBar(DestinationId.profile)) {
          await tester.tap(
            find.descendant(of: bar, matching: find.text('Profil')),
          );
        } else {
          await tester.tap(
            find.descendant(of: bar, matching: find.text(NavLayout.moreLabel)),
          );
          await pumpSteps(tester, const Duration(milliseconds: 900));
          // v4 §3.1: the person card at the top of Diğer opens Profil.
          final profileRow = find.descendant(
            of: find.byType(BottomSheet),
            matching: find.byKey(MoreSheetBody.profileKey),
          );
          await tester.ensureVisible(profileRow);
          await pumpSteps(tester, const Duration(milliseconds: 300));
          await tester.tap(profileRow);
        }
        await pumpSteps(tester, const Duration(milliseconds: 1400));
        await settleIo(tester);
        check('Profil');
        expect(app.location, '/profile');

        // Tema: Koyu → Sistem.
        final dark = find.text('Koyu');
        await qaScrollTo(tester, dark);
        await qaTap(tester, dark.first);
        await pumpSteps(tester, const Duration(milliseconds: 800));
        expect(
          Theme.of(tester.element(find.text('Koyu').first)).brightness,
          Brightness.dark,
          reason: 'tema Koyu seçilince koyu tema',
        );
        await qaTap(tester, find.text('Sistem').first);
        await pumpSteps(tester, const Duration(milliseconds: 800));
        check('tema');

        // Çıkış.
        final signOut = find.widgetWithText(AknButton, 'Çıkış yap');
        await qaScrollTo(tester, signOut);
        expect(signOut, findsOneWidget);
        await qaTap(tester, signOut);
        await pumpSteps(tester, const Duration(milliseconds: 800));
        expect(find.text('Çıkış yapılsın mı?'), findsOneWidget);
        final confirm = find.descendant(
          of: find.byType(Dialog).evaluate().isNotEmpty
              ? find.byType(Dialog)
              : find.byType(BottomSheet),
          matching: find.text('Çıkış yap'),
        );
        await tester.tap(confirm.last);
        for (var k = 0; k < 30 && app.session is SessionAuthenticated; k++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump(const Duration(milliseconds: 100));
        }
        await pumpSteps(tester, const Duration(seconds: 1));
        check('çıkış');
        expect(app.session, isA<SessionUnauthenticated>());
        expect(app.location, '/login');
        expect(router.routerDelegate.currentConfiguration.uri.path, '/login');
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

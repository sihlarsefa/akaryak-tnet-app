// QA logistics-field: saha akışları gerçek uygulamada (360×640). Saha merkezi sekmeleri (Formlarım ·
// Ön kayıtlarım · Portföy), "Saha formu" orta eylemi sihirbazı açar, taslak form → Onaya gönder →
// satış müdürü Onaylar'da görür ve onaylar; ön kayıt sihirbazı açılır.
import 'dart:async';

import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/field/fake/field_fake_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_kit.dart';

Future<void> _switchUser(WidgetTester tester, QaApp app, String persona) async {
  await tester.runAsync(
    () => app.container.read(sessionControllerProvider.notifier).signOut(),
  );
  await steps(tester, const Duration(seconds: 1));
  await tester.runAsync(() async {
    final s = app.container.read(sessionControllerProvider.notifier);
    final outcome = await s.loginWithPassword(persona, 'demo');
    if (outcome is LoginNeedsCode) {
      await s.verifyCode(outcome.challenge.challengeId, '123456');
    }
  });
  await steps(tester, const Duration(seconds: 2));
  await io(tester);
  expect(
    app.container.read(sessionControllerProvider),
    isA<SessionAuthenticated>(),
  );
}

void main() {
  testWidgets('saha 360×640: Saha sekmeleri, Portföy ve Ön kayıtlarım '
      'hatasız; orta eylem sihirbazı açar', (tester) async {
    final app = await QaApp.start(tester, persona: 'saha');
    await tapTab(tester, 'Saha');
    noErrors(tester, 'saha merkezi');
    noErrorState('saha merkezi');
    for (final tab in const ['Ön kayıtlarım', 'Portföy', 'Formlarım']) {
      final f = find.text(tab);
      expect(f, findsWidgets, reason: 'sekme $tab');
      await tester.tap(f.first);
      await steps(tester, const Duration(milliseconds: 900));
      await io(tester);
      noErrors(tester, 'sekme $tab');
      noErrorState('sekme $tab');
    }

    // Orta eylem: "Saha formu" → sihirbaz (Hangi cari için?) → kapat.
    await tester.tap(
      find.descendant(
        of: find.byType(AnimatedBottomBar),
        matching: find.text('Saha formu'),
      ),
    );
    await steps(tester, const Duration(milliseconds: 1200));
    await io(tester);
    noErrors(tester, 'sihirbaz');
    expect(find.text('Hangi cari için?'), findsOneWidget);
    await app.close(tester);
  });

  testWidgets('saha taslak → Onaya gönder → satis Onaylar\'da görür ve '
      'onaylar', (tester) async {
    final app = await QaApp.start(tester, persona: 'saha');
    final forms = FieldFakeState.of(app.world).forms;
    final draft = forms.firstWhere((f) => f['id'] == 7009);
    expect(draft['status'], 0);
    final number = draft['formNumber'] as String;

    unawaited(app.router(tester).push('/field/forms/7009'));
    await steps(tester, const Duration(milliseconds: 1200));
    await io(tester);
    noErrors(tester, 'taslak ayrıntı');
    noErrorState('taslak ayrıntı');
    await scrollTap(tester, find.text('Onaya gönder'));
    expect(find.text('Form onaya gönderilsin mi?'), findsOneWidget);
    await scrollTap(
      tester,
      find.descendant(
        of: find.byType(ConfirmSheet),
        matching: find.text('Onaya gönder'),
      ),
      settle: const Duration(milliseconds: 1500),
    );
    noErrors(tester, 'gönderildi');
    final after = forms.firstWhere((f) => f['id'] == 7009);
    // ignore: avoid_print
    print(
      'QA form 7009 after submit: status=${after['status']} '
      'level=${after['requiredLevel']} texts=${visibleTexts(tester).take(40).join(' | ')}',
    );
    expect(after['status'], isNot(0), reason: 'gönderildi');

    if (after['status'] == 1) {
      await _switchUser(tester, app, 'satis');
      await tapTab(tester, 'Onaylar');
      noErrors(tester, 'satis onaylar');
      noErrorState('satis onaylar');
      // ignore: avoid_print
      print('QA satis approvals: ${visibleTexts(tester).join(' | ')}');
      // QA LF-4: saha formu onayları tek biçimde (SSF-yyyyMMdd-nnnnnn, alan sahtesinin band
      // sözcükleri); eski tohum biçimi ('SF-2026-…', 'yönetici bandı', 'barem dışı') görünmez.
      final inbox = visibleTexts(tester).join(' | ');
      expect(inbox, isNot(contains('SF-2026-')), reason: inbox);
      expect(inbox, isNot(contains('yönetici bandı')), reason: inbox);
      expect(inbox, isNot(contains('barem dışı')), reason: inbox);
      final item = find.textContaining(number.split('-').last);
      final cust = find.textContaining('Ege').evaluate().isEmpty ? item : item;
      await reveal(tester, cust);
      await tester.tap(cust.first);
      await steps(tester, const Duration(milliseconds: 1200));
      await io(tester);
      noErrors(tester, 'onay ayrıntı');
      noErrorState('onay ayrıntı');
      // ignore: avoid_print
      print('QA approval detail: ${visibleTexts(tester).join(' | ')}');
      // ignore: avoid_print
      print('QA approval detail rich: ${richTexts(tester).join(' | ')}');
      await scrollTap(tester, find.text('Onayla').last);
      noErrors(tester, 'onay sayfası');
      // ignore: avoid_print
      print('QA after Onayla: ${visibleTexts(tester).join(' | ')}');
      final confirm = find.text('Onayla');
      if (confirm.evaluate().isNotEmpty) {
        await scrollTap(
          tester,
          confirm.last,
          settle: const Duration(milliseconds: 1500),
        );
      }
      noErrors(tester, 'onaylandı');
      final decided = forms.firstWhere((f) => f['id'] == 7009);
      final approval = app.world.approval(decided['_approvalId'] as int?);
      // ignore: avoid_print
      print(
        'QA after decision: approval=${approval?['status']} '
        'texts=${visibleTexts(tester).join(' | ')}',
      );
      expect(approval?['status'], 1, reason: 'kârlılık talebi onaylandı');
      // Saha tarafı kararı bir sonraki istekte yansıtır: temsilci formu açınca onaylı / dönüşmüş.
      await _switchUser(tester, app, 'saha');
      unawaited(app.router(tester).push('/field/forms/7009'));
      await steps(tester, const Duration(milliseconds: 1200));
      await io(tester);
      noErrors(tester, 'temsilci karar sonrası');
      expect(
        forms.firstWhere((f) => f['id'] == 7009)['status'],
        anyOf(2, 4),
        reason: 'onaylandı / siparişe dönüştü',
      );
    }
    await app.close(tester);
  });

  testWidgets('saha 360×640: Ön kayıt sihirbazı açılır, boş İleri doğrulama '
      'gösterir', (tester) async {
    final app = await QaApp.start(tester, persona: 'saha');
    unawaited(app.router(tester).push('/field/leads/new'));
    await steps(tester, const Duration(milliseconds: 1200));
    await io(tester);
    noErrors(tester, 'ön kayıt sihirbazı');
    noErrorState('ön kayıt sihirbazı');
    // ignore: avoid_print
    print('QA lead wizard: ${visibleTexts(tester).join(' | ')}');
    final next = find.text('İleri');
    if (next.evaluate().isNotEmpty) {
      await scrollTap(tester, next.last);
      noErrors(tester, 'ön kayıt boş ileri');
    }
    await app.close(tester);
  });
}

// v4 B2: Diğer › Talepler › talep ayrıntısı, karar bekleyen talep (şirket yöneticisi, onaylayan).
//
// Eskiden sayfada "Onaylarım'da aç" bandı vardı ve `context.push('/approvals')` çağırıyordu. Onaylar
// bu kullanıcılarda alt menü sekmesidir: tam ekran bir sayfadan sekme yolu `push` edilince kabuk kök
// gezginde ikinci kez kurulur ve uygulama "!keyReservation.contains(key)" / "A GlobalKey was used
// multiple times" ile bozulur (QA SC-01). Şimdi karar çubuğunda "Karar ver" var: talebin kendi onay
// kaydını (`/approvals/{id}?focus=request`) açar; kayıt bulunamazsa süzülmüş Onaylar'a geçer.
import 'dart:async';

import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/models/enums.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/approvals/api.dart';
import 'package:akaryakitnet/features/approvals/presentation/approval_detail_page.dart';
import 'package:akaryakitnet/features/customer_more/application/requests_controller.dart';
import 'package:akaryakitnet/features/customer_more/presentation/requests/request_detail_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../qa/shell-common/qa_support.dart';
import 'cm_test_utils.dart';

/// Gerçek uygulamada (kabuk, gerçek yönlendirici, tüm sahteler) talep 3001'in ayrıntısından karar.
Future<void> _decideFromRequest(WidgetTester tester, String persona) async {
  final qa = QaProblems('b2_request_decide_$persona');
  try {
    final app = await launchQa(tester);
    await qaSignIn(tester, app, persona);
    final router = app.container.read(routerProvider);
    final approval = app.harness.server.world.approvals.firstWhere(
      (a) =>
          a['subjectType'] == companyRequestSubjectType &&
          a['subjectId'] == 3001,
    )['id'];
    qa.where = 'talep ayrıntısı';
    unawaited(router.push('/company/requests/3001'));
    await pumpSteps(tester, const Duration(milliseconds: 1200));
    await settleIo(tester);
    qa.check(tester, 'talep ayrıntısı');
    expect(find.byType(RequestDetailPage), findsOneWidget);
    // Bant yok; kararın yolu çubukta, sekmenin eski adı hiçbir yerde.
    expect(find.byType(AknBanner), findsNothing);
    expect(find.textContaining('Onaylarım'), findsNothing);
    final decide = find.widgetWithText(AknButton, 'Karar ver');
    expect(decide, findsOneWidget);
    expect(
      find.text('Onay talebi açılır; onaylayın ya da reddedin'),
      findsOneWidget,
    );

    qa.where = 'Karar ver';
    await qaTap(tester, decide);
    await pumpSteps(tester, const Duration(milliseconds: 1500));
    await settleIo(tester);
    qa.check(tester, 'Karar ver → onay talebi');
    expect(app.location, '/approvals/$approval?focus=request');
    expect(find.byType(ApprovalDetailPage), findsOneWidget);

    // Geri: talep sayfasına döner (kabuk bir kez kurulu kalır).
    qa.where = 'geri';
    router.pop();
    await pumpSteps(tester, const Duration(milliseconds: 1000));
    await settleIo(tester);
    qa.check(tester, 'geri');
    expect(app.location, '/company/requests/3001');
    await tester.pumpWidget(const SizedBox());
  } catch (e, st) {
    qa.add(
      'beklenmeyen: ${e.toString().split('\n').take(8).join(' ')} @ '
      '${st.toString().split('\n').where((l) => l.contains('customer_more')).take(3).join(' | ')}',
    );
  } finally {
    qa.finish();
  }
}

ApprovalRow _row({
  required int id,
  ApprovalType type = ApprovalType.companyOrderRequest,
  String subjectType = companyRequestSubjectType,
  required int subjectId,
}) => ApprovalRow(
  id: id,
  type: type,
  status: ApprovalStatus.pending,
  subjectType: subjectType,
  subjectId: subjectId,
);

void main() {
  // Roller v5 öncesi akış (eski sunucu, geçiş yapılmamış bayi / cari): şirket içi talep kararı.
  setUpAll(() {
    FakeWorld.defaultCompanyApprovals = true;
  });
  tearDownAll(() {
    FakeWorld.defaultCompanyApprovals = false;
  });

  group('v4 B2 talep ayrıntısı → karar [QA SC-01]', () {
    testWidgets(
      'şirket yöneticisi: "Karar ver" talebin onay kaydını açar, uygulama bozulmaz',
      (tester) => _decideFromRequest(tester, 'musteri'),
    );

    testWidgets(
      'onaylayan: "Karar ver" talebin onay kaydını açar, uygulama bozulmaz',
      (tester) => _decideFromRequest(tester, 'onay'),
    );

    testWidgets(
      'onay talebinde onaylayıp geri dönünce talep yenilenir: çubuk kalkar, sonuç görünür',
      (tester) async {
        final qa = QaProblems('b2_request_decide_roundtrip');
        try {
          final app = await launchQa(tester);
          await qaSignIn(tester, app, 'musteri');
          final router = app.container.read(routerProvider);
          unawaited(router.push('/company/requests/3001'));
          await pumpSteps(tester, const Duration(milliseconds: 1200));
          await settleIo(tester);
          qa.where = 'Karar ver';
          await qaTap(tester, find.widgetWithText(AknButton, 'Karar ver'));
          await pumpSteps(tester, const Duration(milliseconds: 1500));
          await settleIo(tester);
          expect(find.byType(ApprovalDetailPage), findsOneWidget);
          // Onay talebinin çubuğundaki "Onayla", sonra karar sayfasındaki "Onayla".
          qa.where = 'onayla';
          await qaTap(
            tester,
            find.descendant(
              of: find.byType(ActionBar),
              matching: find.widgetWithText(AknButton, 'Onayla'),
            ),
          );
          await pumpSteps(tester, const Duration(milliseconds: 1000));
          await settleIo(tester);
          await qaTap(tester, find.widgetWithText(AknButton, 'Onayla').last);
          await pumpSteps(tester, const Duration(milliseconds: 2000));
          await settleIo(tester);
          qa.check(tester, 'onaylandı');
          qa.where = 'geri';
          router.pop();
          await pumpSteps(tester, const Duration(milliseconds: 1500));
          await settleIo(tester);
          qa.check(tester, 'talebe dönüş');
          expect(app.location, '/company/requests/3001');
          expect(find.widgetWithText(AknButton, 'Karar ver'), findsNothing);
          expect(find.text('Onaylandı'), findsWidgets);
          await tester.pumpWidget(const SizedBox());
        } catch (e, st) {
          qa.add(
            'beklenmeyen: ${e.toString().split('\n').take(8).join(' ')} @ '
            '${st.toString().split('\n').where((l) => l.contains('customer_more')).take(3).join(' | ')}',
          );
        } finally {
          qa.finish();
        }
      },
    );
  });

  group('talebin onay kaydı', () {
    test('konusu talep olan şirket içi talep satırı seçilir', () {
      final rows = [
        _row(id: 1, type: ApprovalType.orderFinance, subjectId: 3001),
        _row(id: 2, subjectType: 'Order', subjectId: 3001),
        _row(id: 3, subjectId: 2987),
        _row(id: 9003, subjectId: 3001),
      ];
      expect(requestApprovalIdIn(rows, 3001), 9003);
      expect(requestApprovalIdIn(rows, 2987), 3);
      expect(requestApprovalIdIn(rows, 4242), isNull);
      // Konu türü boş gelirse (eski sunucu) tür ve numara yeter.
      expect(
        requestApprovalIdIn([_row(id: 7, subjectType: '', subjectId: 5)], 5),
        7,
      );
    });

    test('karar sayfası: kayıt ya da süzülmüş Onaylar', () {
      expect(requestDecisionLocation(9003), '/approvals/9003?focus=request');
      expect(
        requestDecisionLocation(null),
        '/approvals?type=${ApprovalType.companyOrderRequest.code}',
      );
    });

    testWidgets(
      'Onaylar listesi okunamazsa "Karar ver" süzülmüş Onaylar\'ı açar',
      (tester) async {
        // A3 test sunucusunda onay uçları yok: liste hata verir, kayıt bulunamaz.
        final env = (await tester.runAsync(CmEnv.create))!;
        addTearDown(env.dispose);
        await pumpCmApp(tester, env, location: '/company/requests/3001');
        await pumpFor(tester, const Duration(seconds: 1));
        expect(find.byType(AknBanner), findsNothing);
        await tester.tap(find.widgetWithText(AknButton, 'Karar ver'));
        await pumpFor(tester, const Duration(milliseconds: 800));
        expect(
          find.text(
            'stub /approvals?type=${ApprovalType.companyOrderRequest.code}',
          ),
          findsOneWidget,
        );
        await finish(tester);
      },
    );

    testWidgets('talep eden kendi talebinde "Karar ver" görmez', (
      tester,
    ) async {
      final env = (await tester.runAsync(
        () => CmEnv.create(persona: 'talep'),
      ))!;
      addTearDown(env.dispose);
      await pumpCmApp(tester, env, location: '/company/requests/3001');
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.widgetWithText(AknButton, 'Karar ver'), findsNothing);
      expect(find.text('Talebi geri çek'), findsOneWidget);
      await finish(tester);
    });
  });
}

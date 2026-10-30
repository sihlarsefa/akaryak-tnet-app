// v4 "Sade" §5 08 / 08b, §3.4 (P2) ve §9 C: Onaylar'da uyarı bandı ve çip satırı yok, tek seçici,
// gecikenler önce; rozet = Bende = ana sayfa; carinin Bende'si görev kutusunun ta kendisi.
import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/app/tasks/task_inbox.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/models/enums.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/push/unread_count_provider.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/approvals/api.dart';
import 'package:akaryakitnet/features/approvals/copy.dart';
import 'package:akaryakitnet/features/approvals/presentation/widgets/approval_card.dart';
import 'package:akaryakitnet/features/bayi/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/a11y.dart' show pumpSteps, settleIo;
import '../../support/test_app.dart';
import 'a5_test_kit.dart';

Future<ProviderContainer> _signedIn(String key) async {
  final h = await TestHarness.create();
  final c = h.container();
  addTearDown(c.dispose);
  final s = c.read(sessionControllerProvider.notifier);
  final outcome = await s.loginWithPassword(key, 'demo');
  if (outcome is LoginNeedsCode) {
    await s.verifyCode(outcome.challenge.challengeId, '123456');
  }
  expect(c.read(sessionControllerProvider), isA<SessionAuthenticated>());
  return c;
}

Future<void> _until(bool Function() ready) async {
  for (var i = 0; i < 400 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(ready(), isTrue, reason: 'veri yüklenmedi');
}

/// Telefon (390×844, üstte 47 dp sistem çubuğu): yakalamadaki gibi.
void _phone(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
  tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
  addTearDown(tester.view.reset);
}

void main() {
  // Roller v5 öncesi akış (eski sunucu, geçiş yapılmamış bayi / cari): şirket içi talep sonucu
  // (9013) ve müdürün de karar verdiği bayi.
  setUpAll(() {
    FakeWorld.defaultCompanyApprovals = true;
    FakeWorld.defaultV5Station = false;
  });
  tearDownAll(() {
    FakeWorld.defaultCompanyApprovals = false;
    FakeWorld.defaultV5Station = true;
  });

  group('tek sayı (P2)', () {
    for (final key in ['sahip', 'mudur', 'finans']) {
      test(
        '$key: rozet = Bende toplamı = Bende sekmesi = ana sayfadaki satır',
        () async {
          final c = await _signedIn(key);
          c.listen(approvalsListProvider(const ApprovalsQuery()), (_, _) {});
          c.listen(approvalBadgeProvider, (_, _) {});
          c.listen(bayiTaskQueuesProvider, (_, _) {});
          await _until(
            () =>
                c.read(unreadCountProvider).approvals > 0 &&
                c.read(approvalsListProvider(const ApprovalsQuery())).hasData &&
                c.read(approvalBadgeProvider).hasValue &&
                c.read(bayiHomeProvider).data != null,
          );
          final badge = c.read(unreadCountProvider).approvals;
          final bende = c
              .read(approvalsListProvider(const ApprovalsQuery()))
              .totalCount;
          expect(bende, badge, reason: 'Bende toplamı = alt menü rozeti');
          expect(c.read(approvalBadgeProvider).value!.toMe, badge);
          final hero = c.read(bayiTaskQueuesProvider).of(TaskKind.approvals);
          expect(hero?.count, badge, reason: '"Sıra sizde" onay satırı');
        },
      );
    }

    test('teklif limit aşımında açılan finans onayı yeni kimlik alır', () async {
      // Rozet A5 deposunu oturum açılır açılmaz kurar; sonradan açılan talep onun sabit
      // kimlikleriyle çakışmamalı.
      final c = await _signedIn('sahip');
      c.listen(unreadCountProvider, (_, _) {});
      await _until(() => c.read(unreadCountProvider).approvals > 0);
      final h = c.read(fakeServerProvider);
      final ids = [for (final a in h.world.approvals) a['id'] as int];
      final next = h.world.nextId('approval', start: 9001);
      expect(ids.contains(next), isFalse);
    });
  });

  group('bayi Onaylar (08)', () {
    testWidgets(
      'bant durumu, tek seçici; uyarı bandı, çip satırı ve kart yığını yok; gecikmiş önce',
      (tester) async {
        _phone(tester);
        final app = await pumpA5(
          tester,
          persona: 'sahip',
          location: '/approvals',
          size: const Size(390, 844),
        );
        final badge = app.container.read(approvalBadgeProvider).value!;
        expect(badge.toMe, greaterThan(0));
        // Bant: sözcük ve canlı durum (kesilmeyen kısa biçim).
        expect(find.text(ApprovalsCopy.title), findsWidgets);
        expect(
          find.textContaining('${badge.toMe} talep'),
          findsOneWidget,
          reason: 'bant durumu',
        );
        expect(find.byType(AknBanner), findsNothing);
        expect(find.byType(AknChip), findsNothing);
        expect(
          find.byType(SearchField),
          findsNothing,
          reason: 'arama ⌕ ardında',
        );
        expect(
          find.byWidgetPredicate((w) => w is AknSegmented),
          findsOneWidget,
        );
        expect(find.byType(AknCard), findsNothing);
        expect(find.byType(ApprovalRowTile), findsWidgets);

        // Gruplar: gecikmiş varsa ilk grup "Gecikmiş" (tehlike tonu); "Yanıt bekleniyor" sayısız.
        final groups = tester
            .widgetList<AknLedgerGroup>(find.byType(AknLedgerGroup))
            .toList();
        expect(groups, isNotEmpty);
        if (badge.overdue > 0) {
          expect(groups.first.title, ApprovalsCopy.groupOverdue);
          expect(groups.first.tone, AknTone.danger);
        }
        for (final g in groups) {
          if (g.title == ApprovalsCopy.groupWaiting) expect(g.count, isNull);
        }

        // İlk satır ≤ 230 dp (§9).
        final first = tester.getTopLeft(find.byType(ApprovalRowTile).first);
        expect(first.dy, lessThanOrEqualTo(230));
        await finish(tester);
      },
    );

    testWidgets('Filtre: tür süzgeci sorguya gider; denetçiye "Tüm talepler"', (
      tester,
    ) async {
      final app = await pumpA5(
        tester,
        persona: 'sahip',
        location: '/approvals',
      );
      await tapFinder(tester, find.byType(AknFilterButton));
      expect(inSheet(find.text(ApprovalsCopy.scopeAll)), findsOneWidget);
      await tapFinder(tester, inSheet(find.text('Saha formu finansı')));
      expect(
        app.log.last('GET', '/approvals')!.queryParameters['type'],
        ApprovalType.fieldFormFinance.code,
      );
      await tapFinder(tester, inSheet(find.text(ApprovalsCopy.scopeAll)));
      expect(app.log.last('GET', '/approvals')!.queryParameters['scope'], 3);
      await finish(tester);
    });
  });

  group('onay talebi ayrıntısı', () {
    testWidgets(
      'çubukta nesnenin türü; ?focus=request talebin bloğunu parlatır; tek birincil',
      (tester) async {
        await pumpA5(
          tester,
          persona: 'finans',
          location: '/approvals/9001?focus=request',
        );
        // Odak bloğa kaydırıldığı için çubuk talebin adını (collapsedTitle) gösterir.
        final scaffold = tester.widget<AppScaffold>(find.byType(AppScaffold));
        expect(scaffold.title, ApprovalsCopy.detailTitle);
        expect(scaffold.collapsedTitle, isNotEmpty);
        expect(find.byType(AknObjectHeader), findsOneWidget);
        final flash = tester.widget<AknFocusFlash>(find.byType(AknFocusFlash));
        expect(flash.active, isTrue);
        // Karar rıhtımı: bir birincil ("Onayla"), çerçevesiz ikinciller; kapalı birincil yok.
        expect(find.text('Onayla'), findsOneWidget);
        expect(find.text('Reddet'), findsOneWidget);
        expect(find.text(ApprovalsCopy.decideNext), findsOneWidget);
        await finish(tester);
      },
    );
  });

  group('cari Onaylar (08b)', () {
    for (final key in ['onay', 'musteri']) {
      testWidgets(
        '$key: Bende = görev kutusu (aynı satırlar, aynı sıra) = rozet',
        (tester) async {
          _phone(tester);
          final h = await TestHarness.create(
            prefs: const {'akn.onboardingDone': true},
          );
          await tester.pumpWidget(
            ProviderScope(overrides: h.overrides, child: const AknApp()),
          );
          await pumpSteps(tester, const Duration(seconds: 2));
          final c = ProviderScope.containerOf(
            tester.element(find.byType(AknApp)),
          );
          await tester.runAsync(() async {
            final s = c.read(sessionControllerProvider.notifier);
            final outcome = await s.loginWithPassword(key, 'demo');
            if (outcome is LoginNeedsCode) {
              await s.verifyCode(outcome.challenge.challengeId, '123456');
            }
          });
          // Doğrudan Onaylar (ana sayfa sekmesi hiç kurulmaz: başka alanın yerleşimi bu testi
          // etkilemez).
          c.read(routerProvider).go('/approvals');
          await pumpSteps(tester, const Duration(seconds: 3));
          await settleIo(tester);
          await pumpSteps(tester, const Duration(milliseconds: 1500));
          await settleIo(tester, rounds: 4);
          await pumpSteps(tester, const Duration(milliseconds: 600));

          final inbox = c.read(taskInboxProvider);
          final count = c.read(taskCountProvider);
          expect(count, greaterThan(0));
          final rows = tester
              .widgetList<AknTaskRow>(find.byType(AknTaskRow))
              .toList();
          expect(
            [for (final r in rows) r.task.id],
            [
              for (final t in inbox.items)
                if (t.counts) t.id,
            ],
            reason: 'Bende, görev kutusunun sayılan işleri, aynı sırada',
          );
          expect(
            find.text(ApprovalsCopy.customerWaiting(count)),
            findsOneWidget,
          );
          expect(find.byType(AknBanner), findsNothing);
          expect(find.byType(AknChip), findsNothing);
          // Kod yok (P4).
          for (final e in find.byType(Text).evaluate()) {
            final text = (e.widget as Text).data ?? '';
            expect(
              text.contains(RegExp(r'\b(SIP|SSF|TLP)-')),
              isFalse,
              reason: text,
            );
          }
          final firstRow = tester.getTopLeft(find.byType(AknTaskRow).first);
          expect(firstRow.dy, lessThanOrEqualTo(230));
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        },
      );
    }
  });

  // v4 tur 2: Bende'nin gün grupları talebin GELDİĞİ günü söyler (B16); sonuçlanmış talep çıkmaz
  // sokak değildir — "Sıradaki işiniz" görev kutusundaki sıradaki işi açar (B12, §3.5.3).
  group('v4 tur 2', () {
    testWidgets('Bende grupları: "Bugün gelenler", "Dün gelenler"', (
      tester,
    ) async {
      _phone(tester);
      await pumpA5(
        tester,
        persona: 'sahip',
        location: '/approvals',
        size: const Size(390, 844),
      );
      final titles = tester
          .widgetList<AknLedgerGroup>(find.byType(AknLedgerGroup))
          .map((g) => g.title)
          .toList();
      expect(titles, contains(ApprovalsCopy.groupArrivedToday));
      expect(titles, isNot(contains(ApprovalsCopy.groupToday)));
      expect(titles, isNot(contains(ApprovalsCopy.groupYesterday)));
      await finish(tester);
    });

    testWidgets('saha: rozetin saydığı iş Bende\'de; sayfa Bende ile açılır', (
      tester,
    ) async {
      _phone(tester);
      final app = await pumpA5(
        tester,
        persona: 'saha',
        location: '/approvals',
        size: const Size(390, 844),
      );
      // Vergi levhası saha temsilcisinden bekleniyor (9004): rozet 1, Bende onu gösterir.
      expect(app.container.read(unreadCountProvider).approvals, greaterThan(0));
      final seg = tester.widget<AknSegmented<ApprovalScope?>>(
        find.byWidgetPredicate((w) => w is AknSegmented<ApprovalScope?>),
      );
      expect(seg.value, ApprovalScope.toMe);
      expect(find.byType(ApprovalRowTile), findsWidgets);
      // Sekme seçilince kendiliğinden geri dönmez.
      await tester.tap(find.text(ApprovalScope.mine.shortLabel));
      await pumpSteps(tester, const Duration(milliseconds: 900));
      expect(
        tester
            .widget<AknSegmented<ApprovalScope?>>(
              find.byWidgetPredicate((w) => w is AknSegmented<ApprovalScope?>),
            )
            .value,
        ApprovalScope.mine,
      );
      await finish(tester);
    });

    testWidgets('başkası karar verdi: sonuç bandında "Sıradaki işiniz"', (
      tester,
    ) async {
      _phone(tester);
      final h = await TestHarness.create(
        prefs: const {'akn.onboardingDone': true},
      );
      await tester.pumpWidget(
        ProviderScope(overrides: h.overrides, child: const AknApp()),
      );
      await pumpSteps(tester, const Duration(seconds: 2));
      final c = ProviderScope.containerOf(tester.element(find.byType(AknApp)));
      await tester.runAsync(() async {
        final s = c.read(sessionControllerProvider.notifier);
        final outcome = await s.loginWithPassword('onay', 'demo');
        if (outcome is LoginNeedsCode) {
          await s.verifyCode(outcome.challenge.challengeId, '123456');
        }
      });
      // Selin Aydın'ın onayladığı talep (9013): Elif'e kim ve ne zaman, ve sıradaki işi.
      c.read(routerProvider).go('/approvals/9013');
      await pumpSteps(tester, const Duration(seconds: 2));
      await settleIo(tester, rounds: 4);
      await pumpSteps(tester, const Duration(milliseconds: 800));
      expect(find.text('Onaylandı'), findsWidgets);
      expect(find.textContaining('Selin Aydın'), findsWidgets);
      final next = c.read(taskInboxProvider).next(except: '/approvals/9013');
      expect(next, isNotNull, reason: 'Elif\'in bekleyen işi var');
      expect(find.text(nextTaskLabel), findsOneWidget);
      await tester.ensureVisible(find.text(nextTaskLabel));
      await tester.tap(find.text(nextTaskLabel));
      await pumpSteps(tester, const Duration(milliseconds: 1200));
      // Sıradaki iş itilen sayfadır (en üstteki eşleşme).
      expect(
        c
            .read(routerProvider)
            .routerDelegate
            .currentConfiguration
            .last
            .matchedLocation,
        taskPath(next!.route),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  });
}

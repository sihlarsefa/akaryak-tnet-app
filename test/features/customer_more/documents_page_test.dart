import 'package:akaryakitnet/core/auth/access_policy.dart';
import 'package:akaryakitnet/core/auth/permissions.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/models/me_access.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/offline/cache_store.dart';
import 'package:akaryakitnet/core/pdf/akn_pdf.dart';
import 'package:akaryakitnet/features/customer_more/application/cm_common.dart';
import 'package:akaryakitnet/features/customer_more/copy.dart';
import 'package:akaryakitnet/features/customer_more/documents/doc_spec.dart';
import 'package:akaryakitnet/features/customer_more/presentation/documents/documents_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cm_test_utils.dart';

/// Sayfa yetkilerinden [drop] öneklerini çıkaran erişim politikası.
AccessPolicy _without(MeAccess? me, List<String> drop) {
  if (me == null) return AccessPolicy.signedOut;
  return AccessPolicy(
    MeAccess.fromJson({
      ...me.toJson(),
      'pages': [
        for (final p in me.pages)
          if (!drop.any((d) => p.startsWith('$d:'))) p,
      ],
    }),
  );
}

void main() {
  testWidgets('arşiv satırları ve belge düğmeleri; PDF üretilip açılır', (
    tester,
  ) async {
    final env = (await tester.runAsync(CmEnv.create))!;
    addTearDown(env.dispose);
    await pumpCmApp(tester, env, location: '/documents');
    await pumpFor(tester, const Duration(seconds: 1));

    expect(find.byType(ArchiveRowCard), findsWidgets);
    expect(find.widgetWithText(ActionChip, 'Teslim tutanağı'), findsWidgets);
    expect(find.widgetWithText(ActionChip, 'Sevk belgesi'), findsWidgets);
    expect(find.widgetWithText(ActionChip, 'Sipariş formu'), findsWidgets);
    expect(
      find.textContaining(RegExp('irsaliye no', caseSensitive: false)),
      findsNothing,
    );

    // Yazı tipleri ve işaret varlıktan bir kez yüklenir (gerçek zaman).
    await tester.runAsync(AknPdf.theme);
    await tester.tap(find.widgetWithText(ActionChip, 'Sipariş formu').first);
    await pumpFor(tester, const Duration(seconds: 2));
    expect(env.opened, hasLength(1));
    expect(env.opened.single.fileName, endsWith('_Siparis_Formu.pdf'));
    expect(String.fromCharCodes(env.opened.single.bytes.take(5)), '%PDF-');
    expect(
      env.requests.any((r) => r.path.startsWith('documents/orders/')),
      isTrue,
    );
    await finish(tester);
  });

  testWidgets('sipariş / teklif yetkisi yoksa sipariş belgeleri düğmesi yok', (
    tester,
  ) async {
    final env = (await tester.runAsync(
      () => CmEnv.create(
        overrides: [
          accessPolicyProvider.overrideWith(
            (ref) => _without(ref.watch(sessionControllerProvider).access, [
              Pg.customerOrders,
              Pg.customerQuotes,
            ]),
          ),
        ],
      ),
    ))!;
    addTearDown(env.dispose);
    await pumpCmApp(tester, env, location: '/documents');
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(ArchiveRowCard), findsWidgets);
    expect(find.widgetWithText(ActionChip, 'Sipariş formu'), findsNothing);
    expect(find.widgetWithText(ActionChip, 'Sevk belgesi'), findsWidgets);
    await finish(tester);
  });

  testWidgets('çevrimdışı: ilk sayfa önbellekten, "Son güncelleme" notu', (
    tester,
  ) async {
    final env = (await tester.runAsync(CmEnv.create))!;
    addTearDown(env.dispose);
    final router = await pumpCmApp(tester, env, location: '/documents');
    await pumpFor(tester, const Duration(seconds: 1));
    final cached = await tester.runAsync(
      () => env.container
          .read(cacheStoreProvider)
          .read(
            CacheKeys.user(
              env.container.read(currentUserIdProvider)!,
              CmCacheKeys.documentsFirstPage,
            ),
          ),
    );
    expect(cached, isNotNull);
    // Sayfadan çıkılır (denetleyici kapanır), bağlantı kesilir, sayfaya dönülür.
    router.go('/home');
    await pumpFor(tester, const Duration(milliseconds: 600));

    env.harness.server.failureMode = FakeFailureMode.offline;
    router.go('/documents');
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(ArchiveRowCard), findsWidgets);
    expect(find.textContaining('Son güncelleme'), findsOneWidget);
    await finish(tester);
  });

  test('alt bilgi metni sabit', () {
    expect(
      DocSpec.legalFooter,
      'Mali belge değildir; e-irsaliye/e-fatura yerine geçmez.',
    );
    expect(CmCopy.documentsFooter, contains(DocSpec.legalFooter));
  });
}

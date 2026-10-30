// Şirket kullanıcıları. Roller v5 (varsayılan sahte dünya: demo carisinde şirket içi onay kapalı, tek
// müşteri rolü): rol sütunu, rol seçimi, rol açıklamaları ve eşik kartı yok; "Ana kullanıcı"; yeni
// kullanıcı Yönetici. Eski akış (şirket içi onay açık) aşağıdaki grupta korunur.
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/customer_more/copy.dart';
import 'package:akaryakitnet/features/customer_more/presentation/company_users/company_users_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cm_test_utils.dart';

void main() {
  testWidgets('yalnızca şirket yöneticisi: Talep eden sayfayı göremez', (
    tester,
  ) async {
    final env = (await tester.runAsync(() => CmEnv.create(persona: 'talep')))!;
    addTearDown(env.dispose);
    await pumpCmApp(tester, env, location: '/company/users');
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text(CmCopy.usersOnlyAdmin), findsOneWidget);
    expect(find.byType(UserCard), findsNothing);
    expect(
      env.requests.where(
        (r) => r.path.startsWith('customers/me/company-users'),
      ),
      isEmpty,
      reason: 'yetkisi olmayan için istek atılmaz',
    );
    await finish(tester);
  });

  testWidgets(
    'roller v5: liste rol sütunsuz, "Ana kullanıcı"; eşik kartı ve rol açıklamaları yok',
    (tester) async {
      final env = (await tester.runAsync(CmEnv.create))!;
      addTearDown(env.dispose);
      await pumpCmApp(tester, env, location: '/company/users');
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.byType(UserCard), findsNWidgets(5));
      expect(find.text('Selin Aydın (siz)'), findsOneWidget);
      expect(find.text(mainUserLabel), findsOneWidget);
      expect(find.text('Davet bekliyor'), findsOneWidget);
      expect(find.text('Pasif'), findsOneWidget);
      expect(find.text('Henüz giriş yapmadı'), findsOneWidget);
      expect(find.textContaining('Son giriş'), findsWidgets);
      for (final role in ['Talep eden', 'Onaylayan', 'Yönetici']) {
        expect(find.text(role), findsNothing, reason: role);
      }
      expect(find.text(CmCopy.thresholdsTitle), findsNothing);
      expect(find.text('Roller'), findsNothing);
      expect(find.text('Kullanıcı ekle'), findsOneWidget);
      // Eşikler hiç istenmez (akış kapalı).
      expect(
        env.requests.where((r) => r.path.endsWith('approval-settings')),
        isEmpty,
      );
      await finish(tester);
    },
  );

  testWidgets('bağlantıyı yeniden gönder ve pasifleştir (onaylı)', (
    tester,
  ) async {
    final env = (await tester.runAsync(CmEnv.create))!;
    addTearDown(env.dispose);
    await pumpCmApp(tester, env, location: '/company/users');
    await pumpFor(tester, const Duration(seconds: 1));

    await tester.tap(find.text('Hakan Öz'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    await tester.tap(find.text('Bağlantıyı yeniden gönder'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(
      env.requests.any(
        (r) =>
            r.method == 'POST' &&
            r.path == 'customers/me/company-users/u-cm-1/password-link',
      ),
      isTrue,
    );
    expect(find.textContaining('adresine gönderildi'), findsOneWidget);
    await pumpFor(tester, const Duration(seconds: 4));

    await tester.tap(find.text('Burak Yılmaz'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    await tester.tap(find.text('Pasifleştir'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text('Burak Yılmaz pasifleştirilsin mi?'), findsOneWidget);
    await tester.tap(find.widgetWithText(AknButton, 'Pasifleştir'));
    await pumpFor(tester, const Duration(seconds: 1));
    final users = env.world.bag<List<Map<String, dynamic>>>(
      'cm.companyUsers',
      () => [],
    );
    expect(
      users.firstWhere((u) => u['userId'] == 'u-talep')['isActive'],
      isFalse,
    );
    await finish(tester);
  });

  testWidgets(
    'roller v5: kullanıcı ekle — rol seçimi yok, Yönetici olarak davet',
    (tester) async {
      final env = (await tester.runAsync(CmEnv.create))!;
      addTearDown(env.dispose);
      await pumpCmApp(tester, env, location: '/company/users');
      await pumpFor(tester, const Duration(seconds: 1));
      await tester.tap(find.text('Kullanıcı ekle'));
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.text('Şirket rolü'), findsNothing);
      expect(find.text('Talep eden'), findsNothing);
      await tester.enterText(fieldLabeled('Ad soyad *'), 'Deniz Ak');
      await tester.enterText(
        fieldLabeled('E-posta *'),
        'deniz.ak@anadolulojistik.example',
      );
      await tester.tap(find.text('Ekle ve davet gönder'));
      await pumpFor(tester, const Duration(seconds: 1));
      final users = env.world.bag<List<Map<String, dynamic>>>(
        'cm.companyUsers',
        () => [],
      );
      final added = users.firstWhere((u) => u['displayName'] == 'Deniz Ak');
      expect(added['role'], 3);
      expect(added['invitationPending'], isTrue);
      await finish(tester);
    },
  );

  testWidgets('roller v5: düzenlemede rol yok; eylem sayfası rolü anmaz', (
    tester,
  ) async {
    final env = (await tester.runAsync(CmEnv.create))!;
    addTearDown(env.dispose);
    await pumpCmApp(tester, env, location: '/company/users');
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.text('Elif Demir'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text('Bilgileri düzenle'), findsOneWidget);
    expect(find.text('Bilgileri ve rolü düzenle'), findsNothing);
    expect(find.text('onay@demo.akaryakitnet.local'), findsWidgets);
    await tester.tap(find.text('Bilgileri düzenle'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text('Şirket rolü'), findsNothing);
    await tester.tap(find.widgetWithText(AknButton, 'Kaydet'));
    await pumpFor(tester, const Duration(seconds: 1));
    final users = env.world.bag<List<Map<String, dynamic>>>(
      'cm.companyUsers',
      () => [],
    );
    // Sunucu gibi: istekteki rol yok sayılır, herkes Yönetici.
    expect(users.firstWhere((u) => u['userId'] == 'u-onay')['role'], 3);
    await finish(tester);
  });

  group('eski akış (şirket içi onay açık)', () {
    setUp(() => FakeWorld.defaultCompanyApprovals = true);
    tearDown(() => FakeWorld.defaultCompanyApprovals = false);

    testWidgets(
      'liste: rol çipi, "Davet bekliyor", pasif, son giriş; eşikler',
      (tester) async {
        final env = (await tester.runAsync(CmEnv.create))!;
        addTearDown(env.dispose);
        await pumpCmApp(tester, env, location: '/company/users');
        await pumpFor(tester, const Duration(seconds: 1));
        expect(find.byType(UserCard), findsNWidgets(5));
        expect(find.text('Selin Aydın (siz)'), findsOneWidget);
        expect(find.text('Davet bekliyor'), findsOneWidget);
        expect(find.text('Pasif'), findsOneWidget);
        expect(find.text('Henüz giriş yapmadı'), findsOneWidget);
        expect(find.textContaining('Son giriş'), findsWidgets);
        expect(find.text('Onaylayan'), findsWidgets);
        expect(find.text(mainUserLabel), findsNothing);
        expect(find.text(CmCopy.thresholdsTitle), findsOneWidget);
        expect(find.textContaining('20.000'), findsOneWidget);
        expect(find.text('Kullanıcı ekle'), findsOneWidget);
        await finish(tester);
      },
    );

    testWidgets('kullanıcı ekle: rol seçimi ve davet', (tester) async {
      final env = (await tester.runAsync(CmEnv.create))!;
      addTearDown(env.dispose);
      await pumpCmApp(tester, env, location: '/company/users');
      await pumpFor(tester, const Duration(seconds: 1));
      await tester.tap(find.text('Kullanıcı ekle'));
      await pumpFor(tester, const Duration(milliseconds: 600));
      await tester.enterText(fieldLabeled('Ad soyad *'), 'Deniz Ak');
      await tester.enterText(
        fieldLabeled('E-posta *'),
        'deniz.ak@anadolulojistik.example',
      );
      await tester.tap(find.text('Onaylayan').last);
      await pumpFor(tester, const Duration(milliseconds: 300));
      await tester.tap(find.text('Ekle ve davet gönder'));
      await pumpFor(tester, const Duration(seconds: 1));
      final post = env.requests.lastWhere(
        (r) => r.method == 'POST' && r.path == 'customers/me/company-users',
      );
      expect(post, isNotNull);
      final users = env.world.bag<List<Map<String, dynamic>>>(
        'cm.companyUsers',
        () => [],
      );
      final added = users.firstWhere((u) => u['displayName'] == 'Deniz Ak');
      expect(added['role'], 2);
      expect(added['invitationPending'], isTrue);
      await finish(tester);
    });

    testWidgets('onay eşikleri düzenlenir', (tester) async {
      final env = (await tester.runAsync(CmEnv.create))!;
      addTearDown(env.dispose);
      await pumpCmApp(tester, env, location: '/company/users');
      await pumpFor(tester, const Duration(seconds: 1));
      await tester.tap(find.bySemanticsLabel('Onay eşiklerini düzenle'));
      await pumpFor(tester, const Duration(milliseconds: 600));
      await tester.enterText(fieldLabeled('Litre eşiği'), '15000');
      await tester.tap(find.widgetWithText(AknButton, 'Kaydet'));
      await pumpFor(tester, const Duration(seconds: 1));
      final t = env.world.bag<Map<int, Map<String, dynamic>>>(
        'cm.thresholds',
        () => {},
      );
      expect(t[101]!['litres'], 15000);
      expect(find.text('Onay eşikleri kaydedildi.'), findsOneWidget);
      await finish(tester);
    });

    testWidgets(
      'onay eşikleri yüklenemezse liste yine açılır (eşik kartı yok)',
      (tester) async {
        final env = (await tester.runAsync(CmEnv.create))!;
        addTearDown(env.dispose);
        env.harness.server.get(
          'customers/me/company-users/approval-settings',
          (req) => throw FakeResponse.notFound('Uç yok.'),
        );
        await pumpCmApp(tester, env, location: '/company/users');
        await pumpFor(tester, const Duration(seconds: 1));
        expect(find.byType(UserCard), findsNWidgets(5));
        expect(find.text(CmCopy.thresholdsTitle), findsNothing);
        expect(find.text('Onaylayan'), findsWidgets);
        expect(find.text('Kullanıcı ekle'), findsOneWidget);
        await finish(tester);
      },
    );
  });
}

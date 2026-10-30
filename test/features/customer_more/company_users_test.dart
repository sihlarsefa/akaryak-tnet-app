// Şirket kullanıcıları. Roller v5 (varsayılan sahte dünya: demo carisinde şirket içi onay kapalı, tek
// müşteri rolü): rol sütunu, rol seçimi, rol açıklamaları ve eşik kartı yok; "Ana kullanıcı"; yeni
// kullanıcı Yönetici. Eski akış (şirket içi onay açık) aşağıdaki grupta korunur.
// Sahip 2026-10-30: kullanıcı adı + şifreyle ekleme (e-posta isteğe bağlı; şifre boş ve e-posta varsa
// davet), satırda kullanıcı adı, "Şifre belirle" (yönetebilen herkes; ana kullanıcıda yalnızca kendisi).
import 'package:akaryakitnet/core/auth/access_policy.dart';
import 'package:akaryakitnet/core/auth/permissions.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/models/enums.dart';
import 'package:akaryakitnet/core/models/me_access.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/core/utils/validators.dart';
import 'package:akaryakitnet/features/customer_more/application/cm_access.dart';
import 'package:akaryakitnet/features/customer_more/copy.dart';
import 'package:akaryakitnet/features/customer_more/data/company.dart';
import 'package:akaryakitnet/features/customer_more/presentation/company_users/company_users_page.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cm_test_utils.dart';

/// Etiketi [label] olan alanın tamamı (etiket, kutu, yardım / hata satırı).
Finder _fieldBox(String label) => find
    .ancestor(of: find.text(label), matching: find.byType(AknTextField))
    .first;

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
      await tester.enterText(fieldLabeled('Kullanıcı adı *'), 'deniz.ak');
      // Şifre boş, e-posta dolu: eski akış (davet bağlantısı).
      await tester.enterText(
        fieldLabeled('E-posta (isteğe bağlı)'),
        'deniz.ak@anadolulojistik.example',
      );
      await tester.tap(find.text('Kullanıcıyı ekle'));
      await pumpFor(tester, const Duration(seconds: 1));
      final users = env.world.bag<List<Map<String, dynamic>>>(
        'cm.companyUsers',
        () => [],
      );
      final added = users.firstWhere((u) => u['displayName'] == 'Deniz Ak');
      expect(added['role'], 3);
      expect(added['userName'], 'deniz.ak');
      expect(added['invitationPending'], isTrue);
      expect(find.textContaining('adresine gönderildi'), findsOneWidget);
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

  testWidgets('satırda kullanıcı adı adın altında', (tester) async {
    final env = (await tester.runAsync(CmEnv.create))!;
    addTearDown(env.dispose);
    await pumpCmApp(tester, env, location: '/company/users');
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.textContaining('hakan.oz\n'), findsOneWidget);
    expect(find.textContaining('musteri\n'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('kullanıcı adı ve şifreyle ekle: e-posta gerekmez, davet gitmez', (
    tester,
  ) async {
    final env = (await tester.runAsync(CmEnv.create))!;
    addTearDown(env.dispose);
    await pumpCmApp(tester, env, location: '/company/users');
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.tap(find.text('Kullanıcı ekle'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    // Alanlar: Ad soyad, Kullanıcı adı, Şifre (göster / gizle), Telefon, E-posta (isteğe bağlı).
    expect(find.text('Kullanıcı adı *'), findsOneWidget);
    expect(find.text('Şifre'), findsOneWidget);
    expect(find.text('Telefon (isteğe bağlı)'), findsOneWidget);
    expect(find.text('E-posta (isteğe bağlı)'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Şifreyi göster|Göster')),
      findsWidgets,
    );

    // İkisi de boşsa: şifre ya da e-posta istenir; istek gitmez.
    await tester.enterText(fieldLabeled('Ad soyad *'), 'Deniz Ak');
    await tester.enterText(fieldLabeled('Kullanıcı adı *'), 'deniz.ak');
    await tester.tap(find.text('Kullanıcıyı ekle'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text('Şifre belirleyin ya da e-posta girin.'), findsOneWidget);
    // Kullanıcı adı kuralı istemcide de denetlenir.
    await tester.enterText(fieldLabeled('Kullanıcı adı *'), 'de');
    await tester.tap(find.text('Kullanıcıyı ekle'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text('Kullanıcı adı 3–50 karakter olmalı.'), findsOneWidget);
    expect(
      env.requests.where(
        (r) => r.method == 'POST' && r.path == 'customers/me/company-users',
      ),
      isEmpty,
    );

    await tester.enterText(fieldLabeled('Kullanıcı adı *'), 'deniz.ak');
    await tester.enterText(fieldLabeled('Şifre'), 'Guclu123');
    await tester.tap(find.text('Kullanıcıyı ekle'));
    await pumpFor(tester, const Duration(seconds: 1));
    final users = env.world.bag<List<Map<String, dynamic>>>(
      'cm.companyUsers',
      () => [],
    );
    final added = users.firstWhere((u) => u['displayName'] == 'Deniz Ak');
    expect(added['userName'], 'deniz.ak');
    expect(added['email'], '');
    expect(added['password'], 'Guclu123');
    expect(added['invitationPending'], isFalse);
    expect(find.textContaining('Kullanıcı adı: deniz.ak'), findsOneWidget);
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Deniz Ak'), findsOneWidget);
    expect(find.text('deniz.ak'), findsOneWidget, reason: 'adın altında');
    expect(
      find.text('Davet bekliyor'),
      findsOneWidget,
      reason: 'yalnızca Hakan',
    );
    await finish(tester);
  });

  testWidgets(
    'sunucunun doğrulama iletileri ilgili alanın altında (errors.userName, errors.password); '
    'Türkçe harf istemcide sunucunun iletisiyle',
    (tester) async {
      final env = (await tester.runAsync(CmEnv.create))!;
      addTearDown(env.dispose);
      await pumpCmApp(tester, env, location: '/company/users');
      await pumpFor(tester, const Duration(seconds: 1));
      await tester.tap(find.text('Kullanıcı ekle'));
      await pumpFor(tester, const Duration(milliseconds: 600));
      await tester.enterText(fieldLabeled('Ad soyad *'), 'Deniz Ak');
      await tester.enterText(fieldLabeled('Şifre'), 'Guclu123');

      // Türkçe harf: istemci sunucunun iletisini gösterir, istek gitmez.
      await tester.enterText(fieldLabeled('Kullanıcı adı *'), 'şoför');
      await tester.tap(find.text('Kullanıcıyı ekle'));
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(
        find.descendant(
          of: _fieldBox('Kullanıcı adı *'),
          matching: find.text(
            'Kullanıcı adında yalnızca İngilizce harf, rakam, nokta, alt çizgi ve tire olabilir.',
          ),
        ),
        findsOneWidget,
      );
      bool posted() => env.requests.any(
        (r) => r.method == 'POST' && r.path == 'customers/me/company-users',
      );
      expect(posted(), isFalse);

      // Alınmış kullanıcı adı: `errors.userName` alanın altında.
      await tester.enterText(fieldLabeled('Kullanıcı adı *'), 'musteri');
      await tester.tap(find.text('Kullanıcıyı ekle'));
      await pumpFor(tester, const Duration(seconds: 1));
      expect(posted(), isTrue);
      expect(
        find.descendant(
          of: _fieldBox('Kullanıcı adı *'),
          matching: find.text('Bu kullanıcı adı alınmış; başka bir ad seçin.'),
        ),
        findsOneWidget,
      );
      expect(find.byType(AknBanner), findsNothing);

      // Zayıf şifre: `errors.password` Şifre alanının altında; kullanıcı adının iletisi silinir.
      await tester.enterText(fieldLabeled('Kullanıcı adı *'), 'deniz.ak');
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(
        find.text('Bu kullanıcı adı alınmış; başka bir ad seçin.'),
        findsNothing,
      );
      await tester.enterText(fieldLabeled('Şifre'), 'zayif');
      await tester.tap(find.text('Kullanıcıyı ekle'));
      await pumpFor(tester, const Duration(seconds: 1));
      for (final line in const [
        'Şifre en az 8 karakter olmalıdır.',
        'Şifre en az bir rakam içermelidir.',
        'Şifre en az bir büyük harf içermelidir.',
      ]) {
        expect(
          find.descendant(
            of: _fieldBox('Şifre'),
            matching: find.textContaining(line),
          ),
          findsOneWidget,
          reason: line,
        );
      }
      expect(find.byType(AknBanner), findsNothing);
      final users = env.world.bag<List<Map<String, dynamic>>>(
        'cm.companyUsers',
        () => [],
      );
      expect(users.where((u) => u['displayName'] == 'Deniz Ak'), isEmpty);
      await finish(tester);
    },
  );

  test('Validators.userName: sunucunun kuralı ve iletisi', () {
    expect(Validators.userName(' deniz.ak_1-x '), isNull, reason: 'kırpılır');
    expect(Validators.userName(''), 'Kullanıcı adı zorunludur.');
    expect(Validators.userName('de'), 'Kullanıcı adı 3–50 karakter olmalı.');
    expect(
      Validators.userName('a' * 51),
      'Kullanıcı adı 3–50 karakter olmalı.',
    );
    for (final bad in const ['şoför', 'deniz ak', 'ali@x', 'Çınar']) {
      expect(
        Validators.userName(bad),
        'Kullanıcı adında yalnızca İngilizce harf, rakam, nokta, alt çizgi ve tire olabilir.',
        reason: bad,
      );
    }
  });

  group('Şifre belirle', () {
    Future<void> openFor(WidgetTester tester, String name) async {
      await tester.tap(find.text(name));
      await pumpFor(tester, const Duration(milliseconds: 600));
    }

    Future<void> fill(WidgetTester tester, String next, String again) async {
      await tester.enterText(fieldLabeled('Yeni şifre *'), next);
      await tester.enterText(fieldLabeled('Yeni şifre (tekrar) *'), again);
      await tester.tap(find.text('Şifreyi kaydet'));
      await pumpFor(tester, const Duration(seconds: 1));
    }

    testWidgets('başarılı: yeni şifre kaydedilir, sayfa kapanır', (
      tester,
    ) async {
      final env = (await tester.runAsync(CmEnv.create))!;
      addTearDown(env.dispose);
      await pumpCmApp(tester, env, location: '/company/users');
      await pumpFor(tester, const Duration(seconds: 1));
      await openFor(tester, 'Hakan Öz');
      await tester.tap(find.text('Şifre belirle'));
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.text('Hakan Öz · hakan.oz'), findsOneWidget);
      // Göster / gizle her alanda.
      expect(find.text('Göster'), findsNWidgets(2));
      // İstemci yalnızca eşleşmeyi denetler.
      await fill(tester, 'Yeni12345', 'Yeni1234');
      expect(find.text('Şifreler aynı değil.'), findsOneWidget);
      expect(env.requests.where((r) => r.path.endsWith('/password')), isEmpty);
      await fill(tester, 'Yeni1234', 'Yeni1234');
      expect(
        env.requests.any(
          (r) =>
              r.method == 'POST' &&
              r.path == 'customers/me/company-users/u-cm-1/password',
        ),
        isTrue,
      );
      final users = env.world.bag<List<Map<String, dynamic>>>(
        'cm.companyUsers',
        () => [],
      );
      expect(
        users.firstWhere((u) => u['userId'] == 'u-cm-1')['password'],
        'Yeni1234',
      );
      expect(find.text('Şifreyi kaydet'), findsNothing, reason: 'kapandı');
      expect(find.textContaining('yeni şifre kaydedildi'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('sunucunun doğrulama iletisi sayfada görünür', (tester) async {
      final env = (await tester.runAsync(CmEnv.create))!;
      addTearDown(env.dispose);
      await pumpCmApp(tester, env, location: '/company/users');
      await pumpFor(tester, const Duration(seconds: 1));
      await openFor(tester, 'Hakan Öz');
      await tester.tap(find.text('Şifre belirle'));
      await pumpFor(tester, const Duration(milliseconds: 600));
      await fill(tester, 'kisa', 'kisa');
      // `errors.newPassword` "Yeni şifre" alanının altında (bantta değil).
      expect(
        find.descendant(
          of: _fieldBox('Yeni şifre *'),
          matching: find.textContaining('Şifre en az 8 karakter olmalıdır.'),
        ),
        findsOneWidget,
      );
      expect(find.byType(AknBanner), findsNothing);
      expect(find.text('Şifreyi kaydet'), findsOneWidget, reason: 'açık kalır');
      final users = env.world.bag<List<Map<String, dynamic>>>(
        'cm.companyUsers',
        () => [],
      );
      expect(
        users.firstWhere((u) => u['userId'] == 'u-cm-1')['password'],
        isNull,
      );
      await finish(tester);
    });

    testWidgets('yetki yoksa (CustomerCompanyUsers:Duzenler) görünmez', (
      tester,
    ) async {
      final env = (await tester.runAsync(
        () => CmEnv.create(
          overrides: [
            accessPolicyProvider.overrideWith((ref) {
              final a = ref.watch(sessionControllerProvider).access;
              if (a == null) return AccessPolicy.signedOut;
              final edit = '${Pg.customerCompanyUsers}:${Perm.edit}';
              return AccessPolicy(
                MeAccess.fromJson({
                  ...a.toJson(),
                  'pages': [
                    for (final p in a.pages)
                      if (p != edit) p,
                  ],
                }),
              );
            }),
          ],
        ),
      ))!;
      addTearDown(env.dispose);
      await pumpCmApp(tester, env, location: '/company/users');
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.byType(UserCard), findsNWidgets(5));
      await openFor(tester, 'Hakan Öz');
      expect(find.text('Şifre belirle'), findsNothing);
      await finish(tester);
    });

    testWidgets('ana kullanıcıda yalnızca kendisi: kendi satırında var', (
      tester,
    ) async {
      final env = (await tester.runAsync(CmEnv.create))!;
      addTearDown(env.dispose);
      await pumpCmApp(tester, env, location: '/company/users');
      await pumpFor(tester, const Duration(seconds: 1));
      // Selin Aydın hem ana kullanıcı hem kendisi.
      await openFor(tester, 'Selin Aydın (siz)');
      expect(find.text('Şifre belirle'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('ana kullanıcı başkasıysa onun satırında yok', (tester) async {
      final env = (await tester.runAsync(CmEnv.create))!;
      addTearDown(env.dispose);
      // Ana kullanıcı Elif Demir; oturumdaki Selin Aydın değil.
      env.harness.server.get(
        'customers/me/company-users',
        (req) => [
          {
            'userId': 'u-musteri',
            'displayName': 'Selin Aydın',
            'userName': 'musteri',
            'email': 'musteri@demo.akaryakitnet.local',
            'role': 3,
            'isSelf': true,
            'isActive': true,
          },
          {
            'userId': 'u-onay',
            'displayName': 'Elif Demir',
            'userName': 'onay',
            'email': 'onay@demo.akaryakitnet.local',
            'role': 3,
            'isMainUser': true,
            'isActive': true,
          },
          {
            'userId': 'u-cm-1',
            'displayName': 'Hakan Öz',
            'userName': 'hakan.oz',
            'email': '',
            'role': 3,
            'isActive': true,
          },
        ],
      );
      await pumpCmApp(tester, env, location: '/company/users');
      await pumpFor(tester, const Duration(seconds: 1));
      await openFor(tester, 'Elif Demir');
      expect(find.text('Bilgileri düzenle'), findsOneWidget);
      expect(find.text('Şifre belirle'), findsNothing);
      await tester.tapAt(const Offset(200, 40));
      await pumpFor(tester, const Duration(milliseconds: 600));
      await openFor(tester, 'Hakan Öz');
      expect(find.text('Şifre belirle'), findsOneWidget);
      // E-postası olmayana bağlantı gönderilmez.
      expect(find.text('Bağlantıyı yeniden gönder'), findsNothing);
      await finish(tester);
    });

    test('kural: yönetebilen herkes; ana kullanıcıda yalnızca kendisi', () {
      AccessPolicy policy({bool edit = true}) => AccessPolicy(
        MeAccess.fromJson({
          'userId': 'u-musteri',
          'persona': 'customer',
          'customerId': 101,
          'customerUserRole': 3,
          'pages': [
            '${Pg.customerCompanyUsers}:${Perm.view}',
            if (edit) '${Pg.customerCompanyUsers}:${Perm.edit}',
          ],
        }),
      );
      const other = CompanyUser(
        userId: 'u-x',
        displayName: 'X',
        role: CustomerUserRole.admin,
      );
      const mainOther = CompanyUser(
        userId: 'u-y',
        displayName: 'Y',
        role: CustomerUserRole.admin,
        isMainUser: true,
      );
      const mainSelf = CompanyUser(
        userId: 'u-musteri',
        displayName: 'Z',
        role: CustomerUserRole.admin,
        isMainUser: true,
        isSelf: true,
      );
      expect(policy().cmCanSetPassword(other), isTrue);
      expect(policy().cmCanSetPassword(mainSelf), isTrue);
      expect(policy().cmCanSetPassword(mainOther), isFalse);
      expect(policy(edit: false).cmCanSetPassword(other), isFalse);
      expect(policy(edit: false).cmCanSetPassword(mainSelf), isFalse);
    });
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
      await tester.enterText(fieldLabeled('Kullanıcı adı *'), 'deniz.ak');
      await tester.enterText(
        fieldLabeled('E-posta (isteğe bağlı)'),
        'deniz.ak@anadolulojistik.example',
      );
      await tester.tap(find.text('Onaylayan').last);
      await pumpFor(tester, const Duration(milliseconds: 300));
      await tester.tap(find.text('Kullanıcıyı ekle'));
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

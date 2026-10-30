// Ekip (`/bayi/staff`): rol çipleri, son giriş, ara; aktif / pasif anahtarı (pasifleştirme onaylı) ve
// "Şifre bağlantısı gönder" yalnızca StationStaff:Duzenler ile; kendi hesabında anahtar yok; Görür
// yetkisiyle salt okunur; sevkiyat ve saha satış ekranı hiç göremez. "Şifre belirle" (sahip
// 2026-10-30): düzenleyebilen, başkasının kartında; bayinin ana hesabında (`isMainAccount`) yok.
import 'package:akaryakitnet/core/auth/access_policy.dart';
import 'package:akaryakitnet/core/auth/permissions.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/models/me_access.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/bayi/application/staff_controller.dart';
import 'package:akaryakitnet/features/bayi/copy.dart';
import 'package:akaryakitnet/features/bayi/data/staff_models.dart';
import 'package:akaryakitnet/features/bayi/fake/staff_fake.dart';
import 'package:akaryakitnet/features/bayi/presentation/staff/staff_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bayi_app.dart';

Finder _card(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(StaffRow)).first;

Finder _inCard(String name, Finder f) =>
    find.descendant(of: _card(name), matching: f);

Finder _segment(String label) => find.descendant(
  of: find.byType(AknSegmented<StaffFilter>),
  matching: find.textContaining(label),
);

Finder _confirm(String label) =>
    find.descendant(of: find.byType(ConfirmSheet), matching: find.text(label));

void main() {
  testWidgets(
    'bayi sahibi: pasifleştirme onaylı, yeniden aktifleştirme, şifre bağlantısı',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'sahip',
        location: '/bayi/staff',
      );
      expect(find.text('Ekip'), findsWidgets);
      // Kendi kartı: "Siz", anahtar yok.
      expect(_inCard('Mehmet Demir', find.text('Siz')), findsOneWidget);
      expect(_inCard('Mehmet Demir', find.byType(Switch)), findsNothing);
      // Rol çipleri, son giriş, ara.
      expect(_inCard('Mustafa Er', find.text('Şoför')), findsOneWidget);
      expect(
        _inCard('Mustafa Er', find.text('Henüz giriş yapmadı')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Mustafa Er ara'), findsOneWidget);

      // Pasifleştir: onay sorulur; vazgeçilirse değişmez.
      await scrollTap(tester, _inCard('Mustafa Er', find.byType(Switch)));
      expect(find.text('Mustafa Er pasifleştirilsin mi?'), findsOneWidget);
      await scrollTap(tester, _confirm('Vazgeç'));
      expect(
        app.container
            .read(staffProvider)
            .all
            .firstWhere((m) => m.displayName == 'Mustafa Er')
            .isActive,
        isTrue,
      );
      await scrollTap(tester, _inCard('Mustafa Er', find.byType(Switch)));
      await scrollTap(tester, _confirm('Pasifleştir'));
      final s = app.container.read(staffProvider);
      expect(
        s.all.firstWhere((m) => m.displayName == 'Mustafa Er').isActive,
        isFalse,
      );
      expect(
        find.text('Mustafa Er'),
        findsNothing,
        reason: '"Aktif" süzgecinden düştü',
      );

      // "Pasif" süzgecinde: yeniden aktifleştirme onaysız.
      await scrollTap(tester, _segment('Pasif'));
      expect(find.text('Kerem Balcı'), findsOneWidget);
      expect(_inCard('Mustafa Er', find.text('Pasif')), findsWidgets);
      expect(
        _inCard('Mustafa Er', find.text('Şifre bağlantısı gönder')),
        findsNothing,
      );
      await scrollTap(tester, _inCard('Mustafa Er', find.byType(Switch)));
      expect(find.byType(ConfirmSheet), findsNothing);
      expect(
        app.container
            .read(staffProvider)
            .all
            .firstWhere((m) => m.displayName == 'Mustafa Er')
            .isActive,
        isTrue,
      );

      // Şifre bağlantısı: onaydan sonra gönderilir.
      await scrollTap(tester, _segment('Aktif'));
      await scrollTap(
        tester,
        _inCard('Serdar Çınar', find.text('Şifre bağlantısı gönder')),
      );
      expect(find.text('Şifre bağlantısı gönderilsin mi?'), findsOneWidget);
      await scrollTap(tester, _confirm('Gönder'));
      expect(fakePasswordResets(app.harness.world), contains('u-sofor3'));
      expect(tester.takeException(), isNull);
      await app.finish(tester);
    },
  );

  group('Şifre belirle (sahip 2026-10-30)', () {
    Finder field(String label) => find
        .descendant(
          of: find.ancestor(
            of: find.text(label),
            matching: find.byType(AknTextField),
          ),
          matching: find.byType(TextFormField),
        )
        .first;

    Future<void> fill(WidgetTester tester, String next, String again) async {
      await tester.enterText(field('Yeni şifre *'), next);
      await tester.enterText(field('Yeni şifre (tekrar) *'), again);
      await scrollTap(tester, find.text('Şifreyi kaydet'));
      await BayiTestApp.settle(tester);
    }

    testWidgets(
      'yönetici: kullanıcı adı kartta; başkasının kartında var, kendi kartında yok; kaydedilir',
      (tester) async {
        final app = await BayiTestApp.start(
          tester,
          persona: 'sahip',
          location: '/bayi/staff',
        );
        expect(_inCard('Mustafa Er', find.text('mustafa.er')), findsOneWidget);
        expect(_inCard('Mehmet Demir', find.text('sahip')), findsOneWidget);
        expect(
          _inCard('Mehmet Demir', find.text('Şifre belirle')),
          findsNothing,
        );
        expect(
          _inCard('Mustafa Er', find.text('Şifre belirle')),
          findsOneWidget,
        );
        await scrollTap(
          tester,
          _inCard('Mustafa Er', find.text('Şifre belirle')),
        );
        expect(find.text('Mustafa Er · mustafa.er'), findsOneWidget);
        await fill(tester, 'Yeni1234', 'Yeni1234');
        expect(fakePasswordsSet(app.harness.world)['u-sofor2'], 'Yeni1234');
        expect(find.text('Şifreyi kaydet'), findsNothing);
        expect(tester.takeException(), isNull);
        await app.finish(tester);
      },
    );

    testWidgets('sunucu iletileri: doğrulama ve yetki (403) sayfada', (
      tester,
    ) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'sahip',
        location: '/bayi/staff',
      );
      await scrollTap(
        tester,
        _inCard('Serdar Çınar', find.text('Şifre belirle')),
      );
      await fill(tester, 'kisa', 'kisa');
      expect(
        find.textContaining('Şifre en az 8 karakter olmalıdır.'),
        findsOneWidget,
      );
      expect(fakePasswordsSet(app.harness.world), isEmpty);
      // Yedek: düğme ana hesapta gizli olsa da sunucu 403 dönerse ileti sayfada görünür (genel 403
      // bildirimi çıkmaz).
      app.harness.server.post(
        'stations/me/staff/{userId}/password',
        (req) => throw FakeResponse.forbidden(
          'Bayinin ana hesabının şifresini yalnızca kendisi değiştirebilir.',
        ),
      );
      await fill(tester, 'Yeni1234', 'Yeni1234');
      expect(
        find.text(
          'Bayinin ana hesabının şifresini yalnızca kendisi değiştirebilir.',
        ),
        findsOneWidget,
      );
      expect(find.text('Şifreyi kaydet'), findsOneWidget);
      await app.finish(tester);
    });

    testWidgets(
      'bayinin ana hesabı (isMainAccount): başka yönetici onun kartında görmez; diğerlerinde görür',
      (tester) async {
        // Personeli düzenleyebilen ama ana hesap olmayan yönetici: müdür + `StationStaff:Duzenler`.
        final app = await BayiTestApp.start(
          tester,
          persona: 'mudur',
          location: '/bayi/staff',
          overrides: [
            accessPolicyProvider.overrideWith((ref) {
              final a = ref.watch(sessionControllerProvider).access;
              if (a == null) return AccessPolicy.signedOut;
              return AccessPolicy(
                MeAccess.fromJson({
                  ...a.toJson(),
                  'pages': [...a.pages, '${Pg.stationStaff}:${Perm.edit}'],
                }),
              );
            }),
          ],
        );
        // Sahte sunucu bayinin sahibini ana hesap işaretler (yalnızca onu).
        final staff = app.container.read(staffProvider).all;
        expect(staff.where((m) => m.isMainAccount).map((m) => m.userId), const [
          'u-sahip',
        ]);
        expect(
          find.textContaining('Ekibi görüntüleyebilirsiniz'),
          findsNothing,
          reason: 'düzenleme yetkisi var',
        );
        expect(
          _inCard('Mehmet Demir', find.text('Şifre belirle')),
          findsNothing,
          reason: 'ana hesap, kendisi değil',
        );
        expect(
          _inCard('Mustafa Er', find.text('Şifre belirle')),
          findsOneWidget,
        );
        expect(
          _inCard('Ayşe Kaya', find.text('Şifre belirle')),
          findsNothing,
          reason: 'kendi kartı (şifresini Profil\'den değiştirir)',
        );
        await app.finish(tester);
      },
    );

    test('StaffMember.isMainAccount: alan yoksa false', () {
      StaffMember parse(Map<String, Object?> j) =>
          StaffMember.fromJson(JsonReader.of({'userId': 'u-1', ...j}));
      expect(parse(const {}).isMainAccount, isFalse);
      expect(parse(const {'isMainAccount': true}).isMainAccount, isTrue);
      expect(parse(const {'isMainAccount': false}).isMainAccount, isFalse);
      expect(
        parse(const {
          'isMainAccount': true,
        }).copyWith(isActive: false).isMainAccount,
        isTrue,
      );
    });

    testWidgets('düzenleme yetkisi yoksa (Görür) görünmez', (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'mudur',
        location: '/bayi/staff',
      );
      expect(find.text('Mustafa Er'), findsOneWidget);
      expect(find.text('mustafa.er'), findsOneWidget);
      expect(find.text('Şifre belirle'), findsNothing);
      await app.finish(tester);
    });
  });

  testWidgets('arama: ad, e-posta, rol', (tester) async {
    final app = await BayiTestApp.start(
      tester,
      persona: 'sahip',
      location: '/bayi/staff',
    );
    await tester.enterText(find.byType(TextField).first, 'şoför');
    await BayiTestApp.settle(tester);
    final visible = app.container.read(staffProvider).visible;
    expect(visible, isNotEmpty);
    expect(visible.every((m) => m.roles.any((r) => r.isDriver)), isTrue);
    expect(find.text('Gizem Şahin'), findsNothing);
    await app.finish(tester);
  });

  testWidgets(
    'bayi müdürü (Görür): salt okunur, anahtar ve şifre bağlantısı yok',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'mudur',
        location: '/bayi/staff',
      );
      expect(
        find.textContaining('Ekibi görüntüleyebilirsiniz'),
        findsOneWidget,
      );
      expect(find.byType(Switch), findsNothing);
      expect(find.text('Şifre bağlantısı gönder'), findsNothing);
      expect(find.text('Mustafa Er'), findsOneWidget);
      expect(find.bySemanticsLabel('Mustafa Er ara'), findsOneWidget);
      await app.finish(tester);
    },
  );

  for (final persona in const ['sevkiyat', 'saha']) {
    testWidgets('$persona: Ekip ekranı yetkisiz', (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: persona,
        location: '/bayi/staff',
      );
      expect(find.text(BayiCopy.forbiddenTitle), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      expect(find.text('Mustafa Er'), findsNothing);
      await app.finish(tester);
    });
  }
}

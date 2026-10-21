// Ekip (`/bayi/staff`): rol çipleri, son giriş, ara; aktif / pasif anahtarı (pasifleştirme onaylı) ve
// "Şifre bağlantısı gönder" yalnızca StationStaff:Duzenler ile; kendi hesabında anahtar yok; Görür
// yetkisiyle salt okunur; sevkiyat ve saha satış ekranı hiç göremez.
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/bayi/application/staff_controller.dart';
import 'package:akaryakitnet/features/bayi/copy.dart';
import 'package:akaryakitnet/features/bayi/fake/staff_fake.dart';
import 'package:akaryakitnet/features/bayi/presentation/staff/staff_page.dart';
import 'package:akaryakitnet/features/bayi/presentation/widgets/bayi_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bayi_app.dart';

Finder _card(String name) =>
    find.ancestor(of: find.text(name), matching: find.byType(StaffRow)).first;

Finder _inCard(String name, Finder f) =>
    find.descendant(of: _card(name), matching: f);

Finder _segment(String label) => find.descendant(
  of: find.byType(BayiSegmented<StaffFilter>),
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

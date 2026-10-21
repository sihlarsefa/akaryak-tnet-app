// Giriş ekranı (spec A.4 A1, C.7): erişilebilirlik matrisi, hatalı şifre, kilitlenme geri sayımı,
// telefon sekmesi, "Hesabım yok", yasal bağlantılar, "Şifremi unuttum", demo hesapları.
import 'package:akaryakitnet/core/env/app_config_controller.dart';
import 'package:akaryakitnet/core/models/app_config.dart';
import 'package:akaryakitnet/features/auth/application/auth_throttle.dart';
import 'package:akaryakitnet/features/auth/application/login_effects.dart';
import 'package:akaryakitnet/features/auth/auth_fake.dart';
import 'package:akaryakitnet/features/auth/presentation/code_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_test_support.dart';

Finder _field(String label) => find.widgetWithText(TextField, label);

void main() {
  a11yMatrix('giriş (şifre)', (tester, scale, b) async {
    await pumpAuthRoute(tester, '/login', textScale: scale, brightness: b);
    expect(find.text('Giriş yap'), findsOneWidget);
    expect(find.text('Hesabınıza giriş yapın'), findsOneWidget);
    expect(find.text('Şifreyle'), findsOneWidget);
  });

  a11yMatrix('giriş (telefon sekmesi)', (tester, scale, b) async {
    await pumpAuthRoute(tester, '/login', textScale: scale, brightness: b);
    await tapVisible(tester, find.text('Telefonla'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text('Kod gönder'), findsOneWidget);
    expect(_field('Cep telefonu'), findsOneWidget);
  });

  a11yMatrix('giriş (kilitlenme bandı ve geri sayım)', (
    tester,
    scale,
    b,
  ) async {
    final clock = TestClock();
    final c = await pumpAuthRoute(
      tester,
      '/login',
      textScale: scale,
      brightness: b,
      overrides: clockAndLinks(clock: clock),
    );
    c
        .read(authThrottleProvider.notifier)
        .hold(
          ThrottleScope.password,
          const Duration(minutes: 15),
          message: 'Çok fazla hatalı deneme yapıldı.',
          lockout: true,
        );
    await tester.pump();
    expect(find.text('Giriş geçici olarak kapalı'), findsOneWidget);
    expect(find.text('Tekrar dene · 15:00'), findsOneWidget);
  });

  testWidgets('boş alanlar: alan hataları, istek gitmez', (tester) async {
    setPhoneSize(tester);
    await pumpAuthRoute(tester, '/login');
    await tapVisible(tester, find.text('Giriş yap'));
    await tester.pump();
    expect(
      find.text('Kullanıcı adınızı ya da e-postanızı girin.'),
      findsOneWidget,
    );
    expect(find.text('Şifrenizi girin.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hatalı şifre: sunucunun mesajı, şifre temizlenir', (
    tester,
  ) async {
    setPhoneSize(tester);
    await pumpAuthRoute(tester, '/login');
    await tester.enterText(_field('Kullanıcı adı veya e-posta'), 'musteri');
    await tester.enterText(_field('Şifre'), 'yanlis');
    await tapVisible(tester, find.text('Giriş yap'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Giriş yapılamadı'), findsOneWidget);
    expect(find.text('Kullanıcı adı veya şifre hatalı.'), findsOneWidget);
    final password = tester.widget<TextField>(_field('Şifre'));
    expect(password.controller!.text, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('şifre göster / gizle', (tester) async {
    setPhoneSize(tester);
    await pumpAuthRoute(tester, '/login');
    TextField pw() => tester.widget<TextField>(_field('Şifre'));
    expect(pw().obscureText, isTrue);
    await tapVisible(tester, find.byTooltip('Şifreyi göster'));
    await tester.pump();
    expect(pw().obscureText, isFalse);
    expect(find.byTooltip('Şifreyi gizle'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    '5 hatalı deneme: kilit bandı, düğme sayar, süre dolunca açılır',
    (tester) async {
      setPhoneSize(tester);
      final clock = TestClock();
      final h = await AuthHarness.create();
      AuthFakeControls.of(h.server).now = clock.call;
      await pumpAuthRoute(
        tester,
        '/login',
        harness: h,
        overrides: clockAndLinks(clock: clock),
      );
      for (var i = 0; i < 5; i++) {
        await tester.enterText(_field('Kullanıcı adı veya e-posta'), 'musteri');
        await tester.enterText(_field('Şifre'), 'yanlis');
        await tapVisible(tester, find.text('Giriş yap'));
        await pumpFor(tester, const Duration(milliseconds: 300));
      }
      expect(find.text('Giriş geçici olarak kapalı'), findsOneWidget);
      expect(find.textContaining('15 dakika kapatıldı'), findsOneWidget);
      expect(find.text('Tekrar dene · 15:00'), findsOneWidget);
      expect(find.text('Giriş yap'), findsNothing);

      clock.advance(const Duration(minutes: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Tekrar dene · 10:00'), findsOneWidget);

      clock.advance(const Duration(minutes: 10, seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('Giriş yap'), findsOneWidget);
      expect(find.text('Giriş geçici olarak kapalı'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'telefonla giriş: geçersiz numara uyarısı, geçerli numara kod ekranı',
    (tester) async {
      setPhoneSize(tester);
      await pumpAuthRoute(tester, '/login');
      await tapVisible(tester, find.text('Telefonla'));
      await pumpFor(tester, const Duration(milliseconds: 500));
      await tester.enterText(_field('Cep telefonu'), '123');
      await tapVisible(tester, find.text('Kod gönder'));
      await tester.pump();
      expect(
        find.text('Geçerli bir cep telefonu girin (5XX XXX XX XX).'),
        findsOneWidget,
      );
      await tester.enterText(_field('Cep telefonu'), '05320000101');
      expect(
        tester.widget<TextField>(_field('Cep telefonu')).controller!.text,
        '532 000 01 01',
      );
      await tapVisible(tester, find.text('Kod gönder'));
      await pumpFor(tester, const Duration(milliseconds: 800));
      expect(find.byType(CodePage), findsOneWidget);
      expect(find.text('Telefonla giriş'), findsWidgets);
      expect(find.textContaining('0532 *** ** 01'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('telefon sekmesi yalnızca features.otpLogin açıkken', (
    tester,
  ) async {
    setPhoneSize(tester);
    final h = await AuthHarness.create();
    h.server.get(
      'app/config',
      (req) => {
        'contractVersion': 'mobile-v1',
        'features': {'otpLogin': false},
      },
      anonymous: true,
    );
    await pumpAuthRoute(tester, '/login', harness: h);
    expect(find.text('Telefonla'), findsNothing);
    expect(find.text('Giriş yap'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('"Hesabım yok": açıklama ve destek kanalları açılır', (
    tester,
  ) async {
    setPhoneSize(tester);
    final links = LinkLog();
    await pumpAuthRoute(
      tester,
      '/login',
      overrides: clockAndLinks(links: links),
    );
    await tapVisible(tester, find.text('Hesabım yok'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text('Hesabınız yok mu?'), findsOneWidget);
    expect(find.textContaining('bayiniz ya da şirketinizin'), findsOneWidget);
    expect(find.text('Destek hattını arayın'), findsOneWidget);
    expect(find.text('WhatsApp\'tan yazın'), findsOneWidget);
    expect(find.text('E-posta gönderin'), findsOneWidget);

    await tapVisible(tester, find.text('Destek hattını arayın'));
    await tapVisible(tester, find.text('WhatsApp\'tan yazın'));
    await tapVisible(tester, find.text('E-posta gönderin'));
    expect(links.uris.map((u) => u.scheme).toList(), [
      'tel',
      'https',
      'mailto',
    ]);
    expect(links.uris[1].host, 'wa.me');
    expect(links.opened.every((o) => o.external), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('alt bilgi: Gizlilik · KVKK · Koşullar uygulama içi tarayıcıda', (
    tester,
  ) async {
    setPhoneSize(tester);
    final links = LinkLog();
    await pumpAuthRoute(
      tester,
      '/login',
      overrides: clockAndLinks(links: links),
    );
    await tester.scrollUntilVisible(
      find.text('Gizlilik'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    for (final label in ['Gizlilik', 'KVKK', 'Koşullar']) {
      await tapVisible(tester, find.text(label));
      await tester.pump();
    }
    expect(links.uris.map((u) => u.path).toList(), [
      '/gizlilik',
      '/kvkk',
      '/kullanim-kosullari',
    ]);
    expect(links.opened.every((o) => !o.external), isTrue);
    expect(find.text('Sürüm 1.0.0 (1)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('"Şifremi unuttum" portal sayfasını açar', (tester) async {
    setPhoneSize(tester);
    final links = LinkLog();
    await pumpAuthRoute(
      tester,
      '/login',
      overrides: clockAndLinks(links: links),
    );
    await tapVisible(tester, find.text('Şifremi unuttum'));
    await tester.pump();
    expect(links.uris.single.path, '/Account/ForgotPassword');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('kilit ekranından gelince kullanıcı adı hazır', (tester) async {
    setPhoneSize(tester);
    await pumpAuthRoute(
      tester,
      '/login',
      overrides: [
        loginPrefillProvider.overrideWith(() => _Prefilled('musteri')),
      ],
    );
    expect(
      tester
          .widget<TextField>(_field('Kullanıcı adı veya e-posta'))
          .controller!
          .text,
      'musteri',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('isteğe bağlı güncelleme bandı', (tester) async {
    setPhoneSize(tester);
    await pumpAuthRoute(
      tester,
      '/login',
      overrides: [
        appConfigProvider.overrideWith(
          () => _FixedConfig(
            const AppConfig(latestBuild: 9, storeUrl: 'https://store.test/app'),
          ),
        ),
      ],
    );
    expect(find.text('Yeni sürüm hazır'), findsOneWidget);
    expect(find.text('Güncelle'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

class _FixedConfig extends AppConfigController {
  _FixedConfig(this.config);
  final AppConfig config;

  @override
  AppConfig build() => config;

  @override
  Future<void> load({Duration timeout = Duration.zero}) async {}
}

class _Prefilled extends LoginPrefill {
  _Prefilled(this.value);
  final String value;

  @override
  String? build() => value;
}

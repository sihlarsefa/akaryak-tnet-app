// Giriş ekranı (spec A.4 A1, C.7): erişilebilirlik matrisi, hatalı şifre, kilitlenme geri sayımı,
// telefonla giriş, "Bayinizden davet isteyin", yasal bağlantılar, "Şifremi unuttum", demo hesapları
// (sahip kararı 2026-10-21: bandın altında Müşteri / Bayi / Merkez kartları, tek dokunuşla giriş;
// canlı kipte yok).
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/env/app_config_controller.dart';
import 'package:akaryakitnet/core/env/app_env.dart';
import 'package:akaryakitnet/core/models/app_config.dart';
import 'package:akaryakitnet/core/models/me_access.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/auth/application/auth_throttle.dart';
import 'package:akaryakitnet/features/auth/application/login_effects.dart';
import 'package:akaryakitnet/features/auth/auth_fake.dart';
import 'package:akaryakitnet/features/auth/presentation/code_page.dart';
import 'package:akaryakitnet/features/auth/presentation/widgets/demo_accounts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_test_support.dart';

/// Etiketi alanın üstünde duran (tasarım v2 §6.10) metin alanı.
Finder _field(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(AknTextField)),
  matching: find.byType(TextField),
);

void main() {
  a11yMatrix('giriş (şifre, demo derlemesi)', (tester, scale, b) async {
    await pumpAuthRoute(tester, '/login', textScale: scale, brightness: b);
    expect(find.text('Giriş yap'), findsOneWidget);
    expect(find.text('Hoş geldiniz'), findsOneWidget);
    expect(find.text('Numara ile'), findsOneWidget);
    // Demo bölümü bandın altında, formun üstünde; başlığın yerini ayraç alır.
    expect(find.text('Demo hesaplarıyla girin'), findsOneWidget);
    expect(find.text('Kendi hesabınızla girin'), findsOneWidget);
    expect(find.text('Giriş yapın'), findsNothing);
    _expectAbove(tester, 'Demo hesaplarıyla girin', 'Kendi hesabınızla girin');
    _expectAbove(
      tester,
      'Kendi hesabınızla girin',
      'E-posta ya da kullanıcı adı',
    );
  });

  a11yMatrix('giriş (canlı derleme: demo yok)', (tester, scale, b) async {
    await pumpAuthRoute(
      tester,
      '/login',
      textScale: scale,
      brightness: b,
      overrides: [demoLoginsEnabledProvider.overrideWithValue(false)],
    );
    expect(find.text('Giriş yap'), findsOneWidget);
    expect(find.text('Giriş yapın'), findsOneWidget);
    expect(find.text('Demo hesaplarıyla girin'), findsNothing);
    expect(find.text('Kendi hesabınızla girin'), findsNothing);
    expect(find.byType(DemoPersonaCard), findsNothing);
  });

  a11yMatrix('giriş (demo kartları kaydırılmış)', (tester, scale, b) async {
    await pumpAuthRoute(tester, '/login', textScale: scale, brightness: b);
    await tester.scrollUntilVisible(
      find.text('Merkez Operasyon'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('Merkez · Yönetici'), findsOneWidget);
  });

  a11yMatrix('giriş (telefon sekmesi)', (tester, scale, b) async {
    await pumpAuthRoute(tester, '/login', textScale: scale, brightness: b);
    await tapVisible(tester, find.text('Numara ile'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text('Kod gönder'), findsOneWidget);
    expect(find.text('Şifre ile'), findsOneWidget);
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
    expect(find.text('Tekrar dene (15:00)'), findsOneWidget);
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
    await tester.enterText(_field('E-posta ya da kullanıcı adı'), 'musteri');
    await tester.enterText(_field('Şifre'), 'yanlis');
    await tapVisible(tester, find.text('Giriş yap'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Giriş yapılamadı'), findsOneWidget);
    expect(find.text('Kullanıcı adı veya şifre hatalı.'), findsOneWidget);
    final password = tester.widget<TextField>(_field('Şifre'));
    expect(password.controller!.text, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('v4: alanlarda simge yok, şifrede yalnızca "Göster"', (
    tester,
  ) async {
    setPhoneSize(tester);
    await pumpAuthRoute(tester, '/login');
    final fields = find.byType(AknTextField);
    expect(fields, findsNWidgets(2));
    final icons = find.descendant(of: fields, matching: find.byType(Icon));
    // Yalnızca şifre alanının göz simgesi ("Göster" düğmesi).
    expect(icons, findsOneWidget);
    expect(
      find.descendant(of: fields.last, matching: find.text('Göster')),
      findsOneWidget,
    );
    // "Şifre ile / Numara ile" anahtarı da yalın (simgesiz).
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Şifre ile'),
          matching: find.byType(Row),
        ),
        matching: find.byType(Icon),
      ),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('v4: klavye açılınca "Giriş yap" klavyenin üstünde görünür', (
    tester,
  ) async {
    setPhoneSize(tester, const Size(390, 844));
    await pumpAuthRoute(tester, '/login');
    await tapVisible(tester, _field('E-posta ya da kullanıcı adı'));
    await tester.pump();
    // Klavye: 336 dp.
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    addTearDown(tester.view.resetViewInsets);
    await pumpFor(tester, const Duration(milliseconds: 900));
    final button = tester.getRect(
      find.ancestor(
        of: find.text('Giriş yap'),
        matching: find.byType(AknButton),
      ),
    );
    expect(button.bottom, lessThanOrEqualTo(844 - 336 + 0.5));
    expect(button.top, greaterThanOrEqualTo(0));
    // Odaktaki alan da görünür kalır.
    final field = tester.getRect(_field('E-posta ya da kullanıcı adı'));
    expect(field.top, greaterThanOrEqualTo(0));
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
        await tester.enterText(
          _field('E-posta ya da kullanıcı adı'),
          'musteri',
        );
        await tester.enterText(_field('Şifre'), 'yanlis');
        await tapVisible(tester, find.text('Giriş yap'));
        await pumpFor(tester, const Duration(milliseconds: 300));
      }
      expect(find.text('Giriş geçici olarak kapalı'), findsOneWidget);
      expect(find.textContaining('15 dakika kapatıldı'), findsOneWidget);
      expect(find.text('Tekrar dene (15:00)'), findsOneWidget);
      expect(find.text('Giriş yap'), findsNothing);

      clock.advance(const Duration(minutes: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Tekrar dene (10:00)'), findsOneWidget);

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
      await tapVisible(tester, find.text('Numara ile'));
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
      expect(find.text('Kodu girin'), findsOneWidget);
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
    expect(find.text('Numara ile'), findsNothing);
    expect(find.text('Giriş yap'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    '"Bayinizden davet isteyin": açıklama ve destek kanalları açılır',
    (tester) async {
      setPhoneSize(tester);
      final links = LinkLog();
      await pumpAuthRoute(
        tester,
        '/login',
        overrides: clockAndLinks(links: links),
      );
      await tapVisible(tester, find.text('Bayinizden davet isteyin'));
      await pumpFor(tester, const Duration(milliseconds: 600));
      // Satırdaki soru + sayfanın başlığı.
      expect(find.text('Hesabınız yok mu?'), findsNWidgets(2));
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
    },
  );

  testWidgets('girişte alt bilgi yok (yasal bağlantılar ve sürüm Profil\'de)', (
    tester,
  ) async {
    setPhoneSize(tester);
    await pumpAuthRoute(tester, '/login');
    for (final label in ['Gizlilik', 'KVKK', 'Koşullar', 'Sürüm 1.0.0 (1)']) {
      expect(find.text(label), findsNothing, reason: label);
    }
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
          .widget<TextField>(_field('E-posta ya da kullanıcı adı'))
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

  group('demo hesapları', () {
    testWidgets('tüm demo hesapları tek satırda, her persona bir kart', (
      tester,
    ) async {
      setPhoneSize(tester);
      await pumpAuthRoute(tester, '/login');
      expect(find.text('Demo hesaplarıyla girin'), findsOneWidget);
      expect(find.textContaining('Tek dokunuşla giriş.'), findsOneWidget);
      expect(find.text('Tümünü gör'), findsOneWidget);
      // Sahip kararı: Müşteri, Bayi ve Merkez hesapları grup başlığı olmadan tek yatay satırda.
      for (final g in ['Müşteri', 'Bayi', 'Merkez']) {
        expect(find.text(g), findsNothing, reason: g);
      }
      expect(find.byType(DemoPersonaCard), findsNWidgets(fakePersonas.length));
      for (final p in fakePersonas) {
        expect(find.text(p.displayName), findsOneWidget, reason: p.key);
      }
      // v4 §5 01: her kartın alt satırı önce tarafı adlandırır ("Müşteri · Yönetici", "Bayi · Sahip").
      for (final subtitle in [
        'Müşteri · Yönetici',
        'Müşteri · Onaylayan',
        'Müşteri · Talep eden',
        'Bayi · Sahip',
        'Bayi · Müdür',
        'Bayi · Finans müdürü',
        'Bayi · Finans uzmanı',
        'Bayi · Muhasebe',
        'Bayi · Satış müdürü',
        'Bayi · Saha satış',
        'Bayi · Sipariş masası',
        'Bayi · Sevkiyat',
        'Bayi · Şoför',
        'Bayi · Depo',
        'Bayi · Görüntüleyici',
        'Merkez · Yönetici',
      ]) {
        expect(find.text(subtitle), findsOneWidget, reason: subtitle);
      }
      // Kartlar yatay kayar: müşteri kartları aynı satırda, soldan sağa, aynı boyda.
      Finder card(String name) => find.ancestor(
        of: find.text(name),
        matching: find.byType(DemoPersonaCard),
      );
      final selin = tester.getRect(card('Selin Aydın'));
      final elif = tester.getRect(card('Elif Demir'));
      expect(elif.top, selin.top);
      expect(elif.height, selin.height);
      expect(elif.left, greaterThan(selin.right));
      // Ekran okuyucu kartı tek düğme olarak okur.
      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel('Selin Aydın, Müşteri, Yönetici'),
        findsOneWidget,
      );
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'v4: 390 dp ekranda kartlar 156 dp, üçüncü kart ~34 dp görünür; ipucu satırı kalır',
      (tester) async {
        setPhoneSize(tester, const Size(390, 844));
        await pumpAuthRoute(tester, '/login');
        // Kartların açılış hareketi (sağdan kayarak) bitsin.
        await pumpFor(tester, const Duration(milliseconds: 1200));
        Finder card(String name) => find.ancestor(
          of: find.text(name),
          matching: find.byType(DemoPersonaCard),
        );
        final first = tester.getRect(card('Selin Aydın'));
        final second = tester.getRect(card('Elif Demir'));
        final third = tester.getRect(card('Burak Yılmaz'));
        expect(first.width, demoCardWidth);
        expect(first.left, 20);
        expect(second.left - first.right, 12);
        // Üçüncü kart ekranın sağ kenarından ~34 dp içeride başlar: kaydırılabildiği görünür.
        expect(390 - third.left, closeTo(34, 1));
        // İlk bakış: "Hoş geldiniz", hemen altında demo başlığı, ipucu ve kartlar; alt satır yok.
        expect(find.text('Hesabınıza giriş yapın.'), findsNothing);
        final welcome = tester.getRect(find.text('Hoş geldiniz'));
        final hint = tester.getRect(
          find.textContaining('Tek dokunuşla giriş.'),
        );
        expect(hint.top, greaterThan(welcome.bottom));
        expect(first.top, greaterThan(hint.bottom));
        expect(first.bottom, lessThan(844 / 2 + 80), reason: 'ilk ekranda');
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('karta dokunmak o hesapla giriş yapar (müşteri)', (
      tester,
    ) async {
      setPhoneSize(tester);
      final c = await pumpAuthRoute(tester, '/login');
      await tapVisible(tester, find.text('Selin Aydın'));
      await pumpUntil(tester, () => isSignedIn(c));
      expect(isSignedIn(c), isTrue);
      expect(c.read(sessionControllerProvider).access!.userName, 'musteri');
      // Form alanları doldurulmaz (parola yöneticisi demo hesabını kaydetmez).
      expect(
        tester
            .widget<TextField>(_field('E-posta ya da kullanıcı adı'))
            .controller!
            .text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('merkez kartı: SMS kodu kendiliğinden, kod ekranı yok', (
      tester,
    ) async {
      setPhoneSize(tester);
      final c = await pumpAuthRoute(tester, '/login');
      await tapVisible(tester, find.text('Merkez Operasyon'));
      await pumpUntil(tester, () => isSignedIn(c));
      await tester.pump();
      expect(isSignedIn(c), isTrue);
      expect(
        c.read(sessionControllerProvider).access!.persona,
        Persona.platform,
      );
      expect(find.byType(CodePage), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('formdan merkez girişi kod ekranını açar (demo kısayolu yok)', (
      tester,
    ) async {
      setPhoneSize(tester);
      await pumpAuthRoute(tester, '/login');
      await tester.enterText(_field('E-posta ya da kullanıcı adı'), 'merkez');
      await tester.enterText(_field('Şifre'), 'demo');
      await tapVisible(tester, find.text('Giriş yap'));
      await pumpFor(tester, const Duration(milliseconds: 800));
      expect(find.byType(CodePage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Bayi satırı yatay kayar; sondaki karta dokunmak giriş yapar', (
      tester,
    ) async {
      setPhoneSize(tester);
      final c = await pumpAuthRoute(tester, '/login', textScale: 2);
      final row = find.ancestor(
        of: find.text('Mehmet Demir'),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Kemal Aydın'),
        200,
        scrollable: row.first,
      );
      await tapVisible(tester, find.text('Kemal Aydın'));
      await pumpUntil(tester, () => isSignedIn(c));
      expect(c.read(sessionControllerProvider).access!.userName, 'ozelrol');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('"Tümünü gör": gruplu liste, açıklamalar; satır giriş yapar', (
      tester,
    ) async {
      setPhoneSize(tester);
      final c = await pumpAuthRoute(tester, '/login');
      await tapVisible(tester, find.text('Tümünü gör'));
      await pumpFor(tester, const Duration(milliseconds: 600));
      final sheet = find.byType(BottomSheet);
      expect(sheet, findsOneWidget);
      expect(
        find.descendant(of: sheet, matching: find.text('Demo hesabı seçin')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sheet,
          matching: find.text('Talep eden (şirket içi onaya düşer)'),
        ),
        findsOneWidget,
      );
      final burak = find.descendant(
        of: sheet,
        matching: find.text('Burak Yılmaz'),
      );
      await tapVisible(tester, burak);
      await pumpUntil(tester, () => isSignedIn(c));
      expect(c.read(sessionControllerProvider).access!.userName, 'talep');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('canlı kipte bölüm, kartlar ve "Demo" bağlantısı yok', (
      tester,
    ) async {
      setPhoneSize(tester, const Size(360, 1400));
      await pumpAuthRoute(
        tester,
        '/login',
        overrides: [demoLoginsEnabledProvider.overrideWithValue(false)],
      );
      expect(find.text('Demo hesaplarıyla girin'), findsNothing);
      expect(find.text('Tümünü gör'), findsNothing);
      expect(find.byType(DemoPersonaCard), findsNothing);
      expect(find.byType(OwnAccountDivider), findsNothing);
      expect(find.text('Demo'), findsNothing);
      expect(find.text('Selin Aydın'), findsNothing);
      expect(find.text('Giriş yapın'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    test('canlı API ortamında kapalı, sahte kipte açık', () {
      const live = AppEnv(
        env: AknEnv.test,
        apiBaseUrl: 'http://134.149.201.54:3108/',
        apiMode: ApiMode.live,
        portalBaseUrl: 'http://134.149.201.54:3107/',
      );
      final liveContainer = ProviderContainer(
        overrides: [appEnvProvider.overrideWithValue(live)],
      );
      addTearDown(liveContainer.dispose);
      expect(liveContainer.read(demoLoginsEnabledProvider), isFalse);

      final fakeContainer = ProviderContainer(
        overrides: [appEnvProvider.overrideWithValue(AppEnv.fakeForTests)],
      );
      addTearDown(fakeContainer.dispose);
      expect(fakeContainer.read(demoLoginsEnabledProvider), kFakeApiCompiled);
    });

    test(
      'sıra ve gruplar: Müşteri, Bayi, Merkez (sahip kararındaki sırayla)',
      () {
        final all = demoAccounts();
        expect(all.length, fakePersonas.length);
        expect(all.map((a) => a.key).toSet(), {
          for (final p in fakePersonas) p.key,
        });
        final groups = demoGroups(all);
        expect(groups.map((g) => g.$1).toList(), DemoGroup.values);
        expect(groups[0].$2.map((a) => a.key).toList(), [
          'musteri',
          'onay',
          'talep',
        ]);
        expect(groups[1].$2.map((a) => a.key).take(11).toList(), [
          'sahip',
          'mudur',
          'finans',
          'finansuzman',
          'muhasebe',
          'satis',
          'saha',
          'siparis',
          'sevkiyat',
          'sofor',
          'depo',
        ]);
        expect(groups[2].$2.single.key, 'merkez');
        // Ayrıntıda grup öneki ve " · " yok.
        for (final a in all) {
          expect(a.detail, isNot(contains(' · ')), reason: a.key);
          expect(a.role, isNotEmpty, reason: a.key);
        }
        expect(
          all.firstWhere((a) => a.key == 'talep').detail,
          'Talep eden (şirket içi onaya düşer)',
        );
      },
    );

    test('listede olmayan persona türünden gruba ve özetinden role düşer', () {
      const extra = FakePersona(
        key: 'yeni',
        displayName: 'Yeni Kişi',
        phone: '5320000999',
        persona: Persona.customer,
        roles: [],
        summary: 'Müşteri · muhasebe izleyicisi (salt okunur)',
        pages: {},
      );
      final a = demoAccounts([extra]).single;
      expect(a.group, DemoGroup.customer);
      expect(a.role, 'Muhasebe izleyicisi');
      expect(a.detail, 'Muhasebe izleyicisi (salt okunur)');
      expect(a.tone, DemoTone.orange);
    });
  });
}

/// [upper] metni [lower] metninin üstünde.
void _expectAbove(WidgetTester tester, String upper, String lower) {
  expect(
    tester.getTopLeft(find.text(upper)).dy,
    lessThan(tester.getTopLeft(find.text(lower)).dy),
    reason: '"$upper" "$lower" üstünde olmalı',
  );
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

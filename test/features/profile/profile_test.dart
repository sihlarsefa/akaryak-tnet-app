// Profil ve ayarlar (spec A.4 A8): tema, biyometrik kilit, yasal bağlantılar, telefonla giriş, asistan
// onayını geri alma, bekleme uyarılı çıkış ("Şimdi gönder" / "Yine de çık"), aktif oturumlar, şifre
// değiştir, profil düzenle, hesabımı sil, erişilebilirlik (C.7).
import 'package:akaryakitnet/core/auth/lock_settings.dart';
import 'package:akaryakitnet/core/offline/outbox_op.dart';
import 'package:akaryakitnet/core/offline/outbox_providers.dart';
import 'package:akaryakitnet/core/offline/outbox_runner.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/features/assistant/api.dart';
import 'package:akaryakitnet/features/auth/api.dart';
import 'package:akaryakitnet/features/profile/data/profile_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'a8_kit.dart';

const _tall = Size(390, 2600);

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 400 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

OutboxOp _op(String userId, {String type = 'test.op', String id = 'op-1'}) {
  final now = DateTime.now().toUtc();
  return OutboxOp(
    id: id,
    userId: userId,
    type: type,
    payload: const <String, dynamic>{},
    idempotencyKey: '3f1c2d9e-7b4a-4c1e-9f0a-2b6d8e4c1a57',
    label: 'Teslimat bildirimi',
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
}

void main() {
  // ------------------------------------------------------------------ Erişilebilirlik
  a11yMatrix('profil', (tester, scale, b) async {
    await pumpA8(tester, '/profile', textScale: scale, brightness: b);
    expect(find.text('Selin Aydın'), findsOneWidget);
  });

  a11yMatrix('profil (alt bölümler)', (tester, scale, b) async {
    await pumpA8(tester, '/profile', textScale: scale, brightness: b);
    await scrollTo(tester, find.text('Hesabımı sil'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('Çıkış yap'), findsOneWidget);
  });

  a11yMatrix('aktif oturumlar', (tester, scale, b) async {
    await pumpA8(tester, '/profile/sessions', textScale: scale, brightness: b);
    expect(find.text('Bu cihaz'), findsWidgets);
    expect(find.text('Tüm cihazlardan çık'), findsOneWidget);
  });

  a11yMatrix('şifre değiştir', (tester, scale, b) async {
    await pumpA8(tester, '/profile/password', textScale: scale, brightness: b);
    expect(find.text('Şifreyi değiştir'), findsOneWidget);
    expect(find.text('Mevcut şifre *'), findsOneWidget);
  });

  a11yMatrix('profil bilgileri', (tester, scale, b) async {
    await pumpA8(tester, '/profile/edit', textScale: scale, brightness: b);
    expect(find.text('Kaydet'), findsOneWidget);
    expect(find.text('Ad soyad *'), findsOneWidget);
  });

  a11yMatrix('hesabımı sil', (tester, scale, b) async {
    await pumpA8(
      tester,
      '/profile/delete-account',
      textScale: scale,
      brightness: b,
    );
    expect(
      find.textContaining('kişisel verilerinizin silinmesini'),
      findsOneWidget,
    );
    await scrollTo(tester, find.text('Saklananlar'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.text('Saklananlar'), findsOneWidget);
    await scrollTo(tester, find.text('Hesap silme hakkında'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(find.byType(Checkbox), findsOneWidget);
  });

  // ------------------------------------------------------------------ Profil
  testWidgets('tema: Koyu seçilir, tercihe yazılır', (tester) async {
    setPhoneSize(tester, _tall);
    final h = await A8Harness.create();
    final c = await pumpA8(tester, '/profile', harness: h);
    await tester.tap(find.text('Koyu'));
    await pumpFor(tester, const Duration(milliseconds: 300));
    expect(c.read(themeModeProvider), ThemeMode.dark);
    expect(h.prefs.getString(PrefKeys.themeMode), 'dark');
    await finish(tester);
  });

  testWidgets('biyometrik kilit: doğrulayınca açılır, başarısızsa kapalı kalır', (
    tester,
  ) async {
    setPhoneSize(tester, _tall);
    final h = await A8Harness.create();
    final c = await pumpA8(tester, '/profile', harness: h);
    // Test platformu Android: "Yüz tanıma ile kilitle" (iOS'ta "Face ID ile kilitle").
    final tile = find.text('Yüz tanıma ile kilitle');
    expect(tile, findsOneWidget);
    h.biometric.outcomes.add(BiometricOutcome.failed);
    await tester.tap(tile);
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(c.read(biometricLockProvider), isFalse);
    await tester.tap(tile);
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(c.read(biometricLockProvider), isTrue);
    expect(h.biometric.calls, 2);
    await tester.tap(tile);
    await pumpFor(tester, const Duration(milliseconds: 400));
    expect(
      c.read(biometricLockProvider),
      isFalse,
      reason: 'kapatmak doğrulama istemez',
    );
    expect(h.biometric.calls, 2);
    await finish(tester);
  });

  testWidgets('biyometri yoksa anahtar kapalı ve açıklamalı', (tester) async {
    setPhoneSize(tester, _tall);
    final h = await A8Harness.create();
    h.biometric.supportValue = const BiometricSupport(available: false);
    await pumpA8(tester, '/profile', harness: h);
    expect(
      find.text('Bu cihazda biyometrik doğrulama ya da ekran kilidi yok.'),
      findsOneWidget,
    );
    final sw = tester.widget<Switch>(find.byType(Switch).first);
    expect(sw.onChanged, isNull);
    await finish(tester);
  });

  testWidgets('yasal metinler uygulama içi tarayıcıda açılır', (tester) async {
    setPhoneSize(tester, _tall);
    final h = await A8Harness.create();
    await pumpA8(tester, '/profile', harness: h);
    for (final t in [
      'Gizlilik politikası',
      'KVKK aydınlatma metni',
      'Kullanım koşulları',
      'Yapay zekâ aydınlatma metni',
    ]) {
      await tapVisible(tester, find.text(t));
      await pumpFor(tester, const Duration(milliseconds: 200));
    }
    expect(h.links.urls, [
      'https://akaryakitnet.local/gizlilik',
      'https://akaryakitnet.local/kvkk',
      'https://akaryakitnet.local/kullanim-kosullari',
      'http://fake.akaryakitnet.local/legal/ai',
    ]);
    expect(h.links.opened.every((o) => !o.external), isTrue);
    await finish(tester);
  });

  testWidgets('destek: telefon, WhatsApp, e-posta dış uygulamada', (
    tester,
  ) async {
    setPhoneSize(tester, _tall);
    final h = await A8Harness.create();
    await pumpA8(tester, '/profile', harness: h);
    await tapVisible(tester, find.text('Destek ile görüş'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text('WhatsApp ile yazın'));
    await pumpFor(tester, const Duration(milliseconds: 200));
    expect(h.links.opened.single.uri.toString(), 'https://wa.me/908500000000');
    expect(h.links.opened.single.external, isTrue);
    await finish(tester);
  });

  testWidgets('telefonla giriş: durum çipi ve A1 doğrulama sayfası', (
    tester,
  ) async {
    setPhoneSize(tester, _tall);
    await pumpA8(tester, '/profile');
    expect(find.text('Telefonla girişi etkinleştir'), findsOneWidget);
    expect(find.text('Kapalı'), findsOneWidget);
    await tester.tap(find.text('Telefonla girişi etkinleştir'));
    await pumpFor(tester, const Duration(milliseconds: 800));
    expect(find.text('Telefon doğrulama'), findsWidgets);
    await finish(tester);
  });

  testWidgets('gizlilik: asistan onayı geri alınır', (tester) async {
    setPhoneSize(tester, _tall);
    final h = await A8Harness.create();
    final c = await pumpA8(
      tester,
      '/profile',
      harness: h,
      beforeOpen: (c) async {
        c.listen(assistantGateProvider, (_, _) {});
        await until(() => c.read(assistantGateProvider) is! GateChecking);
        await c.read(assistantGateProvider.notifier).accept();
      },
    );
    expect(find.textContaining('tarihinde onayladınız'), findsOneWidget);
    await tapVisible(tester, find.text('Onayı geri al'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text('Onayı geri al').last);
    await pumpFor(tester, const Duration(milliseconds: 800));
    expect(c.read(assistantGateProvider), isA<GateNeedsConsent>());
    expect(
      find.text('Asistanı ilk kullanımda aydınlatma metnini onaylarsınız.'),
      findsOneWidget,
    );
    await finish(tester);
  });

  // ------------------------------------------------------------------ Çıkış
  testWidgets('çıkış: bekleyen işlem yoksa kısa onay', (tester) async {
    setPhoneSize(tester, _tall);
    final h = await A8Harness.create();
    final c = await pumpA8(tester, '/profile', harness: h);
    await scrollTo(tester, find.text('Çıkış yap'));
    await tapVisible(tester, find.text('Çıkış yap'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Çıkış yapılsın mı?'), findsOneWidget);
    await tester.tap(find.text('Çıkış yap').last);
    await pumpFor(tester, const Duration(milliseconds: 800));
    expect(isSignedIn(c), isFalse);
    await finish(tester);
  });

  testWidgets('çıkış: bekleyen işlem → "Şimdi gönder" gönderir ve çıkar', (
    tester,
  ) async {
    setPhoneSize(tester, _tall);
    final h = await A8Harness.create();
    var sent = 0;
    final c = await pumpA8(
      tester,
      '/profile',
      harness: h,
      overrides: [
        outboxHandlersProvider.overrideWithValue({
          'test.op': (OutboxOp op, OutboxContext ctx) async {
            sent++;
            return <String, dynamic>{};
          },
        }),
      ],
      beforeOpen: (c) => h.outbox.insert(_op('u-musteri')),
    );
    await scrollTo(tester, find.text('Çıkış yap'));
    await tapVisible(tester, find.text('Çıkış yap'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Gönderilmeyi bekleyen 1 işlem var'), findsOneWidget);
    expect(find.text('Yine de çık (işlemler silinir)'), findsOneWidget);
    await tester.tap(find.text('Şimdi gönder'));
    await pumpFor(tester, const Duration(milliseconds: 1200));
    expect(sent, 1);
    expect(isSignedIn(c), isFalse);
    final ops = await tester.runAsync(() => h.outbox.list('u-musteri'));
    expect(ops!.single.status, OutboxStatus.done);
    await finish(tester);
  });

  testWidgets(
    'çıkış: gönderilemiyorsa açıklar; "Yine de çık" işlemleri siler',
    (tester) async {
      setPhoneSize(tester, _tall);
      final h = await A8Harness.create();
      final c = await pumpA8(
        tester,
        '/profile',
        harness: h,
        beforeOpen: (c) =>
            h.outbox.insert(_op('u-musteri', type: 'unknown.op')),
      );
      await scrollTo(tester, find.text('Çıkış yap'));
      await tapVisible(tester, find.text('Çıkış yap'));
      await pumpFor(tester, const Duration(milliseconds: 500));
      await tester.tap(find.text('Şimdi gönder'));
      await pumpFor(tester, const Duration(milliseconds: 1200));
      expect(isSignedIn(c), isTrue);
      expect(find.textContaining('1 işlem gönderilemedi'), findsOneWidget);
      await tester.tap(find.text('Yine de çık (işlemler silinir)'));
      await pumpFor(tester, const Duration(milliseconds: 1000));
      expect(isSignedIn(c), isFalse);
      final ops = await tester.runAsync(() => h.outbox.list('u-musteri'));
      expect(ops, isEmpty);
      await finish(tester);
    },
  );

  testWidgets('çıkış: "Vazgeç" oturumu ve işlemleri korur', (tester) async {
    setPhoneSize(tester, _tall);
    final h = await A8Harness.create();
    final c = await pumpA8(
      tester,
      '/profile',
      harness: h,
      beforeOpen: (c) => h.outbox.insert(_op('u-musteri', type: 'unknown.op')),
    );
    await scrollTo(tester, find.text('Çıkış yap'));
    await tapVisible(tester, find.text('Çıkış yap'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text('Vazgeç'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(isSignedIn(c), isTrue);
    final ops = await tester.runAsync(() => h.outbox.list('u-musteri'));
    expect(ops, hasLength(1));
    await finish(tester);
  });

  // ------------------------------------------------------------------ Oturumlar
  testWidgets(
    'oturumlar: "Bu cihaz", diğer cihazı kapatma, tüm cihazlardan çık',
    (tester) async {
      setPhoneSize(tester, _tall);
      final h = await A8Harness.create();
      final c = await pumpA8(tester, '/profile/sessions', harness: h);
      expect(find.text('Bu cihaz'), findsOneWidget);
      expect(find.text('Samsung Galaxy Tab S9'), findsOneWidget);
      await tester.tap(find.text('Oturumu kapat'));
      await pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.text('Bu cihazdaki oturum kapatılsın mı?'), findsOneWidget);
      await tester.tap(find.text('Oturumu kapat').last);
      await pumpFor(tester, const Duration(milliseconds: 800));
      expect(find.text('Samsung Galaxy Tab S9'), findsNothing);
      expect(
        h.server.auth.sessions['musteri']!['fake-tablet-musteri']!.revoked,
        isTrue,
      );
      expect(find.text('Hesabınız yalnızca bu cihazda açık.'), findsOneWidget);
      await tester.tap(find.text('Tüm cihazlardan çık'));
      await pumpFor(tester, const Duration(milliseconds: 500));
      expect(find.text('Tüm cihazlardan çıkılsın mı?'), findsOneWidget);
      await tester.tap(find.text('Tüm cihazlardan çık').last);
      await pumpFor(tester, const Duration(milliseconds: 800));
      expect(isSignedIn(c), isFalse);
      expect(
        h.server.auth.sessions['musteri']!.values.every((d) => d.revoked),
        isTrue,
      );
      await finish(tester);
    },
  );

  // ------------------------------------------------------------------ Şifre
  testWidgets('şifre değiştir: kurallar, hatalı mevcut şifre, başarı → çıkış', (
    tester,
  ) async {
    setPhoneSize(tester, _tall);
    final h = await A8Harness.create();
    final c = await pumpA8(tester, '/profile/password', harness: h);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'yanlis');
    await tester.enterText(fields.at(1), 'Yeni2026');
    await tester.enterText(fields.at(2), 'Yeni2026');
    await tester.pump();
    expect(
      find.byIcon(PhosphorIconsFill.checkCircle),
      findsNWidgets(4),
      reason: 'dört kural sağlandı',
    );
    await tester.tap(find.text('Şifreyi değiştir'));
    await pumpFor(tester, const Duration(milliseconds: 800));
    expect(find.text('Mevcut şifre hatalı.'), findsOneWidget);
    expect(isSignedIn(c), isTrue);
    await tester.enterText(fields.at(0), 'demo');
    await tester.tap(find.text('Şifreyi değiştir'));
    await pumpFor(tester, const Duration(milliseconds: 1000));
    expect(h.profile.passwordChanges, 1);
    expect(isSignedIn(c), isFalse);
    expect(
      signOutMessage(c),
      'Güvenlik bilgileriniz değişti; yeniden giriş yapın.',
    );
    await finish(tester);
  });

  testWidgets('şifre değiştir: kural ve eşleşme hataları (istek gitmez)', (
    tester,
  ) async {
    setPhoneSize(tester, _tall);
    final h = await A8Harness.create();
    await pumpA8(tester, '/profile/password', harness: h);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'demo');
    await tester.enterText(fields.at(1), 'kisa');
    await tester.enterText(fields.at(2), 'baska');
    await tester.tap(find.text('Şifreyi değiştir'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Şifre kurallarını sağlayın.'), findsOneWidget);
    expect(find.text('Şifreler aynı değil.'), findsOneWidget);
    expect(h.profile.passwordChanges, 0);
    await finish(tester);
  });

  // ------------------------------------------------------------------ Profil bilgileri
  testWidgets('profil bilgileri: ad değişir, oturum açık kalır', (
    tester,
  ) async {
    setPhoneSize(tester, _tall);
    final h = await A8Harness.create();
    final c = await pumpA8(tester, '/profile/edit', harness: h);
    expect(find.text('Selin Aydın'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Selin Aydın Kaya');
    await tester.pump();
    expect(find.text('Mevcut şifre *'), findsNothing);
    await tester.tap(find.text('Kaydet'));
    await pumpFor(tester, const Duration(milliseconds: 800));
    expect(h.profile.profileUpdates, 1);
    expect(isSignedIn(c), isTrue);
    await finish(tester);
  });

  testWidgets(
    'profil bilgileri: telefon değişince mevcut şifre; başarı → çıkış',
    (tester) async {
      setPhoneSize(tester, _tall);
      final h = await A8Harness.create();
      final c = await pumpA8(tester, '/profile/edit', harness: h);
      await tester.enterText(find.byType(TextField).at(1), '0533 444 55 66');
      await pumpFor(tester, const Duration(milliseconds: 400));
      expect(find.text('Mevcut şifre *'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(2), 'yanlis');
      await tester.tap(find.text('Kaydet'));
      await pumpFor(tester, const Duration(milliseconds: 800));
      expect(
        find.text(
          'Telefon numarasını değiştirmek için mevcut şifrenizi doğru girin.',
        ),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField).at(2), 'demo');
      await tester.tap(find.text('Kaydet'));
      await pumpFor(tester, const Duration(milliseconds: 1000));
      expect(isSignedIn(c), isFalse);
      expect(
        signOutMessage(c),
        'Güvenlik bilgileriniz değişti; yeniden giriş yapın.',
      );
      await finish(tester);
    },
  );

  // ------------------------------------------------------------------ Hesabımı sil
  testWidgets('hesabımı sil: şifre ve onay zorunlu', (tester) async {
    setPhoneSize(tester, _tall);
    final h = await A8Harness.create();
    await pumpA8(
      tester,
      '/profile/delete-account',
      harness: h,
      persona: 'talep',
    );
    await tester.tap(find.text('Hesabımı sil').last);
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Şifrenizi girin.'), findsOneWidget);
    expect(find.text('Devam etmek için onaylayın.'), findsOneWidget);
    expect(h.profile.deletionRequests, isEmpty);
    await finish(tester);
  });

  testWidgets('hesabımı sil: son şirket yöneticisi iş kuralı mesajı', (
    tester,
  ) async {
    setPhoneSize(tester, _tall);
    final h = await A8Harness.create();
    final c = await pumpA8(tester, '/profile/delete-account', harness: h);
    await tester.enterText(find.byType(TextField).last, 'demo');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Hesabımı sil').last);
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text('Hesabımı sil').last);
    await pumpFor(tester, const Duration(milliseconds: 800));
    expect(find.textContaining('tek yöneticisi sizsiniz'), findsOneWidget);
    expect(isSignedIn(c), isTrue);
    await finish(tester);
  });

  testWidgets('hesabımı sil: hatalı şifre → alan hatası', (tester) async {
    setPhoneSize(tester, _tall);
    final h = await A8Harness.create();
    await pumpA8(
      tester,
      '/profile/delete-account',
      harness: h,
      persona: 'talep',
    );
    await tester.enterText(find.byType(TextField).last, 'yanlis');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Hesabımı sil').last);
    await pumpFor(tester, const Duration(milliseconds: 500));
    await tester.tap(find.text('Hesabımı sil').last);
    await pumpFor(tester, const Duration(milliseconds: 800));
    expect(find.text('Şifre hatalı.'), findsOneWidget);
    expect(h.profile.deletionRequests, isEmpty);
    await finish(tester);
  });

  testWidgets('hesabımı sil: neden + şifre → "Talebiniz alındı" → çıkış', (
    tester,
  ) async {
    setPhoneSize(tester, _tall);
    final h = await A8Harness.create();
    final c = await pumpA8(
      tester,
      '/profile/delete-account',
      harness: h,
      persona: 'talep',
      beforeOpen: (c) => h.outbox.insert(_op('u-talep', type: 'unknown.op')),
    );
    expect(
      find.text(
        'Gönderilmeyi bekleyen 1 işleminiz var; hesap kapanınca gönderilmez.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Şirketten ayrıldım'));
    await tester.enterText(find.byType(TextField).last, 'demo');
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Hesabımı sil').last);
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Hesabınız kapatılsın mı?'), findsOneWidget);
    await tester.tap(find.text('Hesabımı sil').last);
    await pumpFor(tester, const Duration(milliseconds: 1200));
    expect(h.profile.deletionRequests['talep'], 'Şirketten ayrıldım');
    expect(find.text('Talebiniz alındı'), findsOneWidget);
    expect(find.textContaining('SIL-'), findsOneWidget);
    expect(isSignedIn(c), isFalse);
    expect(signOutMessage(c), 'Hesabınız kapatıldı.');
    final ops = await tester.runAsync(() => h.outbox.list('u-talep'));
    expect(ops, isEmpty);
    await tester.tap(find.text('Tamam'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    expect(find.text('Talebiniz alındı'), findsNothing);
    await finish(tester);
  });

  test('modeller: silme sonucu (202) ve AccountOperationResult (400)', () {
    final r = AccountDeletionResult.fromJson({
      'requestId': 'SIL-4100000001',
      'scheduledFor': '2026-11-04T07:00:00+00:00',
      'message': 'Hesabınız kapatıldı.',
    });
    expect(r.requestId, 'SIL-4100000001');
    expect(r.scheduledFor, DateTime.utc(2026, 11, 4, 7));
    final op = AccountOperationResult.fromJson({
      'succeeded': false,
      'errors': ['Mevcut şifre hatalı.'],
      'invalidToken': false,
    });
    expect(op.succeeded, isFalse);
    expect(op.errors.single, 'Mevcut şifre hatalı.');
    expect(AccountOperationResult.matches({'title': 'x'}), isFalse);
  });
}

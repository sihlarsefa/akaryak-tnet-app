// Güncelleme ekranı ve sunucu durumları (spec A.4 A1): "Güncelleme gerekli", "Yeni sürüm hazır",
// "Sunucu güncel değil" (app/config 404 ya da sözleşme farkı), "Bakımdayız"; giriş ekranı bu durumlarda
// formu kapatır, "Tekrar dene" ile döner. Zorunlu güncelleme yönlendirmesi: auth_flow_test.dart.
import 'package:akaryakitnet/core/env/app_config_controller.dart';
import 'package:akaryakitnet/core/models/app_config.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'auth_test_support.dart';

class _FixedConfig extends AppConfigController {
  _FixedConfig(this.config);
  final AppConfig config;

  @override
  AppConfig build() => config;

  @override
  Future<void> load({Duration timeout = Duration.zero}) async {}
}

void main() {
  const store = 'https://store.test/akaryakitnet';

  a11yMatrix('güncelleme gerekli', (tester, scale, b) async {
    await pumpAuthRoute(
      tester,
      '/update?reason=forced',
      textScale: scale,
      brightness: b,
      overrides: [
        appConfigProvider.overrideWith(
          () => _FixedConfig(const AppConfig(minBuild: 5, storeUrl: store)),
        ),
      ],
    );
    expect(find.text('Güncelleme gerekli'), findsOneWidget);
    expect(find.text('Mağazada aç'), findsOneWidget);
    expect(find.text('Tekrar kontrol et'), findsOneWidget);
    expect(find.text('Yüklü sürüm: 1.0.0 (1)'), findsOneWidget);
  });

  a11yMatrix('yeni sürüm hazır (isteğe bağlı)', (tester, scale, b) async {
    await pumpAuthRoute(
      tester,
      '/update?reason=optional',
      textScale: scale,
      brightness: b,
    );
    expect(find.text('Yeni sürüm hazır'), findsOneWidget);
    expect(find.text('Güncelle'), findsOneWidget);
    expect(find.text('Daha sonra'), findsOneWidget);
  });

  a11yMatrix('sunucu güncel değil', (tester, scale, b) async {
    await pumpAuthRoute(
      tester,
      '/update?reason=server',
      textScale: scale,
      brightness: b,
    );
    expect(find.text('Sunucu güncel değil'), findsOneWidget);
    expect(find.text('Tekrar dene'), findsOneWidget);
    expect(find.text('Destek hattını arayın'), findsOneWidget);
  });

  a11yMatrix('bakımdayız', (tester, scale, b) async {
    final h = await AuthHarness.create();
    h.controls
      ..maintenance = true
      ..maintenanceMessage = 'Gece bakımı 02:00–03:00 arasında sürecek.';
    await pumpAuthRoute(
      tester,
      '/update?reason=maintenance',
      harness: h,
      textScale: scale,
      brightness: b,
    );
    expect(find.text('Bakımdayız'), findsOneWidget);
    expect(
      find.text('Gece bakımı 02:00–03:00 arasında sürecek.'),
      findsOneWidget,
    );
  });

  testWidgets('varyant verilmezse durumdan: zorunlu güncelleme', (
    tester,
  ) async {
    setPhoneSize(tester);
    await pumpAuthRoute(
      tester,
      '/update',
      overrides: [
        appConfigProvider.overrideWith(
          () => _FixedConfig(const AppConfig(minBuild: 5)),
        ),
      ],
    );
    expect(find.text('Güncelleme gerekli'), findsOneWidget);
    // Mağaza adresi yoksa (iOS) yönlendirme metni.
    expect(find.text('Mağazada aç'), findsNothing);
    expect(
      find.text(
        'AkaryakıtNet\'i App Store ya da Google Play üzerinden güncelleyin.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('mağaza dış uygulamada açılır', (tester) async {
    setPhoneSize(tester);
    final links = LinkLog();
    await pumpAuthRoute(
      tester,
      '/update?reason=forced',
      overrides: [
        ...clockAndLinks(links: links),
        appConfigProvider.overrideWith(
          () => _FixedConfig(const AppConfig(minBuild: 5, storeUrl: store)),
        ),
      ],
    );
    await tester.tap(find.text('Mağazada aç'));
    await tester.pump();
    expect(links.uris.single.toString(), store);
    expect(links.opened.single.external, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'app/config 404: giriş yerine "Sunucu güncel değil"; düzelince form',
    (tester) async {
      setPhoneSize(tester);
      final h = await AuthHarness.create();
      h.controls.configMissing = true;
      await pumpAuthRoute(tester, '/login', harness: h);
      expect(find.text('Sunucu güncel değil'), findsOneWidget);
      expect(find.text('Giriş yap'), findsNothing);

      h.controls.configMissing = false;
      await tester.tap(find.text('Tekrar dene'));
      await pumpFor(tester, const Duration(seconds: 1));
      expect(find.text('Sunucu güncel değil'), findsNothing);
      expect(find.text('Giriş yap'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('sözleşme sürümü farklı: "Sunucu güncel değil"', (tester) async {
    setPhoneSize(tester);
    final h = await AuthHarness.create();
    h.controls.contractVersion = 'mobile-v2';
    await pumpAuthRoute(tester, '/login', harness: h);
    expect(find.text('Sunucu güncel değil'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('bakım: giriş ekranında "Bakımdayız" ve sunucunun metni', (
    tester,
  ) async {
    setPhoneSize(tester);
    final h = await AuthHarness.create();
    h.controls
      ..maintenance = true
      ..maintenanceMessage = 'Kısa bir bakım yapıyoruz.';
    await pumpAuthRoute(tester, '/login', harness: h);
    expect(find.text('Bakımdayız'), findsOneWidget);
    expect(find.text('Kısa bir bakım yapıyoruz.'), findsOneWidget);
    expect(find.text('Giriş yap'), findsNothing);

    h.controls.maintenance = false;
    await tester.tap(find.text('Tekrar dene'));
    await pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Giriş yap'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('isteğe bağlı güncelleme: "Daha sonra" bu sürümü erteler', (
    tester,
  ) async {
    setPhoneSize(tester);
    final h = await AuthHarness.create();
    await pumpAuthRoute(
      tester,
      '/update?reason=optional',
      harness: h,
      overrides: [
        appConfigProvider.overrideWith(
          () => _FixedConfig(const AppConfig(latestBuild: 7, storeUrl: store)),
        ),
      ],
    );
    await tester.tap(find.text('Daha sonra'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(h.prefs.getInt(PrefKeys.updateSnoozedBuild), 7);
    expect(find.text('ANA SAYFA'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

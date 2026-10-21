// Aşama 0 kapısı (spec D.1): sahte kipte uygulama açılır, her persona girişten sonra kendi kabuğuna
// (alt menü + ana sayfa) ulaşır. Ağ yok; sahte sunucu gecikmesiz.
import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/app/shell/platform_home.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/bayi/api.dart';
import 'package:akaryakitnet/features/customer_home/api.dart';
import 'package:akaryakitnet/features/driver/api.dart';
import 'package:akaryakitnet/features/field/api.dart';
import 'package:akaryakitnet/features/notifications/presentation/notifications_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/test_app.dart';

Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

const _homes = <String, Type>{
  'musteri': CustomerHome,
  'talep': CustomerHome,
  'onay': CustomerHome,
  'sahip': BayiHome,
  'mudur': BayiHome,
  'finans': BayiHome,
  'muhasebe': BayiHome,
  'satis': BayiHome,
  'saha': FieldHome,
  'siparis': BayiHome,
  'sevkiyat': BayiHome,
  'sofor': DriverHome,
  'depo': BayiHome,
  'izleyici': BayiHome,
  'finansuzman': BayiHome,
  'ozelrol': BayiHome,
  'merkez': PlatformHome,
};

Future<ProviderContainer> _launch(
  WidgetTester tester, {
  Map<String, Object> prefs = const {'akn.onboardingDone': true},
}) async {
  final h = await TestHarness.create(prefs: prefs);
  await tester.pumpWidget(
    ProviderScope(overrides: h.overrides, child: const AknApp()),
  );
  await _pumpFor(tester, const Duration(seconds: 2));
  return ProviderScope.containerOf(tester.element(find.byType(AknApp)));
}

void main() {
  testWidgets('ilk açılış: açılış ekranı → tanıtım → giriş', (tester) async {
    await _launch(tester, prefs: const {});
    // Tanıtımın her sayfasında "Atla" var (A1); ilk sayfada "Devam".
    expect(find.text('Atla'), findsOneWidget);
    await tester.tap(find.text('Atla'));
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Giriş yap'), findsOneWidget);
    // Sahte kipte demo hesapları ilk ekranda, üst alanın altında (sahip kararı 2026-10-21); girişte
    // alt bilgi (ve eski "Demo" bağlantısı) yok.
    expect(find.text('Demo hesaplarıyla girin').hitTestable(), findsOneWidget);
    expect(find.text('Selin Aydın'), findsOneWidget);
    expect(find.text('Demo'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('demo hesabına dokunmak giriş yapar ve kabuğu açar', (
    tester,
  ) async {
    final container = await _launch(tester);
    expect(find.text('Giriş yap'), findsOneWidget);
    // Demo kartı giriş ekranında: tek dokunuş giriş yapar.
    await tester.ensureVisible(find.text('Selin Aydın'));
    await tester.pump();
    await tester.tap(find.text('Selin Aydın'));
    for (
      var i = 0;
      i < 40 &&
          container.read(sessionControllerProvider) is! SessionAuthenticated;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _pumpFor(tester, const Duration(seconds: 2));
    expect(find.byType(AnimatedBottomBar), findsOneWidget);
    expect(find.byType(CustomerHome), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  Future<void> login(
    WidgetTester tester,
    ProviderContainer c,
    String key,
  ) async {
    await tester.runAsync(() async {
      final session = c.read(sessionControllerProvider.notifier);
      final outcome = await session.loginWithPassword(key, 'demo');
      if (outcome is LoginNeedsCode) {
        await session.verifyCode(outcome.challenge.challengeId, '123456');
      }
    });
    await _pumpFor(tester, const Duration(seconds: 2));
  }

  testWidgets('orta eylem tam ekran açılır, geri ana sayfaya döner', (
    tester,
  ) async {
    final c = await _launch(tester);
    await login(tester, c, 'musteri');
    final bar = find.byType(AnimatedBottomBar);
    // Ortadaki yükseltilmiş düğme (etiket yalnızca yazı).
    await tester.tap(
      find.descendant(of: bar, matching: find.byIcon(Icons.add_rounded)),
    );
    await _pumpFor(tester, const Duration(seconds: 1));
    // Sipariş sihirbazı (A2) tam ekran açılır: ilk adım "Ürün ve litre".
    expect(find.text('Ürün ve litre'), findsOneWidget);
    expect(find.byType(AnimatedBottomBar), findsNothing, reason: 'tam ekran');
    await tester.tap(find.bySemanticsLabel('Kapat'));
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(CustomerHome), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('zil: sekmedeki Bildirimler açılır (şoför)', (tester) async {
    final c = await _launch(tester);
    await login(tester, c, 'sofor');
    expect(find.byType(DriverHome), findsOneWidget);
    // Şoför ana sayfasında zil yok (tahta ekran 6); Bildirimler alt menüde sekmedir.
    await tester.tap(
      find.descendant(
        of: find.byType(AnimatedBottomBar),
        matching: find.text('Bildirim'),
      ),
    );
    await _pumpFor(tester, const Duration(seconds: 1));
    // Gelen kutusu (A8): şoföre atanan teslimat bildirimi.
    expect(find.byType(NotificationsPage), findsOneWidget);
    expect(find.text('Yeni teslimat atandı'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('çıkış ve başka personayla giriş: kabuk yeniden kurulur', (
    tester,
  ) async {
    final c = await _launch(tester);
    await login(tester, c, 'sahip');
    expect(find.byType(BayiHome), findsOneWidget);
    await tester.runAsync(
      () => c.read(sessionControllerProvider.notifier).signOut(),
    );
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Giriş yap'), findsOneWidget);
    await login(tester, c, 'sofor');
    expect(find.byType(DriverHome), findsOneWidget);
    final bar = find.byType(AnimatedBottomBar);
    expect(
      find.descendant(of: bar, matching: find.text('Teslimat')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bar, matching: find.text('Teklifler')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final persona in fakePersonas) {
    testWidgets('${persona.key}: kendi kabuğuna ulaşır', (tester) async {
      final container = await _launch(tester);
      expect(find.text('Giriş yap'), findsOneWidget);

      await tester.runAsync(() async {
        final session = container.read(sessionControllerProvider.notifier);
        final outcome = await session.loginWithPassword(persona.key, 'demo');
        if (outcome is LoginNeedsCode) {
          await session.verifyCode(outcome.challenge.challengeId, '123456');
        }
      });
      await _pumpFor(tester, const Duration(seconds: 2));

      final layout = container.read(navLayoutProvider);
      expect(layout.isEmpty, isFalse);
      final bar = find.byType(AnimatedBottomBar);
      expect(bar, findsOneWidget);
      for (final d in layout.bar) {
        expect(
          find.descendant(of: bar, matching: find.text(d.barLabel)),
          findsOneWidget,
          reason: d.barLabel,
        );
      }
      expect(
        find.descendant(of: bar, matching: find.text('Diğer')),
        layout.hasMore ? findsOneWidget : findsNothing,
      );
      final center = layout.center;
      if (center != null) {
        expect(
          find.descendant(of: bar, matching: find.text(center.label)),
          findsOneWidget,
        );
      }
      expect(
        find.byType(_homes[persona.key]!),
        findsOneWidget,
        reason: 'ana sayfa',
      );

      // Her sekme açılır (yer tutucu ekranlar dahil).
      for (var i = 1; i < layout.bar.length; i++) {
        await tester.tap(
          find.descendant(of: bar, matching: find.text(layout.bar[i].barLabel)),
        );
        await _pumpFor(tester, const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
      }
      if (layout.hasMore) {
        await tester.tap(
          find.descendant(of: bar, matching: find.text('Diğer')),
        );
        await _pumpFor(tester, const Duration(milliseconds: 800));
        for (final d in layout.more) {
          await tester.scrollUntilVisible(
            find.text(d.label).last,
            80,
            scrollable: find
                .descendant(
                  of: find.byType(BottomSheet),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(find.text(d.label), findsWidgets, reason: 'Diğer: ${d.label}');
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}

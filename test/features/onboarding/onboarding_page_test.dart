// Tanıtım (spec A.4 A1): 3 sahne (Sipariş → Teklif → Teslimat), her sayfada "Atla", "Sayfa 1/3"
// okunuşu, azaltılmış harekette ve ekran okuyucuda durağan son kare, ilk açılışta girişten önce.
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../auth/auth_test_support.dart';

Future<AuthHarness> _harness() => AuthHarness.create(prefs: const {});

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.text('Devam'));
  await pumpFor(tester, const Duration(milliseconds: 700));
}

void main() {
  a11yMatrix('tanıtım · sahne 1', (tester, scale, b) async {
    await pumpAuthRoute(
      tester,
      '/onboarding',
      harness: await _harness(),
      textScale: scale,
      brightness: b,
    );
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.text('Sipariş birkaç dokunuşla'), findsOneWidget);
    expect(find.text('Atla'), findsOneWidget);
  });

  a11yMatrix('tanıtım · sahne 3', (tester, scale, b) async {
    await pumpAuthRoute(
      tester,
      '/onboarding',
      harness: await _harness(),
      textScale: scale,
      brightness: b,
    );
    await _next(tester);
    await _next(tester);
    await pumpFor(tester, const Duration(seconds: 2));
    expect(find.text('Teslimat adım adım'), findsOneWidget);
    expect(find.text('Başlayalım'), findsOneWidget);
  });

  testWidgets('her sayfada "Atla"; okunuş Sayfa 1/3 → 2/3 → 3/3', (
    tester,
  ) async {
    setPhoneSize(tester);
    final semantics = tester.ensureSemantics();
    await pumpAuthRoute(tester, '/onboarding', harness: await _harness());
    expect(find.text('Atla'), findsOneWidget);
    expect(find.bySemanticsLabel('Sayfa 1/3'), findsOneWidget);
    expect(find.bySemanticsLabel('Tanıtımı atla'), findsOneWidget);
    expect(find.text('Devam'), findsOneWidget);

    await _next(tester);
    expect(find.text('Teklif ve onay tek ekranda'), findsOneWidget);
    expect(find.text('Atla'), findsOneWidget);
    expect(find.bySemanticsLabel('Sayfa 2/3'), findsOneWidget);

    await _next(tester);
    expect(find.text('Teslimat adım adım'), findsOneWidget);
    expect(find.text('Atla'), findsOneWidget);
    expect(find.bySemanticsLabel('Sayfa 3/3'), findsOneWidget);
    expect(find.text('Başlayalım'), findsOneWidget);
    expect(find.text('Devam'), findsNothing);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('"Atla" tanıtımı tamamlar (ilk sayfada)', (tester) async {
    setPhoneSize(tester);
    final h = await _harness();
    await pumpAuthRoute(tester, '/onboarding', harness: h);
    await tester.tap(find.text('Atla'));
    await tester.pump();
    expect(h.prefs.getBool(PrefKeys.onboardingDone), isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    '"Başlayalım" son sayfada tamamlar; kaydırma da sayfa değiştirir',
    (tester) async {
      setPhoneSize(tester);
      final h = await _harness();
      await pumpAuthRoute(tester, '/onboarding', harness: h);
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await pumpFor(tester, const Duration(milliseconds: 800));
      expect(find.text('Teklif ve onay tek ekranda'), findsOneWidget);
      await _next(tester);
      await tester.tap(find.text('Başlayalım'));
      await tester.pump();
      expect(h.prefs.getBool(PrefKeys.onboardingDone), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'sahne bir kez oynar: önce "Siparişi gönder", sonra "Siparişiniz bayiye gönderildi"',
    (tester) async {
      setPhoneSize(tester);
      await pumpAuthRoute(tester, '/onboarding', harness: await _harness());
      expect(find.text('Siparişi gönder'), findsOneWidget);
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.text('Siparişiniz bayiye gönderildi'), findsOneWidget);
      expect(find.text('Tahmini sipariş'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse, reason: 'döngü yok');
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final mode in ['azaltılmış hareket', 'ekran okuyucu']) {
    testWidgets('$mode: durağan son kare, sayfa geçişi anında', (tester) async {
      setPhoneSize(tester);
      await pumpAuthRoute(
        tester,
        '/onboarding',
        harness: await _harness(),
        reduceMotion: mode == 'azaltılmış hareket',
        accessibleNavigation: mode == 'ekran okuyucu',
      );
      await tester.pump();
      expect(
        find.text('Siparişiniz bayiye gönderildi'),
        findsOneWidget,
        reason: 'son kare',
      );
      expect(find.text('Tahmini sipariş'), findsOneWidget);
      await tester.tap(find.text('Devam'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Teklif ve onay tek ekranda'), findsOneWidget);
      expect(find.text('Teklif onaylandı'), findsOneWidget, reason: 'son kare');
      await tester.pumpWidget(const SizedBox());
    });
  }
}

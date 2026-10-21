// A8 ekranları gerçek uygulama kabuğunda (yönlendirici, alt menü, zil, "Daha" sayfası): bildirimler
// zilden ve sekmeden açılır, tercihler ve profil alt sayfaları alt menünün üstünde açılır, asistan tam
// ekran açılıp kapatılır. Ağ yok; sahte sunucu gecikmesiz.
import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/notifications/presentation/notification_settings_page.dart';
import 'package:akaryakitnet/features/notifications/presentation/notifications_page.dart';
import 'package:akaryakitnet/features/profile/presentation/sessions_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_app.dart';

Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

Future<ProviderContainer> _launch(WidgetTester tester, String persona) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  final h = await TestHarness.create(prefs: const {'akn.onboardingDone': true});
  await tester.pumpWidget(
    ProviderScope(overrides: h.overrides, child: const AknApp()),
  );
  await _pumpFor(tester, const Duration(seconds: 2));
  final c = ProviderScope.containerOf(tester.element(find.byType(AknApp)));
  await tester.runAsync(() async {
    final s = c.read(sessionControllerProvider.notifier);
    final outcome = await s.loginWithPassword(persona, 'demo');
    if (outcome is LoginNeedsCode) {
      await s.verifyCode(outcome.challenge.challengeId, '123456');
    }
  });
  await _pumpFor(tester, const Duration(seconds: 2));
  return c;
}

Finder _bar(String label) => find.descendant(
  of: find.byType(AnimatedBottomBar),
  matching: find.text(label),
);

void main() {
  testWidgets('şoför: zil gelen kutusunu açar, tercihler tam ekran', (
    tester,
  ) async {
    await _launch(tester, 'sofor');
    await tester.tap(find.byType(NotificationBell));
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(NotificationsPage), findsOneWidget);
    expect(find.text('Yeni teslimat atandı'), findsOneWidget);
    await tester.tap(find.byTooltip('Bildirim ayarları'));
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(NotificationSettingsPage), findsOneWidget);
    expect(find.byType(AnimatedBottomBar), findsNothing, reason: 'tam ekran');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('şoför: Profil sekmesi → Aktif oturumlar alt menünün üstünde', (
    tester,
  ) async {
    await _launch(tester, 'sofor');
    await tester.tap(_bar('Profil'));
    await _pumpFor(tester, const Duration(milliseconds: 800));
    expect(find.text('Ahmet Kurt'), findsOneWidget);
    await tester.tap(find.text('Aktif oturumlar'));
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(SessionsPage), findsOneWidget);
    expect(find.byType(AnimatedBottomBar), findsNothing);
    expect(find.text('Bu cihaz'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(AnimatedBottomBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('şoför: Asistan sekmesi önce aydınlatma metnini gösterir', (
    tester,
  ) async {
    await _launch(tester, 'sofor');
    await tester.tap(_bar('Asistan'));
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Kabul ediyorum'), findsOneWidget);
    expect(find.byTooltip('Kapat'), findsNothing, reason: 'sekme kökü');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('müşteri: Diğer → Asistan tam ekran açılır, kapat ile döner', (
    tester,
  ) async {
    await _launch(tester, 'musteri');
    await tester.tap(_bar('Diğer'));
    await _pumpFor(tester, const Duration(milliseconds: 800));
    await tester.tap(find.text('Asistan').last);
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(find.text('Kabul ediyorum'), findsOneWidget);
    expect(find.byType(AnimatedBottomBar), findsNothing, reason: 'tam ekran');
    await tester.tap(find.byTooltip('Kapat'));
    await _pumpFor(tester, const Duration(seconds: 1));
    expect(find.byType(AnimatedBottomBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('merkez: Bildirimler sekmesi ve bildirim derin bağlantısı', (
    tester,
  ) async {
    await _launch(tester, 'merkez');
    await tester.tap(_bar('Bildirim'));
    await _pumpFor(tester, const Duration(milliseconds: 800));
    expect(find.byType(NotificationsPage), findsOneWidget);
    expect(find.text('Hoş geldiniz'), findsOneWidget);
    // Rota /notifications: dokunmak sayfada bırakır.
    await tester.tap(find.text('Hoş geldiniz'));
    await _pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.byType(NotificationsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

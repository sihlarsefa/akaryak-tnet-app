// Test derlemesi (TestFlight: `AKN_ENV=test`, `API_MODE=live`): canlı sunucu bakımda ya da bu sürümle
// uyumsuzken giriş ekranı. Sahip kuralı: her TestFlight derlemesinde giriş ekranında demo hesapları
// vardır. Demo kartları uygulama içi sahte dünyaya gittiğinden canlı sunucunun durumuna bağlı değildir:
// canlı form durum notuyla yer değiştirir, kartlar kalır ve demo oturumu canlı API'ye hiç gitmez. Ayrıca
// önceki dünyada başlayan "Tekrar dene" yoklaması yeni dünyanın sunucu durumunun üstüne yazılmaz.
import 'dart:async';
import 'dart:convert';

import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/env/app_env.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/auth/application/server_gate_controller.dart';
import 'package:akaryakitnet/features/auth/data/server_gate.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/a11y.dart' show settleIo;
import '../../support/demo_live_harness.dart';
import 'auth_test_support.dart';

ResponseBody _json(int status, Object? body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json; charset=utf-8'],
  },
);

/// Canlı sunucunun `app/config` yanıtını [config] ile değiştirir (diğer yanıtlar aynı kalır).
void _liveConfig(DemoLiveHarness h, Map<String, Object?> config) {
  final base = h.live.fallback!;
  h.live.fallback = (o) =>
      o.uri.path.endsWith('/app/config') ? _json(200, config) : base(o);
}

/// Etiketi alanın üstünde duran metin alanı.
Finder _field(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(AknTextField)),
  matching: find.byType(TextField),
);

final _liveGate = find.byKey(const ValueKey('login.liveGate'));

Future<ProviderContainer> _launch(
  WidgetTester tester,
  DemoLiveHarness h,
) async {
  await tester.pumpWidget(
    ProviderScope(overrides: h.overrides, child: const AknApp()),
  );
  await pumpFor(tester, const Duration(seconds: 2));
  await settleIo(tester);
  return ProviderScope.containerOf(
    tester.element(find.byType(AknApp)),
    listen: false,
  );
}

void main() {
  setUp(() => AknMotion.ambient = false);

  testWidgets(
    'canlı sunucu bakımda: demo kartları kalır, canlı form yerine bakım notu; kart canlı API\'ye gitmez',
    (tester) async {
      setPhoneSize(tester, const Size(390, 844));
      final h = await DemoLiveHarness.create();
      _liveConfig(h, {
        ...liveConfig,
        'maintenance': {'active': true, 'message': 'Gece bakımı sürüyor.'},
      });
      final c = await _launch(tester, h);

      expect(find.text('Demo hesaplarıyla girin'), findsOneWidget);
      expect(find.text('Selin Aydın'), findsOneWidget);
      expect(_liveGate, findsOneWidget);
      expect(
        find.descendant(of: _liveGate, matching: find.text('Bakımdayız')),
        findsOneWidget,
      );
      expect(find.text('Gece bakımı sürüyor.'), findsOneWidget);
      // Canlı form yok (bakımdaki sunucuya giriş denenmez).
      expect(_field('Şifre'), findsNothing);
      expect(find.text('Giriş yap'), findsNothing);
      expect(c.read(appEnvProvider).isFake, isFalse);
      await tester.ensureVisible(_liveGate);
      await pumpFor(tester, const Duration(milliseconds: 400));
      await expectAccessible(tester);

      final before = h.live.requests.length;
      await tapVisible(tester, find.text('Selin Aydın'));
      await pumpUntil(tester, () => isSignedIn(c));
      await pumpFor(tester, const Duration(seconds: 2));
      await settleIo(tester);
      expect(isSignedIn(c), isTrue);
      expect(c.read(appEnvProvider).demoSession, isTrue);
      expect(find.byType(AnimatedBottomBar), findsOneWidget);
      expect(
        h.live.requests.length,
        before,
        reason: 'canlı API\'ye giden: ${h.livePaths.skip(before)}',
      );

      // Çıkış: canlı sunucu hâlâ bakımda; giriş ekranı yine kartlarla.
      await tester.runAsync(
        () => c.read(sessionControllerProvider.notifier).signOut(),
      );
      await pumpFor(tester, const Duration(seconds: 1));
      await settleIo(tester);
      expect(c.read(sessionControllerProvider), isA<SessionUnauthenticated>());
      expect(c.read(appEnvProvider).isFake, isFalse);
      expect(find.text('Demo hesaplarıyla girin'), findsOneWidget);
      expect(_liveGate, findsOneWidget);
      expect(h.liveRequestsWithTokens, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'canlı sunucu bu sürümle uyumsuz: demo kartları kalır, "Sunucu güncel değil" notu; "Tekrar dene" canlıyı yoklar',
    (tester) async {
      setPhoneSize(tester, const Size(390, 844));
      final h = await DemoLiveHarness.create();
      _liveConfig(h, {...liveConfig, 'contractVersion': 'mobile-v9'});
      await _launch(tester, h);

      expect(find.text('Demo hesaplarıyla girin'), findsOneWidget);
      expect(
        find.descendant(
          of: _liveGate,
          matching: find.text('Sunucu güncel değil'),
        ),
        findsOneWidget,
      );
      expect(_field('Şifre'), findsNothing);

      // Sunucu güncellendi: "Tekrar dene" canlı formu geri getirir.
      _liveConfig(h, liveConfig);
      await tapVisible(
        tester,
        find.descendant(of: _liveGate, matching: find.text('Tekrar dene')),
      );
      await settleIo(tester);
      await pumpFor(tester, const Duration(seconds: 1));
      expect(_liveGate, findsNothing);
      expect(_field('Şifre'), findsOneWidget);
      expect(find.text('Giriş yap'), findsOneWidget);
      expect(find.text('Demo hesaplarıyla girin'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'önceki dünyada başlayan "Tekrar dene" yanıtı demo oturumunun sunucu durumunu ezmez',
    () async {
      final h = await DemoLiveHarness.create();
      final c = h.container();
      addTearDown(c.dispose);
      final sub = c.listen(serverGateProvider, (_, _) {});
      addTearDown(sub.close);
      expect((await c.read(serverGateProvider.future)).blocks, isFalse);

      // Canlı sunucu bakıma girdi; "Tekrar dene" yoklaması yanıt beklerken demo kartına dokunulur.
      final release = Completer<void>();
      final base = h.live.fallback!;
      h.live.fallback = (o) async {
        if (!o.uri.path.endsWith('/app/config')) return base(o);
        await release.future;
        return _json(200, {
          ...liveConfig,
          'maintenance': {'active': true},
        });
      };
      final recheck = c.read(serverGateProvider.notifier).recheck();
      await pumpEventQueue();
      expect(c.read(demoSessionProvider.notifier).start(), isTrue);
      final demoGate = await c.read(serverGateProvider.future);
      expect(demoGate.kind, ServerGateKind.ok);

      release.complete();
      await recheck;
      await pumpEventQueue();
      expect(c.read(serverGateProvider).valueOrNull?.kind, ServerGateKind.ok);
    },
  );
}

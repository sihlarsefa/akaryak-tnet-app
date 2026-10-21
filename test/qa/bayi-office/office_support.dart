// QA "bayi-office" yardımcıları: gerçek uygulamayı (AknApp) tüm sahtelerle açar, personayla girer,
// rotaları gerçek yönlendiriciyle açar ve her adımda istisna / hata durumu / takılı yükleme toplar.
import 'dart:async';
import 'dart:io';

import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/auth/access_policy.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/env/app_config_controller.dart';
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/core/routing/route_access.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/a11y.dart';
import '../../support/test_app.dart';

/// Bu gözcünün personaları (bayi ofis rolleri).
const officePersonas = [
  'sahip',
  'mudur',
  'siparis',
  'finans',
  'finansuzman',
  'muhasebe',
  'satis',
  'izleyici',
  'ozelrol',
];

/// Açık uygulama + kapsayıcı + toplanan sorunlar.
class OfficeApp {
  OfficeApp._(this.tester, this.container, this.harness);

  final WidgetTester tester;
  final ProviderContainer container;
  final TestHarness harness;
  final List<String> problems = [];

  /// Yakalanan çerçeve hatalarının kaynağı (`lib/...:satır`), [check] sorun metnine ekler.
  final List<String> _sources = [];
  FlutterExceptionHandler? _previousOnError;

  void _hookErrors() {
    _previousOnError = FlutterError.onError;
    final prev = _previousOnError;
    FlutterError.onError = (d) {
      final m = RegExp(
        r'file://[^\s:]+/lib/([^\s]+?):(\d+):\d+',
      ).firstMatch(d.toString());
      if (m != null) _sources.add('lib/${m.group(1)}:${m.group(2)}');
      prev?.call(d);
    };
  }

  GoRouter get router => container.read(routerProvider);
  AccessPolicy get policy => container.read(accessPolicyProvider);

  String get location =>
      router.routerDelegate.currentConfiguration.uri.toString();

  bool allowed(String path) => RouteAccess.isAllowed(
    path,
    policy,
    container.read(appConfigProvider).features,
  );

  static Future<OfficeApp> start(
    WidgetTester tester,
    String persona, {
    Size size = const Size(360, 640),
    A11yVariant variant = const A11yVariant(1, Brightness.light),
  }) async {
    setA11yPhone(tester, size: size);
    setA11yPlatform(tester, variant);
    final h = await TestHarness.create(
      prefs: const {'akn.onboardingDone': true},
    );
    await tester.pumpWidget(
      ProviderScope(overrides: h.overrides, child: const AknApp()),
    );
    await pumpSteps(tester, const Duration(seconds: 2));
    final c = ProviderScope.containerOf(tester.element(find.byType(AknApp)));
    await tester.runAsync(() async {
      final s = c.read(sessionControllerProvider.notifier);
      final outcome = await s.loginWithPassword(persona, 'demo');
      if (outcome is LoginNeedsCode) {
        await s.verifyCode(outcome.challenge.challengeId, '123456');
      }
    });
    await pumpSteps(tester, const Duration(seconds: 2));
    await settleIo(tester);
    final app = OfficeApp._(tester, c, h).._hookErrors();
    if (c.read(sessionControllerProvider) is! SessionAuthenticated) {
      app.problems.add('$persona: oturum açılmadı');
    }
    app.check('$persona giriş sonrası');
    return app;
  }

  /// Gerçek + sahte zaman ilerletir (ağ yanıtları, animasyonlar).
  Future<void> settle({int rounds = 8}) async {
    await pumpSteps(tester, const Duration(milliseconds: 600));
    await settleIo(tester, rounds: rounds);
  }

  /// İstisna, hata durumu, "bölüm yüklenemedi", takılı yükleme denetimi.
  void check(String where, {bool spinners = true}) {
    final e = tester.takeException();
    if (e != null) {
      final text = e.toString().split('\n').take(6).join(' | ');
      final at = _sources.toSet().join(', ');
      problems.add('$where: İSTİSNA $text${at.isEmpty ? '' : ' @ $at'}');
    }
    if (find.byType(ErrorState).evaluate().isNotEmpty) {
      final texts = find
          .descendant(of: find.byType(ErrorState), matching: find.byType(Text))
          .evaluate()
          .map((el) => (el.widget as Text).data ?? '')
          .where((t) => t.isNotEmpty)
          .take(3)
          .join(' / ');
      problems.add('$where: HATA DURUMU ($texts)');
    }
    if (find.textContaining('Bu bölüm yüklenemedi').evaluate().isNotEmpty) {
      problems.add('$where: "Bu bölüm yüklenemedi"');
    }
    _sources.clear();
    if (spinners) {
      final skel =
          find.byType(SkeletonList).evaluate().length +
          find.byType(SkeletonCard).evaluate().length;
      if (skel > 0) problems.add('$where: iskelet hâlâ görünüyor ($skel)');
    }
  }

  /// Rotaya `go` ile gider; izin yoksa ilk sekmeye düşmeli.
  Future<void> go(String path, {String? label}) async {
    router.go(path);
    await settle();
    final where = '${label ?? path} [${policyName()}]';
    final isAllowed = allowed(path);
    final loc = Uri.parse(location).path;
    if (isAllowed && loc != Uri.parse(path).path) {
      problems.add('$where: izinli rota açılmadı, konum $loc');
    }
    if (!isAllowed && loc == Uri.parse(path).path) {
      problems.add('$where: izinsiz rota açıldı');
    }
    check(where);
  }

  /// Rotayı yığına ekler (detay sayfaları), denetler ve geri döner.
  Future<void> pushAndPop(String path, {String? label}) async {
    unawaited(router.push(path));
    await settle();
    check('${label ?? path} [${policyName()}]');
    if (router.canPop()) router.pop();
    await settle(rounds: 3);
  }

  String policyName() => policy.access?.userName ?? '?';

  /// Liste ucundan ilk satırın [key] kimliği (yetki yoksa null).
  Future<int?> firstId(
    String path,
    String key, {
    Map<String, dynamic>? query,
  }) async {
    int? id;
    await tester.runAsync(() async {
      try {
        id = await container
            .read(apiClientProvider)
            .get(
              path,
              query: query,
              parse: (j) {
                final items = JsonReader.of(j).list('items', (r) => r);
                return items.isEmpty ? null : items.first.intOrNull(key);
              },
            );
      } catch (_) {
        id = null;
      }
    });
    return id;
  }

  /// Uç doğrudan çağrılır: yanıt ya da hata metni.
  Future<Object?> rawGet(String path, {Map<String, dynamic>? query}) async {
    Object? out;
    await tester.runAsync(() async {
      try {
        out = await container
            .read(apiClientProvider)
            .get(path, query: query, parse: (j) => j);
      } catch (e) {
        out = e;
      }
    });
    return out;
  }

  Future<void> finish() async {
    AppToast.dismiss();
    await tester.pumpWidget(const SizedBox());
    FlutterError.onError = _previousOnError;
  }
}

/// QA çıktısı (isteğe bağlı): `--dart-define=QA_OUT=/tam/yol` verilirse sorunlar dosyaya da yazılır.
const _qaOut = String.fromEnvironment('QA_OUT');

/// Toplanan sorunları tek iddiada yazar (hepsi görünsün diye).
void expectNoProblems(OfficeApp app, [String? name]) {
  if (_qaOut.isNotEmpty) {
    final n = (name ?? 'test').replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    File('$_qaOut/$n.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        app.problems.isEmpty ? 'OK\n' : '${app.problems.join('\n')}\n',
      );
  }
  expect(app.problems, isEmpty, reason: app.problems.join('\n'));
}

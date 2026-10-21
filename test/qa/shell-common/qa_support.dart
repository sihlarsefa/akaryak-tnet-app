// QA "shell-common" yardımcıları: gerçek uygulamayı (AknApp, gerçek yönlendirici, tüm sahte uçlar)
// açar, gerçek arayüzden ya da oturum denetleyicisiyle giriş yapar, konumu okur, hata durumlarını ve
// yerleşim hatalarını toplar. Ağ yok.
import 'dart:io';

import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/a11y.dart';
import '../../support/test_app.dart';

export '../../support/a11y.dart';
export '../../support/test_app.dart';

/// Açık uygulama + ortam.
class QaApp {
  QaApp(this.harness, this.container);
  final TestHarness harness;
  final ProviderContainer container;

  /// En üstteki sayfanın konumu (`push` ile açılanlar dahil; `currentConfiguration.uri` push'ta
  /// değişmez).
  String get location => container.read(routerProvider).state.uri.toString();

  SessionState get session => container.read(sessionControllerProvider);
}

/// Uygulamayı 360×640 telefonda açar. [prefs] verilmezse tanıtım görülmüş sayılır.
Future<QaApp> launchQa(
  WidgetTester tester, {
  Map<String, Object> prefs = const {'akn.onboardingDone': true},
  FakeWorld? world,
  List<Override> overrides = const [],
  Size size = const Size(360, 640),
  void Function(TestHarness h)? configure,
}) async {
  setA11yPhone(tester, size: size);
  final h = await TestHarness.create(prefs: prefs, world: world);
  configure?.call(h);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...h.overrides, ...overrides],
      child: const AknApp(),
    ),
  );
  await pumpSteps(tester, const Duration(seconds: 2));
  final c = ProviderScope.containerOf(tester.element(find.byType(AknApp)));
  return QaApp(h, c);
}

/// Oturum denetleyicisiyle giriş (şifre `demo`, gerekirse kod `123456`).
Future<void> qaSignIn(WidgetTester tester, QaApp app, String persona) async {
  await tester.runAsync(() async {
    final s = app.container.read(sessionControllerProvider.notifier);
    final outcome = await s.loginWithPassword(persona, 'demo');
    if (outcome is LoginNeedsCode) {
      await s.verifyCode(outcome.challenge.challengeId, '123456');
    }
  });
  await pumpSteps(tester, const Duration(seconds: 2));
  await settleIo(tester);
}

/// Etiketi alanın üstünde duran metin alanı.
/// Zorunlu alanlarda etiket "Etiket *" biçiminde zengin metindir; ikisi de eşleşir.
Finder qaField(String label) => find.descendant(
  of: find.ancestor(
    of: find.textContaining(
      RegExp('^${RegExp.escape(label)}\\s*\\*?\$'),
      findRichText: true,
    ),
    matching: find.byType(AknTextField),
  ),
  matching: find.byType(TextField),
);

/// Görünür kılıp dokunur (önce klavye odağını bırakır).
Future<void> qaTap(WidgetTester tester, Finder finder) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.ensureVisible(finder);
  await pumpSteps(tester, const Duration(milliseconds: 300));
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump();
}

/// Ekranda hata durumu ya da "yüklenemedi" metni.
List<String> qaErrorTexts() {
  final out = <String>[];
  for (final e in find.byType(ErrorState).evaluate()) {
    final w = e.widget as ErrorState;
    out.add('ErrorState(${w.title ?? ''} ${w.message ?? ''})');
  }
  for (final e in find.textContaining('yüklenemedi').evaluate()) {
    final w = e.widget;
    if (w is Text) out.add('Text(${w.data ?? w.textSpan?.toPlainText()})');
  }
  return out;
}

/// Ekranda sonsuz dönen yükleme göstergesi var mı (iskelet ya da dönen gösterge).
bool qaHasSpinner() =>
    find.byType(CircularProgressIndicator).evaluate().isNotEmpty;

/// Tüm bekleyen istisnaları toplar (ilkini döndürür).
Object? qaTakeException(WidgetTester tester) => tester.takeException();

/// İsteğe bağlı günlük klasörü: `--dart-define=QA_LOG_DIR=/tam/yol` verilirse her testin sorunları
/// `<klasör>/<ad>.log` dosyasına yazılır (uzun çıktılar kesilmeden okunur).
const qaLogDir = String.fromEnvironment('QA_LOG_DIR');

/// Test boyunca Flutter hatalarını (taşma, istisna) toplar; bulunan sorunları biriktirir.
class QaProblems {
  QaProblems(this.name) {
    _original = FlutterError.onError;
    FlutterError.onError = (details) {
      final stack = details.stack
          ?.toString()
          .split('\n')
          .where((l) => l.contains('package:akaryakitnet/'))
          .take(4)
          .join(' | ');
      final ctx = details.context?.toDescription() ?? '';
      // Taşmalarda "The relevant error-causing widget was: Row …/lib/x.dart:12:3" satırı.
      final full = details.toString();
      final where = RegExp(
        r'akaryakitnet-mobile/(lib/[^\s:]+\.dart:\d+)',
      ).allMatches(full).map((m) => m.group(1)).toSet().take(3).join(', ');
      add(
        'FlutterError [$_where] ${details.exceptionAsString().split('\n').take(3).join(' ')}'
        '${ctx.isEmpty ? '' : ' ($ctx)'}${where.isEmpty ? '' : ' [$where]'}'
        '${stack == null || stack.isEmpty ? '' : ' @ $stack'}',
      );
    };
  }

  final String name;
  final List<String> items = [];
  FlutterExceptionHandler? _original;
  String _where = 'başlangıç';

  set where(String w) => _where = w;

  void add(String p) => items.add(p);

  /// Ekrandaki hata durumlarını ve bekleyen istisnayı ekler.
  void check(WidgetTester tester, String where) {
    _where = where;
    final e = tester.takeException();
    if (e != null) add('$where → istisna: $e');
    final errs = qaErrorTexts();
    if (errs.isNotEmpty) add('$where → hata durumu: $errs');
  }

  /// Hata yakalayıcıyı geri verir, günlüğü yazar ve sorun yoksa geçer.
  void finish() {
    FlutterError.onError = _original;
    if (qaLogDir.isNotEmpty) {
      final f = File(
        '$qaLogDir/${name.replaceAll(RegExp(r'[^\w.-]+'), '_')}.log',
      );
      f.createSync(recursive: true);
      f.writeAsStringSync(items.isEmpty ? 'OK\n' : '${items.join('\n')}\n');
    }
    expect(items, isEmpty, reason: items.join('\n'));
  }
}

/// Ekrandaki en büyük dikey kaydırılabilir alan.
Finder qaMainList(WidgetTester tester) {
  final all = find.byType(Scrollable);
  var best = all.first;
  var bestArea = -1.0;
  for (var i = 0; i < all.evaluate().length; i++) {
    final f = all.at(i);
    final s = tester.widget<Scrollable>(f);
    if (axisDirectionToAxis(s.axisDirection) != Axis.vertical) continue;
    final size = tester.getSize(f);
    if (size.width * size.height > bestArea) {
      bestArea = size.width * size.height;
      best = f;
    }
  }
  return best;
}

/// Tembel listede henüz çizilmemiş öğeye dikey kaydırır (ilk eşleşen görünene kadar).
Future<void> qaScrollTo(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: qaMainList(tester),
      maxScrolls: 60,
    );
  }
  await tester.ensureVisible(finder.first);
  await pumpSteps(tester, const Duration(milliseconds: 300));
}

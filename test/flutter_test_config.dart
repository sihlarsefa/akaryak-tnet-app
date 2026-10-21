import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'support/fonts.dart';

// Ekran görüntüsü çalışmaları (`--dart-define=AKN_SCREENS_DIR=…`) ya da `--dart-define=AKN_REAL_FONTS=true`
// ile her test dosyası gerçek yazı tiplerini (Mona Sans, Roboto, Material simgeleri) yükler; yoksa yazılar
// test yazı tipinin kareleriyle çizilir. Normal test çalışmasında hiçbir şey yüklenmez (ölçüler
// değişmez, süre uzamaz).
const _screensDir = String.fromEnvironment('AKN_SCREENS_DIR');
const _realFonts = bool.fromEnvironment('AKN_REAL_FONTS');

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (_screensDir.isNotEmpty || _realFonts) {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadRealFonts();
  }
  await testMain();
}

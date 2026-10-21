// Erişilebilirlik test yardımcıları (spec C.7, D.7): 360×640 telefon, yazı ölçeği 1,0 / 2,0, açık / koyu
// tema ve dört kılavuz (Android/iOS dokunma hedefi, etiketli hedef, metin kontrastı).
//
// ```dart
// for (final v in A11yVariant.all) {
//   testWidgets('ekran — $v', (tester) async {
//     setA11yPhone(tester);
//     await tester.pumpWidget(a11yApp(const MyPage(), v));
//     await tester.pumpAndSettle();
//     expectNoLayoutErrors(tester);
//     await expectA11yGuidelines(tester);
//   });
// }
// ```
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Spec C.7 test telefonu (dp).
const a11yPhone = Size(360, 640);

/// Yazı ölçeği + tema bileşimi.
@immutable
class A11yVariant {
  const A11yVariant(this.textScale, this.brightness);

  final double textScale;
  final Brightness brightness;

  bool get dark => brightness == Brightness.dark;

  /// 1,0 / 2,0 × açık / koyu.
  static const all = [
    A11yVariant(1, Brightness.light),
    A11yVariant(2, Brightness.light),
    A11yVariant(1, Brightness.dark),
    A11yVariant(2, Brightness.dark),
  ];

  /// En zor durum: 2,0 × koyu.
  static const largeDark = A11yVariant(2, Brightness.dark);

  @override
  String toString() =>
      '${textScale.toStringAsFixed(1)}× ${dark ? 'koyu' : 'açık'}';
}

/// Test görünümünü telefon boyutuna getirir (test sonunda geri alınır).
void setA11yPhone(WidgetTester tester, {Size size = a11yPhone}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

/// Platform yazı ölçeği ve parlaklığını ayarlar (tüm uygulama testleri: tema `system`'den gelir).
void setA11yPlatform(WidgetTester tester, A11yVariant v) {
  tester.platformDispatcher.textScaleFactorTestValue = v.textScale;
  tester.platformDispatcher.platformBrightnessTestValue = v.brightness;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
}

/// Tek ekranı uygulama temasıyla (Türkçe yerel, açık/koyu, yazı ölçeği) sarar.
Widget a11yApp(Widget home, A11yVariant v) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: AknTheme.light(),
  darkTheme: AknTheme.dark(),
  themeMode: v.dark ? ThemeMode.dark : ThemeMode.light,
  locale: const Locale('tr', 'TR'),
  supportedLocales: const [Locale('tr', 'TR')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(v.textScale)),
    child: child!,
  ),
  home: home,
);

/// Taşma ve diğer yerleşim hataları yok.
void expectNoLayoutErrors(WidgetTester tester) {
  final e = tester.takeException();
  expect(e, isNull, reason: 'yerleşim hatası: $e');
}

/// Dört kılavuz (spec C.7).
Future<void> expectA11yGuidelines(
  WidgetTester tester, {
  bool tapTargets = true,
  bool contrast = true,
}) async {
  final handle = tester.ensureSemantics();
  try {
    if (tapTargets) {
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    }
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    if (contrast) {
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    }
  } finally {
    handle.dispose();
  }
}

/// [total] süre boyunca 100 ms adımlarla ilerletir (sonsuz animasyonlu ekranlarda `pumpAndSettle`
/// yerine).
Future<void> pumpSteps(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

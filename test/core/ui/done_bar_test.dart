// iOS sayı klavyesinin üstündeki "Bitti" çubuğu (spec D.7): alan klavyeye kaydırılırken çubuğun da
// üstünde kalır; yazılan sayı çubuğun altında kalmaz.
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('iOS: odaktaki sayı alanı "Bitti" çubuğunun altında kalmaz', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final fieldKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: AknTheme.light(),
        home: AppScaffold(
          title: 'Form',
          showBell: false,
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (var i = 0; i < 7; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AknTextField(label: 'Alan $i'),
                ),
              KeyedSubtree(
                key: fieldKey,
                child: const LitersField(label: 'Litre'),
              ),
              const SizedBox(height: 400),
            ],
          ),
          actionBar: AknButton(label: 'İleri', expand: true, onPressed: () {}),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final editable = find.descendant(
      of: find.byKey(fieldKey),
      matching: find.byType(EditableText),
    );
    await tester.tap(editable);
    await tester.pump(const Duration(milliseconds: 100));
    // Klavye açılır (336 dp).
    tester.view.viewInsets = const FakeViewPadding(bottom: 336);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(editable, '12500');
    await tester.pump(const Duration(milliseconds: 600));

    final bitti = find.text(KeyboardDoneAccessory.label);
    expect(bitti, findsOneWidget);
    // Çubuğun kendisi (tam genişlik; içindeki düğmenin Material'ı değil).
    final bar = find
        .ancestor(of: bitti, matching: find.byType(Material))
        .evaluate()
        .map((e) => tester.getRect(find.byWidget(e.widget)))
        .firstWhere((r) => r.width == 390);
    final text = tester.getRect(editable);
    expect(bar.top, 844 - 336 - KeyboardDoneAccessory.barHeight);
    expect(
      text.bottom,
      lessThanOrEqualTo(bar.top),
      reason: 'yazılan sayı ($text) çubuğun ($bar) üstünde',
    );
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android: çubuk yok, kaydırma payı varsayılan', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AknTheme.light(),
        home: const Scaffold(
          body: AknTextField(
            label: 'Litre',
            keyboardType: TextInputType.number,
          ),
        ),
      ),
    );
    await tester.tap(find.byType(EditableText));
    await tester.pump();
    expect(find.text(KeyboardDoneAccessory.label), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.scrollPadding, const EdgeInsets.all(20));
  });
}

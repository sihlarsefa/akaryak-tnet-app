// Şablonlarım (spec A.4): en son kullanılan önce, "Kullan" sihirbazı şablonla açar, silme onay
// sayfasıyla (liste hemen güncellenir, sunucudan silinir), boş durum, C.7 erişilebilirlik.
import 'package:akaryakitnet/features/customer_orders/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/a2_support.dart';

void main() {
  late A2Env env;

  setUp(() async {
    env = await A2Env.create();
  });

  Future<ProviderContainer> open(
    WidgetTester tester, {
    double textScale = 1,
    Brightness brightness = Brightness.light,
    Finder? waitFor,
  }) async {
    final c = (await tester.runAsync(() => env.signedIn('musteri')))!;
    addTearDown(c.dispose);
    await pumpA2(
      tester,
      c,
      initialLocation: templatesRoute,
      textScale: textScale,
      brightness: brightness,
    );
    await pumpUntil(tester, waitFor ?? find.text('Haftalık motorin – Pendik'));
    await pumpReal(tester);
    return c;
  }

  testWidgets('liste en son kullanılan önce; "Kullan" sihirbazı şablonla açar', (
    tester,
  ) async {
    await open(tester);
    final a = tester.getTopLeft(find.text('Haftalık motorin – Pendik')).dy;
    final b = tester.getTopLeft(find.text('Şantiye ikmali (2 nokta)')).dy;
    expect(a, lessThan(b));

    final use = find.bySemanticsLabel(
      'Şantiye ikmali (2 nokta) şablonuyla sipariş ver',
    );
    await tester.ensureVisible(use);
    await tester.pump();
    await tester.tap(use);
    await pumpUntil(tester, find.textContaining('şablonu yüklendi'));
    expect(
      find.text(
        '“Şantiye ikmali (2 nokta)” şablonu yüklendi; litreleri kontrol edin.',
      ),
      findsOneWidget,
    );
    expect(find.text('Satır 2'), findsOneWidget);
    await tearDownUi(tester);
  });

  testWidgets('sil: onay sayfası → listeden kalkar ve sunucudan silinir', (
    tester,
  ) async {
    await open(tester);
    final delete = find.bySemanticsLabel(
      'Haftalık motorin – Pendik şablonunu sil',
    );
    await tester.tap(delete);
    await pumpUntil(tester, find.text('Şablon silinsin mi?'));
    expect(
      find.textContaining('Verilmiş siparişler etkilenmez'),
      findsOneWidget,
    );
    await tester.tap(find.text('Sil'));
    await pumpUntil(tester, find.text('Şablon silindi.'));
    expect(find.text('Haftalık motorin – Pendik'), findsNothing);
    expect(
      A2Fake.templatesOf(env.world, 101).map((t) => t['id']),
      isNot(contains(701)),
    );
    await tearDownUi(tester);
  });

  testWidgets('şablon yoksa açıklayıcı boş durum ve "Sipariş ver"', (
    tester,
  ) async {
    A2Fake.templates(env.world).clear();
    await open(tester, waitFor: find.text('Henüz şablonunuz yok'));
    expect(find.text('Henüz şablonunuz yok'), findsOneWidget);
    expect(find.text(OrdersCopy.newOrder), findsOneWidget);
    await tearDownUi(tester);
  });

  for (final scale in [1.0, 2.0]) {
    for (final b in Brightness.values) {
      testWidgets('erişilebilirlik: Şablonlarım ${scale}x ${b.name}', (
        tester,
      ) async {
        await open(tester, textScale: scale, brightness: b);
        expect(tester.takeException(), isNull);
        await expectA11y(tester);
        await tearDownUi(tester);
      });
    }
  }
}

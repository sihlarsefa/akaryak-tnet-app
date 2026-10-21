// C.7 erişilebilirlik: 360×640, metin ölçeği 1,0 ve 2,0, açık ve koyu temada taşma yok; dokunma alanı,
// etiket ve metin kontrastı yönergeleri.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cm_test_utils.dart';

const _size = Size(360, 640);

/// Anahtar ekranlar (persona, konum).
List<(String, String)> _screens(CmEnv env) {
  final reported =
      env.world.shipments.firstWhere((s) => s['status'] == 2)['id'] as int;
  return [
    ('musteri', '/shipments'),
    ('musteri', '/shipments/$reported'),
    ('musteri', '/documents'),
    ('musteri', '/spending'),
    ('musteri', '/delivery-points'),
    ('musteri', '/delivery-points/new'),
    ('musteri', '/company/requests'),
    ('musteri', '/company/requests/2987'),
    ('musteri', '/finance-info'),
    ('musteri', '/company/users'),
  ];
}

void main() {
  for (final brightness in Brightness.values) {
    for (final scale in const [1.0, 2.0]) {
      testWidgets('ekranlar taşmaz: ${brightness.name}, metin ×$scale', (
        tester,
      ) async {
        final env = (await tester.runAsync(CmEnv.create))!;
        addTearDown(env.dispose);
        final screens = _screens(env);
        // Uygulama bir kez kurulur; ekranlar yönlendiriciyle gezilir (sağlayıcı kapsamı yaşar).
        final router = await pumpCmApp(
          tester,
          env,
          location: screens.first.$2,
          brightness: brightness,
          textScale: scale,
          size: _size,
        );
        final vertical = find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        );
        for (final (_, location) in screens) {
          router.go(location);
          await pumpFor(tester, const Duration(seconds: 1));
          expect(tester.takeException(), isNull, reason: location);
          // Ekranın altına kadar kaydır: tembel kurulan kartlar da denetlensin.
          for (var i = 0; i < 6 && vertical.evaluate().isNotEmpty; i++) {
            await tester.drag(
              vertical.first,
              const Offset(0, -420),
              warnIfMissed: false,
            );
            await pumpFor(tester, const Duration(milliseconds: 300));
          }
          expect(tester.takeException(), isNull, reason: '$location (alt)');
        }
        await finish(tester);
      });
    }

    testWidgets(
      'yönergeler: dokunma alanı, etiket, kontrast (${brightness.name})',
      (tester) async {
        final handle = tester.ensureSemantics();
        final env = (await tester.runAsync(CmEnv.create))!;
        addTearDown(env.dispose);
        final screens = _screens(env);
        final router = await pumpCmApp(
          tester,
          env,
          location: screens.first.$2,
          brightness: brightness,
          size: _size,
        );
        for (final (_, location) in screens) {
          router.go(location);
          await pumpFor(tester, const Duration(seconds: 1));
          await expectLater(
            tester,
            meetsGuideline(androidTapTargetGuideline),
            reason: location,
          );
          await expectLater(
            tester,
            meetsGuideline(iOSTapTargetGuideline),
            reason: location,
          );
          await expectLater(
            tester,
            meetsGuideline(labeledTapTargetGuideline),
            reason: location,
          );
          await expectLater(
            tester,
            meetsGuideline(textContrastGuideline),
            reason: location,
          );
        }
        await finish(tester);
        handle.dispose();
      },
    );
  }
}

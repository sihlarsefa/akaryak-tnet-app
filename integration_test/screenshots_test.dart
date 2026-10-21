// Mağaza ekran görüntüleri (spec D.7.7; ayrıntı: $W/akn-mobile/store/screenshots.md). Sahte kipte
// seçili personaların ana ekranları cihaz boyutunda çekilir. Çalıştırma (sürücü dosyaları
// `screenshots/<ad>.png` olarak yazar):
//
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/screenshots_test.dart \
//     --dart-define-from-file=env/dev.json -d "iPhone 16 Pro Max"     # 1320×2868
//   flutter drive ... -d <Android telefon / emülatör 1080×2400>
//
// DEMO şeridi görüntüde görünür; mağaza için `--dart-define=AKN_ENV=prod` KULLANILMAZ (canlıda sahte
// kip kapalıdır). Şerit yalnızca sağ üst köşededir; gerekirse görüntü işleme ile kırpılır.
import 'dart:io';

import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'smoke_flows.dart';

/// Mağaza sırası: müşteri (sipariş, teklif kararı, takip), bayi (masa, onay), şoför, saha.
const _shots = <(String persona, List<DestinationId> tabs)>[
  (
    'musteri',
    [DestinationId.home, DestinationId.myOrders, DestinationId.approvals],
  ),
  (
    'sahip',
    [DestinationId.home, DestinationId.quoteDesk, DestinationId.approvals],
  ),
  ('sofor', [DestinationId.deliveries]),
  ('saha', [DestinationId.home, DestinationId.field]),
  ('finans', [DestinationId.approvals]),
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final (persona, tabs) in _shots) {
    testWidgets('$persona mağaza görüntüleri', (tester) async {
      if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();
      final c = await launchFakeApp(tester);
      await signInAs(tester, c, persona);
      final layout = c.read(navLayoutProvider);
      final bar = find.byType(AnimatedBottomBar);
      var n = 1;
      for (final id in tabs) {
        final i = layout.bar.indexWhere((d) => d.id == id);
        if (i < 0) continue;
        if (i > 0) {
          await tester.tap(
            find.descendant(
              of: bar,
              matching: find.text(layout.bar[i].barLabel),
            ),
          );
          await pumpFor(tester, const Duration(seconds: 2));
        }
        await binding.takeScreenshot('${persona}_${n++}_${id.name}');
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}

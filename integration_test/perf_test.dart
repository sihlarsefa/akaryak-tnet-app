// Performans bütçesi (spec D.7.8): profil kipinde, orta seviye Android (API 30 / 4 GB) ve iPhone 11
// sınıfı cihazda ölçülür. Bütçe: kabuğa soğuk açılış ≤ 2,5 sn; 100 satırlık teklif masası / sipariş
// listesi kaydırırken takılan kare ≤ %1. Çalıştırma:
//
//   flutter drive --profile --driver=test_driver/integration_test.dart \
//     --target=integration_test/perf_test.dart --dart-define-from-file=env/dev.json -d <cihaz>
//
// Sonuçlar `build/integration_response_data.json` içinde (`timeline_summary` anahtarları).
import 'package:akaryakitnet/app/destinations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'smoke_flows.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('açılıştan kabuğa süre (sahte kip)', (tester) async {
    final sw = Stopwatch()..start();
    final c = await launchFakeApp(tester);
    await signInAs(tester, c, 'siparis');
    sw.stop();
    binding.reportData = {
      ...?binding.reportData,
      'shell_ready_ms': sw.elapsedMilliseconds,
      'layout': c.read(navLayoutProvider).signature,
    };
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('teklif masası ve sipariş listesi kaydırma', (tester) async {
    final c = await launchFakeApp(tester);
    await signInAs(tester, c, 'siparis');
    final layout = c.read(navLayoutProvider);
    for (final id in [DestinationId.quoteDesk, DestinationId.bayiOrders]) {
      final i = layout.bar.indexWhere((d) => d.id == id);
      if (i < 0) continue;
      await tester.tap(find.text(layout.bar[i].barLabel).last);
      await pumpFor(tester, const Duration(seconds: 2));
      final list = find.byType(Scrollable).first;
      await binding.traceAction(() async {
        for (var k = 0; k < 4; k++) {
          await tester.fling(list, const Offset(0, -600), 2400);
          await tester.pumpAndSettle();
          await tester.fling(list, const Offset(0, 600), 2400);
          await tester.pumpAndSettle();
        }
      }, reportKey: 'scroll_${id.name}');
    }
    await tester.pumpWidget(const SizedBox());
  });
}

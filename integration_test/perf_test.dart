// Performans bütçesi (spec D.7.8): profil kipinde, orta seviye Android (API 30 / 4 GB) ve iPhone 11
// sınıfı cihazda ölçülür. Bütçe: kabuğa soğuk açılış ≤ 2,5 sn; 100 satırlık teklif masası / sipariş
// listesi kaydırırken takılan kare ≤ %1. Çalıştırma:
//
//   flutter drive --profile --driver=test_driver/integration_test.dart \
//     --target=integration_test/perf_test.dart --dart-define-from-file=env/dev.json -d <cihaz>
//
// Sonuçlar `build/integration_response_data.json` içinde (`scroll_*` zaman çizelgesi özetleri:
// `average_frame_build_time_millis`, `missed_frame_build_budget_count` / `frame_count` ≤ %1).
// Gerçek soğuk açılış (simgeye dokunuştan ilk kareye) ayrıca ölçülür:
//
//   flutter run --profile --trace-startup --dart-define-from-file=env/test.json -d <cihaz>
//   # build/start_up_info.json → timeToFirstFrameMicros; kabuk için + giriş süresi ≤ 2,5 sn
//
// İndirme boyutu: `flutter build apk --analyze-size` / `flutter build ipa --analyze-size` (≤ 60 MB önerilir).
import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/features/bayi/application/desk_controller.dart';
import 'package:akaryakitnet/features/bayi/application/orders_controller.dart';
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
    // 100+ satır: teklif bekleyen 120 sipariş (sayfalar kaydırdıkça yüklenir).
    final world = FakeWorld.seeded()..addBulkPendingOrders(120);
    final c = await launchFakeApp(tester, world: world);
    await signInAs(tester, c, 'siparis');
    final layout = c.read(navLayoutProvider);
    final lists = <DestinationId, int Function()>{
      DestinationId.quoteDesk: () =>
          c.read(quoteDeskProvider).list.items.length,
      DestinationId.bayiOrders: () =>
          c.read(bayiOrdersProvider).list.items.length,
    };
    for (final MapEntry(key: id, value: loaded) in lists.entries) {
      final i = layout.bar.indexWhere((d) => d.id == id);
      if (i < 0) continue;
      await tester.tap(find.text(layout.bar[i].barLabel).last);
      await pumpFor(tester, const Duration(seconds: 2));
      final list = mainVerticalList(tester);
      bool atEnd() {
        final p = tester.state<ScrollableState>(list).position;
        return p.pixels >= p.maxScrollExtent - 1;
      }

      await binding.traceAction(() async {
        // Aşağı: 100 satır yüklenip sona varılana kadar (sayfalar kaydırdıkça gelir), sonra başa dön.
        for (var k = 0; k < 60 && !(loaded() >= 100 && atEnd()); k++) {
          await tester.fling(list, const Offset(0, -600), 2400);
          await pumpFor(tester, const Duration(milliseconds: 900));
        }
        for (var k = 0; k < 60; k++) {
          await tester.fling(list, const Offset(0, 600), 2400);
          await pumpFor(tester, const Duration(milliseconds: 900));
          if (tester.state<ScrollableState>(list).position.pixels <= 0) break;
        }
      }, reportKey: 'scroll_${id.name}');
      binding.reportData = {
        ...?binding.reportData,
        'rows_${id.name}': loaded(),
      };
    }
    await tester.pumpWidget(const SizedBox());
  });
}

// Cihaz duman testi (spec D.3 A-INT): her sahte persona gerçek cihazda / simülatörde giriş yapar,
// tüm sekmeleri ve "Diğer" hedeflerini açar, çıkar. Çalıştırma:
//
//   flutter test integration_test/app_smoke_test.dart --dart-define-from-file=env/dev.json -d <cihaz>
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'smoke_flows.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final p in fakePersonas) {
    testWidgets('${p.key}: giriş → sekmeler → Diğer → çıkış', (tester) async {
      await runPersonaSmoke(tester, p.key);
    });
  }
}

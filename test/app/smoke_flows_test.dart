// Cihaz duman akışının ana makinede çalışan kopyası (aynı kod: integration_test/smoke_flows.dart).
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/smoke_flows.dart';

void main() {
  for (final p in fakePersonas) {
    testWidgets('${p.key}: giriş → sekmeler → Diğer → çıkış', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await runPersonaSmoke(tester, p.key);
    });
  }
}

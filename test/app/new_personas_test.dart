// A-INT ek personaları (spec D.7.5): `finansuzman` (OrderFinance onay sınırı 1.000.000 ₺, üstünde karar
// düğmesi yok) ve `ozelrol` (şablonsuz özel rol: genel öncelik, onaylayan değil).
import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/core/auth/access_policy.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

void main() {
  // Roller v5 öncesi akış (eski sunucu, geçiş yapılmamış bayi / cari): finans uzmanının 1.000.000 ₺
  // sınırı birim onaycısı olmayan bayide sınanır.
  setUpAll(() {
    FakeWorld.defaultV5Station = false;
  });
  tearDownAll(() {
    FakeWorld.defaultV5Station = true;
  });

  test(
    'finansuzman: 1.000.000 ₺ üstü finans onayında karar yok, ipucu var',
    () async {
      final h = await TestHarness.create();
      final c = h.container();
      addTearDown(c.dispose);
      await c
          .read(sessionControllerProvider.notifier)
          .loginWithPassword('finansuzman', 'demo');
      final p = c.read(accessPolicyProvider);
      expect(p.rolePreset, RolePreset.finance);
      expect(p.isApprover, isTrue);
      final detail = await c
          .read(apiClientProvider)
          .get('approvals/9001', parse: JsonReader.of);
      expect(detail.integer('amount'), greaterThan(1000000));
      expect(detail.list('modes', (r) => r), isEmpty);
      expect(detail.str('decisionHint'), 'Tutar onay sınırınızı aşıyor.');
      // Aynı talepte sınırsız finans müdürü karar verebilir.
      await c.read(sessionControllerProvider.notifier).signOut();
      await c
          .read(sessionControllerProvider.notifier)
          .loginWithPassword('finans', 'demo');
      final manager = await c
          .read(apiClientProvider)
          .get('approvals/9001', parse: JsonReader.of);
      expect(manager.listOf('modes', JsonReader.toInt), contains(1));
    },
  );

  test('ozelrol: şablonsuz özel rol genel önceliği kullanır', () async {
    final h = await TestHarness.create();
    final c = h.container();
    addTearDown(c.dispose);
    await c
        .read(sessionControllerProvider.notifier)
        .loginWithPassword('ozelrol', 'demo');
    final p = c.read(accessPolicyProvider);
    expect(p.rolePreset, RolePreset.generic);
    expect(p.isApprover, isFalse);
    expect(p.access!.bayiRoleNames, ['Bölge sorumlusu']);
    final layout = c.read(navLayoutProvider);
    expect(layout.inBar(DestinationId.approvals), isFalse);
    expect(layout.contains(DestinationId.approvals), isTrue);
    expect(layout.inBar(DestinationId.bayiOrders), isTrue);
  });
}

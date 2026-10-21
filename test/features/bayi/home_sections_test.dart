// Ana sayfa bölümleri ↔ yetki tablosu (spec B.7 "Home sections and grants"): her bayi personası için
// sahte yükte görünen bölümler, rol şablonunun sayfa yetkilerinden hesaplanan beklentiyle aynıdır
// (null = gizli; ownOnly ve saha satış istisnaları dahil).
import 'package:akaryakitnet/core/auth/permissions.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/features/bayi/data/bayi_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bayi_harness.dart';

const _personas = [
  'sahip',
  'mudur',
  'finans',
  'muhasebe',
  'satis',
  'saha',
  'siparis',
  'sevkiyat',
  'sofor',
  'depo',
  'izleyici',
];

/// Spec tablosundan beklenen görünür bölümler.
Map<String, bool> _expected(FakePersona p) {
  bool can(String page) => p.pages.contains('$page:${Perm.view}');
  final ownOnly = p.capabilities.containsKey(Caps.shipmentOwnOnly);
  final fieldSales = p.roles.contains(Roles.fieldSales);
  // StationSettings mobil `me/access` sayfası değildir; rol şablonu harflerinden okunur.
  final settings = p.bayiRoleCodes.any(
    (r) => (FakeRoleTemplates.pages[r]?[Pg.stationSettings] ?? '').isNotEmpty,
  );
  return {
    'desk':
        can(Pg.stationQuoteDesk) ||
        can(Pg.stationQuotes) ||
        can(Pg.stationOrders),
    'shipments':
        !ownOnly && (can(Pg.stationShipments) || can(Pg.stationShipmentBoard)),
    'approvals': can(Pg.stationApprovals),
    'collections': can(Pg.stationPayments),
    'finance': can(Pg.stationFinance),
    'leads': can(Pg.stationLeads),
    'field': can(Pg.stationFieldOrders) || can(Pg.stationFieldApprovals),
    'setup': settings && !fieldSales,
    'sales':
        !fieldSales &&
        !ownOnly &&
        (can(Pg.stationOrders) || can(Pg.stationReports)),
  };
}

void main() {
  for (final key in _personas) {
    test('$key: görünen bölümler yetki tablosuna uyar', () async {
      final h = await BayiHarness.create();
      final c = h.container();
      addTearDown(c.dispose);
      await BayiHarness.login(c, key);
      final home = (await c.read(bayiRepositoryProvider).home()).data;
      final actual = {
        'desk': home.desk != null,
        'shipments': home.shipments != null,
        'approvals': home.approvals != null,
        'collections': home.collections != null,
        'finance': home.finance != null,
        'leads': home.leads != null,
        'field': home.field != null,
        'setup': home.setup != null,
        'sales': home.sales != null,
      };
      expect(actual, _expected(findFakePersona(key)!));
      expect(home.failedSections, isEmpty);
    });
  }
}

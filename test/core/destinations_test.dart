// Yetki → alt menü (spec A.2, A-INT D.7.1): ön ayarlar, "Diğer", kısa çubuk adları, Onaylarım kuralı,
// atanmış teslimatı olan personel, yalnızca şoför, merkez, özel rol.
import 'package:akaryakitnet/app/destinations.dart';
import 'package:akaryakitnet/app/fakes.dart';
import 'package:akaryakitnet/core/auth/access_policy.dart';
import 'package:akaryakitnet/core/auth/permissions.dart';
import 'package:akaryakitnet/core/models/app_config.dart';
import 'package:akaryakitnet/core/models/me_access.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/routing/route_access.dart';
import 'package:flutter_test/flutter_test.dart';

// Tüm özellik sahteleriyle kurulan dünya: şoför sahtesinin tembel tohumu bayi sahibine bir teslimat
// atar (`me/access.assignedOpenShipments`).
final _world = buildFakeServer(latency: false).world;

AccessPolicy _policy(String key) =>
    AccessPolicy(MeAccess.fromJson(_world.meAccess(findFakePersona(key)!)));

AccessPolicy _custom({
  required Set<String> pages,
  List<Capability> caps = const [],
  int assigned = 0,
  List<String> roles = const [Roles.station],
}) => AccessPolicy(
  MeAccess(
    userId: 'u-ozel',
    userName: 'ozel',
    displayName: 'Özel',
    persona: Persona.bayi,
    roles: roles,
    pages: pages,
    capabilities: caps,
    assignedOpenShipments: assigned,
  ),
);

List<String> _labels(List<AppDestination> list) => [
  for (final d in list) d.label,
];

void main() {
  const withAssistant = AppFeatures(assistant: true);
  const noAssistant = AppFeatures();

  group('Rol ön ayarı', () {
    final expected = {
      'musteri': RolePreset.customerApprover,
      'talep': RolePreset.customerRequester,
      'onay': RolePreset.customerApprover,
      'sahip': RolePreset.owner,
      'mudur': RolePreset.owner,
      'finans': RolePreset.finance,
      'muhasebe': RolePreset.accounting,
      'satis': RolePreset.salesManager,
      'saha': RolePreset.fieldRep,
      'siparis': RolePreset.orderDesk,
      'sevkiyat': RolePreset.dispatch,
      'depo': RolePreset.dispatch,
      'izleyici': RolePreset.viewer,
    };
    expected.forEach((key, preset) {
      test(
        '$key → ${preset.name}',
        () => expect(_policy(key).rolePreset, preset),
      );
    });

    test(
      'özel rol (kodsuz, onay yetkinliği yok) Onaylarım\'ı "Diğer"e koyar',
      () {
        final p = _custom(
          pages: const {
            'StationOrders:Gorur',
            'StationShipmentBoard:Gorur',
            'StationApprovals:Gorur',
          },
        );
        expect(p.rolePreset, RolePreset.generic);
        final layout = buildNavLayout(p, noAssistant);
        expect(_labels(layout.bar), [
          'Ana sayfa',
          'Siparişler',
          'Sevkiyat',
          'Bildirimler',
        ]);
        expect(_labels(layout.more), ['Onaylar', 'Profil']);
      },
    );

    test(
      'v4: çubuk girişte sabittir; bekleyen onay Onaylar\'ı ana sekmeye çıkarmaz',
      () {
        final p = _custom(
          pages: const {
            'StationOrders:Gorur',
            'StationShipmentBoard:Gorur',
            'StationApprovals:Gorur',
          },
        );
        final layout = buildNavLayout(p, noAssistant);
        expect(_labels(layout.bar), [
          'Ana sayfa',
          'Siparişler',
          'Sevkiyat',
          'Bildirimler',
        ]);
        expect(_labels(layout.more), ['Onaylar', 'Profil']);
      },
    );

    test('approve.* yetkinliği olan özel rolde Onaylarım ana sekmedir', () {
      final p = _custom(
        pages: const {'StationOrders:Gorur', 'StationApprovals:Gorur'},
        caps: const [Capability(Caps.approveFinanceOrder, 500000)],
      );
      expect(p.isApprover, isTrue);
      final layout = buildNavLayout(p, noAssistant);
      expect(layout.bar.map((d) => d.id), contains(DestinationId.approvals));
    });

    test('ilk eşleşen kod kazanır (müdür + muhasebe → müdür ön ayarı)', () {
      final p = AccessPolicy(
        MeAccess(
          userId: 'u',
          userName: 'u',
          displayName: 'İki rol',
          persona: Persona.bayi,
          bayiRoleCodes: const [
            BayiRoleCodes.accounting,
            BayiRoleCodes.manager,
          ],
          pages: FakeRoleTemplates.grants(const [
            BayiRoleCodes.accounting,
            BayiRoleCodes.manager,
          ]),
        ),
      );
      expect(p.rolePreset, RolePreset.owner);
    });

    // Sunucunun eski türetmesi: rol ataması olmayan bayi sahibi `owner` yetkinliklerini alır, ama
    // `bayiRoleCodes` boş gelir (`isStationOwner: true`).
    MeAccess ownerWithoutCodes({List<String> roles = const [Roles.station]}) =>
        MeAccess(
          userId: 'u-eski-sahip',
          userName: 'eski.sahip',
          displayName: 'Eski Sahip',
          persona: Persona.bayi,
          roles: roles,
          isStationOwner: true,
          pages: FakeRoleTemplates.grants(const [BayiRoleCodes.owner]),
          capabilities: [
            for (final e
                in FakeRoleTemplates.capabilities[BayiRoleCodes.owner]!.entries)
              Capability(e.key, e.value),
          ],
        );

    test('rol kodu olmayan bayi sahibi sahip ön ayarını alır', () {
      final p = AccessPolicy(ownerWithoutCodes());
      expect(p.access!.bayiRoleCodes, isEmpty);
      expect(p.rolePreset, RolePreset.owner);
      final layout = buildNavLayout(p, noAssistant);
      expect(layout.bar.first.id, DestinationId.home);
      expect(
        layout.bar.skip(1).map((d) => d.id),
        containsAllInOrder(presetTabs[RolePreset.owner]!.where(layout.inBar)),
      );
      expect(layout.bar[1].id, presetTabs[RolePreset.owner]!.first);
    });

    test('sahip bayrağı saha satışçıya sahip menüsü vermez', () {
      final p = AccessPolicy(
        ownerWithoutCodes(roles: const [Roles.station, Roles.fieldSales]),
      );
      expect(p.isFieldSales, isTrue);
      expect(p.rolePreset, RolePreset.generic);
    });

    test('sahip bayrağı menü imzasına girer (yeniden kurulum)', () {
      final a = ownerWithoutCodes();
      final b = MeAccess.fromJson({...a.toJson(), 'isStationOwner': false});
      expect(b.isStationOwner, isFalse);
      expect(a.layoutKey, isNot(b.layoutKey));
    });
  });

  test(
    'v4: sayfa başlığı = sekmenin kelimesi (yalnızca uzun adlar kısalır)',
    () {
      const short = {
        DestinationId.deliveries: 'Teslimat',
        DestinationId.myShipments: 'Teslimat',
        DestinationId.notifications: 'Bildirim',
        DestinationId.deliveryPoints: 'Noktalar',
        DestinationId.financeInfo: 'Finans',
        DestinationId.companyUsers: 'Kullanıcı',
        DestinationId.stats: 'İstatistik',
      };
      for (final d in appDestinations) {
        expect(d.barLabel, short[d.id] ?? d.label, reason: d.id.name);
        expect(d.barLabel.length, lessThanOrEqualTo(10), reason: d.id.name);
      }
      expect(destinationOf(DestinationId.approvals).label, 'Onaylar');
      expect(destinationOf(DestinationId.quoteDesk).label, 'Teklifler');
      expect(destinationOf(DestinationId.myOrders).label, 'Siparişler');
      expect(destinationOf(DestinationId.deliveries).label, 'Teslimatlar');
      expect(destinationOf(DestinationId.templates).label, 'Şablonlar');
      expect(destinationOf(DestinationId.limits).label, 'Limitler');
    },
  );

  group('Alt menü (Asistan açık)', () {
    const customerMore = [
      'Talepler',
      'Belgeler',
      'Harcamalar',
      'Teslimat noktaları',
      'Finans bilgisi',
      'Şablonlar',
      'Limitler',
    ];
    final cases =
        <String, (List<String> bar, List<String> more, String? center)>{
          'musteri': (
            ['Ana sayfa', 'Siparişler', 'Onaylar'],
            [
              'Teslimatlar',
              ...customerMore,
              'Şirket kullanıcıları',
              'İstatistikler',
              'Asistan',
              'Bildirimler',
              'Profil',
            ],
            'Sipariş ver',
          ),
          'talep': (
            ['Ana sayfa', 'Siparişler', 'Teslimatlar'],
            ['Onaylar', ...customerMore, 'Asistan', 'Bildirimler', 'Profil'],
            'Sipariş ver',
          ),
          'onay': (
            ['Ana sayfa', 'Siparişler', 'Onaylar'],
            [
              'Teslimatlar',
              ...customerMore,
              'İstatistikler',
              'Asistan',
              'Bildirimler',
              'Profil',
            ],
            'Sipariş ver',
          ),
          'sahip': (
            ['Ana sayfa', 'Onaylar', 'Teklifler', 'Siparişler'],
            [
              'Teslimatlar',
              'Sevkiyat',
              'Tahsilat',
              'Finans',
              'Cariler',
              'Saha',
              'Ekip',
              'İstatistikler',
              'Asistan',
              'Bildirimler',
              'Profil',
            ],
            null,
          ),
          'mudur': (
            ['Ana sayfa', 'Onaylar', 'Teklifler', 'Siparişler'],
            [
              'Sevkiyat',
              'Tahsilat',
              'Finans',
              'Cariler',
              'Saha',
              'Ekip',
              'İstatistikler',
              'Asistan',
              'Bildirimler',
              'Profil',
            ],
            null,
          ),
          'finans': (
            ['Ana sayfa', 'Onaylar', 'Finans', 'Tahsilat'],
            [
              'Teklifler',
              'Siparişler',
              'Cariler',
              'Saha',
              'İstatistikler',
              'Asistan',
              'Bildirimler',
              'Profil',
            ],
            null,
          ),
          'muhasebe': (
            ['Ana sayfa', 'Tahsilat', 'Finans', 'Siparişler'],
            [
              'Onaylar',
              'Cariler',
              'İstatistikler',
              'Asistan',
              'Bildirimler',
              'Profil',
            ],
            null,
          ),
          'satis': (
            ['Ana sayfa', 'Onaylar', 'Saha', 'Cariler'],
            [
              'Siparişler',
              'Ekip',
              'İstatistikler',
              'Asistan',
              'Bildirimler',
              'Profil',
            ],
            null,
          ),
          'saha': (
            ['Ana sayfa', 'Saha', 'Cariler'],
            ['Onaylar', 'İstatistikler', 'Asistan', 'Bildirimler', 'Profil'],
            'Yeni form',
          ),
          'siparis': (
            ['Ana sayfa', 'Teklifler', 'Siparişler', 'Sevkiyat'],
            [
              'Onaylar',
              'Tahsilat',
              'Cariler',
              'Asistan',
              'Bildirimler',
              'Profil',
            ],
            null,
          ),
          'sevkiyat': (
            ['Ana sayfa', 'Sevkiyat', 'Siparişler', 'Cariler'],
            ['Asistan', 'Bildirimler', 'Profil'],
            null,
          ),
          'sofor': (
            ['Teslimatlar', 'Bildirimler', 'Asistan', 'Profil'],
            [],
            null,
          ),
          'depo': (
            ['Ana sayfa', 'Sevkiyat', 'Siparişler', 'Asistan'],
            ['Bildirimler', 'Profil'],
            null,
          ),
          'izleyici': (
            ['Ana sayfa', 'Siparişler', 'Sevkiyat', 'Cariler'],
            [
              'Onaylar',
              'Teklifler',
              'Saha',
              'İstatistikler',
              'Asistan',
              'Bildirimler',
              'Profil',
            ],
            null,
          ),
          'merkez': (
            ['Ana sayfa', 'Onaylar', 'Bildirimler', 'Profil'],
            [],
            null,
          ),
        };

    test('her persona için bir beklenti var', () {
      expect(
        {for (final p in fakePersonas) p.key}.difference(cases.keys.toSet()),
        // Ek personalar (finansuzman, ozelrol) kendi testlerinde.
        everyElement(isIn(const ['finansuzman', 'ozelrol'])),
      );
    });

    cases.forEach((key, expected) {
      test(key, () {
        final layout = buildNavLayout(_policy(key), withAssistant);
        expect(_labels(layout.bar), expected.$1, reason: 'çubuk');
        expect(_labels(layout.more), expected.$2, reason: 'Diğer');
        expect(layout.center?.label, expected.$3, reason: 'orta eylem');
        // Yuva kuralı: 4 hedef + Diğer ya da 3 + eylem + Diğer; Diğer yoksa en fazla 5 konum.
        final positions =
            layout.bar.length +
            (layout.center == null ? 0 : 1) +
            (layout.hasMore ? 1 : 0);
        expect(positions, lessThanOrEqualTo(5));
        // Her hedef kendi rotasını açabilir (derin bağlantı kuralı ile menü tutarlı).
        for (final d in [...layout.bar, ...layout.more]) {
          expect(
            RouteAccess.isAllowed(d.path, _policy(key), withAssistant),
            isTrue,
            reason: '$key → ${d.path}',
          );
        }
      });
    });
  });

  group('Çubuk adları (spec C.7)', () {
    test('her kısa ad en fazla 10 karakter', () {
      for (final d in appDestinations) {
        expect(
          d.barLabel.runes.length,
          lessThanOrEqualTo(10),
          reason: '${d.id.name}: ${d.barLabel}',
        );
      }
    });

    test('kısaltılan adlar', () {
      String bar(DestinationId id) => destinationOf(id).barLabel;
      expect(bar(DestinationId.approvals), 'Onaylar');
      expect(bar(DestinationId.quoteDesk), 'Teklifler');
      expect(bar(DestinationId.deliveries), 'Teslimat');
      expect(bar(DestinationId.myOrders), 'Siparişler');
      expect(bar(DestinationId.notifications), 'Bildirim');
      expect(destinationOf(DestinationId.approvals).label, 'Onaylar');
    });

    test('"Diğer" sekmesinin adı', () => expect(NavLayout.moreLabel, 'Diğer'));
  });

  group('Alt menü (Asistan kapalı)', () {
    test('şoför: Teslimatlarım · Bildirimler · Profil', () {
      final layout = buildNavLayout(_policy('sofor'), noAssistant);
      expect(_labels(layout.bar), ['Teslimatlar', 'Bildirimler', 'Profil']);
      expect(layout.hasMore, isFalse);
      expect(layout.initialLocation, '/driver');
    });

    test('depo: her şey sığar, Diğer gizlenir', () {
      final layout = buildNavLayout(_policy('depo'), noAssistant);
      expect(_labels(layout.bar), [
        'Ana sayfa',
        'Sevkiyat',
        'Siparişler',
        'Bildirimler',
        'Profil',
      ]);
      expect(layout.hasMore, isFalse);
    });

    test('Asistan hiçbir yerde görünmez', () {
      for (final p in fakePersonas) {
        final layout = buildNavLayout(_policy(p.key), noAssistant);
        expect(
          [
            ...layout.bar,
            ...layout.more,
          ].where((d) => d.id == DestinationId.assistant),
          isEmpty,
          reason: p.key,
        );
      }
    });
  });

  group('Teslimatlarım (atanmış teslimat)', () {
    test('kendisine teslimat atanmış personel Teslimatlarım\'ı görür', () {
      final p = _custom(
        pages: const {
          'StationShipments:Gorur',
          'StationShipments:Duzenler',
          'StationShipmentBoard:Gorur',
          'StationOrders:Gorur',
        },
        assigned: 2,
      );
      expect(p.canSeeDeliveries, isTrue);
      expect(p.isDriverOnly, isFalse);
      final layout = buildNavLayout(p, noAssistant);
      expect(layout.contains(DestinationId.deliveries), isTrue);
      expect(
        RouteAccess.isAllowed('/driver/shipments/5', p, noAssistant),
        isTrue,
      );
    });

    test('atanmış teslimatı olmayan personel görmez', () {
      final p = _custom(pages: const {'StationOrders:Gorur'});
      expect(p.canSeeDeliveries, isFalse);
      expect(
        buildNavLayout(p, noAssistant).contains(DestinationId.deliveries),
        isFalse,
      );
    });

    test('bayi sahibi (atanmış teslimat): Teslimatlarım "Diğer"in başında', () {
      final p = _policy('sahip');
      expect(p.assignedOpenShipments, greaterThan(0));
      final layout = buildNavLayout(p, withAssistant);
      expect(layout.more.first.id, DestinationId.deliveries);
    });
  });

  group('Yeni hedefler ve rotalar', () {
    test('Ekip: bayi + StationStaff, saha satış hariç', () {
      expect(
        buildNavLayout(
          _policy('sahip'),
          noAssistant,
        ).contains(DestinationId.staff),
        isTrue,
      );
      expect(
        RouteAccess.isAllowed('/bayi/staff', _policy('sahip'), noAssistant),
        isTrue,
      );
      final rep = _custom(
        pages: const {'StationStaff:Gorur', 'StationFieldOrders:Gorur'},
        roles: const [Roles.station, Roles.fieldSales],
      );
      expect(RouteAccess.isAllowed('/bayi/staff', rep, noAssistant), isFalse);
      expect(
        buildNavLayout(rep, noAssistant).contains(DestinationId.staff),
        isFalse,
      );
    });

    test('Şirket kullanıcıları yalnızca Yönetici', () {
      expect(
        RouteAccess.isAllowed(
          '/company/users',
          _policy('musteri'),
          noAssistant,
        ),
        isTrue,
      );
      expect(
        RouteAccess.isAllowed('/company/users', _policy('onay'), noAssistant),
        isFalse,
      );
      expect(
        RouteAccess.isAllowed('/company/users', _policy('talep'), noAssistant),
        isFalse,
      );
      expect(
        RouteAccess.isAllowed('/company/users', _policy('sahip'), noAssistant),
        isFalse,
      );
    });

    test('Şablonlarım, Limitlerim, Finans bilgisi yalnızca müşteri', () {
      for (final path in ['/templates', '/limits', '/finance-info']) {
        expect(
          RouteAccess.isAllowed(path, _policy('musteri'), noAssistant),
          isTrue,
          reason: path,
        );
        expect(
          RouteAccess.isAllowed(path, _policy('sahip'), noAssistant),
          isFalse,
          reason: path,
        );
      }
    });

    test('merkez yalnızca Onaylarım, Bildirimler, Profil açar', () {
      final p = _policy('merkez');
      expect(RouteAccess.isAllowed('/approvals/9001', p, noAssistant), isTrue);
      expect(RouteAccess.isAllowed('/profile/phone', p, noAssistant), isTrue);
      expect(RouteAccess.isAllowed('/orders/1', p, noAssistant), isFalse);
      expect(RouteAccess.isAllowed('/bayi/orders/1', p, noAssistant), isFalse);
    });
  });

  group('Erişim politikası', () {
    test('yalnızca şoför', () {
      expect(_policy('sofor').isDriverOnly, isTrue);
      expect(_policy('depo').isDriverOnly, isFalse, reason: 'ownOnly yok');
      expect(_policy('sevkiyat').isDriverOnly, isFalse);
    });

    test('onaylayan: approve.* yetkinliği, müşteride Onaylayan/Yönetici', () {
      expect(_policy('sahip').isApprover, isTrue);
      expect(_policy('finans').isApprover, isTrue);
      expect(_policy('satis').isApprover, isTrue);
      expect(_policy('muhasebe').isApprover, isFalse);
      expect(_policy('saha').isApprover, isFalse);
      expect(_policy('musteri').isApprover, isTrue);
      expect(_policy('onay').isApprover, isTrue);
      expect(_policy('talep').isApprover, isFalse);
      expect(_policy('merkez').isApprover, isTrue);
    });

    test('merkez her yetkinliğe sahiptir; giriş yoksa hiçbir şey görünmez', () {
      expect(_policy('merkez').hasCap(Caps.approveHq), isTrue);
      expect(_policy('saha').hasCap(Caps.costsView), isFalse);
      expect(_policy('finans').capLimit(Caps.approveFinanceOrder), isNull);
      expect(
        buildNavLayout(AccessPolicy.signedOut, withAssistant).isEmpty,
        isTrue,
      );
    });

    test('saha temsilcisi maliyet sayfalarını görmez', () {
      final p = _policy('saha');
      expect(p.isFieldSales, isTrue);
      expect(p.can(Pg.stationFieldOrders, Perm.create), isTrue);
      expect(p.can(Pg.stationCustomers), isFalse);
    });

    test('sunucunun isFieldSales bayrağı da saha satış sayılır', () {
      final p = AccessPolicy(
        MeAccess.fromJson(const {
          'userId': 'u',
          'userName': 'u',
          'displayName': 'u',
          'persona': 'bayi',
          'roles': ['Station'],
          'isFieldSales': true,
        }),
      );
      expect(p.isFieldSales, isTrue);
    });
  });
}

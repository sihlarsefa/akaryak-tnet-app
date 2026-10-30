// Yetki → alt menü (spec A.2, A-INT D.7.1): ön ayarlar, "Diğer", kısa çubuk adları, Onaylarım kuralı,
// atanmış teslimatı olan personel, yalnızca şoför, merkez, özel rol. Roller v5: İkmal birimi ön ayarı,
// Onaylar imza yetkinliğinden (`signingCapabilities`; birim onaycısı başkasıysa "Diğer"de), şirket içi
// onay kapalıyken Talepler yok.
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
      'finansuzman': RolePreset.finance,
      'ikmal': RolePreset.supply,
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

    test(
      'roller v5: İkmal birimi sipariş masası ve sevkiyattan önce eşleşir',
      () {
        AccessPolicy withCodes(List<String> codes) => AccessPolicy(
          MeAccess(
            userId: 'u',
            userName: 'u',
            displayName: 'Geçişte',
            persona: Persona.bayi,
            bayiRoleCodes: codes,
            pages: FakeRoleTemplates.grants(codes),
          ),
        );
        expect(
          withCodes(const [
            BayiRoleCodes.orderDesk,
            BayiRoleCodes.supply,
          ]).rolePreset,
          RolePreset.supply,
        );
        expect(
          withCodes(const [
            BayiRoleCodes.dispatch,
            BayiRoleCodes.depot,
            BayiRoleCodes.supply,
          ]).rolePreset,
          RolePreset.supply,
        );
        // Bayi yöneticisi İkmal'den önce gelir.
        expect(
          withCodes(const [
            BayiRoleCodes.supply,
            BayiRoleCodes.owner,
          ]).rolePreset,
          RolePreset.owner,
        );
        // Pasif kodlar ön ayarlarını korur.
        expect(
          withCodes(const [BayiRoleCodes.orderDesk]).rolePreset,
          RolePreset.orderDesk,
        );
        expect(
          withCodes(const [BayiRoleCodes.viewer]).rolePreset,
          RolePreset.viewer,
        );
        expect(presetTabs[RolePreset.supply], const [
          DestinationId.quoteDesk,
          DestinationId.dispatch,
          DestinationId.bayiOrders,
        ]);
      },
    );

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
    final cases = <String, (List<String> bar, List<String> more, String? center)>{
      // Roller v5: tek müşteri rolü, şirket içi onay kapalı → Talepler yok.
      'musteri': (
        ['Ana sayfa', 'Siparişler', 'Onaylar'],
        [
          'Teslimatlar',
          ...customerMore.where((l) => l != 'Talepler'),
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
      // Pasif Bayi müdürü: birimlerin onaycısı başkası (sahip, satis, finans), imza yetkinliği
      // yok → Onaylar "Diğer"de.
      'mudur': (
        ['Ana sayfa', 'Teklifler', 'Siparişler', 'Sevkiyat'],
        [
          'Onaylar',
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
        ['Onaylar', 'Tahsilat', 'Cariler', 'Asistan', 'Bildirimler', 'Profil'],
        null,
      ),
      'sevkiyat': (
        ['Ana sayfa', 'Sevkiyat', 'Siparişler', 'Cariler'],
        ['Asistan', 'Bildirimler', 'Profil'],
        null,
      ),
      'sofor': (['Teslimatlar', 'Bildirimler', 'Asistan', 'Profil'], [], null),
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
      'merkez': (['Ana sayfa', 'Onaylar', 'Bildirimler', 'Profil'], [], null),
      // Roller v5 İkmal birimi: Teklifler · Sevkiyat · Siparişler; onay akışı yok.
      'ikmal': (
        ['Ana sayfa', 'Teklifler', 'Sevkiyat', 'Siparişler'],
        ['Onaylar', 'Tahsilat', 'Cariler', 'Asistan', 'Bildirimler', 'Profil'],
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

    test('Tüm işler (/bayi/tasks) yalnızca bayi', () {
      for (final key in ['sahip', 'finans', 'depo']) {
        expect(
          RouteAccess.isAllowed('/bayi/tasks', _policy(key), noAssistant),
          isTrue,
          reason: key,
        );
      }
      for (final key in ['musteri', 'talep']) {
        expect(
          RouteAccess.isAllowed('/bayi/tasks', _policy(key), noAssistant),
          isFalse,
          reason: key,
        );
      }
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

    test(
      'roller v5: şirket içi onay kapalıyken Talepler menüde yok; eski talebin bağlantısı açılır',
      () {
        final p = _policy('musteri');
        expect(p.access!.companyApprovalsEnabled, isFalse);
        expect(p.companyApprovals, isFalse);
        expect(
          buildNavLayout(
            p,
            withAssistant,
          ).contains(DestinationId.companyRequests),
          isFalse,
        );
        // Sayfa yetkisi sürdükçe (şirketin geçmiş talebi var) bildirimden gelen bağlantı açılır.
        expect(
          RouteAccess.isAllowed('/company/requests/2987', p, noAssistant),
          isTrue,
        );
        // Eski akışın personası (pasif Talep eden) Talepler'i görür.
        final legacy = _policy('talep');
        expect(legacy.companyApprovals, isTrue);
        expect(
          buildNavLayout(
            legacy,
            withAssistant,
          ).contains(DestinationId.companyRequests),
          isTrue,
        );
        // Alan yoksa (eski sunucu) akış açık sayılır.
        final old = AccessPolicy(
          MeAccess.fromJson({
            ...p.access!.toJson(),
            'companyApprovalsEnabled': null,
          }),
        );
        expect(old.companyApprovals, isTrue);
        expect(
          buildNavLayout(
            old,
            withAssistant,
          ).contains(DestinationId.companyRequests),
          isTrue,
        );
      },
    );

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

    test('onaylayan: imza yetkinliğinde approve.*, müşteri, merkez', () {
      // Birim onaycıları (demo bayisi Roller v5'te): sahip yönetici, satis satış, finans finans.
      expect(_policy('sahip').isApprover, isTrue);
      expect(_policy('finans').isApprover, isTrue);
      expect(_policy('satis').isApprover, isTrue);
      expect(_policy('muhasebe').isApprover, isFalse);
      expect(_policy('saha').isApprover, isFalse);
      expect(_policy('ikmal').isApprover, isFalse);
      // Ham yetkinliği var ama birimin onaycısı başkası: imzalayamaz.
      expect(_policy('mudur').isApprover, isFalse);
      expect(_policy('finansuzman').isApprover, isFalse);
      expect(_policy('mudur').hasCap(Caps.approveFinanceOrder), isTrue);
      // Müşteri (tek rol; Onaylar'da bilgi isteklerini yanıtlar), merkez.
      expect(_policy('musteri').isApprover, isTrue);
      expect(_policy('onay').isApprover, isTrue);
      expect(_policy('talep').isApprover, isTrue);
      expect(_policy('merkez').isApprover, isTrue);
    });

    group('roller v5 imza yetkinliği', () {
      // Sekmeler çubuğa sığmasın diye eski müdür şablonunun sayfaları (Onaylar ancak onaylayanda ana
      // sekme).
      MeAccess bayi({
        List<Capability> caps = const [],
        List<Capability>? signing,
      }) => MeAccess(
        userId: 'u',
        userName: 'u',
        displayName: 'u',
        persona: Persona.bayi,
        roles: const [Roles.station],
        bayiRoleCodes: const [BayiRoleCodes.manager],
        pages: FakeRoleTemplates.grants(const [BayiRoleCodes.manager]),
        capabilities: caps,
        signingCapabilities: signing,
      );
      const finance = Capability(Caps.approveFinanceOrder);

      test('alan yoksa (eski sunucu) capabilities geçerli', () {
        final p = AccessPolicy(bayi(caps: const [finance]));
        expect(p.access!.signingCapabilities, isNull);
        expect(p.isApprover, isTrue);
        expect(
          buildNavLayout(p, noAssistant).inBar(DestinationId.approvals),
          isTrue,
        );
      });

      test(
        'imza yetkinliğinde approve.* yoksa Onaylar "Diğer"de (ham yetki sürer)',
        () {
          final p = AccessPolicy(
            bayi(
              caps: const [finance, Capability(Caps.costsView)],
              signing: const [Capability(Caps.costsView)],
            ),
          );
          expect(p.isApprover, isFalse);
          expect(p.hasCap(Caps.approveFinanceOrder), isTrue);
          final layout = buildNavLayout(p, noAssistant);
          expect(layout.inBar(DestinationId.approvals), isFalse);
          expect(layout.contains(DestinationId.approvals), isTrue);
        },
      );

      test('JSON: null ve eksik aynı; liste okunur; menü imzasına girer', () {
        final base = bayi(caps: const [finance]).toJson();
        final missing = MeAccess.fromJson(
          {...base}..remove('signingCapabilities'),
        );
        final nulled = MeAccess.fromJson({
          ...base,
          'signingCapabilities': null,
        });
        expect(missing.signingCapabilities, isNull);
        expect(nulled.signingCapabilities, isNull);
        final empty = MeAccess.fromJson({
          ...base,
          'signingCapabilities': const <Object>[],
          'approverUnits': const ['finance'],
        });
        expect(empty.signingCapabilities, isEmpty);
        expect(empty.approverUnits, const ['finance']);
        expect(AccessPolicy(empty).isApprover, isFalse);
        expect(empty.layoutKey, isNot(nulled.layoutKey));
        final designee = MeAccess.fromJson(empty.toJson());
        expect(designee.approverUnits, const ['finance']);
        expect(designee.signingCapabilities, isEmpty);
      });
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

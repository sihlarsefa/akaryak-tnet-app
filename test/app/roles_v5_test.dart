// Roller v5 (spec akn-roles-v5 §7): rol kodları ve adları sunucuyla aynı, İkmal birimi ön ayarı, birim
// onaycıları ve imza yetkinliği, tek kademeli finans onayı, şirket içi onayın kapanması ve sahte dünyanın
// sunucuyu yansıtması (eski akışlar anahtarla korunur).
import 'package:akaryakitnet/app/app.dart';
import 'package:akaryakitnet/app/dev/dev_menu.dart';
import 'package:akaryakitnet/app/fakes.dart';
import 'package:akaryakitnet/app/router.dart';
import 'package:akaryakitnet/app/shell/more_sheet.dart';
import 'package:akaryakitnet/core/auth/access_policy.dart';
import 'package:akaryakitnet/core/auth/permissions.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/models/me_access.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/routing/app_routes.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/approvals/fake/a5_fake_store.dart';
import 'package:akaryakitnet/features/bayi/application/bayi_grants.dart';
import 'package:akaryakitnet/features/bayi/application/dispatch_controller.dart';
import 'package:akaryakitnet/features/bayi/application/role_tip.dart';
import 'package:akaryakitnet/features/bayi/data/staff_models.dart';
import 'package:akaryakitnet/features/bayi/fake/order_support.dart'
    show routeToFinance;
import 'package:akaryakitnet/features/customer_home/presentation/customer_home.dart';
import 'package:akaryakitnet/features/field/api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

/// Uygulamayı sahte kipte açar ve [persona] ile girer.
Future<ProviderContainer> _launchAs(WidgetTester tester, String persona) async {
  tester.view.physicalSize =
      const Size(412, 1400) * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  final h = await TestHarness.create(prefs: const {'akn.onboardingDone': true});
  await tester.pumpWidget(
    ProviderScope(overrides: h.overrides, child: const AknApp()),
  );
  await _pumpFor(tester, const Duration(seconds: 2));
  final c = ProviderScope.containerOf(tester.element(find.byType(AknApp)));
  await tester.runAsync(
    () => c
        .read(sessionControllerProvider.notifier)
        .loginWithPassword(persona, 'demo'),
  );
  await _pumpFor(tester, const Duration(seconds: 2));
  return c;
}

FakePersona _p(String key) => findFakePersona(key)!;

/// Tüm özellik sahteleriyle kurulmuş, gecikmesiz sunucu.
FakeServer _server({bool? companyApprovals, bool? v5Station}) =>
    buildFakeServer(
      world: FakeWorld.seeded(
        companyApprovals: companyApprovals,
        v5Station: v5Station,
      ),
      latency: false,
    );

Future<Object?> _call(
  FakeServer s,
  String persona,
  String method,
  String path, {
  Object? body,
}) async {
  final token =
      s.auth.issueTokens(_p(persona), deviceId: 'test-device')['accessToken']
          as String;
  final r = await s.handle(
    method: method,
    path: path,
    uri: Uri.parse('http://fake/api/v1/$path'),
    body: body,
    headers: {'authorization': 'Bearer $token'},
  );
  return r.status >= 400 ? r : r.body;
}

/// Onay ayrıntısı (A5 deposu; sunucunun `ApprovalMobileDetailDto` JSON'u).
JsonReader _approval(FakeWorld w, String persona, int id) =>
    JsonReader.of(A5FakeStore.of(w).detail(_p(persona), w.approval(id)!));

AccessPolicy _policy(FakeWorld w, String key) =>
    AccessPolicy(MeAccess.fromJson(w.meAccess(_p(key))));

void main() {
  group('rol kodları ve adları (sunucu BayiRoleTemplateCodes)', () {
    test('etkin 7, pasif 6; adlar panelle aynı', () {
      expect(BayiRoleCodes.active, const [
        'owner',
        'sales_manager',
        'field_rep',
        'finance_manager',
        'supply',
        'accounting',
        'driver',
      ]);
      expect(BayiRoleCodes.passive, const [
        'manager',
        'finance_specialist',
        'order_desk',
        'dispatch',
        'depot',
        'viewer',
      ]);
      expect(
        [for (final c in BayiRoleCodes.active) BayiRoleCodes.name(c)],
        [
          'Bayi yöneticisi',
          'Satış müdürü',
          'Satış temsilcisi',
          'Finans birimi',
          'İkmal birimi',
          'Muhasebe birimi',
          'Şoför',
        ],
      );
      // Pasif şablonlar eski adlarını korur.
      expect(BayiRoleCodes.name('manager'), 'Bayi müdürü');
      expect(BayiRoleCodes.name('finance_specialist'), 'Finans / kredi uzmanı');
      expect(BayiRoleCodes.name('order_desk'), 'Sipariş masası / operasyon');
      expect(BayiRoleCodes.name('viewer'), 'Görüntüleyici');
      expect(BayiRoleCodes.name('role:42'), 'role:42');
    });

    test('kodlar yalnızca sona eklenir (sahte roleId sırası)', () {
      expect(BayiRoleCodes.all.take(12).toList(), const [
        'owner',
        'manager',
        'finance_manager',
        'finance_specialist',
        'accounting',
        'sales_manager',
        'field_rep',
        'order_desk',
        'dispatch',
        'driver',
        'depot',
        'viewer',
      ]);
      expect(BayiRoleCodes.all.last, BayiRoleCodes.supply);
      expect(BayiRoleCodes.all.toSet(), {
        ...BayiRoleCodes.active,
        ...BayiRoleCodes.passive,
      });
    });

    test('pasif etiketi ve yerine geçen rol', () {
      expect(BayiRoleCodes.isPassive('viewer'), isTrue);
      expect(BayiRoleCodes.isPassive('owner'), isFalse);
      expect(BayiRoleCodes.isPassive(null), isFalse);
      expect(
        BayiRoleCodes.label('Görüntüleyici', passive: true),
        'Görüntüleyici (pasif)',
      );
      // Ek iki kez eklenmez; etkin rolde ek yok.
      expect(
        BayiRoleCodes.label('Görüntüleyici (pasif)', passive: true),
        'Görüntüleyici (pasif)',
      );
      expect(
        BayiRoleCodes.label('İkmal birimi', passive: false),
        'İkmal birimi',
      );
      expect(BayiRoleCodes.replacedBy('manager'), 'owner');
      expect(BayiRoleCodes.replacedBy('finance_specialist'), 'finance_manager');
      for (final c in ['order_desk', 'dispatch', 'depot']) {
        expect(BayiRoleCodes.replacedBy(c), 'supply', reason: c);
      }
      expect(BayiRoleCodes.replacedBy('viewer'), isNull);
      expect(BayiRoleCodes.replacedBy('owner'), isNull);
    });

    test('birim onaycıları: kodun birimi, kısa ad, rol satırı', () {
      expect(ApproverUnits.all, const ['management', 'sales', 'finance']);
      expect(ApproverUnits.unitOf(Caps.approveFieldManager), 'sales');
      for (final c in [
        Caps.approveFieldSenior,
        Caps.approveFieldException,
        Caps.approveOrderExecutive,
      ]) {
        expect(ApproverUnits.unitOf(c), 'management', reason: c);
      }
      for (final c in [
        Caps.approveFinanceOrder,
        Caps.approveFinanceOnboarding,
        Caps.approveFinanceLead,
      ]) {
        expect(ApproverUnits.unitOf(c), 'finance', reason: c);
      }
      for (final c in [
        Caps.approveHq,
        Caps.approveLimitHq,
        Caps.approveCompanyOrder,
        Caps.costsView,
        null,
      ]) {
        expect(ApproverUnits.unitOf(c), isNull, reason: c);
      }
      // Bayiye verilebilen her approve.* kodu tam bir birime bağlıdır.
      for (final c in Caps.bayiAssignable.where(
        (c) => c.startsWith('approve.'),
      )) {
        expect(ApproverUnits.unitOf(c), isNotNull, reason: c);
      }
      expect(ApproverUnits.shortLabel('finance'), 'Finans');
      expect(ApproverUnits.shortLabel('management'), 'Bayi yöneticisi');
      expect(ApproverUnits.label('finance'), 'Finans birimi onaycısı');
      expect(
        ApproverUnits.roleLine('Finans birimi', const ['finance']),
        'Finans birimi · onaycı',
      );
      expect(
        ApproverUnits.roleLine('Finans birimi', const []),
        'Finans birimi',
      );
    });
  });

  group('şablonlar (sunucu BayiRoleTemplates)', () {
    test('İkmal birimi spec §1.1 ile aynı', () {
      final pages = FakeRoleTemplates.pages[BayiRoleCodes.supply]!;
      expect(pages, {
        'StationQuoteDesk': 'T',
        'StationQuotes': 'T',
        'StationOrders': 'T',
        'StationShipments': 'T',
        'StationShipmentBoard': 'T',
        'StationCustomers': 'G',
        'StationReports': 'G',
        'StationApprovals': 'G',
        'StationPayments': 'G',
      });
      expect(FakeRoleTemplates.capabilities[BayiRoleCodes.supply], {
        Caps.shipmentAssign: null,
        Caps.loadingRecord: null,
      });
      // İkmal birimi eski üç şablonun birleşimidir (hiçbir yetki kaybolmaz).
      final grants = FakeRoleTemplates.grants(const [BayiRoleCodes.supply]);
      for (final old in const [
        BayiRoleCodes.orderDesk,
        BayiRoleCodes.dispatch,
        BayiRoleCodes.depot,
      ]) {
        expect(
          grants.containsAll(FakeRoleTemplates.grants([old])),
          isTrue,
          reason: old,
        );
        expect(
          FakeRoleTemplates.capabilities[BayiRoleCodes.supply]!.keys.toSet(),
          containsAll(FakeRoleTemplates.capabilities[old]!.keys),
          reason: old,
        );
      }
      // Bayi yöneticisi ⊇ eski müdür; Finans birimi ⊇ eski uzman.
      expect(
        FakeRoleTemplates.grants(const [
          BayiRoleCodes.owner,
        ]).containsAll(FakeRoleTemplates.grants(const [BayiRoleCodes.manager])),
        isTrue,
      );
      expect(
        FakeRoleTemplates.grants(const [
          BayiRoleCodes.financeManager,
        ]).containsAll(
          FakeRoleTemplates.grants(const [BayiRoleCodes.financeSpecialist]),
        ),
        isTrue,
      );
    });
  });

  group('sahte dünya: me/access', () {
    final w = FakeWorld.seeded();

    test('ikmal personası: İkmal ön ayarı, onaycı değil, ad sunucudan', () {
      final p = _policy(w, 'ikmal');
      expect(p.rolePreset, RolePreset.supply);
      expect(p.isApprover, isFalse);
      expect(p.access!.bayiRoleNames, const ['İkmal birimi']);
      expect(p.access!.phoneMasked, '0532 *** ** 15');
      expect(_p('ikmal').passive, isFalse);
    });

    test('birim onaycıları: sahip yönetici, satis satış, finans finans', () {
      expect(_policy(w, 'sahip').approverUnits, const ['management']);
      expect(_policy(w, 'satis').approverUnits, const ['sales']);
      expect(_policy(w, 'finans').approverUnits, const ['finance']);
      for (final key in ['mudur', 'finansuzman', 'muhasebe', 'ikmal']) {
        expect(_policy(w, key).approverUnits, isEmpty, reason: key);
      }
    });

    test('imza yetkinliği: başka birimin kodları düşer, ham yetki sürer', () {
      List<String> signing(String key) => [
        for (final c in _policy(w, key).access!.signingCapabilities!) c.code,
      ];
      final owner = signing('sahip');
      expect(owner, contains(Caps.approveFieldSenior));
      expect(owner, contains(Caps.approveFieldException));
      expect(owner, contains(Caps.approveOrderExecutive));
      expect(owner, isNot(contains(Caps.approveFieldManager)));
      expect(owner, isNot(contains(Caps.approveFinanceOrder)));
      // Onay dışı kodlar dokunulmaz.
      expect(owner, contains(Caps.staffManage));
      expect(
        _policy(w, 'sahip').hasCap(Caps.approveFinanceOrder),
        isTrue,
        reason: 'erişim kapıları ham yetkinliği okur',
      );
      expect(signing('finans'), contains(Caps.approveFinanceOrder));
      expect(signing('finans'), isNot(contains(Caps.approveFieldSenior)));
      expect(signing('satis'), contains(Caps.approveFieldManager));
      expect(signing('mudur').where((c) => c.startsWith('approve.')), isEmpty);
      expect(
        signing('finansuzman').where((c) => c.startsWith('approve.')),
        isEmpty,
      );
      // Müşteri ve merkezde hesaplanmaz.
      expect(_policy(w, 'musteri').access!.signingCapabilities, isNull);
      expect(_policy(w, 'merkez').access!.signingCapabilities, isNull);
    });

    test('pasif rolün adı "(pasif)" ile; etkin rollerde ek yok', () {
      expect(_policy(w, 'mudur').access!.bayiRoleNames, const [
        'Bayi müdürü (pasif)',
      ]);
      expect(_policy(w, 'izleyici').access!.bayiRoleNames, const [
        'Görüntüleyici (pasif)',
      ]);
      expect(_policy(w, 'sahip').access!.bayiRoleNames, const [
        'Bayi yöneticisi',
      ]);
      expect(_policy(w, 'ozelrol').access!.bayiRoleNames, const [
        'Bölge sorumlusu',
      ]);
    });

    test(
      'şirket içi onay: demo carisinde kapalı, pasif rollerde eski akış',
      () {
        expect(_policy(w, 'musteri').companyApprovals, isFalse);
        expect(_policy(w, 'musteri').access!.customerUserRoleLabel, 'Yönetici');
        expect(_policy(w, 'talep').companyApprovals, isTrue);
        expect(_policy(w, 'onay').companyApprovals, isTrue);
        expect(_policy(w, 'sahip').access!.companyApprovalsEnabled, isNull);
        final legacy = FakeWorld.seeded(companyApprovals: true);
        expect(_policy(legacy, 'musteri').companyApprovals, isTrue);
      },
    );

    test('eski bayi (v5Station kapalı): imza yetkinliği ve onaycı yok', () {
      final legacy = FakeWorld.seeded(v5Station: false);
      expect(_policy(legacy, 'mudur').access!.signingCapabilities, isNull);
      expect(_policy(legacy, 'mudur').isApprover, isTrue);
      expect(_policy(legacy, 'finans').approverUnits, isEmpty);
    });
  });

  group('sahte dünya: onaylar', () {
    test('9006 tek kademe "Finans birimi"; eski bayide iki kademe', () {
      final d = _approval(FakeWorld.seeded(), 'finans', 9006);
      expect(d.integer('levelCount'), 1);
      expect(d.list('steps', (r) => r.str('name')), const ['Finans birimi']);
      final old = _approval(FakeWorld.seeded(v5Station: false), 'finans', 9006);
      expect(old.integer('levelCount'), 2);
      expect(old.list('steps', (r) => r.str('name')), const [
        'Finans uzmanı',
        'Finans müdürü (750.000 ₺ üzeri)',
      ]);
    });

    test('finans onayını yalnızca finans birimi onaycısı verir', () {
      final w = FakeWorld.seeded();
      expect(_approval(w, 'finans', 9001).boolean('canDecide'), isTrue);
      for (final key in ['sahip', 'mudur', 'finansuzman']) {
        final d = _approval(w, key, 9001);
        expect(d.boolean('canDecide'), isFalse, reason: key);
        expect(
          d.str('decisionHint'),
          'Bu birimin onaycısı Can Öztürk; talebi o onaylar.',
          reason: key,
        );
      }
      expect(w.canDecide(_p('finans'), w.approval(9001)!), isTrue);
      expect(w.canDecide(_p('mudur'), w.approval(9001)!), isFalse);
      expect(w.approvalsWaitingFor(_p('mudur')), 0);
    });

    test(
      'saha formu bant 1: satış ve yönetici birimi onaycısı; müdür değil',
      () {
        final w = FakeWorld.seeded();
        bool can(String key) => _approval(w, key, 9002).boolean('canDecide');
        expect(can('satis'), isTrue);
        expect(can('sahip'), isTrue, reason: 'üst onay alt bandı da imzalar');
        expect(can('mudur'), isFalse);
        expect(
          _approval(w, 'mudur', 9002).str('decisionHint'),
          'Bu birimin onaycısı Emre Çelik; talebi o onaylar.',
        );
        final legacy = FakeWorld.seeded(v5Station: false);
        expect(_approval(legacy, 'mudur', 9002).boolean('canDecide'), isTrue);
      },
    );

    test('eski bayide finans uzmanının sınırı yine söylenir', () {
      final d = _approval(
        FakeWorld.seeded(v5Station: false),
        'finansuzman',
        9001,
      );
      expect(d.boolean('canDecide'), isFalse);
      expect(d.str('decisionHint'), 'Tutar onay sınırınızı aşıyor.');
    });

    test('şirket içi talepler (9003, 9013) yalnızca eski akışta', () {
      final w = _server().world;
      A5FakeStore.of(w);
      expect(w.approval(9003), isNull);
      expect(w.approval(9013), isNull);
      expect(
        w.notifications.where((n) => n['title'] == 'Onayınızı bekleyen talep'),
        isEmpty,
      );
      final legacy = _server(companyApprovals: true).world;
      A5FakeStore.of(legacy);
      expect(legacy.approval(9003), isNotNull);
      expect(legacy.approval(9013), isNotNull);
      expect(
        legacy.notifications.where(
          (n) => n['title'] == 'Onayınızı bekleyen talep',
        ),
        isNotEmpty,
      );
      // Ön kayıt talebi iki dünyada aynı kimlikte.
      expect(w.approval(9004)!['type'], 7);
      expect(legacy.approval(9004)!['type'], 7);
    });

    test('İkmal birimi sipariş ve sevkiyat bildirimlerini alır', () {
      final w = FakeWorld.seeded();
      final mine = [
        for (final n in w.notifications)
          if (n['userId'] == 'u-ikmal') n['eventCode'],
      ];
      expect(mine, containsAll(const ['order.created', 'order.approved']));
    });

    test(
      'limit aşan teklifin "Finans onayı bekliyor" bildirimi yalnızca imzalayabilene',
      () {
        List<String> recipients(FakeWorld w) {
          final o = w.orders.firstWhere(
            (x) => x['stationId'] == _p('sahip').stationId,
          );
          routeToFinance(w, o, 9000000, _p('ikmal'));
          final id = o['financeApprovalRequestId'];
          return [
            for (final n in w.notifications)
              if (n['eventCode'] == 'approval.pending' && n['entityId'] == id)
                n['userId'] as String,
          ]..sort();
        }

        // Finans biriminin onaycısı finans: bildirim yalnızca ona (sunucu `EligibleApproversAsync`).
        expect(recipients(FakeWorld.seeded()), ['u-finans']);
        // Roller v5 öncesi bayi: yetkinliği olan herkes.
        expect(recipients(FakeWorld.seeded(v5Station: false)), [
          'u-finans',
          'u-mudur',
          'u-sahip',
        ]);
      },
    );
  });

  group('sahte dünya: Ekip', () {
    test('rol etiketi, pasif rol, "İncelenecek" ve onaycı birimi', () async {
      final s = _server();
      final rows =
          (await _call(s, 'sahip', 'GET', 'stations/me/staff'))! as List;
      final staff = {
        for (final r in rows)
          (r as Map)['userId']: StaffMember.fromJson(JsonReader.of(r)),
      };
      final viewer = staff['u-izleyici']!;
      expect(viewer.roles.single.isRetired, isTrue);
      expect(viewer.roles.single.label, 'Görüntüleyici (pasif)');
      expect(viewer.needsReview, isTrue);
      // Taşınacak pasif rol (müdür) "(pasif)" ama incelenecek değil.
      final manager = staff['u-mudur']!;
      expect(manager.roles.single.label, 'Bayi müdürü (pasif)');
      expect(manager.needsReview, isFalse);
      expect(staff['u-finans']!.approverOf, const ['finance']);
      expect(staff['u-finans']!.approverLabels, const ['Onaycı · Finans']);
      expect(staff['u-sahip']!.approverOf, const ['management']);
      expect(staff['u-mudur']!.approverOf, isEmpty);
      expect(staff['u-ikmal']!.roleLabels, const ['İkmal birimi']);
      expect(staff['u-ozelrol']!.roleLabels, const ['Bölge sorumlusu']);
      expect(staff['u-saha']!.roleLabels, const ['Satış temsilcisi']);
    });

    test('pasif rol adı boş gelirse şablon adı "(pasif)" ekiyle', () {
      final r = StaffRole.fromJson(
        JsonReader.of(const {
          'roleId': 1,
          'roleName': '',
          'templateCode': 'depot',
          'isRetired': true,
        }),
      );
      expect(r.label, 'Depo / dolum (pasif)');
      expect(r.roleIsActive, isTrue);
    });
  });

  group('sahte dünya: şirket kullanıcıları (tek rol)', () {
    test('eşikler tanımsız; kaydetme kapalı', () async {
      final s = _server();
      final t = JsonReader.of(
        await _call(
          s,
          'musteri',
          'GET',
          'customers/me/company-users/approval-settings',
        ),
      );
      expect(t.boolean('isConfigured'), isFalse);
      expect(t.has('requireApprovalAboveLitres'), isFalse);
      final put = await _call(
        s,
        'musteri',
        'PUT',
        'customers/me/company-users/approval-settings',
        body: {'requireApprovalAboveLitres': 1000},
      );
      final problem = put! as FakeResponse;
      expect(problem.status, 400);
      expect('${problem.body}', contains('Şirket içi onay kaldırıldı.'));
    });

    test('yeni kullanıcı Yönetici olur; ana kullanıcı işaretli', () async {
      final s = _server();
      final created = JsonReader.of(
        await _call(
          s,
          'musteri',
          'POST',
          'customers/me/company-users',
          body: {
            'displayName': 'Yeni Kişi',
            'email': 'yeni.kisi@anadolulojistik.example',
            'role': 1,
          },
        ),
      );
      expect(created.integer('role'), 3);
      final rows =
          (await _call(s, 'musteri', 'GET', 'customers/me/company-users'))!
              as List;
      final main = [
        for (final r in rows)
          if ((r as Map)['isMainUser'] == true) r['userId'],
      ];
      expect(main, const ['u-musteri']);
    });
  });

  group('ekranların kuralları', () {
    test(
      'sevkiyat ekranı yükleme kaydı olup şoför ataması olmayanda listeyle açılır',
      () {
        final w = FakeWorld.seeded();
        expect(opensWithLoadings(_policy(w, 'depo')), isTrue);
        expect(opensWithLoadings(_policy(w, 'ikmal')), isFalse);
        expect(opensWithLoadings(_policy(w, 'sevkiyat')), isFalse);
        expect(opensWithLoadings(_policy(w, 'sahip')), isFalse);
        expect(opensWithLoadings(_policy(w, 'merkez')), isFalse);
      },
    );

    test('İkmal ipucu: teklif, plan ve şoför, yükleme (yetkiye göre)', () {
      final w = FakeWorld.seeded();
      final g = BayiGrants(_policy(w, 'ikmal'));
      expect(
        BayiHintSteps.forGrants(RolePreset.supply, g, inBar: (_) => true),
        const [
          'Yeni siparişlere Teklifler sekmesinden fiyat verin.',
          'Müşteri onaylayınca sevkiyatı Sevkiyat sekmesinden planlayın ve şoför atayın.',
          'Bugünkü yüklemeler ve dolum kaydı Sevkiyat sekmesinde.',
        ],
      );
      final more = BayiHintSteps.forGrants(
        RolePreset.supply,
        g,
        inBar: (_) => false,
      );
      expect(more.first, "Yeni siparişlere Diğer › Teklifler'den fiyat verin.");
      expect(BayiHintSteps.forPreset(RolePreset.supply), hasLength(3));
    });

    test('talep edenin ana sayfası yalnızca şirket içi onay açıkken', () {
      MeAccess customer(int role, bool? approvals) => MeAccess(
        userId: 'u',
        userName: 'u',
        displayName: 'u',
        persona: Persona.customer,
        customerUserRoleCode: role,
        companyApprovalsEnabled: approvals,
      );
      expect(customerRequesterHome(AccessPolicy(customer(1, true))), isTrue);
      expect(customerRequesterHome(AccessPolicy(customer(1, null))), isTrue);
      expect(customerRequesterHome(AccessPolicy(customer(1, false))), isFalse);
      expect(customerRequesterHome(AccessPolicy(customer(3, true))), isFalse);
    });
  });

  group('uygulama', () {
    testWidgets('"Diğer" kişi kartı: "Finans birimi · onaycı"', (tester) async {
      await _launchAs(tester, 'finans');
      await tester.tap(find.text('Diğer'));
      await _pumpFor(tester, const Duration(milliseconds: 800));
      final card = find.byKey(MoreSheetBody.profileKey);
      expect(card, findsOneWidget);
      expect(
        find.descendant(
          of: card,
          matching: find.textContaining('Finans birimi · onaycı'),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('saha ana sayfası: rol adı "satış temsilcisi"', (tester) async {
      await _launchAs(tester, 'saha');
      expect(find.byType(FieldHome), findsOneWidget);
      // Başlığın kişi satırı (ekran okuyucu ve selamlama): ad + rolün sunucudaki adı.
      final header = tester.widget<AknHomeHeader>(find.byType(AknHomeHeader));
      expect(header.person, 'Deniz Koç, satış temsilcisi');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('dev menüsü pasif personaları "pasif" diye listeler', (
      tester,
    ) async {
      final c = await _launchAs(tester, 'musteri');
      c.read(routerProvider).go(AppRoutes.dev);
      await _pumpFor(tester, const Duration(seconds: 1));
      expect(find.byType(DevMenuPage), findsOneWidget);
      final list = find.descendant(
        of: find.byType(DevMenuPage),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('talep · pasif'),
        300,
        scrollable: list.first,
      );
      expect(find.text('talep · pasif'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('ikmal'),
        300,
        scrollable: list.first,
      );
      expect(find.text('ikmal'), findsOneWidget);
      expect(find.byType(AknListTile), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

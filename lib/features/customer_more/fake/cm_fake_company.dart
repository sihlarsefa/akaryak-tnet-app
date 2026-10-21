import '../../../core/auth/permissions.dart';
import '../../../core/models/json.dart';
import '../../../core/network/fake/fake_personas.dart';
import '../../../core/network/fake/fake_server.dart';
import '../../../core/network/fake/fake_world.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import '../../../core/utils/validators.dart';
import 'cm_fake_support.dart';

/// Şirket içi talepler (`customers/me/order-requests`), şirket kullanıcıları ve onay eşikleri
/// (`customers/me/company-users*`), finans bilgisi (`customers/me/finance-info`).
void registerCmCompanyFakes(FakeServer s) {
  // ------------------------------------------------------------------ Talepler
  s.get('customers/me/order-requests', (req) {
    final p = _customer(req);
    req.requirePage(Pg.customerOrderRequests);
    final statuses = CmFake.intsOf(req, 'statuses');
    final onlyMine =
        (req.queryBool('onlyMine') ?? false) || p.customerUserRole == 1;
    final all =
        _requests(req.world)
            .where((r) => r['customerId'] == p.customerId)
            .where((r) => !onlyMine || r['requestedByUserId'] == p.userId)
            .where((r) => statuses.isEmpty || statuses.contains(r['status']))
            .toList()
          ..sort(
            (a, b) =>
                (b['createdAt'] as String).compareTo(a['createdAt'] as String),
          );
    final skip = (req.queryInt('skip') ?? 0).clamp(0, 1 << 30);
    final take = (req.queryInt('take') ?? 25).clamp(1, 100);
    final page = skip >= all.length
        ? const <JsonMap>[]
        : all.sublist(skip, (skip + take).clamp(0, all.length));
    return {
      'items': [for (final r in page) _requestDto(req.world, r, p)],
      'totalCount': all.length,
      'pageNumber': skip ~/ take + 1,
      'pageSize': take,
      'totalPages': (all.length / take).ceil(),
    };
  });

  s.get('customers/me/order-requests/pending-count', (req) {
    final p = _customer(req);
    final n = _requests(
      req.world,
    ).where((r) => r['customerId'] == p.customerId && r['status'] == 0).length;
    return {'count': n};
  });

  s.get('customers/me/order-requests/{id:int}', (req) {
    final p = _customer(req);
    req.requirePage(Pg.customerOrderRequests);
    return _requestDto(req.world, _ownRequest(req, p), p);
  });

  s.post('customers/me/order-requests/{id:int}/cancel', (req) {
    final p = _customer(req);
    req.requirePage(Pg.customerOrderRequests, Perm.create);
    final r = _ownRequest(req, p);
    if (r['requestedByUserId'] != p.userId) {
      throw FakeResponse.business(
        'Yalnızca kendi talebinizi geri çekebilirsiniz.',
      );
    }
    if (r['status'] != 0) {
      throw FakeResponse.business(
        'Yalnızca onay bekleyen talep geri çekilebilir.',
      );
    }
    r['status'] = 3;
    final mirror = _mirror(req.world, r['id'] as int);
    if (mirror != null) mirror['status'] = 3;
    return {'message': 'Talep iptal edildi.'};
  });

  // ------------------------------------------------------------------ Şirket kullanıcıları
  s.get('customers/me/company-users', (req) {
    final p = _manager(req);
    req.requirePage(Pg.customerCompanyUsers);
    final users =
        _users(req.world).where((u) => u['customerId'] == p.customerId).toList()
          ..sort((a, b) {
            final act = (b['isActive'] == true ? 1 : 0).compareTo(
              a['isActive'] == true ? 1 : 0,
            );
            return act != 0
                ? act
                : (a['displayName'] as String).compareTo(
                    b['displayName'] as String,
                  );
          });
    return [for (final u in users) _userDto(u, p)];
  });

  s.post('customers/me/company-users', (req) {
    final p = _manager(req);
    req.requirePage(Pg.customerCompanyUsers, Perm.create);
    final r = req.json;
    final name = _name(r.str('displayName'));
    final email = r.str('email').trim();
    if (email.isEmpty) throw FakeResponse.business('E-posta zorunludur.');
    if (Validators.email(email) != null) {
      throw FakeResponse.business('Geçerli bir e-posta adresi girin.');
    }
    final users = _users(req.world);
    if (users.any(
      (u) =>
          TurkishText.lower(u['email'] as String) == TurkishText.lower(email),
    )) {
      throw FakeResponse.business(
        'Bu e-posta adresiyle kayıtlı bir kullanıcı zaten var.',
      );
    }
    final row = <String, dynamic>{
      'userId': 'u-cm-${req.world.nextId('cm.user', start: 10)}',
      'customerId': p.customerId,
      'displayName': name,
      'email': email,
      'phoneNumber': _phone(r.nonEmpty('phoneNumber')),
      'role': _role(r.intOrNull('role')),
      'isActive': true,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'lastLoginAt': null,
      'invitationPending': true,
    };
    users.add(row);
    return {..._userDto(row, p), 'invitationQueued': true};
  });

  s.put('customers/me/company-users', (req) {
    final p = _manager(req);
    req.requirePage(Pg.customerCompanyUsers, Perm.edit);
    final r = req.json;
    final row = _user(req, p, r.str('userId'));
    final role = _role(r.intOrNull('role'));
    if (row['userId'] == p.userId && role != row['role']) {
      throw FakeResponse.business(
        'Kendi şirket rolünüzü değiştiremezsiniz; başka bir yönetici değiştirebilir.',
      );
    }
    if (row['role'] == 3 && role != 3) _ensureAnotherAdmin(req.world, p, row);
    row
      ..['displayName'] = _name(r.str('displayName'))
      ..['phoneNumber'] = _phone(r.nonEmpty('phoneNumber'))
      ..['role'] = role;
    return _userDto(row, p);
  });

  s.post('customers/me/company-users/{userId}/active', (req) {
    final p = _manager(req);
    req.requirePage(Pg.customerCompanyUsers, Perm.edit);
    final row = _user(req, p, req.params['userId']!);
    final active = req.json.boolean('isActive');
    if (!active && row['userId'] == p.userId) {
      throw FakeResponse.business('Kendi hesabınızı pasifleştiremezsiniz.');
    }
    if (!active && row['role'] == 3) _ensureAnotherAdmin(req.world, p, row);
    row['isActive'] = active;
    return {
      'message': active
          ? 'Kullanıcı aktifleştirildi.'
          : 'Kullanıcı pasifleştirildi.',
    };
  });

  s.post('customers/me/company-users/{userId}/password-link', (req) {
    final p = _manager(req);
    req.requirePage(Pg.customerCompanyUsers, Perm.edit);
    final row = _user(req, p, req.params['userId']!);
    if (row['isActive'] != true) {
      throw FakeResponse.business(
        'Pasif kullanıcıya şifre bağlantısı gönderilemez; önce aktifleştirin.',
      );
    }
    return FakeResponse.noContent();
  });

  s.get('customers/me/company-users/approval-settings', (req) {
    final p = _manager(req);
    req.requirePage(Pg.customerCompanyUsers);
    return _thresholdsDto(req.world, p.customerId!);
  });

  s.put('customers/me/company-users/approval-settings', (req) {
    final p = _manager(req);
    req.requirePage(Pg.customerCompanyUsers, Perm.edit);
    final r = req.json;
    final litres = r.decOrNull('requireApprovalAboveLitres');
    final amount = r.decOrNull('requireApprovalAboveAmount');
    if (litres != null && litres < 0) {
      throw FakeResponse.business('Litre eşiği negatif olamaz.');
    }
    if (amount != null && amount <= 0) {
      throw FakeResponse.business('Tutar eşiği sıfırdan büyük olmalı.');
    }
    final t = _thresholds(req.world);
    t[p.customerId!] = {
      'litres': litres,
      'amount': amount,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
    return _thresholdsDto(req.world, p.customerId!);
  });

  // ------------------------------------------------------------------ Finans bilgisi
  s.get('customers/me/finance-info', (req) {
    final p = _customer(req);
    if (!p.can(Pg.customerCreateOrder) && !p.can(Pg.customerOrders)) {
      throw FakeResponse.forbidden();
    }
    return _financeInfo(req.world, p);
  });
}

FakePersona _customer(FakeRequest req) {
  final p = req.requireUser();
  if (!CmFake.isCustomer(p)) {
    throw FakeResponse.business('Cari bağlamı gerekli.');
  }
  return p;
}

FakePersona _manager(FakeRequest req) {
  final p = _customer(req);
  if ((p.customerUserRole ?? 3) != 3) {
    throw FakeResponse.business(
      'Şirket kullanıcılarını ve onay eşiklerini yalnızca şirket yöneticisi yönetebilir.',
    );
  }
  return p;
}

// ------------------------------------------------------------------ Talep verisi

/// Şirket içi talepler tek torbadadır (A-INT birleştirme): sihirbazın oluşturduğu talepler (A2) ve
/// Onaylarım kararlarının satır sonuçları (A5) aynı listeye yazılır, Talepler (A3) buradan okur.
/// Bu sahtenin örnekleri, torbada aynı kimlik yoksa bir kez eklenir.
const companyRequestsBag = 'company.orderRequests';

List<JsonMap> _requests(FakeWorld w) {
  final list = w.bag<List<JsonMap>>(companyRequestsBag, () => <JsonMap>[]);
  w.bag<List<int>>('cm.orderRequests.seeded', () {
    final added = <int>[];
    for (final r in _seedRequests(w)) {
      if (list.any((x) => x['id'] == r['id'])) continue;
      list.add(r);
      added.add(r['id'] as int);
    }
    return added;
  });
  return list;
}

JsonMap? _mirror(FakeWorld w, int requestId) {
  for (final a in w.approvals) {
    if (a['subjectType'] == 'CustomerOrderRequest' &&
        a['subjectId'] == requestId) {
      return a;
    }
  }
  return null;
}

JsonMap _ownRequest(FakeRequest req, FakePersona p) {
  final id = req.intParam('id');
  final r = _requests(req.world).where((x) => x['id'] == id).firstOrNull;
  if (r == null || r['customerId'] != p.customerId) {
    throw FakeResponse.notFound('Talep bulunamadı.');
  }
  if (p.customerUserRole == 1 && r['requestedByUserId'] != p.userId) {
    throw FakeResponse.notFound('Talep bulunamadı.');
  }
  return r;
}

List<JsonMap> _seedRequests(FakeWorld w) {
  final now = w.seededAt;
  String utc(Duration ago) => now.subtract(ago).toIso8601String();
  String day(int days) =>
      FakeWorld.local(TrTime.startOfDay(now.add(Duration(days: days))));
  final cheque = w.orders
      .where((o) => o['paymentMethodCode'] == 'CEK' && o['customerId'] == 101)
      .firstOrNull;
  JsonMap line(
    int product,
    int dp,
    double liters,
    int days, {
    double? price,
    int? orderId,
    String? error,
  }) {
    final o = orderId == null ? null : w.order(orderId);
    return {
      'stationId': 1,
      'productId': product,
      'deliveryPointId': dp,
      'quantityLiters': liters,
      'requestedDeliveryDate': day(days),
      'estimatedUnitPrice':
          price ?? (w.product(product)?['listPrice'] as num?)?.toDouble(),
      'orderId': orderId,
      'orderNumber': o?['orderNumber'],
      'error': error,
    };
  }

  return [
    {
      'id': 3001,
      'customerId': 101,
      'concurrencyToken': '6a1f0c7e-1d1e-4a35-9f53-0c3c2b7e3001',
      'requestedByUserId': 'u-talep',
      'requestedByName': 'Burak Yılmaz',
      'status': 0,
      'note': 'Kış öncesi stok için; Pendik tankı boşalmak üzere.',
      'createdAt': utc(const Duration(minutes: 30)),
      'paymentMethodCode': 'HAVALE',
      'paymentTermDays': null,
      'lines': [line(1, 1001, 30000, 2, price: 42.10)],
    },
    {
      'id': 2987,
      'customerId': 101,
      'concurrencyToken': '6a1f0c7e-1d1e-4a35-9f53-0c3c2b7e2987',
      'requestedByUserId': 'u-talep',
      'requestedByName': 'Burak Yılmaz',
      'status': 1,
      'note': 'Tuzla şantiyesi ve merkez için.',
      'createdAt': utc(const Duration(hours: 6)),
      'decidedByName': 'Elif Demir',
      'decidedAt': utc(const Duration(hours: 5)),
      'decisionNote': null,
      'paymentMethodCode': 'CEK',
      'paymentTermDays': 30,
      'createdOrderIds': [?cheque?['id'] as int?],
      'lines': [
        line(1, 1002, 8000, 1, price: 42.10, orderId: cheque?['id'] as int?),
        line(
          2,
          1001,
          3000,
          1,
          price: 44.85,
          error:
              'Bu ürün için bayinin güncel fiyatı yok; satır sipariş olarak oluşturulamadı.',
        ),
      ],
    },
    {
      'id': 2970,
      'customerId': 101,
      'concurrencyToken': '6a1f0c7e-1d1e-4a35-9f53-0c3c2b7e2970',
      'requestedByUserId': 'u-talep',
      'requestedByName': 'Burak Yılmaz',
      'status': 2,
      'note': null,
      'createdAt': utc(const Duration(days: 6, hours: 2)),
      'decidedByName': 'Selin Aydın',
      'decidedAt': utc(const Duration(days: 6)),
      'decisionNote': 'Bu ay bütçe aşıldı; gelecek ay yeniden talep edin.',
      'paymentMethodCode': 'ACIK_HESAP',
      'paymentTermDays': 30,
      'lines': [line(3, 1001, 6000, -4, price: 38.40)],
    },
    {
      'id': 2955,
      'customerId': 101,
      'concurrencyToken': '6a1f0c7e-1d1e-4a35-9f53-0c3c2b7e2955',
      'requestedByUserId': 'u-talep',
      'requestedByName': 'Burak Yılmaz',
      'status': 3,
      'note': 'Yanlış nokta seçildi.',
      'createdAt': utc(const Duration(days: 9)),
      'paymentMethodCode': null,
      'lines': [line(1, 1002, 5000, -7)],
    },
  ];
}

JsonMap _requestDto(FakeWorld w, JsonMap r, FakePersona viewer) {
  // Onay talebi (Onaylarım) karara bağlandıysa durumu yansıt.
  final mirror = _mirror(w, r['id'] as int);
  if (mirror != null && r['status'] == 0) {
    final st = mirror['status'];
    if (st == 1) {
      r['status'] = 1;
      r['decidedByName'] = mirror['decidedByName'] ?? 'Elif Demir';
      r['decidedAt'] = DateTime.now().toUtc().toIso8601String();
    } else if (st == 2) {
      r['status'] = 2;
      r['decidedByName'] = mirror['decidedByName'] ?? 'Elif Demir';
      r['decidedAt'] = DateTime.now().toUtc().toIso8601String();
      r['decisionNote'] = mirror['decisionNote'];
    } else if (st == 3) {
      r['status'] = 3;
    }
  }
  final status = r['status'] as int;
  final lines = ((r['lines'] as List?) ?? const []).cast<JsonMap>();
  final total = lines.fold<double>(
    0,
    (s, l) => s + (l['quantityLiters'] as num).toDouble(),
  );
  double? est;
  for (final l in lines) {
    final price = (l['estimatedUnitPrice'] as num?)?.toDouble();
    if (price == null) continue;
    est = (est ?? 0) + price * (l['quantityLiters'] as num).toDouble();
  }
  final method = r['paymentMethodCode'] as String?;
  final methodName = method == null
      ? null
      : FakeWorld.paymentMethodNames[method];
  final term = r['paymentTermDays'] as int?;
  return {
    'id': r['id'],
    'concurrencyToken': r['concurrencyToken'],
    'customerId': r['customerId'],
    'requestedByUserId': r['requestedByUserId'],
    'requestedByName': r['requestedByName'],
    'status': status,
    'statusLabel': switch (status) {
      0 => 'Onay bekliyor',
      1 => 'Onaylandı',
      2 => 'Reddedildi',
      3 => 'Geri çekildi',
      _ => 'Bilinmiyor',
    },
    'totalLiters': total,
    'estimatedAmount': est == null
        ? null
        : double.parse(est.toStringAsFixed(2)),
    'note': r['note'],
    'decidedByName': r['decidedByName'],
    'decidedAt': r['decidedAt'],
    'decisionNote': r['decisionNote'],
    'createdOrderIds': r['createdOrderIds'] ?? const <int>[],
    'createdAt': r['createdAt'],
    'lines': [
      for (final l in lines)
        {
          ...l,
          'stationTitle': w.stationTitle(l['stationId'] as int?) ?? '',
          'productName': w.product(l['productId'] as int?)?['name'] ?? '',
          'deliveryPointName':
              w.deliveryPoint(l['deliveryPointId'] as int?)?['name'] ?? '',
        },
    ],
    'canDecide':
        status == 0 &&
        (viewer.customerUserRole ?? 3) >= 2 &&
        r['requestedByUserId'] != viewer.userId,
    'canCancel': status == 0 && r['requestedByUserId'] == viewer.userId,
    'paymentMethodCode': method,
    'paymentMethodName': methodName,
    'paymentTermDays': term,
    'paymentInstallments': null,
    'paymentDetailJson': null,
    'paymentDisplay': method == null
        ? null
        : [
            methodName ?? method,
            if (term != null && term > 0) '$term gün',
          ].join(' · '),
    'paymentDetails': const <Object>[],
  };
}

// ------------------------------------------------------------------ Kullanıcı verisi

List<JsonMap> _users(FakeWorld w) =>
    w.bag<List<JsonMap>>('cm.companyUsers', () {
      final now = w.seededAt;
      String ago(Duration d) => now.subtract(d).toIso8601String();
      JsonMap u(
        String id,
        String name,
        String email,
        String? phone,
        int role, {
        bool active = true,
        bool pending = false,
        Duration? lastLogin,
        Duration created = const Duration(days: 200),
      }) => {
        'userId': id,
        'customerId': 101,
        'displayName': name,
        'email': email,
        'phoneNumber': phone,
        'role': role,
        'isActive': active,
        'createdAt': ago(created),
        'lastLoginAt': lastLogin == null ? null : ago(lastLogin),
        'invitationPending': pending,
      };
      return [
        u(
          'u-musteri',
          'Selin Aydın',
          'musteri@demo.akaryakitnet.local',
          '05320000101',
          3,
          lastLogin: const Duration(hours: 2),
          created: const Duration(days: 420),
        ),
        u(
          'u-onay',
          'Elif Demir',
          'onay@demo.akaryakitnet.local',
          '05320000103',
          2,
          lastLogin: const Duration(days: 1),
        ),
        u(
          'u-talep',
          'Burak Yılmaz',
          'talep@demo.akaryakitnet.local',
          '05320000102',
          1,
          lastLogin: const Duration(hours: 4),
        ),
        u(
          'u-cm-1',
          'Hakan Öz',
          'hakan.oz@anadolulojistik.example',
          null,
          1,
          pending: true,
          created: const Duration(days: 2),
        ),
        u(
          'u-cm-2',
          'Merve Kılıç',
          'merve.kilic@anadolulojistik.example',
          '05330000000',
          1,
          active: false,
          lastLogin: const Duration(days: 75),
          created: const Duration(days: 300),
        ),
      ];
    });

JsonMap _user(FakeRequest req, FakePersona p, String userId) {
  final row = _users(req.world)
      .where((u) => u['userId'] == userId && u['customerId'] == p.customerId)
      .firstOrNull;
  if (row == null) throw FakeResponse.business('Kullanıcı bulunamadı.');
  return row;
}

void _ensureAnotherAdmin(FakeWorld w, FakePersona p, JsonMap row) {
  final others = _users(w).where(
    (u) =>
        u['customerId'] == p.customerId &&
        u['userId'] != row['userId'] &&
        u['role'] == 3 &&
        u['isActive'] == true,
  );
  if (others.isEmpty) {
    throw FakeResponse.business(
      'Şirketin en az bir aktif yöneticisi olmalı; önce başka bir kullanıcıyı yönetici yapın.',
    );
  }
}

String _name(String raw) {
  final v = raw.trim();
  if (v.isEmpty) throw FakeResponse.business('Ad soyad zorunludur.');
  if (v.length > 150) {
    throw FakeResponse.business('Ad soyad en çok 150 karakter olabilir.');
  }
  return v;
}

String? _phone(String? raw) {
  final v = raw?.trim();
  if (v == null || v.isEmpty) return null;
  if (v.length > 20) {
    throw FakeResponse.business('Telefon en çok 20 karakter olabilir.');
  }
  return v;
}

int _role(int? role) {
  if (role == null || role < 1 || role > 3) {
    throw FakeResponse.business('Geçersiz şirket rolü.');
  }
  return role;
}

JsonMap _userDto(JsonMap u, FakePersona viewer) => {
  'userId': u['userId'],
  'displayName': u['displayName'],
  'email': u['email'],
  'phoneNumber': u['phoneNumber'],
  'role': u['role'],
  'roleLabel': switch (u['role']) {
    1 => 'Talep eden',
    2 => 'Onaylayan',
    _ => 'Yönetici',
  },
  'isActive': u['isActive'],
  'isSelf': u['userId'] == viewer.userId,
  'createdAt': u['createdAt'],
  'lastLoginAt': u['lastLoginAt'],
  'invitationPending': u['invitationPending'] == true,
  'invitationQueued': false,
};

Map<int, JsonMap> _thresholds(FakeWorld w) => w.bag<Map<int, JsonMap>>(
  'cm.thresholds',
  () => {
    101: {
      'litres': 20000.0,
      'amount': 1000000.0,
      'updatedAt': w.seededAt
          .subtract(const Duration(days: 30))
          .toIso8601String(),
    },
  },
);

JsonMap _thresholdsDto(FakeWorld w, int customerId) {
  final t = _thresholds(w)[customerId];
  final litres = t?['litres'];
  final amount = t?['amount'];
  return {
    'customerId': customerId,
    'requireApprovalAboveLitres': litres,
    'requireApprovalAboveAmount': amount,
    'isConfigured': litres != null || amount != null,
    'updatedAt': t?['updatedAt'],
  };
}

// ------------------------------------------------------------------ Finans bilgisi

JsonMap _financeInfo(FakeWorld w, FakePersona p) {
  final links = w.links.where((l) => l['customerId'] == p.customerId).toList()
    ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
  final out = <JsonMap>[];
  for (final l in links.take(10)) {
    final stationId = l['stationId'] as int;
    if (stationId == 2 && p.customerId == 101) {
      final a = _onboardingRequest(w, p);
      final infoRequested = a['status'] == 4;
      out.add({
        'stationId': stationId,
        'stationTitle': w.stationTitle(stationId),
        'status': {
          'stationId': stationId,
          'customerId': p.customerId,
          'stationCustomerId': l['id'],
          'canOrder': false,
          'blockReason': infoRequested
              ? 'Bayinin finans ekibi ek bilgi istedi; yanıtlayınca değerlendirme sürer.'
              : 'Cari hesabınız bayinin finans onayında.',
          'isGrandfathered': false,
          'profileStatus': infoRequested ? 3 : 0,
          'infoRequested': infoRequested,
          'openApprovalRequestId': a['id'],
        },
        'requestId': a['id'],
        'requestStatus': a['status'],
        'requestStatusLabel': infoRequested ? 'Ek bilgi istendi' : 'Bekliyor',
        'infoNote': infoRequested ? a['infoNote'] : null,
        'requiredKind': infoRequested ? 10 : null,
        'requiredKindLabel': infoRequested ? 'Vergi levhası' : null,
        'requestedAt': a['createdAt'],
        'canReply': infoRequested,
      });
      continue;
    }
    out.add({
      'stationId': stationId,
      'stationTitle': w.stationTitle(stationId),
      'status': {
        'stationId': stationId,
        'customerId': p.customerId,
        'stationCustomerId': l['id'],
        'canOrder': true,
        'blockReason': null,
        'isGrandfathered': false,
        'profileStatus': l['financeStatus'] == 2 ? 2 : 1,
        'infoRequested': false,
        'openApprovalRequestId': null,
      },
      'requestId': null,
      'requestStatus': null,
      'requestStatusLabel': null,
      'infoNote': null,
      'requiredKind': null,
      'requiredKindLabel': null,
      'requestedAt': null,
      'canReply': false,
    });
  }
  final orders = <JsonMap>[];
  for (final o in w.ordersOfCustomer(p.customerId!)) {
    if (o['financeStatus'] != 4) continue;
    final reqId = o['financeApprovalRequestId'] as int?;
    final a = reqId == null ? null : w.approval(reqId);
    orders.add({
      'orderId': o['id'],
      'orderNumber': o['orderNumber'],
      'stationTitle': o['stationTitle'],
      'requestId': reqId ?? 0,
      'infoNote':
          a?['infoNote'] ?? 'Finans ekibi bu sipariş için ek bilgi istedi.',
      'requiredKind': a?['requiredAttachmentKind'],
      'requiredKindLabel': null,
      'createdAt': CmFake.offset(o['createdAt']),
    });
  }
  return {'links': out, 'orders': orders};
}

/// Kuzey Enerji bağlantısı için "ek bilgi istendi" durumundaki yeni cari finans talebi (ilk açılışta bir kez).
JsonMap _onboardingRequest(FakeWorld w, FakePersona p) {
  for (final a in w.approvals) {
    if (a['type'] == 6 &&
        a['customerId'] == p.customerId &&
        a['stationId'] == 2) {
      return a;
    }
  }
  final a = <String, dynamic>{
    'id': w.nextId('approval'),
    'type': 6,
    'status': 4,
    'isMirror': false,
    'stationId': 2,
    'stationTitle': w.stationTitle(2),
    'customerId': p.customerId,
    'customerTitle': w.customerTitle(p.customerId),
    'subjectType': 'Customer',
    'subjectId': p.customerId,
    'subjectNumber': null,
    'title': 'Yeni cari finans onayı',
    'summary': null,
    'amount': null,
    'liters': null,
    'requestedByUserId': 'u-system',
    'requestedByName': w.stationTitle(2),
    'createdAt': w.seededAt
        .subtract(const Duration(days: 1, hours: 3))
        .toIso8601String(),
    'dueAt': null,
    'slaState': 0,
    'currentLevelNo': 1,
    'levelCount': 1,
    'eligibleUserIds': const <String>[],
    'infoNote': 'Güncel vergi levhanızı ve imza sirkülerinizi yükleyin.',
    'requiredAttachmentKind': 10,
  };
  w.approvals.add(a);
  return a;
}

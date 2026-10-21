import '../../../core/auth/permissions.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/json.dart';
import '../../../core/network/fake/fake_personas.dart';
import '../../../core/network/fake/fake_server.dart';
import '../../../core/network/fake/fake_world.dart';
import '../../../core/utils/tr_time.dart';
import '../../field/fake/field_fake_state.dart' show FieldFakeState;
import 'fake_support.dart';
import 'order_support.dart';
import 'seed.dart';

/// Cariler: `bayi/customers` (+ summary), görüşme notları, limit talepleri.
void registerBayiCustomerFakes(FakeServer s) {
  s.get('bayi/customers', (req) {
    final p = bayiUser(req);
    final w = req.world;
    final links = _scope(w, p);
    final q = req.query('q')?.trim() ?? '';
    final rows = [
      for (final l in links)
        if (_matches(w, l, q)) _row(w, l),
    ]..sort((a, b) => (a['title'] as String).compareTo(b['title'] as String));
    return paged(req, rows);
  });

  s.get('bayi/customers/{customerId}/summary', (req) {
    final p = bayiUser(req);
    final w = req.world;
    final customerId = req.intParam('customerId');
    final full = p.can(Pg.stationCustomers);
    final links = _scope(w, p);
    final link = links.where((l) => l['customerId'] == customerId).firstOrNull;
    if (link == null) throw FakeResponse.notFound('Cari bulunamadı.');
    return _summary(w, p, link, portfolio: !full);
  });

  s.get('stations/me/customers/{customerId}/notes', (req) {
    final p = bayiUser(req);
    requireAny(p, const [(Pg.stationCustomers, Perm.view)]);
    final w = req.world;
    final customerId = req.intParam('customerId');
    _requireLink(w, p, customerId);
    final take = (req.queryInt('take') ?? 50).clamp(1, 200);
    return _notes(w, p, customerId).take(take).toList();
  });

  s.post('stations/me/customers/{customerId}/notes', (req) {
    final p = bayiUser(req);
    requireAny(p, const [(Pg.stationCustomers, Perm.edit)]);
    final w = req.world;
    final customerId = req.intParam('customerId');
    _requireLink(w, p, customerId);
    final body = req.json.str('body').trim();
    if (body.isEmpty) throw FakeResponse.business('Not boş olamaz.');
    if (body.length > 2000) {
      throw FakeResponse.business('Not en fazla 2000 karakter olabilir.');
    }
    final note = {
      'id': w.nextId('bayi.note', start: 801),
      'stationId': p.stationId,
      'customerId': customerId,
      'body': body,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'createdByUserId': p.userId,
      'createdByDisplay': p.displayName,
      'canDelete': true,
    };
    final all = w.bag<Map<int, List<JsonMap>>>(BayiBags.notes, () => {});
    (all[customerId] ??= []).insert(0, note);
    return note;
  });

  s.delete('stations/me/customers/{customerId}/notes/{noteId}', (req) {
    final p = bayiUser(req);
    requireAny(p, const [(Pg.stationCustomers, Perm.edit)]);
    final w = req.world;
    final customerId = req.intParam('customerId');
    final noteId = req.intParam('noteId');
    final list =
        w.bag<Map<int, List<JsonMap>>>(BayiBags.notes, () => {})[customerId] ??
        [];
    final note = list.where((n) => n['id'] == noteId).firstOrNull;
    if (note == null) throw FakeResponse.notFound('Not bulunamadı.');
    final mine = note['createdByUserId'] == p.userId;
    final manager = p.can(Pg.stationCustomers, Perm.delete);
    if (!mine && !manager) {
      throw FakeResponse.forbidden('Yalnızca kendi notunuzu silebilirsiniz.');
    }
    list.remove(note);
    return {'message': 'Not silindi.'};
  });

  s.get('stations/me/customers/{customerId}/limit-requests/pending', (req) {
    final p = bayiUser(req);
    requireAny(p, const [(Pg.stationCustomers, Perm.view)]);
    final w = req.world;
    final customerId = req.intParam('customerId');
    final link = _requireLink(w, p, customerId);
    final pending = _pending(w, link);
    if (pending == null) throw FakeResponse.notFound('Bekleyen talep yok.');
    return _limitDto(w, link, pending);
  });

  s.post('stations/me/customers/{customerId}/limit-requests', (req) {
    final p = bayiUser(req);
    requireAny(p, const [(Pg.stationCustomers, Perm.create)]);
    final w = req.world;
    final customerId = req.intParam('customerId');
    final link = _requireLink(w, p, customerId);
    final r = req.json;
    final reason = r.str('reason').trim();
    if (reason.isEmpty) {
      throw FakeResponse.business('Talep gerekçesi zorunludur.');
    }
    if (reason.length > 1000) {
      throw FakeResponse.business('Gerekçe en fazla 1000 karakter olabilir.');
    }
    final period = r.nonEmpty('limitPeriod');
    const periods = ['Günlük', 'Haftalık', 'Aylık', 'Limitsiz', 'Limitli'];
    if (period == null || !periods.contains(period)) {
      throw FakeResponse.business(
        'Limit periyodu seçin (Günlük, Haftalık, Aylık, Limitli veya Limitsiz).',
      );
    }
    String? type;
    double? amount;
    if (period != 'Limitsiz') {
      type = r.nonEmpty('limitType');
      if (type != 'Tutar' && type != 'Litre') {
        throw FakeResponse.business('Limit türü Tutar veya Litre olmalıdır.');
      }
      amount = r.decOrNull('limitAmount');
      if (amount == null || amount <= 0) {
        throw FakeResponse.business(
          'Talep edilen limit sıfırdan büyük olmalıdır.',
        );
      }
      if ((amount * 100 - (amount * 100).roundToDouble()).abs() > 1e-6) {
        throw FakeResponse.business(
          'Limit tutarı geçersiz (en fazla iki ondalık basamak).',
        );
      }
    }
    if (_pending(w, link) != null) {
      throw FakeResponse.business(
        'Bu cari için merkezde bekleyen bir limit talebi var; sonuçlanmasını bekleyin.',
      );
    }
    final same =
        period == link['limitPeriod'] &&
        (period == 'Limitsiz' ||
            (type == link['limitType'] &&
                amount == (link['limitAmount'] as num?)?.toDouble()));
    if (same) {
      throw FakeResponse.business('Talep edilen limit mevcut limitle aynı.');
    }
    final row = {
      'id': w.nextId('bayi.limit', start: 701),
      'stationId': p.stationId,
      'customerId': customerId,
      'requestedLimitType': type,
      'requestedLimitPeriod': period,
      'requestedLimitAmount': amount,
      'reason': reason,
      'status': 0,
      'requestedByUserId': p.userId,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    w.bag<List<JsonMap>>(BayiBags.limitRequests, () => []).add(row);
    return _limitDto(w, link, row);
  });
}

/// Kullanıcının gördüğü bağlantılar: StationCustomers Görür → bayinin tümü; saha satış → portföy.
List<JsonMap> _scope(FakeWorld w, FakePersona p) {
  final mine = w.links.where((l) => l['stationId'] == p.stationId);
  if (p.can(Pg.stationCustomers)) return mine.toList();
  if (isFieldSales(p)) {
    return mine.where((l) => l['salesRepUserId'] == p.userId).toList();
  }
  throw FakeResponse.forbidden();
}

JsonMap _requireLink(FakeWorld w, FakePersona p, int customerId) {
  final link = w.link(p.stationId!, customerId);
  if (link == null) throw FakeResponse.notFound('Cari bulunamadı.');
  return link;
}

bool _matches(FakeWorld w, JsonMap link, String q) {
  if (q.isEmpty) return true;
  final c = w.customer(link['customerId'] as int?);
  return textContains(c?['title'], q) ||
      textContains(c?['taxNumber'], q) ||
      textContains('C-${link['customerId']}', q) ||
      textContains(c?['city'], q) ||
      textContains(c?['district'], q);
}

({double? pct, String tone}) _usage(JsonMap link) {
  final limit = (link['limitAmount'] as num?)?.toDouble();
  if (limit == null || limit <= 0) return (pct: null, tone: 'none');
  final used = (link['used'] as num?)?.toDouble() ?? 0;
  final pct = roundTo(used / limit * 100, 1);
  final tone = pct >= 100
      ? 'danger'
      : pct >= 80
      ? 'warn'
      : 'ok';
  return (pct: pct, tone: tone);
}

int _financeStatus(JsonMap link) =>
    (link['financeStatus'] as num?)?.toInt() ?? 1;

JsonMap _row(FakeWorld w, JsonMap link) {
  final c = w.customer(link['customerId'] as int?)!;
  final orders = [
    for (final o in w.ordersOfCustomer(c['id'] as int))
      if (o['stationId'] == link['stationId']) o,
  ];
  DateTime? last;
  for (final o in orders) {
    final at = local(o['createdAt']);
    if (at != null && (last == null || at.isAfter(last))) last = at;
  }
  final u = _usage(link);
  final fs = _financeStatus(link);
  return {
    'customerId': c['id'],
    'stationCustomerId': link['id'],
    'title': c['title'],
    'city': c['city'],
    'limitUsagePct': u.pct,
    'financeStatus': fs,
    'financeStatusLabel': FinanceProfileStatus.fromCode(fs).label,
    'lastOrderAt': offset(last),
    'openOrders': orders.where((o) => !{4, 6, 7}.contains(st(o))).length,
    'code': 'C-${c['id']}',
    'district': c['district'],
    'phone': c['phone'],
    'limitTone': u.tone,
  };
}

List<JsonMap> _notes(FakeWorld w, FakePersona p, int customerId) {
  final list =
      w.bag<Map<int, List<JsonMap>>>(BayiBags.notes, () => {})[customerId] ??
      const [];
  return [
    for (final n in list)
      {
        ...n,
        'canDelete':
            n['createdByUserId'] == p.userId ||
            p.can(Pg.stationCustomers, Perm.delete),
      },
  ];
}

JsonMap? _pending(FakeWorld w, JsonMap link) => w
    .bag<List<JsonMap>>(BayiBags.limitRequests, () => [])
    .where(
      (r) =>
          r['stationId'] == link['stationId'] &&
          r['customerId'] == link['customerId'] &&
          r['status'] == 0,
    )
    .firstOrNull;

JsonMap _limitDto(FakeWorld w, JsonMap link, JsonMap r) => {
  'id': r['id'],
  'stationCustomerId': link['id'],
  'stationId': link['stationId'],
  'stationTitle': w.stationTitle(link['stationId'] as int?),
  'customerId': link['customerId'],
  'customerTitle': w.customerTitle(link['customerId'] as int?),
  'previousLimitType': link['limitType'],
  'previousLimitPeriod': link['limitPeriod'],
  'previousLimitAmount': link['limitAmount'],
  'requestedLimitType': r['requestedLimitType'],
  'requestedLimitPeriod': r['requestedLimitPeriod'],
  'requestedLimitAmount': r['requestedLimitAmount'],
  'reason': r['reason'],
  'status': r['status'],
  'statusText': 'Merkez onayında',
  'requestedByUserId': r['requestedByUserId'],
  'requestedByDisplay': staffName(r['requestedByUserId'] as String?) ?? '',
  'createdAt': r['createdAt'],
};

JsonMap _summary(
  FakeWorld w,
  FakePersona p,
  JsonMap link, {
  required bool portfolio,
}) {
  final customerId = link['customerId'] as int;
  final c = w.customer(customerId)!;
  final orders =
      [
        for (final o in w.ordersOfCustomer(customerId))
          if (o['stationId'] == link['stationId']) o,
      ]..sort(
        (a, b) => (local(b['createdAt']) ?? TrTime.now()).compareTo(
          local(a['createdAt']) ?? TrTime.now(),
        ),
      );
  JsonMap orderRow(JsonMap o) => {
    'id': o['id'],
    'orderNumber': o['orderNumber'],
    'status': st(o),
    'statusLabel': OrderStatus.fromCode(st(o)).label,
    'productName': o['productName'],
    'quantityLiters': qty(o),
    'totalAmount': currentQuote(o)?['totalAmountTry'],
    'createdAt': offset(local(o['createdAt'])),
  };
  final points = w.deliveryPointsOfCustomer(customerId);
  final u = _usage(link);
  final limit = (link['limitAmount'] as num?)?.toDouble();
  final used = (link['used'] as num?)?.toDouble() ?? 0;
  final liters = link['limitType'] == 'Litre';
  final fs = _financeStatus(link);
  final pending = _pending(w, link);
  final quotable = orders.any((o) => quotableProblem(w, o) == null);
  final canFieldForm =
      p.can(Pg.stationFieldOrders, Perm.create) &&
      (!isFieldSales(p) || link['salesRepUserId'] == p.userId);
  final today = TrTime.todayStart();
  final overdue = [
    for (final o in orders)
      if ((pay(o) == 1 || pay(o) == 2) &&
          (local(o['paymentDueDate'])?.isBefore(today) ?? false))
        o,
  ];
  final instruments = [
    for (final o in orders)
      if ((o['paymentMethodCode'] == 'CEK' ||
              o['paymentMethodCode'] == 'SENET') &&
          (pay(o) == 1 || pay(o) == 2))
        o,
  ];
  DateTime? nextDue;
  for (final o in instruments) {
    final d = local(o['paymentDueDate']);
    if (d != null && (nextDue == null || d.isBefore(nextDue))) nextDue = d;
  }
  final contacts = <JsonMap>[
    if (customerId == 101)
      {
        'name': 'Selin Aydın',
        'role': 'Yetkili, satın alma',
        'phone': '5320000101',
        'email': c['email'],
      },
    for (final dp in points)
      if (dp['contactName'] != null)
        {
          'name': dp['contactName'],
          'role': 'Teslimat sorumlusu, ${dp['name']}',
          'phone': dp['contactPhone'],
          'email': null,
        },
  ];
  final forms = <JsonMap>[
    if (customerId == 103)
      {
        'id': 7001,
        // QA LF-4: saha sahtesindeki formla aynı numara.
        'formNumber': FieldFakeState.seedFormNumber(w, 7001),
        'customerTitle': c['title'],
        'status': 1,
        'statusLabel': 'Onay bekliyor',
        'totalLiters': 18000.0,
        'totalAmount': 702000.0,
        'createdAt': DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 2))
            .toIso8601String(),
      },
  ];
  return {
    'customerId': customerId,
    'stationCustomerId': link['id'],
    'title': c['title'],
    'taxNumberMasked': _mask(c['taxNumber'] as String?),
    'city': c['city'],
    'district': c['district'],
    'contacts': contacts,
    'deliveryPoints': [
      for (final dp in points)
        {
          'id': dp['id'],
          'name': dp['name'],
          'city': dp['city'],
          'district': dp['district'],
          'address': dp['address'],
          'hasCoordinates': dp['latitude'] != null,
          'windowStart': dp['windowStart'],
          'windowEnd': dp['windowEnd'],
          'tankCapacityLiters': dp['tankCapacityLiters'],
          'contactName': dp['contactName'],
          'contactPhone': dp['contactPhone'],
          'latitude': dp['latitude'],
          'longitude': dp['longitude'],
          'accessNotes': dp['accessNotes'],
        },
    ],
    'limit': {
      'amount': limit,
      'used': used,
      'period': link['limitPeriod'],
      'periodLabel': link['limitPeriod'] == 'Limitsiz'
          ? 'Limitsiz'
          : link['limitPeriod'],
      'usagePct': u.pct,
      'unit': liters ? 'L' : 'TL',
      'remaining': limit == null ? null : roundTo(limit - used, 2),
      'limitType': link['limitType'],
      'tone': u.tone,
    },
    'finance': {
      'status': fs,
      'label': FinanceProfileStatus.fromCode(fs).label,
      'canOrder': fs == 1 || fs == 2,
      'blockReason': fs == 1 || fs == 2
          ? null
          : 'Finans kartı onaylanmadan sipariş verilemez.',
    },
    'openOrders': [
      for (final o in orders.where((o) => !{4, 6, 7}.contains(st(o))).take(10))
        orderRow(o),
    ],
    'lastOrders': [for (final o in orders.take(5)) orderRow(o)],
    'openForms': forms,
    'notes': portfolio ? const [] : _notes(w, p, customerId).take(5).toList(),
    'actions': {
      'canAddNote': !portfolio && p.can(Pg.stationCustomers, Perm.edit),
      'canRequestLimit':
          !portfolio &&
          p.can(Pg.stationCustomers, Perm.create) &&
          pending == null,
      'canCreateFieldForm': canFieldForm,
      'canQuote':
          (p.can(Pg.stationQuoteDesk, Perm.create) ||
              p.can(Pg.stationQuotes, Perm.create)) &&
          quotable,
      'canViewNotes': !portfolio && p.can(Pg.stationCustomers),
    },
    'collections': p.can(Pg.stationPayments)
        ? {
            'overdueCount': overdue.length,
            'overdueAmount': overdue.fold<double>(
              0,
              (s, o) =>
                  s +
                  ((currentQuote(o)?['totalAmountTry'] as num?)?.toDouble() ??
                      0),
            ),
            'openInstruments': instruments.length,
            'nextInstrumentDue': nextDue == null
                ? null
                : TrTime.isoDate(nextDue),
            'advanceBalance': null,
          }
        : null,
    'financeCard': p.can(Pg.stationFinance)
        ? {
            'stationCustomerId': link['id'],
            'status': fs,
            'statusLabel': FinanceProfileStatus.fromCode(fs).label,
            'riskClass': link['riskClass'] ?? 0,
            'riskClassLabel': RiskClass.fromCode(
              (link['riskClass'] as num?)?.toInt(),
            ).label,
            'nextReviewDate': TrTime.isoDate(TrTime.addDays(today, 45)),
            'hasBouncedCheque': customerId == 102,
            'hasProtestedNote': false,
            'hasProfile': true,
            'isGrandfathered': false,
          }
        : null,
    'pendingLimitRequest': portfolio || pending == null
        ? null
        : {
            'id': pending['id'],
            'limitType': pending['requestedLimitType'],
            'period': pending['requestedLimitPeriod'],
            'amount': pending['requestedLimitAmount'],
            'createdAt': pending['createdAt'],
          },
    'isPortfolioView': portfolio,
    'code': 'C-$customerId',
    'isActive': true,
  };
}

String? _mask(String? tax) {
  if (tax == null || tax.length < 4) return tax;
  return '${tax.substring(0, 2)}${'*' * (tax.length - 4)}${tax.substring(tax.length - 2)}';
}

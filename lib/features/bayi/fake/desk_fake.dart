import '../../../core/auth/permissions.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/json.dart';
import '../../../core/network/fake/fake_personas.dart';
import '../../../core/network/fake/fake_server.dart';
import '../../../core/network/fake/fake_world.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import 'fake_support.dart';
import 'order_support.dart';
import 'seed.dart';

/// Teklif masası: `bayi/quote-desk` (+ counts, submit) ve eski `stations/me/quote-desk/facets`.
void registerBayiDeskFakes(FakeServer s) {
  s.get('bayi/quote-desk', (req) {
    final p = bayiUser(req);
    requireAny(p, const [(Pg.stationQuoteDesk, Perm.view)]);
    final w = req.world;
    final expiry = expiryEnabled(w);
    var view = (req.query('view') ?? 'all').asciiLower;
    if (view == 'expiringsoon' && !expiry) view = 'all';
    final sort = (req.query('sort') ?? 'expiry').asciiLower;
    final customerId = req.queryInt('customerId');
    final productId = req.queryInt('productId');
    final all = _deskOrders(w, p, customerId: customerId, productId: productId);
    final rows = all.where((o) {
      switch (view) {
        case 'new':
          return st(o) == 1;
        case 'revision':
          return st(o) == 5;
        case 'expiringsoon':
          final left = _secondsLeft(o);
          return left != null && left <= 3600;
        default:
          return true;
      }
    }).toList();
    DateTime at(JsonMap o, String key) => local(o[key]) ?? TrTime.now();
    switch (sort) {
      case 'delivery':
        rows.sort(
          (a, b) => at(
            a,
            'requestedDeliveryDate',
          ).compareTo(at(b, 'requestedDeliveryDate')),
        );
      case 'newest':
        rows.sort((a, b) => at(b, 'createdAt').compareTo(at(a, 'createdAt')));
      default:
        rows.sort((a, b) => at(a, 'expiresAt').compareTo(at(b, 'expiresAt')));
    }
    final page = (req.queryInt('page') ?? 1).clamp(1, 1 << 20);
    final size = (req.queryInt('pageSize') ?? 25).clamp(1, 50);
    final start = (page - 1) * size;
    final slice = start >= rows.length
        ? const <JsonMap>[]
        : rows.sublist(start, (start + size).clamp(0, rows.length));
    return {
      'header': _header(w, p, customerId: customerId, productId: productId),
      'rows': [for (final o in slice) _row(w, o)],
      'totalCount': rows.length,
      'page': page,
      'pageSize': size,
      'view': switch (view) {
        'new' => 'new',
        'revision' => 'revision',
        'expiringsoon' => 'expiringSoon',
        _ => 'all',
      },
      'sort': switch (sort) {
        'delivery' => 'delivery',
        'newest' => 'newest',
        _ => 'expiry',
      },
      'counts': _counts(w, p, customerId: customerId, productId: productId),
      'today': _today(w, p),
      'serverTime': offset(TrTime.now()),
    };
  });

  s.get('bayi/quote-desk/counts', (req) {
    final p = bayiUser(req);
    requireAny(p, const [(Pg.stationQuoteDesk, Perm.view)]);
    final w = req.world;
    return {
      'expiryEnabled': expiryEnabled(w),
      'counts': _counts(
        w,
        p,
        customerId: req.queryInt('customerId'),
        productId: req.queryInt('productId'),
      ),
      'today': _today(w, p),
    };
  });

  s.get('stations/me/quote-desk/facets', (req) {
    final p = bayiUser(req);
    requireAny(p, const [(Pg.stationQuoteDesk, Perm.view)]);
    final w = req.world;
    final rows = _deskOrders(w, p);
    final customers = <int, JsonMap>{};
    final products = <int, JsonMap>{};
    for (final o in rows) {
      final c = customers.putIfAbsent(
        o['customerId'] as int,
        () => {'id': o['customerId'], 'title': o['customerTitle'], 'count': 0},
      );
      c['count'] = (c['count'] as int) + 1;
      final pr = products.putIfAbsent(
        o['productId'] as int,
        () => {'id': o['productId'], 'title': o['productName'], 'count': 0},
      );
      pr['count'] = (pr['count'] as int) + 1;
    }
    int byTitle(JsonMap a, JsonMap b) =>
        (a['title'] as String).compareTo(b['title'] as String);
    return {
      'customers': customers.values.toList()..sort(byTitle),
      'products': products.values.toList()..sort(byTitle),
    };
  });

  s.post('bayi/quote-desk/submit', (req) {
    final p = bayiUser(req);
    requireAny(p, const [(Pg.stationQuoteDesk, Perm.create)]);
    final w = req.world;
    final items = req.json.list('items', (r) => r);
    if (items.isEmpty) {
      throw FakeResponse.business('Gönderilecek teklif satırı yok.');
    }
    if (items.length > 50) {
      throw FakeResponse.business(
        'Tek gönderimde en çok 50 satır gönderilebilir.',
      );
    }
    if (_blocked(w)) {
      throw FakeResponse.business(_blockReason);
    }
    final conflicts = w.bag<Set<int>>(BayiBags.deskConflicts, () => {});
    final errors = w.bag<Set<int>>(BayiBags.deskErrors, () => {});
    final seen = <int>{};
    final out = <JsonMap>[];
    for (final r in items) {
      final orderId = r.integer('orderId');
      JsonMap result(String outcome, String message) => {
        'orderId': orderId,
        'outcome': outcome,
        'outcomeLabel': _outcomeLabel(outcome),
        'success': outcome == 'quoted',
        'message': message,
      };
      if (orderId > 0 && !seen.add(orderId)) {
        out.add(
          result('invalid', 'Bu sipariş aynı gönderimde birden fazla kez var.'),
        );
        continue;
      }
      final price = r.decOrNull('unitPrice');
      final day = TrTime.parseDate(r.strOrNull('deliveryDate'));
      final invalid = validateQuote(price, day);
      if (invalid != null) {
        out.add(result('invalid', invalid));
        continue;
      }
      final o = w.order(orderId);
      if (o == null || o['stationId'] != p.stationId) {
        out.add(result('invalid', 'Sipariş bulunamadı.'));
        continue;
      }
      if (conflicts.remove(orderId)) {
        out.add(
          result(
            'conflict',
            'Sipariş aynı anda başka bir işlemle güncellendi. Masayı yenileyip tekrar deneyin.',
          ),
        );
        continue;
      }
      if (errors.remove(orderId)) {
        out.add(result('error', 'Teklif gönderilemedi. Tekrar deneyin.'));
        continue;
      }
      final problem = quotableProblem(w, o);
      if (problem != null) {
        out.add(result('invalid', problem));
        continue;
      }
      final total = roundTo(price! * qty(o), 2);
      final from = st(o);
      if (exceedsLimit(w, o, total)) {
        routeToFinance(w, o, total, p);
        out.add(
          result(
            'routedToFinance',
            'Teklif cari limitini aşıyor; sipariş finans onayına gönderildi. Finans onaylayınca masaya döner.',
          ),
        );
        continue;
      }
      addQuote(w, o, price, day!);
      addTimeline(w, o, from, 2, p.userId);
      notifyQuoteReady(w, o, p, price);
      out.add(result('quoted', 'Teklif gönderildi.'));
    }
    return out;
  });
}

const _blockReason =
    'Bayi hesabınız pasif olduğu için yeni teklif verilemez; bekleyen siparişleri yalnızca görüntüleyebilirsiniz.';

bool _blocked(FakeWorld w) =>
    w.bag<Map<String, Object>>(
      BayiBags.settings,
      () => {'expiryEnabled': true},
    )['quotingBlocked'] ==
    true;

/// Testler / geliştirme: teklif engelini aç / kapat.
void setFakeQuotingBlocked(FakeWorld w, bool blocked) =>
    w.bag<Map<String, Object>>(
      BayiBags.settings,
      () => {'expiryEnabled': true},
    )['quotingBlocked'] = blocked;

String _outcomeLabel(String outcome) => switch (outcome) {
  'quoted' => 'Teklif gönderildi',
  'routedToFinance' => 'Finans onayına gönderildi',
  'conflict' => 'Başka bir işlemle güncellendi',
  'invalid' => 'Gönderilemedi',
  _ => 'Gönderilemedi, tekrar deneyin',
};

/// Masadaki siparişler: teklif / revize bekleyen, finans engeli yok, (süre dolumu açıksa) süresi geçmemiş.
List<JsonMap> _deskOrders(
  FakeWorld w,
  FakePersona p, {
  int? customerId,
  int? productId,
}) => [
  for (final o in w.ordersOfStation(p.stationId!))
    if ((st(o) == 1 || st(o) == 5) &&
        !financeHeld(o) &&
        fin(o) != 5 &&
        !isExpired(w, o) &&
        (customerId == null || o['customerId'] == customerId) &&
        (productId == null || o['productId'] == productId))
      o,
];

int? _secondsLeft(JsonMap o) {
  final e = local(o['expiresAt']);
  if (e == null) return null;
  final s = e.difference(TrTime.now()).inSeconds;
  return s < 0 ? 0 : s;
}

JsonMap _header(FakeWorld w, FakePersona p, {int? customerId, int? productId}) {
  final blocked = _blocked(w);
  return {
    'expiryEnabled': expiryEnabled(w),
    'financeHeld': _financeHeld(
      w,
      p,
      customerId: customerId,
      productId: productId,
    ),
    'quotingBlocked': blocked,
    'quotingBlockedReason': blocked ? _blockReason : null,
    'canSubmit': p.can(Pg.stationQuoteDesk, Perm.create) && !blocked,
    'epdkWarning': null,
    'soonMinutes': 60,
    'maxBatch': 50,
  };
}

int _financeHeld(
  FakeWorld w,
  FakePersona p, {
  int? customerId,
  int? productId,
}) => w
    .ordersOfStation(p.stationId!)
    .where(
      (o) =>
          (st(o) == 1 || st(o) == 5) &&
          financeHeld(o) &&
          (customerId == null || o['customerId'] == customerId) &&
          (productId == null || o['productId'] == productId),
    )
    .length;

JsonMap _counts(FakeWorld w, FakePersona p, {int? customerId, int? productId}) {
  final rows = _deskOrders(w, p, customerId: customerId, productId: productId);
  final expiry = expiryEnabled(w);
  return {
    'all': rows.length,
    'awaitingQuote': rows.where((o) => st(o) == 1).length,
    'revision': rows.where((o) => st(o) == 5).length,
    'expiringSoon': expiry
        ? rows.where((o) {
            final left = _secondsLeft(o);
            return left != null && left <= 3600;
          }).length
        : null,
    'financeHeld': _financeHeld(
      w,
      p,
      customerId: customerId,
      productId: productId,
    ),
  };
}

JsonMap _today(FakeWorld w, FakePersona p) {
  final today = TrTime.todayStart();
  var orders = 0;
  var quoted = 0;
  for (final o in w.ordersOfStation(p.stationId!)) {
    final c = local(o['createdAt']);
    if (c != null && !c.isBefore(today)) orders++;
    for (final q in quotesOf(o)) {
      final at = local(q['createdAt']);
      if (at != null && !at.isBefore(today)) quoted++;
    }
  }
  return {
    'ordersToday': orders,
    'quotedToday': quoted,
    'avgFirstQuoteMinutes': quoted == 0 ? null : 18,
  };
}

JsonMap _row(FakeWorld w, JsonMap o) {
  final latest = quotesOf(o).lastOrNull;
  final requested = local(o['requestedDeliveryDate']);
  final today = TrTime.todayStart();
  final def = requested == null || requested.isBefore(today)
      ? today
      : requested;
  final suggestion = suggestionFor(w, o);
  final dp = w.deliveryPoint(o['deliveryPointId'] as int?);
  final customer = w.customer(o['customerId'] as int?);
  final product = w.product(o['productId'] as int?);
  return {
    'orderId': o['id'],
    'orderNumber': o['orderNumber'],
    'status': st(o),
    'statusLabel': OrderStatus.fromCode(st(o)).label,
    'stationId': o['stationId'],
    'stationTitle': o['stationTitle'],
    'customerId': o['customerId'],
    'customerTitle': o['customerTitle'],
    'customerCode': 'C-${o['customerId']}',
    'productId': o['productId'],
    'productName': o['productName'],
    'productCode': product?['code'],
    'quantityLiters': qty(o),
    'deliveryPointName': o['deliveryPointName'],
    'deliveryPointCity': dp?['city'] ?? customer?['city'],
    'deliveryPointDistrict': dp?['district'],
    'requestedDeliveryDate': offset(requested),
    'expiresAt': offset(local(o['expiresAt'])),
    'createdAt': offset(local(o['createdAt'])),
    'latestQuoteVersion': latest?['version'],
    'latestUnitPriceTry': latest?['unitPriceTry'],
    'latestQuoteDeliveryDate': offset(local(latest?['deliveryDate'])),
    'latestRevisionNote': st(o) == 5 ? (latest?['revisionNote']) : null,
    'recentPrices': recentPricesFor(w, o),
    'paymentMethodCode': o['paymentMethodCode'],
    'paymentMethodName': o['paymentMethodName'],
    'paymentTermDays': o['paymentTermDays'],
    'paymentDueDate': offset(local(o['paymentDueDate'])),
    'paymentInstallments': o['paymentInstallments'],
    'paymentStatus': pay(o),
    'financeStatus': fin(o),
    'suggestedUnitPrice': suggestion.price,
    'suggestedSource': suggestion.source,
    'suggestedLabel': suggestion.label,
    'defaultDeliveryDate': TrTime.isoDate(def),
    'secondsLeft': expiryEnabled(w) ? _secondsLeft(o) : null,
    'payChip': payChipFor(o),
  };
}

/// Testler: bir sonraki gönderimde bu siparişler için "conflict" / "error" sonucu.
void injectDeskOutcome(FakeWorld w, int orderId, {required String outcome}) {
  ensureBayiSeed(w);
  if (outcome == 'conflict') {
    w.bag<Set<int>>(BayiBags.deskConflicts, () => {}).add(orderId);
  } else if (outcome == 'error') {
    w.bag<Set<int>>(BayiBags.deskErrors, () => {}).add(orderId);
  }
}

/// Testler: bayinin persona anahtarıyla masadaki sipariş kimlikleri (süre sırasıyla).
List<int> fakeDeskOrderIds(FakeWorld w, String personaKey) {
  ensureBayiSeed(w);
  final p = findFakePersona(personaKey)!;
  final rows = _deskOrders(w, p)
    ..sort(
      (a, b) => (local(a['expiresAt']) ?? TrTime.now()).compareTo(
        local(b['expiresAt']) ?? TrTime.now(),
      ),
    );
  return [for (final o in rows) o['id'] as int];
}

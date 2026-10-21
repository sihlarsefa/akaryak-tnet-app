import '../../../core/auth/permissions.dart';
import '../../../core/models/json.dart';
import '../../../core/models/me_access.dart';
import '../../../core/network/fake/fake_personas.dart';
import '../../../core/network/fake/fake_server.dart';
import '../../../core/network/fake/fake_world.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import 'fake_support.dart';
import 'order_support.dart';
import 'seed.dart';

/// Siparişler: `bayi/orders` (+ counts), sipariş ayrıntısı ve zaman çizelgesi (paylaşılan), tekil teklif,
/// tamamla.
void registerBayiOrderFakes(FakeServer s) {
  s.get('bayi/orders', (req) {
    final p = bayiUser(req);
    requireAny(p, const [(Pg.stationOrders, Perm.view)]);
    final w = req.world;
    final rows = _filtered(req, w, p);
    return paged(req, [for (final o in rows) bayiOrderRow(w, o)]);
  });

  s.get('bayi/orders/counts', (req) {
    final p = bayiUser(req);
    requireAny(p, const [(Pg.stationOrders, Perm.view)]);
    final w = req.world;
    final counts = <String, int>{
      for (final k in const [
        'awaitingQuote',
        'revisionRequested',
        'awaitingCustomer',
        'financeHeld',
        'toPlan',
        'inTransit',
        'reported',
        'disputed',
        'paymentPending',
      ])
        k: 0,
    };
    for (final o in w.ordersOfStation(p.stationId!)) {
      for (final seg in segmentsOf(w, o)) {
        counts[seg] = (counts[seg] ?? 0) + 1;
      }
    }
    return counts;
  });

  // Tekil teklif (sipariş ayrıntısı; StationQuotes:Ekler).
  s.post('orders/{id}/quote', (req) {
    final p = bayiUser(req);
    requireAny(p, const [(Pg.stationQuotes, Perm.create)]);
    final w = req.world;
    final o = w.order(req.intParam('id'));
    if (o == null || o['stationId'] != p.stationId) {
      throw FakeResponse.notFound('Sipariş bulunamadı.');
    }
    final problem = quotableProblem(w, o);
    if (problem != null) throw FakeResponse.business(problem);
    final r = req.json;
    final price = r.decOrNull('unitPriceTry');
    final day = TrTime.parseDate(r.strOrNull('deliveryDate'));
    final invalid = validateQuote(price, day);
    if (invalid != null) throw FakeResponse.business(invalid);
    final total = roundTo(price! * qty(o), 2);
    final from = st(o);
    if (exceedsLimit(w, o, total)) {
      routeToFinance(w, o, total, p);
      return {'message': 'Teklif gönderildi.'};
    }
    addQuote(w, o, price, day!);
    addTimeline(w, o, from, 2, p.userId);
    notifyQuoteReady(w, o, p, price);
    return {'message': 'Teklif gönderildi.'};
  });

  s.post('orders/{id}/complete', (req) {
    final p = bayiUser(req);
    requireAny(p, const [(Pg.stationOrders, Perm.edit)]);
    final w = req.world;
    final o = w.order(req.intParam('id'));
    if (o == null || o['stationId'] != p.stationId) {
      throw FakeResponse.notFound('Sipariş bulunamadı.');
    }
    if (st(o) == 7) return {'message': 'Sipariş tamamlandı.'};
    if (st(o) != 3) {
      throw FakeResponse.business(
        'Yalnızca onaylanmış sipariş tamamlanabilir.',
      );
    }
    final accepted = shipmentTotals(w, o['id'] as int).accepted;
    if (accepted + 0.0005 < qty(o)) {
      throw FakeResponse.business(
        'Tüm litre teslim alınmadan sipariş tamamlanamaz.',
      );
    }
    o['status'] = 7;
    addTimeline(w, o, 3, 7, p.userId, note: 'Bayi siparişi tamamladı.');
    return {'message': 'Sipariş tamamlandı.'};
  });

  // ---- Paylaşılan okuma uçları (başka bir özellik kaydetmediyse) ----
  registerSharedIfAbsent(
    s,
    method: 'GET',
    pattern: 'orders/{id:int}',
    probePath: 'orders/1',
    handler: (req) {
      final o = _visibleOrder(req);
      return orderDetailDto(o);
    },
  );

  registerSharedIfAbsent(
    s,
    method: 'GET',
    pattern: 'orders/{id:int}/timeline',
    probePath: 'orders/1/timeline',
    handler: (req) {
      final o = _visibleOrder(req);
      return timelineOf(req.world, o);
    },
  );
}

/// Personaya göre görünür sipariş (bayi: kendi bayisi; cari: kendi carisi; merkez: tümü).
JsonMap _visibleOrder(FakeRequest req) {
  final p = req.requireUser();
  final w = req.world;
  ensureBayiSeed(w);
  final o = w.order(req.intParam('id'));
  if (o == null) throw FakeResponse.notFound('Sipariş bulunamadı.');
  switch (p.persona) {
    case Persona.bayi:
      requireAny(p, const [
        (Pg.stationOrders, Perm.view),
        (Pg.stationQuotes, Perm.view),
      ]);
      if (o['stationId'] != p.stationId) {
        throw FakeResponse.notFound('Sipariş bulunamadı.');
      }
    case Persona.customer:
      requireAny(p, const [
        (Pg.customerOrders, Perm.view),
        (Pg.customerQuotes, Perm.view),
      ]);
      if (o['customerId'] != p.customerId) {
        throw FakeResponse.notFound('Sipariş bulunamadı.');
      }
    case Persona.platform:
      break;
    case Persona.unknown:
      throw FakeResponse.forbidden();
  }
  return o;
}

List<JsonMap> _filtered(FakeRequest req, FakeWorld w, FakePersona p) {
  final statuses = queryInts(req, 'statuses');
  final payment = req.queryInt('paymentStatus');
  final finance = req.queryInt('financeStatus');
  final customerId = req.queryInt('customerId');
  final productId = req.queryInt('productId');
  final createdFrom = queryDate(req, 'createdFrom');
  final createdTo = queryDate(req, 'createdTo');
  final requestedFrom = queryDate(req, 'requestedFrom');
  final requestedTo = queryDate(req, 'requestedTo');
  final segment = req.query('segment');
  final q = req.query('q')?.trim() ?? '';
  bool inRange(DateTime? v, DateTime? from, DateTime? to) {
    if (v == null) return from == null && to == null;
    if (from != null && v.isBefore(from)) return false;
    if (to != null && !v.isBefore(to.add(const Duration(days: 1)))) {
      return false;
    }
    return true;
  }

  final rows = w.ordersOfStation(p.stationId!).where((o) {
    if (statuses.isNotEmpty && !statuses.contains(st(o))) return false;
    if (payment != null && effectivePayment(o) != payment) return false;
    if (finance != null && fin(o) != finance) return false;
    if (customerId != null && o['customerId'] != customerId) return false;
    if (productId != null && o['productId'] != productId) return false;
    if ((createdFrom != null || createdTo != null) &&
        !inRange(local(o['createdAt']), createdFrom, createdTo)) {
      return false;
    }
    if ((requestedFrom != null || requestedTo != null) &&
        !inRange(
          local(o['requestedDeliveryDate']),
          requestedFrom,
          requestedTo,
        )) {
      return false;
    }
    if (segment != null && segment.isNotEmpty) {
      final match = segmentsOf(
        w,
        o,
      ).any((sg) => sg.asciiLower == segment.asciiLower);
      if (!match) return false;
    }
    if (q.isNotEmpty &&
        !(textContains(o['orderNumber'], q) ||
            textContains(o['customerTitle'], q) ||
            textContains(o['productName'], q) ||
            textContains(o['deliveryPointName'], q) ||
            textContains(
              w.customer(o['customerId'] as int?)?['taxNumber'],
              q,
            ))) {
      return false;
    }
    return true;
  }).toList();

  final sort = req.query('sort')?.asciiLower;
  DateTime at(JsonMap o, String key) => local(o[key]) ?? TrTime.now();
  switch (sort) {
    case 'expiry':
      rows.sort((a, b) => at(a, 'expiresAt').compareTo(at(b, 'expiresAt')));
    case 'requested':
      rows.sort(
        (a, b) => at(
          a,
          'requestedDeliveryDate',
        ).compareTo(at(b, 'requestedDeliveryDate')),
      );
    default:
      rows.sort((a, b) => at(b, 'createdAt').compareTo(at(a, 'createdAt')));
  }
  return rows;
}

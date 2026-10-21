import '../../core/auth/permissions.dart';
import '../../core/models/json.dart';
import '../../core/models/me_access.dart';
import '../../core/network/fake/fake_server.dart';
import '../../core/utils/tr_time.dart';
import '../../core/utils/turkish_text.dart';
import '../approvals/api.dart';

/// Tahsilat sahte uçları (sahibi A5; spec §B.8). Ödeme durumu ortak dünyadaki siparişe yazılır
/// (müşterinin sipariş ayrıntısı ve bayi siparişleri aynı durumu görür).
///
/// - `GET payments?method&status=open|all|1..6&statuses=1,2&customerId&overdue&dueFrom&dueTo&q&page`
/// - `GET payments/{orderId}`, `POST payments/{orderId}/status`
/// - `GET payments/instruments?kind&status=open|all|1..7&dueFrom&dueTo&q&page`
/// - `POST payments/instruments/{id}/status`
/// - Yedek: `GET bayi/customers?q` (A4 kaydederse onunki geçerlidir; cari süzgeci için).
void registerPaymentsFakes(FakeServer server) {
  void require(FakeRequest req) {
    final p = req.requireUser();
    if (p.persona != Persona.bayi || !p.can(Pg.stationPayments)) {
      throw FakeResponse.forbidden();
    }
  }

  List<int> csvInts(FakeRequest req, String key) => [
    for (final v in req.queryAll(key))
      for (final part in v.split(',')) ?int.tryParse(part.trim()),
  ];

  List<int>? paymentStatuses(FakeRequest req) {
    final many = csvInts(req, 'statuses').where((s) => s != 0).toList();
    if (many.isNotEmpty) return many;
    final key = TurkishText.searchKey(req.query('status') ?? '');
    if (key.isEmpty || key == 'open') return const [1, 2];
    if (key == 'all') return null;
    final n = int.tryParse(key);
    return n != null && n >= 1 && n <= 6 ? [n] : const [1, 2];
  }

  List<int>? instrumentStatuses(FakeRequest req) {
    final key = TurkishText.searchKey(req.query('status') ?? '');
    if (key.isEmpty || key == 'open') return const [1, 2, 3];
    if (key == 'all') return null;
    final n = int.tryParse(key);
    return n != null && n >= 1 && n <= 7 ? [n] : const [1, 2, 3];
  }

  DateTime? day(FakeRequest req, String key) =>
      TrTime.parseDate(req.query(key));

  server.get('payments', (req) {
    require(req);
    final p = req.requireUser();
    final store = A5FakeStore.of(req.world);
    final statuses = paymentStatuses(req);
    final customerId = req.queryInt('customerId');
    final overdue = req.queryBool('overdue') ?? false;
    final methods = [
      for (final v in req.queryAll('method'))
        for (final m in v.split(','))
          // Yöntem kodları ASCII büyük harftir (NAKIT, HAVALE, CEK…).
          if (m.trim().isNotEmpty) m.trim(),
    ];
    final from = day(req, 'dueFrom');
    final to = day(req, 'dueTo');
    final q = req.query('q');
    final rows = <JsonMap>[];
    for (final o in req.world.orders) {
      if (o['stationId'] != p.stationId) continue;
      final status = (o['paymentStatus'] as int?) ?? 0;
      if (o['paymentMethodCode'] == null || status == 0) continue;
      if (statuses != null && !statuses.contains(status)) continue;
      if (customerId != null && o['customerId'] != customerId) continue;
      if (methods.isNotEmpty && !methods.contains(o['paymentMethodCode'])) {
        continue;
      }
      final row = store.paymentRow(o);
      if (overdue && row['isOverdue'] != true) continue;
      final due = TrTime.parseLocal(row['dueDate'] as String?);
      if (from != null && (due == null || due.isBefore(from))) continue;
      if (to != null && (due == null || due.isAfter(to))) continue;
      if (!A5FakeStore.matches([
        row['orderNumber'],
        row['customerTitle'],
        row['methodName'],
      ], q)) {
        continue;
      }
      rows.add(row);
    }
    // Gecikenler ve vadesi yakın olanlar önce; vadesizler sonda.
    int dueKey(JsonMap r) =>
        TrTime.parseLocal(r['dueDate'] as String?)?.millisecondsSinceEpoch ??
        (1 << 52);
    rows.sort((a, b) => dueKey(a).compareTo(dueKey(b)));
    return req.paged(rows);
  });

  server.get('payments/instruments', (req) {
    require(req);
    final p = req.requireUser();
    final store = A5FakeStore.of(req.world);
    final statuses = instrumentStatuses(req);
    final kind = req.queryInt('kind');
    final from = day(req, 'dueFrom');
    final to = day(req, 'dueTo');
    final q = req.query('q');
    final rows = [
      for (final i in store.instruments)
        if (i['stationId'] == p.stationId &&
            (statuses == null || statuses.contains(i['status'])) &&
            (kind == null || i['kind'] == kind) &&
            A5FakeStore.matches([
              i['customerTitle'],
              i['serialNo'],
              i['bankName'],
              i['orderNumber'],
              i['debtorName'],
            ], q) &&
            (from == null ||
                !(TrTime.parseLocal(i['dueDate'] as String?)?.isBefore(from) ??
                    true)) &&
            (to == null ||
                !(TrTime.parseLocal(i['dueDate'] as String?)?.isAfter(to) ??
                    true)))
          store.instrumentJson(p, i),
    ];
    int dueKey(JsonMap r) =>
        TrTime.parseLocal(r['dueDate'] as String?)?.millisecondsSinceEpoch ?? 0;
    rows.sort((a, b) => dueKey(a).compareTo(dueKey(b)));
    return req.paged(rows);
  });

  JsonMap orderOf(FakeRequest req) {
    final p = req.requireUser();
    final o = req.world.order(req.intParam('orderId'));
    if (o == null || o['stationId'] != p.stationId) {
      throw FakeResponse.notFound('Sipariş bulunamadı.');
    }
    return o;
  }

  server.get('payments/{orderId:int}', (req) {
    require(req);
    final o = orderOf(req);
    return A5FakeStore.of(req.world).paymentDetail(req.requireUser(), o);
  });

  server.post('payments/{orderId:int}/status', (req) {
    require(req);
    final p = req.requireUser();
    if (!p.can(Pg.stationPayments, Perm.edit) ||
        !p.hasCap(Caps.paymentStatusUpdate)) {
      throw FakeResponse.forbidden();
    }
    final o = orderOf(req);
    A5FakeStore.of(req.world).changePaymentStatus(p, o, req.json);
    return FakeResponse.noContent();
  });

  server.post('payments/instruments/{id:int}/status', (req) {
    require(req);
    final p = req.requireUser();
    if (!A5FakeStore.canManageInstruments(p)) throw FakeResponse.forbidden();
    final id = req.intParam('id');
    final store = A5FakeStore.of(req.world);
    final i = store.instruments
        .where((x) => x['id'] == id && x['stationId'] == p.stationId)
        .firstOrNull;
    if (i == null) throw FakeResponse.notFound('Çek / senet kaydı bulunamadı.');
    store.changeInstrumentStatus(p, i, req.json);
    return FakeResponse.noContent();
  });

  // Yedek: A4 `bayi/customers` kaydederse o geçerlidir (daha özgül desen).
  server.get('bayi/{section}', (req) {
    if (req.params['section'] != 'customers') {
      throw FakeResponse.problem(
        404,
        'not_found',
        'Sahte API\'de tanımlı değil: GET ${req.path}',
      );
    }
    final p = req.requireUser();
    if (p.persona != Persona.bayi ||
        !(p.can(Pg.stationCustomers) || p.can(Pg.stationFieldOrders))) {
      throw FakeResponse.forbidden();
    }
    final q = req.query('q');
    final rows = <JsonMap>[];
    for (final l in req.world.links) {
      if (l['stationId'] != p.stationId) continue;
      final c = req.world.customer(l['customerId'] as int?);
      if (c == null) continue;
      if (!A5FakeStore.matches([c['title'], c['city']], q)) continue;
      rows.add({
        'customerId': c['id'],
        'stationCustomerId': l['id'],
        'title': c['title'],
        'city': c['city'],
        'district': c['district'],
        'phone': c['phone'],
        'limitUsagePct': null,
        'financeStatus': l['financeStatus'],
        'lastOrderAt': null,
        'openOrders': 0,
        'limitTone': 'none',
      });
    }
    rows.sort((a, b) => '${a['title']}'.compareTo('${b['title']}'));
    return req.paged(rows);
  });
}

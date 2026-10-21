import 'dart:math' as math;

import '../../../core/auth/permissions.dart';
import '../../../core/models/json.dart';
import '../../../core/network/fake/fake_server.dart';
import '../../../core/network/fake/fake_world.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import 'cm_fake_support.dart';

/// `GET customers/me/spending` (`SpendingReportDto`): onaylanan / tamamlanan siparişlerin teklif tutarları.
///
/// Sahte kipte geçmiş aylar için deterministik bir alım geçmişi eklenir (yalnızca bu rapor için;
/// sipariş listelerini değiştirmez).
void registerCmSpendingFakes(FakeServer s) {
  s.get('customers/me/spending', (req) {
    final p = req.requireUser();
    if (!CmFake.isCustomer(p)) {
      throw FakeResponse.business('Cari bağlamı gerekli.');
    }
    req.requirePage(Pg.customerSpending);
    final w = req.world;
    final today = TrTime.startOfDay(TrTime.now());
    var to = TrTime.parseDate(req.query('toDate')) ?? today;
    if (to.isAfter(today)) to = today;
    final tw = TrTime.wall(to);
    var from =
        TrTime.parseDate(req.query('fromDate')) ??
        TrTime.fromWall(tw.year, tw.month - 11, 1);
    if (from.isAfter(to)) (from, to) = (to, from);
    final tw2 = TrTime.wall(to);
    final earliest = TrTime.fromWall(tw2.year, tw2.month - 35, 1);
    if (from.isBefore(earliest)) from = earliest;
    final rows = _rows(w, p.customerId!, from, to)
        .where(
          (r) =>
              (req.queryInt('deliveryPointId') == null ||
                  r.dp == req.queryInt('deliveryPointId')) &&
              (req.queryInt('productId') == null ||
                  r.product == req.queryInt('productId')) &&
              (req.queryInt('stationId') == null ||
                  r.station == req.queryInt('stationId')),
        )
        .toList();
    return _report(w, rows, from, to);
  });
}

class _Row {
  _Row(
    this.ym,
    this.product,
    this.dp,
    this.station,
    this.orders,
    this.liters,
    this.amount,
  );
  final int ym;
  final int product;
  final int dp;
  final int station;
  final int orders;
  final double liters;
  final double amount;
}

int _ym(DateTime instant) {
  final w = TrTime.wall(instant);
  return w.year * 100 + w.month;
}

List<_Row> _rows(FakeWorld w, int customerId, DateTime from, DateTime to) {
  final out = <_Row>[];
  final end = to.add(const Duration(days: 1));
  // Gerçek (dünyadaki) onaylı / tamamlanmış siparişler.
  for (final o in w.ordersOfCustomer(customerId)) {
    final st = o['status'];
    if (st != 3 && st != 7) continue;
    final created = CmFake.instant(o['createdAt']);
    if (created == null || created.isBefore(from) || !created.isBefore(end)) {
      continue;
    }
    out.add(
      _Row(
        _ym(created),
        o['productId'] as int,
        o['deliveryPointId'] as int,
        o['stationId'] as int,
        1,
        (o['quantityLiters'] as num).toDouble(),
        CmFake.orderAmount(o) ?? 0,
      ),
    );
  }
  if (customerId != 101) return out;
  // Önceki aylar için demo geçmişi (tohum: ay anahtarı).
  final current = _ym(TrTime.now());
  var cursor = TrTime.fromWall(TrTime.wall(from).year, TrTime.wall(from).month);
  var guard = 0;
  while (!cursor.isAfter(to) && guard++ < 40) {
    final ym = _ym(cursor);
    if (ym < current) out.addAll(_history(ym));
    final cw = TrTime.wall(cursor);
    cursor = TrTime.fromWall(cw.year, cw.month + 1);
  }
  return out;
}

List<_Row> _history(int ym) {
  final r = math.Random(ym);
  final month = ym % 100;
  final age =
      (TrTime.wall(TrTime.now()).year * 12 + TrTime.wall(TrTime.now()).month) -
      ((ym ~/ 100) * 12 + month);
  final base = 42.1 - age * 0.18 + (r.nextDouble() - 0.5) * 0.6;
  final out = <_Row>[];
  void add(int product, double price, int orders, double minL, double maxL) {
    for (var i = 0; i < orders; i++) {
      final liters =
          ((minL + r.nextDouble() * (maxL - minL)) / 500).round() * 500.0;
      final dp = r.nextDouble() < 0.7 ? 1001 : 1002;
      final station = r.nextDouble() < 0.85 ? 1 : 2;
      final unit = double.parse(
        (price + (r.nextDouble() - 0.5) * 0.3).toStringAsFixed(4),
      );
      out.add(
        _Row(
          ym,
          product,
          dp,
          station,
          1,
          liters,
          double.parse((liters * unit).toStringAsFixed(2)),
        ),
      );
    }
  }

  add(1, base, 2 + r.nextInt(3), 6000, 15000);
  if (r.nextDouble() < 0.55) add(2, base + 2.8, 1, 2500, 5000);
  final winter = month >= 11 || month <= 3;
  if (winter) add(3, base - 3.6, 1 + r.nextInt(2), 4000, 9000);
  return out;
}

JsonMap _report(FakeWorld w, List<_Row> rows, DateTime from, DateTime to) {
  double round2(double v) => double.parse(v.toStringAsFixed(2));
  double? avg(double amount, double liters) =>
      liters > 0 ? double.parse((amount / liters).toStringAsFixed(4)) : null;
  final totalAmount = rows.fold<double>(0, (s, r) => s + r.amount);
  final totalLiters = rows.fold<double>(0, (s, r) => s + r.liters);
  final totalOrders = rows.fold<int>(0, (s, r) => s + r.orders);

  final months = <JsonMap>[];
  var cursor = TrTime.fromWall(TrTime.wall(from).year, TrTime.wall(from).month);
  var guard = 0;
  while (!cursor.isAfter(to) && guard++ < 37) {
    final cw = TrTime.wall(cursor);
    final ym = cw.year * 100 + cw.month;
    final mRows = rows.where((r) => r.ym == ym);
    final liters = mRows.fold<double>(0, (s, r) => s + r.liters);
    final amount = mRows.fold<double>(0, (s, r) => s + r.amount);
    months.add({
      'year': cw.year,
      'month': cw.month,
      'orderCount': mRows.fold<int>(0, (s, r) => s + r.orders),
      'liters': liters,
      'amount': round2(amount),
      'shortLabel': '${Fmt.monthShort[cw.month - 1]} ${cw.year}',
      'longLabel': '${Fmt.monthNames[cw.month - 1]} ${cw.year}',
      'avgUnitPrice': avg(amount, liters),
    });
    cursor = TrTime.fromWall(cw.year, cw.month + 1);
  }

  List<JsonMap> buckets(
    int Function(_Row r) key,
    String Function(int id) name,
    String? Function(int id) extra,
  ) {
    final by = <int, List<_Row>>{};
    for (final r in rows) {
      (by[key(r)] ??= []).add(r);
    }
    final list = [
      for (final e in by.entries)
        () {
          final liters = e.value.fold<double>(0, (s, r) => s + r.liters);
          final amount = e.value.fold<double>(0, (s, r) => s + r.amount);
          return <String, dynamic>{
            'id': e.key,
            'name': name(e.key),
            'extra': extra(e.key),
            'orderCount': e.value.fold<int>(0, (s, r) => s + r.orders),
            'liters': liters,
            'amount': round2(amount),
            'amountShare': totalAmount <= 0
                ? 0.0
                : double.parse((amount * 100 / totalAmount).toStringAsFixed(1)),
            'avgUnitPrice': avg(amount, liters),
          };
        }(),
    ]..sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));
    return list;
  }

  return {
    'fromDate': FakeWorld.local(from),
    'toDate': FakeWorld.local(to),
    'months': months,
    'byProduct': buckets(
      (r) => r.product,
      (id) => w.product(id)?['name'] as String? ?? '—',
      (id) => w.product(id)?['code'] as String?,
    ),
    'byDeliveryPoint': buckets(
      (r) => r.dp,
      (id) => w.deliveryPoint(id)?['name'] as String? ?? '—',
      (id) => w.deliveryPoint(id)?['city'] as String?,
    ),
    'byStation': buckets(
      (r) => r.station,
      (id) => w.stationTitle(id) ?? '—',
      (id) => w.station(id)?['code'] as String?,
    ),
    'truncated': false,
    'totalOrders': totalOrders,
    'totalLiters': totalLiters,
    'totalAmount': round2(totalAmount),
    'avgUnitPrice': avg(totalAmount, totalLiters),
    'isEmpty': totalOrders == 0,
  };
}

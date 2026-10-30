import 'dart:math' as math;

import '../../core/auth/permissions.dart';
import '../../core/models/json.dart';
import '../../core/models/me_access.dart';
import '../../core/network/fake/fake_personas.dart';
import '../../core/network/fake/fake_server.dart';
import '../../core/network/fake/fake_world.dart';
import '../../core/utils/format.dart';
import '../../core/utils/tr_time.dart';
import '../../core/utils/turkish_text.dart';
import 'data/stats_models.dart';

/// `GET stats/bayi` ve `GET stats/customer` sahteleri (spec R1 §4; sunucu kurallarının sade kopyası):
/// - bayi: `StationReports:Gorur` → kapsam `station`; saha satış (FieldSales) → `own` (yalnızca
///   portföyündeki cariler); müşteri / bayisi olmayan → 403 `forbidden`.
/// - müşteri: `CustomerSpending:Gorur` + şirket rolü Yönetici ya da Onaylayan; talep eden → 403.
/// - geçersiz `period` → 400 `validation`.
///
/// Veri deterministiktir: dünyadaki gerçek siparişler (onaylı / tamamlanan; huni için tümü) + bayi–cari
/// bağlantısı ve gün başına tohumlanmış (çalışma anında rastgelelik yok) sentetik geçmiş. Aynı gün aynı
/// sipariş defteri her personaya aynı görünür: bayinin "Anadolu Lojistik" satışı müşterinin harcamasıyla
/// tutarlıdır.
void registerStatsFakes(FakeServer s) {
  s.get('stats/bayi', StatsFake.handleBayi);
  s.get('stats/customer', StatsFake.handleCustomer);
}

StatsPeriod _period(FakeRequest req) {
  final raw = req.query('period')?.trim();
  if (raw == null || raw.isEmpty) return StatsPeriod.month;
  for (final p in StatsPeriod.values) {
    if (p.key.asciiLower == raw.asciiLower) return p;
  }
  throw FakeResponse.validation({
    'period': ['Dönem month, lastMonth, quarter ya da year olmalıdır.'],
  });
}

/// Dönem penceresi (Türkiye takvimi; bitişler hariç).
class StatsWindow {
  StatsWindow({
    required this.period,
    required this.from,
    required this.to,
    required this.compareFrom,
    required this.compareTo,
    required this.label,
    required this.compareLabel,
  });

  final StatsPeriod period;
  final DateTime from;
  final DateTime to;
  final DateTime compareFrom;
  final DateTime compareTo;
  final String label;
  final String compareLabel;

  /// Sunucu kuralları: bu ay = ayın 1'i → şimdi (önceki ayın aynı uzunluğu); geçen ay = tüm ay (bir
  /// önceki ay); son 3 ay = bugün − 89 gün → şimdi (önceki 90 gün); bu yıl = 1 Ocak → şimdi (geçen
  /// yılın aynı dönemi).
  factory StatsWindow.of(StatsPeriod period, DateTime now) {
    final w = TrTime.wall(now);
    switch (period) {
      case StatsPeriod.month:
        final from = TrTime.fromWall(w.year, w.month, 1);
        final cFrom = TrTime.fromWall(w.year, w.month - 1, 1);
        final span = now.difference(from);
        final cTo = cFrom.add(span).isAfter(from) ? from : cFrom.add(span);
        return StatsWindow(
          period: period,
          from: from,
          to: now,
          compareFrom: cFrom,
          compareTo: cTo,
          label: 'Bu ay',
          compareLabel: 'Geçen ayın aynı dönemi',
        );
      case StatsPeriod.lastMonth:
        return StatsWindow(
          period: period,
          from: TrTime.fromWall(w.year, w.month - 1, 1),
          to: TrTime.fromWall(w.year, w.month, 1),
          compareFrom: TrTime.fromWall(w.year, w.month - 2, 1),
          compareTo: TrTime.fromWall(w.year, w.month - 1, 1),
          label: 'Geçen ay',
          compareLabel: 'Önceki ay',
        );
      case StatsPeriod.quarter:
        final from = TrTime.fromWall(w.year, w.month, w.day - 89);
        return StatsWindow(
          period: period,
          from: from,
          to: now,
          compareFrom: TrTime.fromWall(w.year, w.month, w.day - 179),
          compareTo: from,
          label: 'Son 3 ay',
          compareLabel: 'Önceki 90 gün',
        );
      case StatsPeriod.year:
        final from = TrTime.fromWall(w.year, 1, 1);
        final cFrom = TrTime.fromWall(w.year - 1, 1, 1);
        return StatsWindow(
          period: period,
          from: from,
          to: now,
          compareFrom: cFrom,
          compareTo: cFrom.add(now.difference(from)),
          label: 'Bu yıl',
          compareLabel: 'Geçen yılın aynı dönemi',
        );
    }
  }

  /// `period` gövdesi (saf tarihler; bitiş günü dahil yazılır: gece yarısında biten aralığın son günü
  /// bir önceki gündür).
  JsonMap toJson() {
    String end(DateTime instant) => instant == TrTime.startOfDay(instant)
        ? TrTime.isoDate(instant.subtract(const Duration(seconds: 1)))
        : TrTime.isoDate(instant);
    return {
      'key': period.key,
      'label': label,
      'from': TrTime.isoDate(from),
      'to': end(to),
      'compareLabel': compareLabel,
      'compareFrom': TrTime.isoDate(compareFrom),
      'compareTo': end(compareTo),
    };
  }
}

/// Sipariş defteri olayı (onaylanan satış ya da sonuçlanmayan talep).
class _Ev {
  _Ev({
    required this.at,
    required this.stationId,
    required this.customerId,
    required this.productId,
    required this.pointId,
    required this.liters,
    required this.amount,
    required this.outcome,
    required this.quoted,
    required this.quoteMinutes,
    required this.onTime,
    this.rep,
  });

  final DateTime at;
  final int stationId;
  final int customerId;
  final int productId;
  final int pointId;
  final double liters;
  final double amount;

  /// 0 onaylandı (sayılır), 1 reddedildi, 2 süresi doldu, 3 açık.
  final int outcome;
  final bool quoted;
  final int quoteMinutes;
  final bool onTime;
  final String? rep;

  bool get accepted => outcome == 0;
}

/// Sentetik bayi–cari profili (günlük sipariş olasılığı, litre aralığı, ürün ve nokta ağırlıkları).
class _Profile {
  const _Profile(
    this.index,
    this.stationId,
    this.customerId,
    this.rate,
    this.minL,
    this.maxL,
    this.products,
    this.points,
    this.rep,
  );

  final int index;
  final int stationId;
  final int customerId;
  final double rate;
  final double minL;
  final double maxL;
  final List<(int, double)> products;
  final List<(int, double)> points;
  final String? rep;
}

const _profiles = [
  _Profile(
    0,
    1,
    101,
    0.42,
    6000,
    15000,
    [(1, 0.8), (2, 0.2)],
    [(1001, 0.7), (1002, 0.3)],
    null,
  ),
  _Profile(1, 1, 102, 0.32, 10000, 25000, [(1, 1)], [(1003, 1)], 'u-murat'),
  _Profile(
    2,
    1,
    103,
    0.22,
    3000,
    8000,
    [(1, 0.55), (3, 0.45)],
    [(1004, 1)],
    'u-saha',
  ),
  _Profile(
    3,
    1,
    104,
    0.30,
    5000,
    12000,
    [(1, 0.75), (2, 0.25)],
    [(1005, 1)],
    'u-saha',
  ),
  _Profile(4, 2, 101, 0.07, 5000, 10000, [(1, 1)], [(1001, 1)], null),
];

/// Saha temsilcileri (bayi 1; Selda Ak pasif).
const _reps = {'u-saha': 'Deniz Koç', 'u-murat': 'Murat Şen'};

/// Fiyat ve hacim için sabit dayanak ayı (Ekim 2026): geçmiş "şimdi"ye göre değişmez.
const _anchorMonth = 2026 * 12 + 9;

abstract final class StatsFake {
  /// `GET stats/bayi` işleyicisi (yetki + dönem doğrulaması + gövde; testler sarmalayabilir).
  static JsonMap handleBayi(FakeRequest req) {
    final p = req.requireUser();
    final period = _period(req);
    if (p.persona != Persona.bayi || p.stationId == null) {
      throw FakeResponse.forbidden();
    }
    final field = p.roles.contains(Roles.fieldSales);
    if (!field && !p.can(Pg.stationReports)) throw FakeResponse.forbidden();
    return bayi(req.world, p, period);
  }

  /// `GET stats/customer` işleyicisi.
  static JsonMap handleCustomer(FakeRequest req) {
    final p = req.requireUser();
    final period = _period(req);
    if (p.persona != Persona.customer || p.customerId == null) {
      throw FakeResponse.forbidden();
    }
    final role = p.customerUserRole ?? 3;
    if (!p.can(Pg.customerSpending) || role < 2) {
      throw FakeResponse.forbidden();
    }
    return customer(req.world, p, period);
  }

  /// `stats/bayi` gövdesi.
  static JsonMap bayi(
    FakeWorld w,
    FakePersona p,
    StatsPeriod period, {
    DateTime? now,
  }) {
    final at = (now ?? TrTime.now()).toUtc();
    final win = StatsWindow.of(period, at);
    final own = p.roles.contains(Roles.fieldSales);
    final stationId = p.stationId!;
    final portfolio = {
      for (final l in w.links)
        if (l['stationId'] == stationId && l['salesRepUserId'] == p.userId)
          l['customerId'] as int,
    };
    bool inScope(_Ev e) =>
        e.stationId == stationId && (!own || portfolio.contains(e.customerId));
    final months = _monthStarts(at, period == StatsPeriod.year ? 12 : 6);
    final start = _min(win.compareFrom, months.first);
    final book = _book(w, start, at).where(inScope).toList();
    final cur = _between(book, win.from, win.to);
    final prev = _between(book, win.compareFrom, win.compareTo);
    final accepted = cur.where((e) => e.accepted).toList();
    final amount = _sum(accepted, (e) => e.amount);
    final codes = p.bayiRoleCodes;
    // Ekip istatistiği: Bayi yöneticisi (`owner`), Satış müdürü ve pasif Bayi müdürü (roller v5: kodlar
    // korunur; sunucu `MobileStatsService` ham yetkinlikle sürer).
    final teamAll =
        !own &&
        (codes.contains(BayiRoleCodes.owner) ||
            codes.contains(BayiRoleCodes.manager) ||
            codes.contains(BayiRoleCodes.salesManager));
    return {
      'stationId': stationId,
      'stationTitle': w.stationTitle(stationId),
      'scope': own ? 'own' : 'station',
      'generatedAt': at.toIso8601String(),
      'period': win.toJson(),
      'sales': {
        ..._summary(cur, prev),
        'activeCustomers': accepted.map((e) => e.customerId).toSet().length,
        'newCustomers': 0,
      },
      'months': _months(book, months, at),
      'products': _products(w, accepted),
      'topCustomers': _topCustomers(w, accepted),
      'funnel': _funnel(cur),
      'deliveries': _deliveries(w, cur, at, (sh) {
        if (sh['stationId'] != stationId) return false;
        return !own || portfolio.contains(sh['customerId']);
      }),
      'collections': !own && p.can(Pg.stationPayments)
          ? _collections(
              stationId,
              win,
              accepted.length,
              amount,
              overdue: _overdueNow(w, stationId),
            )
          : null,
      'team': own
          ? [
              _teamRow(
                p.userId,
                _reps[p.userId] ?? p.displayName,
                accepted,
                win,
              ),
            ]
          : teamAll
          ? [
              for (final e in _reps.entries)
                _teamRow(e.key, e.value, accepted, win),
            ]
          : const <Object>[],
      'risk': !own && p.can(Pg.stationCustomers) ? _risk(w, stationId) : null,
      'failedSections': const <String>[],
    };
  }

  /// `stats/customer` gövdesi.
  static JsonMap customer(
    FakeWorld w,
    FakePersona p,
    StatsPeriod period, {
    DateTime? now,
  }) {
    final at = (now ?? TrTime.now()).toUtc();
    final win = StatsWindow.of(period, at);
    final customerId = p.customerId!;
    final months = _monthStarts(at, period == StatsPeriod.year ? 12 : 6);
    final start = _min(win.compareFrom, months.first);
    final book = _book(
      w,
      start,
      at,
    ).where((e) => e.customerId == customerId).toList();
    final cur = _between(book, win.from, win.to);
    final prev = _between(book, win.compareFrom, win.compareTo);
    final accepted = cur.where((e) => e.accepted).toList();
    final total = _sum(accepted, (e) => e.amount);
    final totalLiters = _sum(accepted, (e) => e.liters);

    List<JsonMap> group(
      int Function(_Ev e) key,
      JsonMap Function(int id, List<_Ev> rows, double share) row, {
      bool byLiters = false,
    }) {
      final by = <int, List<_Ev>>{};
      for (final e in accepted) {
        (by[key(e)] ??= []).add(e);
      }
      final out = [
        for (final g in by.entries)
          row(
            g.key,
            g.value,
            _round(
              byLiters
                  ? (totalLiters <= 0
                        ? 0
                        : _sum(g.value, (e) => e.liters) / totalLiters)
                  : (total <= 0 ? 0 : _sum(g.value, (e) => e.amount) / total),
              4,
            ),
          ),
      ];
      out.sort(
        (a, b) => ((b[byLiters ? 'liters' : 'amount'] as num)).compareTo(
          a[byLiters ? 'liters' : 'amount'] as num,
        ),
      );
      return out;
    }

    final shipments = [
      for (final sh in w.shipments)
        if (sh['customerId'] == customerId) sh,
    ];
    int countStatus(int s) => shipments.where((x) => x['status'] == s).length;
    final worldOrders = w.ordersOfCustomer(customerId);
    final deliveredWorld = shipments.where((x) {
      if (x['status'] != 2 && x['status'] != 3) return false;
      final d = TrTime.parseLocal(x['deliveredAt'] as String?);
      return d != null && !d.isBefore(win.from) && d.isBefore(win.to);
    }).length;
    final deliveredBook = accepted
        .where((e) => e.at.add(const Duration(days: 1)).isBefore(at))
        .length;

    return {
      'customerId': customerId,
      'customerTitle': w.customerTitle(customerId),
      'generatedAt': at.toIso8601String(),
      'period': win.toJson(),
      'spending': _summary(cur, prev),
      'months': _months(book, months, at),
      'products': _products(w, accepted),
      'stations': group(
        (e) => e.stationId,
        (id, rows, share) => {
          'stationId': id,
          'title': w.stationTitle(id) ?? 'Bayi',
          'liters': _sum(rows, (e) => e.liters),
          'amount': _round(_sum(rows, (e) => e.amount), 2),
          'share': share,
        },
      ),
      'deliveryPoints': group(
        (e) => e.pointId,
        (id, rows, share) => {
          'deliveryPointId': id,
          'name': w.deliveryPoint(id)?['name'] ?? 'Teslimat noktası',
          'city': w.deliveryPoint(id)?['city'],
          'liters': _sum(rows, (e) => e.liters),
          'amount': _round(_sum(rows, (e) => e.amount), 2),
          'share': share,
        },
        byLiters: true,
      ),
      'orders': {
        'awaitingQuote': worldOrders
            .where((o) => const {0, 1, 5}.contains(o['status']))
            .length,
        'awaitingDecision': worldOrders.where((o) => o['status'] == 2).length,
        'awaitingCompanyApproval': w.approvals
            .where(
              (a) =>
                  a['type'] == 3 &&
                  a['status'] == 0 &&
                  a['customerId'] == customerId,
            )
            .length,
        'inTransit': countStatus(1),
        'delivered': deliveredBook + deliveredWorld,
        'disputed': countStatus(4),
      },
      'limits': [
        for (final l in w.links)
          if (l['customerId'] == customerId) _limit(w, l),
      ],
      'failedSections': const <String>[],
    };
  }

  // ---------------------------------------------------------------- defter

  /// [from]–[to] arasındaki olaylar: dünyadaki siparişler + gün başına tohumlanmış geçmiş.
  static List<_Ev> _book(FakeWorld w, DateTime from, DateTime to) {
    final out = <_Ev>[];
    // Dünyadaki gerçek siparişler.
    for (final o in w.orders) {
      final created = TrTime.parseLocal(o['createdAt'] as String?);
      if (created == null || created.isBefore(from) || !created.isBefore(to)) {
        continue;
      }
      final status = (o['status'] as num?)?.toInt() ?? 0;
      final quotes = (o['quotes'] as List?)?.whereType<Map>().toList() ?? [];
      Map? selected;
      for (final q in quotes) {
        if (q['isSelected'] == true) selected = q;
      }
      final quote = selected ?? (quotes.isEmpty ? null : quotes.last);
      final amount =
          (quote?['totalAmountTry'] as num?)?.toDouble() ??
          (o['estimatedAmount'] as num?)?.toDouble() ??
          0;
      final firstQuote = quotes.isEmpty
          ? null
          : TrTime.parseLocal(quotes.first['createdAt'] as String?);
      final link = w.link(o['stationId'] as int, o['customerId'] as int);
      out.add(
        _Ev(
          at: created,
          stationId: o['stationId'] as int,
          customerId: o['customerId'] as int,
          productId: o['productId'] as int,
          pointId: o['deliveryPointId'] as int,
          liters: (o['quantityLiters'] as num?)?.toDouble() ?? 0,
          amount: amount,
          outcome: switch (status) {
            3 || 7 => 0,
            4 => 1,
            6 => 2,
            _ => 3,
          },
          quoted: quotes.isNotEmpty,
          quoteMinutes: firstQuote == null
              ? 0
              : math.max(1, firstQuote.difference(created).inMinutes),
          onTime: true,
          rep: link?['salesRepUserId'] as String?,
        ),
      );
    }
    // Tohumlanmış geçmiş (bugünün henüz gelmemiş saatleri hariç).
    var day = TrTime.startOfDay(from);
    var guard = 0;
    while (day.isBefore(to) && guard++ < 800) {
      final d = TrTime.wall(day);
      for (final prof in _profiles) {
        if (w.link(prof.stationId, prof.customerId) == null) continue;
        for (final e in _day(w, prof, d)) {
          if (!e.at.isBefore(from) && e.at.isBefore(to)) out.add(e);
        }
      }
      day = TrTime.fromWall(d.year, d.month, d.day + 1);
    }
    return out;
  }

  /// Bir profilin bir günlük olayları (tohum: gün + profil; aynı gün her zaman aynı sonuç).
  static List<_Ev> _day(FakeWorld w, _Profile prof, DateTime wall) {
    final key = wall.year * 10000 + wall.month * 100 + wall.day;
    final r = math.Random((key * 31 + prof.index * 7919) & 0x3fffffff);
    final month = wall.year * 12 + wall.month - 1;
    final winter = wall.month >= 11 || wall.month <= 3;
    final season = switch (wall.month) {
      6 || 7 || 8 => 1.1,
      1 || 2 => 0.92,
      _ => 1.0,
    };
    final growth = 1 + 0.005 * (month - _anchorMonth);
    final weekend = wall.weekday >= DateTime.saturday;
    final rate = prof.rate * season * growth * (weekend ? 0.35 : 1.15);
    final out = <_Ev>[];

    T pick<T>(List<(T, double)> options) {
      final total = options.fold<double>(0, (s, o) => s + o.$2);
      var x = r.nextDouble() * total;
      for (final o in options) {
        x -= o.$2;
        if (x <= 0) return o.$1;
      }
      return options.last.$1;
    }

    DateTime time() => TrTime.fromWall(
      wall.year,
      wall.month,
      wall.day,
      7 + r.nextInt(11),
      r.nextInt(60),
    );

    if (r.nextDouble() < rate) {
      final at = time();
      var product = pick(prof.products);
      // Kalorifer yakıtı yalnızca kışın.
      if (product == 3 && !winter) product = 1;
      final point = pick(prof.points);
      final liters =
          ((prof.minL + r.nextDouble() * (prof.maxL - prof.minL)) / 500)
              .round() *
          500.0;
      final list =
          (w.product(product)?['listPrice'] as num?)?.toDouble() ?? 42.0;
      final unit = _round(
        list * (1 + 0.003 * (month - _anchorMonth)) +
            (r.nextDouble() - 0.5) * 0.3,
        4,
      );
      out.add(
        _Ev(
          at: at,
          stationId: prof.stationId,
          customerId: prof.customerId,
          productId: product,
          pointId: point,
          liters: liters,
          amount: _round(liters * unit, 2),
          outcome: 0,
          quoted: true,
          quoteMinutes: 12 + r.nextInt(64),
          onTime: r.nextDouble() < 0.93,
          rep: prof.rep,
        ),
      );
    }
    if (r.nextDouble() < rate * 0.45) {
      final at = time();
      final x = r.nextDouble();
      final outcome = x < 0.35 ? 1 : (x < 0.65 ? 2 : 3);
      final quoted = outcome == 1 || r.nextBool();
      final liters =
          ((prof.minL + r.nextDouble() * (prof.maxL - prof.minL)) / 500)
              .round() *
          500.0;
      out.add(
        _Ev(
          at: at,
          stationId: prof.stationId,
          customerId: prof.customerId,
          productId: prof.products.first.$1,
          pointId: prof.points.first.$1,
          liters: liters,
          amount: 0,
          outcome: outcome,
          quoted: quoted,
          quoteMinutes: 15 + r.nextInt(70),
          onTime: true,
          rep: prof.rep,
        ),
      );
    }
    return out;
  }

  // ---------------------------------------------------------------- bölümler

  static JsonMap _summary(List<_Ev> cur, List<_Ev> prev) {
    final a = cur.where((e) => e.accepted).toList();
    final b = prev.where((e) => e.accepted).toList();
    final amount = _sum(a, (e) => e.amount);
    final liters = _sum(a, (e) => e.liters);
    final pAmount = _sum(b, (e) => e.amount);
    final pLiters = _sum(b, (e) => e.liters);
    return {
      'orders': a.length,
      'liters': liters,
      'amount': _round(amount, 2),
      'prevOrders': b.length,
      'prevLiters': pLiters,
      'prevAmount': _round(pAmount, 2),
      'avgUnitPrice': liters > 0 ? _round(amount / liters, 4) : null,
      'prevAvgUnitPrice': pLiters > 0 ? _round(pAmount / pLiters, 4) : null,
    };
  }

  static List<JsonMap> _months(
    List<_Ev> book,
    List<DateTime> starts,
    DateTime now,
  ) {
    final out = <JsonMap>[];
    for (var i = 0; i < starts.length; i++) {
      final from = starts[i];
      final w = TrTime.wall(from);
      final to = i + 1 < starts.length
          ? starts[i + 1]
          : TrTime.fromWall(w.year, w.month + 1, 1);
      final rows = book
          .where((e) => e.accepted && !e.at.isBefore(from) && e.at.isBefore(to))
          .toList();
      out.add({
        'year': w.year,
        'month': w.month,
        'label': Fmt.monthShort[w.month - 1],
        'orders': rows.length,
        'liters': _sum(rows, (e) => e.liters),
        'amount': _round(_sum(rows, (e) => e.amount), 2),
      });
    }
    return out;
  }

  static List<JsonMap> _products(FakeWorld w, List<_Ev> accepted) {
    final total = _sum(accepted, (e) => e.amount);
    final by = <int, List<_Ev>>{};
    for (final e in accepted) {
      (by[e.productId] ??= []).add(e);
    }
    final out = [
      for (final g in by.entries)
        {
          'productId': g.key,
          'name': w.product(g.key)?['name'] ?? 'Ürün',
          'liters': _sum(g.value, (e) => e.liters),
          'amount': _round(_sum(g.value, (e) => e.amount), 2),
          'share': total <= 0
              ? 0.0
              : _round(_sum(g.value, (e) => e.amount) / total, 4),
        },
    ]..sort((a, b) => (b['amount'] as num).compareTo(a['amount'] as num));
    return out.take(6).toList();
  }

  static List<JsonMap> _topCustomers(FakeWorld w, List<_Ev> accepted) {
    final total = _sum(accepted, (e) => e.amount);
    final by = <int, List<_Ev>>{};
    for (final e in accepted) {
      (by[e.customerId] ??= []).add(e);
    }
    final out = [
      for (final g in by.entries)
        {
          'customerId': g.key,
          'title': w.customerTitle(g.key) ?? 'Cari',
          'orders': g.value.length,
          'liters': _sum(g.value, (e) => e.liters),
          'amount': _round(_sum(g.value, (e) => e.amount), 2),
          'share': total <= 0
              ? 0.0
              : _round(_sum(g.value, (e) => e.amount) / total, 4),
        },
    ]..sort((a, b) => (b['amount'] as num).compareTo(a['amount'] as num));
    return out.take(5).toList();
  }

  static JsonMap _funnel(List<_Ev> cur) {
    final requests = cur.length;
    final accepted = cur.where((e) => e.accepted).length;
    final quoted = cur.where((e) => e.quoted).toList();
    return {
      'requests': requests,
      'quoted': quoted.length,
      'accepted': accepted,
      'rejected': cur.where((e) => e.outcome == 1).length,
      'expired': cur.where((e) => e.outcome == 2).length,
      'conversionRate': requests == 0 ? null : _round(accepted / requests, 4),
      'avgFirstQuoteMinutes': quoted.isEmpty
          ? null
          : (quoted.fold<int>(0, (s, e) => s + e.quoteMinutes) / quoted.length)
                .round(),
    };
  }

  static JsonMap _deliveries(
    FakeWorld w,
    List<_Ev> cur,
    DateTime now,
    bool Function(JsonMap shipment) inScope,
  ) {
    final delivered = cur
        .where(
          (e) => e.accepted && e.at.add(const Duration(days: 1)).isBefore(now),
        )
        .toList();
    final shipments = [
      for (final sh in w.shipments)
        if (inScope(sh)) sh,
    ];
    return {
      'delivered': delivered.length,
      'deliveredLiters': _sum(
        delivered,
        (e) => (e.liters * 0.997).roundToDouble(),
      ),
      'onTimeRate': delivered.isEmpty
          ? null
          : _round(
              delivered.where((e) => e.onTime).length / delivered.length,
              4,
            ),
      'inTransit': shipments.where((x) => x['status'] == 1).length,
      'planned': shipments.where((x) => x['status'] == 0).length,
      'disputes': shipments.where((x) => x['status'] == 4).length,
    };
  }

  /// Bayinin şu an vadesi geçmiş ödemeleri (ana sayfanın "Vadesi geçen n ödeme"si ve Tahsilat'ın
  /// gecikenleri ile aynı kural; v4 tur 2): onaylı ya da tamamlanmış sipariş, ödeme bekliyor ya da
  /// kısmi, son ödeme günü bugünden önce. Destenin Tahsilat kartı başka bir sayı söylemez.
  static ({int count, double amount}) _overdueNow(FakeWorld w, int stationId) {
    final today = TrTime.todayStart();
    var count = 0;
    var total = 0.0;
    for (final o in w.ordersOfStation(stationId)) {
      final pay = o['paymentStatus'];
      final st = o['status'];
      final due = TrTime.parseLocal(o['paymentDueDate'] as String?);
      if ((pay != 1 && pay != 2) || (st != 3 && st != 7)) continue;
      if (due == null || !due.isBefore(today)) continue;
      final quotes = ((o['quotes'] as List?) ?? const []).cast<JsonMap>();
      final quote =
          quotes.where((q) => q['isSelected'] == true).firstOrNull ??
          quotes.lastOrNull;
      count++;
      total +=
          (quote?['totalAmountTry'] as num?)?.toDouble() ??
          (o['estimatedAmount'] as num?)?.toDouble() ??
          0;
    }
    return (count: count, amount: total);
  }

  static JsonMap _collections(
    int stationId,
    StatsWindow win,
    int orders,
    double amount, {
    ({int count, double amount})? overdue,
  }) {
    final w = TrTime.wall(win.from);
    final r = math.Random(
      stationId * 1000003 + w.year * 400 + w.month * 31 + win.period.index,
    );
    if (amount <= 0) {
      return {
        'collectedAmount': 0.0,
        'collectedCount': 0,
        'overdueAmount': 0.0,
        'overdueCount': 0,
        'dueSoonAmount': 0.0,
        'dueSoonCount': 0,
        'dueSoonDays': 7,
      };
    }
    return {
      'collectedAmount': _round(amount * (0.74 + r.nextDouble() * 0.08), 2),
      'collectedCount': (orders * 0.82).round(),
      'overdueAmount':
          overdue?.amount ?? _round(amount * (0.03 + r.nextDouble() * 0.03), 2),
      'overdueCount': overdue?.count ?? 2 + r.nextInt(4),
      'dueSoonAmount': _round(amount * (0.05 + r.nextDouble() * 0.04), 2),
      'dueSoonCount': 3 + r.nextInt(5),
      'dueSoonDays': 7,
    };
  }

  static JsonMap _teamRow(
    String userId,
    String name,
    List<_Ev> accepted,
    StatsWindow win,
  ) {
    final mine = accepted.where((e) => e.rep == userId).toList();
    final w = TrTime.wall(win.from);
    final r = math.Random(
      userId.codeUnits.fold<int>(7, (h, c) => (h * 31 + c) & 0xffffff) +
          w.year * 400 +
          w.month * 31 +
          win.period.index,
    );
    final converted = (mine.length * 0.8).round();
    return {
      'userId': userId,
      'name': name,
      'forms': converted + 1 + r.nextInt(4),
      'converted': converted,
      'liters': _sum(mine, (e) => e.liters),
    };
  }

  static JsonMap _risk(FakeWorld w, int stationId) {
    final rows = <JsonMap>[];
    for (final l in w.links) {
      if (l['stationId'] != stationId) continue;
      final limit = (l['limitAmount'] as num?)?.toDouble();
      final used = (l['used'] as num?)?.toDouble() ?? 0;
      if (limit == null || limit <= 0) continue;
      final rate = used / limit;
      if (rate < 0.8) continue;
      rows.add({
        'customerId': l['customerId'],
        'title': w.customerTitle(l['customerId'] as int?) ?? 'Cari',
        'usageRate': _round(rate, 4),
      });
    }
    rows.sort(
      (a, b) => (b['usageRate'] as num).compareTo(a['usageRate'] as num),
    );
    return {'nearLimitCount': rows.length, 'nearLimit': rows};
  }

  static JsonMap _limit(FakeWorld w, JsonMap l) {
    final limit = (l['limitAmount'] as num?)?.toDouble();
    final used = (l['used'] as num?)?.toDouble() ?? 0;
    final liters = l['limitType'] == 'Litre';
    return {
      'stationId': l['stationId'],
      'stationTitle': w.stationTitle(l['stationId'] as int?) ?? 'Bayi',
      'limit': limit,
      'used': used,
      'available': limit == null ? null : math.max(0.0, limit - used),
      'usageRate': limit == null || limit <= 0 ? null : _round(used / limit, 4),
      'unit': liters ? 'L' : 'TL',
    };
  }

  // ---------------------------------------------------------------- yardımcılar

  /// [count] takvim ayının başları (eskiden yeniye, sonuncusu bu ay).
  static List<DateTime> _monthStarts(DateTime now, int count) {
    final w = TrTime.wall(now);
    return [
      for (var i = count - 1; i >= 0; i--)
        TrTime.fromWall(w.year, w.month - i, 1),
    ];
  }

  static List<_Ev> _between(List<_Ev> book, DateTime from, DateTime to) => [
    for (final e in book)
      if (!e.at.isBefore(from) && e.at.isBefore(to)) e,
  ];

  static double _sum(Iterable<_Ev> rows, double Function(_Ev e) f) =>
      rows.fold<double>(0, (s, e) => s + f(e));

  static double _round(double v, int digits) {
    final f = math.pow(10, digits).toDouble();
    return (v * f).round() / f;
  }

  static DateTime _min(DateTime a, DateTime b) => a.isBefore(b) ? a : b;
}

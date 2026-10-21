import 'dart:math';

import '../../../core/models/enums.dart';
import '../../../core/models/json.dart';
import '../../../core/network/fake/fake_personas.dart';
import '../../../core/network/fake/fake_world.dart';
import '../../../core/utils/tr_time.dart';
import 'fake_support.dart';
import 'seed.dart';

/// Sahte sipariş hesapları (sunucu kurallarının sade karşılıkları).

const openOrderStatuses = {0, 1, 2, 5};

int st(JsonMap o) => (o['status'] as num?)?.toInt() ?? -1;
int fin(JsonMap o) => (o['financeStatus'] as num?)?.toInt() ?? 0;
int pay(JsonMap o) => (o['paymentStatus'] as num?)?.toInt() ?? 0;
double qty(JsonMap o) => (o['quantityLiters'] as num?)?.toDouble() ?? 0;

/// Finans kararı bekliyor (Pending / InfoRequested).
bool financeHeld(JsonMap o) => fin(o) == 1 || fin(o) == 4;

/// Teklifler sürüm sırasıyla.
List<JsonMap> quotesOf(JsonMap o) {
  final list = [
    for (final q in (o['quotes'] as List? ?? const []))
      if (q is Map) JsonReader.asMap(q),
  ]..sort((a, b) => (a['version'] as num).compareTo(b['version'] as num));
  return list;
}

/// Geçerli teklif: seçili ya da en son sürüm.
JsonMap? currentQuote(JsonMap o) {
  final qs = quotesOf(o);
  if (qs.isEmpty) return null;
  for (final q in qs) {
    if (q['isSelected'] == true) return q;
  }
  return qs.last;
}

/// Süre dolumu açıkken süresi geçmiş açık sipariş.
bool isExpired(FakeWorld w, JsonMap o) {
  if (!expiryEnabled(w) || !openOrderStatuses.contains(st(o))) return false;
  final e = local(o['expiresAt']);
  return e != null && e.isBefore(TrTime.now());
}

/// Sevkiyat hesapları (iptal edilenler sayılmaz).
({double allocated, double accepted, int open}) shipmentTotals(
  FakeWorld w,
  int orderId,
) {
  var allocated = 0.0;
  var accepted = 0.0;
  var open = 0;
  for (final s in w.shipmentsOfOrder(orderId)) {
    final status = (s['status'] as num).toInt();
    if (status == 5) continue;
    final planned = (s['plannedLiters'] as num).toDouble();
    final delivered = (s['deliveredLiters'] as num?)?.toDouble();
    if (status == 3) {
      allocated += delivered ?? planned;
      accepted += delivered ?? planned;
    } else {
      allocated += planned;
      if (status == 0 || status == 1 || status == 4) open++;
    }
  }
  return (allocated: allocated, accepted: accepted, open: open);
}

/// Planlanabilir kalan litre (yalnızca onaylı siparişte).
double remainingLiters(FakeWorld w, JsonMap o) {
  if (st(o) != 3) return 0;
  final rest = qty(o) - shipmentTotals(w, o['id'] as int).allocated;
  return rest <= 0.0005 ? 0 : double.parse(rest.toStringAsFixed(3));
}

/// `BayiShipmentStates` önceliği: disputed > reported > inTransit > planned > delivered / partial > none.
String shipmentState(FakeWorld w, JsonMap o) {
  final ships = [
    for (final s in w.shipmentsOfOrder(o['id'] as int))
      if (s['status'] != 5) (s['status'] as num).toInt(),
  ];
  if (ships.isEmpty) return 'none';
  if (ships.contains(4)) return 'disputed';
  if (ships.contains(2)) return 'reported';
  if (ships.contains(1)) return 'inTransit';
  if (ships.contains(0)) return 'planned';
  final accepted = shipmentTotals(w, o['id'] as int).accepted;
  return accepted + 0.0005 >= qty(o) ? 'delivered' : 'partial';
}

const shipmentStateLabels = {
  'none': 'Sevkiyat yok',
  'planned': 'Planlandı',
  'inTransit': 'Yolda',
  'reported': 'Kabul bekliyor',
  'disputed': 'İtirazlı',
  'partial': 'Kısmi teslim',
  'delivered': 'Teslim alındı',
};

/// Ekrandaki ödeme durumu: kapanmış (reddedilen / süresi dolan) siparişin tahsil edilmemiş ödemesi "İptal".
int effectivePayment(JsonMap o) {
  final p = pay(o);
  if ((st(o) == 4 || st(o) == 6) && (p == 1 || p == 2)) return 6;
  return p;
}

/// Siparişin segmentleri (`BayiOrderSegments`).
Set<String> segmentsOf(FakeWorld w, JsonMap o) {
  final s = st(o);
  final f = fin(o);
  final out = <String>{};
  if (s == 1 && !{1, 4, 5}.contains(f)) out.add('awaitingQuote');
  if (s == 5 && !{1, 4, 5}.contains(f)) out.add('revisionRequested');
  if (s == 2 && !{1, 4}.contains(f)) out.add('awaitingCustomer');
  if (openOrderStatuses.contains(s) && {1, 4}.contains(f)) {
    out.add('financeHeld');
  }
  if (s == 3 && remainingLiters(w, o) > 0) out.add('toPlan');
  final ships = [
    for (final x in w.shipmentsOfOrder(o['id'] as int))
      (x['status'] as num).toInt(),
  ];
  if (ships.contains(1)) out.add('inTransit');
  if (ships.contains(2)) out.add('reported');
  if (ships.contains(4)) out.add('disputed');
  if ((s == 3 || s == 7) && (pay(o) == 1 || pay(o) == 2)) {
    out.add('paymentPending');
  }
  return out;
}

/// `BayiOrderRowDto`.
JsonMap bayiOrderRow(FakeWorld w, JsonMap o) {
  final q = currentQuote(o);
  final s = st(o);
  final expires = local(o['expiresAt']);
  final showExpiry = expiryEnabled(w) && openOrderStatuses.contains(s);
  final state = shipmentState(w, o);
  final eff = effectivePayment(o);
  return {
    'id': o['id'],
    'orderNumber': o['orderNumber'],
    'status': s,
    'statusLabel': OrderStatus.fromCode(s).label,
    'customerId': o['customerId'],
    'customerTitle': o['customerTitle'],
    'productName': o['productName'],
    'quantityLiters': qty(o),
    'requestedDeliveryDate': offset(local(o['requestedDeliveryDate'])),
    'expiresAt': showExpiry ? offset(expires) : null,
    'unitPrice': q?['unitPriceTry'],
    'totalAmount': q?['totalAmountTry'],
    'paymentMethodCode': o['paymentMethodCode'],
    'paymentMethodName': o['paymentMethodName'],
    'paymentStatus': eff,
    'paymentStatusLabel': PaymentStatus.fromCode(eff).label,
    'financeStatus': fin(o),
    'financeLabel': OrderFinanceStatus.fromCode(fin(o)).label,
    'shipmentState': state,
    'shipmentStateLabel': shipmentStateLabels[state],
    'createdAt': offset(local(o['createdAt'])),
    'productId': o['productId'],
    'deliveryPointName': o['deliveryPointName'],
    'deliveryCity': o['deliveryCity'],
    'quoteVersion': q?['version'],
    'paymentDueDate': offset(local(o['paymentDueDate'])),
    'acceptedLiters': shipmentTotals(w, o['id'] as int).accepted,
    'remainingLiters': remainingLiters(w, o),
  };
}

/// `OrderDetailDto` (eski uç; tarihler ofsetsiz Türkiye yerel).
JsonMap orderDetailDto(JsonMap o) {
  final q = currentQuote(o);
  final latest = quotesOf(o).lastOrNull;
  return {
    'id': o['id'],
    'orderNumber': o['orderNumber'],
    'status': st(o),
    'statusDisplay': OrderStatus.fromCode(st(o)).label,
    'quantityLiters': qty(o),
    'requestedDeliveryDate': o['requestedDeliveryDate'],
    'expiresAt': o['expiresAt'],
    'createdAt': o['createdAt'],
    'productName': o['productName'],
    'customerTitle': o['customerTitle'],
    'stationTitle': o['stationTitle'],
    'deliveryPointName': o['deliveryPointName'],
    'latestUnitPriceTry': q?['unitPriceTry'],
    'latestTotalAmountTry': q?['totalAmountTry'],
    'latestRevisionNote': latest?['revisionNote'],
    'customerId': o['customerId'],
    'stationId': o['stationId'],
    'productId': o['productId'],
    'deliveryPointId': o['deliveryPointId'],
    'deliveryAddress': o['deliveryAddress'],
    'quotes': quotesOf(o),
    'paymentMethodCode': o['paymentMethodCode'],
    'paymentTermDays': o['paymentTermDays'],
    'paymentDueDate': o['paymentDueDate'],
    'paymentInstallments': o['paymentInstallments'],
    'paymentDetailJson': o['paymentDetailJson'],
    'paymentStatus': pay(o),
    'paymentGroupKey': o['paymentGroupKey'],
    'estimatedAmount': o['estimatedAmount'],
    'financeStatus': fin(o),
    'financeReasons': o['financeReasons'],
    'financeApprovalRequestId': o['financeApprovalRequestId'],
  };
}

/// Durum geçmişi: tohum verisinden türetilir + bu oturumdaki bayi işlemleri.
List<JsonMap> timelineOf(FakeWorld w, JsonMap o) {
  final events = <({DateTime at, int from, int to, String? note})>[];
  final created = local(o['createdAt']) ?? TrTime.now();
  events.add((at: created, from: 0, to: 1, note: null));
  final qs = quotesOf(o);
  for (var i = 0; i < qs.length; i++) {
    final q = qs[i];
    final at = local(q['createdAt']) ?? created;
    events.add((at: at, from: i == 0 ? 1 : 5, to: 2, note: null));
    final note = q['revisionNote'] as String?;
    if (note != null && note.isNotEmpty) {
      final next = i + 1 < qs.length ? local(qs[i + 1]['createdAt']) : null;
      final revAt =
          next?.subtract(const Duration(minutes: 30)) ??
          at.add(const Duration(hours: 1));
      events.add((at: revAt, from: 2, to: 5, note: note));
    }
  }
  final s = st(o);
  final selected = currentQuote(o);
  final selAt = local(selected?['createdAt']) ?? created;
  if (s == 3 || s == 7) {
    events.add((
      at: selAt.add(const Duration(minutes: 40)),
      from: 2,
      to: 3,
      note: null,
    ));
  }
  if (s == 7) {
    DateTime? last;
    for (final sh in w.shipmentsOfOrder(o['id'] as int)) {
      final a = local(sh['acceptedAt']);
      if (a != null && (last == null || a.isAfter(last))) last = a;
    }
    events.add((
      at: last ?? selAt.add(const Duration(days: 1)),
      from: 3,
      to: 7,
      note: 'Tüm litre müşteri tarafından teslim alındı.',
    ));
  }
  if (s == 4) {
    events.add((
      at: selAt.add(const Duration(hours: 1)),
      from: qs.isEmpty ? 1 : 2,
      to: 4,
      note: null,
    ));
  }
  if (s == 6) {
    events.add((
      at: local(o['expiresAt']) ?? created,
      from: qs.isEmpty ? 1 : 2,
      to: 6,
      note: 'Süre doldu.',
    ));
  }
  final extra =
      w.bag<Map<int, List<JsonMap>>>(BayiBags.timeline, () => {})[o['id']] ??
      const [];
  final out =
      [
        for (final e in events)
          {
            'fromStatus': e.from,
            'toStatus': e.to,
            'note': e.note,
            'changedByUserId': null,
            'changedAt': legacy(e.at),
          },
        ...extra,
      ]..sort(
        (a, b) => (local(a['changedAt']) ?? created).compareTo(
          local(b['changedAt']) ?? created,
        ),
      );
  return out;
}

/// Bayi işlemiyle oluşan durum geçişi (zaman çizelgesine).
void addTimeline(
  FakeWorld w,
  JsonMap o,
  int from,
  int to,
  String userId, {
  String? note,
}) {
  final map = w.bag<Map<int, List<JsonMap>>>(BayiBags.timeline, () => {});
  (map[o['id'] as int] ??= []).add({
    'fromStatus': from,
    'toStatus': to,
    'note': note,
    'changedByUserId': userId,
    'changedAt': legacy(TrTime.now()),
  });
}

/// Teklif ekler (sürüm +1) ve durumu "Onay bekleniyor" yapar. Sunucu gibi (`SubmitQuoteAsync`) yeni
/// teklif seçili kaydedilir, öncekilerin seçimi kalkar; revize, ret ve süre dolumu seçimi değiştirmez.
JsonMap addQuote(
  FakeWorld w,
  JsonMap o,
  double unitPrice,
  DateTime deliveryDay,
) {
  final qs = quotesOf(o);
  final version = qs.isEmpty ? 1 : (qs.last['version'] as num).toInt() + 1;
  for (final old in qs) {
    old['isSelected'] = false;
  }
  final q = w.newQuote(
    id: w.nextId('quote', start: 30001),
    version: version,
    unitPrice: unitPrice,
    liters: qty(o),
    deliveryDate: deliveryDay,
    createdAt: TrTime.now(),
    selected: true,
  );
  o['quotes'] = [...qs, q];
  o['status'] = 2;
  return q;
}

/// Limit aşımı (Tutar limiti): teklif tutarı + kullanım > limit.
bool exceedsLimit(FakeWorld w, JsonMap o, double total) {
  final link = w.link(o['stationId'] as int, o['customerId'] as int);
  if (link == null) return false;
  final limit = (link['limitAmount'] as num?)?.toDouble();
  if (limit == null) return false;
  final used = (link['used'] as num?)?.toDouble() ?? 0;
  if (link['limitType'] == 'Litre') return used + qty(o) > limit;
  return used + total > limit;
}

/// Teklif limit aşımında: sipariş finans onayına (teklif kaydedilmez), onay talebi açılır.
void routeToFinance(FakeWorld w, JsonMap o, double total, FakePersona actor) {
  o['financeStatus'] = 1;
  o['financeReasons'] =
      'Teklif tutarı cari limitini aşıyor (${_money(total)}).';
  final id = w.nextId('approval', start: 9001);
  final now = DateTime.now().toUtc();
  w.approvals.add({
    'id': id,
    'type': 4,
    'status': 0,
    'isMirror': false,
    'stationId': o['stationId'],
    'stationTitle': o['stationTitle'],
    'customerId': o['customerId'],
    'customerTitle': o['customerTitle'],
    'subjectType': 'Order',
    'subjectId': o['id'],
    'subjectNumber': o['orderNumber'],
    'title': 'Sipariş finans onayı',
    'summary': 'Teklif tutarı cari limitini aşıyor',
    'amount': total,
    'liters': qty(o),
    'requestedByUserId': actor.userId,
    'requestedByName': actor.displayName,
    'createdAt': now.toIso8601String(),
    'dueAt': now.add(const Duration(hours: 8)).toIso8601String(),
    'slaState': 1,
    'currentLevelNo': 1,
    'levelCount': 1,
    'eligibleUserIds': ['u-finans', 'u-mudur', 'u-sahip'],
  });
  o['financeApprovalRequestId'] = id;
  notify(
    w,
    userIds: const ['u-finans', 'u-mudur', 'u-sahip'],
    actorId: actor.userId,
    category: 'approvals',
    eventCode: 'approval.pending',
    title: 'Finans onayı bekliyor',
    body: '${o['orderNumber']}: teklif cari limitini aşıyor',
    route: '/approvals/$id',
    severity: 2,
    entityType: 'ApprovalRequest',
    entityId: id,
  );
}

/// Sunucunun limit aşımı yönlendirme metni (bayinin tekil teklifi; `RouteLimitOverrunToFinanceAsync`).
String limitRoutedMessage(FakeWorld w, JsonMap o, double total) {
  final link = w.link(o['stationId'] as int, o['customerId'] as int);
  final limit = (link?['limitAmount'] as num?)?.toDouble() ?? 0;
  final used = (link?['used'] as num?)?.toDouble() ?? 0;
  final litre = link?['limitType'] == 'Litre';
  final available = (limit - used) < 0 ? 0.0 : limit - used;
  final unit = litre ? 'L' : 'TL';
  final availableText = litre
      ? '${_money(available).replaceAll(' ₺', '')} $unit'
      : _money(available).replaceAll('₺', unit);
  return 'Teklif tutarı (${_money(total).replaceAll('₺', 'TL')}) cari limitini aşıyor '
      '(kullanılabilir $availableText); sipariş finans onayına gönderildi. '
      'Finans onaylayınca teklifi yeniden girin.';
}

String _money(double v) {
  final s = v.toStringAsFixed(0);
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '$b ₺';
}

/// Sunucunun `QuoteDeskRules.Validate` karşılığı. Geçerliyse null.
String? validateQuote(double? price, DateTime? day) {
  if (price == null) return 'Birim fiyat girin.';
  if (price <= 0) return 'Birim fiyat sıfırdan büyük olmalı.';
  if (price > 999999) return 'Birim fiyat en fazla 999.999 TL/L olabilir.';
  final scaled = price * 10000;
  if ((scaled - scaled.roundToDouble()).abs() > 1e-6) {
    return 'Birim fiyat en fazla 4 ondalık basamak içerebilir.';
  }
  if (day == null) return 'Teslim tarihi girin.';
  final today = TrTime.todayStart();
  final diff = TrTime.dayDiff(today, day);
  if (diff < 0) return 'Teslim tarihi bugünden önce olamaz.';
  if (diff > 365) return 'Teslim tarihi en fazla bir yıl sonrası olabilir.';
  return null;
}

/// Teklif verilebilirlik (masa ve tekil teklif): sorun yoksa null, varsa Türkçe neden.
String? quotableProblem(FakeWorld w, JsonMap o) {
  if (st(o) != 1 && st(o) != 5) return 'Bu sipariş için teklif verilemez.';
  if (financeHeld(o)) return 'Sipariş finans onayında; teklif verilemez.';
  if (fin(o) == 5) return 'Sipariş finans tarafından reddedildi.';
  if (isExpired(w, o)) return 'Siparişin süresi doldu; teklif verilemez.';
  return null;
}

/// Müşteri kullanıcılarına "Teklif hazır".
void notifyQuoteReady(FakeWorld w, JsonMap o, FakePersona actor, double price) {
  notify(
    w,
    userIds: customerUsersWith(o['customerId'] as int, 'CustomerQuotes'),
    actorId: actor.userId,
    category: 'quotes',
    eventCode: 'order.quote_ready',
    title: 'Teklif hazır',
    body: '${o['orderNumber']}: teklif verildi. Süresi dolmadan karar verin.',
    route: '/orders/${o['id']}',
    severity: 1,
    entityType: 'Order',
    entityId: o['id'] as int,
  );
}

/// Son alım fiyatları: bu carinin bu bayiden bu üründe onaylanan siparişleri (yeniden eskiye, ≤ 3).
List<JsonMap> recentPricesFor(FakeWorld w, JsonMap o) {
  final list =
      [
        for (final x in w.orders)
          if (x['id'] != o['id'] &&
              x['stationId'] == o['stationId'] &&
              x['customerId'] == o['customerId'] &&
              x['productId'] == o['productId'] &&
              (st(x) == 3 || st(x) == 7) &&
              currentQuote(x) != null)
            x,
      ]..sort(
        (a, b) => (local(b['createdAt']) ?? TrTime.now()).compareTo(
          local(a['createdAt']) ?? TrTime.now(),
        ),
      );
  return [
    for (final x in list.take(3))
      {
        'orderId': x['id'],
        'orderNumber': x['orderNumber'],
        'orderDate': offset(local(x['createdAt'])),
        'quantityLiters': qty(x),
        'unitPriceTry': currentQuote(x)!['unitPriceTry'],
      },
  ];
}

/// Önerilen fiyat: son alım → önceki teklif → liste fiyatı.
({double? price, String? source, String? label}) suggestionFor(
  FakeWorld w,
  JsonMap o,
) {
  final recent = recentPricesFor(w, o);
  if (recent.isNotEmpty) {
    return (
      price: (recent.first['unitPriceTry'] as num).toDouble(),
      source: 'last',
      label: 'son alım fiyatı',
    );
  }
  final latest = quotesOf(o).lastOrNull;
  if (latest != null) {
    return (
      price: (latest['unitPriceTry'] as num).toDouble(),
      source: 'prev',
      label: 'önceki teklif',
    );
  }
  final list = (w.product(o['productId'] as int?)?['listPrice'] as num?)
      ?.toDouble();
  return (
    price: list,
    source: list == null ? null : 'list',
    label: list == null ? null : 'liste fiyatı',
  );
}

/// Ödeme çipi (web `QuoteDeskPaymentChip`).
JsonMap? payChipFor(JsonMap o) {
  final code = o['paymentMethodCode'] as String?;
  if (code == null) return null;
  final name = o['paymentMethodName'] as String? ?? code;
  final term = (o['paymentTermDays'] as num?)?.toInt();
  final due = local(o['paymentDueDate']);
  final parts = [
    name,
    if (term != null && term > 0) '$term gün',
    if (due != null) 'vade ${_date(due)}',
  ];
  final p = pay(o);
  final f = fin(o);
  return {
    'line': parts.join(' · '),
    'methodName': name,
    'statusLabel': PaymentStatus.fromCode(p).label,
    'tone': switch (p) {
      1 => 'warn',
      2 => 'info',
      3 => 'ok',
      4 => 'danger',
      _ => 'neutral',
    },
    'financeLabel': f == 0 ? null : OrderFinanceStatus.fromCode(f).label,
    'financeTone': switch (f) {
      2 || 3 => 'ok',
      1 => 'warn',
      4 => 'info',
      5 => 'danger',
      _ => 'neutral',
    },
  };
}

String _date(DateTime d) {
  final w = TrTime.wall(d);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(w.day)}.${two(w.month)}.${w.year}';
}

/// Uygun şoför mü (aynı bayi, aktif; şoför rolü ya da sevkiyat düzenleyen personel).
bool eligibleDriver(FakeWorld w, int stationId, String userId) {
  for (final row in stationStaff(w, stationId)) {
    if (row['userId'] != userId) continue;
    if (row['isActive'] != true) return false;
    final codes = (row['roleCodes'] as List).cast<String>();
    if (codes.contains('driver')) return true;
    final p = findFakePersona(userId);
    return p != null && p.can('StationShipments', 'Duzenler');
  }
  return false;
}

double roundTo(double v, int digits) {
  final m = pow(10, digits).toDouble();
  return (v * m).roundToDouble() / m;
}

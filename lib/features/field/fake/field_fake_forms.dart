import 'dart:math';

import '../../../core/auth/permissions.dart';
import '../../../core/models/json.dart';
import '../../../core/network/fake/fake_personas.dart';
import '../../../core/network/fake/fake_server.dart';
import '../../../core/network/fake/fake_world.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import 'field_fake_state.dart';

/// Saha formu sahte uçları (spec B.9 + B.15): liste, ayrıntı, taslak, önizleme (barem bandı), gönderim,
/// iptal, dönüşüm, belge, e-posta, seçenekler, tedarik önerileri, temsilciler, portföy.
void registerFieldFormFakes(FakeServer s) {
  FieldFakeState st(FakeRequest r) {
    final state = FieldFakeState.of(r.world);
    _syncFromApprovals(state);
    return state;
  }

  void needFields(FakeRequest r, [String perm = Perm.view]) =>
      r.requirePage(Pg.stationFieldOrders, perm);

  // ─────────────────────────────────────────────────────────── Liste ve ayrıntı

  s.get('field-orders', (r) {
    needFields(r);
    final p = r.requireUser();
    final state = st(r);
    final skip = max(0, r.queryInt('skip') ?? 0);
    final take = (r.queryInt('take') ?? 25).clamp(1, 100);
    final statuses = r
        .queryAll('statuses')
        .map(int.tryParse)
        .whereType<int>()
        .toSet();
    final rep = r.queryInt('salesRepresentativeId');
    final level = r.queryInt('requiredApprovalLevel');
    final customer = r.queryInt('customerId');
    final q = r.query('search') ?? '';
    final from = TrTime.parseUtc(r.query('fromUtc'));
    final costs = FieldFakeState.showCosts(p);
    final rows =
        [
          for (final f in state.forms)
            if (state.canSeeForm(p, f) &&
                (statuses.isEmpty || statuses.contains(f['status'])) &&
                (rep == null || f['_repId'] == rep) &&
                (level == null || f['requiredApprovalLevel'] == level) &&
                (customer == null || f['customerId'] == customer) &&
                (from == null ||
                    (TrTime.parseUtc(
                          f['createdAt'] as String?,
                        )?.isAfter(from) ??
                        false)) &&
                (q.isEmpty ||
                    TurkishText.matches(f['formNumber'] as String?, q) ||
                    TurkishText.matches(f['customerTitle'] as String?, q)))
              f,
        ]..sort(
          (a, b) =>
              (b['createdAt'] as String).compareTo(a['createdAt'] as String),
        );
    return {
      'items': [for (final f in rows.skip(skip).take(take)) _row(f, costs)],
      'totalCount': rows.length,
      'includeCosts': costs,
    };
  });

  s.get('field-orders/{id:int}', (r) {
    needFields(r);
    final p = r.requireUser();
    final state = st(r);
    final f = _find(state, p, r.intParam('id'));
    return {
      'form': _formJson(state, f, p),
      'orders': [
        for (final l in (f['lines'] as List).cast<JsonMap>())
          if (l['orderId'] != null)
            {
              'lineId': l['id'],
              'orderId': l['orderId'],
              'orderNumber':
                  r.world.order(l['orderId'] as int)?['orderNumber'] ??
                  l['orderNumber'],
              'status': r.world.order(l['orderId'] as int)?['status'] ?? 2,
            },
      ],
    };
  });

  // ─────────────────────────────────────────────────────────── Taslak

  s.post('field-orders', (r) {
    needFields(r, Perm.create);
    final p = r.requireUser();
    final state = st(r);
    final body = r.json;
    final customerId = body.integer('customerId');
    state.ensureCustomer(p, customerId);
    if (FieldFakeState.isFieldSales(p) && state.repOf(p) == null) {
      throw FakeResponse.business(
        'Satış temsilcisi kaydınız yok; bayi yöneticinizden portföy ataması isteyin.',
      );
    }
    final lines = _linesFrom(state, body, customerId);
    final form = state.newForm(
      id: state.nextFormId(),
      number: state.nextFormNumber(),
      customerId: customerId,
      createdBy: p.userId,
      repId: state.repOf(p)?['id'] as int?,
      lines: lines,
      createdAt: DateTime.now().toUtc(),
    );
    _applyHeader(form, body, p);
    state.forms.add(form);
    return FakeResponse.created(_formJson(state, form, p));
  });

  s.put('field-orders/{id:int}', (r) {
    needFields(r, Perm.edit);
    final p = r.requireUser();
    final state = st(r);
    final f = _find(state, p, r.intParam('id'));
    if (f['status'] != 0) {
      throw FakeResponse.business('Yalnızca taslak form düzenlenebilir.');
    }
    if (FieldFakeState.isFieldSales(p) && f['_createdBy'] != p.userId) {
      throw FakeResponse.business(
        'Bu formu yalnızca oluşturan ya da bayi yöneticisi düzenleyebilir.',
      );
    }
    final body = r.json;
    final token = body.nonEmpty('concurrencyToken');
    if (token != null && token != f['concurrencyToken']) {
      throw FakeResponse.business(
        'Form bu arada başka biri tarafından değiştirildi. Sayfayı yenileyip tekrar deneyin.',
      );
    }
    final customerId = body.integer('customerId');
    state.ensureCustomer(p, customerId);
    final lines = _linesFrom(state, body, customerId);
    f
      ..['customerId'] = customerId
      ..['customerTitle'] = r.world.customerTitle(customerId)
      ..['lines'] = lines
      ..['concurrencyToken'] = FieldFakeState.newToken()
      ..addAll(FieldFakeState.totals(lines));
    _applyHeader(f, body, p);
    return _formJson(state, f, p);
  });

  // ─────────────────────────────────────────────────────────── Önizleme

  s.post('field-orders/preview-v2', (r) {
    needFields(r);
    final p = r.requireUser();
    final state = st(r);
    final body = r.json;
    final customerId = body.integer('customerId');
    state.ensureCustomer(p, customerId);
    return fieldFakePreview(state, p, body);
  });

  // ─────────────────────────────────────────────────────────── Seçenekler

  s.get('field-orders/options-v2', (r) {
    needFields(r);
    final p = r.requireUser();
    final state = st(r);
    final customerId = r.queryInt('customerId') ?? 0;
    state.ensureCustomer(p, customerId);
    return _options(state, p, customerId);
  });

  s.get('field-orders/supply-options', (r) {
    needFields(r);
    final q = r.query('q') ?? '';
    final all = [
      for (final d in const [
        'Petrol Ofisi',
        'Opet',
        'Shell',
        'BP',
        'Aytemiz',
        'TotalEnergies',
      ])
        {'kind': 'distributor', 'name': d},
      for (final t in const [
        'İzmit Körfez Terminali',
        'Aliağa Terminali',
        'Kırıkkale Terminali',
        'Derince Depo',
      ])
        {'kind': 'terminal', 'name': t},
    ];
    return [
      for (final o in all)
        if (q.isEmpty || TurkishText.matches(o['name'], q)) o,
    ];
  });

  s.get('field-orders/customers/search', (r) {
    needFields(r);
    final p = r.requireUser();
    final state = st(r);
    final term = r.query('term') ?? '';
    final ids = FieldFakeState.isFieldSales(p)
        ? state.portfolioOf(p)
        : [
            for (final l in r.world.links)
              if (l['stationId'] == FieldFakeState.stationId)
                l['customerId'] as int,
          ];
    return [
      for (final id in ids)
        if (r.world.customer(id) case final c?)
          if (term.isEmpty ||
              TurkishText.matches(c['title'] as String?, term) ||
              (c['taxNumber'] as String? ?? '').contains(term))
            {'id': id, 'name': c['title'], 'extra': c['city']},
    ].take(20).toList();
  });

  s.get('field-orders/reps', (r) {
    needFields(r);
    final p = r.requireUser();
    if (FieldFakeState.isFieldSales(p)) return const <Object>[];
    return [
      for (final rep in st(r).reps)
        {'id': rep['id'], 'name': rep['name'], 'extra': rep['extra']},
    ];
  });

  s.get('me/portfolio', (r) {
    r.requirePage(Pg.stationFieldOrders);
    final p = r.requireUser();
    final state = st(r);
    final rep = state.repOf(p);
    if (rep == null) {
      throw FakeResponse.business(
        'Hesabınıza bağlı aktif satış temsilcisi kaydı yok.',
      );
    }
    final search = r.query('search') ?? '';
    final skip = max(0, r.queryInt('skip') ?? 0);
    final take = (r.queryInt('take') ?? 25).clamp(1, 100);
    final rows = [
      for (final id in state.portfolioOf(p))
        if (r.world.customer(id) case final c?)
          if (search.isEmpty ||
              TurkishText.matches(c['title'] as String?, search))
            {
              'customerId': id,
              'customerCode': 'C-${id.toString().padLeft(4, '0')}',
              'customerTitle': c['title'],
              'city': c['city'],
              'assignedAt': FakeWorld.utc(
                r.world.seededAt.subtract(const Duration(days: 40)),
              ),
              'assignedBy': 'Mehmet Demir',
            },
    ];
    return {
      'items': rows.skip(skip).take(take).toList(),
      'totalCount': rows.length,
      'pageNumber': skip ~/ take + 1,
      'pageSize': take,
      'totalPages': (rows.length / take).ceil(),
    };
  });

  // ─────────────────────────────────────────────────────────── Gönder, iptal, dönüşüm

  s.post('field-orders/{id:int}/submit', (r) {
    needFields(r, Perm.create);
    final p = r.requireUser();
    final state = st(r);
    final f = _find(state, p, r.intParam('id'));
    if (f['status'] != 0) {
      throw FakeResponse.business('Yalnızca taslak form gönderilebilir.');
    }
    final token = r.json.nonEmpty('concurrencyToken');
    if (token != null && token != f['concurrencyToken']) {
      throw FakeResponse.business(
        'Form bu arada başka biri tarafından değiştirildi. Sayfayı yenileyip tekrar deneyin.',
      );
    }
    final lines = (f['lines'] as List).cast<JsonMap>();
    if (lines.isEmpty) {
      throw FakeResponse.business('Formda en az bir satır olmalı.');
    }
    final pv = fieldFakePreview(state, p, _requestOf(f));
    final finance = JsonReader.of(pv['finance']);
    if (finance.nonEmpty('blocked') != null) {
      throw FakeResponse.business(finance.str('blocked'));
    }
    final band = JsonReader.of(pv['band']);
    final level = (pv['_level'] as int?) ?? 1;
    final reject = band.str('key') == 'reject';
    final now = DateTime.now().toUtc();
    f
      ..['submittedAt'] = FakeWorld.utc(now)
      ..['requiredApprovalLevel'] = level
      ..['concurrencyToken'] = FieldFakeState.newToken()
      ..['_minProfitPercent'] = pv['_minProfit'];
    final financeRequired = finance.boolean('required');
    if (financeRequired && !reject) {
      f
        ..['financeStatus'] = 1
        ..['financeReasons'] = finance.strings('reasons').join(' · ');
      final a = state.addApproval(
        type: 5,
        status: 0,
        form: f,
        title: 'Saha formu finans onayı',
        summary:
            '${f['customerTitle']} · ${FieldFakeState.methodName(f['paymentMethodCode'] as String?)}, ${f['paymentTermDays']} gün vade',
        eligible: const ['finans', 'sahip'],
      );
      f['_financeApprovalId'] = a['id'];
      f['financeApprovalRequestId'] = a['id'];
    }
    String message;
    var autoApproved = false;
    if (reject) {
      f
        ..['status'] = 3
        ..['decidedAt'] = FakeWorld.utc(now)
        ..['decidedByName'] = 'Otomatik ret'
        ..['decisionNote'] =
            'Kâr barem alt sınırının altında; form otomatik reddedildi.'
        ..['financeStatus'] = 0;
      (f['approvals'] as List).add(
        _trail(3, 'Otomatik ret', level, null, null, now),
      );
      message =
          'Form kârlılık kuralı gereği otomatik reddedildi. Fiyatı güncelleyip yeni form açın.';
    } else if (level == 0) {
      (f['approvals'] as List).add(
        _trail(0, 'Otomatik onay', 0, null, null, now),
      );
      if (financeRequired) {
        f['status'] = 2;
        message =
            'Kârlılık onayı tamam; finans onayı bekleniyor. Finans onaylayınca siparişler otomatik açılır.';
      } else {
        _convert(state, f, now);
        autoApproved = true;
        message =
            'Form otomatik onaylandı ve siparişe dönüştü; teklif müşteri onayına gitti.';
      }
    } else {
      f['status'] = 1;
      final eligible = switch (level) {
        1 => const ['satis', 'mudur', 'sahip'],
        2 => const ['mudur', 'finans', 'sahip'],
        _ => const ['sahip'],
      };
      final a = state.addApproval(
        type: 1,
        status: 0,
        form: f,
        title: 'Saha formu kârlılık onayı',
        summary:
            '${f['customerTitle']} · ${Fmt.liters(f['totalLiters'] as num)} · ${band.str('label')}',
        eligible: eligible,
      );
      f['_approvalId'] = a['id'];
      message = 'Form onaya gönderildi: ${band.str('label')}.';
    }
    return {
      'formId': f['id'],
      'formNumber': f['formNumber'],
      'status': f['status'],
      'requiredApprovalLevel': level,
      'autoApproved': autoApproved,
      'autoRejected': reject,
      'convertedOrderIds': f['convertedOrderIds'],
      'message': message,
      'financeStatus': f['financeStatus'],
    };
  });

  s.post('field-orders/{id:int}/cancel', (r) {
    needFields(r, Perm.edit);
    final p = r.requireUser();
    final state = st(r);
    final f = _find(state, p, r.intParam('id'));
    if (!const [0, 1, 2].contains(f['status'])) {
      throw FakeResponse.business(
        'Yalnızca taslak, onay bekleyen ya da dönüşümü tamamlanamamış onaylı form iptal edilebilir.',
      );
    }
    f
      ..['status'] = 5
      ..['decidedAt'] = FakeWorld.utc(DateTime.now())
      ..['decidedByName'] = p.displayName
      ..['decisionNote'] = r.json.nonEmpty('note')
      ..['concurrencyToken'] = FieldFakeState.newToken();
    for (final key in ['_approvalId', '_financeApprovalId']) {
      final a = r.world.approval(f[key] as int?);
      if (a != null && (a['status'] == 0 || a['status'] == 4)) a['status'] = 3;
    }
    return {'message': 'Form iptal edildi.'};
  });

  s.post('field-orders/{id:int}/retry-conversion', (r) {
    r.requirePage(Pg.stationFieldApprovals, Perm.edit);
    final p = r.requireUser();
    final state = st(r);
    final f = _find(state, p, r.intParam('id'));
    if (f['status'] != 2) {
      throw FakeResponse.business('Bu formda tekrar denenecek dönüşüm yok.');
    }
    if (f['financeStatus'] == 1 || f['financeStatus'] == 4) {
      throw FakeResponse.business(
        'Form finans onayı bekliyor; finans onaylayınca siparişe kendiliğinden dönüşür.',
      );
    }
    _convert(state, f, DateTime.now().toUtc());
    return {
      'formId': f['id'],
      'formNumber': f['formNumber'],
      'status': f['status'],
      'requiredApprovalLevel': f['requiredApprovalLevel'],
      'autoApproved': false,
      'autoRejected': false,
      'convertedOrderIds': f['convertedOrderIds'],
      'message': 'Dönüşüm tamamlandı; kalan satırlar siparişe çevrildi.',
      'financeStatus': f['financeStatus'],
    };
  });

  // ─────────────────────────────────────────────────────────── Belge ve e-posta

  s.get('field-orders/{id:int}/document', (r) {
    needFields(r);
    final p = r.requireUser();
    final state = st(r);
    final f = _find(state, p, r.intParam('id'));
    final variant = (r.query('variant') ?? '').asciiLower;
    if (variant.isNotEmpty && variant != 'external' && variant != 'internal') {
      throw FakeResponse.validation({
        'variant': ['Belge türü external ya da internal olmalıdır.'],
      });
    }
    final internal = variant == 'internal';
    if (internal && !FieldFakeState.showCosts(p)) {
      throw FakeResponse.forbidden(
        'İç sipariş formu için maliyet görme yetkisi gerekir.',
      );
    }
    return _document(state, f, p, internal: internal);
  });

  s.post('field-orders/{id:int}/email', (r) {
    needFields(r, Perm.create);
    final p = r.requireUser();
    final state = st(r);
    final f = _find(state, p, r.intParam('id'));
    if (const [0, 3, 5].contains(f['status'])) {
      throw FakeResponse.business(
        'Taslak, reddedilmiş ya da iptal edilmiş form gönderilemez.',
      );
    }
    final to =
        r.json.nonEmpty('toEmail') ??
        (r.world.customer(f['customerId'] as int)?['email'] as String?) ??
        'satinalma@${TurkishText.searchKey((f['customerTitle'] as String).split(' ').first)}.example';
    return {
      'message': 'Sipariş formu $to adresine gönderilmek üzere sıraya alındı.',
    };
  });
}

// ═══════════════════════════════════════════════════════════════════ Yardımcılar

JsonMap _find(FieldFakeState state, FakePersona p, int id) {
  final f = state.forms.where((x) => x['id'] == id).firstOrNull;
  if (f == null || !state.canSeeForm(p, f)) {
    throw FakeResponse.notFound('Saha formu bulunamadı.');
  }
  return f;
}

JsonMap _row(JsonMap f, bool costs) => {
  'id': f['id'],
  'formNumber': f['formNumber'],
  'stationId': f['stationId'],
  'stationTitle': f['stationTitle'],
  'customerId': f['customerId'],
  'customerTitle': f['customerTitle'],
  'salesRepresentativeName': f['salesRepresentativeName'],
  'status': f['status'],
  'paymentTermDays': f['paymentTermDays'],
  'lineCount': (f['lines'] as List).length,
  'totalLiters': f['totalLiters'],
  'totalAmount': f['totalAmount'],
  'totalProfit': null,
  'marginPercent': null,
  'minLineMarginPercent': null,
  'requiredApprovalLevel': f['requiredApprovalLevel'],
  'createdAt': f['createdAt'],
  'submittedAt': f['submittedAt'],
  'decidedAt': f['decidedAt'],
  'pricingModel': 1,
  'financeStatus': f['financeStatus'],
  'paymentMethodCode': f['paymentMethodCode'],
  'minProfitPercent': costs ? f['_minProfitPercent'] : null,
};

/// Ayrıntı JSON'u: iç alanlar atılır; maliyet alanları yalnızca maliyet görebilene; eylem bayrakları kişiye göre.
JsonMap _formJson(FieldFakeState state, JsonMap f, FakePersona p) {
  final costs = FieldFakeState.showCosts(p);
  final draft = f['status'] == 0;
  final owner = f['_createdBy'] == p.userId;
  final manager = !FieldFakeState.isFieldSales(p);
  final out = <String, dynamic>{
    for (final e in f.entries)
      if (!e.key.startsWith('_')) e.key: e.value,
  };
  out['statusLabel'] = const {
    0: 'Taslak',
    1: 'Onay bekliyor',
    2: 'Onaylandı',
    3: 'Reddedildi',
    4: 'Siparişe dönüştü',
    5: 'İptal edildi',
  }[f['status']];
  out['financeStatusLabel'] = const {
    0: 'Gerekmiyor',
    1: 'Finans onayında',
    2: 'Finans onaylandı',
    3: 'Koşullu onaylandı',
    4: 'Ek bilgi istendi',
    5: 'Finans reddetti',
  }[f['financeStatus']];
  out['canEdit'] =
      draft && (owner || manager) && p.can(Pg.stationFieldOrders, Perm.edit);
  out['canSubmit'] =
      draft && (owner || manager) && p.can(Pg.stationFieldOrders, Perm.create);
  out['canCancel'] =
      (draft || f['status'] == 1 || (f['status'] == 2 && manager)) &&
      (owner || manager) &&
      p.can(Pg.stationFieldOrders, Perm.edit);
  out['canDecide'] = false;
  out['awaitingFinance'] =
      f['status'] == 2 && (f['financeStatus'] == 1 || f['financeStatus'] == 4);
  final level = f['requiredApprovalLevel'] as int?;
  out['barem'] = level == null && !draft
      ? null
      : {
          'bandKey': _bandKey(level ?? 1, f['status'] == 3),
          'outcomeLabel': _bandLabel(level ?? 1, f['status'] == 3),
          'hint': _bandHint(level ?? 1, f['status'] == 3, false),
          'notices': const <String>[],
          'requiredLevel': level ?? 1,
          'autoReject':
              f['status'] == 3 && f['decidedByName'] == 'Otomatik ret',
          'costUnknown': false,
          'outOfRange': false,
          'chipText': costs && f['_minProfitPercent'] != null
              ? 'Satır 5 · İdeal %6 / Mümkün %5 / Min %4 → ${_bandLabel(level ?? 1, false)}'
              : null,
        };
  out['minProfitPercent'] = costs ? f['_minProfitPercent'] : null;
  out['salesForm'] = {
    'salesInvoiceTotal': f['totalAmount'],
    'formProfitPercent': costs ? f['_minProfitPercent'] : null,
    'totalProfit': costs && f['_minProfitPercent'] != null
        ? FieldFakeState.round(
            (f['totalAmount'] as num) /
                1.2 *
                ((f['_minProfitPercent'] as num) / 100) *
                0.8,
            2,
          )
        : null,
  };
  // Satırlar kopyalanır (saklanan kayıt değişmesin); maliyet alanları yalnızca maliyet görebilene.
  out['lines'] = [
    for (final l in (f['lines'] as List).cast<JsonMap>())
      {...l, if (!costs) 'bindirimM3': null, if (!costs) 'profitPercent': null},
  ];
  return out;
}

JsonMap _trail(
  int decision,
  String label,
  int level,
  String? approver,
  String? note,
  DateTime at,
) => {
  'level': level,
  'levelLabel': const [
    'Otomatik',
    'Bayi yöneticisi',
    'Üst yönetici',
    'İstisna onayı',
  ][level.clamp(0, 3)],
  'decision': decision,
  'decisionLabel': label,
  'approverName': approver,
  'note': note,
  'marginPercent': null,
  'decidedAt': FakeWorld.utc(at),
};

List<JsonMap> _linesFrom(
  FieldFakeState state,
  JsonReader body,
  int customerId,
) {
  final world = state.world;
  final lines = body.list('lines', (l) => l);
  if (lines.length > 20) {
    throw FakeResponse.business('Bir formda en çok 20 satır olabilir.');
  }
  final today = TrTime.todayStart();
  final out = <JsonMap>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final no = i + 1;
    final productId = l.integer('productId');
    final pointId = l.integer('deliveryPointId');
    final liters = l.dec('quantityLiters');
    final price = _linePrice(body, l);
    final date = l.date('requestedDeliveryDate');
    if (productId <= 0) throw FakeResponse.business('$no. satır: ürün seçin.');
    if (pointId <= 0) {
      throw FakeResponse.business('$no. satır: teslimat noktası seçin.');
    }
    if (liters <= 0) {
      throw FakeResponse.business(
        '$no. satır: litre pozitif olmalı ve en çok 3 ondalık içermeli.',
      );
    }
    if (price <= 0) {
      throw FakeResponse.business(
        "$no. satır: birim fiyat 0'dan büyük ve en çok 4 ondalık olmalı.",
      );
    }
    if (date == null) {
      throw FakeResponse.business('$no. satır: teslim tarihi seçin.');
    }
    if (TrTime.dayDiff(today, date) < 0) {
      throw FakeResponse.business('$no. satır: teslim tarihi geçmiş olamaz.');
    }
    if (world.product(productId) == null) {
      throw FakeResponse.business('Seçilen ürün bulunamadı veya pasif.');
    }
    if (world.deliveryPoint(pointId)?['customerId'] != customerId) {
      throw FakeResponse.business(
        'Teslimat noktası bu cariye ait değil veya pasif.',
      );
    }
    final t = l.decOrNull('tuprasPriceM3');
    if (t != null && (t < 1000 || t > 1000000)) {
      throw FakeResponse.business(
        '$no. satır: Tüpraş fiyatı ₺/m³ (KDV dahil) olarak girilmeli (ör. 61.507,69).',
      );
    }
    final line = state.newLine(
      productId: productId,
      deliveryPointId: pointId,
      liters: liters,
      price: price,
      date: date,
      location: body.nonEmpty('refineryLocation') ?? 'İZMİT',
      tuprasM3: t,
      pumpPrice: l.decOrNull('pumpPricePerLiter'),
      bindirimM3: l.decOrNull('bindirimM3'),
    );
    out.add(line);
  }
  return out;
}

/// Satır birim fiyatı (₺/L, KDV dahil). Kâr % ile girişte (maliyet görebilen) fiyat kârdan hesaplanır:
/// P = C × (1 + (k + valör + visa) / 100), C = Tüpraş + bindirim × 1,2 (nakliye payı yok sayılır).
double _linePrice(JsonReader body, JsonReader l) {
  final entered = l.dec('proposedUnitPrice');
  final pct = l.decOrNull('profitPercent');
  if (l.integer('priceEntryMode') != 1 || pct == null) return entered;
  final productId = l.integer('productId');
  final location = body.nonEmpty('refineryLocation') ?? 'İZMİT';
  final t =
      l.decOrNull('tuprasPriceM3') ??
      FieldFakeState.tupras(productId, location);
  if (t == null) return entered;
  final bindirim =
      l.decOrNull('bindirimM3') ?? FieldFakeState.bindirim[productId] ?? 0;
  final cost = t + bindirim * 1.2;
  final valor = body.integer('paymentTermDays') * 0.04;
  final visa = body.nonEmpty('paymentMethodCode') == 'KART' ? 1.5 : 0.0;
  return FieldFakeState.round(
    cost * (1 + (pct + valor + visa) / 100) / 1000,
    4,
  );
}

void _applyHeader(JsonMap f, JsonReader b, FakePersona p) {
  final ship = b.date('shipDate');
  final term = b.integer('paymentTermDays');
  final method = b.nonEmpty('paymentMethodCode');
  final costs = FieldFakeState.showCosts(p);
  f
    ..['paymentTermDays'] = term
    ..['paymentMethodCode'] = method
    ..['paymentMethodName'] = FieldFakeState.methodName(method)
    ..['paymentDetails'] = b
        .map('paymentDetails')
        .map((k, v) => MapEntry(k, '$v'))
    ..['note'] = b.nonEmpty('note')
    ..['distributorName'] = b.nonEmpty('distributorName')
    ..['terminalName'] = b.nonEmpty('terminalName')
    ..['refineryLocation'] = b.nonEmpty('refineryLocation') ?? 'İZMİT'
    ..['transportKm'] = b.decOrNull('transportKm')
    ..['transportTotal'] = b.decOrNull('transportTotal')
    ..['isCombinedShipment'] = b.boolean('isCombinedShipment')
    ..['combinedTruckLiters'] = b.decOrNull('combinedTruckLiters')
    ..['combinedTruckCost'] = b.decOrNull('combinedTruckCost')
    ..['strategicExceptionRequested'] = b.boolean('strategicExceptionRequested')
    ..['exceptionJustification'] = b.nonEmpty('exceptionJustification');
  if (costs) {
    f
      ..['purchaseTermDays'] = b.intOrNull('purchaseTermDays')
      ..['purchaseTermPercent'] = b.decOrNull('purchaseTermPercent')
      ..['transportPercent'] = b.decOrNull('transportPercent')
      ..['otherPercent'] = b.decOrNull('otherPercent');
  }
  if (ship != null) {
    f
      ..['shipDate'] = FakeWorld.local(ship)
      ..['paymentDueDate'] = FakeWorld.local(TrTime.addDays(ship, term));
  }
}

/// Kayıtlı formun istek hâli (gönderimde önizleme hesabı için).
JsonReader _requestOf(JsonMap f) => JsonReader({
  'customerId': f['customerId'],
  'paymentTermDays': f['paymentTermDays'],
  'paymentMethodCode': f['paymentMethodCode'],
  'shipDate': f['shipDate'],
  'refineryLocation': f['refineryLocation'],
  'transportTotal': f['transportTotal'],
  'isCombinedShipment': f['isCombinedShipment'],
  'combinedTruckLiters': f['combinedTruckLiters'],
  'combinedTruckCost': f['combinedTruckCost'],
  'strategicExceptionRequested': f['strategicExceptionRequested'],
  'exceptionJustification': f['exceptionJustification'],
  'lines': [
    for (final l in (f['lines'] as List).cast<JsonMap>())
      {
        'productId': l['productId'],
        'deliveryPointId': l['deliveryPointId'],
        'quantityLiters': l['quantityLiters'],
        'requestedDeliveryDate': l['requestedDeliveryDate'],
        'proposedUnitPrice': l['proposedUnitPrice'],
        'tuprasPriceM3': l['tuprasOverridden'] == true
            ? l['tuprasPriceM3']
            : null,
        'pumpPricePerLiter': l['pumpPricePerLiter'],
        'bindirimM3': l['bindirimM3'],
      },
  ],
});

/// Formu siparişe çevirir: her satır ortak dünyada "Onay bekleniyor" (teklifli) sipariş açar.
void _convert(FieldFakeState state, JsonMap f, DateTime now) {
  final world = state.world;
  final ids = <int>[];
  for (final l in (f['lines'] as List).cast<JsonMap>()) {
    if (l['orderId'] != null) {
      ids.add(l['orderId'] as int);
      continue;
    }
    final id = world.nextId('order');
    final date =
        TrTime.parseLocal(l['requestedDeliveryDate'] as String?) ?? now;
    final liters = (l['quantityLiters'] as num).toDouble();
    final price = (l['proposedUnitPrice'] as num).toDouble();
    final order = world.newOrder(
      id: id,
      customerId: f['customerId'] as int,
      stationId: FieldFakeState.stationId,
      deliveryPointId: l['deliveryPointId'] as int,
      productId: l['productId'] as int,
      liters: liters,
      status: 2,
      createdAt: now,
      expiresAt: now.add(const Duration(hours: 24)),
      requestedDeliveryDate: date,
      paymentMethodCode: (f['paymentMethodCode'] as String?) ?? 'HAVALE',
      paymentTermDays: (f['paymentTermDays'] as int?) == 0
          ? null
          : f['paymentTermDays'] as int?,
      quotes: [
        world.newQuote(
          id: world.nextId('quote'),
          version: 1,
          unitPrice: price,
          liters: liters,
          deliveryDate: date,
          createdAt: now,
          // Sunucu yeni teklifi seçili kaydeder (`SubmitQuoteAsync`).
          selected: true,
        ),
      ],
      createdByUserId: f['_createdBy'] as String?,
    );
    world.orders.add(order);
    l
      ..['orderId'] = id
      ..['orderNumber'] = order['orderNumber'];
    ids.add(id);
  }
  final note = f['decisionNote'] as String?;
  final marker = note?.indexOf('Dönüşüm hatası:') ?? -1;
  f
    ..['status'] = 4
    ..['convertedOrderIds'] = ids
    ..['decidedAt'] = f['decidedAt'] ?? FakeWorld.utc(now)
    ..['decisionNote'] = marker < 0
        ? note
        : (note!.substring(0, marker).trim().isEmpty
              ? null
              : note.substring(0, marker).trim())
    ..['_noAutoConvert'] = false
    ..['concurrencyToken'] = FieldFakeState.newToken();
  final creator = f['_createdBy'] as String?;
  if (creator != null) {
    world.addNotification(
      userId: creator,
      category: 'field',
      eventCode: 'fieldform.decided',
      title: 'Saha formu siparişe dönüştü',
      body:
          '${f['formNumber']} · ${f['customerTitle']}: teklif müşteri onayına gitti.',
      severity: 1,
      route: '/field/forms/${f['id']}',
      entityType: 'FieldOrderForm',
      entityId: f['id'] as int,
    );
  }
}

/// Onaylarım'da (başka özelliğin sahtesi) verilen kararları forma yansıtır: kârlılık talebi onay / ret,
/// finans talebi onay / ek bilgi / ret.
void _syncFromApprovals(FieldFakeState state) {
  final world = state.world;
  final now = DateTime.now().toUtc();
  for (final f in state.forms) {
    final profit = world.approval(f['_approvalId'] as int?);
    final finance = world.approval(f['_financeApprovalId'] as int?);
    if (finance != null) {
      final fs = switch (finance['status']) {
        1 => 2,
        2 => 5,
        4 => 4,
        0 => 1,
        _ => f['financeStatus'],
      };
      if (fs != f['financeStatus']) {
        f['financeStatus'] = fs;
        f['concurrencyToken'] = FieldFakeState.newToken();
        if (fs == 5 && const [1, 2].contains(f['status'])) {
          f
            ..['status'] = 3
            ..['decidedAt'] = FakeWorld.utc(now)
            ..['decisionNote'] = 'Finans reddetti.';
        }
      }
    }
    if (profit != null && f['status'] == 1) {
      if (profit['status'] == 1) {
        (f['approvals'] as List).add(
          _trail(
            1,
            'Onaylandı',
            (f['requiredApprovalLevel'] as int?) ?? 1,
            'Onaylayan',
            null,
            now,
          ),
        );
        f['status'] = 2;
      } else if (profit['status'] == 2) {
        (f['approvals'] as List).add(
          _trail(
            2,
            'Reddedildi',
            (f['requiredApprovalLevel'] as int?) ?? 1,
            'Onaylayan',
            null,
            now,
          ),
        );
        f
          ..['status'] = 3
          ..['decidedAt'] = FakeWorld.utc(now)
          ..['decisionNote'] = 'Onaylayan formu reddetti.';
      }
    }
    if (f['status'] == 2 &&
        (f['financeStatus'] == 0 ||
            f['financeStatus'] == 2 ||
            f['financeStatus'] == 3)) {
      // Kâr onayı tamam ve finans temiz: dönüşüm (web ile aynı; yarıda kalırsa "yeniden dene").
      if (f['_noAutoConvert'] != true) _convert(state, f, now);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════ Seçenekler

JsonMap _options(FieldFakeState state, FakePersona p, int customerId) {
  final world = state.world;
  final customer = world.customer(customerId)!;
  final costs = FieldFakeState.showCosts(p);
  final link = world.link(FieldFakeState.stationId, customerId);
  final today = TrTime.todayStart();
  double? lastPrice(int productId) {
    double? price;
    for (final o in world.ordersOfCustomer(customerId)) {
      if (o['productId'] != productId) continue;
      for (final q in (o['quotes'] as List).cast<JsonMap>()) {
        if (q['isSelected'] == true) {
          price = (q['unitPriceTry'] as num).toDouble();
        }
      }
    }
    return price;
  }

  return {
    'showCosts': costs,
    'stationId': FieldFakeState.stationId,
    'customerId': customerId,
    'customerTitle': customer['title'],
    'defaultDate': TrTime.isoDate(TrTime.addDays(today, 1)),
    'products': [
      for (final pr in world.products)
        () {
          final id = pr['id'] as int;
          final list = (pr['listPrice'] as num).toDouble();
          final special = customerId == 103
              ? FieldFakeState.round(list - 0.20, 4)
              : null;
          return {
            'id': id,
            'code': pr['code'],
            'name': pr['name'],
            'suggestedUnitPrice': special ?? list,
            'suggestedSource': special == null ? 'list' : 'customer',
            'suggestedSourceLabel': special == null
                ? 'Liste fiyatı'
                : 'Cari fiyatı',
            'lastUnitPrice': lastPrice(id),
            'pumpPricePerLiter': FieldFakeState.pump[id],
            'tuprasPricesM3': {
              for (final l in FieldFakeState.locations)
                l: ?FieldFakeState.tupras(id, l),
            },
            'tuprasPriceDates': {
              for (final l in FieldFakeState.locations)
                l: TrTime.isoDate(FieldFakeState.tuprasDay(l)),
            },
          };
        }(),
    ],
    'points': [
      for (final d in world.deliveryPointsOfCustomer(customerId))
        {
          'id': d['id'],
          'name': d['name'],
          'city': d['city'],
          'district': d['district'],
          'address': d['address'],
          'place': [d['district'], d['city']].whereType<String>().join(' / '),
        },
    ],
    'limit': _limit(link, 0, 0),
    'model': 1,
    'city': customer['city'],
    'distributor': 'Petrol Ofisi',
    'terminal': 'İzmit Körfez Terminali',
    'location': 'İZMİT',
    'locations': [
      for (final l in FieldFakeState.locations)
        {'code': l, 'label': FieldFakeState.locationLabels[l]},
    ],
    'vatRatePercent': 20,
    'pricesIncludeVat': true,
    'collateralPct': customerId == 103 ? 25 : 0,
    'strategic': false,
    'maxPaymentTermDays': 365,
    'payment': {
      'stationId': FieldFakeState.stationId,
      'customerId': customerId,
      'enabled': true,
      'defaultMethodCode': 'HAVALE',
      'methods': FieldFakeState.paymentMethods(),
      'blockedReason': null,
      'advanceBalance': null,
      'linked': true,
    },
    'costInputs': costs
        ? {
            'purchaseTermDays': true,
            'purchaseTermPercent': true,
            'otherPercent': true,
            'transportPercent': true,
            'lineBindirim': true,
            'profitPercentEntry': true,
            'defaultBindirimM3': {
              for (final e in FieldFakeState.bindirim.entries)
                '${e.key}': e.value,
            },
          }
        : null,
  };
}

/// Limit durumu (`FieldOrderLimitStatusDto`; sunucu `EvaluateLimit` metinleri).
JsonMap _limit(JsonMap? link, double liters, double amount) {
  if (link == null) {
    return {
      'state': 'none',
      'message': 'Cari bu bayiye aktif olarak bağlı değil.',
      'used': 0,
      'requested': 0,
      'unit': 'TL',
    };
  }
  final limit = (link['limitAmount'] as num?)?.toDouble();
  final period = (link['limitPeriod'] as String?) ?? 'Aylık';
  if (limit == null || period == 'Limitsiz') {
    return {
      'state': 'unlimited',
      'message': 'Limitsiz.',
      'used': 0,
      'requested': 0,
      'unit': 'TL',
      'limitPeriod': period,
    };
  }
  final litre = link['limitType'] == 'Litre';
  final unit = litre ? 'L' : 'TL';
  final used = (link['used'] as num).toDouble();
  final requested = litre ? liters : amount;
  final available = max(0.0, limit - used);
  String fmt(double v) => litre
      ? Fmt.number(v, maxFraction: 0)
      : Fmt.number(v, minFraction: 2, maxFraction: 2);
  final exceeded = requested > available;
  return {
    'state': exceeded ? 'exceeded' : 'ok',
    'limitType': link['limitType'],
    'limitPeriod': period,
    'limitAmount': limit,
    'used': used,
    'requested': requested,
    'available': available,
    'unit': unit,
    'message': exceeded
        ? '$period limit aşılıyor: kullanılabilir ${fmt(available)} $unit, istenen ${fmt(requested)} $unit.'
        : '$period limit uygun: kullanılabilir ${fmt(available)} $unit.',
  };
}

// ═══════════════════════════════════════════════════════════════════ Önizleme (barem)

String _bandKey(int level, bool reject) {
  if (reject) return 'reject';
  return switch (level) {
    0 => 'ok',
    1 => 'mid',
    3 => 'exception',
    _ => 'low',
  };
}

String _bandLabel(int level, bool reject) {
  if (reject) return 'Otomatik ret';
  return switch (level) {
    0 => 'Otomatik onay',
    1 => 'Bayi yöneticisi onayı',
    2 => 'Üst onay',
    _ => 'İstisna onayı',
  };
}

/// Sunucu `FieldOrderV2Rules.Hint` metinleri (kâr % içermez).
String _bandHint(
  int level,
  bool reject,
  bool outOfRange, {
  bool unknown = false,
}) {
  if (reject) {
    return 'Kâr barem alt sınırının altında; gönderilirse otomatik reddedilir. Fiyatı güncelleyin ya da gerekçeyle stratejik istisna isteyin.';
  }
  if (unknown) return 'Tüpraş fiyatı yok; kâr doğrulanamadı → üst onay.';
  return switch (level) {
    0 => 'Form gönderilince doğrudan siparişe dönüşür.',
    1 => 'Satış müdürü / bayi müdürü onaylar.',
    2 =>
      outOfRange
          ? 'Barem dışı koşul (vade / teminat) → üst onay (bayi müdürü, finans müdürü ya da merkez).'
          : 'Üst onay: bayi müdürü, finans müdürü ya da merkez onaylar.',
    _ => 'İstisna onayı: bayi sahibi ya da merkez onaylar.',
  };
}

String _bandTone(String key, bool outOfRange) => switch (key) {
  'ok' => 'ok',
  'mid' || 'unknown' => 'warn',
  'low' => outOfRange ? 'danger' : 'brand',
  'exception' => 'brand',
  'reject' => 'danger',
  _ => 'neutral',
};

/// `FieldOrderPreviewV2Dto` (barem modeli). Kâr: k = (P − C − N) / C − valör − visa; C = Tüpraş + bindirim
/// (KDV dahil). İdeal %6 / Mümkün %5 / Min %4 → otomatik / yönetici / üst / ret (gerekçeli istisna).
JsonMap fieldFakePreview(FieldFakeState state, FakePersona p, JsonReader body) {
  final world = state.world;
  final costs = FieldFakeState.showCosts(p);
  final customerId = body.integer('customerId');
  final term = body.integer('paymentTermDays');
  final method = body.nonEmpty('paymentMethodCode');
  final location = body.nonEmpty('refineryLocation') ?? 'İZMİT';
  final lines = body.list('lines', (l) => l);
  final ship = body.date('shipDate') ?? TrTime.addDays(TrTime.todayStart(), 1);
  final today = TrTime.todayStart();

  var totalLiters = 0.0;
  var totalAmount = 0.0;
  final prices = [for (final l in lines) _linePrice(body, l)];
  for (var i = 0; i < lines.length; i++) {
    totalLiters += lines[i].dec('quantityLiters');
    totalAmount += lines[i].dec('quantityLiters') * prices[i];
  }
  final totalM3 = totalLiters / 1000;
  final combined = body.boolean('isCombinedShipment');
  final transportTotal = combined
      ? (body.dec('combinedTruckCost') *
            (totalLiters / max(1, body.dec('combinedTruckLiters'))))
      : body.dec('transportTotal');
  final transportM3 = totalM3 <= 0 ? 0.0 : transportTotal / totalM3;
  final valor = term * 0.04;
  final visa = method == 'KART' ? 1.5 : 0.0;

  double? minK;
  var unknown = false;
  var stale = false;
  var lowered = false;
  final overridden = <int>[];
  final outLines = <JsonMap>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    final productId = l.integer('productId');
    final liters = l.dec('quantityLiters');
    final price = prices[i];
    final ref = FieldFakeState.tupras(productId, location);
    final entered = l.decOrNull('tuprasPriceM3');
    final t = entered ?? ref;
    if (entered != null && (ref == null || (entered - ref).abs() >= 0.01)) {
      overridden.add(i + 1);
      if (ref == null || entered < ref - 0.01) lowered = true;
    }
    // Uygulama referans fiyatı satıra kopyalayıp gönderir: girilen değer referansla aynıysa (ya da hiç
    // girilmediyse) ve referans bugünden eskiyse hesap eski fiyatla yapılır.
    final keptReference =
        entered == null || (ref != null && (entered - ref).abs() < 0.01);
    if (keptReference &&
        TrTime.dayDiff(FieldFakeState.tuprasDay(location), today) > 0) {
      stale = true;
    }
    final pumpL =
        l.decOrNull('pumpPricePerLiter') ?? FieldFakeState.pump[productId];
    final invoiceM3 = price * 1000;
    final amount = liters * price;
    final bindirimEx =
        (costs ? l.decOrNull('bindirimM3') : null) ??
        FieldFakeState.bindirim[productId] ??
        0;
    double? k;
    double? costM3;
    if (t == null) {
      unknown = true;
    } else {
      costM3 = t + bindirimEx * 1.2;
      k = (invoiceM3 - costM3 - transportM3) / costM3 * 100 - valor - visa;
      minK = minK == null ? k : min(minK, k);
    }
    final pumpM3 = pumpL == null ? null : pumpL * 1000;
    outLines.add({
      'key': i,
      'productId': productId,
      'productName': world.product(productId)?['name'],
      'liters': liters,
      'unitPriceL': price,
      'unitPriceM3': FieldFakeState.round(invoiceM3, 2),
      'amount': FieldFakeState.round(amount, 2),
      'costUnknown': t == null,
      'tuprasM3': t,
      'pumpM3': pumpM3,
      'invoiceExVatM3': FieldFakeState.round(invoiceM3 / 1.2, 2),
      'invoicePerLiter': price,
      'invoiceExVatPerLiter': FieldFakeState.round(price / 1.2, 4),
      'salesInvoice': FieldFakeState.round(amount, 2),
      'tuprasDiffM3': t == null ? null : FieldFakeState.round(invoiceM3 - t, 2),
      'tuprasDiffPercent': t == null
          ? null
          : FieldFakeState.round((invoiceM3 - t) / t * 100, 2),
      'pumpMinusTuprasM3': t == null || pumpM3 == null
          ? null
          : FieldFakeState.round(pumpM3 - t, 2),
      'pumpMinusTuprasPercent': t == null || pumpM3 == null
          ? null
          : FieldFakeState.round((pumpM3 - t) / t * 100, 2),
      'pumpDiscountM3': pumpM3 == null
          ? null
          : FieldFakeState.round(pumpM3 - invoiceM3, 2),
      'pumpDiscountPercent': pumpM3 == null
          ? null
          : FieldFakeState.round((pumpM3 - invoiceM3) / pumpM3 * 100, 2),
      'pumpAbove': pumpM3 != null && pumpM3 < invoiceM3,
      'cost': costs && costM3 != null && k != null
          ? {
              'costM3': FieldFakeState.round(costM3, 2),
              'costPerLiter': FieldFakeState.round(costM3 / 1000, 4),
              'transportM3': FieldFakeState.round(transportM3, 2),
              'profitPercent': FieldFakeState.round(k, 2),
              'profitTotal': FieldFakeState.round(
                costM3 * k / 100 * liters / 1000,
                2,
              ),
              'netProfit': FieldFakeState.round(
                costM3 * k / 100 * liters / 1000 / 1.2,
                2,
              ),
              'bindirimVatInclM3': FieldFakeState.round(bindirimEx * 1.2, 2),
              'loss': k < 0,
            }
          : null,
    });
  }

  final outOfRange = term > 90;
  final exception =
      body.boolean('strategicExceptionRequested') &&
      (body.nonEmpty('exceptionJustification') ?? '').length >= 20;
  var level = 0;
  var reject = false;
  final k = minK;
  if (unknown) {
    level = 2;
  } else if (k != null) {
    if (k >= 6) {
      level = 0;
    } else if (k >= 5) {
      level = 1;
    } else if (k >= 4) {
      level = 2;
    } else if (exception) {
      level = 3;
    } else {
      reject = true;
    }
  }
  if (!reject && outOfRange) level = max(level, 2);
  final notices = <String>[];
  if (stale) {
    notices.add(
      'Bugünkü Tüpraş referans fiyatı girilmedi (son giriş ${Fmt.date(FieldFakeState.tuprasDay(location))}): hesap eski fiyatla yapılır, form otomatik onaylanmaz.',
    );
    if (!reject) level = max(level, 1);
  }
  if (lowered && !reject) level = max(level, 1);
  final key = unknown ? 'unknown' : _bandKey(level, reject);
  final hint = _bandHint(level, reject, outOfRange, unknown: unknown);

  // Limit ve finans (rakamlar herkese; sunucu metinleri).
  final link = world.link(FieldFakeState.stationId, customerId);
  final limit = _limit(link, totalLiters, totalAmount);
  final limitAmount = (limit['limitAmount'] as num?)?.toDouble();
  final usedPct = limitAmount == null || limitAmount <= 0
      ? null
      : min(
          100.0,
          FieldFakeState.round(
            ((limit['used'] as num) + (limit['requested'] as num)) /
                limitAmount *
                100,
            1,
          ),
        );
  final reasons = <String>[];
  final m = FieldFakeState.method(method);
  if (m != null && m['isDeferred'] == true && term > 0) {
    reasons.add('Vadeli yöntem (${m['name']})');
  }
  if (limit['state'] == 'exceeded') {
    final over =
        (limit['used'] as num) +
        (limit['requested'] as num) -
        (limitAmount ?? 0);
    reasons.add(
      'Limit aşımı ${Fmt.number(over, maxFraction: 0)} ${limit['unit']}',
    );
  }
  final financeStatus = link?['financeStatus'] as int?;
  final blocked =
      link != null &&
          financeStatus != null &&
          financeStatus != 1 &&
          financeStatus != 2
      ? 'Cari finans onayı bekliyor; form gönderilemez.'
      : null;

  return {
    'showCosts': costs,
    'model': 1,
    'band': {
      'key': key,
      'label': unknown ? 'Üst onay' : _bandLabel(level, reject),
      'tone': _bandTone(key, outOfRange),
      'hint': notices.isEmpty ? hint : '$hint ${notices.join(' ')}',
    },
    'notices': notices,
    'totals': {
      'liters': totalLiters,
      'm3': FieldFakeState.round(totalM3, 3),
      'amount': FieldFakeState.round(totalAmount, 2),
      'salesInvoice': FieldFakeState.round(totalAmount, 2),
      'lines': lines.length,
    },
    'lines': outLines,
    'limit': {
      'state': limit['state'],
      'message': limit['message'],
      'blocking':
          limit['state'] == 'exceeded' ||
          limit['state'] == 'invalid' ||
          limit['state'] == 'none',
      'unit': limit['unit'],
      'usedPct': usedPct,
    },
    'dueDate': TrTime.isoDate(TrTime.addDays(ship, term)),
    'collateralPct': customerId == 103 ? 25 : 0,
    'finance': {
      'required': reasons.isNotEmpty,
      'reasons': reasons,
      'blocked': blocked,
    },
    'overriddenLines': overridden,
    'chip': costs && k != null
        ? 'Satır ${term <= 30 ? 3 : 7} · İdeal %6 / Mümkün %5 / Min %4 → ${_bandLabel(level, reject)}'
        : null,
    'reason': costs && k != null
        ? 'En düşük satır kârı %${Fmt.number(k, maxFraction: 2)}.'
        : null,
    'barem': costs
        ? {
            'row': term <= 30 ? 3 : 7,
            'ideal': 6,
            'possible': 5,
            'min': 4,
            'outOfRange': outOfRange,
            'bridge': false,
            'strategic': false,
            'level': level,
            'reject': reject,
          }
        : null,
    'form': costs
        ? {
            'formProfitPercent': k == null ? null : FieldFakeState.round(k, 2),
            'netProfit': k == null
                ? null
                : FieldFakeState.round(totalAmount / 1.2 * k / 100 * 0.8, 2),
            'costUnknownLines': unknown ? 1 : 0,
            'lossLines': outLines
                .where(
                  (l) =>
                      (JsonReader.of(l['cost']).decOrNull('profitPercent') ??
                          0) <
                      0,
                )
                .length,
          }
        : null,
    'thresholds': null,
    // Sahte sunucu iç alanları (gönderim için; istemci yok sayar).
    '_level': level,
    '_minProfit': k == null ? null : FieldFakeState.round(k, 2),
  };
}

// ═══════════════════════════════════════════════════════════════════ Belge

JsonMap _document(
  FieldFakeState state,
  JsonMap f,
  FakePersona p, {
  required bool internal,
}) {
  final world = state.world;
  final station = world.station(FieldFakeState.stationId) ?? const {};
  final customer = world.customer(f['customerId'] as int) ?? const {};
  final lines = (f['lines'] as List).cast<JsonMap>();
  final created = TrTime.parseUtc(f['createdAt'] as String?);
  final submitted = TrTime.parseUtc(f['submittedAt'] as String?);
  return {
    'id': f['id'],
    'formNumber': f['formNumber'],
    'status': f['status'],
    'statusLabel': _formJson(state, f, p)['statusLabel'],
    'createdAtLocal': created == null ? null : FakeWorld.local(created),
    'submittedAtLocal': submitted == null ? null : FakeWorld.local(submitted),
    'decidedAtLocal': null,
    'paymentTermDays': f['paymentTermDays'],
    'note': f['note'],
    'salesRepresentativeName': f['salesRepresentativeName'],
    'createdByName': f['createdByName'],
    'approvedByName': (f['approvals'] as List).isEmpty
        ? null
        : ((f['approvals'] as List).last as JsonMap)['approverName'],
    'approvalKind': f['status'] == 4 ? 'Otomatik onay' : null,
    'distributorBrand': f['distributorName'],
    'station': {
      'title': station['title'] ?? '',
      'code': station['code'],
      'city': station['city'],
      'district': station['district'],
      'phone': station['phone'],
    },
    'customer': {
      'title': customer['title'] ?? '',
      'taxNumber': customer['taxNumber'],
      'city': customer['city'],
      'district': customer['district'],
      'phone': customer['phone'],
      'email': customer['email'],
    },
    'lines': [
      for (var i = 0; i < lines.length; i++)
        {
          'no': i + 1,
          'productCode':
              world.product(lines[i]['productId'] as int)?['code'] ?? '',
          'productName': lines[i]['productName'],
          'deliveryPointName': lines[i]['deliveryPointName'],
          'deliveryAddress': world.deliveryPoint(
            lines[i]['deliveryPointId'] as int,
          )?['address'],
          'requestedDeliveryDate': lines[i]['requestedDeliveryDate'],
          'quantityLiters': lines[i]['quantityLiters'],
          'unitPrice': lines[i]['proposedUnitPrice'],
          'amount': FieldFakeState.round(
            (lines[i]['quantityLiters'] as num) *
                (lines[i]['proposedUnitPrice'] as num),
            2,
          ),
          'orderNumber': lines[i]['orderNumber'],
        },
    ],
    'totalLiters': f['totalLiters'],
    'totalAmount': f['totalAmount'],
    'printedAt': FakeWorld.local(DateTime.now()),
    'printedBy': p.displayName,
    'shipDate': f['shipDate'],
    'paymentMethodCode': f['paymentMethodCode'],
    'paymentMethodName': f['paymentMethodName'],
    'paymentDueDate': f['paymentDueDate'],
    'distributorName': f['distributorName'],
    'terminalName': f['terminalName'],
    'customerCity': customer['city'],
    'pricingModel': 1,
    'internal': internal
        ? {
            'refineryLocation': f['refineryLocation'],
            'refineryLocationLabel':
                FieldFakeState.locationLabels[f['refineryLocation']],
            'termDays': f['paymentTermDays'],
            'purchaseTermDays': f['purchaseTermDays'],
            'purchaseTermPercent': f['purchaseTermPercent'],
            'valorPercent': FieldFakeState.round(
              (f['paymentTermDays'] as int) * 0.04,
              2,
            ),
            'otherPercent': f['otherPercent'],
            'collateralRatioPercent': f['collateralRatioPercent'],
            'vatRatePercent': 20,
            'transportTotal': f['transportTotal'],
            'lines': [
              for (var i = 0; i < lines.length; i++)
                {
                  'no': i + 1,
                  'productName': lines[i]['productName'],
                  'quantityLiters': lines[i]['quantityLiters'],
                  'tuprasOverridden': lines[i]['tuprasOverridden'],
                  'bindirimM3':
                      lines[i]['bindirimM3'] ??
                      FieldFakeState.bindirim[lines[i]['productId']],
                  'priceEntryMode': 0,
                  'result': {
                    'tuprasPriceM3': lines[i]['tuprasPriceM3'],
                    'costM3': lines[i]['tuprasPriceM3'] == null
                        ? null
                        : (lines[i]['tuprasPriceM3'] as num) +
                              (FieldFakeState.bindirim[lines[i]['productId']] ??
                                      0) *
                                  1.2,
                    'invoicePriceM3': lines[i]['invoicePriceM3'],
                    'profitPercent': f['_minProfitPercent'],
                  },
                },
            ],
            'totals': {
              'formProfitPercent': f['_minProfitPercent'],
              'totalProfit': null,
            },
            'barem': null,
            'financeStatusLabel': _formJson(state, f, p)['financeStatusLabel'],
            'financeReasons': f['financeReasons'],
            'approvals': f['approvals'],
          }
        : null,
  };
}

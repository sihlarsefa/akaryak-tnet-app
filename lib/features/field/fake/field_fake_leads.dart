import 'dart:math';

import '../../../core/auth/permissions.dart';
import '../../../core/models/json.dart';
import '../../../core/models/me_access.dart';
import '../../../core/network/fake/fake_personas.dart';
import '../../../core/network/fake/fake_server.dart';
import '../../../core/network/fake/fake_world.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import '../../../core/utils/validators.dart';
import 'field_fake_state.dart';

/// Saha ön kayıt sahte uçları (spec B.9; web `CustomerLeadService` kuralları ve metinleri).
void registerFieldLeadFakes(FakeServer s) {
  FieldFakeState st(FakeRequest r) {
    final state = FieldFakeState.of(r.world);
    _syncLeadsFromApprovals(state);
    return state;
  }

  s.get('leads', (r) {
    r.requirePage(Pg.stationLeads);
    final p = r.requireUser();
    final state = st(r);
    final all = (r.query('scope') ?? 'mine').asciiLower == 'all';
    if (all && !_canViewAll(p)) {
      throw FakeResponse.forbidden(
        'Bayinin tüm ön kayıtlarını görme yetkiniz yok.',
      );
    }
    final statuses = _statusesOf(r.query('status'));
    final q = r.query('q') ?? '';
    final rows =
        [
          for (final l in state.leads)
            if (_visible(state, p, l, mineOnly: !all) &&
                (statuses.isEmpty || statuses.contains(l['status'])) &&
                (q.isEmpty ||
                    TurkishText.matches(l['companyTitle'] as String?, q) ||
                    TurkishText.matches(l['leadNumber'] as String?, q) ||
                    (l['taxNumber'] as String? ?? '').contains(q)))
              l,
        ]..sort(
          (a, b) =>
              (b['createdAt'] as String).compareTo(a['createdAt'] as String),
        );
    return r.paged([for (final l in rows) _row(l)]);
  });

  s.get('leads/{id:int}', (r) {
    r.requirePage(Pg.stationLeads);
    final p = r.requireUser();
    final state = st(r);
    final lead = _find(state, p, r.intParam('id'));
    return _detail(state, p, lead);
  });

  s.get('leads/options', (r) {
    r.requirePage(Pg.stationLeads);
    return {
      'options': {
        'products': [
          for (final pr in r.world.products)
            {'value': '${pr['id']}', 'text': pr['name']},
        ],
        'paymentMethods': [
          for (final m in FieldFakeState.paymentMethods())
            {'value': m['code'], 'text': m['name']},
        ],
        'distributors': const [
          'Petrol Ofisi',
          'Opet',
          'Shell',
          'BP',
          'Aytemiz',
          'TotalEnergies',
        ],
        'kvkkMethods': const [
          'Islak imzalı form',
          'Ekranda onay (tablet / telefon)',
          'E-posta ile onay',
          'SMS ile onay',
          'Sözlü (telefon kaydı)',
        ],
      },
      'kvkkVersion': '1.0',
      'kvkkText': kvkkConsentText,
      'requiredKinds': const [10],
    };
  });

  s.get('leads/check-duplicate', (r) {
    r.requirePage(Pg.stationLeads);
    final state = st(r);
    final digits = Validators.digitsOnly(r.query('taxNumber'));
    final exclude = r.queryInt('excludeId');
    final result = digits.length == 10 || digits.length == 11
        ? _duplicates(
            state,
            digits,
            exclude: exclude,
            ownId: exclude ?? 1 << 30,
          )
        : <String, dynamic>{
            'linkedInThisStation': false,
            'existsElsewhere': false,
            'messages': const <String>[],
          };
    result['formatError'] = digits.isEmpty
        ? null
        : Validators.taxNumber(digits);
    return result;
  });

  s.get('leads/stats', (r) {
    r.requirePage(Pg.stationLeads);
    final p = r.requireUser();
    final state = st(r);
    final from = TrTime.parseDate(r.query('from'));
    final to = TrTime.parseDate(r.query('to'));
    if (from != null && to != null && from.isAfter(to)) {
      throw FakeResponse.validation({
        'from': ['Başlangıç tarihi bitişten sonra olamaz.'],
      });
    }
    final rows = [
      for (final l in state.leads)
        if (_visible(state, p, l, mineOnly: false))
          if (_inRange(l, from, to)) l['status'] as int,
    ];
    int count(bool Function(int s) pick) => rows.where(pick).length;
    final submitted = count((s) => s != 0 && s != 7);
    final converted = count((s) => s == 5);
    return {
      'total': rows.length,
      'draft': count((s) => s == 0),
      'cancelled': count((s) => s == 7),
      'submitted': submitted,
      'inFinance': count((s) => s >= 1 && s <= 4),
      'converted': converted,
      'rejected': count((s) => s == 6),
      'conversionRatePercent': submitted <= 0
          ? null
          : FieldFakeState.round(100 * converted / submitted, 1),
      'byRep': const <Object>[],
    };
  });

  s.post('leads', (r) {
    r.requirePage(Pg.stationLeads, Perm.create);
    final p = r.requireUser();
    final state = st(r);
    if (p.stationId != FieldFakeState.stationId) {
      throw FakeResponse.business(
        'Ön kayıt yalnızca bayi personeli ve merkez tarafından açılabilir.',
      );
    }
    final lead = state.newLead(
      id: state.nextLeadId(),
      number: state.nextLeadNumber(),
      createdBy: p.userId,
      status: 0,
      companyTitle: '',
      taxNumber: '',
      createdAt: DateTime.now().toUtc(),
    );
    final warnings = _apply(state, lead, r.json, p, isNew: true);
    state.leads.add(lead);
    return FakeResponse.created(_saveResult(lead, warnings, created: true));
  });

  s.put('leads/{id:int}', (r) {
    r.requirePage(Pg.stationLeads, Perm.edit);
    final p = r.requireUser();
    final state = st(r);
    final lead = _find(state, p, r.intParam('id'));
    _ensureEditable(lead, 'düzenlenemez');
    _ensureToken(lead, r.json.nonEmpty('concurrencyToken'));
    final copy = {...lead};
    final warnings = _apply(state, copy, r.json, p, isNew: false);
    lead
      ..addAll(copy)
      ..['concurrencyToken'] = FieldFakeState.newToken();
    return _saveResult(lead, warnings, created: false);
  });

  s.post('leads/{id:int}/submit', (r) {
    r.requirePage(Pg.stationLeads, Perm.edit);
    final p = r.requireUser();
    final state = st(r);
    final lead = _find(state, p, r.intParam('id'));
    _ensureEditable(lead, 'finansa gönderilemez');
    _ensureToken(lead, r.json.nonEmpty('concurrencyToken'));
    final missing = _missing(r.world, lead);
    if (missing.isNotEmpty) {
      throw FakeResponse.business(
        'Finansa göndermek için eksik: ${missing.join(', ')}.',
      );
    }
    final dup = _duplicates(
      state,
      lead['taxNumber'] as String,
      exclude: lead['id'] as int,
      ownId: lead['id'] as int,
    );
    if (dup['linkedInThisStation'] == true) {
      throw FakeResponse.business(
        'Bu VKN ile cari bayinizde kayıtlı (${dup['existingCustomerCode']}).',
      );
    }
    if (dup['openLeadNumber'] != null) {
      throw FakeResponse.business(
        'Açık ön kayıt var: ${dup['openLeadNumber']}.',
      );
    }
    final now = DateTime.now().toUtc();
    final open = r.world.approval(lead['approvalRequestId'] as int?);
    if (open != null &&
        open['status'] == 4 &&
        open['requestedByUserId'] == p.userId) {
      // Ek bilgi yanıtı: aynı talep yeniden onaya düşer.
      open
        ..['status'] = 0
        ..['infoResponse'] = {
          'note': 'Ön kayıt güncellendi ve yeniden gönderildi.',
          'respondedAt': FakeWorld.utc(now),
        };
    } else {
      if (open != null && (open['status'] == 0 || open['status'] == 4)) {
        open['status'] = 3;
      }
      final a = _addLeadApproval(state, lead, p, now);
      lead['approvalRequestId'] = a['id'];
    }
    lead
      ..['status'] = 1
      ..['submittedAt'] = FakeWorld.utc(now)
      ..['decisionNote'] = null
      ..['existsElsewhere'] = dup['existsElsewhere'] == true
      ..['concurrencyToken'] = FieldFakeState.newToken();
    return {'message': 'Ön kayıt finans onayına gönderildi.'};
  });

  s.post('leads/{id:int}/cancel', (r) {
    r.requirePage(Pg.stationLeads, Perm.edit);
    final p = r.requireUser();
    final state = st(r);
    final lead = _find(state, p, r.intParam('id'));
    if (lead['status'] != 0 && lead['status'] != 3) {
      throw FakeResponse.business(
        'Yalnızca taslak ya da ek bilgi istenen ön kayıt iptal edilebilir.',
      );
    }
    final open = r.world.approval(lead['approvalRequestId'] as int?);
    if (open != null && (open['status'] == 0 || open['status'] == 4)) {
      open['status'] = 3;
    }
    lead
      ..['status'] = 7
      ..['decisionNote'] = r.json.nonEmpty('note')
      ..['concurrencyToken'] = FieldFakeState.newToken();
    return {'message': 'Ön kayıt iptal edildi.'};
  });

  s.post('leads/{id:int}/forward-hq', (r) {
    final p = r.requireUser();
    if (!p.can(Pg.stationLeads) && !p.can(Pg.stationApprovals)) {
      throw FakeResponse.forbidden();
    }
    if (!p.hasCap(Caps.approveFinanceLead)) throw FakeResponse.forbidden();
    final state = st(r);
    final lead = _find(state, p, r.intParam('id'));
    if (p.persona == Persona.platform) {
      throw FakeResponse.business('Merkez talebe doğrudan karar verebilir.');
    }
    if (lead['status'] != 1 && lead['status'] != 2) {
      throw FakeResponse.business(
        'Yalnızca finans onayı bekleyen ön kayıt merkeze iletilebilir.',
      );
    }
    if (lead['existsElsewhere'] != true) {
      throw FakeResponse.business(
        "Merkeze iletme yalnızca VKN'si başka bayide kayıtlı ön kayıtlar içindir; diğerlerine bayi finansı karar verir.",
      );
    }
    if (lead['isForwardedToHq'] == true) {
      throw FakeResponse.business('Talep zaten merkeze iletildi.');
    }
    lead['isForwardedToHq'] = true;
    final a = r.world.approval(lead['approvalRequestId'] as int?);
    if (a != null) a['escalated'] = true;
    return {'message': 'Ön kayıt merkez onayına iletildi.'};
  });

  s.post('leads/{id:int}/resend-invite', (r) {
    r.requirePage(Pg.stationLeads, Perm.edit);
    final p = r.requireUser();
    final state = st(r);
    final lead = _find(state, p, r.intParam('id'));
    if (lead['status'] != 5) {
      throw FakeResponse.business(
        'Portal daveti yalnızca cariye dönüştürülmüş ön kayıt için gönderilir.',
      );
    }
    if (lead['customerHasPortalUser'] == true) {
      throw FakeResponse.business(
        'Carinin portal kullanıcısı var; yeni kullanıcıyı carinin yöneticisi Şirket kullanıcıları ekranından ekler.',
      );
    }
    final candidates = (lead['inviteCandidates'] as List).cast<String>();
    if (candidates.isEmpty) {
      throw FakeResponse.business(
        'Davet için e-posta yok: ön kayıttaki yetkililerin ya da carinin kayıtlı e-postası bulunmuyor.',
      );
    }
    final asked = r.json.nonEmpty('email');
    final email = asked ?? candidates.first;
    if (!candidates.any((c) => c.asciiLower == email.asciiLower)) {
      throw FakeResponse.business(
        'Davet yalnızca ön kayıttaki yetkililerin ya da carinin kayıtlı e-postasına gönderilebilir.',
      );
    }
    final expires = DateTime.now().toUtc().add(const Duration(hours: 72));
    lead
      ..['inviteEmail'] = email
      ..['inviteExpiresAt'] = FakeWorld.local(expires);
    return {
      'message':
          'Portal daveti $email adresine gönderildi (geçerlilik ${Fmt.dateTime(expires)}). '
          'Önceki davet bağlantısı artık çalışmaz.',
    };
  });
}

/// Web ön kayıt formundaki açık rıza cümlesi (sunucu `LeadsV1Controller.KvkkConsentText`).
const kvkkConsentText =
    'Firma yetkilisi, kişisel verilerinin cari açılışı, finansal değerlendirme (risk raporu dahil) ve '
    'iletişim amacıyla bayi ve AkaryakıtNet tarafından işlenmesine açık rıza verdi.';

// ═══════════════════════════════════════════════════════════════════ Kurallar

bool _canViewAll(FakePersona p) =>
    p.persona == Persona.platform ||
    p.hasCap(Caps.leadViewAll) ||
    p.hasCap(Caps.approveFinanceLead);

bool _owns(FieldFakeState state, FakePersona p, JsonMap lead) {
  final rep = state.repOf(p)?['id'];
  return lead['createdByUserId'] == p.userId ||
      (rep != null && lead['salesRepresentativeId'] == rep);
}

bool _visible(
  FieldFakeState state,
  FakePersona p,
  JsonMap lead, {
  required bool mineOnly,
}) {
  if (p.persona == Persona.platform) return !mineOnly || _owns(state, p, lead);
  if (p.stationId != lead['stationId']) return false;
  if (mineOnly) return _owns(state, p, lead);
  return _canViewAll(p) || _owns(state, p, lead);
}

JsonMap _find(FieldFakeState state, FakePersona p, int id) {
  final lead = state.leads.where((l) => l['id'] == id).firstOrNull;
  if (lead == null || !_visible(state, p, lead, mineOnly: false)) {
    throw FakeResponse.notFound('Ön kayıt bulunamadı.');
  }
  return lead;
}

Set<int> _statusesOf(String? key) => switch ((key ?? '').trim().asciiLower) {
  'draft' => {0},
  'finance' => {1, 2, 4},
  'info' => {3},
  'converted' => {5},
  'rejected' => {6},
  'cancelled' => {7},
  final k => int.tryParse(k) == null ? <int>{} : {int.parse(k)},
};

const _statusLabels = {
  0: 'Taslak',
  1: 'Finansa gönderildi',
  2: 'Finans incelemesinde',
  3: 'Ek bilgi istendi',
  4: 'Onaylandı',
  5: 'Cariye dönüştürüldü',
  6: 'Reddedildi',
  7: 'İptal edildi',
};

void _ensureEditable(JsonMap lead, String verb) {
  final s = lead['status'] as int;
  if (s != 0 && s != 3) {
    throw FakeResponse.business(
      'Ön kayıt "${_statusLabels[s]}" durumunda; $verb.',
    );
  }
}

void _ensureToken(JsonMap lead, String? token) {
  if (token == null || token == '00000000-0000-0000-0000-000000000000') return;
  if (token != lead['concurrencyToken']) {
    throw FakeResponse.business(
      'Ön kayıt başka bir oturumda güncellendi; sayfayı yenileyin.',
    );
  }
}

bool _inRange(JsonMap lead, DateTime? from, DateTime? to) {
  final created = TrTime.parseUtc(lead['createdAt'] as String?);
  if (created == null) return false;
  if (from != null && created.isBefore(from)) return false;
  if (to != null && !created.isBefore(TrTime.addDays(to, 1))) return false;
  return true;
}

bool _hasTaxPlate(FakeWorld world, int leadId) => world.attachments.any(
  (a) =>
      a['ownerType'] == 5 &&
      a['ownerId'] == leadId &&
      a['kind'] == 10 &&
      a['isActive'] == true,
);

int _attachmentCount(FakeWorld world, int leadId) => world.attachments
    .where(
      (a) =>
          a['ownerType'] == 5 &&
          a['ownerId'] == leadId &&
          a['isActive'] == true,
    )
    .length;

/// Web `CustomerLeadService.SubmitAsync` eksik listesi (aynı metinler ve sıra).
List<String> _missing(FakeWorld world, JsonMap lead) {
  final r = JsonReader(lead);
  final missing = <String>[];
  if (r.nonEmpty('companyTitle') == null) missing.add('Firma ünvanı');
  final taxError = Validators.taxNumber(r.str('taxNumber'));
  if (taxError != null) missing.add(taxError.replaceAll(RegExp(r'\.$'), ''));
  if (r.nonEmpty('taxOffice') == null) missing.add('Vergi dairesi');
  if (r.nonEmpty('city') == null) missing.add('İl');
  if (r.nonEmpty('district') == null) missing.add('İlçe');
  final contacts = r.list('contacts', (c) => c);
  if (contacts.isEmpty) {
    missing.add('En az bir yetkili');
  } else if (contacts.any(
    (c) =>
        c.nonEmpty('name') == null ||
        c.nonEmpty('phone') == null ||
        !_isEmail(c.nonEmpty('email')),
  )) {
    missing.add('Yetkili adı, telefonu ve e-postası');
  }
  if (!r.list('products', (p) => p.dec('monthlyLiters')).any((v) => v > 0)) {
    missing.add('En az bir ürün için aylık litre');
  }
  if (!r.boolean('kvkkConsent')) {
    missing.add('KVKK açık rızası');
  } else if (r.nonEmpty('kvkkConsentMethod') == null) {
    missing.add('KVKK rızasının alınma yöntemi');
  }
  if (!_hasTaxPlate(world, r.integer('id'))) {
    missing.add('Vergi levhası (Evrak)');
  }
  return missing;
}

/// Sunucu `LeadRules.IsEmail`.
bool _isEmail(String? v) {
  if (v == null || v.isEmpty) return false;
  final at = v.indexOf('@');
  return at > 0 &&
      at == v.lastIndexOf('@') &&
      at < v.length - 3 &&
      v.indexOf('.', at) > at + 1 &&
      !v.endsWith('.') &&
      !v.contains(RegExp(r'\s'));
}

/// Web `DuplicateCoreAsync` (bayi carileri, başka bayi, açık ön kayıtlar).
JsonMap _duplicates(
  FieldFakeState state,
  String digits, {
  int? exclude,
  required int ownId,
}) {
  final world = state.world;
  final messages = <String>[];
  final result = <String, dynamic>{
    'linkedInThisStation': false,
    'existingCustomerCode': null,
    'openLeadNumber': null,
    'existsElsewhere': false,
  };
  final customer = world.customers
      .where((c) => c['taxNumber'] == digits)
      .firstOrNull;
  if (customer != null) {
    final here = world.link(FieldFakeState.stationId, customer['id'] as int);
    if (here != null) {
      final code = 'C-${customer['id'].toString().padLeft(4, '0')}';
      result
        ..['linkedInThisStation'] = true
        ..['existingCustomerCode'] = code;
      messages.add('Bu VKN ile cari bayinizde kayıtlı ($code).');
    } else {
      result['existsElsewhere'] = true;
    }
  }
  if (customer == null && FieldFakeState.elsewhereVkns.contains(digits)) {
    result['existsElsewhere'] = true;
  }
  if (result['existsElsewhere'] == true) {
    messages.add(
      'Bu VKN sistemde kayıtlı; ön kayıt finansa gönderilebilir, cari açılışı merkez onayıyla yapılır.',
    );
  }
  final others = [
    for (final l in state.leads)
      if (l['taxNumber'] == digits &&
          const [0, 1, 2, 3, 4].contains(l['status']) &&
          (exclude == null || l['id'] != exclude))
        l,
  ]..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
  final blocking = others
      .where((o) => o['status'] != 0 || (o['id'] as int) < ownId)
      .firstOrNull;
  if (blocking != null) {
    result['openLeadNumber'] = blocking['leadNumber'];
    messages.add('Açık ön kayıt var: ${blocking['leadNumber']}.');
  } else if (others.isNotEmpty) {
    messages.add(
      'Aynı VKN ile taslak ön kayıt var: ${others.first['leadNumber']}.',
    );
  }
  result['messages'] = messages;
  return result;
}

// ═══════════════════════════════════════════════════════════════════ Kayıt

/// `LeadSaveDto` gövdesini kayda uygular (doğrulama metinleri web ile aynı). Uyarıları döndürür.
List<String> _apply(
  FieldFakeState state,
  JsonMap lead,
  JsonReader b,
  FakePersona p, {
  required bool isNew,
}) {
  final world = state.world;
  String? t(String key) => b.nonEmpty(key);
  final digits = Validators.digitsOnly(b.str('taxNumber'));
  if (digits.isNotEmpty && digits.length != 10 && digits.length != 11) {
    throw FakeResponse.business('VKN 10, TCKN 11 haneli olmalıdır.');
  }
  final title = t('companyTitle') ?? '';
  if (title.isEmpty && digits.isEmpty) {
    throw FakeResponse.business(
      'Taslağı kaydetmek için en az firma ünvanı ya da VKN / TCKN girin.',
    );
  }
  final lat = b.decOrNull('visitLatitude');
  final lng = b.decOrNull('visitLongitude');
  if ((lat == null) != (lng == null)) {
    throw FakeResponse.business(
      'Konum eksik; enlem ve boylam birlikte girilmeli.',
    );
  }
  if (lat != null && (lat.abs() > 90 || lng!.abs() > 180)) {
    throw FakeResponse.business('Konum geçersiz.');
  }
  final accuracy = b.decOrNull('visitAccuracyMeters');
  if (accuracy != null && accuracy < 0) {
    throw FakeResponse.business('Konum doğruluğu negatif olamaz.');
  }
  if (accuracy != null && accuracy > 100000) {
    throw FakeResponse.business('Konum doğruluğu çok büyük.');
  }
  final products = b.list('products', (x) => x);
  if (products.length > 20) {
    throw FakeResponse.business('En çok 20 ürün satırı girilebilir.');
  }
  final outProducts = <JsonMap>[];
  for (final x in products) {
    final id = x.integer('productId');
    final monthly = x.dec('monthlyLiters');
    final committed = x.decOrNull('committedMonthlyLiters');
    if (monthly < 0 || (committed ?? 0) < 0) {
      throw FakeResponse.business('Litre negatif olamaz.');
    }
    if (world.product(id) == null) {
      throw FakeResponse.business('Seçilen ürün bulunamadı veya pasif.');
    }
    if (monthly > 100000000) {
      throw FakeResponse.business('Aylık litre çok büyük.');
    }
    if (committed != null && committed > monthly) {
      throw FakeResponse.business(
        'Taahhüt edilen litre aylık ihtiyaçtan büyük olamaz.',
      );
    }
    outProducts.add({
      'productId': id,
      'productName': world.product(id)?['name'],
      'monthlyLiters': monthly,
      'committedMonthlyLiters': committed,
    });
  }
  final contacts = b.list('contacts', (x) => x);
  if (contacts.length > 10) {
    throw FakeResponse.business('En çok 10 yetkili girilebilir.');
  }
  final term = b.intOrNull('requestedTermDays');
  if (term != null && (term < 0 || term > 365)) {
    throw FakeResponse.business('Talep edilen vade 0–365 aralığında olmalı.');
  }
  final year = b.intOrNull('foundedYear');
  if (year != null && (year < 1900 || year > TrTime.wall(TrTime.now()).year)) {
    throw FakeResponse.business(
      'Kuruluş yılı 1900–${TrTime.wall(TrTime.now()).year} aralığında olmalı.',
    );
  }
  final consent = b.boolean('kvkkConsent');
  final hadConsent = lead['kvkkConsent'] == true;
  final now = DateTime.now().toUtc();
  final methods = <String>[
    for (final c in b.strings('requestedMethodCodes'))
      if (FieldFakeState.method(c) != null) c,
  ];
  lead
    ..['companyTitle'] = title
    ..['taxNumber'] = digits
    ..['taxOffice'] = t('taxOffice')
    ..['city'] = t('city')
    ..['district'] = t('district')
    ..['address'] = t('address')
    ..['sector'] = t('sector')
    ..['foundedYear'] = year
    ..['phone'] = t('phone')
    ..['email'] = t('email')
    ..['website'] = t('website')
    ..['vehicleCount'] = b.intOrNull('vehicleCount')
    ..['vehicleTypes'] = t('vehicleTypes')
    ..['hasTank'] = b.boolean('hasTank')
    ..['tankCapacityLiters'] = b.boolean('hasTank')
        ? b.decOrNull('tankCapacityLiters')
        : null
    ..['products'] = outProducts
    ..['contractMonths'] = b.intOrNull('contractMonths')
    ..['firstOrderProductId'] = b.intOrNull('firstOrderProductId')
    ..['firstOrderLiters'] = b.decOrNull('firstOrderLiters')
    ..['firstShipDate'] = b.date('firstShipDate') == null
        ? null
        : TrTime.isoDate(b.date('firstShipDate')!)
    ..['requestedMethodCodes'] = methods.toSet().toList()
    ..['requestedTermDays'] = term
    ..['requestedLimitAmount'] = b.decOrNull('requestedLimitAmount')
    ..['collateralRatioPercent'] = b.decOrNull('collateralRatioPercent')
    ..['collateralOfferKind'] = b.intOrNull('collateralOfferKind')
    ..['collateralOfferAmount'] = b.decOrNull('collateralOfferAmount')
    ..['collateralOfferNote'] = t('collateralOfferNote')
    ..['currentDistributor'] = t('currentDistributor')
    ..['currentTerminal'] = t('currentTerminal')
    ..['currentPriceNote'] = t('currentPriceNote')
    ..['priceExpectation'] = t('priceExpectation')
    ..['visitNote'] = t('visitNote')
    ..['visitLatitude'] = lat
    ..['visitLongitude'] = lng
    ..['visitAccuracyMeters'] = accuracy
    ..['visitAt'] = b.date('visitAt') == null
        ? lead['visitAt']
        : TrTime.isoDate(b.date('visitAt')!)
    ..['deliveryPointName'] = t('deliveryPointName')
    ..['deliveryPointCity'] = t('deliveryPointCity')
    ..['deliveryPointDistrict'] = t('deliveryPointDistrict')
    ..['deliveryPointAddress'] = t('deliveryPointAddress')
    ..['contacts'] = [
      for (var i = 0; i < contacts.length; i++)
        {
          'id': contacts[i].intOrNull('id') ?? (lead['id'] as int) * 10 + i + 1,
          'name': contacts[i].str('name').trim(),
          'title': contacts[i].nonEmpty('title'),
          'phone': contacts[i].nonEmpty('phone'),
          'email': contacts[i].nonEmpty('email'),
          'isPrimary': contacts[i].boolean('isPrimary'),
          'isInviteRecipient': contacts[i].boolean('isInviteRecipient'),
        },
    ]
    ..['kvkkConsent'] = consent
    ..['kvkkConsentMethod'] = consent ? t('kvkkConsentMethod') : null;
  if (consent && !hadConsent) {
    lead
      ..['kvkkConsentAt'] = FakeWorld.utc(now)
      ..['kvkkDocumentVersion'] = '1.0';
  } else if (!consent) {
    lead
      ..['kvkkConsentAt'] = null
      ..['kvkkDocumentVersion'] = null;
  }

  final warnings = <String>[];
  final taxError = digits.isEmpty ? null : Validators.taxNumber(digits);
  if (taxError != null) warnings.add(taxError);
  if (digits.length == 10 || digits.length == 11) {
    final id = lead['id'] as int;
    final dup = _duplicates(
      state,
      digits,
      exclude: isNew ? null : id,
      ownId: isNew ? 1 << 30 : id,
    );
    lead['existsElsewhere'] = dup['existsElsewhere'] == true;
    warnings.addAll((dup['messages'] as List).cast<String>());
  } else {
    lead['existsElsewhere'] = false;
  }
  return warnings;
}

JsonMap _saveResult(
  JsonMap lead,
  List<String> warnings, {
  required bool created,
}) => {
  'id': lead['id'],
  'leadNumber': lead['leadNumber'],
  'concurrencyToken': lead['concurrencyToken'],
  'warnings': warnings,
  'status': lead['status'],
  'created': created,
};

JsonMap _row(JsonMap l) => {
  'id': l['id'],
  'leadNumber': l['leadNumber'],
  'status': l['status'],
  'statusLabel': _statusLabels[l['status']],
  'companyTitle': l['companyTitle'],
  'taxNumber': l['taxNumber'],
  'city': l['city'],
  'salesRepName': l['salesRepName'],
  'requestedLimitAmount': l['requestedLimitAmount'],
  'monthlyLiters': _monthly(l),
  'existsElsewhere': l['existsElsewhere'],
  'createdAt': l['createdAt'],
  'submittedAt': l['submittedAt'],
  'convertedAt': l['convertedAt'],
};

double _monthly(JsonMap l) => (l['products'] as List).cast<JsonMap>().fold(
  0.0,
  (s, p) => s + ((p['monthlyLiters'] as num?)?.toDouble() ?? 0),
);

JsonMap _detail(FieldFakeState state, FakePersona p, JsonMap lead) {
  final world = state.world;
  final status = lead['status'] as int;
  final editable =
      (status == 0 || status == 3) &&
      (_owns(state, p, lead) || _canViewAll(p)) &&
      p.can(Pg.stationLeads, Perm.edit);
  final finance = p.hasCap(Caps.approveFinanceLead);
  final approval = world.approval(lead['approvalRequestId'] as int?);
  final candidates = (lead['inviteCandidates'] as List).cast<String>();
  final id = lead['id'] as int;
  return {
    ...lead,
    'statusLabel': _statusLabels[status],
    'canEdit': editable,
    'canSubmit': editable,
    'canCancel': editable,
    'isFinanceViewer': finance,
    'totalMonthlyLiters': _monthly(lead),
    'firstOrderProductName': world.product(
      lead['firstOrderProductId'] as int?,
    )?['name'],
    'requestedMethodNames': [
      for (final c in (lead['requestedMethodCodes'] as List).cast<String>())
        FieldFakeState.methodName(c),
    ],
    'hasTaxPlate': _hasTaxPlate(world, id),
    'attachmentCount': _attachmentCount(world, id),
    'approvalStatus': approval?['status'],
    'canForwardToHq':
        p.persona != Persona.platform &&
        finance &&
        lead['existsElsewhere'] == true &&
        lead['isForwardedToHq'] != true &&
        approval?['status'] == 0 &&
        (status == 1 || status == 2),
    'canResendInvite':
        status == 5 &&
        lead['customerHasPortalUser'] != true &&
        candidates.isNotEmpty &&
        p.can(Pg.stationLeads, Perm.edit),
  };
}

JsonMap _addLeadApproval(
  FieldFakeState state,
  JsonMap lead,
  FakePersona p,
  DateTime now,
) {
  final world = state.world;
  final liters = _monthly(lead);
  final a = <String, dynamic>{
    'id': world.nextId('approval'),
    'type': 7,
    'status': 0,
    'isMirror': false,
    'stationId': FieldFakeState.stationId,
    'stationTitle': world.stationTitle(FieldFakeState.stationId),
    'customerId': null,
    'customerTitle': null,
    'subjectType': 'CustomerLead',
    'subjectId': lead['id'],
    'subjectNumber': lead['leadNumber'],
    'title': 'Ön kayıt finans onayı',
    'summary':
        '${lead['companyTitle']} · VKN ${lead['taxNumber']} · ${Fmt.liters(liters)} / ay',
    'amount': lead['requestedLimitAmount'],
    'liters': liters,
    'requestedByUserId': p.userId,
    'requestedByName': p.displayName,
    'createdAt': FakeWorld.utc(now),
    'dueAt': FakeWorld.utc(now.add(const Duration(hours: 48))),
    'slaState': 1,
    'currentLevelNo': 1,
    'levelCount': 1,
    'eligibleUserIds': const ['u-finans', 'u-sahip'],
  };
  world.approvals.add(a);
  return a;
}

/// Onaylarım'da verilen finans kararlarını ön kayda yansıtır.
void _syncLeadsFromApprovals(FieldFakeState state) {
  final world = state.world;
  final now = DateTime.now().toUtc();
  for (final lead in state.leads) {
    final a = world.approval(lead['approvalRequestId'] as int?);
    if (a == null) continue;
    final status = lead['status'] as int;
    switch (a['status']) {
      case 1 when status >= 1 && status <= 4:
        final contacts = (lead['contacts'] as List).cast<JsonMap>();
        final emails = [
          for (final c in contacts)
            if (c['email'] case final String e when e.isNotEmpty) e,
        ];
        lead
          ..['status'] = 5
          ..['convertedAt'] = FakeWorld.utc(now)
          ..['customerCode'] =
              'C-${1000 + Random(lead['id'] as int).nextInt(8999)}'
          ..['inviteCandidates'] = emails
          ..['inviteEmail'] = emails.isEmpty ? null : emails.first
          ..['inviteExpiresAt'] = emails.isEmpty
              ? null
              : FakeWorld.local(now.add(const Duration(hours: 72)))
          ..['concurrencyToken'] = FieldFakeState.newToken();
      case 2 when status >= 1 && status <= 4:
        lead
          ..['status'] = 6
          ..['decisionNote'] = a['decisionNote'] ?? 'Finans ön kaydı reddetti.'
          ..['concurrencyToken'] = FieldFakeState.newToken();
      case 4 when status == 1 || status == 2:
        final info = a['infoRequest'];
        lead
          ..['status'] = 3
          ..['decisionNote'] = info is Map ? info['note'] : a['decisionNote']
          ..['concurrencyToken'] = FieldFakeState.newToken();
      case 0 when status == 3:
        lead
          ..['status'] = 1
          ..['concurrencyToken'] = FieldFakeState.newToken();
    }
  }
}

import '../../core/auth/permissions.dart';
import '../../core/models/json.dart';
import '../../core/models/me_access.dart';
import '../../core/network/fake/fake_personas.dart';
import '../../core/network/fake/fake_server.dart';
import '../../core/utils/tr_time.dart';
import 'fake/a5_fake_store.dart';

/// Onaylarım sahte uçları (sahibi A5; spec §B.8 biçiminde JSON, C# camelCase anahtarlar).
///
/// - `GET approvals` (scope 0 Bende · 1 Taleplerim · 2 Karar verdiklerim · 3 Tümü, type, q, sayfa)
/// - `GET approvals/badge`, `GET approvals/{id}`
/// - `POST approvals/{id}/decide` (Idempotency-Key; belirteç, not ve koşul kuralları sunucuyla aynı)
/// - `POST approvals/{id}/provide-info` (talep eden tarafı yanıt, onaylayan tarafı "Bilgi alındı")
///
/// Yedek uçlar (asıl sahibi kaydederse onunki geçerlidir — daha özgül desen ya da sonra kayıt):
/// `GET customers/me/order-requests/{id}` (A3), `GET leads/{id}` ve `POST leads/{id}/forward-hq` (A6).
void registerApprovalsFakes(FakeServer server) {
  A5FakeStore store(FakeRequest req) => A5FakeStore.of(req.world);

  void requireInbox(FakePersona p) {
    final ok = switch (p.persona) {
      Persona.platform => true,
      Persona.bayi => p.can(Pg.stationApprovals),
      Persona.customer => p.can(Pg.customerApprovals),
      Persona.unknown => false,
    };
    if (!ok) throw FakeResponse.forbidden();
  }

  void requireDetail(FakePersona p) {
    final ok = switch (p.persona) {
      Persona.platform => true,
      Persona.bayi => p.can(Pg.stationApprovals),
      Persona.customer =>
        p.can(Pg.customerApprovals) ||
            p.can(Pg.customerOrders) ||
            p.can(Pg.customerCreateOrder),
      Persona.unknown => false,
    };
    if (!ok) throw FakeResponse.forbidden();
  }

  bool canSeeAll(FakePersona p) => switch (p.persona) {
    Persona.platform => true,
    Persona.bayi => p.can(Pg.stationApprovals, Perm.inspect),
    Persona.customer => p.can(Pg.customerApprovals, Perm.inspect),
    Persona.unknown => false,
  };

  JsonMap approvalOf(FakeRequest req, A5FakeStore s, FakePersona p) {
    final id = req.intParam('id');
    final a = req.world.approval(id);
    if (a == null || !s.visible(p, a)) {
      throw FakeResponse.notFound('Onay talebi bulunamadı.');
    }
    return a;
  }

  server.get('approvals', (req) {
    final p = req.requireUser();
    requireInbox(p);
    final s = store(req);
    final scope = (req.queryInt('scope') ?? 0).clamp(0, 3);
    if (scope == 3 && !canSeeAll(p)) {
      throw FakeResponse.forbidden('Tüm talepleri görme yetkiniz yok.');
    }
    final type = req.queryInt('type');
    final status = scope == 0 ? null : req.queryInt('status');
    final q = req.query('q');
    final rows = [
      for (final a in s.inbox(p, scope))
        if ((type == null || a['type'] == type) &&
            (status == null || a['status'] == status) &&
            A5FakeStore.matches([
              a['subjectNumber'],
              a['title'],
              a['customerTitle'],
              a['summary'],
            ], q))
          s.row(p, a),
    ];
    return req.paged(rows);
  });

  server.get('approvals/badge', (req) {
    final p = req.requireUser();
    requireInbox(p);
    final s = store(req);
    final rows = [for (final a in s.inbox(p, 0)) s.row(p, a)];
    return {
      'toMe': rows.length,
      'overdue': rows.where((r) => r['slaState'] == 3).length,
    };
  });

  server.get('approvals/{id:int}', (req) {
    final p = req.requireUser();
    requireDetail(p);
    final s = store(req);
    final a = approvalOf(req, s, p);
    // Görüntüleme günlüğe yazılır (aynı kişinin 30 dk içindeki tekrarları hariç).
    final x = s.extraOf(a);
    final now = DateTime.now().toUtc();
    final recent = x.events.any(
      (e) =>
          e['eventType'] == ApprovalEventKind.viewed.code &&
          e['userId'] == p.userId &&
          (TrTime.parseUtc(
                e['occurredAt'] as String?,
              )?.isAfter(now.subtract(const Duration(minutes: 30))) ??
              false),
    );
    if (!recent && !A5FakeStore.customerView(p, a)) {
      x.events.add(s.event(ApprovalEventKind.viewed, userKey: p.key, at: now));
    }
    return s.detail(p, a);
  });

  server.post('approvals/{id:int}/decide', (req) {
    final p = req.requireUser();
    requireInbox(p);
    final s = store(req);
    final a = approvalOf(req, s, p);
    return s.decide(p, a, req.json);
  });

  server.post('approvals/{id:int}/provide-info', (req) {
    final p = req.requireUser();
    requireDetail(p);
    final s = store(req);
    final a = approvalOf(req, s, p);
    return {'message': s.provideInfo(p, a, req.json)};
  });

  // ---------------------------------------------------------------- Yedekler

  // A3 "Talepler" sahtesi `customers/me/order-requests/{id}` kaydederse o geçerlidir (daha özgül).
  server.get('customers/me/{section}/{id:int}', (req) {
    if (req.params['section'] != 'order-requests') {
      throw FakeResponse.problem(
        404,
        'not_found',
        'Sahte API\'de tanımlı değil: GET ${req.path}',
      );
    }
    final p = req.requireUser();
    if (!p.can(Pg.customerOrderRequests)) throw FakeResponse.forbidden();
    final id = req.intParam('id');
    final r = store(req).companyRequests
        .where((x) => x['id'] == id && x['customerId'] == p.customerId)
        .firstOrNull;
    if (r == null) throw FakeResponse.notFound('Talep bulunamadı.');
    return r;
  });

  // A6 ön kayıt sahteleri aynı yolu sonra kaydederse onlarınki geçerlidir.
  server.get('leads/{id:int}', (req) {
    final p = req.requireUser();
    if (!p.can(Pg.stationLeads)) throw FakeResponse.forbidden();
    return store(req).leadJson(p, req.intParam('id'));
  });

  server.post('leads/{id:int}/{action}', (req) {
    if (req.params['action'] != 'forward-hq') {
      throw FakeResponse.problem(
        404,
        'not_found',
        'Sahte API\'de tanımlı değil: POST ${req.path}',
      );
    }
    final p = req.requireUser();
    if (!p.can(Pg.stationLeads) && !p.can(Pg.stationApprovals)) {
      throw FakeResponse.forbidden();
    }
    return {'message': store(req).forwardLead(p, req.intParam('id'))};
  });
}

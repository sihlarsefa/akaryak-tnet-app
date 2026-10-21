import '../../../core/auth/permissions.dart';
import '../../../core/models/json.dart';
import '../../../core/network/fake/fake_personas.dart';
import '../../../core/network/fake/fake_server.dart';
import '../data/delivery_point.dart';
import '../data/window_time.dart';
import 'cm_fake_support.dart';

/// `customers/me/delivery-points` (liste, ayrıntı, ekle, güncelle, pasifleştir). Ortak dünyadaki noktalar
/// değişir; sipariş sihirbazı aynı noktaları görür.
void registerCmDeliveryPointFakes(FakeServer s) {
  s.get('customers/me/delivery-points', (req) {
    final p = _customer(req);
    req.requirePage(Pg.customerDeliveryPoints);
    final inactive = req.queryBool('includeInactive') ?? false;
    final rows =
        req.world
            .deliveryPointsOfCustomer(p.customerId!)
            .where((d) => inactive || d['isActive'] != false)
            .toList()
          ..sort((a, b) {
            final act = (b['isActive'] != false ? 1 : 0).compareTo(
              a['isActive'] != false ? 1 : 0,
            );
            return act != 0
                ? act
                : (a['name'] as String).compareTo(b['name'] as String);
          });
    return [for (final d in rows) deliveryPointDto(d)];
  });

  s.get('customers/me/delivery-points/{id:int}', (req) {
    final p = _customer(req);
    req.requirePage(Pg.customerDeliveryPoints);
    return deliveryPointDto(_own(req, p, req.intParam('id')));
  });

  s.post('customers/me/delivery-points', (req) {
    final p = _customer(req);
    req.requirePage(Pg.customerDeliveryPoints, Perm.create);
    final d = _validated(req);
    final id = req.world.nextId('cm.deliveryPoint', start: 2001);
    final row = <String, dynamic>{
      'id': id,
      'customerId': p.customerId,
      'isActive': true,
      'isDefault': false,
    };
    _apply(row, d);
    req.world.deliveryPoints.add(row);
    return {'id': id};
  });

  s.put('customers/me/delivery-points/{id:int}', (req) {
    final p = _customer(req);
    req.requirePage(Pg.customerDeliveryPoints, Perm.edit);
    final row = _own(req, p, req.intParam('id'));
    _apply(row, _validated(req));
    return {'id': row['id']};
  });

  s.post('customers/me/delivery-points/{id:int}/deactivate', (req) {
    final p = _customer(req);
    req.requirePage(Pg.customerDeliveryPoints, Perm.delete);
    _own(req, p, req.intParam('id'))['isActive'] = false;
    return {'message': 'Teslimat noktası pasifleştirildi.'};
  });
}

FakePersona _customer(FakeRequest req) {
  final p = req.requireUser();
  if (!CmFake.isCustomer(p)) {
    throw FakeResponse.business('Cari bağlamı gerekli.');
  }
  return p;
}

JsonMap _own(FakeRequest req, FakePersona p, int id) {
  final d = req.world.deliveryPoint(id);
  if (d == null || d['customerId'] != p.customerId) {
    throw FakeResponse.business('Teslimat noktası bulunamadı.');
  }
  return d;
}

/// Dünya kaydı (`windowStart` "HH:mm") → `DeliveryPointDetailsDto` (TimeSpan "HH:mm:ss"; gün sonu
/// sunucudaki gibi 23:59:59).
JsonMap deliveryPointDto(JsonMap d) {
  String? span(Object? v) {
    final t = WindowTime.tryParse(v);
    if (t == null) return null;
    return t.isEndOfDay ? '23:59:59' : t.toJson();
  }

  return {
    'id': d['id'],
    'customerId': d['customerId'],
    'name': d['name'],
    'city': d['city'] ?? '',
    'district': d['district'] ?? '',
    'address': d['address'] ?? '',
    'isActive': d['isActive'] != false,
    'latitude': d['latitude'],
    'longitude': d['longitude'],
    'contactName': d['contactName'],
    'contactPhone': d['contactPhone'],
    'deliveryWindowStart': span(d['windowStart']),
    'deliveryWindowEnd': span(d['windowEnd']),
    'tankCapacityLiters': d['tankCapacityLiters'],
    'accessNotes': d['accessNotes'],
    'hasLocation': d['latitude'] != null && d['longitude'] != null,
  };
}

DeliveryPointDraft _validated(FakeRequest req) {
  final r = req.json;
  final draft = DeliveryPointDraft(
    name: r.str('name'),
    city: r.str('city'),
    district: r.str('district'),
    address: r.str('address'),
    latitude: r.decOrNull('latitude'),
    longitude: r.decOrNull('longitude'),
    contactName: r.nonEmpty('contactName'),
    contactPhone: r.nonEmpty('contactPhone'),
    windowStart: WindowTime.tryParse(r['deliveryWindowStart']),
    windowEnd: WindowTime.tryParse(r['deliveryWindowEnd']),
    tankCapacityLiters: r.decOrNull('tankCapacityLiters'),
    accessNotes: r.nonEmpty('accessNotes'),
  );
  final error = draft.validate();
  if (error != null) throw FakeResponse.business(error);
  return draft;
}

void _apply(JsonMap row, DeliveryPointDraft d) {
  row
    ..['name'] = d.name.trim()
    ..['city'] = d.city.trim()
    ..['district'] = d.district.trim()
    ..['address'] = d.address.trim()
    ..['latitude'] = d.latitude
    ..['longitude'] = d.longitude
    ..['contactName'] = d.contactName
    ..['contactPhone'] = d.contactPhone
    ..['windowStart'] = d.windowStart?.label
    ..['windowEnd'] = d.windowEnd?.label
    ..['tankCapacityLiters'] = d.tankCapacityLiters
    ..['accessNotes'] = d.accessNotes;
}

import '../../auth/permissions.dart';
import '../../models/json.dart';
import '../../models/me_access.dart';
import 'fake_personas.dart';
import 'fake_world.dart';

/// Panel eşitliği alanlarının sahte karşılığı (sunucu `CustomerOrderActionEvaluator`): yeni API
/// `orders/{id}`, `customers/me/orders`, `home/customer` ve `shipments` yanıtlarına görüntüleyen için
/// `canDecideQuote`, `canApproveQuote`, `approveBlockedReason` ve `canAcceptDelivery` ekler. Yayındaki
/// eski API bunları göndermez: testler [FakeParity.set] ile kapatıp uygulamanın yedek kuralını
/// sınar. Teklif kuralı (şirket içi onay eşiği) müşteri sipariş sahtesindedir (`A2Fake`).
abstract final class FakeParity {
  static const _bag = 'fake.parityFields';

  static Map<String, bool> _flag(FakeWorld w) =>
      w.bag<Map<String, bool>>(_bag, () => {'on': true});

  /// Yeni alanlar yanıtlarda mı (varsayılan: evet, yeni API).
  static bool on(FakeWorld w) => _flag(w)['on'] ?? true;

  /// [value]: yeni API alanları yanıtlarda (true) ya da yayındaki eski API gibi yok (false).
  static void set(FakeWorld w, {required bool value}) => _flag(w)['on'] = value;

  /// Görüntüleyen panelin müşteri sipariş ayrıntısını açabilir mi: siparişin carisinin kullanıcısı
  /// ya da yönetim. Bayi kullanıcısında alanlar değerlendirilmez (null).
  static bool evaluates(FakePersona p, int? customerId) =>
      p.persona == Persona.platform ||
      (p.persona == Persona.customer && p.customerId == customerId);

  /// Sevkiyat kartında tek dokunuşla kabul (web `_OrderTrackShipments`, sunucu
  /// `CanAcceptShipmentAsync`): carinin kendi kullanıcısı, sipariş "Onaylandı", sevkiyat kabul
  /// bekliyor ve Sevkiyatlar "Düzenler". Yönetim panelin yönetim görünümündeki gibi false; bayi null.
  static bool? acceptsShipment(FakeWorld w, FakePersona p, JsonMap shipment) {
    final order = w.order(shipment['orderId'] as int?);
    final customerId = (order?['customerId'] ?? shipment['customerId']) as int?;
    if (!evaluates(p, customerId)) return null;
    return p.persona == Persona.customer &&
        order?['status'] == 3 &&
        shipment['status'] == 2 &&
        p.can(Pg.customerShipments, Perm.edit);
  }
}

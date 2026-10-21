import '../../core/network/fake/fake_server.dart';
import 'fake/customers_fake.dart';
import 'fake/desk_fake.dart';
import 'fake/dispatch_fake.dart';
import 'fake/home_fake.dart';
import 'fake/orders_fake.dart';
import 'fake/staff_fake.dart';

/// Bayi sahte uçları (sahibi A4). §B biçiminde JSON (anahtarlar C# camelCase adlarıyla aynı); akışlar
/// ortak dünyayı (`server.world`) okur ve değiştirir: verilen teklif müşterinin "Teklif hazır" kartına,
/// planlanan sevkiyat şoförün Teslimatlarım listesine düşer. Ek veriler `bayi.*` torbalarında tohumlanır.
///
/// Yalnızca bayi uçları:
/// - GET home/bayi
/// - GET bayi/quote-desk, bayi/quote-desk/counts; POST bayi/quote-desk/submit;
///   GET stations/me/quote-desk/facets
/// - GET bayi/orders, bayi/orders/counts; POST orders/{id}/quote, orders/{id}/complete
/// - GET bayi/customers, bayi/customers/{id}/summary; stations/me/customers/{id}/notes
///   (GET, POST, DELETE), limit-requests (POST, GET pending)
/// - GET shipments/board, shipments/board/suggestions, stations/me/drivers; POST shipments,
///   shipments/{id}/assign-driver, /dispatch, /report, /cancel
/// - GET stations/me/staff; POST stations/me/staff/{userId}/active, /send-password-reset
///
/// Paylaşılan okuma uçları (bayi + müşteri + merkez görünümü). Başka bir özellik aynı yolu kaydettiyse
/// onunki kalır, bu sürüm eklenmez (bkz. `registerSharedIfAbsent`):
/// - GET orders/{id}, orders/{id}/timeline
/// - GET shipments, shipments/order/{orderId}, shipments/{id}/detail
void registerBayiFakes(FakeServer server) {
  registerBayiHomeFakes(server);
  registerBayiDeskFakes(server);
  registerBayiOrderFakes(server);
  registerBayiCustomerFakes(server);
  registerBayiDispatchFakes(server);
  registerBayiStaffFakes(server);
}

import '../../core/network/fake/fake_server.dart';
import 'fake/cm_fake_company.dart';
import 'fake/cm_fake_delivery_points.dart';
import 'fake/cm_fake_documents.dart';
import 'fake/cm_fake_shipments.dart';
import 'fake/cm_fake_spending.dart';

/// CustomerMore sahte uçları (sahibi A3). Yanıtlar §B / C# DTO camelCase anahtarlarıyla aynıdır ve
/// ortak dünyayı (`server.world`) okur / değiştirir: müşterinin kabulü sevkiyatı "Teslim alındı" yapar,
/// tüm litre kabul edilince sipariş tamamlanır; yeni teslimat noktası sipariş sihirbazında da görünür.
///
/// Uçlar:
/// - `GET shipments` (müşteri, bayi, şoför ve merkez için kapsamlı), `GET shipments/{id}/detail`
/// - `POST shipments/{id}/accept`, `POST shipments/{id}/dispute`
/// - `GET customers/me/documents`, `GET documents/orders/{id}`, `GET documents/shipments/{id}`
/// - `GET customers/me/spending`
/// - `GET|POST|PUT customers/me/delivery-points[/{id}]`, `POST …/{id}/deactivate`
/// - `GET customers/me/order-requests[/{id}]`, `POST …/{id}/cancel`, `GET …/pending-count`
/// - `GET|POST|PUT customers/me/company-users`, `POST …/{userId}/active|password-link`,
///   `GET|PUT …/approval-settings`
/// - `GET customers/me/finance-info`
void registerCustomerMoreFakes(FakeServer server) {
  registerCmShipmentFakes(server);
  registerCmDocumentFakes(server);
  registerCmSpendingFakes(server);
  registerCmDeliveryPointFakes(server);
  registerCmCompanyFakes(server);
}

import '../../../core/auth/access_policy.dart';
import '../../../core/auth/permissions.dart';
import '../../../core/models/enums.dart';

/// A3 düğme kuralları (spec A.1 tablosu; sunucu ayrıca denetler). Rol adına değil sayfa yetkilerine bakılır.
extension CmAccess on AccessPolicy {
  // Teslimatlar
  bool get cmShipments =>
      canAny(const [Pg.customerShipments, Pg.customerOrders]);
  bool get cmShipmentEdit => can(Pg.customerShipments, Perm.edit);

  // Belgeler: sipariş belgeleri `CustomerDocuments` + (`CustomerOrders` | `CustomerQuotes`);
  // sevkiyat belgeleri `CustomerDocuments` + (`CustomerShipments` | `CustomerOrders`) (DocumentsV1Controller).
  bool get cmDocuments => can(Pg.customerDocuments);
  bool get cmOrderDocuments =>
      cmDocuments && canAny(const [Pg.customerOrders, Pg.customerQuotes]);
  bool get cmShipmentDocuments =>
      cmDocuments && canAny(const [Pg.customerShipments, Pg.customerOrders]);

  // Harcamalar
  bool get cmSpending => can(Pg.customerSpending);

  // Teslimat noktaları
  bool get cmPoints => can(Pg.customerDeliveryPoints);
  bool get cmPointCreate => can(Pg.customerDeliveryPoints, Perm.create);
  bool get cmPointEdit => can(Pg.customerDeliveryPoints, Perm.edit);
  bool get cmPointDelete => can(Pg.customerDeliveryPoints, Perm.delete);

  // Şirket içi talepler
  bool get cmRequests => can(Pg.customerOrderRequests);
  bool get cmRequestCancel => can(Pg.customerOrderRequests, Perm.create);

  // Şirket kullanıcıları (yalnızca Yönetici)
  bool get cmCompanyUsers =>
      isCustomer &&
      customerRole == CustomerUserRole.admin &&
      can(Pg.customerCompanyUsers);
  bool get cmCompanyUserCreate =>
      cmCompanyUsers && can(Pg.customerCompanyUsers, Perm.create);
  bool get cmCompanyUserEdit =>
      cmCompanyUsers && can(Pg.customerCompanyUsers, Perm.edit);

  // Finans bilgisi
  bool get cmFinanceInfo =>
      isCustomer && canAny(const [Pg.customerCreateOrder, Pg.customerOrders]);

  /// Ödeme belgesi yükleme (sipariş sayfa yetkisi; sunucu `canUpload` ile ayrıca bildirir).
  bool get cmPaymentUpload =>
      canAny(const [Pg.customerOrders, Pg.customerCreateOrder]);
}

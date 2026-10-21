import '../../core/network/fake/fake_server.dart';
import 'fake/field_fake_forms.dart';
import 'fake/field_fake_leads.dart';

/// Saha sahte uçları (sahibi A6; spec B.9 + D.4).
///
/// - Formlar: GET|POST field-orders, GET|PUT field-orders/{id}, POST field-orders/preview-v2,
///   GET field-orders/options-v2, supply-options, customers/search, reps; POST field-orders/{id}/submit,
///   cancel, retry-conversion, email; GET field-orders/{id}/document.
/// - Portföy: GET me/portfolio.
/// - Ön kayıtlar: GET leads, leads/{id}, leads/options, leads/check-duplicate, leads/stats; POST leads;
///   PUT leads/{id}; POST leads/{id}/submit, cancel, forward-hq, resend-invite.
///
/// Durum ortak dünyanın torbalarındadır (`field.state`; formlar `field.forms`, ön kayıtlar `field.leads`)
/// ve ilk saha isteğinde tohumlanır. Gönderimler `world.approvals`'a talep ekler (9601'den); Onaylarım'da
/// verilen kararlar sonraki saha isteğinde forma / ön kayda yansır.
void registerFieldFakes(FakeServer server) {
  registerFieldFormFakes(server);
  registerFieldLeadFakes(server);
}

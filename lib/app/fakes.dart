import '../core/network/fake/core_fakes.dart';
import '../core/network/fake/fake_server.dart';
import '../core/network/fake/fake_world.dart';
import '../features/approvals/approvals_fake.dart';
import '../features/assistant/assistant_fake.dart';
import '../features/auth/auth_fake.dart';
import '../features/bayi/bayi_fake.dart';
import '../features/customer_home/customer_home_fake.dart';
import '../features/customer_more/customer_more_fake.dart';
import '../features/customer_orders/customer_orders_fake.dart';
import '../features/driver/driver_fake.dart';
import '../features/field/field_fake.dart';
import '../features/finance/finance_fake.dart';
import '../features/notifications/notifications_fake.dart';
import '../features/onboarding/onboarding_fake.dart';
import '../features/payments/payments_fake.dart';
import '../features/profile/profile_fake.dart';
import '../features/weather/weather_fake.dart';

/// Sahte API sunucusu: çekirdek uçlar + her özelliğin `<f>_fake.dart` uçları (spec C.4).
/// Özellik uçları çekirdekten sonra kaydedilir; aynı yolu ezebilir.
FakeServer buildFakeServer({FakeWorld? world, bool latency = true}) {
  final s = FakeServer(world: world)..latencyEnabled = latency;
  registerCoreFakes(s);
  registerAuthFakes(s);
  registerOnboardingFakes(s);
  registerCustomerHomeFakes(s);
  registerCustomerOrdersFakes(s);
  registerCustomerMoreFakes(s);
  registerBayiFakes(s);
  registerApprovalsFakes(s);
  registerFinanceFakes(s);
  registerPaymentsFakes(s);
  registerFieldFakes(s);
  registerDriverFakes(s);
  registerNotificationsFakes(s);
  registerAssistantFakes(s);
  registerWeatherFakes(s);
  registerProfileFakes(s);
  return s;
}

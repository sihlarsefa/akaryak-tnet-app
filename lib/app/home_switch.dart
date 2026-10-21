import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/session_controller.dart';
import '../features/bayi/api.dart';
import '../features/customer_home/api.dart';
import '../features/driver/api.dart';
import '../features/field/api.dart';
import 'shell/platform_home.dart';

/// Ana sayfa seçimi (spec C.3): yalnızca şoför → DriverHome; saha satış → FieldHome; bayi → BayiHome;
/// müşteri → CustomerHome; merkez → PlatformHome.
class HomeSwitch extends ConsumerWidget {
  const HomeSwitch({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(accessPolicyProvider);
    if (p.isDriverOnly) return const DriverHome();
    if (p.isFieldSales) return const FieldHome();
    if (p.isBayi) return const BayiHome();
    if (p.isCustomer) return const CustomerHome();
    if (p.isPlatform) return const PlatformHome();
    return const SizedBox.shrink();
  }
}

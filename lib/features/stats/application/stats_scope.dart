import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/access_policy.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/routing/route_access.dart';

/// İstatistiklerin kapsamı (spec R1 §3.1):
/// - [station]: bayi geneli (sahip, müdür, finans, muhasebe, satış müdürü, görüntüleyici),
/// - [own]: saha temsilcisinin kendi portföyü (aynı uç, sunucu kapsamı daraltır),
/// - [customer]: müşteri şirketi (Yönetici ya da Onaylayan, harcama raporu yetkisiyle),
/// - [none]: deste ve `/stats` yok (talep eden, sipariş masası, sevkiyat / depo, şoför, merkez).
enum StatsScope {
  station,
  own,
  customer,
  none;

  /// Bayi ucu (`stats/bayi`) mı.
  bool get isBayi => this == station || this == own;
}

/// Kapsam kararı. Kitle `RouteAccess.statsAudience` ile aynıdır (`/stats` rotası da onu kullanır).
StatsScope statsScopeFor(AccessPolicy policy) {
  if (!RouteAccess.statsAudience(policy)) return StatsScope.none;
  if (policy.isCustomer) return StatsScope.customer;
  if (policy.isFieldSales) return StatsScope.own;
  return StatsScope.station;
}

/// Oturumdaki kullanıcının istatistik kapsamı (yetki değişince yeniden hesaplanır).
final statsScopeProvider = Provider<StatsScope>(
  (ref) => statsScopeFor(ref.watch(accessPolicyProvider)),
);

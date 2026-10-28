import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session_controller.dart';
import '../../core/models/enums.dart';
import '../../core/push/unread_count_provider.dart';
import '../../features/customer_orders/api.dart';
import '../destinations.dart';

/// Hedef rozetleri (spec A.2): Onaylarım (karar bekleyen), Bildirimler (okunmamış); müşteride Finans
/// bilgisi (yanıt bekleyen bilgi talebi) ve Talep eden kullanıcıda Talepler (onay bekleyen şirket içi
/// talepler; "Diğer" noktası bu rozetle yanar).
///
/// Tasarım v3: alt menüde ve "Diğer" sayfasında rozet koyu turuncu bir haptır (beyaz rakamlar
/// ≥ 4,5:1); sayı değişince zıplar, görünürken yavaşça nefes alır (`AknAmbient`).
final destinationBadgesProvider = Provider<Map<DestinationId, int>>((ref) {
  final u = ref.watch(unreadCountProvider);
  final policy = ref.watch(accessPolicyProvider);
  var financeInfo = 0;
  var requests = 0;
  if (policy.isCustomer) {
    final home = ref.watch(customerHomeProvider.select((h) => h.data));
    financeInfo = home?.financeInfoRequests ?? 0;
    if (policy.customerRole == CustomerUserRole.requester) {
      requests = home?.companyApprovalsWaiting ?? 0;
    }
  }
  return {
    DestinationId.approvals: u.approvals,
    DestinationId.notifications: u.notifications,
    DestinationId.financeInfo: financeInfo,
    DestinationId.companyRequests: requests,
  };
});

/// Rozetin ekran okuyucu ifadesi: "Onaylarım, 3 bekleyen" (spec A.2).
String destinationSemantics(AppDestination d, int badge) {
  if (badge <= 0) return d.label;
  final what = switch (d.id) {
    DestinationId.notifications => 'okunmamış',
    DestinationId.financeInfo => 'yanıt bekliyor',
    _ => 'bekleyen',
  };
  return '${d.label}, $badge $what';
}

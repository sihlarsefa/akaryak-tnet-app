import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/session_controller.dart';
import '../../core/push/unread_count_provider.dart';
import '../../features/customer_orders/api.dart';
import '../destinations.dart';
import '../tasks/task_inbox.dart';

/// Hedef rozetleri (v4 §3.1, P2): rozetler yalnızca SIRA SİZDE olan işleri sayar ve açtıkları listeye
/// eşittir.
///
/// * Onaylar: müşteride görev kutusunun sayısı (ana sayfadaki "Sıra sizde" = rozet = Onaylar › Bende);
///   bayide ve merkezde `unread-count.approvals` (= Bende).
/// * Bildirimler: okunmamış bildirimler (açtığı listeye eşit).
/// * Finans bilgisi (müşteri): yanıt bekleyen bilgi talebi — görev kutusunun (Onaylar) zaten taşıdığı
///   bilgi soruları hariç: bir iş tek yerde sayılır, "Diğer" noktası onu ikinci kez yakmaz.
///
/// Talep edenin kendi bekleyen talepleri rozet değildir (onun sırası değil).
final destinationBadgesProvider = Provider.autoDispose<Map<DestinationId, int>>(
  (ref) {
    final u = ref.watch(unreadCountProvider);
    final policy = ref.watch(accessPolicyProvider);
    var financeInfo = 0;
    var approvals = u.approvals;
    if (policy.isCustomer) {
      final home = ref.watch(customerHomeProvider.select((h) => h.data));
      final inbox = ref.watch(taskInboxProvider);
      final asked = inbox.items
          .where((t) => t.counts && t.kind == TaskKind.financeQuestion)
          .length;
      financeInfo = math.max(0, (home?.financeInfoRequests ?? 0) - asked);
      approvals = inbox.count;
    }
    return {
      DestinationId.approvals: approvals,
      DestinationId.notifications: u.notifications,
      DestinationId.financeInfo: financeInfo,
    };
  },
);

/// Sıra sizde olan işler: "Diğer" noktası yalnızca bunlar için yanar (okunmamış bildirimler için
/// asla).
const yourMoveDestinations = {
  DestinationId.approvals,
  DestinationId.financeInfo,
};

/// Rozetin ekran okuyucu ifadesi: "Onaylar, 3 bekleyen" (spec A.2).
String destinationSemantics(AppDestination d, int badge) {
  if (badge <= 0) return d.label;
  final what = switch (d.id) {
    DestinationId.notifications => 'okunmamış',
    DestinationId.financeInfo => 'yanıt bekliyor',
    _ => 'bekleyen',
  };
  return '${d.label}, $badge $what';
}

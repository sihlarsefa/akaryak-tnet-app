import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/models/enums.dart';
import '../data/customer_more_repository.dart';
import '../data/order_requests.dart';

/// Ana sayfadaki talep satırları (tasarım v2 §7.4): en çok [HomeRequests.max] talep ve toplam.
@immutable
class HomeRequests {
  const HomeRequests({required this.items, required this.total});

  static const max = 3;

  final List<OrderRequest> items;
  final int total;
}

/// Ana sayfanın şirket içi talepleri: `pendingOnly` true iken onaylayanın kararını bekleyenler
/// ("Onayınızı bekleyen talepler"), false iken kullanıcının son talepleri ("Taleplerim"; talep eden
/// yalnızca kendi taleplerini görür, sunucu kuralı). Uç yoksa ya da hata olursa null (ana sayfa
/// sayı satırına döner).
final homeOrderRequestsProvider = FutureProvider.autoDispose
    .family<HomeRequests?, bool>((ref, pendingOnly) async {
      ref.watch(currentUserIdProvider);
      try {
        final res = await ref
            .read(customerMoreRepositoryProvider)
            .orderRequests(
              take: HomeRequests.max,
              statuses: pendingOnly
                  ? const [CustomerOrderRequestStatus.pending]
                  : const [],
            );
        return HomeRequests(
          items: List.unmodifiable(res.items.take(HomeRequests.max)),
          total: res.totalCount,
        );
      } catch (_) {
        return null;
      }
    });

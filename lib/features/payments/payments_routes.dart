import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/nav_keys.dart';
import 'presentation/payment_detail_page.dart';
import 'presentation/payments_page.dart';

/// Tahsilat rotaları (sahibi A5). Yollar spec C.4 / v4 §3.5 derin bağlantı sözleşmesidir:
/// - `/payments` (isteğe bağlı `?tab=instruments`: çek / senet portföyü; B2 çek vadesi bildirimi;
///   `?filter=overdue|documents`: gecikenler, kontrol bekleyen belgeler)
/// - `/payments/:orderId` (ödeme ayrıntısı)
List<RouteBase> paymentsRoutes() => [
  GoRoute(
    path: '/payments',
    builder: (context, state) {
      final q = state.uri.queryParameters;
      return PaymentsPage(
        // Yeni bir süzgeçli bağlantı açık sayfayı o süzgeçle yeniden kurar.
        key: ValueKey('payments-${q['tab'] ?? ''}-${q['filter'] ?? ''}'),
        initialTab: switch (q['tab']) {
          'instruments' || 'cek' || 'portfoy' => PaymentsTab.instruments,
          _ => PaymentsTab.payments,
        },
        initialFilter: q['filter'],
      );
    },
    routes: [
      GoRoute(
        path: ':orderId',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['orderId'] ?? '') ?? 0;
          return PaymentDetailPage(key: ValueKey('payment-$id'), orderId: id);
        },
      ),
    ],
  ),
];

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/nav_keys.dart';
import 'presentation/approval_detail_page.dart';
import 'presentation/approvals_page.dart';

/// Onaylarım rotaları (sahibi A5). Yollar spec C.4 derin bağlantı sözleşmesidir:
/// - `/approvals` (isteğe bağlı `?scope=bende|taleplerim|kararlarim|tumu`)
/// - `/approvals/:id` (isteğe bağlı `?reply=1`: ek bilgi yanıt alanına odaklanır)
///
/// Ayrıntı `parentNavigatorKey: rootNavigatorKey` ile alt menünün üstünde tam ekran açılır.
List<RouteBase> approvalsRoutes() => [
  GoRoute(
    path: '/approvals',
    builder: (context, state) => ApprovalsPage(
      initialScope: ApprovalsPage.parseScope(
        state.uri.queryParameters['scope'],
      ),
    ),
    routes: [
      GoRoute(
        path: ':id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          final reply = state.uri.queryParameters['reply'];
          return ApprovalDetailPage(
            key: ValueKey('approval-$id'),
            id: id,
            focusReply: reply == '1' || reply == 'true',
          );
        },
      ),
    ],
  ),
];

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/nav_keys.dart';
import 'presentation/approval_detail_page.dart';
import 'presentation/approvals_page.dart';

/// Onaylar rotaları (sahibi A5). Yollar spec C.4 / v4 §3.5 derin bağlantı sözleşmesidir:
/// - `/approvals` (isteğe bağlı `?scope=bende|taleplerim|kararlarim|tumu` ve `?type=4`)
/// - `/approvals/:id` (isteğe bağlı `?reply=1`: ek bilgi yanıt alanına odaklanır; `?focus=request`:
///   talebin karar / yanıt bloğuna kaydırıp parlatır)
///
/// Ayrıntı `parentNavigatorKey: rootNavigatorKey` ile alt menünün üstünde tam ekran açılır.
List<RouteBase> approvalsRoutes() => [
  GoRoute(
    path: '/approvals',
    builder: (context, state) {
      final q = state.uri.queryParameters;
      return ApprovalsPage(
        // Yeni bir süzgeçli bağlantı açık sayfayı o süzgeçle yeniden kurar.
        key: ValueKey('approvals-${q['scope'] ?? ''}-${q['type'] ?? ''}'),
        initialScope: ApprovalsPage.parseScope(q['scope']),
        initialType: ApprovalsPage.parseType(q['type']),
      );
    },
    routes: [
      GoRoute(
        path: ':id',
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          final q = state.uri.queryParameters;
          final reply = q['reply'];
          return ApprovalDetailPage(
            key: ValueKey('approval-$id'),
            id: id,
            focusReply: reply == '1' || reply == 'true',
            focusRequest: q['focus'] == 'request',
          );
        },
      ),
    ],
  ),
];

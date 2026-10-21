import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/models/paged_result.dart';
import '../../../core/push/unread_count_provider.dart';
import '../data/approval_models.dart';
import '../data/approvals_repository.dart';
import '../shared/paged_list.dart';

/// Onaylarım listesi (sekme + tür + arama başına).
final approvalsListProvider = NotifierProvider.autoDispose
    .family<ApprovalsListController, PagedState<ApprovalRow>, ApprovalsQuery>(
      ApprovalsListController.new,
    );

class ApprovalsListController
    extends PagedNotifier<ApprovalRow, ApprovalsQuery> {
  @override
  Future<PagedResult<ApprovalRow>> fetchPage(ApprovalsQuery q, int page) => ref
      .read(approvalsRepositoryProvider)
      .list(q, page: page, pageSize: pageSize);

  @override
  Object? keyOf(ApprovalRow item) => item.id;
}

/// `approvals/badge`: Bende ve SLA'sı geçenler (sekme sayacı, uyarı bandı). Hata → sıfır.
final approvalBadgeProvider = FutureProvider.autoDispose<ApprovalBadge>((
  ref,
) async {
  ref.watch(currentUserIdProvider);
  try {
    return await ref.read(approvalsRepositoryProvider).badge();
  } catch (_) {
    return ApprovalBadge.zero;
  }
});

/// Şirket içi sipariş talebi (satır sonuçları).
final companyRequestProvider = FutureProvider.autoDispose
    .family<CompanyRequest, int>((ref, id) {
      ref.watch(currentUserIdProvider);
      return ref.read(approvalsRepositoryProvider).companyRequest(id);
    });

/// Ön kaydın "Merkeze ilet" bilgisi (okunamazsa null: onay durumu kuralı uygulanır).
final leadForwardInfoProvider = FutureProvider.autoDispose
    .family<LeadForwardInfo?, int>((ref, id) async {
      ref.watch(currentUserIdProvider);
      try {
        return await ref.read(approvalsRepositoryProvider).lead(id);
      } catch (_) {
        return null;
      }
    });

/// Karar ya da yanıt sonrası: listeler, sekme sayacı ve alt menü rozeti yenilenir.
void refreshApprovalCounters(Ref ref) {
  ref.invalidate(approvalsListProvider);
  ref.invalidate(approvalBadgeProvider);
  unawaited(ref.read(unreadCountProvider.notifier).refresh());
}

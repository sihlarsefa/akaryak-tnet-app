import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/enums.dart';
import '../../../core/models/json.dart';
import '../../../core/models/paged_result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_providers.dart';
import 'approval_models.dart';

/// Onaylarım liste sorgusu (aile anahtarı).
@immutable
class ApprovalsQuery {
  const ApprovalsQuery({
    this.scope = ApprovalScope.toMe,
    this.type,
    this.search = '',
  });

  final ApprovalScope scope;
  final ApprovalType? type;
  final String search;

  ApprovalsQuery copyWith({
    ApprovalScope? scope,
    ApprovalType? Function()? type,
    String? search,
  }) => ApprovalsQuery(
    scope: scope ?? this.scope,
    type: type == null ? this.type : type(),
    search: search ?? this.search,
  );

  bool get isFiltered => type != null || search.trim().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is ApprovalsQuery &&
      other.scope == scope &&
      other.type == type &&
      other.search == search;

  @override
  int get hashCode => Object.hash(scope, type, search);
}

/// `POST approvals/{id}/decide` gövdesi (`ApprovalDecideRequest`).
@immutable
class ApprovalDecisionRequest {
  const ApprovalDecisionRequest({
    required this.decision,
    required this.concurrencyToken,
    this.note,
    this.conditions,
    this.requiredAttachmentKind,
    this.viewedAttachmentIds = const [],
  });

  final ApprovalDecision decision;
  final String concurrencyToken;
  final String? note;

  /// Yalnızca koşullu onayda ve yalnızca formun anahtarları.
  final Map<String, Object>? conditions;

  /// Yalnızca ek bilgi isteğinde.
  final AttachmentKind? requiredAttachmentKind;
  final List<String> viewedAttachmentIds;

  JsonMap toJson() {
    final n = note?.trim();
    final c = conditions;
    return {
      'decision': decision.code,
      if (n != null && n.isNotEmpty) 'note': n,
      'concurrencyToken': concurrencyToken,
      if (decision == ApprovalDecision.conditionalApprove &&
          c != null &&
          c.isNotEmpty)
        'conditions': c,
      if (decision == ApprovalDecision.requestInfo &&
          requiredAttachmentKind != null &&
          !requiredAttachmentKind!.isUnknown)
        'requiredAttachmentKind': requiredAttachmentKind!.code,
      'viewedAttachmentIds': viewedAttachmentIds,
    };
  }

  /// Kullanıcı niyeti (Idempotency-Key bunun için tutulur; gövde değişince yeni niyet).
  String intent(int approvalId) =>
      'approvals.decide:$approvalId:${jsonEncode(toJson())}';
}

/// Onaylarım uçları (spec §B.8). Hatalar [AppFailure] olarak fırlar.
class ApprovalsRepository {
  ApprovalsRepository(this.api);

  final ApiClient api;

  Future<PagedResult<ApprovalRow>> list(
    ApprovalsQuery q, {
    int page = 1,
    int pageSize = 25,
  }) => api.get(
    'approvals',
    query: {
      'scope': q.scope.code,
      'type': q.type?.code,
      'q': q.search.trim(),
      'page': page,
      'pageSize': pageSize,
    },
    parse: (j) => PagedResult.fromJson(j, ApprovalRow.fromJson),
  );

  Future<ApprovalBadge> badge() =>
      api.get('approvals/badge', parse: ApprovalBadge.fromJson, quiet403: true);

  Future<ApprovalDetail> detail(int id) =>
      api.get('approvals/$id', parse: ApprovalDetail.fromJson);

  Future<ApprovalDecisionResult> decide(
    int id,
    ApprovalDecisionRequest body, {
    required String idempotencyKey,
  }) => api.post(
    'approvals/$id/decide',
    body: body.toJson(),
    idempotencyKey: idempotencyKey,
    parse: ApprovalDecisionResult.fromJson,
  );

  /// Ek bilgi yanıtı (talep eden tarafı) ya da "Bilgi alındı" ([resume], onaylayan tarafı) → mesaj.
  Future<String> provideInfo(int id, {String? note, bool resume = false}) {
    final n = note?.trim();
    return api.post(
      'approvals/$id/provide-info',
      body: {if (n != null && n.isNotEmpty) 'note': n, 'resume': resume},
      parse: (j) => JsonReader.of(j).str('message'),
    );
  }

  /// Şirket içi sipariş talebi (satır sonuçları). Yetki yoksa ekran kendisi gösterir (sessiz 403).
  Future<CompanyRequest> companyRequest(int id) => api.get(
    'customers/me/order-requests/$id',
    parse: CompanyRequest.fromJson,
    quiet403: true,
  );

  /// Ön kaydın merkeze iletme bilgisi (sahibi B6; yetki yoksa sessiz).
  Future<LeadForwardInfo> lead(int id) =>
      api.get('leads/$id', parse: LeadForwardInfo.fromJson, quiet403: true);

  /// "Merkeze ilet" (yetkinlik approve.finance.lead) → mesaj.
  Future<String> forwardLeadToHq(int leadId, {String? note}) {
    final n = note?.trim();
    return api.post(
      'leads/$leadId/forward-hq',
      body: {if (n != null && n.isNotEmpty) 'note': n},
      parse: (j) => JsonReader.of(j).str('message'),
    );
  }
}

final approvalsRepositoryProvider = Provider<ApprovalsRepository>(
  (ref) => ApprovalsRepository(ref.watch(apiClientProvider)),
);

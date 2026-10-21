/// Onay ayrıntısı: yükleme, karar (Idempotency-Key + belirsiz sonuçta uzlaştırma), ek bilgi yanıtı,
/// "Bilgi alındı" ve "Merkeze ilet" (spec §B.8, C.4a).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/permissions.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/models/enums.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/network/idempotency.dart';
import '../../../core/utils/tr_time.dart';
import '../data/approval_models.dart';
import '../data/approvals_repository.dart';
import '../shared/action_outcome.dart';
import '../shared/submit_retry.dart';
import 'approvals_providers.dart';

export '../shared/action_outcome.dart';

@immutable
class ApprovalDetailState {
  const ApprovalDetailState({
    this.detail,
    this.loading = true,
    this.refreshing = false,
    this.error,
    this.loadedAt,
    this.viewed = const {},
    this.doneMessage,
  });

  final ApprovalDetail? detail;
  final bool loading;
  final bool refreshing;
  final AppFailure? error;
  final DateTime? loadedAt;

  /// Bu ekranda açılan belgeler (`viewedAttachmentIds`).
  final Set<String> viewed;

  /// Talep artık açılamıyor ama işlem tamamlandı (ör. CustomerApprovals olmayan cari yanıt verdi):
  /// ekran sonuç görünümüne geçer.
  final String? doneMessage;

  ApprovalDetailState copyWith({
    ApprovalDetail? detail,
    bool? loading,
    bool? refreshing,
    AppFailure? Function()? error,
    DateTime? loadedAt,
    Set<String>? viewed,
    String? Function()? doneMessage,
  }) => ApprovalDetailState(
    detail: detail ?? this.detail,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    error: error == null ? this.error : error(),
    loadedAt: loadedAt ?? this.loadedAt,
    viewed: viewed ?? this.viewed,
    doneMessage: doneMessage == null ? this.doneMessage : doneMessage(),
  );
}

final approvalDetailProvider = NotifierProvider.autoDispose
    .family<ApprovalDetailController, ApprovalDetailState, int>(
      ApprovalDetailController.new,
    );

class ApprovalDetailController
    extends AutoDisposeFamilyNotifier<ApprovalDetailState, int> {
  int _epoch = 0;
  bool _disposed = false;
  Future<void>? _loading;

  ApprovalsRepository get _repo => ref.read(approvalsRepositoryProvider);

  @override
  ApprovalDetailState build(int arg) {
    ref.watch(currentUserIdProvider);
    final epoch = ++_epoch;
    _loading = null;
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    Future.microtask(() => _load(epoch));
    return const ApprovalDetailState();
  }

  bool _alive(int epoch) => !_disposed && epoch == _epoch;

  Future<void> _load(int epoch) async {
    if (!_alive(epoch)) return;
    try {
      final d = await _repo.detail(arg);
      if (!_alive(epoch)) return;
      state = state.copyWith(
        detail: d,
        loading: false,
        refreshing: false,
        error: () => null,
        loadedAt: DateTime.now().toUtc(),
      );
    } catch (e) {
      if (!_alive(epoch)) return;
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: () => AppFailure.from(e),
      );
    }
  }

  /// Yeniden okur (içerik kalır). Eşzamanlı çağrılar birleşir.
  Future<void> refresh() {
    final running = _loading;
    if (running != null) return running;
    final epoch = ++_epoch;
    state = state.copyWith(
      loading: state.detail == null,
      refreshing: state.detail != null,
      error: () => null,
    );
    final f = _load(epoch);
    _loading = f;
    return f.whenComplete(() {
      if (identical(_loading, f)) _loading = null;
    });
  }

  /// Açılan belge (karar isteğinin `viewedAttachmentIds` listesine girer).
  void markViewed(String publicId) {
    if (state.viewed.contains(publicId)) return;
    state = state.copyWith(viewed: {...state.viewed, publicId});
  }

  String? get _me => ref.read(currentUserIdProvider);

  /// Karar verir. Aynı niyet (gövde) için tek Idempotency-Key; belirsiz hatada aynı anahtarla tekrar,
  /// sonra kayıt yeniden okunur ve kararım günlükte varsa başarı sayılır (spec C.4a).
  Future<ActionOutcome> decide(
    ApprovalDecision decision, {
    String? note,
    Map<String, Object>? conditions,
    AttachmentKind? requiredKind,
    void Function(String phase)? onPhase,
  }) async {
    final d = state.detail;
    if (d == null) {
      return const ActionFailed(UnknownFailure('Talep yüklenmedi.'));
    }
    final body = ApprovalDecisionRequest(
      decision: decision,
      concurrencyToken: d.concurrencyToken,
      note: note,
      conditions: decision == ApprovalDecision.conditionalApprove
          ? conditions
          : null,
      requiredAttachmentKind: decision == ApprovalDecision.requestInfo
          ? requiredKind
          : null,
      viewedAttachmentIds: state.viewed.toList()..sort(),
    );
    final ledger = ref.read(a5IdempotencyLedgerProvider);
    final intent = body.intent(d.id);
    final key = ledger.keyFor(intent);
    final since = TrTime.now().subtract(const Duration(minutes: 2));
    try {
      final result = await runWithRetry(
        () => _repo.decide(d.id, body, idempotencyKey: key),
        schedule: ref.read(a5RetryScheduleProvider),
        onRetry: (_) => onPhase?.call('Kararınız kontrol ediliyor…'),
        keepGoing: () => !_disposed,
      );
      ledger.settle(intent);
      await _afterChange();
      return ActionDone(
        result.message.isEmpty ? _defaultMessage(decision) : result.message,
        result: result,
      );
    } on AppFailure catch (f) {
      ledger.settle(intent, error: f);
      return _resolveFailure(
        f,
        reached: () => _reconcile(
          ApprovalEventType.ofDecision(decision),
          since,
          ledger: ledger,
          intent: intent,
        ),
        fallbackSuccess: _defaultMessage(decision),
      );
    }
  }

  /// Ek bilgi yanıtı (talep eden tarafı) ya da "Bilgi alındı" ([resume], onaylayan tarafı).
  Future<ActionOutcome> provideInfo({String? note, bool resume = false}) async {
    final d = state.detail;
    if (d == null) {
      return const ActionFailed(UnknownFailure('Talep yüklenmedi.'));
    }
    final since = TrTime.now().subtract(const Duration(minutes: 2));
    try {
      final message = await _repo.provideInfo(d.id, note: note, resume: resume);
      final text = message.isEmpty
          ? (resume
                ? 'Bilgi alındı olarak kaydedildi; talep yeniden incelemede.'
                : 'Yanıtınız iletildi.')
          : message;
      if (_closesAfterReply(d, resume)) {
        // CustomerApprovals görmeyen cari yanıttan sonra talebi açamaz (sunucu 404): sonuç ekranı.
        state = state.copyWith(doneMessage: () => text);
        refreshApprovalCounters(ref);
      } else {
        await _afterChange();
      }
      return ActionDone(text);
    } on AppFailure catch (f) {
      return _resolveFailure(
        f,
        reached: () => _reconcile(ApprovalEventType.infoProvided, since),
        fallbackSuccess: resume
            ? 'Bilgi alındı olarak kaydedildi.'
            : 'Yanıtınız iletildi.',
        notFoundMeansDone: !resume,
      );
    }
  }

  /// "Merkeze ilet" (ön kayıt finansı; yetkinlik approve.finance.lead).
  Future<ActionOutcome> forwardToHq(int leadId, {String? note}) async {
    try {
      final message = await _repo.forwardLeadToHq(leadId, note: note);
      ref.invalidate(leadForwardInfoProvider(leadId));
      await _afterChange();
      return ActionDone(
        message.isEmpty ? 'Ön kayıt merkez onayına iletildi.' : message,
      );
    } on AppFailure catch (f) {
      if (f is ConflictFailure && f.isConcurrency) {
        return const ActionConflict(_conflictText);
      }
      if (f is ValidationFailure) return _invalid(f);
      return ActionFailed(f);
    }
  }

  bool _closesAfterReply(ApprovalDetail d, bool resume) {
    if (resume || !d.customerView) return false;
    final policy = ref.read(accessPolicyProvider);
    return !policy.can(Pg.customerApprovals);
  }

  static const _conflictText =
      'Bu kayıt sizden sonra güncellendi. Yenileyip tekrar deneyin; yazdıklarınız korunur.';

  String _defaultMessage(ApprovalDecision d) => switch (d) {
    ApprovalDecision.approve => 'Talep onaylandı.',
    ApprovalDecision.conditionalApprove => 'Talep koşullu onaylandı.',
    ApprovalDecision.requestInfo => 'Ek bilgi istendi.',
    ApprovalDecision.reject => 'Talep reddedildi.',
    ApprovalDecision.unknown => 'Kararınız kaydedildi.',
  };

  ActionInvalid _invalid(ValidationFailure f) => ActionInvalid(f.message, {
    for (final e in f.fieldErrors.entries)
      if (e.value.isNotEmpty) e.key: e.value.first,
  });

  /// Hata → sonuç. Zaman aşımı, 400 iş kuralı ve 409'da önce kayıt yeniden okunur: işlem
  /// kaydedilmişse başarı (spec C.4a).
  Future<ActionOutcome> _resolveFailure(
    AppFailure f, {
    required Future<bool> Function() reached,
    required String fallbackSuccess,
    bool notFoundMeansDone = false,
  }) async {
    if (f is ValidationFailure) return _invalid(f);
    final uncertain = isRetryable(f) || f.isUncertain;
    final reconcile =
        uncertain ||
        f is ConflictFailure ||
        f is BusinessFailure ||
        (notFoundMeansDone && f is NotFoundFailure);
    if (reconcile) {
      try {
        if (await reached()) {
          await _afterChange(reload: false);
          return ActionDone(fallbackSuccess);
        }
      } on NotFoundFailure {
        if (notFoundMeansDone) {
          state = state.copyWith(doneMessage: () => fallbackSuccess);
          refreshApprovalCounters(ref);
          return ActionDone(fallbackSuccess);
        }
      } catch (_) {
        // Yeniden okunamadı: aşağıdaki sonuç geçerli.
      }
    }
    if (f is ConflictFailure && f.isConcurrency) {
      return const ActionConflict(_conflictText);
    }
    if (uncertain) {
      return const ActionUnverified(
        'Sonuç doğrulanamadı. Bağlantınızı kontrol edip yeniden deneyin; aynı işlem ikinci kez kaydedilmez.',
      );
    }
    return ActionFailed(f);
  }

  /// Kaydı yeniden okur; kullanıcının beklenen olayı günlükte varsa true.
  Future<bool> _reconcile(
    ApprovalEventType expected,
    DateTime since, {
    IdempotencyLedger? ledger,
    String? intent,
  }) async {
    final me = _me;
    final fresh = await _repo.detail(arg);
    if (!_disposed) {
      state = state.copyWith(
        detail: fresh,
        loading: false,
        refreshing: false,
        error: () => null,
        loadedAt: DateTime.now().toUtc(),
      );
    }
    final done = me != null && fresh.hasEventBy(me, expected, since);
    if (done && ledger != null && intent != null) ledger.settle(intent);
    return done;
  }

  Future<void> _afterChange({bool reload = true}) async {
    refreshApprovalCounters(ref);
    if (reload && !_disposed) await refresh();
  }
}

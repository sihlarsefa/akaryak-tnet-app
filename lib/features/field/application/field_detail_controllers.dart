import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/media/attachment_api.dart';
import '../../../core/models/attachment.dart';
import '../../../core/models/enums.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/network/idempotency.dart';
import '../data/field_models.dart';
import '../data/field_repository.dart';
import '../data/lead_models.dart';
import 'field_lists.dart';
import 'uncertain.dart';

/// Saha formu ayrıntısı (`GET field-orders/{id}`) ve eylemleri.
final fieldFormDetailProvider = AsyncNotifierProvider.autoDispose
    .family<FieldFormDetailController, FieldFormDetail, int>(
      FieldFormDetailController.new,
    );

class FieldFormDetailController
    extends AutoDisposeFamilyAsyncNotifier<FieldFormDetail, int> {
  String? _submitKey;

  FieldRepository get _repo => ref.read(fieldRepositoryProvider);

  @override
  Future<FieldFormDetail> build(int arg) {
    ref.watch(currentUserIdProvider);
    return _repo.form(arg);
  }

  Future<void> refresh() async {
    final previous = state.valueOrNull;
    try {
      final d = await _repo.form(arg);
      state = AsyncData(d);
    } catch (e, st) {
      if (previous == null) state = AsyncError(e, st);
      rethrow;
    }
  }

  /// Taslağı onaya gönder (aynı Idempotency-Key ile yinelenir; belirsizlikte form yeniden okunur).
  Future<FieldSubmitResult> submit() async {
    final form = state.requireValue.form;
    _submitKey ??= newIdempotencyKey();
    final result = await retryUncertain(
      () => _repo.submitForm(
        arg,
        concurrencyToken: form.concurrencyToken,
        idempotencyKey: _submitKey,
      ),
      reconcile: () async {
        final f = (await _repo.form(arg)).form;
        if (f.status == FieldOrderFormStatus.draft) return null;
        return FieldSubmitResult(
          formId: f.id,
          formNumber: f.formNumber,
          status: f.status,
          requiredApprovalLevel: f.requiredApprovalLevel,
          financeStatus: f.financeStatus,
          message: 'Form gönderildi.',
        );
      },
    );
    _submitKey = null;
    ref.read(fieldSyncTickProvider.notifier).bump();
    await _quietRefresh();
    return result;
  }

  Future<String> cancel({String? note}) async {
    final message = await _repo.cancelForm(arg, note: note);
    ref.read(fieldSyncTickProvider.notifier).bump();
    await _quietRefresh();
    return message;
  }

  Future<FieldSubmitResult> retryConversion() async {
    final form = state.requireValue.form;
    final result = await _repo.retryConversion(
      arg,
      concurrencyToken: form.concurrencyToken,
    );
    ref.read(fieldSyncTickProvider.notifier).bump();
    await _quietRefresh();
    return result;
  }

  Future<String> email({String? toEmail}) =>
      _repo.emailDocument(arg, toEmail: toEmail);

  Future<FieldDocument> document({required bool internal}) =>
      _repo.document(arg, internal: internal);

  Future<void> _quietRefresh() async {
    try {
      state = AsyncData(await _repo.form(arg));
    } on AppFailure {
      // Ekrandaki veri kalır; kullanıcı yenileyebilir.
    }
  }
}

/// Ön kayıt ayrıntısı + belgeleri.
class LeadDetailView {
  const LeadDetailView({required this.detail, this.documents = const []});

  final LeadDetail detail;
  final List<Attachment> documents;
}

final fieldLeadDetailProvider = AsyncNotifierProvider.autoDispose
    .family<FieldLeadDetailController, LeadDetailView, int>(
      FieldLeadDetailController.new,
    );

class FieldLeadDetailController
    extends AutoDisposeFamilyAsyncNotifier<LeadDetailView, int> {
  FieldRepository get _repo => ref.read(fieldRepositoryProvider);

  @override
  Future<LeadDetailView> build(int arg) async {
    ref.watch(currentUserIdProvider);
    return _load();
  }

  Future<LeadDetailView> _load() async {
    final detail = await _repo.lead(arg);
    List<Attachment> docs = const [];
    try {
      docs = await ref
          .read(attachmentApiProvider)
          .list(AttachmentOwnerType.customerLead, arg);
    } catch (_) {
      // Belgeler yüklenemezse ayrıntı yine gösterilir.
    }
    return LeadDetailView(detail: detail, documents: docs);
  }

  Future<void> refresh() async {
    try {
      state = AsyncData(await _load());
    } catch (e, st) {
      if (state.valueOrNull == null) state = AsyncError(e, st);
      rethrow;
    }
  }

  Future<String> submit() async {
    final d = state.requireValue.detail;
    final message = await retryUncertain(
      () => _repo.submitLead(arg, concurrencyToken: d.draft.concurrencyToken),
      reconcile: () async {
        final now = await _repo.lead(arg);
        return now.status.isEditable
            ? null
            : 'Ön kayıt finans onayına gönderildi.';
      },
    );
    await _after();
    return message;
  }

  Future<String> cancel({String? note}) async {
    final message = await _repo.cancelLead(arg, note: note);
    await _after();
    return message;
  }

  Future<String> forwardToHq({String? note}) async {
    final message = await _repo.forwardLeadToHq(arg, note: note);
    await _after();
    return message;
  }

  Future<String> resendInvite({String? email}) async {
    final message = await _repo.resendLeadInvite(arg, email: email);
    await _after();
    return message;
  }

  Future<void> _after() async {
    ref.read(fieldSyncTickProvider.notifier).bump();
    try {
      state = AsyncData(await _load());
    } on AppFailure {
      // Ekrandaki veri kalır.
    }
  }
}

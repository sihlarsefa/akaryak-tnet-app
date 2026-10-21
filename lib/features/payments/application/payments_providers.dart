import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/models/enums.dart';
import '../../../core/models/paged_result.dart';
import '../../../core/network/app_failure.dart';
import '../../approvals/api.dart';
import '../data/payment_models.dart';
import '../data/payments_repository.dart';

/// Ödemeler listesi (süzgeç başına).
final paymentsListProvider = NotifierProvider.autoDispose
    .family<PaymentsListController, PagedState<PaymentRow>, PaymentsQuery>(
      PaymentsListController.new,
    );

class PaymentsListController extends PagedNotifier<PaymentRow, PaymentsQuery> {
  @override
  Future<PagedResult<PaymentRow>> fetchPage(PaymentsQuery q, int page) => ref
      .read(paymentsRepositoryProvider)
      .list(q, page: page, pageSize: pageSize);

  @override
  Object? keyOf(PaymentRow item) => item.orderId;
}

/// Çek / senet portföyü (süzgeç başına).
final instrumentsListProvider = NotifierProvider.autoDispose
    .family<
      InstrumentsListController,
      PagedState<Instrument>,
      InstrumentsQuery
    >(InstrumentsListController.new);

class InstrumentsListController
    extends PagedNotifier<Instrument, InstrumentsQuery> {
  @override
  Future<PagedResult<Instrument>> fetchPage(InstrumentsQuery q, int page) => ref
      .read(paymentsRepositoryProvider)
      .instruments(q, page: page, pageSize: pageSize);

  @override
  Object? keyOf(Instrument item) => item.id;
}

/// Ödeme ayrıntısı.
final paymentDetailProvider = FutureProvider.autoDispose
    .family<PaymentDetail, int>((ref, orderId) {
      ref.watch(currentUserIdProvider);
      return ref.read(paymentsRepositoryProvider).detail(orderId);
    });

/// Cari süzgeci araması.
final paymentCustomersProvider = FutureProvider.autoDispose
    .family<List<CustomerOption>, String>((ref, q) {
      ref.watch(currentUserIdProvider);
      return ref.read(paymentsRepositoryProvider).customers(q);
    });

/// Tahsilat işlemleri (durum değişiklikleri; belirsiz sonuçta kayıt yeniden okunur — spec C.4a).
final paymentActionsProvider = Provider<PaymentActions>(PaymentActions.new);

class PaymentActions {
  PaymentActions(this.ref);

  final Ref ref;

  PaymentsRepository get _repo => ref.read(paymentsRepositoryProvider);

  static const conflictText =
      'Bu kayıt sizden sonra güncellendi. Yenileyip tekrar deneyin; seçiminiz korunur.';

  void _invalidate(int? orderId) {
    ref.invalidate(paymentsListProvider);
    ref.invalidate(instrumentsListProvider);
    if (orderId != null) ref.invalidate(paymentDetailProvider(orderId));
  }

  /// Sipariş ödeme durumunu değiştirir.
  Future<ActionOutcome> changeStatus(
    PaymentDetail d,
    PaymentStatus to, {
    String? note,
    String? attachmentPublicId,
  }) => _changeStatus(
    d,
    to,
    note: note,
    attachmentPublicId: attachmentPublicId,
    retried: false,
  );

  Future<ActionOutcome> _changeStatus(
    PaymentDetail d,
    PaymentStatus to, {
    String? note,
    String? attachmentPublicId,
    required bool retried,
  }) async {
    final done = 'Ödeme durumu "${to.label}" olarak güncellendi.';
    final ledger = ref.read(a5IdempotencyLedgerProvider);
    final intent = jsonEncode([
      'payments.status',
      d.orderId,
      to.code,
      d.concurrencyToken,
      note?.trim() ?? '',
      attachmentPublicId ?? '',
    ]);
    final key = ledger.keyFor(intent);
    try {
      await runWithRetry(
        () => _repo.changeStatus(
          d.orderId,
          to: to,
          concurrencyToken: d.concurrencyToken,
          note: note,
          attachmentPublicId: attachmentPublicId,
          idempotencyKey: key,
        ),
        schedule: ref.read(a5RetryScheduleProvider),
      );
      ledger.settle(intent);
      _invalidate(d.orderId);
      return ActionDone(done);
    } on AppFailure catch (f) {
      ledger.settle(intent, error: f);
      if (f is ValidationFailure) {
        return ActionInvalid(f.message, {
          for (final e in f.fieldErrors.entries)
            if (e.value.isNotEmpty) e.key: e.value.first,
        });
      }
      // Belirsiz sonuç ya da çakışma: kayıt yeniden okunur; hedef duruma ulaşıldıysa başarı.
      if (isRetryable(f) || f.isUncertain || f is ConflictFailure) {
        PaymentDetail? fresh;
        try {
          fresh = await _repo.detail(d.orderId);
        } catch (_) {
          fresh = null;
        }
        if (fresh != null &&
            fresh.row.paymentStatus == to &&
            fresh.concurrencyToken != d.concurrencyToken) {
          _invalidate(d.orderId);
          return ActionDone(done);
        }
        // Belge yüklenince sunucu bekleyen ödemeyi kendiliğinden "Belge yüklendi" yapar ve sürümü
        // yeniler (ör. dekontu müşteri ya da başka bir personel ekledi). Başka bir değişiklik yoksa
        // ve seçilen geçiş hâlâ izinliyse yeni sürümle bir kez yeniden denenir.
        if (!retried &&
            fresh != null &&
            f is ConflictFailure &&
            f.isConcurrency &&
            d.row.paymentStatus == PaymentStatus.pending &&
            fresh.row.paymentStatus == PaymentStatus.documentUploaded &&
            fresh.allowedTransitions.contains(to)) {
          return _changeStatus(
            fresh,
            to,
            note: note,
            attachmentPublicId: attachmentPublicId,
            retried: true,
          );
        }
      }
      if (f is ConflictFailure && f.isConcurrency) {
        return const ActionConflict(conflictText);
      }
      if (isRetryable(f) || f.isUncertain) {
        return const ActionUnverified(
          'Sonuç doğrulanamadı. Bağlantınızı kontrol edip ekranı yenileyin.',
        );
      }
      return ActionFailed(f);
    }
  }

  /// Çek / senet portföy durumunu değiştirir.
  Future<ActionOutcome> changeInstrumentStatus(
    Instrument i,
    InstrumentStatus to, {
    String? note,
  }) async {
    final ledger = ref.read(a5IdempotencyLedgerProvider);
    final intent = jsonEncode([
      'payments.instrument',
      i.id,
      i.status.code,
      to.code,
      note?.trim() ?? '',
    ]);
    try {
      await _repo.changeInstrumentStatus(
        i.id,
        to: to,
        note: note,
        idempotencyKey: ledger.keyFor(intent),
      );
      ledger.settle(intent);
      _invalidate(i.orderId);
      return ActionDone('${i.displayKindLabel} durumu "${to.label}" oldu.');
    } on AppFailure catch (f) {
      ledger.settle(intent, error: f);
      if (f is ValidationFailure) {
        return ActionInvalid(f.message, {
          for (final e in f.fieldErrors.entries)
            if (e.value.isNotEmpty) e.key: e.value.first,
        });
      }
      if (f is ConflictFailure && f.isConcurrency) {
        _invalidate(i.orderId);
        return const ActionConflict(conflictText);
      }
      if (f.isUncertain) {
        _invalidate(i.orderId);
        return const ActionUnverified(
          'Sonuç doğrulanamadı. Liste yenilendi; durumu kontrol edin.',
        );
      }
      return ActionFailed(f);
    }
  }
}

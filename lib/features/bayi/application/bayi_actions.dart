import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/network/idempotency.dart';
import '../../../core/utils/tr_time.dart';
import '../../../core/utils/turkish_text.dart';
import '../data/bayi_repository.dart';
import '../data/customer_models.dart';
import '../data/dispatch_models.dart';
import 'bayi_runtime.dart';

/// Bayi ekranlarının durum değiştiren işlemleri (spec C.4a): tek niyet = tek anahtar, belirsiz sonuçta
/// aynı anahtarla tekrar, 400 / 409 / zaman aşımında yeniden okuyup hedef duruma ulaşıldıysa başarı.
/// Başarıdan sonra ilgili ekranlara "değişti" yayınlanır. Hatalar `AppFailure` olarak fırlar.
class BayiActions {
  BayiActions(this.ref);

  final Ref ref;

  BayiRepository get _repo => ref.read(bayiRepositoryProvider);
  IdempotencyLedger get _ledger => ref.read(bayiIdempotencyProvider);
  List<Duration> get _delays => ref.read(bayiRetryDelaysProvider);

  void _emit(List<BayiChange> changes) =>
      ref.read(bayiChangesProvider).emit(changes);

  // ------------------------------------------------------------------ Sipariş

  /// Tekil teklif (sipariş ayrıntısı).
  ///
  /// Teklif cari limitini aşıyorsa ve bayi kuralı aşımı finansa gönderiyorsa sunucu siparişi finans
  /// onayına alır, bunu kaydeder ve ardından 400 iş kuralı döner ("…sipariş finans onayına
  /// gönderildi. Finans onaylayınca teklifi yeniden girin."; teklif kaydedilmez). Bu durumda sipariş
  /// yeniden okunur: [wasAwaitingFinance] değilken artık finans kararı bekleniyorsa sonuç
  /// [BayiOutcome.routedToFinance] olur (hata değil). Her sonuçta, hata da olsa, sipariş ve teklif
  /// ekranları tazelenir.
  Future<BayiOutcome> quoteOrder(
    int orderId, {
    required double unitPrice,
    required DateTime deliveryDate,
    bool wasAwaitingFinance = false,
  }) async {
    try {
      final outcome = await runTransition(
        call: () => _repo.quoteOrder(
          orderId,
          unitPrice: unitPrice,
          deliveryDate: deliveryDate,
        ),
        reconcile: () async {
          final o = await _repo.order(orderId);
          final q = o.currentQuote;
          return o.status == OrderStatus.awaitingApproval &&
              q != null &&
              (q.unitPriceTry - unitPrice).abs() < 0.00005;
        },
      );
      return outcome;
    } on AppFailure catch (f) {
      if (!wasAwaitingFinance &&
          (f is BusinessFailure || f is ConflictFailure)) {
        try {
          final o = await _repo.order(orderId);
          if (o.financeStatus.isAwaitingDecision) {
            return BayiOutcome.routedToFinance;
          }
        } on AppFailure catch (_) {
          // Okunamadı: asıl hata gösterilir.
        }
      }
      rethrow;
    } finally {
      _emit(const [BayiChange.quotes, BayiChange.orders]);
    }
  }

  /// Siparişi tamamla (tüm litre teslim alındı).
  Future<BayiOutcome> completeOrder(int orderId) async {
    final outcome = await runTransition(
      call: () => _repo.completeOrder(orderId),
      reconcile: () async =>
          (await _repo.order(orderId)).status == OrderStatus.completed,
    );
    _emit(const [BayiChange.orders]);
    return outcome;
  }

  // ------------------------------------------------------------------ Sevkiyat

  /// Sevkiyat planla (Idempotency-Key). Belirsiz sonuçta siparişin sevkiyatları okunur; aynı plan
  /// görülürse başarı sayılır.
  Future<BayiOutcome> planShipment(
    PlanShipmentDraft draft, {
    VoidCallback? onChecking,
  }) async {
    final outcome = await runIdempotent(
      ledger: _ledger,
      intent: draft.intent,
      delays: _delays,
      onChecking: onChecking,
      call: (key) => _repo.planShipment(draft, idempotencyKey: key),
      reconcile: () async {
        final f = await _repo.fulfillment(draft.orderId);
        return f.shipments.any(
          (s) =>
              s.status == ShipmentStatus.planned &&
              (s.plannedLiters - draft.plannedLiters).abs() < 0.0005 &&
              _samePlate(s.vehiclePlate, draft.vehiclePlate) &&
              s.scheduledAt != null &&
              s.scheduledAt!.difference(draft.scheduledAt).inMinutes.abs() < 1,
        );
      },
    );
    _emit(const [BayiChange.shipments, BayiChange.orders]);
    return outcome;
  }

  /// Şoför değiştir (Idempotency-Key; yalnızca planlı sevkiyat).
  Future<BayiOutcome> assignDriver(
    int shipmentId, {
    required StationDriver driver,
    String? vehiclePlate,
    VoidCallback? onChecking,
  }) async {
    final plate = vehiclePlate?.trim();
    final outcome = await runIdempotent(
      ledger: _ledger,
      intent: 'assign:$shipmentId:${driver.userId}:${plate ?? ''}',
      delays: _delays,
      onChecking: onChecking,
      call: (key) => _repo.assignDriver(
        shipmentId,
        driverUserId: driver.userId,
        vehiclePlate: plate == null || plate.isEmpty ? null : plate,
        idempotencyKey: key,
      ),
      reconcile: () async =>
          (await _repo.shipmentDetail(shipmentId)).driverUserId ==
          driver.userId,
    );
    _emit(const [BayiChange.shipments]);
    return outcome;
  }

  /// Yola çıkar (uygulaması olmayan şoför için personel).
  Future<BayiOutcome> dispatch(int shipmentId) async {
    final outcome = await runTransition(
      call: () => _repo.dispatch(shipmentId),
      reconcile: () async {
        final s = (await _repo.shipmentDetail(shipmentId)).status;
        return s == ShipmentStatus.inTransit ||
            s == ShipmentStatus.reported ||
            s == ShipmentStatus.accepted;
      },
    );
    _emit(const [BayiChange.shipments, BayiChange.orders]);
    return outcome;
  }

  /// Teslim bildir / Teslimatı düzelt.
  Future<BayiOutcome> report(
    int shipmentId, {
    required double deliveredLiters,
    required String deliveryDocumentNo,
  }) async {
    final outcome = await runTransition(
      call: () => _repo.report(
        shipmentId,
        deliveredLiters: deliveredLiters,
        deliveryDocumentNo: deliveryDocumentNo,
      ),
      reconcile: () async {
        final d = await _repo.shipmentDetail(shipmentId);
        return d.status == ShipmentStatus.reported &&
            (d.deliveredLiters ?? -1) == deliveredLiters &&
            TurkishText.searchKey(d.deliveryDocumentNo ?? '') ==
                TurkishText.searchKey(deliveryDocumentNo);
      },
    );
    _emit(const [BayiChange.shipments, BayiChange.orders]);
    return outcome;
  }

  /// Planı iptal et.
  Future<BayiOutcome> cancelShipment(int shipmentId) async {
    final outcome = await runTransition(
      call: () => _repo.cancelShipment(shipmentId),
      reconcile: () async =>
          (await _repo.shipmentDetail(shipmentId)).status ==
          ShipmentStatus.cancelled,
    );
    _emit(const [BayiChange.shipments, BayiChange.orders]);
    return outcome;
  }

  // ------------------------------------------------------------------ Cari

  /// Görüşme notu (Idempotency-Key; aynı not iki kez kaydedilmez).
  Future<CustomerNote> addNote(int customerId, String body) async {
    CustomerNote? note;
    await runIdempotent(
      ledger: _ledger,
      intent: 'note:$customerId:${body.trim()}',
      delays: _delays,
      call: (key) async {
        note = await _repo.addNote(customerId, body, idempotencyKey: key);
      },
    );
    return note!;
  }

  Future<void> deleteNote(int customerId, int noteId) =>
      _repo.deleteNote(customerId, noteId);

  /// Limit değişikliği talebi (merkez onayına). Belirsiz sonuçta kart okunur: bekleyen talep görülürse
  /// başarı sayılır.
  Future<BayiOutcome> requestLimit(
    int customerId,
    LimitRequestDraft draft,
  ) async {
    final outcome = await runTransition(
      call: () => _repo.createLimitRequest(customerId, draft),
      // Yalnızca bu talebin kendisi bekliyorsa (başkasının açtığı talep "gönderildi" sayılmaz).
      reconcile: () async {
        final p = (await _repo.customerSummary(customerId)).pendingLimitRequest;
        if (p == null || p.period != draft.limitPeriod) return false;
        if (draft.isUnlimited) return true;
        return p.limitType == draft.limitType &&
            p.amount != null &&
            draft.limitAmount != null &&
            (p.amount! - draft.limitAmount!).abs() < 0.005;
      },
    );
    _emit(const [BayiChange.customer]);
    return outcome;
  }

  static bool _samePlate(String a, String b) {
    String n(String s) => s.asciiUpper.replaceAll(RegExp(r'[^0-9A-Z]'), '');
    return n(a) == n(b);
  }
}

final bayiActionsProvider = Provider<BayiActions>(BayiActions.new);

/// Plan saatinin varsayılanı: istenen gün 09:00; bugünse bir saat sonrası (çeyreğe yuvarlanmış).
DateTime defaultScheduleFor(DateTime? requestedDay) {
  final today = TrTime.todayStart();
  final day = requestedDay == null || requestedDay.isBefore(today)
      ? today
      : TrTime.startOfDay(requestedDay);
  final nine = day.add(const Duration(hours: 9));
  final now = TrTime.now();
  if (nine.isAfter(now)) return nine;
  final soon = now.add(const Duration(hours: 1));
  final w = TrTime.wall(soon);
  final minute = ((w.minute + 14) ~/ 15) * 15;
  return TrTime.fromWall(
    w.year,
    w.month,
    w.day,
    w.hour,
  ).add(Duration(minutes: minute));
}

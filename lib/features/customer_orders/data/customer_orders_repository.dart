import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/models.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_providers.dart';
import '../../../core/utils/tr_time.dart';
import 'form_models.dart';
import 'home_models.dart';
import 'order_models.dart';
import 'payment_models.dart';
import 'place_models.dart';

/// Teklif kararı (`orders/{id}/approve|reject|revise`).
enum QuoteAction {
  approve('approve', 'Onayla', OrderStatus.approved),
  revise('revise', 'Revize iste', OrderStatus.revisionRequested),
  reject('reject', 'Reddet', OrderStatus.rejected);

  const QuoteAction(this.path, this.label, this.targetStatus);
  final String path;
  final String label;

  /// Karar işlendiğinde siparişin ulaştığı durum (belirsiz sonuçta doğrulama için).
  final OrderStatus targetStatus;

  /// Sipariş bu kararın sonucuna ulaşmış mı (onay sonrası tamamlanmış da sayılır).
  bool reached(OrderStatus s) =>
      s == targetStatus || (this == approve && s == OrderStatus.completed);
}

/// Aylık harcama (`SpendingMonthDto`; ana sayfa eğrisi).
@immutable
class SpendingMonth {
  const SpendingMonth({
    required this.year,
    required this.month,
    this.liters = 0,
    this.amount = 0,
    this.shortLabel,
  });

  factory SpendingMonth.fromJson(JsonReader r) => SpendingMonth(
    year: r.integer('year'),
    month: r.integer('month'),
    liters: r.dec('liters'),
    amount: r.dec('amount'),
    shortLabel: r.nonEmpty('shortLabel'),
  );

  final int year;
  final int month;
  final double liters;
  final double amount;
  final String? shortLabel;
}

/// Müşteri sipariş uçları (spec B.6, B.15). Tüm hatalar `AppFailure`.
class CustomerOrdersRepository {
  CustomerOrdersRepository(this.api);

  final ApiClient api;

  // ------------------------------------------------------------------ Ana sayfa

  Future<CustomerHomeData> home() =>
      api.get('home/customer', parse: CustomerHomeData.fromJson);

  /// Ham ana sayfa gövdesi (önbelleğe olduğu gibi yazılır).
  Future<Object?> homeRaw() => api.get('home/customer', parse: (j) => j);

  Future<OrderingStatus> orderingStatus(int? stationId) => api.get(
    'customers/me/ordering-status',
    query: {'stationId': stationId},
    parse: OrderingStatus.parse,
  );

  /// Son [months] ayın harcaması (sunucu toplamları).
  Future<List<SpendingMonth>> spendingMonths({int months = 6}) {
    final today = TrTime.wall(TrTime.now());
    final from = DateTime(today.year, today.month - (months - 1));
    String d(DateTime x) =>
        '${x.year.toString().padLeft(4, '0')}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    return api.get(
      'customers/me/spending',
      query: {
        'fromDate': d(from),
        'toDate': d(DateTime(today.year, today.month, today.day)),
      },
      quiet403: true,
      parse: (j) => JsonReader.of(j).list('months', SpendingMonth.fromJson),
    );
  }

  // ------------------------------------------------------------------ Siparişlerim

  Future<PagedResult<CustomerOrderRow>> orders({
    required OrderSegment segment,
    String? q,
    int page = 1,
    int pageSize = 25,
  }) => api.get(
    'customers/me/orders',
    query: {
      'segment': segment.code,
      'q': q,
      'page': page,
      'pageSize': pageSize,
    },
    parse: (j) => PagedResult.fromJson(j, CustomerOrderRow.fromJson),
  );

  /// Ham sayfa (önbellek için).
  Future<Object?> ordersRaw({
    required OrderSegment segment,
    String? q,
    int page = 1,
    int pageSize = 25,
  }) => api.get(
    'customers/me/orders',
    query: {
      'segment': segment.code,
      'q': q,
      'page': page,
      'pageSize': pageSize,
    },
    parse: (j) => j,
  );

  // ------------------------------------------------------------------ Sipariş formu

  Future<Object?> orderFormRaw() =>
      api.get('catalog/order-form', parse: (j) => j);

  Future<CustomerPaymentOptions> paymentOptions({
    required int stationId,
    required Iterable<int> productIds,
  }) => api.get(
    'payments/options',
    query: {
      'stationId': stationId,
      'productIds': productIds.toSet().toList()..sort(),
    },
    parse: CustomerPaymentOptions.fromJson,
  );

  /// Sipariş ver. [idempotencyKey] kullanıcı onayında üretilir ve sonuç kesinleşene kadar korunur.
  Future<PlaceOrderResult> place(
    PlaceOrderRequest request, {
    required String idempotencyKey,
  }) => api.post(
    'orders/place',
    body: request.toJson(),
    idempotencyKey: idempotencyKey,
    parse: PlaceOrderResult.fromJson,
  );

  /// Ödeme belgesi hedefi; belge gerekmiyorsa null (204).
  Future<PaymentUploadTarget?> documentTarget({
    String? methodCode,
    String? groupKey,
    Iterable<int> orderIds = const [],
  }) => api.get(
    'orders/payment-document-target',
    query: {
      'methodCode': methodCode,
      'groupKey': groupKey,
      'orderIds': orderIds.toList(),
    },
    parse: PaymentUploadTarget.tryParse,
  );

  // ------------------------------------------------------------------ Sipariş ayrıntısı

  Future<Object?> orderRaw(int id) => api.get('orders/$id', parse: (j) => j);

  Future<OrderDetail> order(int id) =>
      api.get('orders/$id', parse: OrderDetail.fromJson);

  Future<Object?> trackingRaw(int id) =>
      api.get('orders/$id/tracking', parse: (j) => j);

  /// Teklif kararı. [expectedQuoteId] ekranda görülen teklif; son teklif değilse 409.
  Future<void> decide(
    int orderId,
    QuoteAction action, {
    String? note,
    int? expectedQuoteId,
    required String idempotencyKey,
  }) => api.post<void>(
    'orders/$orderId/${action.path}',
    body: {
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      'expectedQuoteId': ?expectedQuoteId,
    },
    idempotencyKey: idempotencyKey,
  );

  Future<List<Attachment>> attachments(
    AttachmentOwnerType ownerType,
    int ownerId,
  ) => api.get(
    'attachments',
    query: {'ownerType': ownerType.code, 'ownerId': ownerId},
    parse: (j) => JsonReader.parseList(j, Attachment.fromJson),
  );

  // ------------------------------------------------------------------ Şablonlar

  Future<List<TemplateListItem>> templates() => api.get(
    'customers/me/templates',
    parse: (j) => JsonReader.parseList(j, TemplateListItem.fromJson),
  );

  Future<OrderTemplate> template(int id) =>
      api.get('customers/me/templates/$id', parse: OrderTemplate.fromJson);

  Future<OrderTemplate> saveTemplate({
    int? id,
    required String name,
    required List<
      ({int productId, int deliveryPointId, double liters, int? stationId})
    >
    lines,
  }) => api.post(
    'customers/me/templates',
    body: {
      'id': ?id,
      'name': name.trim(),
      'lines': [
        for (final l in lines)
          {
            'productId': l.productId,
            'deliveryPointId': l.deliveryPointId,
            'quantityLiters': l.liters,
            'stationId': ?l.stationId,
          },
      ],
    },
    parse: OrderTemplate.fromJson,
  );

  Future<void> deleteTemplate(int id) =>
      api.delete<void>('customers/me/templates/$id');

  /// Siparişten kaydedilmemiş şablon taslağı (Id 0).
  Future<OrderTemplate> templateFromOrder(int orderId) => api.post(
    'customers/me/templates/from-order',
    query: {'orderId': orderId},
    parse: OrderTemplate.fromJson,
  );

  // ------------------------------------------------------------------ Şirket içi talepler

  Future<OrderRequestSnapshot> orderRequest(int id) => api.get(
    'customers/me/order-requests/$id',
    parse: OrderRequestSnapshot.parse,
  );

  /// Son talepler (sonuç doğrulaması).
  Future<List<OrderRequestSnapshot>> recentOrderRequests({int take = 10}) =>
      api.get(
        'customers/me/order-requests',
        query: {'skip': 0, 'take': take},
        quiet403: true,
        parse: (j) =>
            JsonReader.of(j).list('items', OrderRequestSnapshot.fromJson),
      );
}

final customerOrdersRepositoryProvider = Provider<CustomerOrdersRepository>(
  (ref) => CustomerOrdersRepository(ref.watch(apiClientProvider)),
);

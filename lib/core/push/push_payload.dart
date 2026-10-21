import 'package:flutter/foundation.dart';

/// Push verisi (spec B.4): `notification {title, body}` + `data {type, notificationId, route,
/// entityType, entityId, category}` (hepsi metin). Push tekrar edebilir; uygulama her birini
/// "yeniden yükle" sinyali sayar.
@immutable
class PushPayload {
  const PushPayload({
    this.type,
    this.notificationId,
    this.route,
    this.entityType,
    this.entityId,
    this.category,
    this.title,
    this.body,
    this.receivedAt,
  });

  factory PushPayload.fromData(
    Map<String, dynamic> data, {
    String? title,
    String? body,
  }) {
    String? s(String k) {
      final v = data[k];
      if (v == null) return null;
      final t = '$v'.trim();
      return t.isEmpty ? null : t;
    }

    return PushPayload(
      type: s('type'),
      notificationId: int.tryParse(s('notificationId') ?? ''),
      route: s('route'),
      entityType: s('entityType'),
      entityId: int.tryParse(s('entityId') ?? ''),
      category: s('category'),
      title: title ?? s('title'),
      body: body ?? s('body'),
      receivedAt: DateTime.now().toUtc(),
    );
  }

  /// Olay kodu (`order.quote_ready`, `shipment.reported` …).
  final String? type;
  final int? notificationId;

  /// Uygulama rotası (`/orders/12`).
  final String? route;

  /// `Order`, `Shipment`, `ApprovalRequest`, `FieldOrderForm`, `CustomerLead` …
  final String? entityType;
  final int? entityId;

  /// `orders`, `quotes`, `shipments`, `payments`, `approvals`, `field`, `system`.
  final String? category;
  final String? title;
  final String? body;
  final DateTime? receivedAt;

  /// Olay kodu [prefix] ile mi başlıyor (`isFor('order.')`).
  bool isFor(String prefix) => type?.startsWith(prefix) ?? false;

  @override
  String toString() => 'PushPayload($type, $entityType#$entityId → $route)';
}

/// Push olayının nereden geldiği.
enum PushOrigin {
  /// Uygulama açıkken geldi (uygulama içi bildirim).
  foreground,

  /// Kullanıcı bildirime dokundu (uygulama arka plandaydı ya da kapalıydı).
  tap,
}

/// Özelliklerin dinlediği push olayı (`pushEventsProvider`).
@immutable
class PushEvent {
  const PushEvent(this.payload, this.origin);
  final PushPayload payload;
  final PushOrigin origin;
}

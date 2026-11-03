import 'dart:convert';

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

  /// Yerel bildirime dokunuşun verisi ([toLocalPayload]). Ön planda gösterilen push'un kopyası push
  /// verisinin JSON'unu taşır: dokunuş kilit ekranındaki push gibi aynı rotayı, aynı olayı ve aynı
  /// `?focus=` bloğunu açar. Eski bildirimlerde (bildirim merkezinde kalmış olabilir) veri düz rotadır;
  /// o da eskisi gibi açılır. Okunamayan veri düz rota sayılır (biçimsizse `/notifications`).
  factory PushPayload.fromLocalPayload(String? raw) {
    final text = raw?.trim();
    if (text != null && text.startsWith('{')) {
      try {
        final data = jsonDecode(text);
        if (data is Map) {
          return PushPayload.fromData(data.cast<String, dynamic>());
        }
      } on FormatException {
        // Düz rota gibi.
      }
    }
    return PushPayload(route: raw, receivedAt: DateTime.now().toUtc());
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

  /// Yerel bildirim kopyasının dokunuş verisi: push verisinin anahtarlarıyla JSON
  /// ([PushPayload.fromLocalPayload] geri okur; varış zamanı dokunuşta yeniden konur).
  String toLocalPayload() => jsonEncode({
    'type': ?type,
    'notificationId': ?notificationId,
    'route': ?route,
    'entityType': ?entityType,
    'entityId': ?entityId,
    'category': ?category,
    'title': ?title,
    'body': ?body,
  });

  @override
  String toString() => 'PushPayload($type, $entityType#$entityId → $route)';
}

/// Push olayının nereden geldiği.
enum PushOrigin {
  /// Uygulama açıkken geldi: uygulama kapalıyken olduğu gibi sistem bildirimi olur
  /// ([PushEvent.presented]); gösterilemezse uygulama içi bildirim.
  foreground,

  /// Kullanıcı bildirime dokundu (uygulama arka plandaydı ya da kapalıydı; ön planda gösterilen
  /// sistem bildirimine dokunuş da).
  tap,
}

/// Özelliklerin dinlediği push olayı (`pushEventsProvider`).
@immutable
class PushEvent {
  const PushEvent(this.payload, this.origin, {this.presented = false});
  final PushPayload payload;
  final PushOrigin origin;

  /// Ön plan push'u sistem bildirimi olarak gösterildi mi (iOS bandı, Android yerel bildirim;
  /// Bildirim Merkezi'nde kalır). false ise uygulama içi balon gösterilir. Dokunuşta false.
  final bool presented;
}

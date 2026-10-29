import 'package:flutter/material.dart';

import '../../../core/models/json.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/turkish_text.dart';

/// Bildirim kategorileri (sunucu `NotificationCategories`; tercih ekranındaki sıra).
abstract final class NotificationCategory {
  static const orders = 'orders';
  static const quotes = 'quotes';
  static const shipments = 'shipments';
  static const payments = 'payments';
  static const approvals = 'approvals';
  static const field = 'field';
  static const system = 'system';

  static const all = [
    orders,
    quotes,
    shipments,
    payments,
    approvals,
    field,
    system,
  ];

  /// Sunucu etiketi yoksa kullanılan Türkçe ad.
  static String label(String category) => switch (category) {
    orders => 'Siparişler',
    quotes => 'Teklifler',
    shipments => 'Teslimatlar',
    payments => 'Ödemeler',
    approvals => 'Onaylar',
    field => 'Saha',
    system => 'Sistem',
    _ => 'Diğer',
  };

  /// Tercih ekranındaki açıklama.
  static String description(String category) => switch (category) {
    orders => 'Yeni, süresi dolan ve tamamlanan siparişler, finans durumu',
    quotes => 'Teklif hazır, onay, ret ve revize talepleri',
    shipments => 'Planlama, yola çıkış, teslim ve itirazlar',
    payments => 'Belge yükleme, tahsilat ve vadesi yaklaşan ödemeler',
    approvals => 'Kararınızı bekleyen talepler ve sonuçları',
    field => 'Saha formu ve ön kayıt kararları',
    // Merkezin panelden gönderdiği duyurular da bu kategoridedir (kapatılırsa push gelmez, kutuda kalır).
    system => 'Merkez duyuruları, kampanyalar ve hesap bildirimleri',
    _ => '',
  };

  static IconData icon(String category) => switch (category) {
    orders => PhosphorIconsFill.receipt,
    quotes => PhosphorIconsFill.invoice,
    shipments => PhosphorIconsFill.truck,
    payments => PhosphorIconsRegular.money,
    approvals => PhosphorIconsFill.checkCircle,
    field => PhosphorIconsRegular.storefront,
    _ => PhosphorIconsFill.bell,
  };
}

/// `UserNotificationDto` (spec B.4): gelen kutusu satırı. Tarihler UTC.
@immutable
class UserNotification {
  const UserNotification({
    required this.id,
    required this.category,
    required this.eventCode,
    required this.title,
    required this.body,
    required this.createdAt,
    this.categoryLabel,
    this.severity = 0,
    this.route,
    this.entityType,
    this.entityId,
    this.readAt,
  });

  factory UserNotification.fromJson(JsonReader r) => UserNotification(
    id: r.integer('id'),
    category: r.str('category', NotificationCategory.system),
    categoryLabel: r.nonEmpty('categoryLabel'),
    eventCode: r.str('eventCode'),
    title: TurkishText.commaList(r.str('title')),
    body: TurkishText.commaList(r.str('body')),
    severity: r.integer('severity'),
    route: r.nonEmpty('route'),
    entityType: r.nonEmpty('entityType'),
    entityId: r.intOrNull('entityId'),
    createdAt: r.dateUtc('createdAt') ?? DateTime.now().toUtc(),
    readAt: r.dateUtc('readAt'),
  );

  final int id;
  final String category;
  final String? categoryLabel;
  final String eventCode;
  final String title;
  final String body;

  /// 0 bilgi, 1 olumlu, 2 uyarı, 3 tehlike.
  final int severity;

  /// Uygulama içi derin bağlantı (`/orders/12`).
  final String? route;
  final String? entityType;
  final int? entityId;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  String get label => categoryLabel ?? NotificationCategory.label(category);

  /// Önem derecesinin tonu (renk tek başına anlam taşımaz: başlık ve metin her zaman yazılır).
  AknTone get tone => switch (severity) {
    1 => AknTone.ok,
    2 => AknTone.warn,
    3 => AknTone.danger,
    _ => AknTone.info,
  };

  UserNotification markedRead(DateTime at) => UserNotification(
    id: id,
    category: category,
    categoryLabel: categoryLabel,
    eventCode: eventCode,
    title: title,
    body: body,
    severity: severity,
    route: route,
    entityType: entityType,
    entityId: entityId,
    createdAt: createdAt,
    readAt: readAt ?? at,
  );

  UserNotification markedUnread() => UserNotification(
    id: id,
    category: category,
    categoryLabel: categoryLabel,
    eventCode: eventCode,
    title: title,
    body: body,
    severity: severity,
    route: route,
    entityType: entityType,
    entityId: entityId,
    createdAt: createdAt,
  );

  JsonMap toJson() => {
    'id': id,
    'category': category,
    'categoryLabel': categoryLabel,
    'eventCode': eventCode,
    'title': title,
    'body': body,
    'severity': severity,
    'route': route,
    'entityType': entityType,
    'entityId': entityId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'readAt': readAt?.toUtc().toIso8601String(),
  };
}

/// `NotificationPreferenceDto`: kategori başına push açık/kapalı (gelen kutusu her durumda tutulur).
@immutable
class NotificationPreference {
  const NotificationPreference({
    required this.category,
    required this.label,
    required this.pushEnabled,
  });

  factory NotificationPreference.fromJson(JsonReader r) {
    final category = r.str('category');
    return NotificationPreference(
      category: category,
      label: r.nonEmpty('label') ?? NotificationCategory.label(category),
      pushEnabled: r.boolean('pushEnabled', true),
    );
  }

  final String category;
  final String label;
  final bool pushEnabled;

  NotificationPreference withPush(bool enabled) => NotificationPreference(
    category: category,
    label: label,
    pushEnabled: enabled,
  );

  JsonMap toJson() => {'category': category, 'pushEnabled': pushEnabled};
}

/// `POST notifications/test` → `{devices, sent}`.
@immutable
class NotificationTestResult {
  const NotificationTestResult({required this.devices, required this.sent});

  factory NotificationTestResult.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return NotificationTestResult(
      devices: r.integer('devices'),
      sent: r.integer('sent'),
    );
  }

  final int devices;
  final int sent;
}

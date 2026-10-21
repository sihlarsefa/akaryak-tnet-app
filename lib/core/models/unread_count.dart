import 'package:flutter/foundation.dart';

import 'json.dart';

/// `GET notifications/unread-count` → `{notifications, approvals}` (zil ve Onaylarım rozetleri).
@immutable
class UnreadCount {
  const UnreadCount({this.notifications = 0, this.approvals = 0});

  static const zero = UnreadCount();

  factory UnreadCount.fromJson(Object? json) {
    final r = JsonReader.of(json);
    return UnreadCount(
      notifications: r.integer('notifications'),
      approvals: r.integer('approvals'),
    );
  }

  final int notifications;
  final int approvals;

  JsonMap toJson() => {'notifications': notifications, 'approvals': approvals};

  @override
  bool operator ==(Object other) =>
      other is UnreadCount &&
      other.notifications == notifications &&
      other.approvals == approvals;

  @override
  int get hashCode => Object.hash(notifications, approvals);

  @override
  String toString() => 'UnreadCount($notifications, $approvals)';
}

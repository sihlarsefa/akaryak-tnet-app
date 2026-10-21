import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/json.dart';
import '../../../core/models/paged_result.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_providers.dart';
import 'notification_models.dart';

/// Bildirim kutusu uçları (spec B.4, `api/v1/notifications`).
class NotificationsRepository {
  NotificationsRepository(this._api);

  final ApiClient _api;

  static const pageSize = 25;

  Future<PagedResult<UserNotification>> list({
    int page = 1,
    bool unreadOnly = false,
  }) => _api.get(
    'notifications',
    query: {
      'page': page,
      'pageSize': pageSize,
      if (unreadOnly) 'unreadOnly': true,
    },
    parse: (j) => PagedResult.fromJson(j, UserNotification.fromJson),
  );

  Future<void> markRead(int id) => _api.post<void>('notifications/$id/read');

  Future<void> markAllRead() => _api.post<void>('notifications/read-all');

  Future<List<NotificationPreference>> preferences() => _api.get(
    'notifications/preferences',
    parse: (j) => JsonReader.parseList(j, NotificationPreference.fromJson),
  );

  /// Tam listeyi gönderir; sunucunun güncel listesi döner.
  Future<List<NotificationPreference>> savePreferences(
    List<NotificationPreference> prefs,
  ) => _api.put(
    'notifications/preferences',
    body: [for (final p in prefs) p.toJson()],
    parse: (j) => JsonReader.parseList(j, NotificationPreference.fromJson),
  );

  /// "Test bildirimi" (saatte 3).
  Future<NotificationTestResult> sendTest() =>
      _api.post('notifications/test', parse: NotificationTestResult.fromJson);
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(apiClientProvider)),
);

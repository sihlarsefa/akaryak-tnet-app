import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_controller.dart';

/// Entities the viewer opened (or finished) in this session (v4 §3.5): their
/// notifications read as read on this device at once, before the server
/// catches up. The router marks every entity page it opens; the
/// notifications inbox reads [isRead] for a notification's route.
///
/// Keys are entity paths: `/orders/12002`, `/shipments/7`,
/// `/approvals/31`, `/bayi/orders/12001`, `/driver/shipments/7`,
/// `/company/requests/4`, `/payments/12002`, `/customers/5`.
final localReadMarksProvider = NotifierProvider<LocalReadMarks, Set<String>>(
  LocalReadMarks.new,
);

class LocalReadMarks extends Notifier<Set<String>> {
  /// Entity pages (a path that ends in an id).
  static final RegExp _entity = RegExp(
    r'^/(orders|shipments|approvals|bayi/orders|driver/shipments|company/requests|payments|customers|finance/customers|field/forms|field/leads)/\d+$',
  );

  @override
  Set<String> build() {
    // A new user starts with no marks.
    ref.watch(currentUserIdProvider);
    return const <String>{};
  }

  /// The entity path of [location], or null when it is not an entity page.
  static String? entityOf(String? location) {
    if (location == null) return null;
    final path = Uri.tryParse(location)?.path;
    if (path == null || !_entity.hasMatch(path)) return null;
    return path;
  }

  /// Marks the entity at [location] (opened or finished).
  void mark(String location) {
    final path = entityOf(location);
    if (path == null || state.contains(path)) return;
    state = {...state, path};
  }

  /// True when the notification [route] points at an entity marked here.
  bool isRead(String? route) {
    final path = entityOf(route);
    return path != null && state.contains(path);
  }
}

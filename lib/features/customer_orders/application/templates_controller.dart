import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/network/app_failure.dart';
import '../data/customer_orders_repository.dart';
import '../data/form_models.dart';
import 'loadable.dart';

/// Şablonlarım (`GET customers/me/templates`, en son kullanılan önce).
final templatesProvider =
    NotifierProvider.autoDispose<
      TemplatesController,
      Loadable<List<TemplateListItem>>
    >(TemplatesController.new);

class TemplatesController
    extends AutoDisposeNotifier<Loadable<List<TemplateListItem>>> {
  int _epoch = 0;
  bool _alive = true;

  @override
  Loadable<List<TemplateListItem>> build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    final uid = ref.watch(currentUserIdProvider);
    final epoch = ++_epoch;
    if (uid == null) return const Loadable();
    Future.microtask(() => _load(epoch));
    return const Loadable.initial();
  }

  Future<void> refresh() => _load(_epoch);

  Future<void> _load(int epoch) async {
    if (!_alive) return;
    state = state.copyWith(loading: true);
    try {
      final list = await ref.read(customerOrdersRepositoryProvider).templates();
      if (!_alive || epoch != _epoch) return;
      state = Loadable(data: list, updatedAt: DateTime.now().toUtc());
    } on AppFailure catch (f) {
      if (!_alive || epoch != _epoch) return;
      state = state.copyWith(loading: false, error: f);
    }
  }

  /// Siler; listeden hemen kaldırır (hata olursa geri yükler ve fırlatır).
  Future<void> delete(int id) async {
    final before = state.data ?? const <TemplateListItem>[];
    state = state.copyWith(data: before.where((t) => t.id != id).toList());
    try {
      await ref.read(customerOrdersRepositoryProvider).deleteTemplate(id);
    } on AppFailure {
      if (_alive) state = state.copyWith(data: before);
      rethrow;
    }
  }
}

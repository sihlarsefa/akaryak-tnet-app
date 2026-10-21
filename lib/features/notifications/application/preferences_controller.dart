import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/network/app_failure.dart';
import '../data/notification_models.dart';
import '../data/notifications_repository.dart';

/// Bildirim tercihleri ekranının durumu.
@immutable
class PreferencesState {
  const PreferencesState({
    this.items = const [],
    this.loading = true,
    this.error,
    this.saving = const {},
  });

  final List<NotificationPreference> items;
  final bool loading;
  final AppFailure? error;

  /// Kaydedilmekte olan kategoriler (anahtar kısa süre kilitlenir).
  final Set<String> saving;

  PreferencesState copyWith({
    List<NotificationPreference>? items,
    bool? loading,
    AppFailure? Function()? error,
    Set<String>? saving,
  }) => PreferencesState(
    items: items ?? this.items,
    loading: loading ?? this.loading,
    error: error == null ? this.error : error(),
    saving: saving ?? this.saving,
  );
}

/// Kategori başına push tercihi (spec B.4 `GET|PUT notifications/preferences`). Anahtar iyimser
/// değişir; sunucu reddederse eski değere döner.
final preferencesControllerProvider =
    NotifierProvider.autoDispose<PreferencesController, PreferencesState>(
      PreferencesController.new,
    );

class PreferencesController extends AutoDisposeNotifier<PreferencesState> {
  int _epoch = 0;
  bool _disposed = false;

  NotificationsRepository get _repo =>
      ref.read(notificationsRepositoryProvider);

  @override
  PreferencesState build() {
    ref.watch(currentUserIdProvider);
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    final epoch = ++_epoch;
    Future.microtask(() => _load(epoch));
    return const PreferencesState();
  }

  Future<void> _load(int epoch) async {
    try {
      final items = await _repo.preferences();
      if (_disposed || epoch != _epoch) return;
      state = state.copyWith(
        items: _ordered(items),
        loading: false,
        error: () => null,
      );
    } catch (e) {
      if (_disposed || epoch != _epoch) return;
      state = state.copyWith(loading: false, error: () => AppFailure.from(e));
    }
  }

  Future<void> reload() {
    final epoch = ++_epoch;
    state = state.copyWith(loading: true, error: () => null);
    return _load(epoch);
  }

  /// Anahtarı değiştirir; hata olursa geri alır ve hatayı döndürür.
  Future<AppFailure?> toggle(String category, bool enabled) async {
    final before = state.items;
    final next = [
      for (final p in before) p.category == category ? p.withPush(enabled) : p,
    ];
    state = state.copyWith(items: next, saving: {...state.saving, category});
    try {
      final saved = await _repo.savePreferences(next);
      if (_disposed) return null;
      state = state.copyWith(
        items: saved.isEmpty ? next : _ordered(saved),
        saving: {...state.saving}..remove(category),
      );
      return null;
    } catch (e) {
      if (_disposed) return AppFailure.from(e);
      state = state.copyWith(
        items: [
          for (final p in state.items)
            p.category == category
                ? before.firstWhere((b) => b.category == category)
                : p,
        ],
        saving: {...state.saving}..remove(category),
      );
      return AppFailure.from(e);
    }
  }

  /// "Test bildirimi gönder".
  Future<NotificationTestResult> sendTest() => _repo.sendTest();

  static List<NotificationPreference> _ordered(
    List<NotificationPreference> items,
  ) {
    int rank(String c) {
      final i = NotificationCategory.all.indexOf(c);
      return i < 0 ? 99 : i;
    }

    return [...items]..sort((a, b) => rank(a.category) - rank(b.category));
  }
}

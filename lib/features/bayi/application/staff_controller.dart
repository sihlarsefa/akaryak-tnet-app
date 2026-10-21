import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/utils/turkish_text.dart';
import '../data/bayi_repository.dart';
import '../data/staff_models.dart';
import 'bayi_runtime.dart';

/// Ekip süzgeci.
enum StaffFilter {
  active('Aktif'),
  passive('Pasif'),
  all('Tümü');

  const StaffFilter(this.label);
  final String label;
}

/// Ekip ekranı durumu.
@immutable
class StaffState {
  const StaffState({
    this.data = const Loadable.loading(),
    this.filter = StaffFilter.active,
    this.query = '',
    this.busy = const {},
  });

  final Loadable<List<StaffMember>> data;
  final StaffFilter filter;
  final String query;

  /// İşlem süren kullanıcılar (anahtar ve düğme kilitlenir).
  final Set<String> busy;

  List<StaffMember> get all => data.data ?? const [];

  /// Süzgeç + arama uygulanmış, Türkçe ada göre sıralı liste.
  List<StaffMember> get visible {
    final q = query.trim();
    final rows =
        all.where((m) {
          final passFilter = switch (filter) {
            StaffFilter.active => m.isActive,
            StaffFilter.passive => !m.isActive,
            StaffFilter.all => true,
          };
          if (!passFilter) return false;
          if (q.isEmpty) return true;
          return TurkishText.matches(m.displayName, q) ||
              TurkishText.matches(m.email, q) ||
              TurkishText.matches(m.phoneNumber, q) ||
              m.roleLabels.any((r) => TurkishText.matches(r, q));
        }).toList()..sort(
          (a, b) => TurkishText.searchKey(
            a.displayName,
          ).compareTo(TurkishText.searchKey(b.displayName)),
        );
    return rows;
  }

  int countOf(StaffFilter f) => switch (f) {
    StaffFilter.active => all.where((m) => m.isActive).length,
    StaffFilter.passive => all.where((m) => !m.isActive).length,
    StaffFilter.all => all.length,
  };

  StaffState copyWith({
    Loadable<List<StaffMember>>? data,
    StaffFilter? filter,
    String? query,
    Set<String>? busy,
  }) => StaffState(
    data: data ?? this.data,
    filter: filter ?? this.filter,
    query: query ?? this.query,
    busy: busy ?? this.busy,
  );
}

/// Ekip (`stations/me/staff`): rol çipleri, arama, aktif / pasif, şifre bağlantısı.
final staffProvider = NotifierProvider<StaffController, StaffState>(
  StaffController.new,
);

class StaffController extends Notifier<StaffState> {
  int _epoch = 0;

  BayiRepository get _repo => ref.read(bayiRepositoryProvider);

  @override
  StaffState build() {
    final user = ref.watch(currentUserIdProvider);
    final sub = ref.read(bayiChangesProvider).stream.listen((c) {
      if (c == BayiChange.staff) unawaited(refresh());
    });
    ref.onDispose(sub.cancel);
    if (user == null) return const StaffState(data: Loadable());
    Future.microtask(refresh);
    return const StaffState();
  }

  Future<void> refresh() async {
    final epoch = ++_epoch;
    final d = state.data;
    state = state.copyWith(
      data: d.hasData
          ? d.copyWith(refreshing: true, error: null)
          : const Loadable.loading(),
    );
    try {
      final rows = await _repo.staff();
      if (epoch != _epoch) return;
      state = state.copyWith(
        data: Loadable(
          data: List.unmodifiable(rows),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    } catch (e) {
      if (epoch != _epoch) return;
      final f = AppFailure.from(e);
      state = state.copyWith(
        data: state.data.hasData
            ? state.data.copyWith(refreshing: false, loading: false, error: f)
            : Loadable(error: f),
      );
    }
  }

  void setFilter(StaffFilter f) => state = state.copyWith(filter: f);

  void setQuery(String q) => state = state.copyWith(query: q);

  /// Aktif / pasif. Sonuç kesin değilse (bağlantı, zaman aşımı) liste yeniden okunur ve hedef duruma
  /// ulaşıldıysa başarı sayılır.
  Future<void> setActive(StaffMember m, bool active) async {
    if (state.busy.contains(m.userId)) return;
    _setBusy(m.userId, true);
    _replace(m.copyWith(isActive: active));
    try {
      await runTransition(
        call: () => _repo.setStaffActive(m.userId, active),
        reconcile: () async {
          final rows = await _repo.staff();
          return rows.any((r) => r.userId == m.userId && r.isActive == active);
        },
      );
    } catch (_) {
      _replace(m);
      rethrow;
    } finally {
      _setBusy(m.userId, false);
    }
  }

  /// "Şifre bağlantısı gönder" (personelin e-postasına).
  Future<void> sendPasswordLink(StaffMember m) async {
    if (state.busy.contains(m.userId)) return;
    _setBusy(m.userId, true);
    try {
      await _repo.sendPasswordReset(m.userId);
    } finally {
      _setBusy(m.userId, false);
    }
  }

  void _setBusy(String userId, bool busy) {
    final next = Set<String>.of(state.busy);
    busy ? next.add(userId) : next.remove(userId);
    state = state.copyWith(busy: Set.unmodifiable(next));
  }

  void _replace(StaffMember m) {
    final rows = state.all;
    if (rows.isEmpty) return;
    state = state.copyWith(
      data: state.data.copyWith(
        data: List.unmodifiable([
          for (final r in rows) r.userId == m.userId ? m : r,
        ]),
      ),
    );
  }
}

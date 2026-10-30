import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/models/enums.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/utils/log.dart';
import '../data/company.dart';
import '../data/customer_more_repository.dart';
import '../data/finance_info.dart';

@immutable
class CompanyUsersState {
  const CompanyUsersState({
    this.users = const [],
    this.thresholds,
    this.loading = true,
    this.refreshing = false,
    this.error,
  });

  final List<CompanyUser> users;
  final ApprovalThresholds? thresholds;
  final bool loading;
  final bool refreshing;
  final AppFailure? error;

  int get activeAdmins =>
      users.where((u) => u.isActive && u.role == CustomerUserRole.admin).length;

  CompanyUsersState copyWith({
    List<CompanyUser>? users,
    ApprovalThresholds? thresholds,
    bool? loading,
    bool? refreshing,
    AppFailure? error,
    bool clearError = false,
  }) => CompanyUsersState(
    users: users ?? this.users,
    thresholds: thresholds ?? this.thresholds,
    loading: loading ?? this.loading,
    refreshing: refreshing ?? this.refreshing,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Şirket kullanıcıları ve onay eşikleri (`customers/me/company-users*`; yalnızca Yönetici). Roller v5:
/// şirket içi onay kapalıysa (`me/access.companyApprovalsEnabled == false`) eşikler istenmez; açıkken
/// eşiklerin yüklenememesi sayfayı düşürmez (kullanıcılar görünür, eşik kartı gizlenir).
final companyUsersControllerProvider =
    NotifierProvider.autoDispose<CompanyUsersController, CompanyUsersState>(
      CompanyUsersController.new,
    );

class CompanyUsersController extends AutoDisposeNotifier<CompanyUsersState> {
  int _epoch = 0;
  bool _disposed = false;

  @override
  CompanyUsersState build() {
    ref.watch(currentUserIdProvider);
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _epoch++;
    });
    Future.microtask(load);
    return const CompanyUsersState();
  }

  CustomerMoreRepository get _repo => ref.read(customerMoreRepositoryProvider);

  Future<void> load() async {
    if (_disposed) return;
    final epoch = ++_epoch;
    final s = state;
    state = s.copyWith(
      loading: s.users.isEmpty,
      refreshing: s.users.isNotEmpty,
      clearError: true,
    );
    final thresholds = ref.read(accessPolicyProvider).companyApprovals
        ? _thresholdsOrNull()
        : Future<ApprovalThresholds?>.value();
    try {
      final users = await _repo.companyUsers();
      final t = await thresholds;
      if (epoch != _epoch) return;
      state = state.copyWith(
        users: users,
        thresholds: t,
        loading: false,
        refreshing: false,
      );
    } catch (e) {
      if (epoch != _epoch) return;
      state = state.copyWith(
        loading: false,
        refreshing: false,
        error: AppFailure.from(e),
      );
    }
  }

  /// Onay eşikleri; yüklenemezse null (kart gizlenir; liste yine açılır).
  Future<ApprovalThresholds?> _thresholdsOrNull() async {
    try {
      return await _repo.approvalThresholds();
    } catch (e) {
      AppLog.debug('Şirket içi onay eşikleri yüklenemedi: $e');
      return null;
    }
  }

  void _replace(CompanyUser u) {
    if (_disposed) return;
    final list = [
      for (final x in state.users)
        if (x.userId == u.userId) u else x,
    ];
    if (!list.any((x) => x.userId == u.userId)) list.add(u);
    state = state.copyWith(users: list);
  }

  Future<CompanyUser> add({
    required String displayName,
    required String userName,
    String? email,
    String? password,
    String? phone,
    required CustomerUserRole role,
  }) async {
    final u = await _repo.createCompanyUser(
      displayName: displayName,
      userName: userName,
      email: email,
      password: password,
      phoneNumber: phone,
      role: role,
    );
    _replace(u);
    unawaited(load());
    return u;
  }

  Future<CompanyUser> update(
    CompanyUser user, {
    required String displayName,
    String? phone,
    required CustomerUserRole role,
  }) async {
    final u = await _repo.updateCompanyUser(
      userId: user.userId,
      displayName: displayName,
      phoneNumber: phone,
      role: role,
    );
    _replace(u);
    return u;
  }

  Future<String> setActive(CompanyUser user, bool active) async {
    final message = await _repo.setCompanyUserActive(user.userId, active);
    unawaited(load());
    return message ??
        (active ? 'Kullanıcı aktifleştirildi.' : 'Kullanıcı pasifleştirildi.');
  }

  Future<void> sendLink(CompanyUser user) =>
      _repo.sendPasswordLink(user.userId);

  /// "Şifre belirle": yöneticinin verdiği yeni şifre (sunucu kuralları; hata olduğu gibi döner).
  Future<void> setPassword(CompanyUser user, String newPassword) =>
      _repo.setCompanyUserPassword(user.userId, newPassword);

  Future<ApprovalThresholds> saveThresholds({
    double? aboveLitres,
    double? aboveAmount,
  }) async {
    final error = ApprovalThresholds.validate(aboveLitres, aboveAmount);
    if (error != null) throw BusinessFailure(error);
    final t = await _repo.saveApprovalThresholds(
      aboveLitres: aboveLitres,
      aboveAmount: aboveAmount,
    );
    if (!_disposed) state = state.copyWith(thresholds: t);
    return t;
  }
}

/// `GET customers/me/finance-info` → `{links, orders}`.
final financeInfoProvider = FutureProvider.autoDispose<FinanceInfo>((ref) {
  ref.watch(currentUserIdProvider);
  return ref.read(customerMoreRepositoryProvider).financeInfo();
});

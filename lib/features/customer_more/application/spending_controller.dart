import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/network/app_failure.dart';
import '../data/customer_more_repository.dart';
import '../data/spending.dart';

/// Harcama sekmeleri (Ay / Ürün / Nokta / Bayi).
enum SpendingTab {
  month('Ay'),
  product('Ürün'),
  point('Nokta'),
  station('Bayi');

  const SpendingTab(this.label);
  final String label;
}

/// Grafik ölçüsü.
enum SpendingMetric {
  amount('Tutar'),
  liters('Litre');

  const SpendingMetric(this.label);
  final String label;
}

/// Hazır aralıklar (web "Hızlı aralık").
enum SpendingPreset {
  last3('Son 3 ay'),
  last6('Son 6 ay'),
  last12('Son 12 ay'),
  thisYear('Bu yıl'),
  lastYear('Geçen yıl'),
  last36('Son 36 ay'),
  custom('Özel');

  const SpendingPreset(this.label);
  final String label;

  SpendingRange? range({DateTime? now}) => switch (this) {
    last3 => SpendingRange.lastMonths(3, now: now),
    last6 => SpendingRange.lastMonths(6, now: now),
    last12 => SpendingRange.lastMonths(12, now: now),
    thisYear => SpendingRange.thisYear(now: now),
    lastYear => SpendingRange.lastYear(now: now),
    last36 => SpendingRange.lastMonths(36, now: now),
    custom => null,
  };
}

/// Etkin süzgeç (kırılım satırından süzme).
@immutable
class SpendingFilter {
  const SpendingFilter({
    this.deliveryPointId,
    this.deliveryPointName,
    this.productId,
    this.productName,
    this.stationId,
    this.stationName,
  });

  final int? deliveryPointId;
  final String? deliveryPointName;
  final int? productId;
  final String? productName;
  final int? stationId;
  final String? stationName;

  bool get isEmpty =>
      deliveryPointId == null && productId == null && stationId == null;

  @override
  bool operator ==(Object other) =>
      other is SpendingFilter &&
      other.deliveryPointId == deliveryPointId &&
      other.productId == productId &&
      other.stationId == stationId;

  @override
  int get hashCode => Object.hash(deliveryPointId, productId, stationId);
}

@immutable
class SpendingState {
  const SpendingState({
    required this.range,
    this.preset = SpendingPreset.last12,
    this.tab = SpendingTab.month,
    this.metric = SpendingMetric.amount,
    this.filter = const SpendingFilter(),
    this.report,
    this.loading = true,
    this.error,
    this.clamped = false,
  });

  final SpendingRange range;
  final SpendingPreset preset;
  final SpendingTab tab;
  final SpendingMetric metric;
  final SpendingFilter filter;
  final SpendingReport? report;
  final bool loading;
  final AppFailure? error;

  /// Aralık 36 aydan genişti; başlangıç kırpıldı.
  final bool clamped;

  SpendingState copyWith({
    SpendingRange? range,
    SpendingPreset? preset,
    SpendingTab? tab,
    SpendingMetric? metric,
    SpendingFilter? filter,
    SpendingReport? report,
    bool? loading,
    AppFailure? error,
    bool clearError = false,
    bool? clamped,
  }) => SpendingState(
    range: range ?? this.range,
    preset: preset ?? this.preset,
    tab: tab ?? this.tab,
    metric: metric ?? this.metric,
    filter: filter ?? this.filter,
    report: report ?? this.report,
    loading: loading ?? this.loading,
    error: clearError ? null : (error ?? this.error),
    clamped: clamped ?? this.clamped,
  );
}

/// `GET customers/me/spending`: yalnızca sunucu toplamları gösterilir (uygulama hesaplamaz).
final spendingControllerProvider =
    NotifierProvider.autoDispose<SpendingController, SpendingState>(
      SpendingController.new,
    );

class SpendingController extends AutoDisposeNotifier<SpendingState> {
  int _epoch = 0;
  bool _disposed = false;

  @override
  SpendingState build() {
    ref.watch(currentUserIdProvider);
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _epoch++;
    });
    Future.microtask(load);
    return SpendingState(range: SpendingRange.lastMonths(12));
  }

  Future<void> load() async {
    if (_disposed) return;
    final epoch = ++_epoch;
    final s = state;
    state = s.copyWith(loading: true, clearError: true);
    try {
      final f = s.filter;
      final report = await ref
          .read(customerMoreRepositoryProvider)
          .spending(
            s.range,
            deliveryPointId: f.deliveryPointId,
            productId: f.productId,
            stationId: f.stationId,
          );
      if (epoch != _epoch) return;
      state = state.copyWith(report: report, loading: false);
    } catch (e) {
      if (epoch != _epoch) return;
      state = state.copyWith(loading: false, error: AppFailure.from(e));
    }
  }

  void setPreset(SpendingPreset preset) {
    final r = preset.range();
    if (r == null) return;
    state = state.copyWith(range: r, preset: preset, clamped: false);
    unawaited(load());
  }

  /// Özel aralık (en geniş 36 ay; daha genişi başlangıçtan kırpılır, kullanıcıya bildirilir).
  void setCustomRange(SpendingRange range) {
    final n = range.normalized();
    state = state.copyWith(
      range: n,
      preset: SpendingPreset.custom,
      clamped: n.from != range.from && !range.from.isAfter(range.to),
    );
    unawaited(load());
  }

  void setTab(SpendingTab tab) => state = state.copyWith(tab: tab);

  void setMetric(SpendingMetric m) => state = state.copyWith(metric: m);

  void setFilter(SpendingFilter f) {
    if (f == state.filter) return;
    state = state.copyWith(filter: f);
    unawaited(load());
  }
}

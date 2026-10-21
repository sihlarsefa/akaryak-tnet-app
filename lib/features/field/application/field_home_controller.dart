import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/models/json.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/cache_store.dart';
import '../../../core/utils/tr_time.dart';
import '../data/field_models.dart';
import '../data/field_repository.dart';
import '../data/lead_models.dart';
import 'field_access.dart';
import 'field_lists.dart';

/// Saha ana sayfası özeti: taslaklar, onay bekleyenler, son 30 günde reddedilenler, portföy sayısı ve
/// ön kayıtlar. Sayılar listelerle aynı uçlardan gelir (gösterilen satırlarla her zaman tutarlı).
@immutable
class FieldHomeData {
  const FieldHomeData({
    this.drafts = 0,
    this.recentDrafts = const [],
    this.pending = 0,
    this.recentPending = const [],
    this.rejected = 0,
    this.recentRejected = const [],
    this.portfolioCount,
    this.leadStats,
    this.leadsNeedingInfo = const [],
    this.leadsNeedingInfoCount = 0,
    this.failed = const {},
  });

  factory FieldHomeData.fromRaw(JsonMap raw) {
    final r = JsonReader(raw);
    FieldFormsPage page(String key) => FieldFormsPage.fromJson(r[key]);
    final d = page('drafts');
    final p = page('pending');
    final x = page('rejected');
    final leads = r['leadsInfo'] == null
        ? null
        : FieldRepository.parseLeads(r['leadsInfo']);
    return FieldHomeData(
      drafts: d.totalCount,
      recentDrafts: d.items,
      pending: p.totalCount,
      recentPending: p.items,
      rejected: x.totalCount,
      recentRejected: x.items,
      portfolioCount: r.intOrNull('portfolioCount'),
      leadStats: r['leadStats'] == null
          ? null
          : LeadStats.fromJson(r['leadStats']),
      leadsNeedingInfo: leads?.items ?? const [],
      leadsNeedingInfoCount: leads?.totalCount ?? 0,
      failed: Set.unmodifiable(r.strings('failed')),
    );
  }

  final int drafts;
  final List<FieldFormRow> recentDrafts;
  final int pending;
  final List<FieldFormRow> recentPending;
  final int rejected;
  final List<FieldFormRow> recentRejected;

  /// Yalnızca temsilci (portföy uç noktası); yüklenemediyse null.
  final int? portfolioCount;
  final LeadStats? leadStats;
  final List<LeadRow> leadsNeedingInfo;
  final int leadsNeedingInfoCount;

  /// Yetkisi olduğu hâlde yüklenemeyen bölümler (`forms`, `portfolio`, `leads`).
  final Set<String> failed;
}

@immutable
class FieldHomeState {
  const FieldHomeState({
    this.data,
    this.loading = true,
    this.refreshing = false,
    this.error,
    this.cachedAt,
  });

  final FieldHomeData? data;
  final bool loading;
  final bool refreshing;
  final AppFailure? error;
  final DateTime? cachedAt;
}

final fieldHomeProvider =
    NotifierProvider.autoDispose<FieldHomeController, FieldHomeState>(
      FieldHomeController.new,
    );

class FieldHomeController extends AutoDisposeNotifier<FieldHomeState> {
  int _epoch = 0;

  static const _cacheName = 'field.home';

  @override
  FieldHomeState build() {
    ref.listen<int>(fieldSyncTickProvider, (_, _) => unawaited(refresh()));
    ref.watch(currentUserIdProvider);
    Future.microtask(_initial);
    return const FieldHomeState();
  }

  String? get _cacheKey {
    final uid = ref.read(currentUserIdProvider);
    return uid == null ? null : CacheKeys.user(uid, _cacheName);
  }

  Future<void> _initial() async {
    final key = _cacheKey;
    if (key != null) {
      final cached = await ref.read(cacheStoreProvider).read(key);
      if (cached != null && state.data == null) {
        try {
          state = FieldHomeState(
            data: FieldHomeData.fromRaw(JsonReader.asMap(cached.value)),
            loading: false,
            refreshing: true,
            cachedAt: cached.storedAt,
          );
        } catch (_) {
          // Bozuk önbellek: yok say.
        }
      }
    }
    await refresh();
  }

  Future<void> refresh() async {
    final epoch = ++_epoch;
    state = FieldHomeState(
      data: state.data,
      loading: state.data == null,
      refreshing: state.data != null,
      cachedAt: state.cachedAt,
    );
    final repo = ref.read(fieldRepositoryProvider);
    final access = ref.read(fieldAccessProvider);
    final failed = <String>{};
    final failures = <AppFailure>[];

    Future<Object?> guard(String section, Future<Object?> Function() f) async {
      try {
        return await f();
      } catch (e) {
        final failure = AppFailure.from(e);
        failures.add(failure);
        failed.add(section);
        return null;
      }
    }

    final now = TrTime.now();
    final monthStart = () {
      final w = TrTime.wall(now);
      return TrTime.fromWall(w.year, w.month);
    }();
    final forms = access.canSeeForms;
    final leads = access.canSeeLeads;
    final results = await Future.wait<Object?>([
      if (forms) ...[
        guard(
          'forms',
          () => repo.formsJson(const FieldFormsQuery(statuses: [0]), take: 3),
        ),
        guard(
          'forms',
          () => repo.formsJson(const FieldFormsQuery(statuses: [1]), take: 3),
        ),
        guard(
          'forms',
          () => repo.formsJson(
            FieldFormsQuery(
              statuses: const [3],
              fromUtc: now.subtract(const Duration(days: 30)),
            ),
            take: 3,
          ),
        ),
      ],
      if (access.isRep)
        guard(
          'portfolio',
          () async => JsonReader.of(
            await repo.portfolioJson(take: 1),
          ).integer('totalCount'),
        ),
      if (leads) ...[
        guard(
          'leads',
          () async =>
              (await repo.leadStats(from: monthStart, to: now)).toJson(),
        ),
        guard(
          'leads',
          () => repo.leadsJson(
            LeadsQuery(all: access.canSeeAllLeads, status: 'info'),
            size: 3,
          ),
        ),
      ],
    ]);
    if (epoch != _epoch) return;

    var i = 0;
    Object? next() => results[i++];
    final raw = <String, Object?>{};
    if (forms) {
      raw['drafts'] = next();
      raw['pending'] = next();
      raw['rejected'] = next();
    }
    if (access.isRep) raw['portfolioCount'] = next();
    if (leads) {
      raw['leadStats'] = next();
      raw['leadsInfo'] = next();
    }
    raw['failed'] = failed.toList();

    final allFailed =
        failures.isNotEmpty &&
        failures.length == results.length &&
        results.every((r) => r == null);
    if (allFailed) {
      // Hiçbir bölüm gelmedi: önbellekteki veri kalır, yoksa hata gösterilir.
      state = FieldHomeState(
        data: state.data,
        loading: false,
        error: failures.first,
        cachedAt: state.cachedAt,
      );
      return;
    }
    final data = FieldHomeData.fromRaw(raw);
    state = FieldHomeState(data: data, loading: false);
    final key = _cacheKey;
    if (key != null) {
      await ref
          .read(cacheStoreProvider)
          .write(
            key,
            raw,
            userId: ref.read(currentUserIdProvider),
            ttl: const Duration(days: 7),
          );
    }
  }
}

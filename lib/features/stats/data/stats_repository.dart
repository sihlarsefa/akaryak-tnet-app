import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/json.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/network_providers.dart';
import 'stats_models.dart';

/// Saha temsilcisinin form sayıları (`home/bayi` → `sections.field`). "Saha formlarım" kartı, sunucu
/// `team` içinde temsilcinin kendi satırını göndermezse bunu kullanır.
@immutable
class StatsFieldSummary {
  const StatsFieldSummary({
    this.drafts = 0,
    this.pending = 0,
    this.rejected = 0,
    this.converted = 0,
  });

  factory StatsFieldSummary.fromJson(JsonReader r) => StatsFieldSummary(
    drafts: r.integer('drafts'),
    pending: r.integer('pending'),
    rejected: r.integer('rejected'),
    converted: r.integer('converted'),
  );

  final int drafts;
  final int pending;
  final int rejected;
  final int converted;

  int get total => drafts + pending + rejected + converted;
}

/// İstatistik uçları (spec R1 §4). Her hata `AppFailure` olarak fırlar; 403 genel "yetkiniz yok"
/// bildirimi göstermez (deste kendini gizler, sayfa kendi durumunu gösterir).
class StatsRepository {
  StatsRepository(this.api);

  final ApiClient api;

  /// `GET stats/bayi?period=` → model + ham gövde (önbellek için).
  Future<({BayiStats data, Object? raw})> bayi(StatsPeriod period) => api.get(
    'stats/bayi',
    query: {'period': period.key},
    quiet403: true,
    parse: (j) => (data: BayiStats.fromJson(j, period: period), raw: j),
  );

  /// `GET stats/customer?period=` → model + ham gövde.
  Future<({CustomerStats data, Object? raw})> customer(StatsPeriod period) =>
      api.get(
        'stats/customer',
        query: {'period': period.key},
        quiet403: true,
        parse: (j) => (data: CustomerStats.fromJson(j, period: period), raw: j),
      );

  /// Saha bölümü (`home/bayi`); bölüm yoksa null.
  Future<StatsFieldSummary?> fieldSummary() => api.get(
    'home/bayi',
    quiet403: true,
    parse: (j) {
      final field = JsonReader.of(j).obj('sections').objOrNull('field');
      return field == null ? null : StatsFieldSummary.fromJson(field);
    },
  );
}

final statsRepositoryProvider = Provider<StatsRepository>(
  (ref) => StatsRepository(ref.watch(apiClientProvider)),
);

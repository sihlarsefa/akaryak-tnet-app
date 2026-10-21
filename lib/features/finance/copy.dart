/// Finans Türkçe metinleri.
library;

import 'dart:convert';

import '../../core/models/enums.dart';
import '../../core/utils/format.dart';
import '../../core/utils/tr_time.dart';
import 'data/finance_models.dart';

abstract final class FinanceCopy {
  static const title = 'Finans';
  static const subtitle = 'Cari finans kartları';
  static const searchHint = 'Cari ünvanı ya da VKN ara';
  static const allStatuses = 'Tümü';
  static const reviewOverdue = 'Gözden geçirmesi geçen';
  static const emptyTitle = 'Finans kartı yok';
  static const emptyMessage =
      'Bayinize bağlı carilerin finans kartları burada listelenir.';
  static const filteredTitle = 'Filtreye uyan kart yok';
  static const filteredMessage =
      'Filtreleri değiştirin ya da temizleyip tüm kartları görün.';
  static const clearFilters = 'Filtreleri temizle';
  static const notFoundTitle = 'Bu finans kartı artık görüntülenemiyor';

  /// Koşul JSON'unun (FinanceReview.ConditionsJson) okunur özeti.
  static String? describeConditions(String? json) {
    if (json == null || json.trim().isEmpty) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(json);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final parts = <String>[];
    decoded.forEach((k, v) {
      final key = '$k';
      final text = switch (key) {
        'methodCode' => 'Ödeme yöntemi: ${paymentMethodName('$v')}',
        'termDays' => 'Vade: $v gün',
        'limitAmount' => 'Limit: ${Fmt.money(double.tryParse('$v'))}',
        'limitPeriod' => 'Limit dönemi: $v',
        'maxTermDays' => 'En uzun vade: $v gün',
        'allowedMethodCodes' =>
          'İzinli yöntemler: ${(v is List ? v : '$v'.split(',')).map((c) => paymentMethodName('$c')).join(', ')}',
        'riskClass' => 'Risk sınıfı: $v',
        'collateralRatioPercent' =>
          'Teminat oranı: ${Fmt.percent(double.tryParse('$v'))}',
        'nextReviewDate' =>
          'Gözden geçirme: ${Fmt.date(TrTime.parseDate('$v'))}',
        'note' => null,
        _ => null,
      };
      if (text != null) parts.add(text);
    });
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// Kartı olmayan eski cari.
  static String statusLabel(FinanceProfileStatus? s) =>
      s?.label ?? 'Kart yok (eski cari)';
}

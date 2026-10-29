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

  // ---------------------------------------------------------------- v4 (§3.2, §5 09)

  /// Bant durumu: "1 cari finans onayınızı bekliyor"; dar bantta "1 cari onayınızda" (kimin onayı
  /// olduğu kısa sözde de kalır; satırın "Finans onayınızı bekliyor"u ile aynı kişi, v4 tur 2).
  static String pendingStatus(int n, {bool short = false}) =>
      short ? '$n cari onayınızda' : '$n cari finans onayınızı bekliyor';
  static const calmStatus = 'Onay bekleyen cari yok';

  /// Bant durumu, karar başkasındayken (sakin): "1 cari finans onayında".
  static String pendingElsewhereStatus(int n) => '$n cari finans onayında';

  /// Satırın üçüncü satırı (karar izleyenin sırası: talep Onaylar › Bende'de; Pas).
  static const pendingYourMove = 'Finans onayınızı bekliyor';

  /// Bekleyen kartın kararı başkasında (sakin not).
  static const pendingElsewhere = 'Finans onayında';

  /// Finans ek bilgi istedi; yanıt bekleniyor (sakin not).
  static const infoWaiting = 'Bilgi bekleniyor';

  /// Gözden geçirme günü geçti (uyarı).
  static const reviewOverdueLine = 'Gözden geçirme tarihi geçti';

  /// Limiti olmayan cari: "limitsiz" sınırsız kredi gibi okunur (v4 B16).
  static const noLimit = 'Limit tanımlanmadı';

  /// Kartın "Bağlantı limiti" değeri.
  static const noLimitValue = 'Tanımlanmadı';

  /// Kart alt çubuğunun birincili: talebi açar, karar orada (v4 B1). Düğme sözü yalın emirdir;
  /// müşterinin talep ayrıntısındaki "Karar ver"le aynı.
  static const decide = 'Karar ver';

  /// Gözden geçirme uyarısının eylemi: kart web portalında açılır.
  static const openInPortal = 'Portalda aç';

  static const groupAttention = 'Dikkat';
  static const groupAll = 'Tüm cariler';
  static const groupOthers = 'Diğer cariler';

  static const filterRisk = 'Risk sınıfı';
  static const filterReview = 'Gözden geçirme';
  static const filterSort = 'Sıralama';

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

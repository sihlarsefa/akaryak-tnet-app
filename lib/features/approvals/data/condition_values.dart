/// Koşullu onay formunun değerleri → karar isteğindeki `conditions` nesnesi (spec §B.8).
///
/// Kurallar:
/// - Yalnızca formun alanlarının anahtarları gönderilir; boş bırakılan alan "değişmez" demektir ve
///   gönderilmez. Kartta / kayıtta geçerli değerle ([ConditionField.current]) aynı girilen değer de
///   değişiklik sayılmaz.
/// - Değerler sunucu DTO'sunun tipleriyle gider (`FinanceDecisionConditions`): yöntem ve dönem metin,
///   vade gün sayısı tamsayı, tutar ve yüzde sayı, risk sınıfı sayı (1 A … 4 D), tarih `yyyy-MM-dd`,
///   izinli yöntemler dizi.
/// - Formdaki değerler ekranda "gönderilecek biçimde" metin olarak tutulur (sunucunun `current` /
///   `suggestion` biçimi: "30", "150000.5", "Aylık", "2", "2027-10-21", "CEK,HAVALE").
library;

import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';
import 'approval_models.dart';

/// Kullanıcının forma girdiği değerler (anahtar → gönderilecek biçimde metin).
typedef ConditionValues = Map<String, String?>;

/// Koşul doğrulama sonucu: alan anahtarı → Türkçe hata.
typedef ConditionErrors = Map<String, String>;

abstract final class ConditionValueCodec {
  /// Sayıyı değişmez kültürde yazar (`150000.5`, `25`).
  static String canonical(num value) {
    if (value is int || value == value.roundToDouble()) {
      return value.round().toString();
    }
    var s = value.toStringAsFixed(2);
    while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  /// "CEK,HAVALE" → ["CEK", "HAVALE"] (boşluklar ve tekrarlar atılır, sıra korunur).
  static List<String> splitCodes(String? csv) {
    final out = <String>[];
    for (final part in (csv ?? '').split(',')) {
      final c = part.trim();
      if (c.isNotEmpty && !out.contains(c)) out.add(c);
    }
    return out;
  }

  static String joinCodes(Iterable<String> codes) =>
      codes.where((c) => c.trim().isNotEmpty).join(',');

  /// İki değer aynı koşulu mu anlatıyor (tür bilerek: "30" == "30.0", yöntem listesi sırasız).
  static bool same(ConditionField field, String? a, String? b) {
    final x = a?.trim() ?? '';
    final y = b?.trim() ?? '';
    if (x.isEmpty || y.isEmpty) return x.isEmpty && y.isEmpty;
    switch (field.type) {
      case ConditionFieldTypes.integer:
      case ConditionFieldTypes.money:
      case ConditionFieldTypes.percent:
      case ConditionFieldTypes.riskClass:
        final nx = double.tryParse(x);
        final ny = double.tryParse(y);
        return nx != null && ny != null ? (nx - ny).abs() < 0.0001 : x == y;
      case ConditionFieldTypes.methods:
        final sx = splitCodes(x).toSet();
        final sy = splitCodes(y).toSet();
        return sx.length == sy.length && sx.containsAll(sy);
      default:
        return x == y;
    }
  }

  /// Formun değerlerinden `conditions` JSON nesnesi. Yalnızca formun anahtarları; boş ya da
  /// mevcut değerle aynı alanlar atlanır. Geçersiz sayılar atlanır (önce [validate] çağrılmalıdır).
  static Map<String, Object> build(ConditionForm form, ConditionValues values) {
    final out = <String, Object>{};
    for (final f in form.fields) {
      final raw = values[f.key]?.trim();
      if (raw == null || raw.isEmpty) continue;
      if (same(f, raw, f.current)) continue;
      final Object? v = switch (f.type) {
        ConditionFieldTypes.integer ||
        ConditionFieldTypes.riskClass => int.tryParse(raw),
        ConditionFieldTypes.money ||
        ConditionFieldTypes.percent => _number(raw),
        ConditionFieldTypes.methods => () {
          final codes = splitCodes(raw);
          return codes.isEmpty ? null : codes;
        }(),
        _ => raw,
      };
      if (v != null) out[f.key] = v;
    }
    return out;
  }

  static num? _number(String raw) {
    final d = double.tryParse(raw);
    if (d == null || !d.isFinite) return null;
    return d == d.roundToDouble() ? d.round() : d;
  }

  /// Alan doğrulaması (sunucu kurallarının aynası; sunucu yine denetler).
  static ConditionErrors validate(
    ConditionForm form,
    ConditionValues values, {
    DateTime? today,
  }) {
    final errors = <String, String>{};
    final allowedCodes = {for (final m in form.methodOptions) m.code};
    for (final f in form.fields) {
      final raw = values[f.key]?.trim();
      if (raw == null || raw.isEmpty) continue;
      switch (f.type) {
        case ConditionFieldTypes.integer:
          final n = int.tryParse(raw);
          if (n == null) {
            errors[f.key] = 'Tam sayı girin.';
          } else if (f.min != null && n < f.min!) {
            errors[f.key] = 'En az ${canonical(f.min!)} girilebilir.';
          } else if (f.max != null && n > f.max!) {
            errors[f.key] = 'En fazla ${canonical(f.max!)} girilebilir.';
          }
        case ConditionFieldTypes.money:
        case ConditionFieldTypes.percent:
          final n = double.tryParse(raw);
          if (n == null || !n.isFinite) {
            errors[f.key] = 'Geçerli bir sayı girin.';
          } else if (f.min != null && n < f.min!) {
            errors[f.key] = 'En az ${canonical(f.min!)} girilebilir.';
          } else if (f.max != null && n > f.max!) {
            errors[f.key] = f.type == ConditionFieldTypes.percent
                ? 'En fazla %${canonical(f.max!)} girilebilir.'
                : 'En fazla ${canonical(f.max!)} girilebilir.';
          }
        case ConditionFieldTypes.riskClass:
          final n = int.tryParse(raw);
          if (n == null || n < 1 || n > 4) {
            errors[f.key] = 'Risk sınıfı A, B, C ya da D olmalı.';
          }
        case ConditionFieldTypes.date:
          final d = TrTime.parseDate(raw);
          if (d == null) {
            errors[f.key] = 'Geçerli bir tarih seçin.';
          } else if (TrTime.dayDiff(today ?? TrTime.now(), d) < 0) {
            errors[f.key] = 'Tarih bugünden önce olamaz.';
          }
        case ConditionFieldTypes.method:
          if (allowedCodes.isNotEmpty && !allowedCodes.contains(raw)) {
            errors[f.key] = 'Bu ödeme yöntemi seçilemez.';
          }
        case ConditionFieldTypes.methods:
          final codes = splitCodes(raw);
          if (allowedCodes.isNotEmpty &&
              codes.any((c) => !allowedCodes.contains(c))) {
            errors[f.key] = 'Seçilemeyen bir ödeme yöntemi var.';
          }
        default:
          break;
      }
    }
    return errors;
  }

  /// Koşulun ekrandaki özeti ("Ödeme yöntemi: Havale; Vade (gün): 30").
  static String describe(ConditionForm form, Map<String, Object> conditions) {
    final parts = <String>[];
    for (final f in form.fields) {
      final v = conditions[f.key];
      if (v == null) continue;
      parts.add('${f.label}: ${display(form, f, v)}');
    }
    return parts.join('; ');
  }

  /// Bir koşul değerinin Türkçe gösterimi.
  static String display(ConditionForm form, ConditionField f, Object value) {
    switch (f.type) {
      case ConditionFieldTypes.method:
        return form.methodName('$value');
      case ConditionFieldTypes.methods:
        final codes = value is List
            ? [for (final c in value) '$c']
            : splitCodes('$value');
        return codes.map(form.methodName).join(', ');
      case ConditionFieldTypes.riskClass:
        for (final o in form.riskClassOptions) {
          if (o.code == '$value') return o.label;
        }
        return const {'1': 'A', '2': 'B', '3': 'C', '4': 'D'}['$value'] ??
            '$value';
      case ConditionFieldTypes.date:
        final d = TrTime.parseDate('$value');
        return d == null ? '$value' : Fmt.date(d);
      case ConditionFieldTypes.money:
        final n = value is num ? value : double.tryParse('$value');
        return n == null ? '$value' : Fmt.money(n);
      case ConditionFieldTypes.percent:
        final n = value is num ? value : double.tryParse('$value');
        return n == null ? '$value' : Fmt.percent(n, maxFraction: 2);
      case ConditionFieldTypes.period:
        for (final o in form.periodOptions) {
          if (o.code == '$value') return o.label;
        }
        return '$value';
      default:
        return '$value';
    }
  }
}

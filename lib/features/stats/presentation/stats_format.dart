import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';

/// İstatistik biçimleri (tr-TR, spec R1 §3.2). Kartlar kısa yazar ("21,5 Mn ₺", "820 B ₺",
/// "512.000 L", "1,2 Mn L", "%92", "▲ %8,6"); sayfa tam değeri gösterir ("21.500.000 ₺").
abstract final class StatsFmt {
  static const dash = Fmt.dash;

  // ------------------------------------------------------------------ Kısa sayılar

  static const _moneyDivs = [1e9, 1e6, 1e3, 1.0];
  static const _moneySuffix = ['Mr', 'Mn', 'B', ''];
  static const _moneySpoken = ['milyar', 'milyon', 'bin', ''];
  static const _literDivs = [1e9, 1e6, 1.0];
  static const _literSuffix = ['Mr', 'Mn', ''];
  static const _literSpoken = ['milyar', 'milyon', ''];

  /// Birim içindeki ondalık hane: Mr / Mn bir hane, bin 100'ün altında bir hane, tam sayı hanesiz.
  static int _fraction(double scaled, double div) {
    if (div >= 1e6) return 1;
    if (div >= 1e3) return scaled < 100 ? 1 : 0;
    return 0;
  }

  static double _round(double v, int fraction) {
    var f = 1.0;
    for (var i = 0; i < fraction; i++) {
      f *= 10;
    }
    return (v * f).round() / f;
  }

  /// [basis] için birim sırası; yuvarlanınca bir üst birime ulaşan değer o birimle yazılır
  /// (999.960 → "1 Mn", "1.000 B" değil).
  static int _unitFor(double basis, List<double> divs) {
    var i = divs.length - 1;
    for (var k = 0; k < divs.length; k++) {
      if (basis >= divs[k]) {
        i = k;
        break;
      }
    }
    while (i > 0) {
      final scaled = basis / divs[i];
      final rounded = _round(scaled, _fraction(scaled, divs[i]));
      if (rounded * divs[i] < divs[i - 1]) break;
      i--;
    }
    return i;
  }

  static String _compact(
    num value,
    List<double> divs,
    List<String> suffixes, {
    num? unitOf,
  }) {
    final v = value.toDouble();
    if (v.isNaN || v.isInfinite) return dash;
    final basis = (unitOf ?? value).toDouble().abs();
    final i = _unitFor(basis, divs);
    final div = divs[i];
    final digits = _fraction(basis / div, div);
    final scaled = _round(v.abs() / div, digits);
    final sign = v < 0 && scaled > 0 ? '-' : '';
    final text = Fmt.number(scaled, maxFraction: digits);
    return suffixes[i].isEmpty ? '$sign$text' : '$sign$text ${suffixes[i]}';
  }

  /// Kartlardaki tutar: `21,5 Mn ₺`, `820 B ₺`, `15,3 B ₺`, `950 ₺`, `1,2 Mr ₺`.
  static String moneyCompact(num? value) =>
      value == null ? dash : '${_compact(value, _moneyDivs, _moneySuffix)} ₺';

  /// Sayaç karesi: [value] [target]'ın biriminde yazılır (sayarken birim ve genişlik değişmez).
  static String moneyCompactAt(num value, num target) =>
      '${_compact(value, _moneyDivs, _moneySuffix, unitOf: target)} ₺';

  /// Eksen sayısı (birimsiz): `21,5 Mn`, `820 B`, `40`.
  static String compactNumber(num? value) =>
      value == null ? dash : _compact(value, _moneyDivs, _moneySuffix);

  /// Kartlardaki litre: `512.000 L`, `1,2 Mn L`.
  static String litersCompact(num? value) =>
      value == null ? dash : '${_compact(value, _literDivs, _literSuffix)} L';

  static String litersCompactAt(num value, num target) =>
      '${_compact(value, _literDivs, _literSuffix, unitOf: target)} L';

  /// Ekran okuyucu: "21,5 milyon lira", "820 bin lira".
  static String moneySpoken(num value) =>
      '${_compact(value, _moneyDivs, _moneySpoken)} lira';

  /// Ekran okuyucu: "512.000 litre", "1,2 milyon litre".
  static String litersSpoken(num value) =>
      '${_compact(value, _literDivs, _literSpoken)} litre';

  // ------------------------------------------------------------------ Tam değerler (sayfa)

  /// `21.500.000 ₺` (kuruşsuz).
  static String money(num? value) => Fmt.moneyWhole(value);

  /// `512.000 L`.
  static String liters(num? value) =>
      value == null ? dash : '${Fmt.number(value.round())} L';

  /// `42`.
  static String count(num? value) =>
      value == null ? dash : Fmt.number(value.round());

  /// Ortalama birim fiyat, iki hane: `42,50 ₺/L`.
  static String unitPrice(num? value) => value == null
      ? dash
      : '${Fmt.number(value, minFraction: 2, maxFraction: 2)} ₺/L';

  // ------------------------------------------------------------------ Oran ve fark

  /// Oran (0..1) → `%92` ([decimals] hane).
  static String rate(num? rate, {int decimals = 0}) =>
      rate == null ? dash : '%${Fmt.number(rate * 100, maxFraction: decimals)}';

  /// Önceki döneme göre yüzde değişim; önceki değer yoksa ya da sıfırsa null (çip gizlenir).
  static double? change(num? current, num? previous) {
    if (current == null || previous == null || previous <= 0) return null;
    return (current - previous) / previous * 100;
  }

  /// Değişim yok sayılan eşik (yüzde puanı).
  static const flatThreshold = 0.05;

  /// Yönsüz yüzde (çipte ok simgesinin yanında): `%8,6`, `%0`.
  static String deltaPercent(double percent) => percent.abs() < flatThreshold
      ? '%0'
      : '%${Fmt.number(percent.abs(), maxFraction: 1)}';

  /// `▲ %8,6`, `▼ %3,2`, `= %0`.
  static String delta(double percent) {
    if (percent.abs() < flatThreshold) return '= %0';
    final arrow = percent > 0 ? '▲' : '▼';
    return '$arrow %${Fmt.number(percent.abs(), maxFraction: 1)}';
  }

  /// Ekran okuyucu: "yüzde 8,6 artış", "yüzde 3,2 azalış", "değişim yok".
  static String deltaSpoken(double percent) {
    if (percent.abs() < flatThreshold) return 'değişim yok';
    final v = Fmt.number(percent.abs(), maxFraction: 1);
    return percent > 0 ? 'yüzde $v artış' : 'yüzde $v azalış';
  }

  /// Fark iyi mi: artış iyi (satış, litre) ya da [lowerIsBetter] ise düşüş iyi (birim fiyat).
  /// Değişim yoksa null.
  static bool? deltaIsGood(double percent, {bool lowerIsBetter = false}) {
    if (percent.abs() < flatThreshold) return null;
    return (percent > 0) != lowerIsBetter;
  }

  // ------------------------------------------------------------------ Süre ve tarih

  /// `34 dk`, `1 sa 20 dk`, `2 sa`, `1 g 3 sa`.
  static String minutes(num? minutes) {
    if (minutes == null || minutes.isNaN) return dash;
    final m = minutes.round();
    if (m < 60) return '$m dk';
    if (m < 24 * 60) {
      final h = m ~/ 60;
      final r = m % 60;
      return r == 0 ? '$h sa' : '$h sa $r dk';
    }
    final d = m ~/ (24 * 60);
    final h = (m % (24 * 60)) ~/ 60;
    return h == 0 ? '$d g' : '$d g $h sa';
  }

  /// Dönem aralığı: `1–21 Ekim 2026`, `24 Tem – 21 Eki 2026`, `1 Oca 2025 – 21 Eki 2026`.
  static String range(DateTime? from, DateTime? to) {
    if (from == null || to == null) return dash;
    final a = TrTime.wall(from);
    final b = TrTime.wall(to);
    if (a.year == b.year && a.month == b.month) {
      if (a.day == b.day) {
        return '${a.day} ${Fmt.monthNames[a.month - 1]} ${a.year}';
      }
      return '${a.day}–${b.day} ${Fmt.monthNames[a.month - 1]} ${a.year}';
    }
    if (a.year == b.year) {
      return '${a.day} ${Fmt.monthShort[a.month - 1]} – '
          '${b.day} ${Fmt.monthShort[b.month - 1]} ${b.year}';
    }
    return '${a.day} ${Fmt.monthShort[a.month - 1]} ${a.year} – '
        '${b.day} ${Fmt.monthShort[b.month - 1]} ${b.year}';
  }
}

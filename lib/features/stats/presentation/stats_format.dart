import '../../../core/utils/format.dart';
import '../../../core/utils/tr_time.dart';

/// İstatistik biçimleri (tr-TR, tasarım v2 §3.3). Plaka rakamı kuruşsuz tam sayıdır ("8.426.350 ₺");
/// okumalar, çubuk etiketleri ve sıralı satırlar üç anlamlı haneyle kısalır ("2,25 mn ₺",
/// "12,4 mn ₺", "820 bin ₺", "1,2 mn L"); oran "%92", fark "%9,4", birim fiyat "42,34 ₺/L".
/// "Mn", "B" gibi büyük harfli kısaltmalar ve " · " kullanılmaz.
abstract final class StatsFmt {
  static const dash = Fmt.dash;

  // ------------------------------------------------------------------ Kısa sayılar

  static const _moneyDivs = [1e9, 1e6, 1e3, 1.0];
  static const _moneySuffix = ['mr', 'mn', 'bin', ''];
  static const _moneySpoken = ['milyar', 'milyon', 'bin', ''];
  static const _literDivs = [1e9, 1e6, 1.0];
  static const _literSuffix = ['mr', 'mn', ''];
  static const _literSpoken = ['milyar', 'milyon', ''];

  /// "bin" birimi 10.000'den başlar: altı tam yazılır ("9.876 ₺").
  static const _thousandFrom = 1e4;

  /// Üç anlamlı hane: birimli değer 10'un altında iki, 100'ün altında bir ondalık; birimsiz tam sayı.
  static int _fraction(double scaled, double div) {
    if (div <= 1) return 0;
    if (scaled < 10) return 2;
    if (scaled < 100) return 1;
    return 0;
  }

  static double _round(double v, int fraction) {
    var f = 1.0;
    for (var i = 0; i < fraction; i++) {
      f *= 10;
    }
    return (v * f).round() / f;
  }

  static double _min(double div) => div == 1e3 ? _thousandFrom : div;

  /// [basis] için birim sırası; yuvarlanınca bir üst birime ulaşan değer o birimle yazılır
  /// (999.960 → "1 mn", "1.000 bin" değil).
  static int _unitFor(double basis, List<double> divs) {
    var i = divs.length - 1;
    for (var k = 0; k < divs.length; k++) {
      if (basis >= _min(divs[k])) {
        i = k;
        break;
      }
    }
    while (i > 0) {
      final scaled = basis / divs[i];
      final rounded = _round(scaled, _fraction(scaled, divs[i]));
      if (rounded * divs[i] < _min(divs[i - 1])) break;
      i--;
    }
    return i;
  }

  /// Kısa sayı ve birimi ayrı: (`2,25`, `mn`). [unitOf] verilirse birim ve hane sayısı onunkidir.
  static (String, String) _parts(
    num value,
    List<double> divs,
    List<String> suffixes, {
    num? unitOf,
  }) {
    final v = value.toDouble();
    if (v.isNaN || v.isInfinite) return (dash, '');
    final basis = (unitOf ?? value).toDouble().abs();
    final i = _unitFor(basis, divs);
    final div = divs[i];
    final digits = _fraction(basis / div, div);
    final scaled = _round(v.abs() / div, digits);
    final sign = v < 0 && scaled > 0 ? '-' : '';
    return ('$sign${Fmt.number(scaled, maxFraction: digits)}', suffixes[i]);
  }

  static String _join(String number, String suffix, [String? unit]) =>
      [number, if (suffix.isNotEmpty) suffix, ?unit].join(' ');

  /// Kısa tutar: `21,5 mn ₺`, `2,25 mn ₺`, `820 bin ₺`, `9.876 ₺`, `1,2 mr ₺`.
  static String moneyCompact(num? value) {
    if (value == null) return dash;
    final (n, s) = _parts(value, _moneyDivs, _moneySuffix);
    return _join(n, s, '₺');
  }

  /// [value] [target]'ın biriminde ve hane sayısında (aynı listede birim değişmez: "0,94 mn ₺").
  static String moneyCompactAt(num value, num target) {
    final (n, s) = _parts(value, _moneyDivs, _moneySuffix, unitOf: target);
    return _join(n, s, '₺');
  }

  /// Okuma için sayı ve birim ayrı: (`2,25`, `mn ₺`), (`9.876`, `₺`).
  static (String, String) moneyReadout(num value) {
    final (n, s) = _parts(value, _moneyDivs, _moneySuffix);
    return (n, s.isEmpty ? '₺' : '$s ₺');
  }

  /// Birimsiz kısa sayı (grafik etiketi): `8,43 mn`, `820 bin`, `40`.
  static String compactNumber(num? value) {
    if (value == null) return dash;
    final (n, s) = _parts(value, _moneyDivs, _moneySuffix);
    return _join(n, s);
  }

  /// [value], [target]'ın biriminde ve birimsiz (aynı serinin etiketleri: `13,1`).
  static String compactNumberAt(num value, num target) {
    final (n, _) = _parts(value, _moneyDivs, _moneySuffix, unitOf: target);
    return n;
  }

  /// Kısa litre: `512.000 L`, `1,2 mn L`.
  static String litersCompact(num? value) {
    if (value == null) return dash;
    final (n, s) = _parts(value, _literDivs, _literSuffix);
    return _join(n, s, 'L');
  }

  static String litersCompactAt(num value, num target) {
    final (n, s) = _parts(value, _literDivs, _literSuffix, unitOf: target);
    return _join(n, s, 'L');
  }

  /// Ekran okuyucu: "21,5 milyon lira", "820 bin lira".
  static String moneySpoken(num value) {
    final (n, s) = _parts(value, _moneyDivs, _moneySpoken);
    return _join(n, s, 'lira');
  }

  /// Ekran okuyucu, tam tutar: "8.426.350 lira".
  static String moneyWholeSpoken(num value) => '${count(value)} lira';

  /// Ekran okuyucu: "512.000 litre", "1,2 milyon litre".
  static String litersSpoken(num value) {
    final (n, s) = _parts(value, _literDivs, _literSpoken);
    return _join(n, s, 'litre');
  }

  // ------------------------------------------------------------------ Tam değerler (sayfa)

  /// `21.500.000 ₺` (kuruşsuz).
  static String money(num? value) => Fmt.moneyWhole(value);

  /// `512.000 L`.
  static String liters(num? value) =>
      value == null ? dash : '${Fmt.number(value.round())} L';

  /// `42`, `8.426.350` (plaka rakamı: kuruşsuz, birimsiz).
  static String count(num? value) =>
      value == null ? dash : Fmt.number(value.round());

  /// Ortalama birim fiyat, iki hane: `42,50 ₺/L`.
  static String unitPrice(num? value) => value == null
      ? dash
      : '${Fmt.number(value, minFraction: 2, maxFraction: 2)} ₺/L';

  /// Birim fiyat rakamı (birimsiz): `42,34`.
  static String price(num? value) =>
      value == null ? dash : Fmt.number(value, minFraction: 2, maxFraction: 2);

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

  /// Yönsüz yüzde (çipte okun yanında): `%8,6`, `%0`.
  static String deltaPercent(double percent) => percent.abs() < flatThreshold
      ? '%0'
      : '%${Fmt.number(percent.abs(), maxFraction: 1)}';

  /// Metin olarak fark (paylaşılan belge): `▲ %8,6`, `▼ %3,2`, `= %0`. Ekranda ok çizilir
  /// (`TriangleGlyph`); bu metin yalnızca belgede kullanılır.
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

  /// Birim fiyat farkı (yönsüz): `0,44 ₺`.
  static String priceDelta(double diff) =>
      '${Fmt.number(diff.abs(), minFraction: 2, maxFraction: 2)} ₺';

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

  /// Plakadaki ve başlıktaki kısa dönem: bu yılın aralığı yılsız (`1–21 Ekim`, `24 Tem – 21 Eki`),
  /// başka yıl [range] gibi.
  static String rangeShort(DateTime? from, DateTime? to, {DateTime? now}) {
    if (from == null || to == null) return dash;
    final a = TrTime.wall(from);
    final b = TrTime.wall(to);
    final year = TrTime.wall(now ?? TrTime.now()).year;
    if (a.year != year || b.year != year) return range(from, to);
    if (a.month == b.month) {
      if (a.day == b.day) return '${a.day} ${Fmt.monthNames[a.month - 1]}';
      return '${a.day}–${b.day} ${Fmt.monthNames[a.month - 1]}';
    }
    return '${a.day} ${Fmt.monthShort[a.month - 1]} – '
        '${b.day} ${Fmt.monthShort[b.month - 1]}';
  }
}

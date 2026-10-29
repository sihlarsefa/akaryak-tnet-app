import 'tr_time.dart';
import 'turkish_text.dart';

/// Türkçe biçimlendiriciler (spec C.7): `1.234,56 ₺`, `12.500 L`, `dd.MM.yyyy`, Europe/Istanbul.
///
/// Tutarlar her zaman sunucu değerinden gösterilir; uygulama yalnızca "tahmini" hesaplar.
/// Tarih girdileri an (UTC `DateTime`) olarak beklenir ve Türkiye saatine çevrilir ([TrTime]).
/// Biçimlendirme yerel ayar verisi gerektirmez (initializeDateFormatting çağrılmadan da çalışır).
abstract final class Fmt {
  static const dash = '—';

  static const monthNames = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', //
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
  ];
  static const monthShort = [
    'Oca',
    'Şub',
    'Mar',
    'Nis',
    'May',
    'Haz',
    'Tem',
    'Ağu',
    'Eyl',
    'Eki',
    'Kas',
    'Ara',
  ];
  static const weekdayNames = [
    'Pazartesi',
    'Salı',
    'Çarşamba',
    'Perşembe',
    'Cuma',
    'Cumartesi',
    'Pazar',
  ];
  static const weekdayShort = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

  // ------------------------------------------------------------------ Sayılar

  /// Türkçe sayı: binlik ayırıcı nokta, ondalık virgül. [minFraction]..[maxFraction] hane.
  static String number(num? value, {int minFraction = 0, int maxFraction = 0}) {
    if (value == null) return dash;
    if (value is double && (value.isNaN || value.isInfinite)) return dash;
    final max = maxFraction < minFraction ? minFraction : maxFraction;
    var fixed = value.toDouble().abs().toStringAsFixed(max);
    var intPart = fixed;
    var frac = '';
    final dot = fixed.indexOf('.');
    if (dot >= 0) {
      intPart = fixed.substring(0, dot);
      frac = fixed.substring(dot + 1);
      while (frac.length > minFraction && frac.endsWith('0')) {
        frac = frac.substring(0, frac.length - 1);
      }
    }
    fixed = _group(intPart) + (frac.isEmpty ? '' : ',$frac');
    final negative = value < 0 && RegExp(r'[1-9]').hasMatch(fixed);
    return negative ? '-$fixed' : fixed;
  }

  static String _group(String digits) {
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) b.write('.');
      b.write(digits[i]);
    }
    return b.toString();
  }

  /// Tamsayı: `12.500`.
  static String integer(num? value) => number(value);

  /// Tutar: `1.234,56 ₺`.
  static String money(num? value, {int decimals = 2}) => value == null
      ? dash
      : '${number(value, minFraction: decimals, maxFraction: decimals)} ₺';

  /// Kuruşsuz tutar (KPI): `1.235 ₺`.
  static String moneyWhole(num? value) =>
      value == null ? dash : '${number(value.round())} ₺';

  /// Kısa tutar (grafik ekseni, KPI): `850 bin ₺`, `1,2 mn ₺`, `3,4 mr ₺`.
  static String moneyCompact(num? value) {
    if (value == null) return dash;
    final v = value.abs();
    final sign = value < 0 ? '-' : '';
    if (v >= 1e9) return '$sign${number(v / 1e9, maxFraction: 1)} mr ₺';
    if (v >= 1e6) return '$sign${number(v / 1e6, maxFraction: 1)} mn ₺';
    if (v >= 1e4) return '$sign${number(v / 1e3, maxFraction: 0)} bin ₺';
    return '$sign${number(v, maxFraction: 0)} ₺';
  }

  /// Birim fiyat ₺/L (sunucu 4 hane saklar): `42,13 ₺/L`, `42,1255 ₺/L`.
  static String unitPrice(num? value) => value == null
      ? dash
      : '${number(value, minFraction: 2, maxFraction: 4)} ₺/L';

  /// ₺/m³ fiyatı (Tüpraş): `42.125,00 ₺/m³`.
  static String pricePerM3(num? value) => value == null
      ? dash
      : '${number(value, minFraction: 2, maxFraction: 2)} ₺/m³';

  /// Litre: `12.500 L`, kesirli ise `12.500,5 L` (en fazla 3 hane).
  static String liters(num? value) =>
      value == null ? dash : '${number(value, maxFraction: 3)} L';

  /// Metreküp: `12,5 m³`.
  static String cubicMeters(num? value) =>
      value == null ? dash : '${number(value, maxFraction: 3)} m³';

  /// Yüzde (Türkçe yazım, işaret önde): `%45`, `%45,5`.
  static String percent(num? value, {int maxFraction = 1}) =>
      value == null ? dash : '%${number(value, maxFraction: maxFraction)}';

  /// Dosya boyutu: `820 KB`, `1,4 MB`.
  static String fileSize(num? bytes) {
    if (bytes == null) return dash;
    if (bytes < 1024) return '${bytes.round()} B';
    if (bytes < 1024 * 1024) {
      return '${number(bytes / 1024, maxFraction: 0)} KB';
    }
    return '${number(bytes / (1024 * 1024), maxFraction: 1)} MB';
  }

  // ------------------------------------------------------------------ Tarihler (an → Türkiye saati)

  static String _pad2(int v) => v.toString().padLeft(2, '0');

  /// `21.10.2026`.
  static String date(DateTime? instant) {
    if (instant == null) return dash;
    final w = TrTime.wall(instant);
    return '${_pad2(w.day)}.${_pad2(w.month)}.${w.year}';
  }

  /// `21.10.2026 14:20`.
  static String dateTime(DateTime? instant) =>
      instant == null ? dash : '${date(instant)} ${time(instant)}';

  /// `14:20`.
  static String time(DateTime? instant) {
    if (instant == null) return dash;
    final w = TrTime.wall(instant);
    return '${_pad2(w.hour)}:${_pad2(w.minute)}';
  }

  /// `21 Ekim 2026`.
  static String longDate(DateTime? instant) {
    if (instant == null) return dash;
    final w = TrTime.wall(instant);
    return '${w.day} ${monthNames[w.month - 1]} ${w.year}';
  }

  /// `21 Eki`.
  static String dayMonth(DateTime? instant) {
    if (instant == null) return dash;
    final w = TrTime.wall(instant);
    return '${w.day} ${monthShort[w.month - 1]}';
  }

  /// `Ekim 2026`.
  static String monthYear(DateTime? instant) {
    if (instant == null) return dash;
    final w = TrTime.wall(instant);
    return '${monthNames[w.month - 1]} ${w.year}';
  }

  /// `Salı`.
  static String weekday(DateTime? instant) =>
      instant == null ? dash : weekdayNames[TrTime.wall(instant).weekday - 1];

  /// Gün adı: `Bugün`, `Yarın`, `Dün`, bu hafta içinde gün adı, değilse `21 Eki`.
  static String dayLabel(DateTime? instant, {DateTime? now}) {
    if (instant == null) return dash;
    final diff = TrTime.dayDiff(now ?? TrTime.now(), instant);
    if (diff == 0) return 'Bugün';
    if (diff == 1) return 'Yarın';
    if (diff == -1) return 'Dün';
    if (diff > 1 && diff < 7) return weekday(instant);
    return dayMonth(instant);
  }

  /// Geçmiş için göreli zaman: `Az önce`, `5 dk önce`, `3 sa önce`, `Dün 14:20`, `Salı 09:10`, `18.10.2026`.
  static String relative(DateTime? instant, {DateTime? now}) {
    if (instant == null) return dash;
    final n = now ?? TrTime.now();
    final d = n.difference(instant);
    if (d.isNegative) return dateTime(instant);
    if (d.inSeconds < 60) return 'Az önce';
    if (d.inMinutes < 60) return '${d.inMinutes} dk önce';
    final days = TrTime.dayDiff(instant, n);
    if (days == 0) {
      return d.inHours < 6 ? '${d.inHours} sa önce' : 'Bugün ${time(instant)}';
    }
    if (days == 1) return 'Dün ${time(instant)}';
    if (days < 7) return '${weekday(instant)} ${time(instant)}';
    return date(instant);
  }

  /// Geri sayım: `2 g 3 sa`, `2 sa 15 dk`, `45 dk`, `30 sn`; süre geçtiyse `Süresi doldu`.
  static String countdown(Duration remaining) {
    if (remaining.inSeconds <= 0) return 'Süresi doldu';
    final days = remaining.inDays;
    final hours = remaining.inHours % 24;
    final minutes = remaining.inMinutes % 60;
    if (days > 0) return hours > 0 ? '$days g $hours sa' : '$days g';
    if (remaining.inHours > 0) {
      return minutes > 0
          ? '${remaining.inHours} sa $minutes dk'
          : '${remaining.inHours} sa';
    }
    if (remaining.inMinutes > 0) return '${remaining.inMinutes} dk';
    return '${remaining.inSeconds} sn';
  }

  // ------------------------------------------------------------------ Metin

  /// Telefon: `0532 123 45 67` (10 haneli Türkiye numarası); bilinmeyen biçim olduğu gibi döner.
  static String phone(String? raw) {
    if (raw == null || raw.trim().isEmpty) return dash;
    final d = raw.replaceAll(RegExp(r'\D'), '');
    String? ten;
    if (d.length == 10) ten = d;
    if (d.length == 11 && d.startsWith('0')) ten = d.substring(1);
    if (d.length == 12 && d.startsWith('90')) ten = d.substring(2);
    if (ten == null) return raw.trim();
    return '0${ten.substring(0, 3)} ${ten.substring(3, 6)} ${ten.substring(6, 8)} ${ten.substring(8)}';
  }

  /// Plaka: `34 ABC 123`. Harf ve rakam grupları ayrılır, büyük harfe çevrilir.
  static String plate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return dash;
    final s = raw.asciiUpper.replaceAll(RegExp(r'[^0-9A-Z]'), '');
    final m = RegExp(r'^(\d{2})([A-Z]{1,3})(\d{2,5})$').firstMatch(s);
    return m == null ? raw.trim().asciiUpper : '${m[1]} ${m[2]} ${m[3]}';
  }

  /// Boş/null için tire.
  static String orDash(String? value) =>
      value == null || value.trim().isEmpty ? dash : value.trim();

  /// Bölünmez boşluk (U+00A0).
  static const nbsp = '\u00A0';

  /// Kısa bir olgunun sözcüklerini bölünmez boşlukla bağlar ("Tuzla Şantiye", "Motorin 8.000 L"):
  /// satır yalnızca olgular arasındaki " · " ayırıcısında kırılır, bir olgunun ortasında değil
  /// (v4 A17). [max] karakterden uzun olgular olağan biçimde sarılır (satırı taşırmasın).
  static String whole(String fact, {int max = 24}) {
    final t = fact.trim();
    return t.length <= max ? t.replaceAll(' ', nbsp) : t;
  }
}

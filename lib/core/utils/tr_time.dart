/// Türkiye saati yardımcıları (F2GO `utils/tr_saat.dart` uyarlaması).
///
/// Türkiye 2016'dan beri sabit UTC+3'tür (yaz saati yok). Uygulama içinde her zaman **an** (UTC
/// `DateTime`, `isUtc == true`) taşınır; ekranda gösterirken Türkiye duvar saatine çevrilir. Böylece
/// telefonun saat dilimi farklı olsa da tarih ve geri sayımlar doğru kalır.
///
/// Sunucu kuralları (spec B.2):
/// - Yeni DTO'lar `DateTimeOffset` gönderir (`Z` ya da `+03:00`): her zaman kesin bir an.
/// - Eski DTO'lar ofsetsiz gönderir. Bunların çoğu Türkiye yerel saatidir ([parseLocal]); ek, onay
///   tarihleri, `*Utc` alanları ve belirteç süreleri ise UTC'dir ([parseUtc]).
/// - Saf tarihler `yyyy-MM-dd` biçimindedir ([parseDate], [isoDate]).
library;

abstract final class TrTime {
  /// Türkiye'nin UTC farkı.
  static const offset = Duration(hours: 3);

  /// Test ve önizleme için saat kaynağı. Testler sabit bir an döndürebilir.
  static DateTime Function() clock = _systemNow;

  static DateTime _systemNow() => DateTime.now().toUtc();

  /// Şu an (UTC an).
  static DateTime now() => clock().toUtc();

  /// Anı Türkiye duvar saatine çevirir. Dönen değer `isUtc == false` olan, alanları Türkiye saatini
  /// gösteren bir `DateTime`'dır; yalnızca biçimlendirme ve takvim hesapları içindir.
  static DateTime wall(DateTime instant) {
    final t = instant.toUtc().add(offset);
    return DateTime(
      t.year,
      t.month,
      t.day,
      t.hour,
      t.minute,
      t.second,
      t.millisecond,
      t.microsecond,
    );
  }

  /// Türkiye duvar saati alanlarından an üretir.
  static DateTime fromWall(
    int year, [
    int month = 1,
    int day = 1,
    int hour = 0,
    int minute = 0,
    int second = 0,
  ]) => DateTime.utc(year, month, day, hour, minute, second).subtract(offset);

  /// Ofsetsiz değer Türkiye yerel saatidir; `Z`/ofsetli değer olduğu gibi an olarak okunur.
  static DateTime? parseLocal(String? value) => _parse(value, assumeUtc: false);

  /// Ofsetsiz değer UTC'dir; `Z`/ofsetli değer olduğu gibi an olarak okunur.
  static DateTime? parseUtc(String? value) => _parse(value, assumeUtc: true);

  /// `yyyy-MM-dd` (ya da tam tarih-saat) → o günün Türkiye gece yarısı (an).
  static DateTime? parseDate(String? value) {
    final s = value?.trim();
    if (s == null || s.isEmpty) return null;
    final m = _dateOnly.firstMatch(s);
    if (m != null) {
      return fromWall(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    }
    final t = parseLocal(s);
    return t == null ? null : startOfDay(t);
  }

  static final _dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  static DateTime? _parse(String? value, {required bool assumeUtc}) {
    var s = value?.trim();
    if (s == null || s.isEmpty) return null;
    // .NET 7 haneli kesirli saniye gönderebilir; Dart en fazla 6 haneyi okur.
    s = s.replaceFirstMapped(RegExp(r'(\.\d{6})\d+'), (m) => m[1]!);
    final parsed = DateTime.tryParse(s);
    if (parsed == null) return null;
    if (parsed.isUtc) return parsed;
    // Ofsetsiz: alanlar ya Türkiye ya UTC duvar saatidir.
    final utc = DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    );
    return assumeUtc ? utc : utc.subtract(offset);
  }

  /// Türkiye takvimine göre günün başlangıcı (an).
  static DateTime startOfDay(DateTime instant) {
    final w = wall(instant);
    return fromWall(w.year, w.month, w.day);
  }

  /// Bugünün Türkiye gece yarısı (an).
  static DateTime todayStart() => startOfDay(now());

  /// İki an Türkiye takviminde aynı gün mü.
  static bool isSameDay(DateTime a, DateTime b) {
    final x = wall(a);
    final y = wall(b);
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  /// Türkiye takviminde gün farkı (b − a); aynı gün 0, ertesi gün 1.
  static int dayDiff(DateTime a, DateTime b) =>
      startOfDay(b).difference(startOfDay(a)).inHours ~/ 24;

  /// Gün ekleme (Türkiye takvimi; saat değişmez).
  static DateTime addDays(DateTime instant, int days) =>
      instant.add(Duration(days: days));

  static String _pad2(int v) => v.toString().padLeft(2, '0');
  static String _pad4(int v) => v.toString().padLeft(4, '0');

  /// `yyyy-MM-dd` (Türkiye takvimi).
  static String isoDate(DateTime instant) {
    final w = wall(instant);
    return '${_pad4(w.year)}-${_pad2(w.month)}-${_pad2(w.day)}';
  }

  /// `yyyy-MM-ddTHH:mm:ss` Türkiye duvar saati, ofsetsiz (yerel saat bekleyen eski uç noktalar).
  static String isoLocal(DateTime instant) {
    final w = wall(instant);
    return '${isoDate(instant)}T${_pad2(w.hour)}:${_pad2(w.minute)}:${_pad2(w.second)}';
  }

  /// `yyyy-MM-ddTHH:mm:ss+03:00` (DateTimeOffset bekleyen yeni uç noktalar).
  static String isoOffset(DateTime instant) => '${isoLocal(instant)}+03:00';

  /// UTC ISO 8601 (`...Z`).
  static String isoUtc(DateTime instant) => instant.toUtc().toIso8601String();
}

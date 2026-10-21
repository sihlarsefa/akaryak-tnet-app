import '../../../core/models/json.dart';
import '../../../core/utils/tr_time.dart';

/// Bayi sözleşmesine özgü küçük JSON yardımcıları (spec B.2 tarih kuralları).
///
/// - Yeni DTO'lar ofsetli gelir (`+03:00` Türkiye yerel, `+00:00` UTC): her iki okuyucu da kesin an döner.
/// - Eski DTO'lar ofsetsizdir: Türkiye yerel ([JsonReader.dateTr]); not, ek, limit talebi ve son giriş
///   tarihleri UTC'dir ([JsonReader.dateUtc]).
/// - Teslim pencereleri `HH:mm` (yeni) ya da .NET TimeSpan `HH:mm:ss` / `1.00:00:00` (eski pano) gelir.
abstract final class BayiJson {
  static final _window = RegExp(
    r'^(?:(\d+)\.)?(\d{1,2}):(\d{2})(?::\d{2}(?:\.\d+)?)?$',
  );

  /// Teslim penceresi saatini `HH:mm` biçimine çevirir (`1.00:00:00` → `24:00`). Tanınmayan değer
  /// olduğu gibi döner; boşsa null.
  static String? windowTime(String? raw) {
    final s = raw?.trim();
    if (s == null || s.isEmpty) return null;
    final m = _window.firstMatch(s);
    if (m == null) return s;
    final days = int.tryParse(m[1] ?? '0') ?? 0;
    final hours = int.parse(m[2]!) + days * 24;
    return '${hours.toString().padLeft(2, '0')}:${m[3]}';
  }

  /// `08:00–18:00`; yalnızca biri varsa `08:00'den sonra` / `18:00'e kadar`; ikisi de yoksa null.
  static String? windowLabel(String? start, String? end) {
    final a = windowTime(start);
    final b = windowTime(end);
    if (a == null && b == null) return null;
    if (a != null && b != null) return '$a–$b';
    if (a != null) return '$a sonrası';
    return '$b öncesi';
  }

  /// Saf tarih `yyyy-MM-dd` (ya da tarih-saat) → o günün Türkiye gece yarısı.
  static DateTime? date(JsonReader r, String key) => r.date(key);

  /// Sunucuya gönderilen saf tarih (`yyyy-MM-dd`, Türkiye takvimi).
  static String isoDate(DateTime instant) => TrTime.isoDate(instant);

  /// Eski uçların beklediği ofsetsiz Türkiye yerel saat (`yyyy-MM-ddTHH:mm:ss`).
  static String isoLocal(DateTime instant) => TrTime.isoLocal(instant);
}

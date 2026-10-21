import 'package:flutter/foundation.dart';

/// Teslim saat aralığının bir ucu (sunucuda .NET `TimeSpan`).
///
/// JSON biçimi .NET "c" biçimidir: `08:00:00`, gün sonu (24:00) `1.00:00:00`.
/// Okurken `08:00`, `24:00` ve kesirli saniye de kabul edilir. Sunucu SQL `time`
/// sütununa 24:00 yazamadığı için gün sonunu `23:59:59` saklar; bu değer
/// yeniden 24:00 olarak okunur (gidiş-dönüş kararlıdır).
@immutable
class WindowTime implements Comparable<WindowTime> {
  const WindowTime(this.minutes) : assert(minutes >= 0 && minutes <= 1440);

  /// Gece yarısından dakika (0–1440).
  final int minutes;

  /// Gün başı (00:00).
  static const startOfDay = WindowTime(0);

  /// Gün sonu (24:00).
  static const endOfDay = WindowTime(minutesPerDay);

  static const minutesPerDay = 1440;

  factory WindowTime.hm(int hour, int minute) =>
      WindowTime((hour * 60 + minute).clamp(0, minutesPerDay));

  static final _pattern = RegExp(
    r'^(?:(\d+)\.)?(\d{1,2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?$',
  );

  /// Sunucu değerini okur; boş ya da geçersizse null.
  static WindowTime? tryParse(Object? value) {
    if (value == null) return null;
    final s = '$value'.trim();
    if (s.isEmpty) return null;
    final m = _pattern.firstMatch(s);
    if (m == null) return null;
    final days = int.tryParse(m[1] ?? '0') ?? 0;
    final h = int.parse(m[2]!);
    final min = int.parse(m[3]!);
    final sec = int.tryParse(m[4] ?? '0') ?? 0;
    if (min > 59 || sec > 59) return null;
    final total = days * minutesPerDay + h * 60 + min;
    if (total > minutesPerDay) return null;
    // Sunucunun "gün sonu" karşılığı.
    if (total == minutesPerDay - 1 && sec == 59) return endOfDay;
    return WindowTime(total);
  }

  bool get isEndOfDay => minutes >= minutesPerDay;
  int get hour => minutes ~/ 60;
  int get minute => minutes % 60;

  static String _p2(int v) => v.toString().padLeft(2, '0');

  /// Ekran: `08:30`, gün sonu `24:00`.
  String get label => isEndOfDay ? '24:00' : '${_p2(hour)}:${_p2(minute)}';

  /// İstek gövdesi (.NET TimeSpan "c"): `08:30:00`, gün sonu `1.00:00:00`.
  String toJson() =>
      isEndOfDay ? '1.00:00:00' : '${_p2(hour)}:${_p2(minute)}:00';

  @override
  int compareTo(WindowTime other) => minutes.compareTo(other.minutes);

  bool operator <(WindowTime other) => minutes < other.minutes;
  bool operator >=(WindowTime other) => minutes >= other.minutes;

  @override
  bool operator ==(Object other) =>
      other is WindowTime && other.minutes == minutes;

  @override
  int get hashCode => minutes.hashCode;

  @override
  String toString() => 'WindowTime($label)';
}

/// "08:00–18:00" (uçlardan biri yoksa null).
String? windowLabel(WindowTime? start, WindowTime? end) {
  if (start == null || end == null) return null;
  if (start.minutes == 0 && end.isEndOfDay) return 'Gün boyu (00:00–24:00)';
  return '${start.label}–${end.label}';
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Geri sayımların saati (kilitlenme, kod yeniden gönderimi, kod geçerliliği). Testler sahte saatle ezer;
/// `DateTime.now()` test zamanlayıcısıyla ilerlemediği için doğrudan kullanılmaz.
final authClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Bekleme süresinin kısa yazımı (spec C.7): `45 sn`, `14:59`, `1:05:00`.
String formatWait(Duration remaining) {
  final total = waitSeconds(remaining);
  if (total < 60) return '$total sn';
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// Ekran okuyucu için: `14 dakika 59 saniye`, `45 saniye`.
String spokenWait(Duration remaining) {
  final total = waitSeconds(remaining);
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  return [
    if (h > 0) '$h saat',
    if (m > 0) '$m dakika',
    if (s > 0 || total == 0) '$s saniye',
  ].join(' ');
}

/// Kalan saniye (yukarı yuvarlanır; negatif olmaz).
int waitSeconds(Duration remaining) {
  final ms = remaining.inMilliseconds;
  if (ms <= 0) return 0;
  return (ms / 1000).ceil();
}

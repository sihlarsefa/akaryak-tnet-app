import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ne zaman "eskidiyse tazele" sorulur.
enum RevalidateReason {
  /// Uygulama öne geldi.
  resume,

  /// Bir alt menü sekmesi yeniden gösterildi.
  tab,
}

/// Tazeleme işareti: [seq] her olayda artar (aynı sekmeye ikinci dokunuş da yeni olaydır).
@immutable
class RevalidateEvent {
  const RevalidateEvent(this.reason, this.seq, {this.path});

  final RevalidateReason reason;
  final int seq;

  /// Sekme olayında sekmenin kök yolu (`/bayi/orders`).
  final String? path;

  @override
  bool operator ==(Object other) =>
      other is RevalidateEvent && other.seq == seq;

  @override
  int get hashCode => seq.hashCode;
}

/// Sekme kökleri ve ana sayfalar açık kalır (kabuk dalları); bu işaretle **eskidiyse** sessizce
/// tazelenirler (içerik kalır, üstte ince "güncelleniyor" çubuğu). Taze veri için istek atılmaz.
///
/// ```dart
/// ref.listen(revalidateProvider, (_, e) {
///   if (e != null && Freshness.isStale(state.updatedAt, Freshness.list)) refresh(silent: true);
/// });
/// ```
final revalidateProvider = NotifierProvider<RevalidateBus, RevalidateEvent?>(
  RevalidateBus.new,
);

class RevalidateBus extends Notifier<RevalidateEvent?> {
  int _seq = 0;

  @override
  RevalidateEvent? build() => null;

  void resumed() => state = RevalidateEvent(RevalidateReason.resume, ++_seq);

  void tabShown(String path) =>
      state = RevalidateEvent(RevalidateReason.tab, ++_seq, path: path);
}

/// Tazelik süreleri: bundan genç veri yeniden istenmez (sekme dönüşü, öne gelme).
abstract final class Freshness {
  /// Listeler (Siparişler, Tahsilat, Finans, Sevkiyat, Cariler …).
  static const list = Duration(minutes: 2);

  /// Ana sayfalar ve istatistik destesi.
  static const home = Duration(minutes: 5);

  /// Ayrıntılar (açık sipariş, kart).
  static const detail = Duration(minutes: 1);

  /// Fiyat ve limit kararı (sipariş gönderme, teklif onayı): bundan eski veriyle işlem yapılmaz.
  static const decision = Duration(seconds: 45);

  /// [at] (UTC) yoksa ya da [ttl]'den eskiyse true.
  static bool isStale(DateTime? at, Duration ttl, {DateTime? now}) {
    if (at == null) return true;
    return (now ?? DateTime.now().toUtc()).difference(at.toUtc()) > ttl;
  }
}

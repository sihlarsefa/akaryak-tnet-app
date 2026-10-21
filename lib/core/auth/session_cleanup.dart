import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../push/app_badge.dart';
import '../push/local_notifications.dart';
import '../utils/log.dart';

/// Oturum kapanınca ya da kullanıcı değişince yapılan temizlik (spec D.7). Önbellek ve tercihler
/// `SessionController` içinde silinir; bu adım cihazda kalan diğer izleri kaldırır:
///
/// - bellekteki çözülmüş görseller (`PaintingBinding.imageCache`),
/// - bildirim merkezinde duran yerel / push bildirimleri,
/// - uygulama simgesi rozeti,
/// - özelliklerin kayıtlı temizlikleri ([sessionCleanupHooksProvider]).
///
/// Hata fırlatmaz. Testler geçersiz kılabilir.
typedef SessionCleanup = Future<void> Function(String? userId);

/// Özelliklerin ek temizlikleri (ör. kullanıcının saklı PDF belgeleri). Uygulama katmanı
/// (`app/wiring.dart`) doldurur; çekirdek özellikleri tanımaz. Beklenmez, hata yutulur.
final sessionCleanupHooksProvider = Provider<List<SessionCleanup>>(
  (ref) => const [],
);

final sessionCleanupProvider = Provider<SessionCleanup>(
  (ref) => (userId) async {
    for (final hook in ref.read(sessionCleanupHooksProvider)) {
      unawaited(
        Future.sync(() => hook(userId)).catchError((Object e) {
          AppLog.debug('Özellik temizliği tamamlanamadı: ${e.runtimeType}');
        }),
      );
    }
    try {
      PaintingBinding.instance.imageCache
        ..clear()
        ..clearLiveImages();
    } catch (e) {
      AppLog.debug('Görsel önbelleği temizlenemedi: ${e.runtimeType}');
    }
    // Platform çağrıları beklenmez: çıkış eklentiye takılmasın (test ortamında eklenti yoktur).
    unawaited(LocalNotifications.cancelAll());
    unawaited(ref.read(appBadgeProvider).clear());
  },
);

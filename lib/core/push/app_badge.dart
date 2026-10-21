import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/log.dart';

/// Uygulama simgesi rozeti (spec D.7): okunmamış bildirim sayısı; çıkışta sıfırlanır. iOS'ta APNs
/// yükü de rozeti günceller (sunucu `badge` = okunmamış sayı). Desteklemeyen başlatıcılarda sessizce
/// hiçbir şey yapmaz.
abstract interface class AppBadge {
  Future<void> set(int count);

  Future<void> clear();
}

class PluginAppBadge implements AppBadge {
  const PluginAppBadge();

  @override
  Future<void> set(int count) async {
    if (kIsWeb) return;
    try {
      await AppBadgePlus.updateBadge(count < 0 ? 0 : count);
    } catch (e) {
      AppLog.debug('Uygulama rozeti güncellenemedi: ${e.runtimeType}');
    }
  }

  @override
  Future<void> clear() => set(0);
}

/// Bellek içi rozet (testler).
class MemoryAppBadge implements AppBadge {
  int count = 0;

  @override
  Future<void> set(int value) async => count = value;

  @override
  Future<void> clear() async => count = 0;
}

final appBadgeProvider = Provider<AppBadge>((ref) => const PluginAppBadge());

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/log.dart';

/// Ağ bağlantısı var mı (Wi-Fi / hücresel / ethernet). Eklenti yoksa (test) çevrimiçi sayılır.
/// Not: bağlantı olması sunucuya ulaşıldığı anlamına gelmez; istek hataları ayrıca ele alınır.
final connectivityProvider = StreamProvider<bool>((ref) {
  final controller = StreamController<bool>();
  StreamSubscription<List<ConnectivityResult>>? sub;
  bool online(List<ConnectivityResult> r) =>
      r.any((c) => c != ConnectivityResult.none);

  Future<void> start() async {
    try {
      final c = Connectivity();
      controller.add(online(await c.checkConnectivity()));
      sub = c.onConnectivityChanged.listen(
        (r) => controller.add(online(r)),
        onError: (Object _) => controller.add(true),
      );
    } catch (e) {
      AppLog.debug('Bağlantı izlenemiyor; çevrimiçi varsayılıyor ($e)');
      controller.add(true);
    }
  }

  unawaited(start());
  ref.onDispose(() async {
    await sub?.cancel();
    await controller.close();
  });
  return controller.stream.distinct();
});

/// Anlık bağlantı durumu (bilinmiyorsa çevrimiçi).
final isOnlineProvider = Provider<bool>(
  (ref) => ref.watch(connectivityProvider).valueOrNull ?? true,
);

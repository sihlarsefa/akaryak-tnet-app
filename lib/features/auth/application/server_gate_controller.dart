import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/env/app_config_controller.dart';
import '../../../core/env/app_env.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/utils/log.dart';
import '../data/auth_api.dart';
import '../data/server_gate.dart';

/// Giriş ekranı açılınca `app/config` yoklanır (spec A.4 A1): bakım ya da uyumsuz sunucu varsa giriş
/// formu yerine "Bakımdayız" / "Sunucu güncel değil" gösterilir. Çekirdek yapılandırma modeli bakım ve
/// sözleşme alanlarını taşımadığından ham yanıt burada okunur. Ekrandan çıkınca bırakılır; sonraki
/// açılışta yeniden yoklanır. Hep formun konuştuğu sunucuyu anlatır: test derlemesinde demo oturumu
/// açılıp kapanınca o dünyanın sunucusu yeniden yoklanır.
final serverGateProvider =
    AsyncNotifierProvider.autoDispose<ServerGateController, ServerGate>(
      ServerGateController.new,
    );

class ServerGateController extends AutoDisposeAsyncNotifier<ServerGate> {
  bool _alive = true;

  /// Yoklamanın kuşağı: her kurulumda (ortam değişince) artar. Önceki dünyada başlayan "Tekrar dene"
  /// yanıtı yeni dünyanın durumunun üstüne yazılmaz.
  int _generation = 0;

  @override
  Future<ServerGate> build() {
    _alive = true;
    _generation++;
    ref.onDispose(() => _alive = false);
    ref.watch(appEnvProvider);
    return _probe();
  }

  Future<ServerGate> _probe() async {
    try {
      final json = await ref.read(authApiProvider).appConfig();
      return ServerGate.fromConfigJson(json);
    } catch (e) {
      final failure = AppFailure.from(e);
      AppLog.debug('app/config yoklanamadı: ${failure.runtimeType}');
      return ServerGate.fromFailure(failure);
    }
  }

  /// "Tekrar dene": yeniden yoklar, çekirdek yapılandırmayı da tazeler.
  Future<void> recheck() async {
    final generation = _generation;
    state = const AsyncLoading<ServerGate>().copyWithPrevious(state);
    unawaited(ref.read(appConfigProvider.notifier).load());
    final next = await _probe();
    if (_alive && generation == _generation) state = AsyncData(next);
  }
}

/// Giriş ekranının destek ve yasal bağlantıları: yoklama yanıtı, yoksa çekirdek yapılandırma, yasal
/// metinler için son çare API'nin `/legal/*` sayfaları.
final authLinksProvider = Provider.autoDispose<AuthLinks>((ref) {
  final config = AuthLinks.fromConfig(ref.watch(appConfigProvider));
  final gate = ref.watch(serverGateProvider).valueOrNull;
  final links = gate?.links?.orElse(config) ?? config;
  return links.withLegalFallback(ref.watch(appEnvProvider));
});

/// "Telefonla giriş" sekmesi açık mı (`features.otpLogin`).
final otpLoginEnabledProvider = Provider.autoDispose<bool>((ref) {
  final gate = ref.watch(serverGateProvider).valueOrNull;
  return gate?.otpLogin ?? ref.watch(appConfigProvider).features.otpLogin;
});

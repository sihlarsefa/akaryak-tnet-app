import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/env/app_config_controller.dart';
import '../../../core/models/json.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/cache_store.dart';
import '../../../core/storage/prefs_store.dart';
import '../../../core/utils/tr_time.dart';
import '../data/assistant_models.dart';
import '../data/assistant_repository.dart';

/// Asistanın sunucuda kapalı olduğu (503 `assistant_disabled`) öğrenildi. Uygulama ayarları yeniden
/// yüklenince sıfırlanır.
final assistantServerDisabledProvider =
    NotifierProvider<AssistantServerDisabled, bool>(
      AssistantServerDisabled.new,
    );

class AssistantServerDisabled extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(appConfigProvider.select((c) => c.features.assistant));
    ref.watch(currentUserIdProvider);
    return false;
  }

  void markDisabled() => state = true;
}

/// Asistan girişleri gösterilsin mi (spec A.6): `features.assistant` açık ve sunucu 503 demedi.
/// Ana sayfa kartları, uygulama çubuğu ikonu ve "Diğer" sayfası bunu izleyebilir.
final assistantEnabledProvider = Provider<bool>(
  (ref) =>
      ref.watch(appConfigProvider.select((c) => c.features.assistant)) &&
      !ref.watch(assistantServerDisabledProvider),
);

bool isAssistantDisabled(AppFailure f) =>
    f is ServerFailure &&
    f.statusCode == 503 &&
    (f.code == null || f.code == 'assistant_disabled');

/// Onay kapısının durumu.
@immutable
sealed class AssistantGate {
  const AssistantGate();
}

/// Denetleniyor (aydınlatma metni okunuyor).
final class GateChecking extends AssistantGate {
  const GateChecking();
}

/// Kullanıcı bu sürümü onaylamadı: tam ekran aydınlatma metni gösterilir.
final class GateNeedsConsent extends AssistantGate {
  const GateNeedsConsent(this.disclosure, {this.notice});

  final AssistantDisclosure disclosure;

  /// Ör. "Aydınlatma metni güncellendi".
  final String? notice;
}

/// Onay var; sohbet açık. Her sohbet isteği [version] gönderir.
final class GateReady extends AssistantGate {
  const GateReady(this.version, {this.disclosure, this.acceptedAt});

  final String version;
  final AssistantDisclosure? disclosure;
  final DateTime? acceptedAt;
}

/// Asistan sunucuda kapalı (503).
final class GateDisabled extends AssistantGate {
  const GateDisabled(this.message);

  final String message;
}

/// Aydınlatma metni okunamadı (çevrimdışı, sunucu hatası).
final class GateError extends AssistantGate {
  const GateError(this.failure);

  final AppFailure failure;
}

/// Asistan onay kapısı (spec A.6): ilk kullanımda ve `assistantConsentVersion` değişince tam ekran
/// aydınlatma metni; "Kabul ediyorum" → `POST assistant/consent`. Kabul edilen sürüm kullanıcıya özel
/// tercihlerde tutulur; uygulama ayarlarındaki sürümle aynıysa sunucuya sorulmadan sohbet açılır.
/// Sohbet `consent_required` dönerse kapı yeniden kapanır. Profil > Gizlilik onayı geri alır.
final assistantGateProvider =
    NotifierProvider<AssistantGateController, AssistantGate>(
      AssistantGateController.new,
    );

class AssistantGateController extends Notifier<AssistantGate> {
  static const updatedNotice =
      'Aydınlatma metni güncellendi; devam etmek için lütfen yeniden okuyun.';

  int _epoch = 0;

  AssistantRepository get _repo => ref.read(assistantRepositoryProvider);

  String? get _userId => ref.read(currentUserIdProvider);

  String? get _prefKey {
    final uid = _userId;
    return uid == null ? null : PrefKeys.user(uid, 'assistant.consentVersion');
  }

  @override
  AssistantGate build() {
    final uid = ref.watch(currentUserIdProvider);
    final epoch = ++_epoch;
    if (uid != null) Future.microtask(() => _check(epoch));
    return const GateChecking();
  }

  /// Asistan açılırken: uygulama ayarlarındaki sürüm, onaylanan sürümden farklıysa (metin
  /// güncellendi) kapı yeniden denetlenir. Aynıysa ya da sürüm bilinmiyorsa bir şey yapmaz.
  Future<void> revalidate() async {
    final s = state;
    if (s is! GateReady) return;
    final configured = await _configuredVersion();
    if (configured == null || configured == s.version) return;
    if (state is! GateReady) return;
    await recheck(notice: updatedNotice);
  }

  /// Yeniden denetler (hata ekranındaki "Tekrar dene").
  Future<void> recheck({String? notice}) {
    final epoch = ++_epoch;
    state = const GateChecking();
    return _check(epoch, notice: notice);
  }

  Future<void> _check(int epoch, {String? notice}) async {
    if (epoch != _epoch || _userId == null) return;
    final prefs = ref.read(prefsStoreProvider);
    final key = _prefKey;
    final local = key == null ? null : prefs.getString(key);
    final configured = await _configuredVersion();
    if (epoch != _epoch) return;
    if (local != null && configured != null && local == configured) {
      state = GateReady(local);
      return;
    }
    try {
      final d = await _repo.disclosure();
      if (epoch != _epoch) return;
      if (d.accepted) {
        if (key != null) await prefs.setString(key, d.version);
        if (epoch != _epoch) return;
        state = GateReady(d.version, disclosure: d, acceptedAt: d.acceptedAt);
      } else {
        if (key != null) await prefs.remove(key);
        if (epoch != _epoch) return;
        state = GateNeedsConsent(d, notice: notice);
      }
    } on AppFailure catch (f) {
      if (epoch != _epoch) return;
      if (isAssistantDisabled(f)) {
        ref.read(assistantServerDisabledProvider.notifier).markDisabled();
        state = GateDisabled(f.problem?.detail ?? f.message);
      } else if (local != null && (f.isTransient || f is ServerFailure)) {
        // Çevrimdışı: daha önce verilen onayla devam (sohbet zaten bağlantı ister).
        state = GateReady(local);
      } else {
        state = GateError(f);
      }
    }
  }

  /// "Kabul ediyorum". Hata [AppFailure] olarak fırlar (ekran gösterir).
  Future<void> accept() async {
    final s = state;
    if (s is! GateNeedsConsent) return;
    final version = s.disclosure.version;
    try {
      await _repo.consent(version);
    } on ValidationFailure {
      // Metin bu arada değişti: yenisini göster.
      await recheck(notice: updatedNotice);
      return;
    } on AppFailure catch (f) {
      if (isAssistantDisabled(f)) {
        ref.read(assistantServerDisabledProvider.notifier).markDisabled();
        state = GateDisabled(f.problem?.detail ?? f.message);
        return;
      }
      rethrow;
    }
    final key = _prefKey;
    if (key != null) {
      await ref.read(prefsStoreProvider).setString(key, version);
    }
    _epoch++;
    state = GateReady(
      version,
      disclosure: s.disclosure,
      acceptedAt: TrTime.now(),
    );
  }

  /// Profil > Gizlilik: onayı geri al (`DELETE assistant/consent`). Hata [AppFailure] olarak fırlar.
  Future<void> withdraw() async {
    await _repo.withdrawConsent();
    final key = _prefKey;
    if (key != null) await ref.read(prefsStoreProvider).remove(key);
    await recheck();
  }

  /// Sohbet `consent_required` döndü: kapı yeniden kapanır.
  Future<void> consentRequired() async {
    final key = _prefKey;
    if (key != null) await ref.read(prefsStoreProvider).remove(key);
    await recheck(notice: updatedNotice);
  }

  /// 503 `assistant_disabled`.
  void disabled(String message) {
    _epoch++;
    ref.read(assistantServerDisabledProvider.notifier).markDisabled();
    state = GateDisabled(message);
  }

  Future<String?> _configuredVersion() async {
    try {
      final e = await ref.read(cacheStoreProvider).read(CacheKeys.appConfig);
      return JsonReader.of(e?.value).nonEmpty('assistantConsentVersion');
    } catch (_) {
      return null;
    }
  }
}

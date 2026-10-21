import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/lock_settings.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/auth/session_state.dart';
import '../../../core/push/push_providers.dart';
import '../../../core/routing/nav_keys.dart';
import '../../../core/storage/prefs_store.dart';
import '../../../core/ui/ui.dart';
import '../copy.dart';
import 'biometric.dart';

/// Kimlik özelliğinin cihaz tercihleri (kullanıcıya bağlı değil; çıkışta silinmez).
abstract final class AuthPrefKeys {
  /// Bu cihazdaki başarılı etkileşimli giriş sayısı (biyometrik öneri ikinci girişte).
  static const loginCount = 'akn.auth.loginCount';

  /// Biyometrik kilit önerisi gösterildi (bir kez).
  static const biometricOffered = 'akn.auth.biometricOffered';
}

/// Kilit ekranındaki "Şifreyle giriş yap" sonrası giriş formuna yazılacak kullanıcı adı (yalnızca
/// bellekte; cihazda saklanmaz).
final loginPrefillProvider = NotifierProvider<LoginPrefill, String?>(
  LoginPrefill.new,
);

class LoginPrefill extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? userName) => state = userName;

  /// Değeri alır ve temizler.
  String? take() {
    final v = state;
    state = null;
    return v;
  }
}

/// Bildirim ön sayfası bu oturumda gösterilecek mi (spec C.7: biyometrik öneri onunla aynı oturumda
/// gösterilmez). Kabuk ön sayfayı girişten hemen sonra açtığı için giriş isteğinden önce okunur.
bool pushPrimerPending(ProviderContainer container) =>
    container.read(firebaseAvailableProvider) &&
    !container.read(prefsStoreProvider).getBool(PrefKeys.pushPrimerShown);

/// Etkileşimli giriş (şifre, 2FA, telefon kodu) başarıyla bitti.
///
/// - Şifreyle girişte parola yöneticisine "kaydet" denir (`finishAutofillContext`).
/// - Giriş sayısı artar; ikinci girişten itibaren, cihaz uygunsa ve bildirim ön sayfası bu oturumda
///   gösterilmeyecekse, kabuk açıldıktan sonra bir kez biyometrik kilit önerilir.
Future<void> afterInteractiveLogin(
  ProviderContainer container, {
  required bool primerPending,
  bool savePassword = false,
}) async {
  if (savePassword) TextInput.finishAutofillContext();
  final prefs = container.read(prefsStoreProvider);
  final count = (prefs.getInt(AuthPrefKeys.loginCount) ?? 0) + 1;
  await prefs.setInt(AuthPrefKeys.loginCount, count);
  // Müşterilere bildirim ön sayfası girişte değil ilk siparişten sonra gösterilir (kabuk atlar).
  final primerThisSession =
      primerPending && !container.read(accessPolicyProvider).isCustomer;
  if (count < 2 || primerThisSession) return;
  if (prefs.getBool(AuthPrefKeys.biometricOffered)) return;
  if (container.read(biometricLockProvider)) return;
  final support = await container
      .read(biometricAuthenticatorProvider)
      .support();
  if (!support.available) return;
  await prefs.setBool(AuthPrefKeys.biometricOffered, true);
  // Kabuğun açılış geçişi bitsin.
  await Future<void>.delayed(const Duration(milliseconds: 900));
  final context = rootNavigatorKey.currentContext;
  if (context == null || !context.mounted) return;
  if (container.read(sessionControllerProvider) is! SessionAuthenticated) {
    return;
  }
  await showBiometricOffer(context, container, support);
}

/// "Daha hızlı ve güvenli açılış" önerisi. Kabul edilince bir kez doğrulanır, sonra kilit açılır.
Future<void> showBiometricOffer(
  BuildContext context,
  ProviderContainer container,
  BiometricSupport support,
) async {
  final accepted = await showAppSheet<bool>(
    context: context,
    showClose: false,
    builder: (ctx) => _OfferBody(kind: support.kind),
  );
  if (accepted != true) return;
  final outcome = await container
      .read(biometricAuthenticatorProvider)
      .authenticate(AuthCopy.biometricReason);
  if (outcome != BiometricOutcome.success) return;
  await container.read(biometricLockProvider.notifier).set(true);
  AppToast.success(AuthCopy.offerEnabled);
}

class _OfferBody extends StatelessWidget {
  const _OfferBody({required this.kind});

  final BiometricKind? kind;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final named =
        kind == BiometricKind.face ||
        kind == BiometricKind.fingerprint ||
        kind == BiometricKind.iris;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Center(
          child: AknIconBox(
            icon: biometricIcon(kind),
            tone: AknTone.brand,
            size: 56,
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            AuthCopy.offerTitle,
            style: t.title,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AuthCopy.offerBody(biometricPhrase(kind)),
          style: t.body.copyWith(color: c.dim),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        AknButton(
          label: named
              ? AuthCopy.offerAccept(biometricMethodName(kind))
              : AuthCopy.offerAcceptGeneric,
          expand: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: 8),
        AknButton.ghost(
          label: AuthCopy.offerLater,
          expand: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}

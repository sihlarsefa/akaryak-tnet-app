import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/auth/session_state.dart';
import '../../../core/models/auth_models.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../application/login_effects.dart';
import '../copy.dart';
import '../data/auth_api.dart';
import 'widgets/code_entry.dart';

/// Kod ekranının amacı.
enum CodePurpose {
  /// Şifreden sonra SMS kodu (iki adımlı doğrulama); yeniden gönderim `auth/challenge/resend`.
  twoFactor,

  /// Telefonla giriş; yeniden gönderim `auth/otp/send` (yeni sorgu).
  otpLogin,
}

/// `/login/code` rotasının argümanı (`context.push(AppRoutes.loginCode, extra: CodePageArgs(…))`).
@immutable
class CodePageArgs {
  const CodePageArgs({
    required this.challenge,
    required this.purpose,
    this.phone,
    this.primerPending = false,
    this.savePassword = false,
  });

  final OtpChallenge challenge;
  final CodePurpose purpose;

  /// Telefonla girişte numara (`90XXXXXXXXXX`), yeniden gönderim için.
  final String? phone;

  /// Girişten önce okunan bildirim ön sayfası durumu (biyometrik öneri için).
  final bool primerPending;

  /// 2FA: şifre girişin parçasıdır; parola yöneticisine kaydet denir.
  final bool savePassword;
}

/// SMS kodu ekranı (2FA ve telefonla giriş, spec A.4 A1). Doğrulanınca oturum açılır ve yönlendirici
/// kabuğa geçer.
class CodePage extends ConsumerWidget {
  const CodePage({super.key, this.args});

  /// Rota `extra`sı yoksa (uygulama yeniden açıldı, eski bağlantı) girişe dönüş önerilir.
  final CodePageArgs? args;

  /// Rota `extra`sından: [CodePageArgs] ya da (aşama 0 uyumu) yalnızca [OtpChallenge].
  static CodePageArgs? argsFrom(Object? extra) => switch (extra) {
    final CodePageArgs a => a,
    final OtpChallenge c => CodePageArgs(
      challenge: c,
      purpose: CodePurpose.twoFactor,
    ),
    _ => null,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = args;
    if (a == null) {
      return AppScaffold(
        title: AuthCopy.codeTitleTwoFactor,
        showBell: false,
        body: Center(
          child: SingleChildScrollView(
            child: EmptyState(
              title: AuthCopy.missingChallenge,
              message: AuthCopy.missingChallengeBody,
              illustration: AknIllustration.locked,
              actionLabel: AuthCopy.backToLogin,
              onAction: () => context.go(AppRoutes.login),
            ),
          ),
        ),
      );
    }
    final otp = a.purpose == CodePurpose.otpLogin;
    return AppScaffold(
      title: otp ? AuthCopy.codeTitleOtp : AuthCopy.codeTitleTwoFactor,
      showBell: false,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        excludeFromSemantics: true,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            24,
            16,
            24 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: CodeEntry(
                challenge: a.challenge,
                note: otp ? AuthCopy.otpNote : AuthCopy.twoFactorNote,
                onVerify: (id, code) => _verify(context, ref, a, id, code),
                onResend: (current) => _resend(ref, a, current),
                onRestart: () => context.go(AppRoutes.login),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _verify(
    BuildContext context,
    WidgetRef ref,
    CodePageArgs a,
    String challengeId,
    String code,
  ) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final outcome = await ref
        .read(sessionControllerProvider.notifier)
        .verifyCode(challengeId, code);
    if (outcome is LoginSucceeded) {
      unawaited(
        afterInteractiveLogin(
          container,
          primerPending: a.primerPending,
          savePassword: a.savePassword,
        ),
      );
    } else {
      throw const UnknownFailure(
        'Doğrulama tamamlanamadı. Lütfen tekrar deneyin.',
      );
    }
  }

  Future<OtpChallenge> _resend(
    WidgetRef ref,
    CodePageArgs a,
    OtpChallenge current,
  ) {
    final phone = a.phone;
    if (a.purpose == CodePurpose.otpLogin && phone != null) {
      return ref.read(sessionControllerProvider.notifier).sendOtp(phone);
    }
    return ref.read(authApiProvider).resendChallenge(current.challengeId);
  }
}

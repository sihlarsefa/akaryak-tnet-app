import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/env/app_config_controller.dart';
import '../../../core/models/auth_models.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../application/auth_errors.dart';
import '../application/auth_throttle.dart';
import '../copy.dart';
import '../data/auth_api.dart';
import 'widgets/auth_banners.dart';
import 'widgets/auth_header.dart';
import 'widgets/code_entry.dart';
import 'widgets/gate_view.dart';
import 'widgets/hold_button.dart';

/// Profildeki telefonun durumu (Profil > Güvenlik "Telefonla girişi etkinleştir" de kullanır).
final phoneStatusProvider = FutureProvider.autoDispose<PhoneStatus>(
  (ref) => ref.watch(authApiProvider).phoneStatus(),
);

enum _Step { intro, code, done }

/// Telefon doğrulama (`/profile/phone`, spec A.4 A1): `me/phone/verify-start` ile profildeki numaraya
/// kod gider, `me/phone/verify` ile doğrulanır; telefonla giriş bu numara için açılır. Kod yeniden
/// gönderimi `auth/challenge/resend` iledir.
class PhoneVerificationPage extends ConsumerStatefulWidget {
  const PhoneVerificationPage({super.key});

  @override
  ConsumerState<PhoneVerificationPage> createState() =>
      _PhoneVerificationPageState();
}

class _PhoneVerificationPageState extends ConsumerState<PhoneVerificationPage> {
  _Step _step = _Step.intro;
  OtpChallenge? _challenge;
  bool _starting = false;
  AuthErrorInfo? _error;

  void _announce(String message) {
    final view = View.maybeOf(context);
    if (view == null) return;
    unawaited(
      SemanticsService.sendAnnouncement(view, message, TextDirection.ltr),
    );
  }

  Future<void> _start() async {
    if (_starting) return;
    if (ref
            .read(authThrottleProvider.notifier)
            .active(ThrottleScope.phoneVerify) !=
        null) {
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final challenge = await ref
          .read(authApiProvider)
          .startPhoneVerification();
      if (!mounted) return;
      setState(() {
        _starting = false;
        _challenge = challenge;
        _step = _Step.code;
      });
    } on AppFailure catch (f) {
      if (!mounted) return;
      if (f is RateLimitedFailure) {
        ref
            .read(authThrottleProvider.notifier)
            .hold(
              ThrottleScope.phoneVerify,
              f.retryAfter,
              message: f.problem?.detail,
            );
        setState(() => _starting = false);
        _announce(f.message);
        return;
      }
      final info = describeAuthFailure(f, title: AuthCopy.codeErrorTitle);
      setState(() {
        _starting = false;
        _error = info;
      });
      AknHaptics.warning();
      _announce(info.message);
    }
  }

  Future<void> _verify(String challengeId, String code) async {
    await ref.read(authApiProvider).verifyPhone(challengeId, code);
    if (!mounted) return;
    ref.invalidate(phoneStatusProvider);
    unawaited(
      ref.read(sessionControllerProvider.notifier).refreshAccess(force: true),
    );
    setState(() => _step = _Step.done);
    AknHaptics.success();
    _announce(AuthCopy.phoneDoneTitle);
  }

  void _close() {
    if (context.canPop()) {
      context.pop(true);
    } else {
      context.go(AppRoutes.profile);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step != _Step.code,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step == _Step.code) {
          setState(() => _step = _Step.intro);
        }
      },
      child: AppScaffold(
        title: AuthCopy.phoneTitle,
        showBell: false,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          excludeFromSemantics: true,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              AknSpace.page,
              8,
              AknSpace.page,
              24 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: SharedAxisSwitcher(
                  reverse: _step == _Step.intro,
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: switch (_step) {
                      _Step.intro => _intro(context),
                      _Step.code => CodeEntry(
                        challenge: _challenge!,
                        showLogo: false,
                        onVerify: _verify,
                        onResend: (current) => ref
                            .read(authApiProvider)
                            .resendChallenge(current.challengeId),
                        onRestart: () => setState(() => _step = _Step.intro),
                      ),
                      _Step.done => ResultView(
                        title: AuthCopy.phoneDoneTitle,
                        message: AuthCopy.phoneDoneBody,
                        primaryLabel: AuthCopy.done,
                        onPrimary: _close,
                      ),
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _intro(BuildContext context) {
    final status = ref.watch(phoneStatusProvider);
    final isPlatform = ref.watch(accessPolicyProvider).isPlatform;
    final otpEnabled = ref.watch(
      appConfigProvider.select((c) => c.features.otpLogin),
    );
    final t = context.aknText;
    final c = context.akn;
    final hold = ref.watch(authThrottleProvider)[ThrottleScope.phoneVerify];
    final activeHold =
        hold != null &&
            ref
                    .read(authThrottleProvider.notifier)
                    .active(ThrottleScope.phoneVerify) !=
                null
        ? hold
        : null;
    return status.when(
      loading: () => const SkeletonCard(lines: 3, margin: EdgeInsets.zero),
      error: (e, _) => ErrorState(
        title: AuthCopy.statusLoadFailed,
        message: describeAuthFailure(AppFailure.from(e)).message,
        offline: AppFailure.from(e) is OfflineFailure,
        onRetry: () => ref.invalidate(phoneStatusProvider),
      ),
      data: (s) {
        if (!s.hasPhone) {
          return EmptyState(
            title: AuthCopy.noPhoneTitle,
            message: AuthCopy.noPhoneBody,
            illustration: AknIllustration.documents,
            actionLabel: AuthCopy.done,
            onAction: _close,
          );
        }
        // v3: solda telefon çizimi (süzülen turuncu disk), başlık ve cümle; numara ve doğrulama durumu
        // beyaz kartta; eylemler altta. Bölümler sırayla yukarı kayarak belirir.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AuthPop(
                child: GateArt(
                  icon: s.verified
                      ? PhosphorIconsRegular.shieldCheck
                      : PhosphorIconsRegular.deviceMobile,
                  tone: s.verified ? AknTone.ok : AknTone.brand,
                  size: 92,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const AuthPageHeader(
              title: AuthCopy.phoneIntroTitle,
              message: AuthCopy.phoneIntroBody,
              showLogo: false,
            ),
            const SizedBox(height: 20),
            AuthRise(
              delay: const Duration(milliseconds: 120),
              child: AknCard(
                radius: 20,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FactRow(
                      label: AuthCopy.phoneNumberLabel,
                      value: s.phoneMasked!,
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: AknLamp(
                        label: s.verified
                            ? AuthCopy.phoneVerified
                            : AuthCopy.phoneNotVerified,
                        tone: s.verified ? AknTone.ok : AknTone.neutral,
                      ),
                    ),
                    if (s.verified) ...[
                      const SizedBox(height: 8),
                      Text(
                        AuthCopy.phoneVerifiedBody,
                        style: t.bodySmall.copyWith(color: c.dim),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (isPlatform)
              const AknBanner(
                message: AuthCopy.platformNote,
                tone: AknTone.info,
              )
            else ...[
              if (!otpEnabled)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: AknBanner(
                    message: AuthCopy.otpOffNote,
                    tone: AknTone.info,
                  ),
                ),
              if (activeHold != null)
                ThrottleBanner(
                  hold: activeHold,
                  margin: const EdgeInsets.only(bottom: 16),
                )
              else if (_error != null)
                AuthErrorBanner(
                  error: _error!,
                  margin: const EdgeInsets.only(bottom: 16),
                ),
              HoldAwareButton(
                scope: ThrottleScope.phoneVerify,
                label: s.verified
                    ? AuthCopy.reverify
                    : AuthCopy.sendVerification,
                busyLabel: AuthCopy.sendingCode,
                icon: PhosphorIconsRegular.chatDots,
                variant: s.verified
                    ? AknButtonVariant.secondary
                    : AknButtonVariant.primary,
                busy: _starting,
                onPressed: _starting ? null : () => unawaited(_start()),
              ),
              const SizedBox(height: 12),
              Text(
                AuthCopy.phoneChangeNote,
                style: t.bodySmall.copyWith(color: c.dim),
              ),
            ],
          ],
        );
      },
    );
  }
}

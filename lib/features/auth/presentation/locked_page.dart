import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/ui/ui.dart';
import '../application/biometric.dart';
import '../application/login_effects.dart';
import '../copy.dart';
import 'widgets/gate_view.dart';

/// Biyometrik kilit ekranı (`/locked`, spec A.4 A1). Uygulama arka planda 60 sn'den uzun kalınca
/// çekirdek kilitler (süre çekirdektedir); ekran açılınca bir kez Face ID / parmak izi ister. Başarısız
/// ya da iptal edilmiş denemeden sonra "Şifreyle giriş yap" görünür: oturum kapanır, giriş formu
/// kullanıcı adıyla hazır açılır.
class LockedPage extends ConsumerStatefulWidget {
  const LockedPage({super.key});

  @override
  ConsumerState<LockedPage> createState() => _LockedPageState();
}

class _LockedPageState extends ConsumerState<LockedPage> {
  late final AppLifecycleListener _lifecycle;
  Animation<double>? _routeAnimation;
  bool _busy = false;
  bool _autoTried = false;
  bool _signingOut = false;
  BiometricOutcome? _last;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _auto);
    WidgetsBinding.instance.addPostFrameCallback((_) => _auto());
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _lifecycle.dispose();
    super.dispose();
  }

  /// Ekran ön plandayken bir kez otomatik sorar (arka planda sistem penceresi açılamaz). Kilit
  /// sayfasının geçişi bitmeden sorulmaz: anında doğrulanırsa kabuk, eski kabuk henüz ağaçtayken
  /// yeniden kurulmasın.
  void _auto() {
    if (!mounted || _autoTried) return;
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    final animation = ModalRoute.of(context)?.animation;
    if (animation != null && !animation.isCompleted) {
      if (_routeAnimation == null) {
        _routeAnimation = animation;
        animation.addStatusListener(_onRouteStatus);
      }
      return;
    }
    _autoTried = true;
    unawaited(_unlock());
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = null;
    _auto();
  }

  Future<void> _unlock() async {
    if (_busy || _signingOut) return;
    setState(() => _busy = true);
    final outcome = await ref
        .read(biometricAuthenticatorProvider)
        .authenticate(AuthCopy.biometricReason);
    if (!mounted) return;
    if (outcome == BiometricOutcome.success) {
      AknHaptics.success();
      ref.read(sessionControllerProvider.notifier).unlock();
      return;
    }
    setState(() {
      _busy = false;
      _last = outcome;
    });
    if (outcome != BiometricOutcome.cancelled) AknHaptics.warning();
    final view = View.maybeOf(context);
    final message = _message(outcome);
    if (view != null && message != null) {
      unawaited(
        SemanticsService.sendAnnouncement(view, message, TextDirection.ltr),
      );
    }
  }

  Future<void> _passwordLogin() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    final session = ref.read(sessionControllerProvider);
    ref.read(loginPrefillProvider.notifier).set(session.access?.userName);
    await ref
        .read(sessionControllerProvider.notifier)
        .signOut(
          message: AuthCopy.passwordFallbackNotice,
          // Yeniden giriş: yarım teslim / sipariş taslakları korunur.
          reason: SignOutReason.lockFallback,
        );
  }

  static String? _message(BiometricOutcome? outcome) => switch (outcome) {
    BiometricOutcome.cancelled => AuthCopy.biometricCancelled,
    BiometricOutcome.failed => AuthCopy.biometricFailed,
    BiometricOutcome.unavailable => AuthCopy.biometricUnavailable,
    BiometricOutcome.lockedOut => AuthCopy.biometricLockedOut,
    BiometricOutcome.error => AuthCopy.biometricError,
    BiometricOutcome.success || null => null,
  };

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(sessionControllerProvider).access;
    final support = ref.watch(biometricSupportProvider).valueOrNull;
    final kind = support?.kind;
    final unavailable =
        (support != null && !support.available) ||
        _last == BiometricOutcome.unavailable;
    final failed = _last != null;
    final name = access?.displayName;
    final message = unavailable
        ? AuthCopy.biometricUnavailable
        : _message(_last);
    // Beyaz sayfa (tasarım v2 §7.2): 40 px logo karosu, `display` başlık, tek cümle; sonuç cümlesi
    // bir kuyuda; eylemler altta (birincil kilit aç, ikincil şifreyle giriş).
    return AppScaffold(
      appBar: false,
      showBell: false,
      showOfflineBanner: false,
      body: GateView(
        icon: biometricIcon(kind),
        tone: AknTone.neutral,
        title: name == null
            ? AuthCopy.lockedScreenTitle
            : AuthCopy.welcomeBack(name),
        message: name == null
            ? AuthCopy.lockedBody
            : '${AuthCopy.lockedScreenTitle}. ${AuthCopy.lockedBody}',
        below: message == null
            ? null
            : AknBanner(
                message: message,
                tone: unavailable ? AknTone.warn : AknTone.neutral,
                icon: unavailable
                    ? Icons.no_encryption_gmailerrorred_outlined
                    : biometricIcon(kind),
              ),
        primary: unavailable
            ? null
            : AknButton(
                label: failed ? AuthCopy.tryUnlockAgain : unlockLabel(kind),
                semanticLabel: unlockLabel(kind),
                icon: biometricIcon(kind),
                expand: true,
                size: AknButtonSize.large,
                loading: _busy,
                loadingLabel: AuthCopy.checking,
                onPressed: _signingOut ? null : _unlock,
              ),
        secondary: failed || unavailable
            ? AknButton.secondary(
                label: AuthCopy.passwordFallback,
                icon: Icons.password_rounded,
                expand: true,
                size: AknButtonSize.large,
                loading: _signingOut,
                onPressed: _busy ? null : _passwordLogin,
              )
            : null,
      ),
    );
  }
}

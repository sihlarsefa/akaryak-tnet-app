import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/ui/ui.dart';
import '../application/biometric.dart';
import '../application/login_effects.dart';
import '../copy.dart';

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
        .signOut(message: AuthCopy.passwordFallbackNotice);
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
    final c = context.akn;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AknTheme.overlayOnNavy,
      child: AppScaffold(
        appBar: false,
        showBell: false,
        showOfflineBanner: false,
        backgroundColor: c.navy,
        body: OnNavy(
          child: Builder(
            builder: (context) {
              final t = context.aknText;
              final n = context.akn;
              final message = unavailable
                  ? AuthCopy.biometricUnavailable
                  : _message(_last);
              return SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: math.max(0.0, constraints.maxHeight - 48),
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Center(
                                child: LogoMark(size: 64, animate: true),
                              ),
                              const SizedBox(height: 28),
                              Semantics(
                                header: true,
                                child: Text(
                                  name == null
                                      ? AuthCopy.lockedScreenTitle
                                      : AuthCopy.welcomeBack(name),
                                  style: t.title,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                name == null
                                    ? AuthCopy.lockedBody
                                    : '${AuthCopy.lockedScreenTitle}. ${AuthCopy.lockedBody}',
                                style: t.body.copyWith(color: n.dim),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 32),
                              Center(
                                child: ExcludeSemantics(
                                  child: Container(
                                    width: 88,
                                    height: 88,
                                    decoration: BoxDecoration(
                                      color: n.surface,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: n.lineStrong),
                                    ),
                                    child: Icon(
                                      biometricIcon(kind),
                                      size: 44,
                                      color: n.ink,
                                    ),
                                  ),
                                ),
                              ),
                              if (message != null) ...[
                                const SizedBox(height: 20),
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    message,
                                    style: t.bodyStrong.copyWith(color: n.ink),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 28),
                              if (!unavailable)
                                AknButton(
                                  label: failed
                                      ? AuthCopy.tryUnlockAgain
                                      : unlockLabel(kind),
                                  semanticLabel: unlockLabel(kind),
                                  icon: biometricIcon(kind),
                                  expand: true,
                                  size: AknButtonSize.large,
                                  loading: _busy,
                                  loadingLabel: AuthCopy.checking,
                                  onPressed: _signingOut ? null : _unlock,
                                ),
                              if (failed || unavailable) ...[
                                const SizedBox(height: 12),
                                AknButton.secondary(
                                  label: AuthCopy.passwordFallback,
                                  icon: Icons.password_rounded,
                                  expand: true,
                                  size: AknButtonSize.large,
                                  loading: _signingOut,
                                  onPressed: _busy ? null : _passwordLogin,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

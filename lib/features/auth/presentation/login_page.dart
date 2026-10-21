import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/auth/session_state.dart';
import '../../../core/env/app_config_controller.dart';
import '../../../core/env/app_env.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/network/fake/fake_auth.dart';
import '../../../core/network/fake/fake_personas.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/validators.dart';
import '../application/auth_errors.dart';
import '../application/auth_throttle.dart';
import '../application/link_opener.dart';
import '../application/login_effects.dart';
import '../application/server_gate_controller.dart';
import '../application/update_prompt.dart';
import '../copy.dart';
import '../data/server_gate.dart';
import 'code_page.dart';
import 'widgets/auth_banners.dart';
import 'widgets/auth_header.dart';
import 'widgets/hold_button.dart';
import 'widgets/legal_footer.dart';
import 'widgets/mode_switch.dart';
import 'widgets/no_account_sheet.dart';
import 'widgets/phone_formatter.dart';
import 'widgets/server_status.dart';

/// Giriş yöntemi.
enum LoginMode { password, phone }

/// Giriş (spec A.4 A1): kullanıcı adı / e-posta + şifre (parola yöneticisi doldurur ve kaydeder,
/// şifre göster/gizle), `features.otpLogin` açıksa "Telefonla" sekmesi, kilitlenme ve 429'da geri sayım,
/// "Şifremi unuttum" (portal), "Hesabım yok" ve alt bilgide "Gizlilik · KVKK · Koşullar". Sunucu bakımda
/// ya da uyumsuzsa form yerine durum ekranı gösterilir. Sahte kipte demo hesapları tek dokunuşla girer.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _user = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();
  final _userFocus = FocusNode(debugLabel: 'login.user');
  final _passwordFocus = FocusNode(debugLabel: 'login.password');
  final _phoneFocus = FocusNode(debugLabel: 'login.phone');

  LoginMode _mode = LoginMode.password;
  bool _obscure = true;
  bool _busy = false;
  AuthErrorInfo? _error;
  String? _userError;
  String? _passwordError;
  String? _phoneError;

  @override
  void initState() {
    super.initState();
    // Kilit ekranından "Şifreyle giriş yap": kullanıcı adı hazır, şifreye odaklan.
    final prefill = ref.read(loginPrefillProvider);
    if (prefill != null && prefill.isNotEmpty) {
      _user.text = prefill;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(loginPrefillProvider.notifier).set(null);
        _passwordFocus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    _phone.dispose();
    _userFocus.dispose();
    _passwordFocus.dispose();
    _phoneFocus.dispose();
    super.dispose();
  }

  /// Telefonla giriş sunucuda kapandıysa şifreye döner.
  LoginMode get _effectiveMode =>
      ref.read(otpLoginEnabledProvider) ? _mode : LoginMode.password;

  void _announce(String message) {
    final view = View.maybeOf(context);
    if (view == null) return;
    unawaited(
      SemanticsService.sendAnnouncement(view, message, TextDirection.ltr),
    );
  }

  void _setMode(LoginMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _error = null;
      _userError = null;
      _passwordError = null;
      _phoneError = null;
    });
  }

  void _submit() => unawaited(
    _effectiveMode == LoginMode.password ? _loginWithPassword() : _sendOtp(),
  );

  // ------------------------------------------------------------------ Şifreyle giriş

  Future<void> _loginWithPassword({String? user, String? password}) async {
    if (_busy) return;
    final u = (user ?? _user.text).trim();
    final p = password ?? _password.text;
    setState(() {
      _error = null;
      _userError = u.isEmpty ? AuthCopy.userRequired : null;
      _passwordError = p.isEmpty ? AuthCopy.passwordRequired : null;
    });
    if (u.isEmpty || p.isEmpty) {
      AknHaptics.warning();
      (u.isEmpty ? _userFocus : _passwordFocus).requestFocus();
      _announce(u.isEmpty ? AuthCopy.userRequired : AuthCopy.passwordRequired);
      return;
    }
    if (ref
            .read(authThrottleProvider.notifier)
            .active(ThrottleScope.password) !=
        null) {
      return;
    }
    FocusScope.of(context).unfocus();
    final container = ProviderScope.containerOf(context, listen: false);
    final primer = pushPrimerPending(container);
    setState(() => _busy = true);
    try {
      final outcome = await ref
          .read(sessionControllerProvider.notifier)
          .loginWithPassword(u, p);
      if (outcome is LoginSucceeded) {
        unawaited(
          afterInteractiveLogin(
            container,
            primerPending: primer,
            savePassword: true,
          ),
        );
      }
      if (!mounted) return;
      setState(() => _busy = false);
      if (outcome is LoginNeedsCode) {
        await context.push(
          AppRoutes.loginCode,
          extra: CodePageArgs(
            challenge: outcome.challenge,
            purpose: CodePurpose.twoFactor,
            primerPending: primer,
            savePassword: true,
          ),
        );
      }
    } on AppFailure catch (f) {
      if (!mounted) return;
      setState(() => _busy = false);
      _onFailure(f, ThrottleScope.password);
    }
  }

  // ------------------------------------------------------------------ Telefonla giriş

  Future<void> _sendOtp() async {
    if (_busy) return;
    final digits = TrMobileFormatter.localDigits(_phone.text);
    final invalid = Validators.mobilePhone(digits);
    setState(() {
      _error = null;
      _phoneError = invalid;
    });
    if (invalid != null) {
      AknHaptics.warning();
      _phoneFocus.requestFocus();
      _announce(invalid);
      return;
    }
    if (ref.read(authThrottleProvider.notifier).active(ThrottleScope.otp) !=
        null) {
      return;
    }
    final phone = Validators.normalizePhone(digits)!;
    FocusScope.of(context).unfocus();
    final container = ProviderScope.containerOf(context, listen: false);
    final primer = pushPrimerPending(container);
    setState(() => _busy = true);
    try {
      final challenge = await ref
          .read(sessionControllerProvider.notifier)
          .sendOtp(phone);
      if (!mounted) return;
      setState(() => _busy = false);
      await context.push(
        AppRoutes.loginCode,
        extra: CodePageArgs(
          challenge: challenge,
          purpose: CodePurpose.otpLogin,
          phone: phone,
          primerPending: primer,
        ),
      );
    } on AppFailure catch (f) {
      if (!mounted) return;
      setState(() => _busy = false);
      _onFailure(f, ThrottleScope.otp);
    }
  }

  // ------------------------------------------------------------------ Hatalar

  void _onFailure(AppFailure f, ThrottleScope scope) {
    switch (f) {
      case RateLimitedFailure(:final retryAfter):
        // Kilitlenme / hız sınırı: bant + düğmede geri sayım (spec C.7).
        ref
            .read(authThrottleProvider.notifier)
            .hold(
              scope,
              retryAfter,
              message: f.problem?.detail,
              lockout: scope == ThrottleScope.password,
            );
        AknHaptics.warning();
        _announce(f.message);
        return;
      case UpdateRequiredFailure():
        // Yönlendirici güncelleme ekranına geçer (426, çekirdek).
        return;
      case NotFoundFailure():
        // Eski API: mobil uçlar yok. Sunucu durumu yeniden yoklanır; doğrulanırsa form yerine
        // "Sunucu güncel değil" gelir.
        unawaited(ref.read(serverGateProvider.notifier).recheck());
      default:
        break;
    }
    final info = f is NotFoundFailure
        ? const AuthErrorInfo(
            title: AuthCopy.serverTitle,
            message: AuthCopy.serverBody,
          )
        : describeAuthFailure(
            f,
            title: scope == ThrottleScope.otp
                ? AuthCopy.codeErrorTitle
                : AuthCopy.errorTitle,
          );
    setState(() {
      _error = info;
      _userError = info.fieldError('userNameOrEmail');
      _passwordError = info.fieldError('password');
      _phoneError = info.fieldError('phone');
    });
    if (f is UnauthorizedFailure && scope == ThrottleScope.password) {
      _password.clear();
      _passwordFocus.requestFocus();
    }
    AknHaptics.warning();
    _announce(info.message);
  }

  Future<void> _openForgotPassword() async {
    final env = ref.read(appEnvProvider);
    final ok = await ref.read(linkOpenerProvider)(env.forgotPasswordUrl);
    if (!ok) AppToast.error(AuthCopy.linkFailed);
  }

  // ------------------------------------------------------------------ Görünüm

  @override
  Widget build(BuildContext context) {
    final gate = ref.watch(serverGateProvider).valueOrNull;
    final blocked = gate != null && gate.blocks;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: blocked
          ? AknTheme.overlayFor(context.akn.brightness)
          : AknTheme.overlayOnNavy,
      child: AppScaffold(
        appBar: false,
        showBell: false,
        showOfflineBanner: false,
        body: FadeThroughSwitcher(
          child: blocked
              ? KeyedSubtree(
                  key: ValueKey(gate.kind),
                  child: UpdateGateBody(
                    reason: gate.kind == ServerGateKind.maintenance
                        ? UpdateReason.maintenance
                        : UpdateReason.server,
                    maintenanceMessage: gate.maintenanceMessage,
                  ),
                )
              : KeyedSubtree(
                  key: const ValueKey('login'),
                  child: _form(context),
                ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final env = ref.watch(appEnvProvider);
    final otpEnabled = ref.watch(otpLoginEnabledProvider);
    final mode = otpEnabled ? _mode : LoginMode.password;
    final t = context.aknText;
    final c = context.akn;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      excludeFromSemantics: true,
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewPaddingOf(context).bottom,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          // Büyük yazıda başlık kısalır; form ilk ekranda kalır.
          AuthHeader(compact: MediaQuery.textScalerOf(context).scale(16) > 22),
          // Sahte kipte demo hesapları formun üstünde (persona değiştirmek tek dokunuş).
          if (kFakeApiCompiled && env.isFake)
            _DemoAccounts(onSelected: _loginAsDemo),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                // Form ilk açılışta bir kez, sakin biçimde belirir (azaltılmış harekette anında).
                child: FadeUp(
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(AuthCopy.loginTitle, style: t.title),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AuthCopy.loginSubtitle,
                          style: t.bodySmall.copyWith(color: c.dim),
                        ),
                        const SizedBox(height: 20),
                        if (otpEnabled) ...[
                          ModeSwitch<LoginMode>(
                            semanticLabel: AuthCopy.modeGroup,
                            value: mode,
                            onChanged: _setMode,
                            options: const [
                              (
                                value: LoginMode.password,
                                label: AuthCopy.modePassword,
                                icon: Icons.password_rounded,
                              ),
                              (
                                value: LoginMode.phone,
                                label: AuthCopy.modePhone,
                                icon: Icons.smartphone_rounded,
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ],
                        ..._notices(context, mode),
                        SharedAxisSwitcher(
                          reverse: mode == LoginMode.password,
                          child: mode == LoginMode.password
                              ? KeyedSubtree(
                                  key: const ValueKey('password'),
                                  child: _passwordFields(),
                                )
                              : KeyedSubtree(
                                  key: const ValueKey('phone'),
                                  child: _phoneFields(),
                                ),
                        ),
                        const SizedBox(height: 20),
                        HoldAwareButton(
                          scope: mode == LoginMode.password
                              ? ThrottleScope.password
                              : ThrottleScope.otp,
                          label: mode == LoginMode.password
                              ? AuthCopy.loginButton
                              : AuthCopy.sendCode,
                          busyLabel: mode == LoginMode.password
                              ? AuthCopy.loggingIn
                              : AuthCopy.sendingCode,
                          busy: _busy,
                          onPressed: _busy ? null : _submit,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          runSpacing: 4,
                          children: [
                            if (mode == LoginMode.password)
                              AknButton.ghost(
                                label: AuthCopy.forgotPassword,
                                onPressed: _openForgotPassword,
                              ),
                            AknButton.ghost(
                              label: AuthCopy.noAccount,
                              icon: Icons.help_outline_rounded,
                              onPressed: () => showNoAccountSheet(context),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const LegalFooter(),
        ],
      ),
    );
  }

  void _loginAsDemo(FakePersona p) {
    _setMode(LoginMode.password);
    _user.text = p.key;
    _password.text = FakeAuth.password;
    unawaited(_loginWithPassword(user: p.key, password: FakeAuth.password));
  }

  List<Widget> _notices(BuildContext context, LoginMode mode) {
    const gap = EdgeInsets.only(bottom: 16);
    final scope = mode == LoginMode.password
        ? ThrottleScope.password
        : ThrottleScope.otp;
    ref.watch(authThrottleProvider);
    final hold = ref.read(authThrottleProvider.notifier).active(scope);
    final active = hold != null;
    final session = ref.watch(sessionControllerProvider);
    final notice = session is SessionUnauthenticated ? session.message : null;
    final offline = AppChrome.maybeOf(context)?.offline ?? false;
    final update = ref.watch(updateStatusProvider) == UpdateStatus.optional;
    final error = _error;
    return [
      if (hold != null)
        ThrottleBanner(hold: hold, margin: gap)
      else if (error != null)
        AuthErrorBanner(error: error, margin: gap)
      else if (notice != null)
        Padding(
          padding: gap,
          child: AknBanner(message: notice, tone: AknTone.warn),
        ),
      if (offline && !active)
        const Padding(
          padding: gap,
          child: AknBanner(
            message: AuthCopy.offlineNotice,
            tone: AknTone.neutral,
            icon: Icons.cloud_off_rounded,
          ),
        ),
      if (update && error == null && !active)
        Padding(
          padding: gap,
          child: AknBanner(
            title: AuthCopy.updateBannerTitle,
            message: AuthCopy.updateBannerBody,
            tone: AknTone.info,
            icon: Icons.system_update_rounded,
            actionLabel: AuthCopy.updateAction,
            onAction: () => openStore(ref),
          ),
        ),
    ];
  }

  Widget _passwordFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AknTextField(
          controller: _user,
          focusNode: _userFocus,
          label: AuthCopy.userLabel,
          prefixIcon: Icons.person_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username, AutofillHints.email],
          errorText: _userError,
          onChanged: (_) {
            if (_userError != null) setState(() => _userError = null);
          },
        ),
        const SizedBox(height: 12),
        AknTextField(
          controller: _password,
          focusNode: _passwordFocus,
          label: AuthCopy.passwordLabel,
          prefixIcon: Icons.lock_outline_rounded,
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          errorText: _passwordError,
          onChanged: (_) {
            if (_passwordError != null) setState(() => _passwordError = null);
          },
          onSubmitted: (_) => _submit(),
          suffixIcon: IconButton(
            tooltip: _obscure ? AuthCopy.showPassword : AuthCopy.hidePassword,
            onPressed: () => setState(() => _obscure = !_obscure),
            icon: Icon(
              _obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
          ),
        ),
      ],
    );
  }

  Widget _phoneFields() {
    return AknTextField(
      controller: _phone,
      focusNode: _phoneFocus,
      label: AuthCopy.phoneLabel,
      hint: AuthCopy.phoneHint,
      helper: AuthCopy.phoneHelper,
      prefixIcon: Icons.smartphone_rounded,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.telephoneNumberNational],
      inputFormatters: const [TrMobileFormatter()],
      errorText: _phoneError,
      onChanged: (_) {
        if (_phoneError != null) setState(() => _phoneError = null);
      },
      onSubmitted: (_) => _submit(),
    );
  }
}

/// Sahte kipte demo hesapları (şifre `demo`, kod `123456`): yatay kaydırılan kısa kartlar; canlı
/// derlemede hiç gösterilmez.
class _DemoAccounts extends StatelessWidget {
  const _DemoAccounts({required this.onSelected});

  final ValueChanged<FakePersona> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(AuthCopy.demoTitle, style: t.bodyStrong),
                ),
                Text(
                  AuthCopy.demoSubtitle(FakeAuth.password, FakeAuth.code),
                  style: t.caption.copyWith(color: c.dim),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final p in fakePersonas) ...[
                  _DemoChip(persona: p, onTap: () => onSelected(p)),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoChip extends StatelessWidget {
  const _DemoChip({required this.persona, required this.onTap});

  final FakePersona persona;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Semantics(
      button: true,
      label: '${persona.displayName}, ${persona.summary}',
      excludeSemantics: true,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 240,
          minHeight: AknSpace.minTap,
        ),
        child: Material(
          color: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AknRadius.card,
            side: BorderSide(color: c.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AknAvatar(name: persona.displayName, size: 32),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          persona.displayName,
                          style: t.bodyStrong.copyWith(color: c.ink),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          persona.summary,
                          style: t.caption.copyWith(color: c.dim),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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
import 'widgets/demo_accounts.dart';
import 'widgets/hold_button.dart';
import 'widgets/mode_switch.dart';
import 'widgets/no_account_sheet.dart';
import 'widgets/phone_formatter.dart';
import 'widgets/server_status.dart';

/// Giriş yöntemi.
enum LoginMode { password, phone }

/// Giriş (spec A.4 A1): kullanıcı adı / e-posta + şifre (parola yöneticisi doldurur ve kaydeder,
/// şifre göster/gizle), `features.otpLogin` açıksa "Telefonla" sekmesi, kilitlenme ve 429'da geri sayım,
/// "Şifremi unuttum" (portal), "Hesabım yok" ve alt bilgide "Gizlilik · KVKK · Koşullar". Sunucu bakımda
/// ya da uyumsuzsa form yerine durum ekranı gösterilir. Sahte kipte (demo derlemesi) bandın hemen
/// altında, formun üstünde demo hesapları Müşteri / Bayi / Merkez kartlarıyla durur; bir karta dokunmak
/// o hesapla giriş yapar (sahip kararı 2026-10-21). Canlı derlemede bölüm hiç derlenmez.
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

  /// Demo kartından giriş yapılan personanın anahtarı (kartında ilerleme göstergesi).
  String? _demoBusy;

  /// Demo bölümü: alt bilgideki "Demo" bağlantısı buraya kaydırır.
  final _demoKey = GlobalKey(debugLabel: 'login.demo');
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

  /// [demoCode] verilirse (demo kartı) iki adımlı doğrulama kodu da kendiliğinden girilir: tek dokunuş
  /// = oturum açık. Demo girişinde parola yöneticisine kaydet denmez.
  Future<void> _loginWithPassword({
    String? user,
    String? password,
    String? demoCode,
  }) async {
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
      final session = ref.read(sessionControllerProvider.notifier);
      var outcome = await session.loginWithPassword(u, p);
      if (outcome is LoginNeedsCode && demoCode != null) {
        outcome = await session.verifyCode(
          outcome.challenge.challengeId,
          demoCode,
        );
      }
      if (outcome is LoginSucceeded) {
        unawaited(
          afterInteractiveLogin(
            container,
            primerPending: primer,
            savePassword: demoCode == null,
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
    return AppScaffold(
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
            : KeyedSubtree(key: const ValueKey('login'), child: _form(context)),
      ),
    );
  }

  /// Giriş (tasarım v3 "Akış"): ışıklı turuncu bant (süzülen logo, yazı markası, başlık), üstüne binen
  /// beyaz sayfa (r28) ve içinde sırayla beliren bölümler: "Hoş geldiniz", demo kartları (demo
  /// derlemesi), "Şifre ile / Numara ile" anahtarı, etiketi üstte alanlar, birincil "Giriş yap" ve
  /// "Hesabınız yok mu? Bayinizden davet isteyin".
  Widget _form(BuildContext context) {
    // Derleme zamanı koruması: canlı derlemede `kFakeApiCompiled` sabit false; demo bölümü ve
    // personalar derlemeye girmez.
    final demo = kFakeApiCompiled && ref.watch(demoLoginsEnabledProvider);
    final otpEnabled = ref.watch(otpLoginEnabledProvider);
    final mode = otpEnabled ? _mode : LoginMode.password;
    final t = context.aknText;
    final c = context.akn;
    final large = MediaQuery.textScalerOf(context).scale(16) > 22;
    final compact = large || demo;
    final notices = _notices(context, mode);
    final headerHeight = AuthHeader.layoutHeight(context, compact: compact);
    final noticeBlock = AknAnimatedSize(
      alignment: Alignment.topCenter,
      duration: AknMotion.slow,
      curve: AknMotion.emphasizedCurve,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: notices,
      ),
    );
    return Stack(
      children: [
        // Kenarda esneyince (iOS) üstte bandın rengi, altta sayfanın rengi görünür.
        Positioned.fill(
          child: Column(
            children: [
              Expanded(child: ColoredBox(color: c.heroStart)),
              Expanded(child: ColoredBox(color: c.surface)),
            ],
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          excludeFromSemantics: true,
          onTap: () => FocusScope.of(context).unfocus(),
          // Tek sütun, hepsi kurulur (tembel liste değil): demo bölümüyle form ilk ekranın altında kalsa
          // da alanlar hazırdır (parola yöneticisi, kilit ekranından gelince şifreye odak).
          child: LayoutBuilder(
            builder: (context, viewport) => SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Büyük yazıda ve demo derlemesinde bant daralır; altındaki içerik ilk ekrana yaklaşır.
                  AuthHeader(compact: compact),
                  // Beyaz sayfa ekranın altına kadar iner (kısa içerikte de boşluk yok).
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: math.max(
                        0.0,
                        viewport.maxHeight - headerHeight,
                      ),
                    ),
                    child: LoginSheet(
                      child: Padding(
                        // Alt bilgi yok (sahip kararı); ev çubuğu payının bir kısmı son bağlantının
                        // 48 px dokunma alanına girer.
                        padding: EdgeInsets.only(
                          bottom:
                              28 +
                              math.max(
                                0.0,
                                MediaQuery.viewPaddingOf(context).bottom - 18,
                              ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AuthReveal(
                              index: 0,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AknSpace.page,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Semantics(
                                      header: true,
                                      child: Text(
                                        demo
                                            ? AuthCopy.welcome
                                            : AuthCopy.loginTitle,
                                        style: t.display.copyWith(color: c.ink),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      demo
                                          ? AuthCopy.welcomeLine
                                          : AuthCopy.loginSubtitle,
                                      style: t.body.copyWith(color: c.dim),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // QA SC-03: demo derlemesinde uyarılar (oturum kapandı, hata, bekleme,
                            // çevrimdışı) demo kartlarının üstünde, ilk ekranda görünür.
                            if (demo)
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  AknSpace.page,
                                  notices.isEmpty ? 0 : 16,
                                  AknSpace.page,
                                  0,
                                ),
                                child: noticeBlock,
                              ),
                            if (demo) ...[
                              AuthReveal(
                                index: 1,
                                child: Padding(
                                  key: _demoKey,
                                  padding: const EdgeInsets.only(top: 18),
                                  child: DemoAccountsSection(
                                    onSelected: _loginAsDemo,
                                    onSeeAll: () => _pickDemo(context),
                                    busyKey: _demoBusy,
                                    enabled: !_busy,
                                    singleRow: true,
                                  ),
                                ),
                              ),
                              const AuthReveal(
                                index: 2,
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    AknSpace.page,
                                    2,
                                    AknSpace.page,
                                    0,
                                  ),
                                  child: OwnAccountDivider(),
                                ),
                              ),
                            ],
                            Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 520,
                                ),
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    AknSpace.page,
                                    demo ? 16 : 22,
                                    AknSpace.page,
                                    0,
                                  ),
                                  child: AutofillGroup(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (!demo) noticeBlock,
                                        // Şifre ile / Numara ile: akan başparmaklı anahtar, alanlar yatay
                                        // geçişle değişir.
                                        if (otpEnabled) ...[
                                          AuthReveal(
                                            index: 3,
                                            child: ModeSwitch<LoginMode>(
                                              semanticLabel:
                                                  AuthCopy.loginTitle,
                                              value: mode,
                                              onChanged: (m) {
                                                if (_busy || m == mode) return;
                                                _setMode(m);
                                              },
                                              options: const [
                                                (
                                                  value: LoginMode.password,
                                                  label: AuthCopy.modePassword,
                                                  icon:
                                                      PhosphorIconsRegular.lock,
                                                ),
                                                (
                                                  value: LoginMode.phone,
                                                  label: AuthCopy.modePhone,
                                                  icon: PhosphorIconsRegular
                                                      .deviceMobile,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(height: 18),
                                        ],
                                        AuthReveal(
                                          index: 4,
                                          child: SharedAxisSwitcher(
                                            reverse: mode == LoginMode.password,
                                            child: mode == LoginMode.password
                                                ? KeyedSubtree(
                                                    key: const ValueKey(
                                                      'password',
                                                    ),
                                                    child: _passwordFields(),
                                                  )
                                                : KeyedSubtree(
                                                    key: const ValueKey(
                                                      'phone',
                                                    ),
                                                    child: _phoneFields(),
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        AuthReveal(
                                          index: 5,
                                          child: HoldAwareButton(
                                            scope: mode == LoginMode.password
                                                ? ThrottleScope.password
                                                : ThrottleScope.otp,
                                            label: mode == LoginMode.password
                                                ? AuthCopy.loginButton
                                                : AuthCopy.sendCode,
                                            busyLabel:
                                                mode == LoginMode.password
                                                ? AuthCopy.loggingIn
                                                : AuthCopy.sendingCode,
                                            busy: _busy && _demoBusy == null,
                                            onPressed: _busy ? null : _submit,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        AuthReveal(
                                          index: 6,
                                          child: _NoAccountLine(
                                            onTap: () =>
                                                showNoAccountSheet(context),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// "Tümünü gör": tüm demo hesapları açıklamalarıyla, gruplu bir sayfada.
  Future<void> _pickDemo(BuildContext context) async {
    if (_busy) return;
    final persona = await showAppSheet<FakePersona>(
      context: context,
      title: AuthCopy.demoTitle,
      subtitle: AuthCopy.demoSubtitle(FakeAuth.password, FakeAuth.code),
      padding: const EdgeInsets.only(bottom: 16),
      builder: (sheet) =>
          DemoAccountsList(onSelected: (p) => Navigator.of(sheet).pop(p)),
    );
    if (persona != null && mounted) _loginAsDemo(persona);
  }

  /// Demo kartı: tek dokunuşla o personayla giriş (şifre `demo`; merkezin SMS kodu `123456`
  /// kendiliğinden girilir). Form alanları doldurulmaz (parola yöneticisi demo hesabını kaydetmez).
  void _loginAsDemo(FakePersona p) {
    if (_busy) return;
    AknHaptics.selection();
    _setMode(LoginMode.password);
    setState(() => _demoBusy = p.key);
    _announce(AuthCopy.demoSigningIn(p.displayName));
    unawaited(
      _loginWithPassword(
        user: p.key,
        password: FakeAuth.password,
        demoCode: FakeAuth.code,
      ).whenComplete(() {
        if (mounted) setState(() => _demoBusy = null);
      }),
    );
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
            icon: PhosphorIconsRegular.cloudSlash,
          ),
        ),
      if (update && error == null && !active)
        Padding(
          padding: gap,
          child: AknBanner(
            title: AuthCopy.updateBannerTitle,
            message: AuthCopy.updateBannerBody,
            tone: AknTone.info,
            icon: PhosphorIconsRegular.downloadSimple,
            actionLabel: AuthCopy.updateAction,
            onAction: () => openStore(ref),
          ),
        ),
    ];
  }

  Widget _passwordFields() {
    // Büyük yazıda "Şifremi unuttum" etiket satırına sığmaz: alanın altına iner.
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AknTextField(
          controller: _user,
          focusNode: _userFocus,
          label: AuthCopy.userLabel,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username, AutofillHints.email],
          errorText: _userError,
          onChanged: (_) {
            if (_userError != null) setState(() => _userError = null);
          },
        ),
        // Şifre etiketinin satırı "Şifremi unuttum" bağlantısıyla 48 px; boşluğu o verir.
        if (large) const SizedBox(height: 14),
        AknTextField(
          controller: _password,
          focusNode: _passwordFocus,
          label: AuthCopy.passwordLabel,
          labelActionText: large ? null : AuthCopy.forgotPassword,
          onLabelAction: large ? null : _openForgotPassword,
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.password],
          errorText: _passwordError,
          onChanged: (_) {
            if (_passwordError != null) setState(() => _passwordError = null);
          },
          onSubmitted: (_) => _submit(),
          suffixIcon: _RevealButton(
            obscured: _obscure,
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        if (large)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AknInlineLink(
              label: AuthCopy.forgotPassword,
              onTap: _openForgotPassword,
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

/// Şifre alanının sağındaki "Göster / Gizle" (tasarım v3): göz simgesi + ink 14/20 600, 48 dp hedef. Simge
/// değişirken küçülüp büyüyerek döner (göz → kapalı göz); basınca hafifçe içe çöker.
class _RevealButton extends StatelessWidget {
  const _RevealButton({required this.obscured, required this.onPressed});

  final bool obscured;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final label = obscured ? AuthCopy.show : AuthCopy.hide;
    final duration = AknMotion.of(context, AknMotion.iconSwap);
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: Tooltip(
        message: obscured ? AuthCopy.showPassword : AuthCopy.hidePassword,
        excludeFromSemantics: true,
        child: Semantics(
          button: true,
          label: obscured ? AuthCopy.showPassword : AuthCopy.hidePassword,
          excludeSemantics: true,
          onTap: onPressed,
          child: PressScale(
            child: InkWell(
              onTap: () {
                AknHaptics.selection();
                onPressed();
              },
              borderRadius: AknRadius.buttonSmall,
              splashFactory: NoSplash.splashFactory,
              highlightColor: c.surfaceAlt,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AknSpace.minTap,
                  minWidth: AknSpace.minTap,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: duration,
                        switchInCurve: AknMotion.pop,
                        switchOutCurve: AknMotion.exit,
                        transitionBuilder: (child, a) => FadeTransition(
                          opacity: a,
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.6, end: 1).animate(a),
                            child: RotationTransition(
                              turns: Tween<double>(
                                begin: -0.08,
                                end: 0,
                              ).animate(a),
                              child: child,
                            ),
                          ),
                        ),
                        child: Icon(
                          obscured
                              ? PhosphorIconsRegular.eye
                              : PhosphorIconsRegular.eyeSlash,
                          key: ValueKey(obscured),
                          size: 20,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: t.label.copyWith(
                          fontSize: 14,
                          height: 20 / 14,
                          color: c.ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Hesabınız yok mu? Bayinizden davet isteyin" (ortalı; bağlantı ink 600 + alt çizgi).
class _NoAccountLine extends StatelessWidget {
  const _NoAccountLine({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final style = t.body.copyWith(height: 20 / 15);
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        ExcludeSemantics(
          child: Text(AuthCopy.noAccount, style: style.copyWith(color: c.dim)),
        ),
        AknInlineLink(
          label: AuthCopy.noAccountLink,
          onTap: onTap,
          style: style.copyWith(fontWeight: FontWeight.w700, color: c.link),
        ),
      ],
    );
  }
}

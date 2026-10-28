import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/ui/ui.dart';
import '../copy.dart';
import '../data/profile_repository.dart';
import 'widgets/settings_widgets.dart';

/// Şifre kuralları (sunucu Identity ayarları: en az 8 karakter, büyük harf, küçük harf, rakam).
abstract final class PasswordRules {
  static bool length(String v) => v.length >= 8;
  static bool upper(String v) => RegExp(r'[A-ZÇĞİÖŞÜ]').hasMatch(v);
  static bool lower(String v) => RegExp(r'[a-zçğıöşü]').hasMatch(v);
  static bool digit(String v) => RegExp(r'\d').hasMatch(v);

  static bool all(String v) => length(v) && upper(v) && lower(v) && digit(v);
}

/// Şifre değiştir (spec A.4 A8 `me/change-password`; tasarım v3): mevcut şifre, yeni şifre (güç çizgili
/// canlı kural kuyusu), tekrar; bölümler sırayla belirir, sunucu hatası bandı yerinde yumuşakça açılır.
/// Başarılı olunca sunucu tüm oturumları kapatır; uygulama "Güvenlik bilgileriniz değişti" iletisiyle
/// giriş ekranına döner.
class ChangePasswordPage extends ConsumerStatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  ConsumerState<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends ConsumerState<ChangePasswordPage> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  bool _show = false;
  String? _error;
  String? _currentError;

  @override
  void initState() {
    super.initState();
    _next.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _error = null;
      _currentError = null;
    });
    if (!(_form.currentState?.validate() ?? false)) {
      AknHaptics.warning();
      return;
    }
    try {
      await ref
          .read(profileRepositoryProvider)
          .changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
    } on AppFailure catch (f) {
      if (!mounted) return;
      AknHaptics.warning();
      setState(() {
        if (f.message.contains('Mevcut şifre')) {
          _currentError = f.message;
          _current.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _current.text.length,
          );
        } else {
          _error = f.message;
        }
      });
      return;
    }
    if (!mounted) return;
    TextInput.finishAutofillContext();
    AppToast.success(ProfileCopy.passwordDoneTitle);
    await ref
        .read(sessionControllerProvider.notifier)
        .signOut(
          message: ProfileCopy.securityChanged,
          reason: SignOutReason.securityChanged,
        );
  }

  Widget _toggle() => IconButton(
    tooltip: _show ? ProfileCopy.hidePassword : ProfileCopy.showPassword,
    onPressed: () => setState(() => _show = !_show),
    icon: Icon(
      _show ? PhosphorIconsRegular.eyeSlash : PhosphorIconsRegular.eye,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final v = _next.text;
    return AppScaffold(
      title: ProfileCopy.passwordTitle,
      showBell: false,
      actionBar: barOf(
        AknButton(
          label: ProfileCopy.passwordSave,
          expand: true,
          showSuccess: false,
          onPressedAsync: _submit,
        ),
      ),
      body: Form(
        key: _form,
        child: AutofillGroup(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AknSpace.page,
              16,
              AknSpace.page,
              32,
            ),
            children: [
              const SettingsReveal(
                index: 0,
                child: AknBanner(
                  tone: AknTone.info,
                  icon: PhosphorIconsRegular.devices,
                  message: ProfileCopy.passwordIntro,
                ),
              ),
              // Hata bandı yerinde açılır (yapı sabit: alanlar yeniden kurulmaz).
              AknAnimatedSize(
                duration: AknMotion.slow,
                curve: AknMotion.emphasizedCurve,
                alignment: Alignment.topCenter,
                child: _error == null
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: AknBanner(
                          tone: AknTone.danger,
                          message: _error!,
                        ),
                      ),
              ),
              const SizedBox(height: 20),
              SettingsReveal(
                index: 1,
                child: AknTextField(
                  controller: _current,
                  label: ProfileCopy.currentPassword,
                  requiredMark: true,
                  obscureText: !_show,
                  errorText: _currentError,
                  onChanged: (_) {
                    if (_currentError != null) {
                      setState(() => _currentError = null);
                    }
                  },
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.password],
                  suffixIcon: _toggle(),
                  validator: (s) => s == null || s.isEmpty
                      ? ProfileCopy.currentPasswordRequired
                      : null,
                ),
              ),
              const SizedBox(height: 16),
              SettingsReveal(
                index: 2,
                child: AknTextField(
                  controller: _next,
                  label: ProfileCopy.newPassword,
                  requiredMark: true,
                  obscureText: !_show,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  suffixIcon: _toggle(),
                  validator: (s) {
                    final x = s ?? '';
                    if (!PasswordRules.all(x)) return ProfileCopy.passwordRules;
                    if (x == _current.text) return ProfileCopy.passwordSame;
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 12),
              // v3: kuralların kuyusu — üstte dört dilimli güç çizgisi, altında canlı kurallar.
              SettingsReveal(
                index: 3,
                child: _RulesWell(
                  rules: [
                    (PasswordRules.length(v), ProfileCopy.ruleLength),
                    (PasswordRules.upper(v), ProfileCopy.ruleUpper),
                    (PasswordRules.lower(v), ProfileCopy.ruleLower),
                    (PasswordRules.digit(v), ProfileCopy.ruleDigit),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SettingsReveal(
                index: 4,
                child: AknTextField(
                  controller: _again,
                  label: ProfileCopy.newPasswordAgain,
                  requiredMark: true,
                  obscureText: !_show,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  suffixIcon: _toggle(),
                  onSubmitted: (_) => _submit(),
                  validator: (s) =>
                      s != _next.text ? ProfileCopy.passwordMismatch : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kuralların kuyusu (tasarım v3): `surfaceAlt` zeminde r14; üstte dört dilimli güç çizgisi (sağlanan
/// her kural bir dilimi soldan sağa yeşille doldurur), altında kurallar.
class _RulesWell extends StatelessWidget {
  const _RulesWell({required this.rules});

  final List<(bool, String)> rules;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final done = rules.where((r) => r.$1).length;
    final duration = AknMotion.of(context, AknMotion.slow);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: AknRadius.input,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < rules.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: AknRadius.pillAll,
                      ),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: i < done ? 1 : 0),
                        duration: duration,
                        curve: AknMotion.emphasizedCurve,
                        builder: (context, f, _) => FractionallySizedBox(
                          alignment: AlignmentDirectional.centerStart,
                          widthFactor: f,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: done == rules.length
                                  ? c.ok.solid
                                  : c.brand,
                              borderRadius: AknRadius.pillAll,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final (ok, label) in rules) _Rule(ok: ok, label: label),
        ],
      ),
    );
  }
}

/// Canlı şifre kuralı satırı (renk tek başına değil: ikon ve "sağlandı" okunur). Sağlanınca onay simgesi
/// küçükten büyüyerek ve hafifçe taşarak gelir.
class _Rule extends StatelessWidget {
  const _Rule({required this.ok, required this.label});

  final bool ok;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Semantics(
      label: '$label, ${ok ? 'sağlandı' : 'sağlanmadı'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: AknMotion.of(context, AknMotion.base),
              switchInCurve: AknMotion.pop,
              switchOutCurve: AknMotion.exit,
              transitionBuilder: (child, a) => ScaleTransition(
                scale: Tween<double>(begin: 0.4, end: 1).animate(a),
                child: FadeTransition(opacity: a, child: child),
              ),
              child: Icon(
                ok
                    ? PhosphorIconsFill.checkCircle
                    : PhosphorIconsRegular.circle,
                key: ValueKey(ok),
                size: 18,
                color: ok ? c.ok.fg : c.dim,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedDefaultTextStyle(
                duration: AknMotion.of(context, AknMotion.base),
                style: t.bodySmall.copyWith(
                  color: ok ? c.ok.fg : c.text,
                  fontWeight: ok ? FontWeight.w600 : FontWeight.w400,
                ),
                child: Text(label),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

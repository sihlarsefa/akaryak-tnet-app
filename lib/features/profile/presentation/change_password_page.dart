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

/// Şifre değiştir (spec A.4 A8 `me/change-password`): mevcut şifre, yeni şifre (canlı kural listesi),
/// tekrar. Başarılı olunca sunucu tüm oturumları kapatır; uygulama "Güvenlik bilgileriniz değişti"
/// iletisiyle giriş ekranına döner.
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
        .signOut(message: ProfileCopy.securityChanged);
  }

  Widget _toggle() => IconButton(
    tooltip: _show ? ProfileCopy.hidePassword : ProfileCopy.showPassword,
    onPressed: () => setState(() => _show = !_show),
    icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded),
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
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              const AknBanner(
                tone: AknTone.info,
                icon: Icons.devices_other_rounded,
                message: ProfileCopy.passwordIntro,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                AknBanner(tone: AknTone.danger, message: _error!),
              ],
              const SizedBox(height: 20),
              AknTextField(
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
              const SizedBox(height: 16),
              AknTextField(
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
              const SizedBox(height: 10),
              _Rule(ok: PasswordRules.length(v), label: ProfileCopy.ruleLength),
              _Rule(ok: PasswordRules.upper(v), label: ProfileCopy.ruleUpper),
              _Rule(ok: PasswordRules.lower(v), label: ProfileCopy.ruleLower),
              _Rule(ok: PasswordRules.digit(v), label: ProfileCopy.ruleDigit),
              const SizedBox(height: 16),
              AknTextField(
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Canlı şifre kuralı satırı (renk tek başına değil: ikon ve "sağlandı" okunur).
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
              duration: AknMotion.of(context, AknMotion.fast),
              child: Icon(
                ok ? Icons.check_circle_rounded : Icons.circle_outlined,
                key: ValueKey(ok),
                size: 18,
                color: ok ? c.ok.fg : c.dim,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: t.bodySmall.copyWith(color: ok ? c.ok.fg : c.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

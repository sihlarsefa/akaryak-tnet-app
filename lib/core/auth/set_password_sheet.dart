import 'package:flutter/material.dart';

import '../network/app_failure.dart';
import '../ui/ui.dart';

/// "Şifre belirle" metinleri (şirket kullanıcıları ve bayi ekibi ortak).
abstract final class SetPasswordCopy {
  static const action = 'Şifre belirle';
  static const actionHint = 'Yeni şifreyi siz verirsiniz; e-posta gerekmez.';
  static const newPassword = 'Yeni şifre';
  static const again = 'Yeni şifre (tekrar)';
  static const rules =
      'En az 8 karakter; büyük harf, küçük harf ve rakam içermeli.';
  static const required = 'Yeni şifreyi girin.';
  static const mismatch = 'Şifreler aynı değil.';
  static const save = 'Şifreyi kaydet';
  static String saved(String name) =>
      '$name için yeni şifre kaydedildi. Şifreyi kendisine iletin.';
}

/// Yöneticinin kullanıcısına şifre belirlemesi (sahip 2026-10-30: kullanıcı adı + şifreyle giriş, e-posta
/// gerekmez): "Yeni şifre" ve "Yeni şifre (tekrar)" (ikisinde de göster / gizle). Uygulama yalnızca boşluğu
/// ve eşleşmeyi denetler; kuralları sunucu uygular. Sunucunun `validation` iletileri
/// (`errors.newPassword`) "Yeni şifre" alanının altında, diğerleri (`forbidden`, `not_found`, bağlantı)
/// formun üstündeki bantta olduğu gibi gösterilir. Kaydedilince sayfa kapanır, başarı bildirimi çıkar ve
/// `true` döner.
Future<bool> showSetPasswordSheet(
  BuildContext context, {
  required String name,
  String? userName,
  required Future<void> Function(String newPassword) save,
}) async {
  final done = await showAppSheet<bool>(
    context: context,
    title: SetPasswordCopy.action,
    subtitle: userName == null || userName.isEmpty ? name : '$name · $userName',
    builder: (_) => SetPasswordForm(name: name, save: save),
  );
  return done ?? false;
}

/// [showSetPasswordSheet] formu.
class SetPasswordForm extends StatefulWidget {
  const SetPasswordForm({super.key, required this.name, required this.save});

  final String name;
  final Future<void> Function(String newPassword) save;

  @override
  State<SetPasswordForm> createState() => _SetPasswordFormState();
}

class _SetPasswordFormState extends State<SetPasswordForm> {
  final _form = GlobalKey<FormState>();
  final _next = TextEditingController();
  final _again = TextEditingController();

  /// Formun üstündeki bant (alanı olmayan sunucu iletisi).
  String? _error;

  /// "Yeni şifre" alanının altındaki sunucu iletisi (`errors.newPassword`); alan değişince silinir.
  String? _nextError;

  @override
  void dispose() {
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  static const _field = 'newPassword';

  Future<void> _save() async {
    setState(() {
      _error = null;
      _nextError = null;
    });
    if (!(_form.currentState?.validate() ?? false)) return;
    try {
      await widget.save(_next.text);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      AppToast.success(SetPasswordCopy.saved(widget.name), context: context);
    } catch (e) {
      final f = AppFailure.from(e);
      if (!mounted) return;
      setState(() {
        if (f is ValidationFailure) {
          _nextError = f.errorsFor(_field);
          _error =
              f.errorsExcept(const [_field]) ??
              (_nextError == null ? f.message : null);
        } else {
          _error = f.message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _form,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AknAnimatedSize(
              alignment: Alignment.topCenter,
              child: _error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: AknBanner(
                          tone: AknTone.danger,
                          message: _error!,
                        ),
                      ),
                    ),
            ),
            AknPasswordField(
              controller: _next,
              label: SetPasswordCopy.newPassword,
              requiredMark: true,
              helper: SetPasswordCopy.rules,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              errorText: _nextError,
              onChanged: (_) {
                if (_nextError != null) setState(() => _nextError = null);
              },
              validator: (v) =>
                  (v ?? '').isEmpty ? SetPasswordCopy.required : null,
            ),
            const SizedBox(height: 12),
            AknPasswordField(
              controller: _again,
              label: SetPasswordCopy.again,
              requiredMark: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              validator: (v) =>
                  (v ?? '') != _next.text ? SetPasswordCopy.mismatch : null,
            ),
            const SizedBox(height: 16),
            AknButton(
              label: SetPasswordCopy.save,
              icon: PhosphorIconsRegular.check,
              expand: true,
              showSuccess: false,
              onPressedAsync: _save,
            ),
          ],
        ),
      ),
    );
  }
}

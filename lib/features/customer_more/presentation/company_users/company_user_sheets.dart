import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/auth/set_password_sheet.dart';
import '../../../../core/models/enums.dart';
import '../../../../core/network/app_failure.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_number.dart';
import '../../../../core/utils/validators.dart';
import '../../application/cm_access.dart';
import '../../application/company_controller.dart';
import '../../copy.dart';
import '../../data/company.dart';
import '../cm_widgets.dart';

/// Eski akışın rolleri (şirket içi onay açıkken).
const _roles = [
  CustomerUserRole.requester,
  CustomerUserRole.approver,
  CustomerUserRole.admin,
];

/// Roller v5: şirket içi onay kapalıysa (tek müşteri rolü) rol seçimi yok; her kullanıcı Yönetici'dir
/// (sunucu da eski rolleri 3'e çevirir).
const _singleRole = CustomerUserRole.admin;

/// Yeni şirket kullanıcısı (sahip 2026-10-30): kullanıcı adı ve şifreyle hemen giriş yapar; e-posta
/// isteğe bağlıdır. Şifre boş, e-posta doluysa eski akış: e-postaya şifre belirleme bağlantısı gider.
Future<void> showAddUserSheet(BuildContext context) => showAppSheet<void>(
  context: context,
  title: 'Kullanıcı ekle',
  subtitle: 'Kullanıcı adı ve şifreyle giriş yapar; e-posta gerekmez.',
  builder: (_) => const _UserForm(),
);

/// Kullanıcı bilgilerini ve rolünü düzenler.
Future<void> showEditUserSheet(BuildContext context, CompanyUser user) =>
    showAppSheet<void>(
      context: context,
      title: 'Kullanıcıyı düzenle',
      subtitle: _who(user),
      builder: (_) => _UserForm(user: user),
    );

/// Sayfa alt başlığındaki kimlik: e-posta, yoksa kullanıcı adı.
String? _who(CompanyUser user) =>
    user.email.isNotEmpty ? user.email : user.userName;

class _UserForm extends ConsumerStatefulWidget {
  const _UserForm({this.user});

  final CompanyUser? user;

  @override
  ConsumerState<_UserForm> createState() => _UserFormState();
}

class _UserFormState extends ConsumerState<_UserForm> {
  late final _name = TextEditingController(
    text: widget.user?.displayName ?? '',
  );
  late final _email = TextEditingController(text: widget.user?.email ?? '');
  late final _userName = TextEditingController(
    text: widget.user?.userName ?? '',
  );
  final _password = TextEditingController();
  late final _phone = TextEditingController(
    text: widget.user?.phoneNumber ?? '',
  );
  late CustomerUserRole _role = widget.user?.role ?? CustomerUserRole.requester;
  final _form = GlobalKey<FormState>();
  String? _error;

  /// Sunucunun alan hataları (400 `validation`: `errors.userName`, `errors.password` …): ilgili alanın
  /// altında gösterilir; alan değişince silinir.
  Map<String, String> _fieldErrors = const {};

  bool get _isNew => widget.user == null;

  bool get _hasUserName => (widget.user?.userName ?? '').isNotEmpty;

  /// Formda görünen alanların sunucu anahtarları (diğer hatalar üstteki bantta).
  List<String> get _shownFields => [
    'displayName',
    if (_isNew || _hasUserName) 'userName',
    if (_isNew) 'password',
    'phoneNumber',
    if (_isNew || _email.text.isNotEmpty) 'email',
  ];

  void _clearError(String field) {
    if (!_fieldErrors.containsKey(field)) return;
    setState(() => _fieldErrors = {..._fieldErrors}..remove(field));
  }

  bool get _self => widget.user?.isSelf ?? false;

  /// Şirket içi onay açık mı (eski akış: rol seçimi var).
  bool get _approvals => ref.read(accessPolicyProvider).companyApprovals;

  /// Gönderilecek rol: onay kapalıyken tek rol.
  CustomerUserRole get _sentRole => _approvals ? _role : _singleRole;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _userName.dispose();
    _password.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _error = null;
      _fieldErrors = const {};
    });
    if (!(_form.currentState?.validate() ?? false)) return;
    final ctrl = ref.read(companyUsersControllerProvider.notifier);
    try {
      if (_isNew) {
        final userName = _userName.text.trim();
        final invite = _password.text.isEmpty;
        final u = await ctrl.add(
          displayName: _name.text,
          userName: userName,
          email: _email.text,
          password: _password.text,
          phone: _phone.text,
          role: _sentRole,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        AppToast.success(
          invite
              ? 'Kullanıcı eklendi; şifre belirleme bağlantısı ${u.email} adresine gönderildi.'
              : 'Kullanıcı eklendi. Kullanıcı adı: ${u.userName ?? userName}. Şifreyi kendisine iletin.',
          context: context,
        );
      } else {
        await ctrl.update(
          widget.user!,
          displayName: _name.text,
          phone: _phone.text,
          role: _sentRole,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        AppToast.success('Kullanıcı güncellendi.', context: context);
      }
    } catch (e) {
      // Hata formda gösterilir (düğme yalnızca bekleme durumunu yönetir): doğrulama hataları alanın
      // altında, alanı olmayanlar ve diğer hatalar üstteki bantta.
      final f = AppFailure.from(e);
      if (!mounted) return;
      setState(() {
        if (f is ValidationFailure) {
          final shown = _shownFields;
          _fieldErrors = {for (final k in shown) k: ?f.errorsFor(k)};
          _error =
              f.errorsExcept(shown) ??
              (_fieldErrors.isEmpty ? failureText(f) : null);
        } else {
          _error = failureText(f);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final approvals = ref.watch(accessPolicyProvider).companyApprovals;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            AknBanner(tone: AknTone.danger, message: _error!),
            const SizedBox(height: 12),
          ],
          AknTextField(
            controller: _name,
            label: 'Ad soyad',
            requiredMark: true,
            maxLength: 150,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            textInputAction: TextInputAction.next,
            errorText: _fieldErrors['displayName'],
            onChanged: (_) => _clearError('displayName'),
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Ad soyad zorunludur.' : null,
          ),
          if (_isNew) ...[
            const SizedBox(height: 12),
            AknTextField(
              controller: _userName,
              label: 'Kullanıcı adı',
              requiredMark: true,
              maxLength: 50,
              // ASCII klavye: kullanıcı adı girişte yazılır (Türkçe karakter yok).
              keyboardType: TextInputType.visiblePassword,
              autofillHints: const [AutofillHints.newUsername],
              textInputAction: TextInputAction.next,
              helper:
                  'Girişte kullanılır: İngilizce harf, rakam, nokta, alt çizgi, tire (3–50 karakter).',
              errorText: _fieldErrors['userName'],
              onChanged: (_) => _clearError('userName'),
              validator: Validators.userName,
            ),
            const SizedBox(height: 12),
            AknPasswordField(
              controller: _password,
              label: 'Şifre',
              autofillHints: const [AutofillHints.newPassword],
              textInputAction: TextInputAction.next,
              errorText: _fieldErrors['password'],
              onChanged: (_) => _clearError('password'),
              helper:
                  '${SetPasswordCopy.rules} Boş bırakırsanız e-postaya şifre belirleme bağlantısı gider.',
              validator: (v) => (v ?? '').isEmpty && _email.text.trim().isEmpty
                  ? 'Şifre belirleyin ya da e-posta girin.'
                  : null,
            ),
          ] else if ((widget.user?.userName ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            AknTextField(
              controller: _userName,
              label: 'Kullanıcı adı',
              enabled: false,
              helper: 'Kullanıcı adı değiştirilemez.',
              errorText: _fieldErrors['userName'],
            ),
          ],
          const SizedBox(height: 12),
          AknTextField(
            controller: _phone,
            label: 'Telefon (isteğe bağlı)',
            maxLength: 20,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            errorText: _fieldErrors['phoneNumber'],
            onChanged: (_) => _clearError('phoneNumber'),
          ),
          if (_isNew || _email.text.isNotEmpty) ...[
            const SizedBox(height: 12),
            AknTextField(
              controller: _email,
              label: _isNew ? 'E-posta (isteğe bağlı)' : 'E-posta',
              enabled: _isNew,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              textInputAction: TextInputAction.done,
              helper: _isNew
                  ? 'Şifre boşsa davet bağlantısı bu adrese gönderilir.'
                  : 'E-posta adresi değiştirilemez.',
              errorText: _fieldErrors['email'],
              onChanged: (_) => _clearError('email'),
              validator: _isNew
                  ? (v) => Validators.email(v, required: false)
                  : null,
            ),
          ],
          if (approvals) ...[
            const SizedBox(height: 16),
            Text('Şirket rolü', style: t.label),
            if (_self)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Kendi rolünüzü değiştiremezsiniz; başka bir yönetici değiştirebilir.',
                  style: t.caption,
                ),
              ),
            const SizedBox(height: 8),
            for (final r in _roles)
              ChoiceCard(
                title: r.label,
                subtitle: companyRoleHint(r),
                leadingIcon: r.statusStyle.icon,
                selected: _role == r,
                enabled: !_self,
                margin: const EdgeInsets.only(bottom: 8),
                onTap: _self ? null : () => setState(() => _role = r),
              ),
          ],
          const SizedBox(height: 8),
          AknButton(
            label: _isNew ? 'Kullanıcıyı ekle' : 'Kaydet',
            icon: _isNew
                ? PhosphorIconsRegular.userPlus
                : PhosphorIconsRegular.check,
            expand: true,
            showSuccess: false,
            onPressedAsync: _save,
          ),
        ],
      ),
    );
  }
}

/// Kullanıcı eylemleri: düzenle, şifre belirle, bağlantıyı yeniden gönder (e-postası varsa), aktif /
/// pasif (onaylı). Roller v5 (şirket içi onay kapalı): rol anılmaz; ana kullanıcıyı yalnızca merkez ya da
/// kendisi pasifleştirir (düğme yok). "Şifre belirle": kullanıcıları yönetebilen herkes; ana kullanıcının
/// şifresini yalnızca kendisi ([CmAccess.cmCanSetPassword]).
Future<void> showUserActionsSheet(
  BuildContext context,
  CompanyUser user, {
  bool companyApprovals = true,
}) => showAppSheet<void>(
  context: context,
  title: user.displayName,
  subtitle: companyApprovals
      ? [user.displayRole, ?_who(user)].join(', ')
      : _who(user),
  builder: (sheet) => Consumer(
    builder: (context, ref, _) {
      final ctrl = ref.read(companyUsersControllerProvider.notifier);
      final policy = ref.watch(accessPolicyProvider);
      final approvals = companyApprovals;
      Future<void> run(Future<String> Function() action) async {
        Navigator.of(sheet).pop();
        try {
          final message = await action();
          if (context.mounted) AppToast.success(message, context: context);
        } catch (e) {
          if (context.mounted) showFailureToast(context, e);
        }
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AknListTile(
            leadingIcon: PhosphorIconsRegular.pencilSimple,
            titleStyle: cmRowTitle(context),
            padding: const EdgeInsets.symmetric(vertical: 10),
            title: approvals
                ? 'Bilgileri ve rolü düzenle'
                : 'Bilgileri düzenle',
            onTap: () {
              Navigator.of(sheet).pop();
              showEditUserSheet(context, user);
            },
          ),
          if (policy.cmCanSetPassword(user))
            AknListTile(
              leadingIcon: PhosphorIconsRegular.password,
              titleStyle: cmRowTitle(context),
              padding: const EdgeInsets.symmetric(vertical: 10),
              title: SetPasswordCopy.action,
              subtitle: SetPasswordCopy.actionHint,
              onTap: () {
                Navigator.of(sheet).pop();
                showSetPasswordSheet(
                  context,
                  name: user.displayName,
                  userName: user.userName,
                  save: (p) => ctrl.setPassword(user, p),
                );
              },
            ),
          if (user.isActive && user.email.isNotEmpty)
            AknListTile(
              leadingIcon: PhosphorIconsRegular.envelopeSimpleOpen,
              titleStyle: cmRowTitle(context),
              padding: const EdgeInsets.symmetric(vertical: 10),
              title: 'Bağlantıyı yeniden gönder',
              subtitle: user.invitationPending
                  ? 'Davet bağlantısı yeniden gönderilir.'
                  : 'Şifre belirleme bağlantısı gönderilir.',
              onTap: () => run(() async {
                await ctrl.sendLink(user);
                return 'Bağlantı ${user.email} adresine gönderildi.';
              }),
            ),
          if (!user.isSelf && !(user.isMainUser && user.isActive && !approvals))
            AknListTile(
              leadingIcon: user.isActive
                  ? PhosphorIconsRegular.userMinus
                  : PhosphorIconsFill.user,
              leadingTone: user.isActive ? AknTone.danger : null,
              titleStyle: cmRowTitle(context),
              padding: const EdgeInsets.symmetric(vertical: 10),
              title: user.isActive ? 'Pasifleştir' : 'Aktifleştir',
              subtitle: user.isActive
                  ? 'Kullanıcı giriş yapamaz; açık oturumları kapanır.'
                  : 'Kullanıcı yeniden giriş yapabilir.',
              onTap: () async {
                Navigator.of(sheet).pop();
                final ok = await showConfirmSheet(
                  context,
                  title: user.isActive
                      ? '${user.displayName} pasifleştirilsin mi?'
                      : '${user.displayName} aktifleştirilsin mi?',
                  message: user.isActive
                      ? 'Kullanıcı uygulamaya ve portala giriş yapamaz. İstediğiniz zaman yeniden aktifleştirebilirsiniz.'
                      : 'Kullanıcı rolündeki yetkilerle yeniden giriş yapabilir.',
                  confirmLabel: user.isActive ? 'Pasifleştir' : 'Aktifleştir',
                  destructive: user.isActive,
                );
                if (!ok) return;
                try {
                  final message = await ctrl.setActive(user, !user.isActive);
                  if (context.mounted) {
                    AppToast.success(message, context: context);
                  }
                } catch (e) {
                  if (context.mounted) showFailureToast(context, e);
                }
              },
            ),
        ],
      );
    },
  ),
);

/// Şirket içi onay eşikleri (litre ≥ 0 — 0 her sipariş; tutar > 0; ikisi de boş = onay kapalı).
Future<void> showThresholdsSheet(
  BuildContext context,
  ApprovalThresholds? current,
) => showAppSheet<void>(
  context: context,
  title: CmCopy.thresholdsTitle,
  builder: (_) => _ThresholdsForm(current: current),
);

class _ThresholdsForm extends ConsumerStatefulWidget {
  const _ThresholdsForm({required this.current});

  final ApprovalThresholds? current;

  @override
  ConsumerState<_ThresholdsForm> createState() => _ThresholdsFormState();
}

class _ThresholdsFormState extends ConsumerState<_ThresholdsForm> {
  late final _litres = TextEditingController();
  late final _amount = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.current;
    if (c?.aboveLitres != null) {
      _litres.text = Fmt.number(c!.aboveLitres, maxFraction: 3);
    }
    if (c?.aboveAmount != null) {
      _amount.text = Fmt.number(c!.aboveAmount, maxFraction: 2);
    }
  }

  @override
  void dispose() {
    _litres.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save({bool off = false}) async {
    final litres = off ? null : TrNumber.parse(_litres.text);
    final amount = off ? null : TrNumber.parse(_amount.text);
    final error = ApprovalThresholds.validate(litres, amount);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    try {
      await ref
          .read(companyUsersControllerProvider.notifier)
          .saveThresholds(aboveLitres: litres, aboveAmount: amount);
      if (!mounted) return;
      Navigator.of(context).pop();
      AppToast.success(
        litres == null && amount == null
            ? 'Şirket içi onay kapatıldı.'
            : 'Onay eşikleri kaydedildi.',
        context: context,
      );
    } catch (e) {
      if (mounted) setState(() => _error = failureText(AppFailure.from(e)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          AknBanner(tone: AknTone.danger, message: _error!),
          const SizedBox(height: 12),
        ],
        LitersField(
          label: 'Litre eşiği',
          controller: _litres,
          min: 0,
          max: ApprovalThresholds.maxLitres,
          helper: CmCopy.thresholdsLitreHint,
        ),
        const SizedBox(height: 12),
        MoneyField(
          label: 'Tahmini tutar eşiği',
          controller: _amount,
          helper: CmCopy.thresholdsAmountHint,
        ),
        const SizedBox(height: 8),
        Text(CmCopy.thresholdsOff, style: t.caption),
        const SizedBox(height: 16),
        AknButton(
          label: 'Kaydet',
          icon: PhosphorIconsRegular.check,
          expand: true,
          showSuccess: false,
          onPressedAsync: _save,
        ),
        if (widget.current?.isConfigured ?? false)
          AknButton.ghost(
            label: 'Onayı kapat',
            expand: true,
            onPressedAsync: () => _save(off: true),
          ),
      ],
    );
  }
}

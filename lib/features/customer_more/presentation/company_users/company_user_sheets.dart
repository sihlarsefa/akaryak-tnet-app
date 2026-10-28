import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/network/app_failure.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_number.dart';
import '../../../../core/utils/validators.dart';
import '../../application/company_controller.dart';
import '../../copy.dart';
import '../../data/company.dart';
import '../cm_widgets.dart';

const _roles = [
  CustomerUserRole.requester,
  CustomerUserRole.approver,
  CustomerUserRole.admin,
];

/// Yeni şirket kullanıcısı (davet e-postası gönderilir).
Future<void> showAddUserSheet(BuildContext context) => showAppSheet<void>(
  context: context,
  title: 'Kullanıcı ekle',
  subtitle: 'Şifre belirleme bağlantısı e-posta adresine gönderilir.',
  builder: (_) => const _UserForm(),
);

/// Kullanıcı bilgilerini ve rolünü düzenler.
Future<void> showEditUserSheet(BuildContext context, CompanyUser user) =>
    showAppSheet<void>(
      context: context,
      title: 'Kullanıcıyı düzenle',
      subtitle: user.email,
      builder: (_) => _UserForm(user: user),
    );

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
  late final _phone = TextEditingController(
    text: widget.user?.phoneNumber ?? '',
  );
  late CustomerUserRole _role = widget.user?.role ?? CustomerUserRole.requester;
  final _form = GlobalKey<FormState>();
  String? _error;

  bool get _isNew => widget.user == null;
  bool get _self => widget.user?.isSelf ?? false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    if (!(_form.currentState?.validate() ?? false)) return;
    final ctrl = ref.read(companyUsersControllerProvider.notifier);
    try {
      if (_isNew) {
        final u = await ctrl.add(
          displayName: _name.text,
          email: _email.text,
          phone: _phone.text,
          role: _role,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        AppToast.success(
          'Kullanıcı eklendi; şifre belirleme bağlantısı ${u.email} adresine gönderildi.',
          context: context,
        );
      } else {
        await ctrl.update(
          widget.user!,
          displayName: _name.text,
          phone: _phone.text,
          role: _role,
        );
        if (!mounted) return;
        Navigator.of(context).pop();
        AppToast.success('Kullanıcı güncellendi.', context: context);
      }
    } catch (e) {
      // Hata formda gösterilir (düğme yalnızca bekleme durumunu yönetir).
      final f = AppFailure.from(e);
      if (mounted) setState(() => _error = failureText(f));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
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
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Ad soyad zorunludur.' : null,
          ),
          const SizedBox(height: 12),
          AknTextField(
            controller: _email,
            label: 'E-posta',
            requiredMark: _isNew,
            enabled: _isNew,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            helper: _isNew
                ? 'Şifre belirleme bağlantısı bu adrese gönderilir.'
                : 'E-posta adresi değiştirilemez.',
            validator: _isNew ? (v) => Validators.email(v) : null,
          ),
          const SizedBox(height: 12),
          AknTextField(
            controller: _phone,
            label: 'Telefon (isteğe bağlı)',
            maxLength: 20,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
          ),
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
          const SizedBox(height: 8),
          AknButton(
            label: _isNew ? 'Ekle ve davet gönder' : 'Kaydet',
            icon: _isNew
                ? PhosphorIconsRegular.paperPlaneRight
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

/// Kullanıcı eylemleri: düzenle, bağlantıyı yeniden gönder, aktif / pasif (onaylı).
Future<void> showUserActionsSheet(
  BuildContext context,
  CompanyUser user,
) => showAppSheet<void>(
  context: context,
  title: user.displayName,
  subtitle: '${user.displayRole}, ${user.email}',
  builder: (sheet) => Consumer(
    builder: (context, ref, _) {
      final ctrl = ref.read(companyUsersControllerProvider.notifier);
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
            leading: const CmIconTile(icon: PhosphorIconsRegular.pencilSimple),
            titleStyle: cmRowTitle(context),
            padding: const EdgeInsets.symmetric(vertical: 10),
            title: 'Bilgileri ve rolü düzenle',
            onTap: () {
              Navigator.of(sheet).pop();
              showEditUserSheet(context, user);
            },
          ),
          if (user.isActive)
            AknListTile(
              leading: const CmIconTile(
                icon: PhosphorIconsRegular.envelopeSimpleOpen,
              ),
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
          if (!user.isSelf)
            AknListTile(
              leading: CmIconTile(
                icon: user.isActive
                    ? PhosphorIconsRegular.userMinus
                    : PhosphorIconsFill.user,
                tone: user.isActive ? AknTone.danger : AknTone.ok,
              ),
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

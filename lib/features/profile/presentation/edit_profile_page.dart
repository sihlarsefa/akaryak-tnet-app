import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/validators.dart';
import '../copy.dart';
import '../data/profile_models.dart';
import '../data/profile_repository.dart';
import 'widgets/settings_widgets.dart';

final userProfileProvider = FutureProvider.autoDispose<UserProfile>(
  (ref) => ref.watch(profileRepositoryProvider).profile(),
);

/// Profil bilgileri (spec A.4 A8 `me/profile`; tasarım v3): ad soyad ve cep telefonu, altında
/// değiştirilemeyen bilgiler (e-posta, rol, bağlı olduğu yer) simge karolu beyaz kartta; bölümler sırayla
/// belirir. Telefon değişirse uyarı ve mevcut şifre alanı yumuşakça açılır; kayıttan sonra sunucu tüm
/// oturumları kapatır ("Güvenlik bilgileriniz değişti").
class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  UserProfile? _loaded;
  bool _showPassword = false;
  String? _error;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    _name.addListener(_changed);
    _phone.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  void _fill(UserProfile p) {
    if (_loaded != null) return;
    _loaded = p;
    _name.text = p.displayName;
    _phone.text = p.phoneNumber == null ? '' : Fmt.phone(p.phoneNumber);
  }

  static String _digits(String? v) {
    final n = Validators.normalizePhone(v);
    return n ?? Validators.digitsOnly(v);
  }

  bool get _phoneChanged =>
      _loaded != null && _digits(_phone.text) != _digits(_loaded!.phoneNumber);

  bool get _dirty =>
      _loaded != null &&
      (_name.text.trim() != _loaded!.displayName || _phoneChanged);

  Future<void> _save() async {
    setState(() {
      _error = null;
      _passwordError = null;
    });
    if (!(_form.currentState?.validate() ?? false)) {
      AknHaptics.warning();
      return;
    }
    if (!_dirty) {
      unawaited(Navigator.of(context).maybePop());
      return;
    }
    final phoneChanged = _phoneChanged;
    final phone = _phone.text.trim().isEmpty
        ? null
        : Fmt.phone(_phone.text.trim());
    try {
      await ref
          .read(profileRepositoryProvider)
          .updateProfile(
            displayName: _name.text.trim(),
            phoneNumber: phone,
            currentPassword: phoneChanged ? _password.text : null,
          );
    } on AppFailure catch (f) {
      if (!mounted) return;
      AknHaptics.warning();
      setState(() {
        if (phoneChanged && f.message.contains('şifre')) {
          _passwordError = f.message;
          _password.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _password.text.length,
          );
        } else {
          _error = f.message;
        }
      });
      return;
    }
    if (!mounted) return;
    AppToast.success(ProfileCopy.saved);
    final session = ref.read(sessionControllerProvider.notifier);
    if (phoneChanged) {
      // Sunucu güvenlik damgasını yeniledi: bu oturum da kapandı.
      await session.signOut(
        message: ProfileCopy.securityChanged,
        reason: SignOutReason.securityChanged,
      );
      return;
    }
    _loaded = null;
    ref.invalidate(userProfileProvider);
    unawaited(session.refreshAccess(force: true));
    if (mounted) unawaited(Navigator.of(context).maybePop());
  }

  Future<bool> _confirmLeave() => showConfirmSheet(
    context,
    title: ProfileCopy.leaveTitle,
    message: ProfileCopy.leaveMessage,
    confirmLabel: ProfileCopy.leave,
    cancelLabel: ProfileCopy.stay,
    tone: AknTone.warn,
    icon: PhosphorIconsRegular.notePencil,
  );

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(userProfileProvider);
    final p = async.valueOrNull;
    if (p != null) _fill(p);
    final loaded = _loaded;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmLeave();
        if (leave && context.mounted) {
          _loaded = null;
          Navigator.of(context).pop();
        }
      },
      child: AppScaffold(
        title: ProfileCopy.editTitle,
        showBell: false,
        actionBar: loaded == null
            ? null
            : barOf(
                AknButton(
                  label: ProfileCopy.save,
                  expand: true,
                  showSuccess: false,
                  onPressedAsync: _save,
                ),
              ),
        body: loaded == null
            ? async.hasError
                  ? Center(
                      child: SingleChildScrollView(
                        child: ErrorState(
                          title: ProfileCopy.profileLoadFailed,
                          offline: async.error is OfflineFailure,
                          message: async.error is AppFailure
                              ? (async.error! as AppFailure).message
                              : null,
                          onRetry: () => ref.invalidate(userProfileProvider),
                        ),
                      ),
                    )
                  : const SkeletonList(itemCount: 3, lines: 2, leading: false)
            : Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AknSpace.page,
                    16,
                    AknSpace.page,
                    32,
                  ),
                  children: [
                    // Hata bandı yerinde açılır (yapı sabit: alanlar yeniden kurulmaz).
                    AknAnimatedSize(
                      duration: AknMotion.slow,
                      curve: AknMotion.emphasizedCurve,
                      alignment: Alignment.topCenter,
                      child: _error == null
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: AknBanner(
                                tone: AknTone.danger,
                                message: _error!,
                              ),
                            ),
                    ),
                    SettingsReveal(
                      index: 0,
                      child: AknTextField(
                        controller: _name,
                        label: ProfileCopy.fullName,
                        requiredMark: true,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.name],
                        maxLength: 150,
                        validator: (v) {
                          final s = v?.trim() ?? '';
                          if (s.isEmpty) return ProfileCopy.fullNameRequired;
                          if (s.length > 150) {
                            return ProfileCopy.fullNameTooLong;
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    SettingsReveal(
                      index: 1,
                      child: AknTextField(
                        controller: _phone,
                        label: ProfileCopy.mobilePhone,
                        hint: '05XX XXX XX XX',
                        helper: ProfileCopy.mobilePhoneHelper,
                        keyboardType: TextInputType.phone,
                        autofillHints: const [AutofillHints.telephoneNumber],
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9 +()-]'),
                          ),
                          LengthLimitingTextInputFormatter(20),
                        ],
                        validator: (v) =>
                            Validators.mobilePhone(v, required: false),
                      ),
                    ),
                    AknAnimatedSize(
                      duration: AknMotion.slow,
                      curve: AknMotion.emphasizedCurve,
                      alignment: Alignment.topCenter,
                      child: !_phoneChanged
                          ? const SizedBox(width: double.infinity)
                          : Padding(
                              padding: const EdgeInsets.only(top: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const AknBanner(
                                    tone: AknTone.warn,
                                    icon: PhosphorIconsRegular.lockKey,
                                    message: ProfileCopy.phoneChangeNote,
                                  ),
                                  const SizedBox(height: 16),
                                  AknTextField(
                                    controller: _password,
                                    label: ProfileCopy.currentPassword,
                                    requiredMark: true,
                                    obscureText: !_showPassword,
                                    errorText: _passwordError,
                                    onChanged: (_) {
                                      if (_passwordError != null) {
                                        setState(() => _passwordError = null);
                                      }
                                    },
                                    autofillHints: const [
                                      AutofillHints.password,
                                    ],
                                    suffixIcon: IconButton(
                                      tooltip: _showPassword
                                          ? ProfileCopy.hidePassword
                                          : ProfileCopy.showPassword,
                                      onPressed: () => setState(
                                        () => _showPassword = !_showPassword,
                                      ),
                                      icon: Icon(
                                        _showPassword
                                            ? PhosphorIconsRegular.eyeSlash
                                            : PhosphorIconsRegular.eye,
                                      ),
                                    ),
                                    validator: (v) =>
                                        _phoneChanged &&
                                            (v == null || v.isEmpty)
                                        ? ProfileCopy.currentPasswordRequired
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(height: 24),
                    // v3: değiştirilemeyen bilgiler simge karolu satırlarla beyaz kartta.
                    SettingsReveal(
                      index: 2,
                      child: AknCard(
                        radius: 20,
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SettingsFactLine(
                              icon: PhosphorIconsRegular.envelopeSimple,
                              label: ProfileCopy.email,
                              value: Fmt.orDash(loaded.email),
                            ),
                            if (loaded.roleLabel != null)
                              SettingsFactLine(
                                icon: PhosphorIconsRegular.identificationBadge,
                                label: ProfileCopy.role,
                                value: loaded.roleLabel!,
                              ),
                            if (loaded.organizationTitle != null)
                              SettingsFactLine(
                                icon: PhosphorIconsRegular.buildingOffice,
                                label: ProfileCopy.organization,
                                value: loaded.organizationTitle!,
                              ),
                            const SizedBox(height: 6),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: context.akn.lineSoft,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ExcludeSemantics(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 1),
                                    child: Icon(
                                      PhosphorIconsRegular.info,
                                      size: 16,
                                      color: context.akn.dim,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    ProfileCopy.emailHint,
                                    style: context.aknText.caption.copyWith(
                                      color: context.akn.dim,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

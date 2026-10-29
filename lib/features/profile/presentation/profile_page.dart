import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/lock_settings.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/env/app_config_controller.dart';
import '../../../core/env/app_env.dart';
import '../../../core/env/app_info.dart';
import '../../../core/models/me_access.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/outbox_providers.dart';
import '../../../core/offline/pending_ops_chip.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/storage/prefs_store.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/log.dart';
import '../../assistant/api.dart';
import '../../auth/api.dart';
import '../../notifications/api.dart';
import '../application/config_extras.dart';
import '../application/links.dart';
import '../application/logout_flow.dart';
import '../copy.dart';
import '../profile_paths.dart';
import 'support_sheet.dart';
import 'widgets/settings_widgets.dart';

/// Profil ve ayarlar (spec A.4 A8; tasarım v3): sıcak "üye kartı" baş (halkalı avatar, ad, rol, e-posta ve
/// telefon), simge karolu beyaz grup kartları — güvenlik (biyometrik kilit, şifre, profil, telefonla
/// giriş, aktif oturumlar), bildirim tercihleri, tema, destek, yasal metinler, gizlilik (asistan onayı),
/// bekleyen işlemler, hakkında — çıkış ve hesabımı sil. Bölümler açılışta sırayla belirir.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(sessionControllerProvider).access;
    final features = ref.watch(appConfigProvider.select((c) => c.features));
    final env = ref.watch(appEnvProvider);
    final assistantOn = ref.watch(assistantEnabledProvider);
    final legal = ref.watch(legalUrisProvider);
    final isPlatform = access?.persona == Persona.platform;
    final gate = features.assistant ? ref.watch(assistantGateProvider) : null;
    final showConsent =
        gate != null && gate is! GateDisabled && gate is! GateError;

    Future<void> open(Uri uri) async {
      final ok = await ref.read(profileLinkOpenerProvider)(uri);
      if (!ok) AppToast.error(ProfileCopy.linkFailed);
    }

    var order = 0;
    // Bölümler sırayla belirir (tasarım v3 §5). Tümü bir kez kurulur (tembel liste değil): kaydırınca
    // yeni bölüm doğmaz, açılıştaki sıralı giriş bir kez oynar.
    Widget reveal(Widget child) => SettingsReveal(index: order++, child: child);

    // v4 §3.2: sekme kökünde (şoför, merkez) bant — sekmenin simgesi ve adı, tek durum satırı; Diğer'den
    // itildiğinde bar "Profil" der (durum satırı yalnızca bantta).
    return AppScaffold(
      title: ProfileCopy.title,
      bandIcon: PhosphorIconsRegular.user,
      status: ProfileCopy.bandStatus,
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          top: 4,
          bottom: 32 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (access != null) reveal(_ProfileHeader(access: access)),
            const PendingOpsChip(
              margin: EdgeInsets.fromLTRB(AknSpace.page, 12, AknSpace.page, 0),
            ),

            // ---------------------------------------------------------- Güvenlik
            reveal(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SettingsHeader(ProfileCopy.security),
                  SettingsGroup(
                    children: [
                      const _BiometricTile(),
                      SettingsTile(
                        icon: PhosphorIconsRegular.password,
                        title: ProfileCopy.passwordSave,
                        subtitle: ProfileCopy.changePasswordHint,
                        onTap: () => context.push(ProfilePaths.password),
                      ),
                      SettingsTile(
                        icon: PhosphorIconsRegular.user,
                        title: ProfileCopy.editTitle,
                        subtitle: ProfileCopy.editProfile,
                        onTap: () => context.push(ProfilePaths.edit),
                      ),
                      if (features.otpLogin && !isPlatform)
                        const _PhoneLoginTile(),
                      SettingsTile(
                        icon: PhosphorIconsRegular.devices,
                        title: ProfileCopy.sessions,
                        subtitle: ProfileCopy.sessionsHint,
                        onTap: () => context.push(ProfilePaths.sessions),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ---------------------------------------------------------- Bildirimler
            reveal(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SettingsHeader(ProfileCopy.notifications),
                  SettingsGroup(
                    children: [
                      SettingsTile(
                        icon: PhosphorIconsRegular.bellRinging,
                        title: ProfileCopy.notificationPrefs,
                        subtitle: ProfileCopy.notificationPrefsHint,
                        onTap: () => context.push(NotificationsPaths.settings),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ---------------------------------------------------------- Görünüm
            reveal(
              const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingsHeader(ProfileCopy.appearance),
                  _ThemePicker(),
                ],
              ),
            ),

            // ---------------------------------------------------------- Destek
            reveal(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SettingsHeader(ProfileCopy.support),
                  SettingsGroup(
                    children: [
                      SettingsTile(
                        icon: PhosphorIconsRegular.headset,
                        title: ProfileCopy.supportTitle,
                        subtitle: ProfileCopy.supportSubtitle,
                        onTap: () => unawaited(showSupportSheet(context)),
                      ),
                      if (assistantOn)
                        SettingsTile(
                          icon: PhosphorIconsRegular.chatCircle,
                          title: ProfileCopy.askAssistant,
                          subtitle: ProfileCopy.askAssistantHint,
                          onTap: () => context.push(AppRoutes.assistant),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // ---------------------------------------------------------- Yasal
            reveal(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SettingsHeader(ProfileCopy.legal),
                  SettingsGroup(
                    children: [
                      SettingsTile(
                        icon: PhosphorIconsRegular.fileLock,
                        title: ProfileCopy.privacyPolicy,
                        external: true,
                        onTap: () => unawaited(open(legal.privacy)),
                      ),
                      SettingsTile(
                        icon: PhosphorIconsRegular.shieldCheck,
                        title: ProfileCopy.kvkk,
                        external: true,
                        onTap: () => unawaited(open(legal.kvkk)),
                      ),
                      SettingsTile(
                        icon: PhosphorIconsRegular.gavel,
                        title: ProfileCopy.terms,
                        external: true,
                        onTap: () => unawaited(open(legal.terms)),
                      ),
                      SettingsTile(
                        icon: PhosphorIconsRegular.sparkle,
                        title: ProfileCopy.aiDisclosure,
                        external: true,
                        onTap: () => unawaited(open(legal.ai)),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ---------------------------------------------------------- Gizlilik
            reveal(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SettingsHeader(ProfileCopy.privacy),
                  SettingsGroup(
                    children: [
                      if (showConsent) _AssistantConsentTile(gate: gate),
                      SettingsTile(
                        icon: PhosphorIconsRegular.gearSix,
                        title: ProfileCopy.permissions,
                        subtitle: ProfileCopy.permissionsHint,
                        external: true,
                        onTap: () => unawaited(_openAppSettings()),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ---------------------------------------------------------- Uygulama
            reveal(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SettingsHeader(ProfileCopy.app),
                  SettingsGroup(
                    children: [
                      const _PendingOpsTile(),
                      const _AboutTile(),
                      if (env.isFake || env.isDev)
                        SettingsTile(
                          icon: PhosphorIconsRegular.code,
                          title: ProfileCopy.devMenu,
                          subtitle: ProfileCopy.devMenuHint,
                          onTap: () => context.push(AppRoutes.dev),
                        ),
                    ],
                  ),
                ],
              ),
            ),

            // ---------------------------------------------------------- Çıkış
            reveal(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AknSpace.page,
                      32,
                      AknSpace.page,
                      0,
                    ),
                    child: AknButton.danger(
                      label: ProfileCopy.signOut,
                      icon: PhosphorIconsRegular.signOut,
                      expand: true,
                      onPressed: () =>
                          unawaited(confirmAndSignOut(context, ref)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SettingsGroup(
                    children: [
                      SettingsTile(
                        icon: PhosphorIconsRegular.userMinus,
                        title: ProfileCopy.deleteAccount,
                        destructive: true,
                        onTap: () => context.push(ProfilePaths.deleteAccount),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> _openAppSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (e) {
      AppLog.debug('Uygulama ayarları açılamadı: $e');
    }
  }
}

/// Profil başı (tasarım v3): sıcak "üye kartı" — kahraman kartın dilinde beyaz kart (üstte sıcak
/// `plateTint` ışığı, r26, sıcak gölge); solda turuncu degrade halkalı 64 px avatar (açılışta "pop"),
/// yanında ad (`title` 22/28 800), rol ve çalıştığı yer; sağ üstte 44 px yuvarlak "Düzenle". İnce çizginin
/// altında e-posta ve telefon, simge karolarıyla.
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.access});

  final MeAccess access;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final roles = <String>[
      ...access.bayiRoleNames,
      if (access.persona == Persona.customer) access.customerUserRole.label,
      if (access.persona == Persona.platform) Persona.platform.label,
    ];
    final second = [
      if (roles.isNotEmpty) roles.join(', '),
      ?access.organizationTitle,
    ].join(', ');
    final facts = <(IconData, String, String)>[
      if (access.email != null)
        (PhosphorIconsRegular.envelopeSimple, ProfileCopy.email, access.email!),
      if (access.phoneMasked != null)
        (
          PhosphorIconsRegular.deviceMobile,
          ProfileCopy.mobilePhone,
          access.phoneMasked!,
        ),
    ];
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final names = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(
            access.displayName,
            style: t.title.copyWith(
              fontSize: 22,
              height: 28 / 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: c.ink,
            ),
            textScaler: MediaQuery.textScalerOf(
              context,
            ).clamp(maxScaleFactor: 1.6),
          ),
        ),
        if (second.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(second, style: t.bodySmall.copyWith(color: c.dim)),
        ],
      ],
    );
    final edit = _EditButton(onPressed: () => context.push(ProfilePaths.edit));
    final avatar = _RingAvatar(name: access.displayName);
    // v4 §4: plaka yalnızca ana sayfaların kahramanıdır; burada beyaz kart (r20, ince gölge; koyu
    // temada 1 px çizgi) — gece renkli bir levha yok.
    return Padding(
      padding: const EdgeInsets.fromLTRB(AknSpace.page, 8, AknSpace.page, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: AknRadius.card,
          border: c.isDark ? Border.all(color: c.line) : null,
          boxShadow: c.isDark ? null : AknShadows.card(c),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Büyük yazıda ad avatarın altına iner (tam genişlik).
              if (large) ...[
                Row(children: [avatar, const Spacer(), edit]),
                const SizedBox(height: 12),
                names,
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    avatar,
                    const SizedBox(width: 14),
                    Expanded(child: names),
                    const SizedBox(width: 8),
                    edit,
                  ],
                ),
              if (facts.isNotEmpty) ...[
                const SizedBox(height: 16),
                Divider(height: 1, thickness: 1, color: c.lineSoft),
                for (final (icon, label, value) in facts)
                  // v4 P5: turuncu yalnızca eylem ve "buradasınız" içindir; bilgi karoları nötr.
                  SettingsFactLine(icon: icon, label: label, value: value),
              ] else
                const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Turuncu degrade halkalı avatar (64 px): halka ile avatar arasında kart renginde ince boşluk; açılışta
/// küçükten büyüyerek ve hafifçe taşarak yerine oturur, halkanın ışığı çok yavaş döner.
class _RingAvatar extends StatelessWidget {
  const _RingAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: AknMotion.reduced(context) ? 1 : 0.6, end: 1),
      duration: AknMotion.of(context, const Duration(milliseconds: 560)),
      curve: AknMotion.pop,
      builder: (context, v, child) => Transform.scale(scale: v, child: child),
      // Halkanın ışığı çok yavaş döner (ortam hareketi; testlerde ve azaltılmış harekette durur).
      child: RepaintBoundary(
        child: AknAmbient(
          period: const Duration(seconds: 14),
          curve: Curves.linear,
          builder: (context, t, child) => DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: SweepGradient(
                colors: [c.heroStart, c.brand, c.heroEnd, c.heroStart],
                transform: GradientRotation(2 * math.pi * t),
              ),
            ),
            child: child,
          ),
          child: SizedBox.square(
            dimension: 66,
            child: Padding(
              padding: const EdgeInsets.all(2.5),
              child: Container(
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.surface,
                ),
                child: AknAvatar(name: name, size: 56),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Düzenle": 44 px yuvarlak, kart renginde, ince çizgili kalem düğmesi (48 dp hedef); basınca içe çöker.
class _EditButton extends StatelessWidget {
  const _EditButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return Tooltip(
      message: ProfileCopy.editProfile,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: ProfileCopy.editProfile,
        excludeSemantics: true,
        onTap: onPressed,
        child: PressScale(
          scale: 0.92,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              AknHaptics.selection();
              onPressed();
            },
            child: SizedBox.square(
              dimension: AknSpace.minTap,
              child: Center(
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.line),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    PhosphorIconsRegular.pencilSimple,
                    size: 20,
                    color: c.ink,
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

/// Biyometrik kilit anahtarı (A1'in cihaz uygunluğu ve doğrulaması; tercih çekirdekte).
class _BiometricTile extends ConsumerWidget {
  const _BiometricTile();

  Future<void> _toggle(WidgetRef ref, bool enable) async {
    final lock = ref.read(biometricLockProvider.notifier);
    if (!enable) {
      await lock.set(false);
      return;
    }
    final outcome = await ref
        .read(biometricAuthenticatorProvider)
        .authenticate(ProfileCopy.biometricReason);
    if (outcome == BiometricOutcome.success) {
      await lock.set(true);
      AppToast.success(ProfileCopy.biometricOn);
    } else if (outcome != BiometricOutcome.cancelled) {
      AppToast.warning(ProfileCopy.biometricFailed);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final support = ref.watch(biometricSupportProvider).valueOrNull;
    final on = ref.watch(biometricLockProvider);
    final available = support?.available ?? false;
    final method = biometricMethodName(support?.kind);
    return SettingsSwitchTile(
      icon: biometricIcon(support?.kind),
      title: ProfileCopy.biometricTitle(
        available ? method : ProfileCopy.biometricGeneric,
      ),
      subtitle: support == null
          ? null
          : available
          ? ProfileCopy.biometricHint
          : ProfileCopy.biometricUnavailable,
      value: on && available,
      onChanged: available ? (v) => unawaited(_toggle(ref, v)) : null,
    );
  }
}

/// "Telefonla giriş" (A1 `/profile/phone`): doğrulama durumu çipi.
class _PhoneLoginTile extends ConsumerWidget {
  const _PhoneLoginTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(phoneStatusProvider).valueOrNull;
    final verified = status?.verified ?? false;
    return SettingsTile(
      icon: PhosphorIconsRegular.deviceMobile,
      title: verified ? ProfileCopy.phoneLogin : ProfileCopy.phoneLoginEnable,
      subtitle: status == null
          ? null
          : !status.hasPhone
          ? ProfileCopy.phoneMissing
          : verified
          ? ProfileCopy.phoneVerified
          : ProfileCopy.phoneNotVerified,
      trailing: status == null
          ? null
          : AknLamp(
              label: verified ? ProfileCopy.phoneOn : ProfileCopy.phoneOff,
              tone: verified ? AknTone.ok : AknTone.neutral,
              size: AknLampSize.small,
            ),
      onTap: () async {
        await context.push(AuthRoutes.phone);
        if (context.mounted) ref.invalidate(phoneStatusProvider);
      },
    );
  }
}

/// Görünüm: Sistem / Açık / Koyu (çekirdek `themeModeProvider`), bölmeli seçici (§6.11, §7.17).
class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AknSpace.page),
      child: Semantics(
        container: true,
        label: ProfileCopy.theme,
        child: AknSegmented<ThemeMode>(
          segments: const [
            FilterOption(
              value: ThemeMode.system,
              label: ProfileCopy.themeSystem,
            ),
            FilterOption(value: ThemeMode.light, label: ProfileCopy.themeLight),
            FilterOption(value: ThemeMode.dark, label: ProfileCopy.themeDark),
          ],
          value: mode,
          onChanged: (m) =>
              unawaited(ref.read(themeModeProvider.notifier).set(m)),
        ),
      ),
    );
  }
}

/// Profil > Gizlilik: asistan onayının durumu ve "Onayı geri al".
class _AssistantConsentTile extends ConsumerWidget {
  const _AssistantConsentTile({required this.gate});

  final AssistantGate gate;

  Future<void> _withdraw(BuildContext context, WidgetRef ref) async {
    final ok = await showConfirmSheet(
      context,
      title: ProfileCopy.withdrawTitle,
      message: ProfileCopy.withdrawMessage,
      confirmLabel: ProfileCopy.withdraw,
      cancelLabel: ProfileCopy.cancel,
      icon: PhosphorIconsRegular.shieldWarning,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final consent = ref.read(assistantGateProvider.notifier);
    try {
      await consent.withdraw();
      AppToast.success(ProfileCopy.withdrawDone);
    } on AppFailure catch (f) {
      AppToast.error(
        f is OfflineFailure || f is TimeoutFailure
            ? f.message
            : ProfileCopy.withdrawFailed,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(assistantEnabledProvider);
    return switch (gate) {
      GateReady(:final acceptedAt) => SettingsTile(
        icon: PhosphorIconsRegular.chatCircle,
        title: ProfileCopy.assistantConsent,
        subtitle: ProfileCopy.consentGiven(
          acceptedAt == null ? null : Fmt.date(acceptedAt),
        ),
        trailing: AknButton.ghost(
          label: ProfileCopy.withdraw,
          size: AknButtonSize.small,
          onPressed: () => unawaited(_withdraw(context, ref)),
        ),
      ),
      GateNeedsConsent() => SettingsTile(
        icon: PhosphorIconsRegular.chatCircle,
        title: ProfileCopy.assistantConsent,
        subtitle: ProfileCopy.consentNotGiven,
        onTap: enabled ? () => context.push(AppRoutes.assistant) : null,
      ),
      GateChecking() => const SettingsTile(
        icon: PhosphorIconsRegular.chatCircle,
        title: ProfileCopy.assistantConsent,
        subtitle: ProfileCopy.consentChecking,
      ),
      GateDisabled() || GateError() => const SizedBox.shrink(),
    };
  }
}

class _PendingOpsTile extends ConsumerWidget {
  const _PendingOpsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingOpsCountProvider);
    final attention = ref.watch(attentionOpsCountProvider);
    return SettingsTile(
      icon: PhosphorIconsRegular.cloudArrowUp,
      tone: attention > 0
          ? AknTone.danger
          : pending > 0
          ? AknTone.warn
          : null,
      title: ProfileCopy.pendingOps,
      subtitle: pending + attention == 0
          ? ProfileCopy.pendingNone
          : ProfileCopy.pendingCount(pending + attention),
      onTap: () => unawaited(showPendingOpsSheet(context)),
    );
  }
}

class _AboutTile extends ConsumerWidget {
  const _AboutTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final env = ref.watch(appEnvProvider);
    final info = ref.watch(appInfoProvider);
    final extras = ref.watch(configExtrasProvider).valueOrNull;
    final server = [?extras?.contractVersion, ?extras?.apiBuild].join(', ');
    return SettingsTile(
      icon: PhosphorIconsRegular.info,
      title: ProfileCopy.about,
      subtitle: [
        ProfileCopy.version(
          info.versionLabel,
          env.badge.replaceAll(' · ', ', '),
        ),
        if (server.isNotEmpty) ProfileCopy.server(server),
      ].join('\n'),
    );
  }
}

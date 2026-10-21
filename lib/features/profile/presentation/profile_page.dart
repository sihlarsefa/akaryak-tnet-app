import 'dart:async';

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

/// Profil ve ayarlar (spec A.4 A8): kullanıcı kartı + roller, güvenlik (biyometrik kilit, şifre,
/// profil, telefonla giriş, aktif oturumlar), bildirim tercihleri, tema, destek, yasal metinler,
/// gizlilik (asistan onayı), bekleyen işlemler, hakkında, çıkış ve hesabımı sil.
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

    return AppScaffold(
      title: ProfileCopy.title,
      body: ListView(
        padding: EdgeInsets.only(
          bottom: 32 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          if (access != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _UserCard(access: access),
            ),
          const PendingOpsChip(margin: EdgeInsets.fromLTRB(16, 12, 16, 0)),

          // ---------------------------------------------------------- Güvenlik
          const SettingsHeader(ProfileCopy.security),
          SettingsGroup(
            children: [
              const _BiometricTile(),
              SettingsTile(
                icon: Icons.password_rounded,
                title: ProfileCopy.changePassword,
                subtitle: ProfileCopy.changePasswordHint,
                onTap: () => context.push(ProfilePaths.password),
              ),
              SettingsTile(
                icon: Icons.badge_outlined,
                title: ProfileCopy.editTitle,
                subtitle: ProfileCopy.editProfile,
                onTap: () => context.push(ProfilePaths.edit),
              ),
              if (features.otpLogin && !isPlatform) const _PhoneLoginTile(),
              SettingsTile(
                icon: Icons.devices_rounded,
                title: ProfileCopy.sessions,
                subtitle: ProfileCopy.sessionsHint,
                onTap: () => context.push(ProfilePaths.sessions),
              ),
            ],
          ),

          // ---------------------------------------------------------- Bildirimler
          const SettingsHeader(ProfileCopy.notifications),
          SettingsGroup(
            children: [
              SettingsTile(
                icon: Icons.notifications_active_outlined,
                title: ProfileCopy.notificationPrefs,
                subtitle: ProfileCopy.notificationPrefsHint,
                onTap: () => context.push(NotificationsPaths.settings),
              ),
            ],
          ),

          // ---------------------------------------------------------- Görünüm
          const SettingsHeader(ProfileCopy.appearance),
          const _ThemePicker(),

          // ---------------------------------------------------------- Destek
          const SettingsHeader(ProfileCopy.support),
          SettingsGroup(
            children: [
              SettingsTile(
                icon: Icons.support_agent_rounded,
                title: ProfileCopy.supportTitle,
                subtitle: ProfileCopy.supportSubtitle,
                onTap: () => unawaited(showSupportSheet(context)),
              ),
              if (assistantOn)
                SettingsTile(
                  icon: Icons.forum_outlined,
                  title: ProfileCopy.askAssistant,
                  subtitle: ProfileCopy.askAssistantHint,
                  onTap: () => context.push(AppRoutes.assistant),
                ),
            ],
          ),

          // ---------------------------------------------------------- Yasal
          const SettingsHeader(ProfileCopy.legal),
          SettingsGroup(
            children: [
              SettingsTile(
                icon: Icons.policy_outlined,
                title: ProfileCopy.privacyPolicy,
                external: true,
                onTap: () => unawaited(open(legal.privacy)),
              ),
              SettingsTile(
                icon: Icons.verified_user_outlined,
                title: ProfileCopy.kvkk,
                external: true,
                onTap: () => unawaited(open(legal.kvkk)),
              ),
              SettingsTile(
                icon: Icons.gavel_rounded,
                title: ProfileCopy.terms,
                external: true,
                onTap: () => unawaited(open(legal.terms)),
              ),
              SettingsTile(
                icon: Icons.auto_awesome_outlined,
                title: ProfileCopy.aiDisclosure,
                external: true,
                onTap: () => unawaited(open(legal.ai)),
              ),
            ],
          ),

          // ---------------------------------------------------------- Gizlilik
          const SettingsHeader(ProfileCopy.privacy),
          SettingsGroup(
            children: [
              if (showConsent) _AssistantConsentTile(gate: gate),
              SettingsTile(
                icon: Icons.app_settings_alt_outlined,
                title: ProfileCopy.permissions,
                subtitle: ProfileCopy.permissionsHint,
                external: true,
                onTap: () => unawaited(_openAppSettings()),
              ),
            ],
          ),

          // ---------------------------------------------------------- Uygulama
          const SettingsHeader(ProfileCopy.app),
          SettingsGroup(
            children: [
              const _PendingOpsTile(),
              const _AboutTile(),
              if (env.isFake || env.isDev)
                SettingsTile(
                  icon: Icons.developer_mode_rounded,
                  title: ProfileCopy.devMenu,
                  subtitle: ProfileCopy.devMenuHint,
                  onTap: () => context.push(AppRoutes.dev),
                ),
            ],
          ),

          // ---------------------------------------------------------- Çıkış
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
            child: AknButton.secondary(
              label: ProfileCopy.signOut,
              icon: Icons.logout_rounded,
              expand: true,
              onPressed: () => unawaited(confirmAndSignOut(context, ref)),
            ),
          ),
          const SizedBox(height: 12),
          SettingsGroup(
            children: [
              SettingsTile(
                icon: Icons.person_remove_outlined,
                title: ProfileCopy.deleteAccount,
                destructive: true,
                onTap: () => context.push(ProfilePaths.deleteAccount),
              ),
            ],
          ),
        ],
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

/// Kullanıcı kartı: avatar, ad, çalıştığı yer, e-posta / telefon, rol çipleri, düzenle.
class _UserCard extends StatelessWidget {
  const _UserCard({required this.access});

  final MeAccess access;

  @override
  Widget build(BuildContext context) {
    final roles = <String>[
      ...access.bayiRoleNames,
      if (access.persona == Persona.customer) access.customerUserRole.label,
      if (access.persona == Persona.platform) Persona.platform.label,
    ];
    return AknHeroPanel(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
      child: Builder(
        builder: (context) {
          final t = context.aknText;
          final c = context.akn;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AknAvatar(name: access.displayName, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(access.displayName, style: t.headline),
                    ),
                    if (access.organizationTitle != null) ...[
                      const SizedBox(height: 2),
                      Text(access.organizationTitle!, style: t.bodySmall),
                    ],
                    if (access.email != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        access.email!,
                        style: t.caption.copyWith(color: c.dim),
                      ),
                    ],
                    if (access.phoneMasked != null)
                      Text(
                        access.phoneMasked!,
                        style: t.caption.copyWith(color: c.dim),
                      ),
                    if (roles.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [for (final r in roles) _RoleChip(label: r)],
                      ),
                    ],
                  ],
                ),
              ),
              AknIconButton(
                icon: Icons.edit_outlined,
                semanticLabel: ProfileCopy.editProfile,
                color: c.ink,
                onPressed: () => context.push(ProfilePaths.edit),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AknRadius.pillAll,
        border: Border.all(color: c.lineStrong),
      ),
      child: Text(label, style: t.captionStrong.copyWith(color: c.ink)),
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
      icon: Icons.sms_outlined,
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
          : StatusChip(
              label: verified ? ProfileCopy.phoneOn : ProfileCopy.phoneOff,
              tone: verified ? AknTone.ok : AknTone.neutral,
              size: StatusChipSize.small,
            ),
      onTap: () async {
        await context.push(AuthRoutes.phone);
        if (context.mounted) ref.invalidate(phoneStatusProvider);
      },
    );
  }
}

/// Tema: Sistem / Açık / Koyu (çekirdek `themeModeProvider`).
class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Semantics(
      container: true,
      label: ProfileCopy.theme,
      child: FilterChips<ThemeMode>(
        options: const [
          FilterOption(
            value: ThemeMode.system,
            label: ProfileCopy.themeSystem,
            icon: Icons.brightness_auto_rounded,
          ),
          FilterOption(
            value: ThemeMode.light,
            label: ProfileCopy.themeLight,
            icon: Icons.light_mode_rounded,
          ),
          FilterOption(
            value: ThemeMode.dark,
            label: ProfileCopy.themeDark,
            icon: Icons.dark_mode_rounded,
          ),
        ],
        selected: {mode},
        allowEmpty: false,
        onChanged: (m) {
          if (m.isNotEmpty) {
            unawaited(ref.read(themeModeProvider.notifier).set(m.first));
          }
        },
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
      icon: Icons.privacy_tip_outlined,
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
        icon: Icons.forum_outlined,
        title: ProfileCopy.assistantConsent,
        subtitle: ProfileCopy.consentGiven(
          acceptedAt == null ? null : Fmt.date(acceptedAt),
        ),
        trailing: TextButton(
          onPressed: () => unawaited(_withdraw(context, ref)),
          child: const Text(ProfileCopy.withdraw),
        ),
      ),
      GateNeedsConsent() => SettingsTile(
        icon: Icons.forum_outlined,
        title: ProfileCopy.assistantConsent,
        subtitle: ProfileCopy.consentNotGiven,
        onTap: enabled ? () => context.push(AppRoutes.assistant) : null,
      ),
      GateChecking() => const SettingsTile(
        icon: Icons.forum_outlined,
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
      icon: Icons.cloud_upload_outlined,
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
    final server = [?extras?.contractVersion, ?extras?.apiBuild].join(' · ');
    return SettingsTile(
      icon: Icons.info_outline_rounded,
      title: ProfileCopy.about,
      subtitle: [
        ProfileCopy.version(info.versionLabel, env.badge),
        if (server.isNotEmpty) ProfileCopy.server(server),
      ].join('\n'),
    );
  }
}

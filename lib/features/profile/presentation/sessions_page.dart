import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_repository.dart';
import '../../../core/auth/session_controller.dart';
import '../../../core/models/auth_models.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/turkish_text.dart';
import '../application/logout_flow.dart';
import '../copy.dart';
import 'widgets/settings_widgets.dart';

/// `GET auth/sessions`: bu cihaz önce, sonra son etkinliğe göre.
final sessionsProvider = FutureProvider.autoDispose<List<SessionInfo>>((
  ref,
) async {
  ref.watch(currentUserIdProvider);
  final list = await ref.watch(authRepositoryProvider).sessions();
  final sorted = [...list]
    ..sort((a, b) {
      if (a.current != b.current) return a.current ? -1 : 1;
      final x = a.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final y = b.lastSeenAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return y.compareTo(x);
    });
  return sorted;
});

/// Aktif oturumlar (spec A.4 A8): cihazlar, "Bu cihaz" çipi, cihaz başına çıkış
/// (`DELETE auth/sessions/{deviceId}`), "Tüm cihazlardan çık" (`auth/logout {allDevices: true}`).
class SessionsPage extends ConsumerStatefulWidget {
  const SessionsPage({super.key});

  @override
  ConsumerState<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends ConsumerState<SessionsPage> {
  final Set<String> _revoked = {};

  Future<void> _revoke(SessionInfo s) async {
    final ok = await showConfirmSheet(
      context,
      title: ProfileCopy.revokeTitle,
      message: ProfileCopy.revokeMessage,
      confirmLabel: ProfileCopy.revoke,
      cancelLabel: ProfileCopy.cancel,
      icon: PhosphorIconsRegular.deviceMobileSlash,
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _revoked.add(s.deviceId));
    try {
      await ref.read(authRepositoryProvider).revokeSession(s.deviceId);
      AppToast.success(ProfileCopy.revoked);
      ref.invalidate(sessionsProvider);
    } on AppFailure catch (f) {
      if (!mounted) return;
      setState(() => _revoked.remove(s.deviceId));
      AppToast.error(f.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(sessionsProvider);
    final list = async.valueOrNull
        ?.where((s) => !_revoked.contains(s.deviceId))
        .toList();
    final Widget body;
    if (list == null) {
      body = async.hasError
          ? Center(
              child: SingleChildScrollView(
                child: ErrorState(
                  title: ProfileCopy.sessionsLoadFailed,
                  offline: async.error is OfflineFailure,
                  message: async.error is AppFailure
                      ? (async.error! as AppFailure).message
                      : null,
                  onRetry: () => ref.invalidate(sessionsProvider),
                ),
              ),
            )
          : const SkeletonList(itemCount: 3, lines: 2);
    } else {
      // v3: her cihaz kendi beyaz kartında (r20, kart gölgesi), kartlar sırayla belirir.
      body = PullToRefresh(
        onRefresh: () => ref.refresh(sessionsProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AknSpace.page,
            8,
            AknSpace.page,
            32,
          ),
          children: [
            for (final (i, s) in list.indexed)
              SettingsReveal(
                index: i,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _SessionTile(
                    session: s,
                    onRevoke: s.current ? null : () => unawaited(_revoke(s)),
                  ),
                ),
              ),
            if (list.length <= 1)
              SettingsReveal(
                index: list.length,
                child: const AknBanner(
                  tone: AknTone.info,
                  icon: PhosphorIconsRegular.shieldCheck,
                  message: ProfileCopy.onlyThisDevice,
                  margin: EdgeInsets.only(top: 4),
                ),
              ),
          ],
        ),
      );
    }
    return AppScaffold(
      title: ProfileCopy.sessionsTitle,
      showBell: false,
      refreshing: async.isRefreshing,
      actionBar: barOf(
        AknButton.secondary(
          label: ProfileCopy.signOutAll,
          icon: PhosphorIconsRegular.signOut,
          expand: true,
          onPressed: () =>
              unawaited(confirmAndSignOut(context, ref, allDevices: true)),
        ),
      ),
      body: body,
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, this.onRevoke});

  final SessionInfo session;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final s = session;
    final android = s.platform.asciiLower == 'android';
    final ios = s.platform.asciiLower == 'ios';
    final name =
        s.model ??
        (android
            ? ProfileCopy.androidPhone
            : ios
            ? ProfileCopy.iphone
            : ProfileCopy.unknownDevice);
    final details = [
      if (s.appVersion != null) ProfileCopy.appVersion(s.appVersion!),
      if (s.lastSeenAt != null)
        s.appVersion != null
            ? ProfileCopy.lastSeenInline(Fmt.relative(s.lastSeenAt))
            : ProfileCopy.lastSeen(Fmt.relative(s.lastSeenAt)),
    ].join(', ');
    // Kart (v3): 40 px cihaz karosu (bu cihazda yeşil kuyu), ad, ayrıntı; bu cihaz yeşil lamba; diğerlerinde
    // ayrıntının altında küçük "Oturumu kapat".
    final revoke = onRevoke == null
        ? null
        : AknButton.danger(
            label: ProfileCopy.revoke,
            icon: PhosphorIconsRegular.signOut,
            size: AknButtonSize.small,
            onPressed: onRevoke,
          );
    return Semantics(
      container: true,
      label: [
        name,
        if (s.current) ProfileCopy.thisDevice,
        if (details.isNotEmpty) details,
      ].join(', '),
      child: AknCard(
        radius: 20,
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: s.current ? c.ok.bg : c.surfaceAlt,
                  borderRadius: AknRadius.buttonSmall,
                ),
                alignment: Alignment.center,
                child: Icon(
                  android || ios
                      ? PhosphorIconsRegular.deviceMobile
                      : PhosphorIconsRegular.devices,
                  size: 22,
                  color: s.current ? c.ok.fg : c.ink,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(name, style: t.headline.copyWith(color: c.ink)),
                        if (details.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            details,
                            style: t.bodySmall.copyWith(
                              color: c.dim,
                              fontFeatures: AknNumerals.tabular,
                            ),
                          ),
                        ],
                        if (s.current) ...[
                          const SizedBox(height: 10),
                          const AknLamp(
                            label: ProfileCopy.thisDevice,
                            tone: AknTone.ok,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (revoke != null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: revoke,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

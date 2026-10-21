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
      icon: Icons.phonelink_erase_rounded,
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
      body = PullToRefresh(
        onRefresh: () => ref.refresh(sessionsProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: [
            SettingsGroup(
              children: [
                for (final s in list)
                  _SessionTile(
                    session: s,
                    onRevoke: s.current ? null : () => unawaited(_revoke(s)),
                  ),
              ],
            ),
            if (list.length <= 1)
              const AknBanner(
                tone: AknTone.info,
                icon: Icons.verified_user_rounded,
                message: ProfileCopy.onlyThisDevice,
                margin: EdgeInsets.fromLTRB(16, 16, 16, 0),
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
          icon: Icons.logout_rounded,
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
        ProfileCopy.lastSeen(Fmt.relative(s.lastSeenAt)),
    ].join(' · ');
    final Widget tile = Semantics(
      container: true,
      label: [
        name,
        if (s.current) ProfileCopy.thisDevice,
        if (details.isNotEmpty) details,
      ].join(', '),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 8, onRevoke == null ? 12 : 0),
        child: Row(
          children: [
            AknIconBox(
              icon: android
                  ? Icons.phone_android_rounded
                  : ios
                  ? Icons.phone_iphone_rounded
                  : Icons.devices_other_rounded,
              tone: s.current ? AknTone.brand : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ExcludeSemantics(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name, style: t.bodyStrong),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(details, style: t.bodySmall),
                    ],
                    if (s.current) ...[
                      const SizedBox(height: 6),
                      const StatusChip(
                        label: ProfileCopy.thisDevice,
                        tone: AknTone.ok,
                        size: StatusChipSize.small,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (onRevoke == null) return tile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tile,
        Padding(
          padding: const EdgeInsets.only(left: 60, bottom: 4),
          child: TextButton.icon(
            onPressed: onRevoke,
            style: TextButton.styleFrom(foregroundColor: c.danger.fg),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text(ProfileCopy.revoke),
          ),
        ),
      ],
    );
  }
}

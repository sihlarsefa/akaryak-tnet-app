import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/auth/auth_repository.dart';
import '../../../core/env/app_config_controller.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/push/push_providers.dart';
import '../../../core/push/push_service.dart';
import '../../../core/push/unread_count_provider.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/log.dart';
import '../application/preferences_controller.dart';
import '../copy.dart';
import '../data/notification_models.dart';

/// Bu cihazın bildirim izni (testler ezer).
final pushPermissionProvider = FutureProvider.autoDispose<PushPermission>(
  (ref) => ref.watch(pushServiceProvider).permission(),
);

/// Bildirim ayarları (spec A.4 A8 "preferences per category"): cihaz izni, kategori anahtarları
/// (`PUT notifications/preferences`), test bildirimi.
class NotificationSettingsPage extends ConsumerWidget {
  const NotificationSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(preferencesControllerProvider);
    return AppScaffold(
      title: NotificationsCopy.settingsTitle,
      showBell: false,
      body: ListView(
        padding: EdgeInsets.only(
          bottom: 32 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _DevicePushCard(),
          ),
          const SectionHeader(
            title: NotificationsCopy.categoriesTitle,
            subtitle: NotificationsCopy.categoriesHint,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _Categories(state: s),
          ),
          const SectionHeader(title: NotificationsCopy.testTitle),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _TestCard(),
          ),
        ],
      ),
    );
  }
}

class _Categories extends ConsumerWidget {
  const _Categories({required this.state});

  final PreferencesState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = state;
    final ctl = ref.read(preferencesControllerProvider.notifier);
    if (s.loading && s.items.isEmpty) {
      return const Shimmer(
        child: SkeletonCard(lines: 4, margin: EdgeInsets.zero),
      );
    }
    final error = s.error;
    if (error != null && s.items.isEmpty) {
      return AknCard(
        child: ErrorState(
          compact: true,
          offline: error is OfflineFailure,
          title: NotificationsCopy.prefsError,
          message: error is OfflineFailure ? null : error.message,
          onRetry: () => unawaited(ctl.reload()),
        ),
      );
    }
    return AknCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < s.items.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 68),
            _PrefTile(
              pref: s.items[i],
              busy: s.saving.contains(s.items[i].category),
              onChanged: (v) async {
                final f = await ctl.toggle(s.items[i].category, v);
                if (f != null) {
                  AppToast.error(
                    f is OfflineFailure
                        ? f.message
                        : NotificationsCopy.prefsSaveFailed,
                  );
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _PrefTile extends StatelessWidget {
  const _PrefTile({
    required this.pref,
    required this.busy,
    required this.onChanged,
  });

  final NotificationPreference pref;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final description = NotificationCategory.description(pref.category);
    return MergeSemantics(
      child: InkWell(
        onTap: busy ? null : () => onChanged(!pref.pushEnabled),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          child: Row(
            children: [
              AknIconBox(
                icon: NotificationCategory.icon(pref.category),
                tone: pref.pushEnabled ? AknTone.brand : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(pref.label, style: t.bodyStrong),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(description, style: t.bodySmall),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: pref.pushEnabled,
                onChanged: busy ? null : onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cihazın bildirim izni ve sunucunun push durumu.
class _DevicePushCard extends ConsumerWidget {
  const _DevicePushCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final firebase = ref.watch(firebaseAvailableProvider);
    final serverPush = ref.watch(
      appConfigProvider.select((c) => c.features.push),
    );
    if (!firebase || !serverPush) {
      return const AknBanner(
        tone: AknTone.info,
        icon: Icons.notifications_paused_rounded,
        title: NotificationsCopy.pushOffTitle,
        message: NotificationsCopy.pushOffMessage,
      );
    }
    final permission = ref.watch(pushPermissionProvider).valueOrNull;
    return switch (permission) {
      PushPermission.granted => const AknBanner(
        tone: AknTone.ok,
        icon: Icons.notifications_active_rounded,
        title: NotificationsCopy.pushOnTitle,
        message: NotificationsCopy.pushOnMessage,
      ),
      PushPermission.notDetermined => AknBanner(
        tone: AknTone.info,
        icon: Icons.notifications_rounded,
        title: NotificationsCopy.pushAskTitle,
        message: NotificationsCopy.pushAskMessage,
        actionLabel: NotificationsCopy.pushAsk,
        onAction: () => unawaited(_ask(ref)),
      ),
      PushPermission.denied => AknBanner(
        tone: AknTone.warn,
        icon: Icons.notifications_off_rounded,
        title: NotificationsCopy.pushDeniedTitle,
        message: NotificationsCopy.pushDeniedMessage,
        actionLabel: NotificationsCopy.openSettings,
        onAction: () => unawaited(_openSettings()),
      ),
      _ => const SizedBox.shrink(),
    };
  }

  static Future<void> _ask(WidgetRef ref) async {
    final push = ref.read(pushServiceProvider);
    final granted = await push.requestPermission();
    ref.invalidate(pushPermissionProvider);
    if (!granted) return;
    try {
      final token = await push.token();
      await ref
          .read(authRepositoryProvider)
          .registerDevice(pushToken: token, pushEnabled: token != null);
    } catch (e) {
      AppLog.debug('Cihaz kaydı güncellenemedi: $e');
    }
  }

  static Future<void> _openSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (e) {
      AppLog.debug('Ayarlar açılamadı: $e');
    }
  }
}

class _TestCard extends ConsumerStatefulWidget {
  const _TestCard();

  @override
  ConsumerState<_TestCard> createState() => _TestCardState();
}

class _TestCardState extends ConsumerState<_TestCard> {
  String? _result;
  AknTone _tone = AknTone.ok;

  Future<void> _send() async {
    try {
      final r = await ref
          .read(preferencesControllerProvider.notifier)
          .sendTest();
      if (!mounted) return;
      setState(() {
        _tone = r.sent > 0 ? AknTone.ok : AknTone.info;
        _result = r.sent > 0
            ? NotificationsCopy.testSent(r.sent)
            : NotificationsCopy.testInboxOnly;
      });
      unawaited(ref.read(unreadCountProvider.notifier).refresh());
    } on AppFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _tone = AknTone.warn;
        _result = f.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final result = _result;
    return AknCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(NotificationsCopy.testTile, style: t.bodyStrong),
          const SizedBox(height: 2),
          Text(NotificationsCopy.testHint, style: t.bodySmall),
          const SizedBox(height: 12),
          // Genişletilmiş: çekirdek AknButton'ın daraltılmış hâli eşzamansız işlemde
          // (genişliği sınırsız) kısıt geçişinde hata verir.
          AknButton.secondary(
            label: NotificationsCopy.testSend,
            icon: Icons.send_rounded,
            expand: true,
            showSuccess: false,
            onPressedAsync: _send,
          ),
          if (result != null) ...[
            const SizedBox(height: 12),
            AknBanner(tone: _tone, message: result),
          ],
        ],
      ),
    );
  }
}

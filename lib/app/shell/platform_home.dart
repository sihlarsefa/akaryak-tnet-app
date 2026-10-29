import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/session_controller.dart';
import '../../core/env/app_env.dart';
import '../../core/push/unread_count_provider.dart';
import '../../core/routing/app_location.dart';
import '../../core/routing/app_routes.dart';
import '../../core/ui/ui.dart';
import '../../core/utils/external_activity.dart';
import '../tasks/task_inbox.dart';

/// Merkez (Admin, HeadOffice) ana sayfası (v4 §3.3): turuncu bant (avatar, selamlama, "AkaryakıtNet
/// merkez", zil) → bandın üstüne binen "Sıra sizde" kartı ("Onayınızı bekleyen n talep"; bekleyen
/// yoksa sakin satır) → "Web portalı" satırı. Merkez mobilde yalnızca Onaylar, Bildirimler ve
/// Profil kullanır; diğer işler web portalındadır.
///
/// Onaylar ve Profil Merkez'in alt menü sekmeleridir: hepsi [openAppLocation] ile açılır (sekmeye
/// geçilir; `push` kabuğu ikinci kez kurardı, QA SC-01).
class PlatformHome extends ConsumerWidget {
  const PlatformHome({super.key});

  static const company = 'AkaryakıtNet merkez';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(sessionControllerProvider).access;
    final inbox = ref.watch(platformTasksProvider);
    final env = ref.watch(appEnvProvider);
    final name = access?.displayName ?? '';
    final count = inbox.count;
    final tasks = [
      for (final t in inbox.items)
        t.toAknTask(
          onTap: () => context.openAppLocation(t.location),
          onAction: () => context.openAppLocation(t.location),
        ),
    ];
    return AppScaffold(
      homeHeader: AknHomeHeader(
        company: company,
        person: name.isEmpty ? 'Merkez' : '$name, merkez',
        onOpenProfile: () => context.openAppLocation(AppRoutes.profile),
      ),
      body: PullToRefresh(
        onRefresh: () => ref.read(unreadCountProvider.notifier).refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            // "Sıra sizde" bandın üstüne biner ve yükselerek gelir.
            AknBandOverlap(
              child: AknTaskCard(
                tasks: tasks,
                total: count,
                calm: 'Üst onaya gelen talepler burada görünür.',
                onSeeAll: () => context.openAppLocation(AppRoutes.approvals),
              ),
            ),
            const SizedBox(height: AknSpace.s16),
            StaggerItem(
              index: 1,
              child: AknLedger(
                children: [
                  AknListTile(
                    leadingIcon: PhosphorIconsRegular.arrowSquareOut,
                    title: 'Web portalı',
                    subtitle: 'Bayiler, cariler, raporlar ve ayarlar',
                    showChevron: true,
                    semanticLabel:
                        'Web portalı. Bayiler, cariler, raporlar ve ayarlar için portalı açar.',
                    onTap: () => launchExternal(
                      Uri.parse(env.portalBaseUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

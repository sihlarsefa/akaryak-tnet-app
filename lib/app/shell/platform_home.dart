import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/session_controller.dart';
import '../../core/env/app_env.dart';
import '../../core/push/unread_count_provider.dart';
import '../../core/routing/app_routes.dart';
import '../../core/routing/home_placeholder.dart';
import '../../core/ui/ui.dart';
import '../../core/utils/external_activity.dart';

/// Merkez (Admin, HeadOffice) ana sayfası (M0a): onay özeti ve web portalı bağlantısı. Merkez mobilde
/// yalnızca Onaylarım, Bildirimler ve Profil kullanır; diğer işler web portalındadır.
class PlatformHome extends ConsumerWidget {
  const PlatformHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(sessionControllerProvider).access;
    final unread = ref.watch(unreadCountProvider);
    final env = ref.watch(appEnvProvider);
    final t = context.aknText;
    final c = context.akn;
    final firstName = (access?.displayName ?? '').split(' ').first;
    return AppScaffold(
      navy: true,
      // Lacivert başlıkta marka logosu (müşteri ana sayfasıyla aynı).
      titleWidget: const AknLogo(markSize: 28, onDark: true),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          AknHeroPanel(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${HomePlaceholder.greeting()}${firstName.isEmpty ? '' : ', $firstName'}',
                  style: t.title,
                ),
                const SizedBox(height: 4),
                Text('Merkez', style: t.body.copyWith(color: c.onNavyDim)),
              ],
            ),
          ),
          const SectionHeader(title: 'Bugün'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: KpiTile(
                    label: 'Kararınızı bekleyen',
                    value: unread.approvals.toDouble(),
                    icon: Icons.task_alt_rounded,
                    onTap: () => context.go(AppRoutes.approvals),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: KpiTile(
                    label: 'Okunmamış bildirim',
                    value: unread.notifications.toDouble(),
                    icon: Icons.notifications_rounded,
                    onTap: () => context.go(AppRoutes.notifications),
                  ),
                ),
              ],
            ),
          ),
          const SectionHeader(title: 'Web portalı'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AknCard(
              child: AknListTile(
                leadingIcon: Icons.open_in_new_rounded,
                title: 'Yönetim işlemleri web portalında',
                subtitle:
                    'Bayiler, cariler, raporlar ve ayarlar için portalı açın.',
                padding: EdgeInsets.zero,
                onTap: () => launchExternal(
                  Uri.parse(env.portalBaseUrl),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

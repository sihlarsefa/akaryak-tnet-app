import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/session_controller.dart';
import '../../core/env/app_env.dart';
import '../../core/push/unread_count_provider.dart';
import '../../core/routing/app_routes.dart';
import '../../core/ui/ui.dart';
import '../../core/utils/external_activity.dart';

/// Merkez (Admin, HeadOffice) ana sayfası (M0a; tasarım v2 §7.6): plaka yok — ana sayfa başlığı (logo
/// karosu, "AkaryakıtNet merkez", ad), "Bugün" defter satırları (kararınızı bekleyenler, okunmamış
/// bildirimler) ve web portalı satırı. Merkez mobilde yalnızca Onaylarım, Bildirimler ve Profil kullanır;
/// diğer işler web portalındadır.
class PlatformHome extends ConsumerWidget {
  const PlatformHome({super.key});

  static const company = 'AkaryakıtNet merkez';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(sessionControllerProvider).access;
    final unread = ref.watch(unreadCountProvider);
    final env = ref.watch(appEnvProvider);
    final name = access?.displayName ?? '';
    final approvals = unread.approvals;
    final notifications = unread.notifications;
    return AppScaffold(
      homeHeader: AknHomeHeader(
        company: company,
        person: name.isEmpty ? 'Merkez' : '$name, merkez',
        onOpenProfile: () => context.push(AppRoutes.profile),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SectionHeader(title: 'Bugün'),
          AknLedger(
            children: [
              AknListTile(
                title: 'Kararınızı bekleyen',
                subtitle: approvals == 0
                    ? 'Bekleyen onay yok.'
                    : 'Onaylarım sekmesinde sırayla.',
                amount: '$approvals',
                status: approvals == 0
                    ? null
                    : const AknLamp(
                        label: 'Onayınızı bekliyor',
                        tone: AknTone.brand,
                      ),
                showChevron: true,
                semanticLabel: approvals == 0
                    ? 'Kararınızı bekleyen onay yok'
                    : 'Kararınızı bekleyen $approvals onay. Onaylarımı açar.',
                onTap: () => context.go(AppRoutes.approvals),
              ),
              AknListTile(
                title: 'Okunmamış bildirim',
                subtitle: notifications == 0
                    ? 'Tüm bildirimleri okudunuz.'
                    : 'Bildirimler sayfasında, en yenisi üstte.',
                amount: '$notifications',
                showChevron: true,
                semanticLabel:
                    '$notifications okunmamış bildirim. Bildirimleri açar.',
                onTap: () => context.go(AppRoutes.notifications),
              ),
            ],
          ),
          const SectionHeader(title: 'Web portalı'),
          AknListTile(
            leadingIcon: Icons.open_in_new_rounded,
            title: 'Yönetim işlemleri web portalında',
            subtitle:
                'Bayiler, cariler, raporlar ve ayarlar için portalı açın.',
            showChevron: true,
            onTap: () => launchExternal(
              Uri.parse(env.portalBaseUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
      ),
    );
  }
}

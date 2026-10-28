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

/// Merkez (Admin, HeadOffice) ana sayfası (M0a; tasarım v3 "Akış"): plaka yok — turuncu bant (avatar,
/// selamlama, "AkaryakıtNet merkez"), bandın üstüne binen beyaz "Bugün" kartı (kararınızı bekleyenler,
/// okunmamış bildirimler) ve altında "Web portalı" kartı. Kartlar sırayla yükselerek gelir. Merkez
/// mobilde yalnızca Onaylarım, Bildirimler ve Profil kullanır; diğer işler web portalındadır.
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
    const rowPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);
    return AppScaffold(
      homeHeader: AknHomeHeader(
        company: company,
        person: name.isEmpty ? 'Merkez' : '$name, merkez',
        onOpenProfile: () => context.push(AppRoutes.profile),
      ),
      body: StaggerScope(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            // Bugünün kartı bandın üstüne biner ve yükselerek gelir.
            AknBandOverlap(
              child: _Section(
                title: 'Bugün',
                children: [
                  AknListTile(
                    leadingIcon: PhosphorIconsRegular.checkCircle,
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
                    padding: rowPadding,
                    semanticLabel: approvals == 0
                        ? 'Kararınızı bekleyen onay yok'
                        : 'Kararınızı bekleyen $approvals onay. Onaylarımı açar.',
                    onTap: () => context.go(AppRoutes.approvals),
                  ),
                  AknListTile(
                    leadingIcon: PhosphorIconsRegular.bell,
                    title: 'Okunmamış bildirim',
                    subtitle: notifications == 0
                        ? 'Tüm bildirimleri okudunuz.'
                        : 'Bildirimler sayfasında, en yenisi üstte.',
                    amount: '$notifications',
                    showChevron: true,
                    padding: rowPadding,
                    semanticLabel:
                        '$notifications okunmamış bildirim. Bildirimleri açar.',
                    onTap: () => context.go(AppRoutes.notifications),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AknSpace.s16),
            StaggerItem(
              index: 1,
              child: Padding(
                padding: AknSpace.pagePadding,
                child: _Section(
                  title: 'Web portalı',
                  children: [
                    AknListTile(
                      leadingIcon: PhosphorIconsRegular.arrowSquareOut,
                      title: 'Yönetim işlemleri web portalında',
                      subtitle:
                          'Bayiler, cariler, raporlar ve ayarlar için portalı açın.',
                      showChevron: true,
                      padding: rowPadding,
                      onTap: () => launchExternal(
                        Uri.parse(env.portalBaseUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Beyaz bölüm kartı (tasarım v3 §3): r22 yuvarlatılmış kare, kart gölgesi (koyu temada 1 px çizgi),
/// içinde başlık (18/24 w800) ve satırlar; satırlar arasında içeriden başlayan ince çizgi.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: c.surface,
        shape: RoundedSuperellipseBorder(
          borderRadius: AknRadius.section,
          side: c.isDark ? BorderSide(color: c.line) : BorderSide.none,
        ),
        shadows: AknShadows.card(c),
      ),
      child: ClipRSuperellipse(
        borderRadius: AknRadius.section,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: t.headline.copyWith(
                    fontSize: 18,
                    height: 24 / 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: c.ink,
                  ),
                ),
              ),
            ),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    height: 1,
                    width: double.infinity,
                    child: ColoredBox(color: c.lineSoft),
                  ),
                ),
              children[i],
            ],
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

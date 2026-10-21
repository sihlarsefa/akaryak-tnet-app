import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/session_controller.dart';
import '../../core/auth/session_state.dart';
import '../../core/env/app_env.dart';
import '../../core/env/app_info.dart';
import '../../core/network/app_failure.dart';
import '../../core/network/fake/fake_auth.dart';
import '../../core/network/fake/fake_personas.dart';
import '../../core/network/fake/fake_server.dart';
import '../../core/network/network_providers.dart';
import '../../core/push/unread_count_provider.dart';
import '../../core/routing/app_routes.dart';
import '../../core/ui/gallery/gallery_route.dart';
import '../../core/ui/ui.dart';

/// Geliştirici menüsü (yalnızca sahte kip / geliştirme ortamı; `/dev`): demo hesabı değiştirme, hata
/// enjeksiyonu, gecikme, belirteç düşürme, sahte verileri sıfırlama, tasarım galerisi.
class DevMenuPage extends ConsumerStatefulWidget {
  const DevMenuPage({super.key});

  @override
  ConsumerState<DevMenuPage> createState() => _DevMenuPageState();
}

class _DevMenuPageState extends ConsumerState<DevMenuPage> {
  Future<void> _switchTo(FakePersona p) async {
    final session = ref.read(sessionControllerProvider.notifier);
    final router = GoRouter.of(context);
    if (ref.read(sessionControllerProvider) is! SessionUnauthenticated) {
      await session.signOut();
    }
    try {
      final outcome = await session.loginWithPassword(p.key, FakeAuth.password);
      if (outcome is LoginNeedsCode) {
        await session.verifyCode(outcome.challenge.challengeId, FakeAuth.code);
      }
    } on AppFailure catch (f) {
      AppToast.error(f.message);
      router.go(AppRoutes.login);
    }
  }

  @override
  Widget build(BuildContext context) {
    final env = ref.watch(appEnvProvider);
    final info = ref.watch(appInfoProvider);
    final current = ref.watch(currentUserIdProvider);
    final FakeServer? server = kFakeApiCompiled && env.isFake
        ? ref.watch(fakeServerProvider)
        : null;
    return AppScaffold(
      title: 'Geliştirici menüsü',
      subtitle: env.badge,
      showBell: false,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: AknCard(
              child: Column(
                children: [
                  FactRow(label: 'Ortam', value: env.env.label),
                  FactRow(
                    label: 'API',
                    value: env.isFake ? 'Sahte (uygulama içi)' : env.apiBaseUrl,
                  ),
                  FactRow(label: 'Portal', value: env.portalBaseUrl),
                  FactRow(label: 'Sürüm', value: info.versionLabel),
                  FactRow(
                    label: 'Cihaz',
                    value: '${info.platform}, ${info.model ?? '—'}',
                  ),
                ],
              ),
            ),
          ),
          if (server != null) ...[
            const SectionHeader(title: 'Sahte sunucu'),
            SwitchListTile.adaptive(
              title: const Text('Ağ gecikmesi (300–800 ms)'),
              value: server.latencyEnabled,
              onChanged: (v) => setState(() => server.latencyEnabled = v),
            ),
            const SectionHeader(
              title: 'Hata enjeksiyonu',
              padding: EdgeInsets.fromLTRB(16, 12, 8, 4),
            ),
            for (final mode in FakeFailureMode.values)
              AknListTile(
                title: mode.label,
                dense: true,
                trailing: server.failureMode == mode
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: context.akn.brand,
                        semanticLabel: 'Seçili',
                      )
                    : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                onTap: () => setState(() => server.failureMode = mode),
              ),
            AknListTile(
              leadingIcon: Icons.timer_off_outlined,
              title: 'Erişim belirtecini düşür',
              subtitle: 'Sonraki istek yenileme akışını dener',
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              onTap: () {
                server.auth.expireAllAccessTokens();
                AppToast.info('Erişim belirteçlerinin süresi doldu.');
              },
            ),
            AknListTile(
              leadingIcon: Icons.restart_alt_rounded,
              title: 'Sahte verileri sıfırla',
              subtitle: 'Siparişler, sevkiyatlar, onaylar baştan yüklenir',
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              onTap: () {
                server.resetWorld();
                ref.read(unreadCountProvider.notifier).refresh();
                AppToast.success('Sahte veriler sıfırlandı.');
              },
            ),
            const SectionHeader(
              title: 'Demo hesapları',
              subtitle: 'Şifre ${FakeAuth.password}, SMS kodu ${FakeAuth.code}',
            ),
            for (final p in fakePersonas)
              AknListTile(
                leading: AknAvatar(name: p.displayName),
                title: p.displayName,
                subtitle: p.summary,
                meta: p.userId == current ? 'açık' : p.key,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                onTap: p.userId == current ? null : () => _switchTo(p),
              ),
          ],
          const SectionHeader(title: 'Tasarım'),
          AknListTile(
            leadingIcon: Icons.palette_outlined,
            title: 'Tasarım galerisi',
            subtitle: 'Bileşenler, renkler, hareket',
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            onTap: () => context.push(kDesignGalleryPath),
          ),
        ],
      ),
    );
  }
}

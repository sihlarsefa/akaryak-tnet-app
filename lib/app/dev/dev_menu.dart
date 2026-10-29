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

/// Geliştirici menüsü (yalnızca sahte kip / geliştirme ortamı; test derlemesinde demo oturumu sürerken;
/// `/dev`): demo hesabı değiştirme, hata enjeksiyonu, gecikme, belirteç düşürme, sahte verileri
/// sıfırlama, tasarım galerisi.
///
/// Tasarım v3: her grup 20 px kenar boşluğunda beyaz, gölgeli bir kart (satırlar arasında içeriden
/// ince çizgi); bölümler sırayla yükselerek gelir; seçili hata kipinin işareti zıplayarak değişir.
class DevMenuPage extends ConsumerStatefulWidget {
  const DevMenuPage({super.key});

  @override
  ConsumerState<DevMenuPage> createState() => _DevMenuPageState();
}

class _DevMenuPageState extends ConsumerState<DevMenuPage> {
  /// Demo hesabı değişimi. Test derlemesinin demo oturumunda değişim sahte dünyada kalır: çıkış demo
  /// oturumunu bitirmez, demo şifresi canlı API'ye gitmez; giriş olmazsa uygulama canlı kipe döner.
  Future<void> _switchTo(FakePersona p) async {
    final session = ref.read(sessionControllerProvider.notifier);
    final demo = ref.read(demoSessionProvider.notifier);
    final inDemoSession = ref.read(appEnvProvider).demoSession;
    final router = GoRouter.of(context);
    if (ref.read(sessionControllerProvider) is! SessionUnauthenticated) {
      await session.signOut(endDemoSession: false);
    }
    try {
      final outcome = await session.loginWithPassword(p.key, FakeAuth.password);
      if (outcome is LoginNeedsCode) {
        await session.verifyCode(outcome.challenge.challengeId, FakeAuth.code);
      }
    } on AppFailure catch (f) {
      if (inDemoSession) demo.end();
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
    const rowPadding = EdgeInsets.symmetric(horizontal: 16, vertical: 8);
    return AppScaffold(
      title: 'Geliştirici menüsü',
      subtitle: env.badge,
      showBell: false,
      body: StaggerScope(
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: staggered([
            _Group(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
            if (server != null) ...[
              const SectionHeader(title: 'Sahte sunucu'),
              _Group(
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    title: const Text('Ağ gecikmesi (300–800 ms)'),
                    value: server.latencyEnabled,
                    onChanged: (v) => setState(() => server.latencyEnabled = v),
                  ),
                ],
              ),
              const SectionHeader(title: 'Hata enjeksiyonu'),
              _Group(
                children: [
                  for (final mode in FakeFailureMode.values)
                    AknListTile(
                      title: mode.label,
                      dense: true,
                      trailing: _Picked(picked: server.failureMode == mode),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      onTap: () => setState(() => server.failureMode = mode),
                    ),
                  AknListTile(
                    leadingIcon: PhosphorIconsRegular.hourglassLow,
                    title: 'Erişim belirtecini düşür',
                    subtitle: 'Sonraki istek yenileme akışını dener',
                    padding: rowPadding,
                    onTap: () {
                      server.auth.expireAllAccessTokens();
                      AppToast.info('Erişim belirteçlerinin süresi doldu.');
                    },
                  ),
                  AknListTile(
                    leadingIcon: PhosphorIconsRegular.arrowCounterClockwise,
                    title: 'Sahte verileri sıfırla',
                    subtitle:
                        'Siparişler, sevkiyatlar, onaylar baştan yüklenir',
                    padding: rowPadding,
                    onTap: () {
                      server.resetWorld();
                      ref.read(unreadCountProvider.notifier).refresh();
                      AppToast.success('Sahte veriler sıfırlandı.');
                    },
                  ),
                ],
              ),
              const SectionHeader(
                title: 'Demo hesapları',
                subtitle:
                    'Şifre ${FakeAuth.password}, SMS kodu ${FakeAuth.code}',
              ),
              _Group(
                children: [
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
              ),
            ],
            const SectionHeader(title: 'Tasarım'),
            _Group(
              children: [
                AknListTile(
                  leadingIcon: PhosphorIconsRegular.palette,
                  title: 'Tasarım galerisi',
                  subtitle: 'Bileşenler, renkler, hareket',
                  padding: rowPadding,
                  onTap: () => context.push(kDesignGalleryPath),
                ),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

/// Bir grup: 20 px kenar boşluğunda beyaz kart (r20, kart gölgesi; koyu temada 1 px çizgi), satırlar
/// arasında içeriden ince çizgi.
class _Group extends StatelessWidget {
  const _Group({required this.children, this.padding = EdgeInsets.zero});

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return Padding(
      padding: AknSpace.pagePadding,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: c.surface,
          shape: RoundedSuperellipseBorder(
            borderRadius: AknRadius.card,
            side: c.isDark ? BorderSide(color: c.line) : BorderSide.none,
          ),
          shadows: AknShadows.card(c),
        ),
        child: ClipRSuperellipse(
          borderRadius: AknRadius.card,
          child: Material(
            type: MaterialType.transparency,
            child: Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Seçili hata kipinin işareti: turuncu dolu onay, gelirken zıplar (pop), giderken küçülür.
class _Picked extends StatelessWidget {
  const _Picked({required this.picked});

  final bool picked;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AknMotion.of(context, AknMotion.base),
      switchInCurve: AknMotion.pop,
      switchOutCurve: AknMotion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: picked
          ? Icon(
              PhosphorIconsFill.checkCircle,
              key: const ValueKey('picked'),
              color: context.akn.brand,
              semanticLabel: 'Seçili',
            )
          : const SizedBox.square(key: ValueKey('none'), dimension: 24),
    );
  }
}

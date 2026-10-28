import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/prefs_store.dart';
import '../../../core/ui/ui.dart';
import '../copy.dart';
import 'scenes.dart';

/// Bir tanıtım sahnesi.
@immutable
class OnboardingSceneData {
  const OnboardingSceneData({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.description,
    required this.builder,
  });

  final String eyebrow;
  final String title;
  final String body;

  /// Çizimin ekran okuyucu açıklaması.
  final String description;
  final Widget Function(double t) builder;
}

/// Siparişten teslimata üç sahne (spec A.4 A1).
final onboardingScenes = <OnboardingSceneData>[
  OnboardingSceneData(
    eyebrow: OnboardingCopy.orderEyebrow,
    title: OnboardingCopy.orderTitle,
    body: OnboardingCopy.orderBody,
    description: OnboardingCopy.orderScene,
    builder: (t) => OrderScene(t: t, animate: t < 1),
  ),
  OnboardingSceneData(
    eyebrow: OnboardingCopy.quoteEyebrow,
    title: OnboardingCopy.quoteTitle,
    body: OnboardingCopy.quoteBody,
    description: OnboardingCopy.quoteScene,
    builder: (t) => QuoteScene(t: t, animate: t < 1),
  ),
  OnboardingSceneData(
    eyebrow: OnboardingCopy.deliveryEyebrow,
    title: OnboardingCopy.deliveryTitle,
    body: OnboardingCopy.deliveryBody,
    description: OnboardingCopy.deliveryScene,
    builder: (t) => DeliveryScene(t: t),
  ),
];

/// İlk açılış tanıtımı (spec A.4 A1; tasarım v3): Sipariş → Teklif → Teslimat. Üst yarıda gerçek arayüzün
/// canlı bir minyatürü (0,9 ölçek: sihirbaz özet plakası, teklif plakası ve "Teklifi onayla", » aracıyla
/// rota + adımlar) yumuşak, yavaşça kayan sıcak bir ışığın önünde; altında adım çipi, `display` başlık ve
/// tek cümle; kapsül sayfa göstergesi ve birincil "Devam" / son sayfada "Başlayalım"; sağ üstte sade
/// "Atla". Sayfa değişirken derinlik vardır: çizim sayfadan yavaş, yazı hızlı kayar ve ikisi de solar;
/// gösterge parmağı izler. Kendiliğinden ilerlemez. Sahneler sayfa öne gelince bir kez oynar; azaltılmış
/// harekette ya da ekran okuyucu açıkken durağan son kare gösterilir. Sayfa göstergesi "Sayfa 1/3" diye
/// okunur.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _controller = PageController();
  int _index = 0;

  int get _count => onboardingScenes.length;
  bool get _last => _index == _count - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _staticFrames(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ||
      MediaQuery.accessibleNavigationOf(context);

  void _finish() {
    AknHaptics.light();
    unawaited(ref.read(onboardingDoneProvider.notifier).complete());
  }

  void _go(int target) {
    if (target == _index) return;
    if (_staticFrames(context)) {
      _controller.jumpToPage(target);
    } else {
      unawaited(
        _controller.animateToPage(
          target,
          duration: AknMotion.slow,
          curve: AknMotion.emphasizedCurve,
        ),
      );
    }
  }

  void _next() {
    if (_last) {
      _finish();
      return;
    }
    _go(_index + 1);
  }

  /// Sayfanın kaydırma konumu (parmağı izleyen ondalık sayfa).
  double get _page =>
      _controller.hasClients && _controller.position.haveDimensions
      ? (_controller.page ?? _index.toDouble())
      : _index.toDouble();

  @override
  Widget build(BuildContext context) {
    final animate = !_staticFrames(context);
    return AppScaffold(
      appBar: false,
      showBell: false,
      showOfflineBanner: false,
      body: Stack(
        children: [
          // Sahnenin arkasında yavaşça kayan sıcak ışık (süs).
          const Positioned.fill(child: _StageGlow()),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  children: [
                    _TopBar(onSkip: _finish),
                    Expanded(
                      child: PageView.builder(
                        controller: _controller,
                        itemCount: _count,
                        onPageChanged: (i) {
                          AknHaptics.selection();
                          setState(() => _index = i);
                        },
                        itemBuilder: (context, i) => _ScenePage(
                          scene: onboardingScenes[i],
                          step: i,
                          active: i == _index,
                          animate: animate,
                          controller: _controller,
                          current: _index,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AknSpace.page,
                        4,
                        AknSpace.page,
                        16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Semantics(
                            label: OnboardingCopy.page(_index + 1, _count),
                            liveRegion: true,
                            child: AnimatedBuilder(
                              animation: _controller,
                              builder: (context, _) => _Capsules(
                                count: _count,
                                page: _page,
                                onSelect: _go,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          AknButton(
                            label: _last
                                ? OnboardingCopy.start
                                : OnboardingCopy.next,
                            expand: true,
                            size: AknButtonSize.large,
                            onPressed: _next,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Üst satır: solda 32 px logo karosu, sağda sade "Atla" (48 dp hedef, ink).
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSkip});

  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AknSpace.page, 8, 8, 0),
      child: Row(
        children: [
          const LogoMark(size: 32, animate: true),
          const Spacer(),
          Semantics(
            button: true,
            label: OnboardingCopy.skipSpoken,
            excludeSemantics: true,
            onTap: onSkip,
            child: AknButton.ghost(
              label: OnboardingCopy.skip,
              size: AknButtonSize.small,
              onPressed: onSkip,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kapsül sayfa göstergesi (tasarım v3): etkin sayfa 24 × 8 turuncu kapsül, diğerleri 8 × 8 soluk nokta;
/// genişlik ve renk kaydırma konumunu ([page]) parmakla birlikte izler. Tüm şerit tek 48 dp dokunma
/// alanıdır (en yakın noktaya atlar); ekran okuyucu sayfayı üstteki etiketten duyar.
class _Capsules extends StatelessWidget {
  const _Capsules({
    required this.count,
    required this.page,
    required this.onSelect,
  });

  final int count;
  final double page;
  final ValueChanged<int> onSelect;

  static const double _dot = 8;
  static const double _active = 24;
  static const double _gap = 8;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final rest = c.lineStrong.withValues(alpha: 0.45);
    final widths = [
      for (var i = 0; i < count; i++)
        _dot + (_active - _dot) * (1 - (page - i).abs()).clamp(0.0, 1.0),
    ];
    return ExcludeSemantics(
      child: Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            var x = 0.0;
            for (var i = 0; i < count; i++) {
              if (d.localPosition.dx <= x + widths[i] + _gap / 2) {
                onSelect(i);
                return;
              }
              x += widths[i] + _gap;
            }
            onSelect(count - 1);
          },
          child: SizedBox(
            height: AknSpace.minTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < count; i++) ...[
                  if (i > 0) const SizedBox(width: _gap),
                  Container(
                    width: widths[i],
                    height: _dot,
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        rest,
                        c.brand,
                        (1 - (page - i).abs()).clamp(0.0, 1.0),
                      ),
                      borderRadius: AknRadius.pillAll,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sahnenin arkasındaki yumuşak sıcak ışık: üst yarıda büyük bir radyal parıltı (açık temada `brandSoft`,
/// koyuda `plateTint`), [AknMotion.bandDrift] boyunca hafifçe kayar.
class _StageGlow extends StatelessWidget {
  const _StageGlow();

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final glow = c.isDark ? c.plateTint : c.brandSoft;
    return IgnorePointer(
      child: ExcludeSemantics(
        child: AknAmbient(
          period: AknMotion.bandDrift,
          reverse: true,
          builder: (context, t, _) => DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.35 + 0.5 * t, -0.55 + 0.08 * t),
                radius: 0.95,
                colors: [glow, glow.withValues(alpha: 0)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScenePage extends StatelessWidget {
  const _ScenePage({
    required this.scene,
    required this.step,
    required this.active,
    required this.animate,
    required this.controller,
    required this.current,
  });

  final OnboardingSceneData scene;
  final int step;
  final bool active;
  final bool animate;
  final PageController controller;

  /// Şu an öndeki sayfa (kaydırma konumu henüz yokken).
  final int current;

  /// Sayfanın ortadan uzaklığı (−1 … 1): derinlik ve solma bundan.
  double get _delta {
    if (!animate) return 0;
    final page = controller.hasClients && controller.position.haveDimensions
        ? (controller.page ?? current.toDouble())
        : current.toDouble();
    return (step - page).clamp(-1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    // Ağır minyatür bir kez kurulur; kaydırırken yalnızca öteleme / ölçek / opaklık değişir.
    final miniature = Padding(
      padding: const EdgeInsets.fromLTRB(AknSpace.page, 12, AknSpace.page, 0),
      child: Align(
        alignment: Alignment.center,
        child: Semantics(
          image: true,
          label: scene.description,
          excludeSemantics: true,
          child: AknAmbient(
            period: AknMotion.float,
            reverse: true,
            builder: (context, t, child) =>
                Transform.translate(offset: Offset(0, -3 * t), child: child),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Transform.scale(
                scale: 0.9,
                child: MediaQuery.withNoTextScaling(
                  child: SceneTimeline(
                    active: active,
                    animate: animate,
                    builder: (context, t) => scene.builder(t),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final textMax = constraints.maxHeight * 0.62;
        final width = constraints.maxWidth;
        return Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, area) {
                  if (area.maxHeight < 96 || area.maxWidth < 120) {
                    return const SizedBox.shrink();
                  }
                  // Gerçek arayüzün minyatürü: 0,9 ölçek, alana sığacak kadar küçülür; yazı ölçeği
                  // uygulanmaz (çizimdir, anlamını sahne açıklaması taşır). Sayfa kayarken çizim
                  // sayfadan yavaş kayar (derinlik), küçülür ve solar.
                  return AnimatedBuilder(
                    animation: controller,
                    child: miniature,
                    builder: (context, child) {
                      final d = _delta;
                      return Opacity(
                        opacity: (1 - d.abs() * 0.7).clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset: Offset(-d * width * 0.38, 0),
                          child: Transform.scale(
                            scale: 1 - d.abs() * 0.08,
                            child: child,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: textMax),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AknSpace.page),
                // Yazı sayfadan biraz hızlı kayar ve çabuk solar.
                child: AnimatedBuilder(
                  animation: controller,
                  child: _SceneText(scene: scene, step: step),
                  builder: (context, child) {
                    final d = _delta;
                    return Opacity(
                      opacity: (1 - d.abs() * 1.6).clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(d * width * 0.18, 0),
                        child: child,
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Adım çipi (yumuşak turuncu hap, "Sipariş"), başlık (`display` 28/34 800) ve tek cümle (`body` dim).
class _SceneText extends StatelessWidget {
  const _SceneText({required this.scene, required this.step});

  final OnboardingSceneData scene;
  final int step;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final scaler = MediaQuery.textScalerOf(context);
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: c.brandTone.bg,
              borderRadius: AknRadius.pillAll,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: c.brand,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    scene.eyebrow,
                    textScaler: scaler.clamp(maxScaleFactor: 1.6),
                    style: t.captionStrong.copyWith(color: c.brandInk),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text(
              scene.title,
              style: t.display.copyWith(color: c.ink),
              textScaler: scaler.clamp(maxScaleFactor: 1.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(scene.body, style: t.body.copyWith(color: c.dim)),
        ],
      ),
    );
  }
}

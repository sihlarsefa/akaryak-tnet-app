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

/// İlk açılış tanıtımı (spec A.4 A1; tasarım v2 §7.3): Sipariş → Teklif → Teslimat. Beyaz sayfa; üst
/// yarıda gerçek arayüzün canlı bir minyatürü (0,9 ölçek: sihirbaz özet plakası, teklif plakası ve
/// "Teklifi onayla", » aracıyla rota + adımlar), altında `display` başlık, tek cümle, şerit sayfa
/// göstergesi ve birincil "Devam" / son sayfada "Başlayalım"; sağ üstte sade "Atla". Kaydırarak sayfa
/// değişir, kendiliğinden ilerlemez. Sahneler sayfa öne gelince bir kez oynar; azaltılmış harekette ya da
/// ekran okuyucu açıkken durağan son kare gösterilir. Sayfa göstergesi "Sayfa 1/3" diye okunur.
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

  @override
  Widget build(BuildContext context) {
    final animate = !_staticFrames(context);
    return AppScaffold(
      appBar: false,
      showBell: false,
      showOfflineBanner: false,
      body: SafeArea(
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
                      active: i == _index,
                      animate: animate,
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
                        child: LanePager(
                          count: _count,
                          index: _index,
                          onSelect: _go,
                          showPosition: false,
                          padding: EdgeInsets.zero,
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
    );
  }
}

/// Üst satır: solda 32 px logo karosu, sağda sade "Atla" (44 px, ink).
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSkip});

  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AknSpace.page, 8, 8, 0),
      child: Row(
        children: [
          const LogoMark(size: 32),
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

class _ScenePage extends StatelessWidget {
  const _ScenePage({
    required this.scene,
    required this.active,
    required this.animate,
  });

  final OnboardingSceneData scene;
  final bool active;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textMax = constraints.maxHeight * 0.62;
        return Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, area) {
                  if (area.maxHeight < 96 || area.maxWidth < 120) {
                    return const SizedBox.shrink();
                  }
                  // Gerçek arayüzün minyatürü: 0,9 ölçek, alana sığacak kadar küçülür; yazı ölçeği
                  // uygulanmaz (çizimdir, anlamını sahne açıklaması taşır).
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AknSpace.page,
                      12,
                      AknSpace.page,
                      0,
                    ),
                    child: Align(
                      alignment: Alignment.center,
                      child: Semantics(
                        image: true,
                        label: scene.description,
                        excludeSemantics: true,
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
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: textMax),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: AknSpace.page),
                child: _SceneText(scene: scene),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Başlık (`display` 30/36) ve tek cümle (`body` dim); üst etiket yok.
class _SceneText extends StatelessWidget {
  const _SceneText({required this.scene});

  final OnboardingSceneData scene;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              scene.title,
              style: t.display.copyWith(color: c.ink),
              textScaler: MediaQuery.textScalerOf(
                context,
              ).clamp(maxScaleFactor: 1.6),
            ),
          ),
          const SizedBox(height: 8),
          Text(scene.body, style: t.body.copyWith(color: c.dim)),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    builder: (t) => OrderScene(t: t),
  ),
  OnboardingSceneData(
    eyebrow: OnboardingCopy.quoteEyebrow,
    title: OnboardingCopy.quoteTitle,
    body: OnboardingCopy.quoteBody,
    description: OnboardingCopy.quoteScene,
    builder: (t) => QuoteScene(t: t),
  ),
  OnboardingSceneData(
    eyebrow: OnboardingCopy.deliveryEyebrow,
    title: OnboardingCopy.deliveryTitle,
    body: OnboardingCopy.deliveryBody,
    description: OnboardingCopy.deliveryScene,
    builder: (t) => DeliveryScene(t: t),
  ),
];

/// İlk açılış tanıtımı (spec A.4 A1, F2GO `onboarding_tanitim.dart` yapısı, yeni sahneler): Sipariş →
/// Teklif → Teslimat. Her sayfada "Atla"; son sayfada "Başlayalım". Sahneler sayfa öne gelince bir kez
/// oynar; azaltılmış harekette ya da ekran okuyucu açıkken durağan son kare gösterilir. Sayfa göstergesi
/// "Sayfa 1/3" diye okunur. Degrade, ışık hüzmesi ya da nokta yükleyici yoktur.
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

  void _next() {
    if (_last) {
      _finish();
      return;
    }
    final target = _index + 1;
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

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final animate = !_staticFrames(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AknTheme.overlayOnNavy,
      child: AppScaffold(
        appBar: false,
        showBell: false,
        showOfflineBanner: false,
        backgroundColor: c.navy,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                children: [
                  OnNavy(child: _TopBar(onSkip: _finish)),
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
                  OnNavy(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PageDots(index: _index, count: _count),
                          const SizedBox(height: 16),
                          AknButton(
                            label: _last
                                ? OnboardingCopy.start
                                : OnboardingCopy.next,
                            trailingIcon: _last
                                ? null
                                : Icons.arrow_forward_rounded,
                            expand: true,
                            size: AknButtonSize.large,
                            onPressed: _next,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSkip});

  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 12, 0),
      child: Row(
        children: [
          const LogoMark(size: 36),
          const SizedBox(width: 10),
          const Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: AknWordmark(
                  fontSize: 18,
                  onDark: true,
                  semanticLabel: null,
                ),
              ),
            ),
          ),
          Semantics(
            button: true,
            label: OnboardingCopy.skipSpoken,
            excludeSemantics: true,
            onTap: onSkip,
            child: TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFFFFFF),
                minimumSize: const Size(64, AknSpace.minTap),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                textStyle: t.bodyStrong,
              ),
              child: const Text(OnboardingCopy.skip),
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
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    child: Center(
                      child: Semantics(
                        image: true,
                        label: scene.description,
                        excludeSemantics: true,
                        child: FittedBox(
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
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: textMax),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: OnNavy(child: _SceneText(scene: scene)),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SceneText extends StatelessWidget {
  const _SceneText({required this.scene});

  final OnboardingSceneData scene;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          scene.eyebrow,
          // Lacivert üzerinde marka metni #F08A55 (spec C.5).
          style: t.label.copyWith(color: const Color(0xFFF08A55)),
        ),
        const SizedBox(height: 6),
        Semantics(
          header: true,
          child: Text(scene.title, style: t.title.copyWith(color: c.ink)),
        ),
        const SizedBox(height: 8),
        Text(scene.body, style: t.body.copyWith(color: c.dim)),
      ],
    );
  }
}

/// Sayfa göstergesi: etkin nokta uzar (logo turuncusu, yalnızca süs); okunuşu "Sayfa 1/3".
class _PageDots extends StatelessWidget {
  const _PageDots({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final duration = AknMotion.of(context, AknMotion.base);
    return Semantics(
      label: OnboardingCopy.page(index + 1, count),
      liveRegion: true,
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: duration,
              curve: AknMotion.emphasizedCurve,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == index ? 24 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == index ? c.logo : const Color(0x59FFFFFF),
                borderRadius: AknRadius.pillAll,
              ),
            ),
        ],
      ),
    );
  }
}

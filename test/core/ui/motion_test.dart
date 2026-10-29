import 'dart:async';
import 'dart:math' as math;

import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test_helpers.dart';

class _Counter extends StatefulWidget {
  const _Counter(this.name);

  final String name;

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int n = 0;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => n++),
    child: Text('${widget.name} $n'),
  );
}

void main() {
  test('timings: the base scale and the v3 tokens (§5)', () {
    expect(AknMotion.fast, const Duration(milliseconds: 150));
    expect(AknMotion.base, const Duration(milliseconds: 250));
    expect(AknMotion.slow, const Duration(milliseconds: 400));
    expect(AknMotion.emphasized, const Duration(milliseconds: 600));
    // The home moment: the hero card rises, its figure rolls, the bars grow.
    expect(AknMotion.plateLight, const Duration(milliseconds: 180));
    expect(AknMotion.heroRise, const Duration(milliseconds: 520));
    expect(AknMotion.plateRoll, const Duration(milliseconds: 900));
    expect(AknMotion.barsRise, const Duration(milliseconds: 300));
    expect(AknMotion.barsStagger, const Duration(milliseconds: 40));
    expect(AknMotion.projectionDraw, const Duration(milliseconds: 200));
    // Feedback: every touch scales to 0.97 (100 ms in) and springs back
    // (260 ms); indicators slide on the spring.
    expect(AknMotion.plateHandoff, const Duration(milliseconds: 200));
    expect(AknMotion.deckFly, const Duration(milliseconds: 240));
    expect(AknMotion.deckStep, const Duration(milliseconds: 260));
    expect(AknMotion.press, const Duration(milliseconds: 100));
    expect(AknMotion.pressOut, const Duration(milliseconds: 260));
    expect(AknMotion.pressScale, 0.97);
    expect(AknMotion.stamp, const Duration(milliseconds: 180));
    expect(AknMotion.stageStep, const Duration(milliseconds: 280));
    expect(AknMotion.needle, const Duration(milliseconds: 320));
    expect(AknMotion.thumb, const Duration(milliseconds: 280));
    expect(AknMotion.iconSwap, const Duration(milliseconds: 180));
    expect(AknMotion.routeGlide, const Duration(milliseconds: 400));
    // Transitions: sheets 360 ms emphasized, dialogs 220 ms, toasts drop in
    // on the spring.
    expect(AknMotion.sheet, const Duration(milliseconds: 360));
    expect(AknMotion.dialog, const Duration(milliseconds: 220));
    expect(AknMotion.scrim, const Duration(milliseconds: 220));
    expect(AknMotion.toastIn, const Duration(milliseconds: 320));
    expect(AknMotion.toastOut, const Duration(milliseconds: 200));
    expect(AknMotion.skeletonPulse, const Duration(milliseconds: 1200));
    expect(AknMotion.shimmer, const Duration(milliseconds: 1400));
    // Numbers count; list items enter one after another.
    expect(AknMotion.count, const Duration(milliseconds: 600));
    expect(AknMotion.stagger, const Duration(milliseconds: 520));
    expect(AknMotion.staggerStep, const Duration(milliseconds: 55));
    // v4 §6: the stagger stops after 6 items.
    expect(AknMotion.staggerMaxItems, 6);
    // Ambient loops (AknAmbient).
    expect(AknMotion.bandDrift, const Duration(seconds: 9));
    expect(AknMotion.breathe, const Duration(milliseconds: 1800));
    expect(AknMotion.float, const Duration(milliseconds: 3200));
    // Curves.
    expect(AknMotion.standard, Curves.easeOutCubic);
    expect(AknMotion.emphasizedCurve, const Cubic(0.2, 0, 0, 1));
    expect(AknMotion.exit, Curves.easeInCubic);
    expect(AknMotion.spring, const Cubic(0.34, 1.36, 0.64, 1));
    expect(AknMotion.pop, Curves.easeOutBack);
    expect(AknMotion.fly, Curves.easeIn);
    // The spring overshoots a little (~5 %) and settles exactly.
    var peak = 0.0;
    for (var i = 0; i <= 100; i++) {
      peak = math.max(peak, AknMotion.spring.transform(i / 100));
    }
    expect(peak, inExclusiveRange(1.02, 1.08));
    expect(AknMotion.spring.transform(1), 1);
    // Bars rise 40 ms apart, all within the last 300 ms of the roll.
    expect(AknMotion.barDelay(0), Duration.zero);
    expect(AknMotion.barDelay(5), const Duration(milliseconds: 200));
    expect(AknMotion.barDelay(-1), Duration.zero);
    // List items cascade 55 ms apart; past the sixth they enter together.
    expect(AknMotion.staggerDelay(0), Duration.zero);
    expect(AknMotion.staggerDelay(3), const Duration(milliseconds: 165));
    expect(AknMotion.staggerDelay(40), const Duration(milliseconds: 330));
  });

  test('register roll: v(t) = 1 − (1 − t)^3.2 (§5)', () {
    expect(AknMotion.rollProgress(0), 0);
    expect(AknMotion.rollProgress(1), 1);
    for (final t in [0.05, 0.3, 0.6, 0.9]) {
      final expected = 1 - math.pow(1 - t, 3.2);
      expect(AknMotion.rollProgress(t), closeTo(expected, 1e-12));
      expect(AknMotion.roll.transform(t), closeTo(expected, 1e-12));
    }
    // Fast start, long settle: past half-way after ~20 % of the time.
    expect(AknMotion.rollProgress(0.2), greaterThan(0.5));
    // Monotonic.
    var last = 0.0;
    for (var i = 1; i <= 100; i++) {
      final v = AknMotion.rollProgress(i / 100);
      expect(v, greaterThanOrEqualTo(last));
      last = v;
    }
    expect(AknMotion.rollProgress(2), 1);
  });

  for (final reduce in [false, true]) {
    testWidgets('AknMotion.of under reduceMotion=$reduce', (tester) async {
      late Duration d;
      late bool flag;
      await pumpUi(
        tester,
        Builder(
          builder: (context) {
            d = AknMotion.of(context, AknMotion.slow);
            flag = context.reduceMotion;
            return const SizedBox();
          },
        ),
        reduceMotion: reduce,
      );
      expect(d, reduce ? Duration.zero : AknMotion.slow);
      expect(flag, reduce);
    });
  }

  testWidgets('FadeUp fades, rises and grows in; instant under reduce motion', (
    tester,
  ) async {
    // The hero-card rise (§5): 24 px and from 0.94 over heroRise.
    await pumpUi(
      tester,
      const FadeUp(
        offset: 24,
        scale: 0.94,
        duration: AknMotion.heroRise,
        child: _Counter('Merhaba'),
      ),
    );
    final up = find.byType(FadeUp);
    double opacity() => tester
        .widget<FadeTransition>(
          find.descendant(of: up, matching: find.byType(FadeTransition)).first,
        )
        .opacity
        .value;
    Matrix4 transform(int i) => tester
        .widget<Transform>(
          find.descendant(of: up, matching: find.byType(Transform)).at(i),
        )
        .transform;
    double lift() => transform(0).getTranslation().y;
    double scale() => transform(1).entry(0, 0);

    // First frame: invisible, 24 px low, at 94 %.
    expect(opacity(), 0);
    expect(lift(), 24);
    expect(scale(), closeTo(0.94, 1e-6));
    await tester.pump(AknMotion.heroRise ~/ 4);
    expect(opacity(), inExclusiveRange(0, 1));
    expect(lift(), inExclusiveRange(0, 24));
    expect(scale(), inExclusiveRange(0.94, 1));
    // A tap mid-entrance lands on the child …
    await tester.tap(find.text('Merhaba 0'));
    await tester.pump(AknMotion.heroRise);
    // … in place, at full size, and the child kept its state when the
    // entrance ended (the tree shape never changes).
    expect(opacity(), 1);
    expect(lift(), 0);
    expect(scale(), 1);
    expect(find.text('Merhaba 1'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);

    await pumpUi(
      tester,
      const FadeUp(
        key: ValueKey('r'),
        offset: 24,
        scale: 0.94,
        child: Text('Anında'),
      ),
      reduceMotion: true,
    );
    // Reduce motion: the final frame from the first one; the entrance never
    // runs.
    expect(opacity(), 1);
    expect(lift(), 0);
    expect(scale(), 1);
    final fade = tester.widget<FadeTransition>(
      find.descendant(of: up, matching: find.byType(FadeTransition)).first,
    );
    expect(fade.opacity.status, AnimationStatus.completed);
  });

  testWidgets('StaggerItem: no entrance under reduce motion', (tester) async {
    await pumpUi(
      tester,
      StaggerScope(
        child: Column(children: staggered(const [Text('a'), Text('b')])),
      ),
      reduceMotion: true,
    );
    // The child renders directly: nothing fades, moves or ticks.
    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
    for (final type in [FadeTransition, Opacity, Transform]) {
      expect(
        find.descendant(
          of: find.byType(StaggerItem),
          matching: find.byType(type),
        ),
        findsNothing,
        reason: '$type',
      );
    }
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('StaggerScope / StaggerItem: a cascade, then a scroll reveal', (
    tester,
  ) async {
    final items = ValueNotifier<int>(3);
    addTearDown(items.dispose);
    await pumpUi(
      tester,
      StaggerScope(
        child: ValueListenableBuilder<int>(
          valueListenable: items,
          builder: (context, n, _) => Column(
            children: [
              for (var i = 0; i < n; i++)
                StaggerItem(index: i, child: _Counter('satır $i')),
            ],
          ),
        ),
      ),
    );
    Finder item(int i) =>
        find.byWidgetPredicate((w) => w is StaggerItem && w.index == i);
    double opacity(int i) => tester
        .widget<FadeTransition>(
          find
              .descendant(of: item(i), matching: find.byType(FadeTransition))
              .first,
        )
        .opacity
        .value;
    double lift(int i) => tester
        .widget<Transform>(
          find.descendant(of: item(i), matching: find.byType(Transform)).first,
        )
        .transform
        .getTranslation()
        .y;

    // v3 §5: every item starts hidden, 24 px low …
    for (var i = 0; i < 3; i++) {
      expect(opacity(i), 0, reason: 'item $i');
      expect(lift(i), 24, reason: 'item $i');
    }
    // … and, inside the open scope, they enter one after another
    // (staggerStep apart): the first is on its way while the second still
    // waits its 55 ms.
    await tester.pump(const Duration(milliseconds: 40));
    expect(opacity(0), greaterThan(0));
    expect(opacity(1), 0);
    expect(opacity(2), 0);
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(opacity(2), greaterThan(0));
    expect(opacity(1), greaterThan(opacity(2)));
    expect(opacity(0), greaterThan(opacity(1)));
    expect(lift(0), lessThan(lift(1)));
    expect(lift(1), lessThan(lift(2)));
    // A tap during the entrance lands on the item.
    await tester.tap(find.text('satır 0 0'));

    // Past the entrance: every item in place, and the tapped one kept its
    // state when its entrance ended (the tree shape never changes).
    await tester.pump(AknMotion.stagger);
    for (var i = 0; i < 3; i++) {
      expect(opacity(i), 1, reason: 'item $i');
      expect(lift(i), 0, reason: 'item $i');
    }
    expect(find.text('satır 0 1'), findsOneWidget);
    expect(
      find.descendant(of: item(0), matching: find.byType(FadeTransition)),
      findsOneWidget,
    );
    expect(tester.hasRunningAnimations, isFalse);

    // After the scope's window an item that scrolls in (or the next page)
    // still slides in — at once, without waiting for its index.
    await tester.pump(const Duration(milliseconds: 200));
    items.value = 4;
    await tester.pump();
    expect(opacity(3), 0);
    expect(lift(3), 24);
    await tester.pump(const Duration(milliseconds: 40));
    expect(opacity(3), greaterThan(0));
    expect(lift(3), lessThan(24));
    await tester.pump(AknMotion.stagger);
    expect(opacity(3), 1);
    expect(lift(3), 0);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('AknMotion.animateTo jumps under reduce motion', (tester) async {
    for (final reduce in [true, false]) {
      late AnimationController controller;
      late BuildContext ctx;
      await pumpUi(
        tester,
        _ControllerHost(
          key: ValueKey(reduce),
          onReady: (c, context) {
            controller = c;
            ctx = context;
          },
        ),
        reduceMotion: reduce,
      );
      unawaited(
        AknMotion.animateTo(
          ctx,
          controller,
          1,
          duration: AknMotion.plateRoll,
          curve: AknMotion.roll,
        ),
      );
      await tester.pump();
      if (reduce) {
        expect(controller.value, 1);
        expect(AknMotion.curveOf(ctx, AknMotion.spring), Curves.linear);
      } else {
        expect(controller.value, lessThan(1));
        expect(AknMotion.curveOf(ctx, AknMotion.spring), AknMotion.spring);
        await tester.pump(AknMotion.plateRoll);
        expect(controller.value, 1);
      }
    }
  });

  testWidgets('PressScale: 0.97 while pressed, a spring back; static under '
      'reduce motion', (tester) async {
    await pumpUi(
      tester,
      const Center(
        child: PressScale(
          child: ColoredBox(
            color: Color(0xFFF3F4F6),
            child: SizedBox(width: 100, height: 40),
          ),
        ),
      ),
    );
    final box = find.byType(PressScale);
    final gesture = await tester.startGesture(tester.getCenter(box));
    await tester.pump();
    // v3 §5: the press lands at once (0.97 in 100 ms) …
    var scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scale.scale, AknMotion.pressScale);
    expect(scale.scale, 0.97);
    expect(scale.duration, AknMotion.press);
    expect(scale.curve, AknMotion.standard);
    await gesture.up();
    await tester.pump();
    // … and the release springs back (260 ms, a soft overshoot).
    scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scale.scale, 1);
    expect(scale.duration, AknMotion.pressOut);
    expect(scale.curve, AknMotion.spring);
    await tester.pumpAndSettle();

    await pumpUi(
      tester,
      const Center(
        key: ValueKey('r'),
        child: PressScale(
          child: ColoredBox(
            color: Color(0xFFF3F4F6),
            child: SizedBox(width: 100, height: 40),
          ),
        ),
      ),
      reduceMotion: true,
    );
    final g2 = await tester.startGesture(
      tester.getCenter(find.byType(PressScale)),
    );
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    await g2.up();
  });

  testWidgets('Shimmer is static under reduce motion', (tester) async {
    await pumpUi(
      tester,
      const Shimmer(child: SkeletonBox(width: 100)),
      reduceMotion: true,
    );
    await tester.pump(const Duration(milliseconds: 100));
    // Nothing ticks: no frame is scheduled after the first one.
    expect(tester.binding.hasScheduledFrame, isFalse);

    await pumpUi(
      tester,
      const Shimmer(key: ValueKey('s'), child: SkeletonBox(width: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    // With motion on, the loading shimmer sweeps (v3 §5, while loading).
    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets('FadeThroughIndexedStack keeps every tab state', (tester) async {
    final index = ValueNotifier<int>(0);
    await pumpUi(
      tester,
      ValueListenableBuilder<int>(
        valueListenable: index,
        builder: (context, i, _) => FadeThroughIndexedStack(
          index: i,
          children: const [_Counter('A'), _Counter('B')],
        ),
      ),
    );
    await tester.tap(find.text('A 0'));
    await tester.pump();
    expect(find.text('A 1'), findsOneWidget);

    index.value = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('B 0'), findsOneWidget);
    // Offstage tab is not hit-testable.
    expect(find.text('A 1').hitTestable(), findsNothing);

    index.value = 0;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('A 1'), findsOneWidget);
  });

  for (final reduce in [false, true]) {
    testWidgets(
      'Android page transition: predictive back (reduceMotion=$reduce)',
      (tester) async {
        final key = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: key,
            theme: AknTheme.light().copyWith(platform: TargetPlatform.android),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduce),
              child: child!,
            ),
            home: const Scaffold(body: Text('Liste')),
          ),
        );
        unawaited(
          key.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Detay')),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        // Yeni sayfa hemen görünür; azaltılmış harekette solma yok.
        expect(find.text('Detay'), findsOneWidget);
        if (reduce) {
          expect(
            find.ancestor(
              of: find.text('Detay'),
              matching: find.byType(FadeTransition),
            ),
            findsNothing,
          );
        }
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('Detay'), findsOneWidget);
        expect(find.text('Liste'), findsNothing);
      },
    );
  }

  testWidgets('SharedAxisSwitcher swaps keyed children', (tester) async {
    final step = ValueNotifier<int>(0);
    await pumpUi(
      tester,
      ValueListenableBuilder<int>(
        valueListenable: step,
        builder: (context, s, _) =>
            SharedAxisSwitcher(child: Text('Adım $s', key: ValueKey(s))),
      ),
    );
    step.value = 1;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Adım 0'), findsOneWidget);
    expect(find.text('Adım 1'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Adım 0'), findsNothing);
    expect(find.text('Adım 1'), findsOneWidget);
  });

  testWidgets('AknOpenContainer opens the detail and closes back', (
    tester,
  ) async {
    await pumpUi(
      tester,
      AknOpenContainer<void>(
        closedBuilder: (context, open) =>
            TextButton(onPressed: open, child: const Text('Kart')),
        openBuilder: (context, close) => Scaffold(
          body: TextButton(onPressed: close, child: const Text('Ayrıntı')),
        ),
      ),
    );
    await tester.tap(find.text('Kart'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Ayrıntı'), findsOneWidget);
    await tester.tap(find.text('Ayrıntı'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Ayrıntı'), findsNothing);
    expect(find.text('Kart'), findsOneWidget);
  });

  testWidgets('MorphHero and AknHero fly list → detail without errors', (
    tester,
  ) async {
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        theme: AknTheme.light().copyWith(platform: TargetPlatform.android),
        home: Scaffold(
          body: Column(
            children: [
              MorphHero(
                tag: AknHeroTags.orderCard(7),
                child: const SizedBox(height: 80, child: Text('SP-7 kart')),
              ),
              AknHero(
                tag: AknHeroTags.orderStatus(7),
                child: StatusChip.style(
                  AknStatus.custom('Onay bekleniyor', tone: 'warn'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    unawaited(
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: Column(
              children: [
                MorphHero(
                  tag: AknHeroTags.orderCard(7),
                  radius: AknMorphRadius.header,
                  child: const SizedBox(
                    height: 200,
                    child: Text('SP-7 ayrıntı'),
                  ),
                ),
                AknHero(
                  tag: AknHeroTags.orderStatus(7),
                  child: StatusChip.style(
                    AknStatus.custom('Onay bekleniyor', tone: 'warn'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    }
    expect(find.text('SP-7 ayrıntı'), findsOneWidget);
    nav.currentState!.pop();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    }
    expect(find.text('SP-7 kart'), findsOneWidget);
  });
}

class _ControllerHost extends StatefulWidget {
  const _ControllerHost({super.key, required this.onReady});

  final void Function(AnimationController controller, BuildContext context)
  onReady;

  @override
  State<_ControllerHost> createState() => _ControllerHostState();
}

class _ControllerHostState extends State<_ControllerHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.onReady(_c, context);
    return const SizedBox();
  }
}

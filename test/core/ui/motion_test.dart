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
  test('timings: the base scale and the v2 tokens (§8)', () {
    expect(AknMotion.fast, const Duration(milliseconds: 150));
    expect(AknMotion.base, const Duration(milliseconds: 250));
    expect(AknMotion.slow, const Duration(milliseconds: 400));
    expect(AknMotion.emphasized, const Duration(milliseconds: 600));
    // The one orchestrated moment (§8.1).
    expect(AknMotion.plateLight, const Duration(milliseconds: 180));
    expect(AknMotion.plateRoll, const Duration(milliseconds: 900));
    expect(AknMotion.barsRise, const Duration(milliseconds: 300));
    expect(AknMotion.barsStagger, const Duration(milliseconds: 40));
    expect(AknMotion.projectionDraw, const Duration(milliseconds: 200));
    // Feedback (§8.2).
    expect(AknMotion.plateHandoff, const Duration(milliseconds: 200));
    expect(AknMotion.deckFly, const Duration(milliseconds: 240));
    expect(AknMotion.deckStep, const Duration(milliseconds: 220));
    expect(AknMotion.press, const Duration(milliseconds: 90));
    expect(AknMotion.pressOut, const Duration(milliseconds: 120));
    expect(AknMotion.pressScale, 0.98);
    expect(AknMotion.stamp, const Duration(milliseconds: 160));
    expect(AknMotion.stageStep, const Duration(milliseconds: 240));
    expect(AknMotion.needle, const Duration(milliseconds: 200));
    expect(AknMotion.thumb, const Duration(milliseconds: 220));
    expect(AknMotion.routeGlide, const Duration(milliseconds: 400));
    expect(AknMotion.sheet, const Duration(milliseconds: 250));
    expect(AknMotion.scrim, const Duration(milliseconds: 200));
    expect(AknMotion.toastIn, const Duration(milliseconds: 200));
    expect(AknMotion.toastOut, const Duration(milliseconds: 150));
    expect(AknMotion.skeletonPulse, const Duration(milliseconds: 1200));
    expect(AknMotion.fly, Curves.easeIn);
    // Bars rise 40 ms apart, all within the last 300 ms of the roll.
    expect(AknMotion.barDelay(0), Duration.zero);
    expect(AknMotion.barDelay(5), const Duration(milliseconds: 200));
    expect(AknMotion.barDelay(-1), Duration.zero);
    // Deprecated (kept for API stability).
    expect(AknMotion.staggerDelay(3), const Duration(milliseconds: 90));
    expect(AknMotion.staggerDelay(40), const Duration(milliseconds: 240));
  });

  test('register roll: v(t) = 1 − (1 − t)^3.2 (§8.1)', () {
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

  testWidgets('FadeUp animates in, and is instant under reduce motion', (
    tester,
  ) async {
    await pumpUi(tester, const FadeUp(child: Text('Merhaba')));
    final early = tester.widget<Opacity>(
      find.ancestor(of: find.text('Merhaba'), matching: find.byType(Opacity)),
    );
    expect(early.opacity, lessThan(1));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.ancestor(of: find.text('Merhaba'), matching: find.byType(Opacity)),
      findsNothing,
    );

    await pumpUi(
      tester,
      const FadeUp(key: ValueKey('r'), child: Text('Anında')),
      reduceMotion: true,
    );
    expect(
      find.ancestor(of: find.text('Anında'), matching: find.byType(Opacity)),
      findsNothing,
    );
  });

  testWidgets('StaggerItem: no entrance under reduce motion', (tester) async {
    await pumpUi(
      tester,
      StaggerScope(
        child: Column(children: staggered(const [Text('a'), Text('b')])),
      ),
      reduceMotion: true,
    );
    expect(find.byType(FadeUp), findsNothing);
  });

  testWidgets('StaggerScope / StaggerItem: no list entrances in v2 (§8.3)', (
    tester,
  ) async {
    final items = ValueNotifier<int>(2);
    await pumpUi(
      tester,
      StaggerScope(
        child: ValueListenableBuilder<int>(
          valueListenable: items,
          builder: (context, n, _) => Column(
            children: [
              for (var i = 0; i < n; i++)
                StaggerItem(index: i, child: Text('satır $i')),
            ],
          ),
        ),
      ),
    );
    // Items render at once: no fade, no lift.
    expect(find.byType(FadeUp), findsNothing);
    expect(find.text('satır 1'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('satır 0'), matching: find.byType(Opacity)),
      findsNothing,
    );
    expect(
      find.ancestor(of: find.text('satır 0'), matching: find.byType(Transform)),
      findsNothing,
    );
    items.value = 3;
    await tester.pump();
    expect(find.text('satır 2'), findsOneWidget);
    expect(find.byType(FadeUp), findsNothing);
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

  testWidgets('PressScale: 0.98 while pressed, static under reduce motion', (
    tester,
  ) async {
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
    var scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scale.scale, AknMotion.pressScale);
    expect(scale.duration, AknMotion.press);
    await gesture.up();
    await tester.pump();
    scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scale.scale, 1);
    expect(scale.duration, AknMotion.pressOut);
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
    // With motion on, the loading pulse runs.
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

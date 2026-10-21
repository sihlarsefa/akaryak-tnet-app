import 'dart:async';

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
  test('timings follow spec C.6', () {
    expect(AknMotion.fast, const Duration(milliseconds: 150));
    expect(AknMotion.base, const Duration(milliseconds: 250));
    expect(AknMotion.slow, const Duration(milliseconds: 400));
    expect(AknMotion.emphasized, const Duration(milliseconds: 600));
    expect(AknMotion.staggerDelay(0), Duration.zero);
    expect(AknMotion.staggerDelay(3), const Duration(milliseconds: 90));
    expect(AknMotion.staggerDelay(8), const Duration(milliseconds: 240));
    expect(AknMotion.staggerDelay(40), const Duration(milliseconds: 240));
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

  testWidgets('StaggerScope: only the first screenful animates', (
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
    expect(find.byType(FadeUp), findsNWidgets(2));
    await tester.pump(const Duration(seconds: 2));
    items.value = 3;
    await tester.pump();
    // The late item appears without an entrance.
    expect(
      find.ancestor(of: find.text('satır 2'), matching: find.byType(FadeUp)),
      findsNothing,
    );
  });

  testWidgets('Shimmer is static under reduce motion', (tester) async {
    await pumpUi(
      tester,
      const Shimmer(child: SkeletonBox(width: 100)),
      reduceMotion: true,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ShaderMask), findsNothing);

    await pumpUi(
      tester,
      const Shimmer(key: ValueKey('s'), child: SkeletonBox(width: 100)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(ShaderMask), findsOneWidget);
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

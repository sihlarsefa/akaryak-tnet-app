// Redesign R1 components: hero app bar + header strip, status-bar icons per surface, AnimatedNumber,
// floating bottom bar, button variants, card press.
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test_helpers.dart';

/// The style the framework last applied to the system bars (the status bar
/// follows the AnnotatedRegion at the top of the screen, the navigation bar
/// the one at the bottom).
SystemUiOverlayStyle _applied() => SystemChrome.latestStyle!;

Widget _page({
  required bool hero,
  bool navy = false,
  bool refreshing = false,
}) => AppScaffold(
  hero: hero,
  navy: navy,
  title: 'Siparişler',
  refreshing: refreshing,
  body: ListView(
    padding: EdgeInsets.zero,
    children: [
      if (hero || navy)
        const AknHeroHeader(
          title: 'Günaydın, Ayşe',
          subtitle: 'Demo Petrol',
          chips: [AknHeroChip(label: 'Sahip')],
        ),
      for (var i = 0; i < 30; i++) ListTile(title: Text('Satır $i')),
    ],
  ),
);

void main() {
  group('AppScaffold', () {
    testBothThemes('white app bar: ink title w800, surface background', (
      tester,
      b,
    ) async {
      await pumpUi(tester, _page(hero: false), brightness: b, scaffold: false);
      final c = b == Brightness.dark ? AknColors.dark : AknColors.light;
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.backgroundColor, c.surface);
      expect(bar.systemOverlayStyle, AknTheme.overlayFor(b));
      final title = tester.widget<Text>(find.text('Siparişler'));
      expect(title.style!.color, c.ink);
      expect(title.style!.fontWeight, FontWeight.w800);
      expect(find.byType(OnHero), findsNothing);
    });

    testWidgets('white app bar: hairline + shadow fade in once scrolled', (
      tester,
    ) async {
      await pumpUi(tester, _page(hero: false), scaffold: false);
      double edge() => tester
          .widget<AnimatedOpacity>(
            find.descendant(
              of: find.byType(AppScaffold),
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity;
      expect(edge(), 0);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(edge(), 1);
      await tester.drag(find.byType(ListView), const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(edge(), 0);
    });

    for (final navy in [false, true]) {
      testBothThemes(
        '${navy ? 'navy (alias)' : 'hero'}: orange strip, white title, light status icons',
        (tester, b) async {
          await pumpUi(
            tester,
            _page(hero: !navy, navy: navy),
            brightness: b,
            scaffold: false,
          );
          final bar = tester.widget<AppBar>(find.byType(AppBar));
          expect(bar.systemOverlayStyle, AknTheme.overlayOnHero);
          expect(bar.backgroundColor, const Color(0x00000000));
          // The strip gradient paints behind the bar and the header block.
          final strips = tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .map((p) => p.painter)
              .whereType<HeroBackdropPainter>()
              .where((p) => p.style == AknHeroStyle.strip);
          expect(strips.length, greaterThanOrEqualTo(2));
          final title = tester.widget<Text>(find.text('Siparişler'));
          expect(title.style!.color, const Color(0xFFFFFFFF));
          final greeting = tester.widget<Text>(find.text('Günaydın, Ayşe'));
          expect(greeting.style!.color, const Color(0xFFFFFFFF));
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('hero refresh bar is white, inside the orange bar', (
      tester,
    ) async {
      await pumpUi(
        tester,
        _page(hero: true, refreshing: true),
        scaffold: false,
      );
      await tester.pump(const Duration(milliseconds: 300));
      final bars = tester.widgetList<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bars, hasLength(1));
      expect(bars.single.color, const Color(0xFFFFFFFF));
      final rect = tester.getRect(find.byType(LinearProgressIndicator));
      final barRect = tester.getRect(find.byType(AppBar));
      expect(rect.bottom, closeTo(barRect.bottom, 0.5));
    });

    testWidgets('status bar: light icons on the orange bar, dark on white', (
      tester,
    ) async {
      await pumpUi(tester, _page(hero: true), scaffold: false);
      await tester.pump();
      expect(_applied().statusBarIconBrightness, Brightness.light);
      expect(_applied().statusBarBrightness, Brightness.dark);
      // The page below the bar is light: dark navigation-bar icons.
      expect(_applied().systemNavigationBarIconBrightness, Brightness.dark);
      await pumpUi(tester, _page(hero: false), scaffold: false);
      await tester.pump();
      expect(_applied().statusBarIconBrightness, Brightness.dark);
      expect(_applied().statusBarBrightness, Brightness.light);
      expect(_applied().systemNavigationBarIconBrightness, Brightness.dark);
    });

    testWidgets('dark mode: light status icons on the white-bar pages too', (
      tester,
    ) async {
      await pumpUi(
        tester,
        _page(hero: false),
        scaffold: false,
        brightness: Brightness.dark,
      );
      await tester.pump();
      expect(_applied().statusBarIconBrightness, Brightness.light);
      expect(_applied().systemNavigationBarIconBrightness, Brightness.light);
    });

    testWidgets('hero: pulling down fills the gap with the strip', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await pumpUi(tester, _page(hero: true), scaffold: false);
      final header = tester.getRect(find.byType(AknHeroHeader));
      final gesture = await tester.startGesture(header.center);
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump();
      final moved = tester.getRect(find.byType(AknHeroHeader));
      expect(moved.top, greaterThan(header.top));
      final band = find.byWidgetPredicate(
        (w) =>
            w is SizedBox &&
            w.child is AknHeroBackground &&
            (w.height ?? 0) > 0,
      );
      expect(band, findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('AknHeroHeader', () {
    testBothThemes('greeting is a header; chips are white on dark glass', (
      tester,
      b,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpUi(
        tester,
        const AknHeroHeader(
          title: 'Günaydın, Ayşe',
          subtitle: 'Demo Petrol',
          chips: [
            AknHeroChip(label: 'Sahip', icon: Icons.verified_user_rounded),
            AknHeroChip(label: 'Finans'),
          ],
        ),
        brightness: b,
      );
      expect(
        tester.getSemantics(find.text('Günaydın, Ayşe')),
        isSemantics(isHeader: true, label: 'Günaydın, Ayşe'),
      );
      final chip = tester.widget<Text>(find.text('Sahip'));
      expect(chip.style!.color, const Color(0xFFFFFFFF));
      final box = tester.widget<Container>(
        find
            .ancestor(of: find.text('Finans'), matching: find.byType(Container))
            .first,
      );
      final deco = box.decoration! as BoxDecoration;
      expect(deco.color, OnHero.glassStrong);
      // 28 px rounded bottom edge.
      final clip = tester.widget<ClipRRect>(
        find
            .descendant(
              of: find.byType(AknHeroHeader),
              matching: find.byType(ClipRRect),
            )
            .first,
      );
      expect(clip.borderRadius, AknRadius.header);
      handle.dispose();
    });

    testWidgets('topInset runs under the status bar with light icons', (
      tester,
    ) async {
      tester.view.padding = const FakeViewPadding(top: 72);
      addTearDown(tester.view.resetPadding);
      await pumpUi(
        tester,
        const AknHeroHeader(title: 'Merhaba', topInset: true),
        scaffold: false,
      );
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find
            .ancestor(
              of: find.text('Merhaba'),
              matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
            )
            .first,
      );
      expect(region.value, AknTheme.overlayOnHero);
      expect(tester.getTopLeft(find.text('Merhaba')).dy, greaterThan(24));
    });

    testWidgets('a tappable hero chip has a 48 dp target and a label', (
      tester,
    ) async {
      var taps = 0;
      final handle = tester.ensureSemantics();
      await pumpUi(
        tester,
        AknHeroPanel(
          child: AknHeroChip(
            label: '3 teklif',
            semanticLabel: '3 teklif bekliyor',
            onTap: () => taps++,
          ),
        ),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      tester.semantics.tap(find.semantics.byLabel('3 teklif bekliyor'));
      expect(taps, 1);
      handle.dispose();
    });
  });

  group('AnimatedNumber', () {
    testWidgets(
      'counts up to the formatted value, screen readers hear it once',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpUi(
          tester,
          AnimatedNumber(value: 12500, format: (v) => '${v.round()} L'),
        );
        await tester.pump(const Duration(milliseconds: 60));
        expect(find.text('12500 L'), findsNothing);
        expect(find.bySemanticsLabel('12500 L'), findsOneWidget);
        await tester.pump(AknMotion.count);
        expect(find.text('12500 L'), findsOneWidget);
        handle.dispose();
      },
    );

    testWidgets('integers count in whole steps; default format groups', (
      tester,
    ) async {
      await pumpUi(tester, const AnimatedNumber(value: 1234567));
      await tester.pump(const Duration(milliseconds: 120));
      final mid = tester.widget<Text>(find.byType(Text)).data!;
      expect(mid, isNot(contains(',')));
      await tester.pump(AknMotion.count);
      expect(find.text('1.234.567'), findsOneWidget);
      final style = tester.widget<Text>(find.byType(Text)).style!;
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(style.fontWeight, FontWeight.w800);
    });

    testWidgets('reduce motion shows the value at once', (tester) async {
      await pumpUi(
        tester,
        const AnimatedNumber(value: 640),
        reduceMotion: true,
      );
      await tester.pump();
      expect(find.text('640'), findsOneWidget);
    });

    testWidgets('a new value counts on from the value on screen', (
      tester,
    ) async {
      var value = 100;
      await pumpUi(
        tester,
        StatefulBuilder(
          builder: (context, set) => GestureDetector(
            onTap: () => set(() => value = 200),
            child: AnimatedNumber(value: value),
          ),
        ),
      );
      await tester.pump(AknMotion.count);
      expect(find.text('100'), findsOneWidget);
      await tester.tap(find.byType(AnimatedNumber));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final mid = int.parse(tester.widget<Text>(find.byType(Text)).data!);
      expect(mid, inInclusiveRange(101, 199));
      await tester.pump(AknMotion.count);
      expect(find.text('200'), findsOneWidget);
    });
  });

  group('AnimatedBottomBar', () {
    Widget bar({int badge = 3, AknCenterAction? center}) => Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedBottomBar(
        currentIndex: 0,
        onSelected: (_) {},
        centerAction: center,
        items: [
          const AknNavItem(icon: Icons.home_rounded, label: 'Ana sayfa'),
          AknNavItem(
            icon: Icons.task_alt_rounded,
            label: 'Onaylarım',
            badgeCount: badge,
          ),
          const AknNavItem(
            icon: Icons.receipt_long_rounded,
            label: 'Siparişler',
          ),
          const AknNavItem(icon: Icons.more_horiz_rounded, label: 'Diğer'),
        ],
      ),
    );

    testBothThemes('floating capsule: 12 dp side inset, red badge', (
      tester,
      b,
    ) async {
      await pumpUi(tester, bar(), brightness: b, size: const Size(390, 800));
      await tester.pump(const Duration(milliseconds: 400));
      final paint = tester.getRect(
        find
            .descendant(
              of: find.byType(AnimatedBottomBar),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      expect(paint.left, 12);
      expect(paint.right, 390 - 12);
      final c = b == Brightness.dark ? AknColors.dark : AknColors.light;
      final badge = tester.widget<Container>(
        find
            .ancestor(of: find.text('3'), matching: find.byType(Container))
            .first,
      );
      expect((badge.decoration! as BoxDecoration).color, c.dangerFill);
      expect(tester.takeException(), isNull);
    });

    testWidgets('selected label is orange text (AA), others dim', (
      tester,
    ) async {
      await pumpUi(tester, bar(badge: 0));
      await tester.pump(const Duration(milliseconds: 400));
      final style = tester
          .widget<AnimatedDefaultTextStyle>(
            find
                .ancestor(
                  of: find.text('Ana sayfa'),
                  matching: find.byType(AnimatedDefaultTextStyle),
                )
                .first,
          )
          .style;
      expect(style.color, AknColors.light.brandInk);
      final other = tester
          .widget<AnimatedDefaultTextStyle>(
            find
                .ancestor(
                  of: find.text('Siparişler'),
                  matching: find.byType(AnimatedDefaultTextStyle),
                )
                .first,
          )
          .style;
      expect(other.color, AknColors.light.dim);
    });

    testWidgets('center action still works with the capsule notch', (
      tester,
    ) async {
      var opened = 0;
      await pumpUi(
        tester,
        bar(
          center: AknCenterAction(
            icon: Icons.add_rounded,
            label: 'Sipariş ver',
            onPressed: () => opened++,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Sipariş ver'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(opened, 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('Buttons and cards', () {
    testWidgets('variants: primary fill, tonal secondary, neutral outline', (
      tester,
    ) async {
      await pumpUi(
        tester,
        Column(
          children: [
            AknButton(label: 'Gönder', onPressed: () {}),
            AknButton.secondary(label: 'Revize', onPressed: () {}),
            AknButton.outline(label: 'Vazgeç', onPressed: () {}),
          ],
        ),
      );
      BoxDecoration deco(String label) =>
          tester
                  .widget<AnimatedContainer>(
                    find
                        .ancestor(
                          of: find.text(label),
                          matching: find.byType(AnimatedContainer),
                        )
                        .first,
                  )
                  .decoration!
              as BoxDecoration;
      const c = AknColors.light;
      expect(deco('Gönder').color, c.brandFill);
      expect(deco('Gönder').borderRadius, BorderRadius.circular(14));
      expect(deco('Revize').color, c.brandSoft);
      expect(deco('Revize').border, isNull);
      expect(deco('Vazgeç').color, c.surface);
      expect((deco('Vazgeç').border! as Border).top.color, c.lineStrong);
      expect(tester.getSize(find.byType(AknButton).first).height, 52);
      final label = tester.widget<Text>(find.text('Revize'));
      expect(label.style!.color, c.brandInk);
    });

    testWidgets('confirm sheet: neutral outline cancel next to the action', (
      tester,
    ) async {
      await pumpUi(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showConfirmSheet(context, title: 'Emin misiniz?'),
            child: const Text('aç'),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      final cancel = tester.widget<AknButton>(
        find.widgetWithText(AknButton, 'Vazgeç'),
      );
      expect(cancel.variant, AknButtonVariant.outline);
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
    });

    testWidgets('tappable card: selection haptic, scale + shadow on press', (
      tester,
    ) async {
      final haptics = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      var taps = 0;
      await pumpUi(
        tester,
        Padding(
          padding: const EdgeInsets.all(16),
          child: AknCard(onTap: () => taps++, child: const Text('Kart')),
        ),
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Kart')),
      );
      await tester.pump(const Duration(milliseconds: 200));
      final scale = tester.widget<AnimatedScale>(
        find
            .ancestor(
              of: find.text('Kart'),
              matching: find.byType(AnimatedScale),
            )
            .first,
      );
      expect(scale.scale, 0.985);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 200));
      expect(taps, 1);
      expect(haptics, contains('HapticFeedbackType.selectionClick'));
      // Light mode: soft diffuse shadow, 20 px radius.
      final box = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text('Kart'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      final deco = box.decoration! as BoxDecoration;
      expect(deco.borderRadius, BorderRadius.circular(20));
      expect(deco.boxShadow, isNotEmpty);
    });

    testWidgets('filter pills: selected is a solid orange pill, white label', (
      tester,
    ) async {
      await pumpUi(
        tester,
        FilterChips<int>(
          options: const [
            FilterOption(value: 1, label: 'Bekleyen'),
            FilterOption(value: 2, label: 'Biten'),
          ],
          selected: const {1},
          onChanged: (_) {},
        ),
      );
      final label = tester.widget<Text>(find.text('Bekleyen'));
      expect(label.style!.color, AknColors.light.onBrandFill);
      final other = tester.widget<Text>(find.text('Biten'));
      expect(other.style!.color, AknColors.light.text);
      expect(
        contrast(AknColors.light.onBrandFill, AknColors.light.brandFill),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  testWidgets('hero panel passes the text contrast guideline (light + dark)', (
    tester,
  ) async {
    for (final b in Brightness.values) {
      final handle = tester.ensureSemantics();
      await pumpUi(
        tester,
        ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AknHeroPanel(
              child: Builder(
                builder: (context) {
                  final t = context.aknText;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SP-2026-0142', style: t.title),
                      Text('Motorin · 12.500 L', style: t.headline),
                      Text('Demo Petrol · 21.10.2026', style: t.bodySmall),
                      Text('Karar bekliyor', style: t.caption),
                      const SizedBox(height: 8),
                      const KpiRow(
                        children: [
                          KpiTile(label: 'Bekleyen', value: 3),
                          KpiTile(label: 'Bu ay', value: 12),
                        ],
                      ),
                      const SizedBox(height: 8),
                      AknButton(label: 'Sipariş ver', onPressed: () {}),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            const AknHeroHeader(
              title: 'Günaydın, Ayşe',
              subtitle: 'Demo Petrol · Kartal',
              chips: [AknHeroChip(label: 'Sahip')],
            ),
          ],
        ),
        brightness: b,
        size: const Size(360, 900),
      );
      await tester.pump(const Duration(seconds: 1));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    }
  });
}

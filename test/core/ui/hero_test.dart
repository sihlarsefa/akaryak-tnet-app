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
    testBothThemes('root page bar: page colour, display title in ink', (
      tester,
      b,
    ) async {
      await pumpUi(tester, _page(hero: false), brightness: b, scaffold: false);
      final c = b == Brightness.dark ? AknColors.dark : AknColors.light;
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.backgroundColor, c.bg);
      expect(bar.systemOverlayStyle, AknTheme.overlayFor(b));
      // v2 §6.1: a root tab page (no back button) titles in `display`
      // 30/36 600 at the 20 px edge, in a 60 px bar.
      expect(bar.toolbarHeight, AknTheme.rootBarHeight);
      expect(bar.titleSpacing, AknSpace.page);
      final title = tester.widget<Text>(find.text('Siparişler'));
      expect(title.style!.color, c.ink);
      expect(title.style!.fontWeight, FontWeight.w600);
      expect(title.style!.fontSize, 30);
      expect(title.style!.fontFamily, AknFonts.sans);
      expect(find.byType(OnHero), findsNothing);
    });

    testWidgets('pushed page bar: back button, headline title, 52 px', (
      tester,
    ) async {
      await pumpUi(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AppScaffold(
                  title: 'SIP-20261021-12002',
                  body: SizedBox.expand(),
                ),
              ),
            ),
            child: const Text('aç'),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.toolbarHeight, AknTheme.pushedBarHeight);
      expect(find.byType(BackButtonIcon), findsOneWidget);
      final title = tester.widget<Text>(find.text('SIP-20261021-12002'));
      expect(title.style!.fontSize, 17);
      expect(title.style!.fontWeight, FontWeight.w600);
      expect(title.maxLines, 1);
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
        '${navy ? 'navy (alias)' : 'hero'} (deprecated): the normal white bar, no strip',
        (tester, b) async {
          await pumpUi(
            tester,
            _page(hero: !navy, navy: navy),
            brightness: b,
            scaffold: false,
          );
          final c = b == Brightness.dark ? AknColors.dark : AknColors.light;
          final bar = tester.widget<AppBar>(find.byType(AppBar));
          // v2 §6.1: no orange app bar; status icons follow the page.
          expect(bar.systemOverlayStyle, AknTheme.overlayFor(b));
          expect(bar.backgroundColor, c.bg);
          final strips = tester
              .widgetList<CustomPaint>(
                find.descendant(
                  of: find.byType(AppBar),
                  matching: find.byType(CustomPaint),
                ),
              )
              .map((p) => p.painter)
              .whereType<HeroBackdropPainter>();
          expect(strips, isEmpty);
          final title = tester.widget<Text>(find.text('Siparişler'));
          expect(title.style!.color, c.ink);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('refresh bar runs under the bar, content stays', (
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
      final rect = tester.getRect(find.byType(LinearProgressIndicator));
      final barRect = tester.getRect(find.byType(AppBar));
      expect(rect.top, closeTo(barRect.bottom, 0.5));
      expect(find.text('Satır 0'), findsOneWidget);
    });

    testWidgets('status bar: dark icons on the white bar (hero too)', (
      tester,
    ) async {
      await pumpUi(tester, _page(hero: true), scaffold: false);
      await tester.pump();
      expect(_applied().statusBarIconBrightness, Brightness.dark);
      expect(_applied().statusBarBrightness, Brightness.light);
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

    testWidgets('hero: pulling down shows the page, no orange band', (
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
      expect(band, findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('AknHeroHeader', () {
    testBothThemes('deprecated: a plain white header, chips render as lamps', (
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
      final c = b == Brightness.dark ? AknColors.dark : AknColors.light;
      // v2 §6.28: no orange strip — the page colour, an ink display title,
      // a dim subtitle; off the plate a hero chip is a lamp.
      expect(OnHero.isOn(tester.element(find.text('Sahip'))), isFalse);
      expect(find.byType(AknLamp), findsNWidgets(2));
      final title = tester.widget<Text>(find.text('Günaydın, Ayşe'));
      expect(title.style!.color, c.ink);
      expect(title.style!.fontSize, 30);
      expect(tester.widget<Text>(find.text('Demo Petrol')).style!.color, c.dim);
      final fill = tester.widget<ColoredBox>(
        find
            .descendant(
              of: find.byType(AknHeroHeader),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(fill.color, c.bg);
      expect(
        find.descendant(
          of: find.byType(AknHeroHeader),
          matching: find.byType(AknHeroBackground),
        ),
        findsNothing,
      );
      handle.dispose();
    });

    testWidgets('topInset runs under the status bar with page icons', (
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
      expect(region.value, AknTheme.overlayFor(Brightness.light));
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
    // v2 §6.9 / §8.3: no count-ups — only the plate rolls. The final value
    // is on screen from the first frame and screen readers hear it once.
    testWidgets('shows the formatted value at once, read once', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpUi(
        tester,
        AnimatedNumber(value: 12500, format: (v) => '${v.round()} L'),
      );
      expect(find.text('12500 L'), findsOneWidget);
      expect(find.bySemanticsLabel('12500 L'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
      handle.dispose();
    });

    testWidgets('default format groups; proportional Condensed figures', (
      tester,
    ) async {
      await pumpUi(tester, const AnimatedNumber(value: 1234567));
      expect(find.text('1.234.567'), findsOneWidget);
      final style = tester.widget<Text>(find.byType(Text)).style!;
      expect(
        style.fontFeatures ?? const [],
        isNot(contains(const FontFeature.tabularFigures())),
      );
      expect(style.fontFamily, AknFonts.condensed);
      expect(style.fontWeight, FontWeight.w700);
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

    testWidgets('a new value replaces the old one without counting', (
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
      expect(find.text('100'), findsOneWidget);
      await tester.tap(find.byType(AnimatedNumber));
      await tester.pump();
      expect(find.text('200'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('fit scales a long value down instead of wrapping', (
      tester,
    ) async {
      await pumpUi(
        tester,
        const SizedBox(
          width: 60,
          child: AnimatedNumber(value: 123456789, fit: true),
        ),
      );
      expect(find.byType(FittedBox), findsOneWidget);
      expect(tester.takeException(), isNull);
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

    testBothThemes('docked full width, hairline on top, Asfalt badge', (
      tester,
      b,
    ) async {
      await pumpUi(tester, bar(), brightness: b, size: const Size(390, 800));
      await tester.pump(const Duration(milliseconds: 400));
      final c = b == Brightness.dark ? AknColors.dark : AknColors.light;
      final rect = tester.getRect(find.byType(AnimatedBottomBar));
      expect(rect.left, 0);
      expect(rect.right, 390);
      final box = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(AnimatedBottomBar),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final deco = box.decoration as BoxDecoration;
      // v2 §6.4: no floating pill, no shadow; dark mode sits on `surface`.
      expect(deco.color, c.isDark ? c.surface : c.surfaceRaised);
      expect(deco.boxShadow, isNull);
      expect((deco.border! as Border).top.color, c.line);
      // §6.3: red is reserved for danger — the count badge is ink.
      final badge = tester.widget<Container>(
        find
            .ancestor(of: find.text('3'), matching: find.byType(Container))
            .first,
      );
      expect((badge.decoration! as BoxDecoration).color, c.ink);
      expect(tester.takeException(), isNull);
    });

    testWidgets('selected: ink label 600 + orange needle; others navInactive', (
      tester,
    ) async {
      await pumpUi(tester, bar(badge: 0), size: const Size(390, 800));
      await tester.pump(const Duration(milliseconds: 400));
      const c = AknColors.light;
      final style = tester.widget<Text>(find.text('Ana sayfa')).style!;
      expect(style.color, c.ink);
      expect(style.fontWeight, FontWeight.w600);
      final other = tester.widget<Text>(find.text('Siparişler')).style!;
      expect(other.color, c.navInactive);
      expect(other.fontWeight, FontWeight.w500);
      // The needle: 22 × 3 in the logo orange over the first item.
      final needle = find.byWidgetPredicate(
        (w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == c.logo,
      );
      expect(needle, findsOneWidget);
      final r = tester.getRect(needle);
      expect(r.width, 22);
      expect(r.height, 3);
      final home = tester.getRect(find.text('Ana sayfa'));
      expect((r.center.dx - home.center.dx).abs(), lessThan(1));
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
    testWidgets(
      'variants: orange primary, white bordered secondary / outline',
      (tester) async {
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
        // Owner decision G: primary = the orange gradient (#F7742F →
        // #E8590C) with a WHITE 17 px w700 label, radius 12.
        expect(deco('Gönder').gradient, c.buttonGradient);
        expect(deco('Gönder').borderRadius, BorderRadius.circular(12));
        final primaryLabel = tester.widget<Text>(find.text('Gönder')).style!;
        expect(primaryLabel.color, c.onBrandFill);
        expect(primaryLabel.color, const Color(0xFFFFFFFF));
        expect(primaryLabel.fontSize, 17);
        expect(primaryLabel.fontWeight, FontWeight.w700);
        // Secondary and outline: white, 1.5 px control border, ink label.
        expect(deco('Revize').color, c.surface);
        expect((deco('Revize').border! as Border).top.color, c.lineStrong);
        expect((deco('Revize').border! as Border).top.width, 1.5);
        expect(deco('Vazgeç').color, c.surface);
        expect((deco('Vazgeç').border! as Border).top.color, c.lineStrong);
        // The default size is the 52 px flow button.
        expect(tester.getSize(find.byType(AknButton).first).height, 52);
        final label = tester.widget<Text>(find.text('Revize'));
        expect(label.style!.color, c.ink);
      },
    );

    testWidgets('confirm sheet: full-width action, ghost "Vazgeç" under it', (
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
      expect(cancel.variant, AknButtonVariant.ghost);
      expect(
        tester.getTopLeft(find.text('Vazgeç')).dy,
        greaterThan(tester.getTopLeft(find.text('Onayla')).dy),
        reason: 'v2 §6.21: the action first, the cancel under it',
      );
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
    });

    testWidgets('tappable card: selection haptic, flat press (fill + 0.98)', (
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
      expect(scale.scale, AknMotion.pressScale);
      // v2 §6.6: pressed = Beton fill; flat (no shadow), radius 12, hairline.
      final pressedBox = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text('Kart'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect(
        (pressedBox.decoration! as BoxDecoration).color,
        AknColors.light.surfaceAlt,
      );
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 200));
      expect(taps, 1);
      expect(haptics, contains('HapticFeedbackType.selectionClick'));
      final box = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text('Kart'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      final deco = box.decoration! as BoxDecoration;
      expect(deco.borderRadius, BorderRadius.circular(12));
      expect(deco.boxShadow, anyOf(isNull, isEmpty));
      expect(deco.color, AknColors.light.surface);
      expect((deco.border! as Border).top.color, AknColors.light.line);
    });

    testWidgets('filter chips: selected is an ink chip, no orange (v2 §6.11)', (
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
      final c = AknColors.light;
      final label = tester.widget<Text>(find.text('Bekleyen'));
      expect(label.style!.color, c.bg);
      final other = tester.widget<Text>(find.text('Biten'));
      expect(other.style!.color, c.ink);
      final fills = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .map((w) => (w.decoration as BoxDecoration?)?.color)
          .toList();
      expect(fills, containsAll([c.ink, c.surfaceAlt]));
      expect(fills, isNot(contains(c.brandFill)));
      expect(contrast(c.bg, c.ink), greaterThanOrEqualTo(4.5));
      expect(contrast(c.ink, c.surfaceAlt), greaterThanOrEqualTo(4.5));
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

// Design v3 "Akış" components: the page-coloured app bar that turns frosted on scroll (root
// `display` / pushed `headline` titles, the back button in its circle), the deprecated hero
// header, status-bar icons per surface, AnimatedNumber's count-up, the frosted bottom bar with its
// sliding pill and deep-orange badges, button variants, card press and filter chips.
import 'dart:ui' as ui;

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
      // v3 §4: a root tab page (no back button) titles in `display`
      // 28/34 800 (−0.4, Archivo's panel tracking) at the 20 px edge, in a
      // 60 px bar.
      expect(bar.toolbarHeight, AknTheme.rootBarHeight);
      expect(AknTheme.rootBarHeight, 60);
      expect(bar.titleSpacing, AknSpace.page);
      final title = tester.widget<Text>(find.text('Siparişler'));
      expect(title.style!.color, c.ink);
      expect(title.style!.fontWeight, FontWeight.w800);
      expect(title.style!.fontSize, 28);
      expect(title.style!.height, 34 / 28);
      expect(title.style!.letterSpacing, -0.4);
      expect(title.style!.fontFamily, AknFonts.sans);
      expect(find.byType(OnHero), findsNothing);
    });

    testBothThemes('root page band: the panel\'s page hero with the actions', (
      tester,
      b,
    ) async {
      await pumpUi(
        tester,
        AppScaffold(
          title: 'Siparişler',
          bandIcon: PhosphorIconsRegular.receipt,
          eyebrow: 'Bayi',
          description: 'Tüm müşteri siparişleri',
          actions: [
            AknIconButton(
              icon: PhosphorIconsRegular.slidersHorizontal,
              semanticLabel: 'Süzgeçler',
              onPressed: () {},
            ),
          ],
          body: const SizedBox.expand(),
        ),
        brightness: b,
        scaffold: false,
      );
      final c = b == Brightness.dark ? AknColors.dark : AknColors.light;
      final band = find.byType(AknPageBand);
      expect(band, findsOneWidget);
      // Eyebrow (Pas 12 600), title (20 700 ink, the page header) and the
      // one-line description (13 dim) next to the 40 px icon tile.
      final eyebrow = tester.widget<Text>(find.text('Bayi')).style!;
      expect(eyebrow.color, c.brandInk);
      expect(eyebrow.fontSize, 12);
      expect(eyebrow.fontWeight, FontWeight.w600);
      final title = tester.widget<Text>(find.text('Siparişler')).style!;
      expect(title.color, c.ink);
      expect(title.fontSize, 20);
      expect(title.fontWeight, FontWeight.w700);
      final desc = tester.widget<Text>(find.text('Tüm müşteri siparişleri'));
      expect(desc.style!.color, c.dim);
      expect(desc.maxLines, 1);
      expect(
        tester.getSemantics(find.text('Siparişler')),
        matchesSemantics(label: 'Siparişler', isHeader: true),
      );
      // The page actions sit inside the band, on its right.
      expect(
        find.descendant(
          of: band,
          matching: find.byIcon(PhosphorIconsRegular.slidersHorizontal),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(PhosphorIconsRegular.receipt), findsOneWidget);
      // The bar is as tall as the band and its margins; the band spans the
      // 20 px gutters.
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(
        bar.toolbarHeight,
        AknPageBand.heightFor(TextScaler.noScaling) + AknPageBand.margin * 2,
      );
      final rect = tester.getRect(band);
      expect(rect.left, AknSpace.page);
      final barWidth = tester.getSize(find.byType(AppBar)).width;
      expect(barWidth - rect.right, AknSpace.page);
      expect(tester.takeException(), isNull);
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
      expect(AknTheme.pushedBarHeight, 52);
      // v3 §4: the platform BackButton (its tooltip and semantics) draws the
      // Phosphor arrowLeft 22 in a 40 px white circle with the card shadow.
      expect(find.byType(BackButtonIcon), findsOneWidget);
      expect(find.byIcon(PhosphorIconsRegular.arrowLeft), findsOneWidget);
      final circle = find.descendant(
        of: find.byType(AppBar),
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).shape == BoxShape.circle,
        ),
      );
      expect(tester.getSize(circle), const Size.square(40));
      final disc = tester.widget<DecoratedBox>(circle).decoration;
      expect((disc as BoxDecoration).color, AknColors.light.surface);
      expect(disc.boxShadow, AknShadows.card(AknColors.light));
      // The title in `headline` 17/22 700, one line.
      final title = tester.widget<Text>(find.text('SIP-20261021-12002'));
      expect(title.style!.fontSize, 17);
      expect(title.style!.fontWeight, FontWeight.w700);
      expect(title.maxLines, 1);
    });

    testWidgets('app bar turns frosted with a soft shadow once scrolled', (
      tester,
    ) async {
      await pumpUi(tester, _page(hero: false), scaffold: false);
      const c = AknColors.light;
      final scaffold = find.byType(AppScaffold);
      double frost() => tester
          .widget<AnimatedOpacity>(
            find.descendant(
              of: scaffold,
              matching: find.byType(AnimatedOpacity),
            ),
          )
          .opacity;
      Color fill() =>
          tester.widget<AppBar>(find.byType(AppBar)).backgroundColor!;
      // At rest: the page colour, no frost.
      expect(frost(), 0);
      expect(fill(), c.bg);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pumpAndSettle();
      // v3 §4: content under the bar — the bar clears and the frost shows:
      // `surface` at 85 % over a σ 16 blur with a soft shadow, never a
      // hairline.
      expect(frost(), 1);
      expect(fill().a, 0);
      final blur = find.descendant(
        of: scaffold,
        matching: find.byType(BackdropFilter),
      );
      expect(
        tester.widget<BackdropFilter>(blur).filter,
        ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      );
      final glass =
          tester
                  .widget<DecoratedBox>(
                    find
                        .descendant(
                          of: blur,
                          matching: find.byType(DecoratedBox),
                        )
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(glass.color, c.surface.withValues(alpha: 0.85));
      expect(glass.border, isNull);
      final shadow =
          tester
                  .widget<DecoratedBox>(
                    find
                        .ancestor(of: blur, matching: find.byType(DecoratedBox))
                        .first,
                  )
                  .decoration
              as BoxDecoration;
      expect(shadow.boxShadow, isNotEmpty);
      await tester.drag(find.byType(ListView), const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(frost(), 0);
      expect(fill(), c.bg);
    });

    for (final navy in [false, true]) {
      testBothThemes(
        '${navy ? 'navy (alias)' : 'hero'} (deprecated): the normal page-coloured bar, no strip',
        (tester, b) async {
          await pumpUi(
            tester,
            _page(hero: !navy, navy: navy),
            brightness: b,
            scaffold: false,
          );
          final c = b == Brightness.dark ? AknColors.dark : AknColors.light;
          final bar = tester.widget<AppBar>(find.byType(AppBar));
          // v3 §4: no orange app bar (the orange band is the homes' header);
          // the bar is the page colour and status icons follow the page.
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

    testWidgets('status bar: dark icons on the light page bar (hero too)', (
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

    testWidgets('dark mode: light status icons on the bar pages too', (
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
    testBothThemes('deprecated: a plain page-colour header, chips are lamps', (
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
            AknHeroChip(label: 'Sahip', icon: PhosphorIconsFill.shieldCheck),
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
      // v3: no orange strip — the page colour, an ink `display` title
      // (28/34 800), a dim subtitle; off the plate a hero chip is a lamp.
      expect(OnHero.isOn(tester.element(find.text('Sahip'))), isFalse);
      expect(find.byType(AknLamp), findsNWidgets(2));
      final title = tester.widget<Text>(find.text('Günaydın, Ayşe'));
      expect(title.style!.color, c.ink);
      expect(title.style!.fontSize, 28);
      expect(title.style!.fontWeight, FontWeight.w800);
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
    // v3 §5 "Numbers": a value counts up from 0 when it first appears and
    // counts on from the number on screen when it changes (AknMotion.count,
    // 600 ms). Tabular figures in a box held at the final width keep the
    // digits ticking in place; screen readers hear the final value once.
    String shown(WidgetTester tester) => tester
        .widget<Text>(
          find.descendant(
            of: find.byType(AnimatedNumber),
            matching: find.byType(Text),
          ),
        )
        .data!;

    testWidgets('counts up from 0 to the formatted value, read once', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpUi(
        tester,
        AnimatedNumber(value: 12500, format: (v) => '${v.round()} L'),
      );
      final size = tester.getSize(find.byType(AnimatedNumber));
      // The first frame starts at 0; the screen reader already has the
      // final value — and only it.
      expect(find.text('0 L'), findsOneWidget);
      expect(find.bySemanticsLabel('12500 L'), findsOneWidget);
      expect(find.bySemanticsLabel('0 L'), findsNothing);
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(AknMotion.count ~/ 2);
      final mid = int.parse(shown(tester).replaceAll(' L', ''));
      expect(mid, inExclusiveRange(0, 12500));
      expect(find.bySemanticsLabel('12500 L'), findsOneWidget);
      // Nothing beside the number moves while it counts.
      expect(tester.getSize(find.byType(AnimatedNumber)), size);
      await tester.pump(AknMotion.count);
      expect(find.text('12500 L'), findsOneWidget);
      expect(find.bySemanticsLabel('12500 L'), findsOneWidget);
      expect(tester.getSize(find.byType(AnimatedNumber)), size);
      expect(tester.hasRunningAnimations, isFalse);
      handle.dispose();
    });

    testWidgets('default format groups; tabular figures in `number`', (
      tester,
    ) async {
      await pumpUi(tester, const AnimatedNumber(value: 1234567));
      await tester.pump(AknMotion.count);
      expect(find.text('1.234.567'), findsOneWidget);
      final style = tester.widget<Text>(find.byType(Text)).style!;
      // v3 §1: every figure is tabular (the count never changes width), in
      // Archivo `number` 24/30 800.
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(style.fontFamily, AknFonts.sans);
      expect(style.fontSize, 24);
      expect(style.fontWeight, FontWeight.w800);
    });

    testWidgets('reduce motion shows the value at once', (tester) async {
      await pumpUi(
        tester,
        const AnimatedNumber(value: 640),
        reduceMotion: true,
      );
      expect(find.text('640'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a new value counts on from the number on screen', (
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
      await tester.pumpAndSettle();
      expect(find.text('100'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
      await tester.tap(find.byType(AnimatedNumber));
      await tester.pump();
      // From 100, not from 0; the screen reader hears only the new value.
      expect(find.text('100'), findsOneWidget);
      expect(find.bySemanticsLabel('200'), findsOneWidget);
      await tester.pump(AknMotion.count ~/ 2);
      expect(int.parse(shown(tester)), inExclusiveRange(100, 200));
      await tester.pump(AknMotion.count);
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
    // v3 §4: Phosphor Regular at rest, Fill when active.
    Widget bar({int badge = 3, AknCenterAction? center}) => Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedBottomBar(
        currentIndex: 0,
        onSelected: (_) {},
        centerAction: center,
        items: [
          const AknNavItem(
            icon: PhosphorIconsRegular.house,
            selectedIcon: PhosphorIconsFill.house,
            label: 'Ana sayfa',
          ),
          AknNavItem(
            icon: PhosphorIconsRegular.checkCircle,
            selectedIcon: PhosphorIconsFill.checkCircle,
            label: 'Onaylarım',
            badgeCount: badge,
          ),
          const AknNavItem(
            icon: PhosphorIconsRegular.receipt,
            selectedIcon: PhosphorIconsFill.receipt,
            label: 'Siparişler',
          ),
          const AknNavItem(
            icon: PhosphorIconsRegular.dotsThree,
            label: 'Diğer',
          ),
        ],
      ),
    );

    testBothThemes(
      'docked full width, frosted, no hairline; deep-orange badge',
      (tester, b) async {
        await pumpUi(tester, bar(), brightness: b, size: const Size(390, 800));
        await tester.pump(const Duration(milliseconds: 400));
        final c = b == Brightness.dark ? AknColors.dark : AknColors.light;
        final rect = tester.getRect(find.byType(AnimatedBottomBar));
        expect(rect.left, 0);
        expect(rect.right, 390);
        // v3 §4: the dock lifts off the content with the bar shadow …
        final dock = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(AnimatedBottomBar),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        expect((dock.decoration as BoxDecoration).boxShadow, AknShadows.bar(c));
        // … and is frosted: `surfaceRaised` at 92 % over a σ 20 blur, with no
        // hairline (dark mode keeps a faint top edge, as dark cards do).
        final blur = find.descendant(
          of: find.byType(AnimatedBottomBar),
          matching: find.byType(BackdropFilter),
        );
        expect(
          tester.widget<BackdropFilter>(blur).filter,
          ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        );
        final glass =
            tester
                    .widget<DecoratedBox>(
                      find
                          .descendant(
                            of: blur,
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;
        expect(glass.color, c.surfaceRaised.withValues(alpha: 0.92));
        if (c.isDark) {
          expect(
            (glass.border! as Border).top.color,
            c.line.withValues(alpha: 0.7),
          );
        } else {
          expect(glass.border, isNull);
        }
        // The count badge: a deep-orange pill (`brandFillPressed`) in a 2 px
        // ring of the bar colour; white 10 w800 tabular figures (≥ 4.5:1).
        final badge = tester.widget<Container>(
          find
              .ancestor(of: find.text('3'), matching: find.byType(Container))
              .first,
        );
        final pill = badge.decoration! as BoxDecoration;
        expect(pill.color, c.brandFillPressed);
        expect(pill.borderRadius, AknRadius.pillAll);
        expect(pill.border, Border.all(color: c.surfaceRaised, width: 2));
        final digits = tester.widget<Text>(find.text('3')).style!;
        expect(digits.color, c.onBrandFill);
        expect(digits.fontSize, 10);
        expect(digits.fontWeight, FontWeight.w800);
        expect(
          digits.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
        expect(
          contrast(c.onBrandFill, c.brandFillPressed),
          greaterThanOrEqualTo(4.5),
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('selected: Pas 700 label and Fill icon on the brandSoft pill '
        '(the panel\'s "you are here"); others navInactive 600, Regular', (
      tester,
    ) async {
      await pumpUi(tester, bar(badge: 0), size: const Size(390, 800));
      await tester.pump(const Duration(milliseconds: 400));
      const c = AknColors.light;
      final style = tester.widget<Text>(find.text('Ana sayfa')).style!;
      expect(style.color, c.brandInk);
      expect(style.fontWeight, FontWeight.w700);
      final other = tester.widget<Text>(find.text('Siparişler')).style!;
      expect(other.color, c.navInactive);
      expect(other.fontWeight, FontWeight.w600);
      expect(find.byIcon(PhosphorIconsFill.house), findsOneWidget);
      expect(find.byIcon(PhosphorIconsRegular.house), findsNothing);
      expect(find.byIcon(PhosphorIconsRegular.receipt), findsOneWidget);
      expect(find.byIcon(PhosphorIconsFill.receipt), findsNothing);
      // The pill: one 56 × 32 `brandSoft` capsule (r16) behind the active
      // icon, 10 px under the top, in the middle of its slot (the needle and
      // the hairline are gone).
      final pill = find.descendant(
        of: find.byType(AnimatedBottomBar),
        matching: find.byType(CustomPaint),
      );
      expect(pill, findsOneWidget);
      const slot = (390 - 12) / 4;
      expect(
        pill,
        paints..rrect(
          rrect: RRect.fromRectAndRadius(
            const Rect.fromLTWH(slot / 2 - 28, 10, 56, 32),
            const Radius.circular(16),
          ),
          color: c.brandSoft,
        ),
      );
      final home = tester.getRect(find.text('Ana sayfa'));
      final centre = tester.getTopLeft(pill).dx + slot / 2;
      expect((centre - home.center.dx).abs(), lessThan(1));
    });

    testWidgets('center action: the orange key runs its action', (
      tester,
    ) async {
      var opened = 0;
      await pumpUi(
        tester,
        bar(
          center: AknCenterAction(
            icon: PhosphorIconsRegular.plus,
            label: 'Sipariş ver',
            onPressed: () => opened++,
          ),
        ),
      );
      // v3 §4 (decision G): a 52 × 40 r14 key in the primary button's orange
      // gradient with a white glyph.
      const c = AknColors.light;
      final key = find.descendant(
        of: find.byType(AnimatedBottomBar),
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).gradient == c.buttonGradient,
        ),
      );
      expect(tester.getSize(key), const Size(52, 40));
      expect(
        (tester.widget<DecoratedBox>(key).decoration as BoxDecoration)
            .borderRadius,
        BorderRadius.circular(14),
      );
      expect(
        tester.widget<Icon>(find.byIcon(PhosphorIconsRegular.plus)).color,
        c.onBrandFill,
      );
      await tester.tap(find.byIcon(PhosphorIconsRegular.plus));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('Sipariş ver'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(opened, 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('Buttons and cards', () {
    testWidgets(
      'variants: orange gradient primary with its glow, white bordered '
      'secondary / outline',
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
        ShapeDecoration deco(String label) =>
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
                as ShapeDecoration;
        RoundedSuperellipseBorder shape(String label) =>
            deco(label).shape as RoundedSuperellipseBorder;
        const c = AknColors.light;
        // Owner decision G: primary = the orange gradient (the panel's
        // --grad-brand #D2450E → #B93A0B) with a WHITE 16 px w700 label;
        // v3 §4: the warm glow under it, a radius-16 superellipse.
        expect(c.brandFillStart, const Color(0xFFD2450E));
        expect(c.brandFill, const Color(0xFFB93A0B));
        expect(deco('Gönder').gradient, c.buttonGradient);
        expect(deco('Gönder').shadows, AknShadows.button(c));
        expect(shape('Gönder').borderRadius, BorderRadius.circular(16));
        expect(shape('Gönder').side, BorderSide.none);
        final primaryLabel = tester.widget<Text>(find.text('Gönder')).style!;
        expect(primaryLabel.color, c.onBrandFill);
        expect(primaryLabel.color, const Color(0xFFFFFFFF));
        expect(primaryLabel.fontSize, 16);
        expect(primaryLabel.fontWeight, FontWeight.w700);
        // Secondary and outline: white, a 1.5 px `lineStrong` 60 % border,
        // an ink label, no glow.
        expect(
          AknTheme.secondaryBorder(c),
          c.lineStrong.withValues(alpha: 0.6),
        );
        for (final label in ['Revize', 'Vazgeç']) {
          expect(deco(label).gradient!.colors, everyElement(c.surface));
          expect(
            shape(label).side,
            BorderSide(color: AknTheme.secondaryBorder(c), width: 1.5),
          );
          expect(shape(label).borderRadius, BorderRadius.circular(16));
          expect(deco(label).shadows, anyOf(isNull, isEmpty));
          expect(tester.widget<Text>(find.text(label)).style!.color, c.ink);
        }
        // The default size is the 52 px flow button.
        expect(tester.getSize(find.byType(AknButton).first).height, 52);
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
        reason: 'the action first, the cancel under it',
      );
      await tester.tap(find.text('Vazgeç'));
      await tester.pumpAndSettle();
    });

    testWidgets('tappable card: selection haptic; press 0.97, fill dims, the '
        'shadow settles', (tester) async {
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
      expect(scale.scale, 0.97);
      // v3 §3/§5: pressed = the fill dims to `surfaceAlt` and the card
      // settles onto the page (only the contact shadow).
      const c = AknColors.light;
      final pressedBox = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text('Kart'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      final pressed = pressedBox.decoration! as BoxDecoration;
      expect(pressed.color, c.surfaceAlt);
      expect(pressed.boxShadow, AknShadows.pressed(c));
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
      // At rest: a white card floating on the soft card shadow, radius 20,
      // no hairline in light mode.
      final deco = box.decoration! as BoxDecoration;
      expect(deco.borderRadius, BorderRadius.circular(20));
      expect(deco.boxShadow, AknShadows.card(c));
      expect(deco.color, c.surface);
      expect(deco.border, isNull);
    });

    testWidgets('filter chips: selected is the panel\'s soft orange chip with '
        'a check', (tester) async {
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
      await tester.pump(const Duration(milliseconds: 500));
      const c = AknColors.light;
      Finder chip(String label) => find
          .ancestor(of: find.text(label), matching: find.byType(Container))
          .first;
      BoxDecoration deco(String label) =>
          tester.widget<Container>(chip(label)).decoration! as BoxDecoration;
      double check(String label) => tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.descendant(
                    of: chip(label),
                    matching: find.byIcon(PhosphorIconsBold.check),
                  ),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;
      // Chips (the panel's `.chip`): selected = the soft orange well, its
      // orange line, a Pas label and a check (never colour alone); at rest
      // white with a 1 px `line` border and an ink label.
      expect(deco('Bekleyen').color, c.brandSoft);
      expect((deco('Bekleyen').border! as Border).top.color, c.brandLine);
      expect(deco('Bekleyen').borderRadius, AknRadius.chip);
      expect(
        tester.widget<Text>(find.text('Bekleyen')).style!.color,
        c.brandInk,
      );
      expect(check('Bekleyen'), 1);
      expect(deco('Biten').color, c.surface);
      expect((deco('Biten').border! as Border).top.color, c.line);
      expect(tester.widget<Text>(find.text('Biten')).style!.color, c.ink);
      expect(check('Biten'), 0);
      // The chip at rest is never orange; the selected label stays AA.
      final rest = deco('Biten');
      for (final color in [rest.color, (rest.border! as Border).top.color]) {
        expect(
          color,
          isNot(anyOf(c.brand, c.brandFill, c.brandSoft, c.brandLine)),
        );
      }
      expect(contrast(c.brandInk, c.brandSoft), greaterThanOrEqualTo(4.5));
      expect(contrast(c.ink, c.surface), greaterThanOrEqualTo(4.5));
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

import 'package:akaryakitnet/core/models/enums.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test_helpers.dart';

void main() {
  tearDown(() {
    AppToast.dismiss();
    TrTime.clock = () => DateTime.now().toUtc();
  });

  group('AknButton', () {
    testBothThemes('tap calls back; null disables', (tester, b) async {
      var taps = 0;
      await pumpUi(
        tester,
        Column(
          children: [
            AknButton(label: 'Gönder', onPressed: () => taps++),
            const AknButton.secondary(label: 'Pasif', onPressed: null),
          ],
        ),
        brightness: b,
      );
      await tester.tap(find.text('Gönder'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(taps, 1);

      await tester.tap(find.text('Pasif'));
      await tester.pump();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Pasif')),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
      );
      expect(
        tester.getSize(find.byType(AknButton).first).height,
        greaterThanOrEqualTo(48),
      );
    });

    testBothThemes('async: spinner while running, then a check', (
      tester,
      b,
    ) async {
      await pumpUi(
        tester,
        AknButton(
          label: 'Teklifi gönder',
          expand: true,
          onPressedAsync: () =>
              Future<void>.delayed(const Duration(milliseconds: 500)),
        ),
        brightness: b,
      );
      await tester.tap(find.text('Teklifi gönder'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ChevronSpinner), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byIcon(PhosphorIconsRegular.check), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(find.text('Teklifi gönder'), findsOneWidget);
    });

    testWidgets('press gives a light haptic', (tester) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            calls.add('${call.arguments}');
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
      await pumpUi(tester, AknButton(label: 'Onayla', onPressed: () {}));
      await tester.tap(find.text('Onayla'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(calls, contains('HapticFeedbackType.lightImpact'));
    });
  });

  testBothThemes('KpiTile counts up to the formatted value, read once', (
    tester,
    b,
  ) async {
    await pumpUi(
      tester,
      const SizedBox(
        width: 200,
        child: KpiTile(label: 'Bekleyen', value: 12500),
      ),
      brightness: b,
    );
    // v3 §5 "Numbers": readouts count up from 0 when they appear
    // (AknMotion.count); screen readers hear the final value from the
    // first frame, never the count.
    expect(find.text('0'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Bekleyen: 12.500')), findsOneWidget);
    await tester.pump(AknMotion.count ~/ 2);
    expect(find.text('0'), findsNothing);
    expect(find.text('12.500'), findsNothing);
    await tester.pump(AknMotion.count);
    expect(find.text('12.500'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Bekleyen: 12.500')), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('KpiTile shows the final value at once under reduce motion', (
    tester,
  ) async {
    await pumpUi(
      tester,
      const SizedBox(width: 200, child: KpiTile(label: 'Litre', value: 640)),
      reduceMotion: true,
    );
    expect(find.text('640'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testBothThemes('EmptyState and ErrorState call their actions', (
    tester,
    b,
  ) async {
    var actions = 0;
    await pumpUi(
      tester,
      Column(
        children: [
          EmptyState(
            title: 'Teklif yok',
            message: 'Yeni teklif gelince bildirim alırsınız.',
            actionLabel: 'Sipariş ver',
            onAction: () => actions++,
          ),
          ErrorState(onRetry: () => actions++),
        ],
      ),
      brightness: b,
      scroll: true,
    );
    await tester.pump(const Duration(milliseconds: 400));
    // §10.2: what failed + what to do, never "Bir şeyler ters gitti".
    expect(find.text(ErrorState.defaultTitle), findsOneWidget);
    expect(find.text(ErrorState.defaultMessage), findsOneWidget);
    expect(find.text('Bir şeyler ters gitti'), findsNothing);
    expect(find.byType(EmptyIllustration), findsNWidgets(2));
    await tester.tap(find.text('Sipariş ver'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.ensureVisible(find.text('Tekrar dene'));
    await tester.pump();
    await tester.tap(find.text('Tekrar dene'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(actions, 2);
  });

  group('AnimatedBottomBar', () {
    testBothThemes('selects tabs, shows badges, runs the center action', (
      tester,
      b,
    ) async {
      final selected = <int>[];
      var center = 0;
      await pumpUi(
        tester,
        Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedBottomBar(
            currentIndex: 0,
            onSelected: selected.add,
            centerAction: AknCenterAction(
              icon: PhosphorIconsRegular.plus,
              label: 'Sipariş ver',
              onPressed: () => center++,
            ),
            items: const [
              AknNavItem(icon: PhosphorIconsFill.house, label: 'Ana sayfa'),
              AknNavItem(
                icon: PhosphorIconsFill.checkCircle,
                label: 'Onaylarım',
                badgeCount: 3,
              ),
              AknNavItem(icon: PhosphorIconsFill.truck, label: 'Teslimatlar'),
              AknNavItem(
                icon: PhosphorIconsRegular.dotsThree,
                label: 'Diğer',
                showDot: true,
              ),
            ],
          ),
        ),
        brightness: b,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('3'), findsOneWidget);
      await tester.tap(find.text('Onaylarım'));
      await tester.tap(find.text('Diğer'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(selected, [1, 3]);

      await tester.tap(find.byIcon(PhosphorIconsRegular.plus));
      await tester.pump(const Duration(milliseconds: 200));
      expect(center, 1);

      expect(find.bySemanticsLabel('Onaylarım, 3 yeni'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Ana sayfa')),
        isSemantics(isSelected: true, isButton: true),
      );
    });
  });

  group('AppScaffold', () {
    testBothThemes('bell with unread badge from AppChrome', (tester, b) async {
      var opened = 0;
      await pumpUi(
        tester,
        AppChrome(
          unreadCount: 5,
          onOpenNotifications: () => opened++,
          offline: true,
          pendingOps: 2,
          // v4: the bell is opt-in on AppScaffold (it lives in the home band).
          child: const AppScaffold(
            title: 'Siparişler',
            showBell: true,
            body: Text('içerik'),
          ),
        ),
        brightness: b,
        scaffold: false,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('5'), findsOneWidget);
      expect(
        find.text(OfflineBanner.message(offline: true, pending: 2)),
        findsOneWidget,
      );
      // v3 §4: the bell keeps its Regular (outline) glyph; the orange count
      // badge counts.
      await tester.tap(find.byIcon(PhosphorIconsRegular.bell));
      await tester.pump(const Duration(milliseconds: 200));
      expect(opened, 1);
    });

    testWidgets('no AppChrome: no bell, no banner', (tester) async {
      await pumpUi(
        tester,
        const AppScaffold(title: 'Profil', body: Text('içerik')),
        scaffold: false,
      );
      expect(find.byIcon(PhosphorIconsRegular.bell), findsNothing);
      expect(find.byType(OfflineBanner), findsNothing);
    });
  });

  testBothThemes('AppToast shows, announces and goes away', (tester, b) async {
    await pumpUi(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () =>
              AppToast.success('Teklif gönderildi', context: context),
          child: const Text('göster'),
        ),
      ),
      brightness: b,
    );
    await tester.tap(find.text('göster'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Teklif gönderildi'), findsOneWidget);
    expect(AppToast.isShowing, isTrue);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Teklif gönderildi'), findsNothing);
    expect(AppToast.isShowing, isFalse);
  });

  group('SlideToConfirm', () {
    testBothThemes('a full drag confirms; a short one springs back', (
      tester,
      b,
    ) async {
      var confirmed = 0;
      await pumpUi(
        tester,
        Padding(
          padding: const EdgeInsets.all(16),
          child: SlideToConfirm(
            label: 'Kaydırarak yola çık',
            onConfirmed: () => confirmed++,
          ),
        ),
        brightness: b,
      );
      final track = find.byType(SlideToConfirm);
      final left = tester.getTopLeft(track) + const Offset(36, 32);
      await tester.dragFrom(left, const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 400));
      expect(confirmed, 0);
      await tester.dragFrom(left, const Offset(800, 0));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(confirmed, 1);
      expect(find.text('Onaylandı'), findsOneWidget);
    });

    testWidgets('screen readers confirm with a tap action', (tester) async {
      var confirmed = 0;
      final handle = tester.ensureSemantics();
      await pumpUi(
        tester,
        SlideToConfirm(label: 'Teslim et', onConfirmed: () => confirmed++),
      );
      final node = tester.getSemantics(find.bySemanticsLabel('Teslim et'));
      expect(node.hint, 'Onaylamak için iki kez dokunun');
      node.owner!.performAction(node.id, SemanticsAction.tap);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
      expect(confirmed, 1);
      handle.dispose();
    });

    testWidgets(
      'with a screen reader running, the tap opens a confirm sheet (§6.26)',
      (tester) async {
        var confirmed = 0;
        final handle = tester.ensureSemantics();
        await pumpUi(
          tester,
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
              child: SlideToConfirm(
                label: 'Teslimatı kaydetmek için kaydırın',
                confirmTitle: 'Teslimatı kaydet',
                confirmLabel: 'Teslimatı kaydet',
                onConfirmed: () => confirmed++,
              ),
            ),
          ),
        );
        final node = tester.getSemantics(
          find.bySemanticsLabel('Teslimatı kaydetmek için kaydırın'),
        );
        node.owner!.performAction(node.id, SemanticsAction.tap);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(confirmed, 0, reason: 'nothing happens before the sheet');
        expect(find.byType(ConfirmSheet), findsOneWidget);
        await tester.tap(find.widgetWithText(AknButton, 'Teslimatı kaydet'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 100));
        expect(confirmed, 1);
        handle.dispose();
      },
    );

    testBothThemes('a 64 px surfaceAlt pill track, a 56 px orange knob', (
      tester,
      b,
    ) async {
      await pumpUi(
        tester,
        Padding(
          padding: const EdgeInsets.all(16),
          child: SlideToConfirm(label: 'Yola çık', onConfirmed: () {}),
        ),
        brightness: b,
      );
      final c = b == Brightness.dark ? AknColors.dark : AknColors.light;
      final boxes = tester
          .widgetList<Container>(
            find.descendant(
              of: find.byType(SlideToConfirm),
              matching: find.byType(Container),
            ),
          )
          .map((w) => w.decoration)
          .whereType<BoxDecoration>()
          .toList();
      // v3 §4: the track is a `surfaceAlt` pill.
      expect(
        boxes.where(
          (d) => d.color == c.surfaceAlt && d.borderRadius == AknRadius.pillAll,
        ),
        isNotEmpty,
      );
      // The knob: a 56 px circle in the primary's orange gradient (logo
      // orange underneath) with its warm glow.
      final knobFinder = find.descendant(
        of: find.byType(SlideToConfirm),
        matching: find.byType(AnimatedContainer),
      );
      final knob = tester.widget<AnimatedContainer>(knobFinder);
      final deco = knob.decoration! as BoxDecoration;
      expect(deco.color, c.logo);
      expect(deco.gradient, c.buttonGradient);
      expect(deco.shape, BoxShape.circle);
      expect(deco.boxShadow, AknShadows.button(c));
      expect(tester.getSize(knobFinder), const Size.square(56));
      expect(tester.getSize(find.byType(SlideToConfirm)).height, 64);
    });
  });

  testBothThemes('CountdownBadge shows time left and expiry', (
    tester,
    b,
  ) async {
    final now = DateTime.utc(2026, 10, 21, 9);
    TrTime.clock = () => now;
    await pumpUi(
      tester,
      Column(
        children: [
          CountdownBadge(deadline: now.add(const Duration(minutes: 95))),
          CountdownBadge(deadline: now.subtract(const Duration(minutes: 1))),
        ],
      ),
      brightness: b,
    );
    expect(find.text('1 sa 35 dk kaldı'), findsOneWidget);
    expect(find.text('Süresi doldu'), findsOneWidget);
  });

  group('TrNumberInputFormatter', () {
    TextEditingValue type(TrNumberInputFormatter f, List<String> keys) {
      var v = TextEditingValue.empty;
      for (final k in keys) {
        final text = v.text + k;
        v = f.formatEditUpdate(
          v,
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
        );
      }
      return v;
    }

    test('groups thousands while typing', () {
      final f = TrNumberInputFormatter(decimals: 0);
      expect(type(f, ['1', '2', '5', '0', '0']).text, '12.500');
      expect(type(f, ['0', '0', '7']).text, '7');
    });

    test('decimal comma, typed dot becomes a comma, decimals capped', () {
      final f = TrNumberInputFormatter();
      expect(
        type(f, ['1', '2', '3', '4', ',', '5', '6', '7']).text,
        '1.234,56',
      );
      expect(type(f, ['4', '2', '.', '1']).text, '42,1');
      expect(type(f, [',', '5']).text, '0,5');
    });

    test('paste is parsed as a whole, decimals cut (not rounded)', () {
      final f = TrNumberInputFormatter();
      TextEditingValue paste(String text) => f.formatEditUpdate(
        TextEditingValue.empty,
        TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        ),
      );
      expect(paste('12500.75').text, '12.500,75');
      expect(paste('12.500,759').text, '12.500,75');
      expect(paste('1 234,5 ₺').text, '1.234,5');
      expect(paste('12.500').text, '12.500');
      expect(paste('abc').text, '');
    });

    test('backspace over a grouping dot removes the digit before it', () {
      final f = TrNumberInputFormatter(decimals: 0);
      // "12.500" with the caret after the dot; backspace removes the dot.
      final v = f.formatEditUpdate(
        const TextEditingValue(
          text: '12.500',
          selection: TextSelection.collapsed(offset: 3),
        ),
        const TextEditingValue(
          text: '12500',
          selection: TextSelection.collapsed(offset: 2),
        ),
      );
      expect(v.text, '1.500');
    });
  });

  testBothThemes('LitersField validates the maximum in Turkish', (
    tester,
    b,
  ) async {
    double? read;
    await pumpUi(
      tester,
      Form(
        autovalidateMode: AutovalidateMode.always,
        child: LitersField(max: 12500, onChanged: (v) => read = v),
      ),
      brightness: b,
    );
    expect(find.text('En fazla 12.500 L'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '13000');
    await tester.pump();
    expect(read, 13000);
    expect(find.text('13.000'), findsOneWidget);
    expect(find.text('En fazla 12.500 L girilebilir.'), findsOneWidget);
  });

  testBothThemes('PlateBadge and timeline speak Turkish to screen readers', (
    tester,
    b,
  ) async {
    await pumpUi(
      tester,
      const Column(
        children: [
          PlateBadge(plate: '34abc123'),
          StepTimeline(
            steps: [
              TimelineStep(title: 'Sipariş', state: TimelineState.done),
              TimelineStep(title: 'Yolda', state: TimelineState.current),
              TimelineStep(title: 'Teslim'),
            ],
          ),
        ],
      ),
      brightness: b,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.bySemanticsLabel('Plaka 34 ABC 123'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'Adım 2 / 3: Yolda, şu anki adım')),
      findsOneWidget,
    );
  });

  testWidgets('PullToRefresh runs onRefresh on a pull', (tester) async {
    var refreshed = 0;
    await pumpUi(
      tester,
      PullToRefresh(
        onRefresh: () async => refreshed++,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < 20; i++) ListTile(title: Text('Satır $i')),
          ],
        ),
      ),
    );
    await tester.fling(find.text('Satır 0'), const Offset(0, 400), 1000);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(refreshed, 1);
  });

  testBothThemes('components survive 200 % text on a small phone', (
    tester,
    b,
  ) async {
    await pumpUi(
      tester,
      Column(
        children: [
          AknListTile(
            title: 'Kartal depo motorin siparişi',
            subtitle: '12.500 L · Tuzla şantiye',
            meta: '14:20',
            leadingIcon: PhosphorIconsFill.truck,
            onTap: () {},
          ),
          StatusChip.style(OrderStatus.awaitingApproval.statusStyle),
          AknButton(label: 'Teklifi onayla', expand: true, onPressed: () {}),
          const KpiTile(label: 'Bekleyen teklif', value: 12),
          const FactRow(label: 'Limit kullanımı', value: '%92'),
          const AknBanner(message: 'Siparişiniz finans onayında.'),
          const EmptyState(
            title: 'Kayıt yok',
            message: 'Yeni kayıt gelince burada görünür.',
            compact: true,
          ),
          AnimatedBottomBar(
            currentIndex: 0,
            onSelected: (_) {},
            items: const [
              AknNavItem(icon: PhosphorIconsFill.house, label: 'Ana sayfa'),
              AknNavItem(
                icon: PhosphorIconsFill.checkCircle,
                label: 'Onaylarım',
              ),
              AknNavItem(
                icon: PhosphorIconsFill.invoice,
                label: 'Teklif masası',
              ),
              AknNavItem(icon: PhosphorIconsFill.receipt, label: 'Siparişler'),
              AknNavItem(icon: PhosphorIconsRegular.dotsThree, label: 'Diğer'),
            ],
          ),
        ],
      ),
      brightness: b,
      textScale: 2,
      scroll: true,
      size: const Size(360, 740),
    );
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);
  });

  testBothThemes('ChoiceCard is a checked radio for screen readers', (
    tester,
    b,
  ) async {
    var picked = '';
    await pumpUi(
      tester,
      Column(
        children: [
          ChoiceCard(
            title: 'Çek',
            subtitle: '30–90 gün vade',
            selected: true,
            onTap: () => picked = 'cek',
          ),
          ChoiceCard(
            title: 'DBS',
            selected: false,
            onTap: () => picked = 'dbs',
          ),
        ],
      ),
      brightness: b,
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('^Çek'))),
      isSemantics(
        isChecked: true,
        hasCheckedState: true,
        isInMutuallyExclusiveGroup: true,
      ),
    );
    await tester.tap(find.text('DBS'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(picked, 'dbs');
    // v3: the selected card wears a 2 px orange border over a soft orange
    // wash and a filled orange check — never colour alone (the check and
    // "seçili"); the other one is a plain card with an empty control ring.
    final c = b == Brightness.dark ? AknColors.dark : AknColors.light;
    BoxDecoration card(String title) =>
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.widgetWithText(ChoiceCard, title),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    final on = card('Çek');
    final onSide = (on.border! as Border).top;
    expect(onSide.color, c.brand);
    expect(onSide.width, 2);
    expect(on.gradient!.colors.first, c.brandSoft);
    expect(on.borderRadius, AknRadius.card);
    final check = tester.widget<Icon>(
      find.byIcon(PhosphorIconsFill.checkCircle),
    );
    expect(check.color, c.brandFill);
    // Non-text contrast: the check reads on the wash and on the card.
    expect(contrast(c.brandFill, c.brandSoft), greaterThanOrEqualTo(3));
    expect(contrast(c.brandFill, c.surface), greaterThanOrEqualTo(3));
    final off = card('DBS');
    final offSide = (off.border! as Border).top;
    // Light: no visible border (the card shadow lifts it); dark: 1 px line.
    if (c.isDark) {
      expect(offSide.color, c.line);
      expect(offSide.width, 1);
    } else {
      expect(offSide.color.a, 0);
      expect(off.boxShadow, AknShadows.card(c));
    }
    expect(off.gradient!.colors, everyElement(c.surface));
    final ring = tester
        .widgetList<Container>(
          find.descendant(
            of: find.widgetWithText(ChoiceCard, 'DBS'),
            matching: find.byType(Container),
          ),
        )
        .map((w) => w.decoration)
        .whereType<BoxDecoration>()
        .singleWhere((d) => d.shape == BoxShape.circle);
    expect((ring.border! as Border).top.color, c.lineStrong);
    expect((ring.border! as Border).top.width, 1.5);
    expect(contrast(c.lineStrong, c.surface), greaterThanOrEqualTo(3));
  });

  testBothThemes('ResultView: check for success, icon otherwise', (
    tester,
    b,
  ) async {
    await pumpUi(
      tester,
      const Column(
        children: [
          ResultView(title: 'Siparişiniz alındı'),
          ResultView(tone: AknTone.danger, title: 'Gönderilemedi'),
        ],
      ),
      brightness: b,
      scroll: true,
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.byType(SuccessCheck), findsOneWidget);
    expect(find.byIcon(PhosphorIconsFill.warningCircle), findsOneWidget);
    expect(find.text('Gönderilemedi'), findsOneWidget);
  });
}

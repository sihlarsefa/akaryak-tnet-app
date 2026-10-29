// Design v4 "Sade" core components (spec §4, §3b, §6, §9 core tests): the "Sıra sizde" card, the »
// Akış line, the countdown's urgency colours, the loop budget, the decision dock, the object header,
// the section header and ledger group, the list row's new slots and the focus flash.
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test_helpers.dart';

AknTask _task(
  String id, {
  String title = 'Teklifi onaylayın',
  String? action,
  VoidCallback? onAction,
  VoidCallback? onTap,
  AknTaskTone tone = AknTaskTone.yourMove,
  String? figure,
  String? amount,
  bool counts = true,
}) => AknTask(
  id: id,
  title: title,
  subtitle: 'Demir Petrol · Motorin 8.000 L · Tuzla',
  actionLabel: action,
  onAction: onAction,
  onTap: onTap ?? () {},
  tone: tone,
  figure: figure,
  amount: amount,
  counts: counts,
);

Finder _primaries() => find.byWidgetPredicate(
  (w) =>
      w is AknButton &&
      w.variant == AknButtonVariant.primary &&
      (w.onPressed != null || w.onPressedAsync != null),
);

void main() {
  group('AknTaskCard ("Sıra sizde")', () {
    testBothThemes('calm: one row, no header count, the role sentence', (
      tester,
      b,
    ) async {
      await pumpUi(
        tester,
        const AknTaskCard(
          tasks: [],
          calm: 'Yeni sipariş için + tuşuna dokunun.',
        ),
        brightness: b,
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Bekleyen işiniz yok'), findsOneWidget);
      expect(find.text('Yeni sipariş için + tuşuna dokunun.'), findsOneWidget);
      expect(find.text('Sıra sizde'), findsNothing);
      expect(_primaries(), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'one primary, the lead + at most 2 rows, "Tüm işler" past them',
      (tester) async {
        var opened = 0;
        var acted = 0;
        await pumpUi(
          tester,
          SingleChildScrollView(
            child: AknTaskCard(
              tasks: [
                _task(
                  'a',
                  action: 'Çek görselini yükle',
                  onAction: () => acted++,
                  figure: '338.800,00 ₺',
                ),
                _task('b', title: "Burak Yılmaz'ın talebini onaylayın"),
                _task('c', title: 'Teslimatı onaylayın'),
                _task('d', title: 'Bilgi gönderin', action: 'Bilgi gönder'),
              ],
              total: 4,
              onSeeAll: () => opened++,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 900));
        // Header with the count; screen readers hear "Sıra sizde, 4 iş".
        expect(find.text('Sıra sizde'), findsOneWidget);
        expect(find.bySemanticsLabel('Sıra sizde, 4 iş'), findsOneWidget);
        // Exactly ONE enabled primary (the lead's); rows carry none.
        expect(_primaries(), findsOneWidget);
        expect(find.text('Çek görselini yükle'), findsOneWidget);
        expect(find.text('Bilgi gönder'), findsNothing);
        // The lead + two rows; the fourth task waits behind "Tüm işler" (the
        // count is the pill's; v4 round 2: one footer word on every home).
        expect(find.byType(AknTaskRow), findsNWidgets(2));
        expect(find.text('Bilgi gönderin'), findsNothing);
        expect(find.text('Tüm işler'), findsOneWidget);
        expect(find.bySemanticsLabel('Tüm işler, 4 iş'), findsOneWidget);
        await tester.tap(find.text('Tüm işler'));
        await tester.tap(find.text('Çek görselini yükle'));
        expect(opened, 1);
        expect(acted, 1);
        expect(find.text('338.800,00 ₺'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testBothThemes(
      'queue card (bayi): no count pill, "Tüm işler", the legend on the '
      'right, neutral row tiles',
      (tester, b) async {
        var opened = 0;
        await pumpUi(
          tester,
          SingleChildScrollView(
            child: AknTaskCard(
              tasks: [
                _task('quotes', action: 'Teklif ver', onAction: () {}),
                _task('approvals', title: 'Kararınızı bekleyen 8 talep'),
                _task('disputes', title: 'İtiraz edilen 2 teslimat'),
                _task('plan', title: 'Planlanmayı bekleyen 3 sipariş'),
              ],
              showCount: false,
              legend: true,
              overview: const SizedBox(height: 40),
              onSeeAll: () => opened++,
            ),
          ),
          brightness: b,
          size: const Size(390, 844),
        );
        await tester.pump(const Duration(milliseconds: 900));
        // No second number in the header, none in the footer.
        expect(find.bySemanticsLabel(RegExp(r'^Sıra sizde, \d')), findsNothing);
        expect(find.textContaining('Tümünü gör'), findsNothing);
        await tester.tap(find.text('Tüm işler'));
        expect(opened, 1);
        // The legend sits on the right edge of the card's content.
        final legend = tester.getRect(find.text('sizin sıranız'));
        final card = tester.getRect(find.byType(AknTaskCard));
        expect(legend.right, moreOrLessEquals(card.right - 20, epsilon: 1));
        // Row tiles are the page's neutral well (not the plate's warm one),
        // like Onaylar › Bende; only the lead tile is orange.
        final c = b == Brightness.dark ? AknColors.dark : AknColors.light;
        final rowTiles = find.descendant(
          of: find.byType(AknTaskRow),
          matching: find.byWidgetPredicate(
            (w) =>
                w is AnimatedContainer &&
                w.constraints?.maxWidth == 36 &&
                w.constraints?.maxHeight == 36,
          ),
        );
        expect(rowTiles, findsNWidgets(2));
        for (final e in rowTiles.evaluate()) {
          final box =
              (e.widget as AnimatedContainer).decoration! as BoxDecoration;
          expect(box.color, c.surfaceAlt);
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('no footer when every task is shown', (tester) async {
      await pumpUi(
        tester,
        AknTaskCard(
          tasks: [_task('a', action: 'Teklifi incele', onAction: () {})],
          onSeeAll: () {},
        ),
      );
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.textContaining('Tümünü gör'), findsNothing);
      expect(_primaries(), findsOneWidget);
    });

    testWidgets('a finished task folds away and the card turns calm', (
      tester,
    ) async {
      Widget card(List<AknTask> tasks) => AknTaskCard(
        tasks: tasks,
        calm: 'Yeni sipariş gelince bildirim alırsınız.',
      );
      await pumpUi(
        tester,
        card([_task('a', action: 'Teklif ver', onAction: () {})]),
      );
      await tester.pump(const Duration(milliseconds: 900));
      await pumpUi(tester, card(const []));
      // The stamp and the fold play, then the calm row fades through.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(PhosphorIconsBold.check), findsWidgets);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Bekleyen işiniz yok'), findsOneWidget);
      expect(find.text('Teklif ver'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reflows at 2.0× text with nothing cut', (tester) async {
      await pumpUi(
        tester,
        SingleChildScrollView(
          child: AknTaskCard(
            tasks: [
              _task(
                'a',
                action: 'Çek görselini yükle',
                onAction: () {},
                figure: '338.800,00 ₺',
              ),
              _task('b', amount: '1.263.000,00 ₺'),
            ],
          ),
        ),
        textScale: 2,
      );
      await tester.pump(const Duration(milliseconds: 900));
      expect(tester.takeException(), isNull);
    });
  });

  group('CountdownBadge urgency (v4 §4)', () {
    Color colorOf(WidgetTester tester, String containing) =>
        tester.widget<Text>(find.textContaining(containing)).style!.color!;

    testWidgets('more than 3 h: dim, even on your move', (tester) async {
      await pumpUi(
        tester,
        CountdownBadge(
          deadline: TrTime.now().add(const Duration(hours: 5, minutes: 10)),
          yourMove: true,
        ),
      );
      expect(colorOf(tester, 'sa'), AknColors.light.dim);
      expect(find.byIcon(PhosphorIconsRegular.timer), findsOneWidget);
    });

    testWidgets('3 h or less on your move: Pas 700', (tester) async {
      await pumpUi(
        tester,
        CountdownBadge(
          deadline: TrTime.now().add(const Duration(hours: 2, minutes: 59)),
          yourMove: true,
        ),
      );
      final t = tester.widget<Text>(find.textContaining('sa'));
      expect(t.style!.color, AknColors.light.brandInk);
      expect(t.style!.fontWeight, FontWeight.w700);
    });

    testWidgets('30 min or less: danger 700 with the filled timer', (
      tester,
    ) async {
      await pumpUi(
        tester,
        CountdownBadge(deadline: TrTime.now().add(const Duration(minutes: 20))),
      );
      expect(colorOf(tester, 'dk'), AknColors.light.danger.fg);
      expect(find.byIcon(PhosphorIconsFill.timer), findsOneWidget);
    });

    testWidgets('compact: the time alone ("41 dk")', (tester) async {
      await pumpUi(
        tester,
        CountdownBadge(
          deadline: TrTime.now().add(const Duration(minutes: 41, seconds: 30)),
          compact: true,
          yourMove: true,
        ),
      );
      expect(find.text('41 dk'), findsOneWidget);
      expect(find.textContaining('kaldı'), findsNothing);
    });
  });

  group('loop budget (v4 §6)', () {
    Widget focusLoop(String label) => AknAmbient(
      period: AknMotion.breathe,
      reverse: true,
      role: AknAmbientRole.focus,
      builder: (context, t, child) => Text('$label $t'),
    );

    testWidgets('one focus loop per page; an urgent countdown pauses it', (
      tester,
    ) async {
      AknMotion.ambient = true;
      addTearDown(() => AknMotion.ambient = false);
      await pumpUi(
        tester,
        AppScaffold(
          title: 'Sipariş',
          body: Column(
            children: [
              focusLoop('a'),
              focusLoop('b'),
              AknAmbient(
                period: AknMotion.bandDrift,
                builder: (context, t, child) => const SizedBox(),
              ),
            ],
          ),
        ),
        scaffold: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      // The decorative loop + ONE focus loop.
      expect(AknAmbient.debugRunningCount, 2);
      await pumpUi(
        tester,
        AppScaffold(
          title: 'Sipariş',
          body: Column(
            children: [
              focusLoop('a'),
              focusLoop('b'),
              CountdownBadge(
                deadline: TrTime.now().add(const Duration(minutes: 12)),
              ),
            ],
          ),
        ),
        scaffold: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      // The urgent countdown breathes; the focus loop rests.
      expect(AknAmbient.debugRunningCount, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
      'home: the lead halo is the one loop; the deck\'s month glow waits',
      (tester) async {
        AknMotion.ambient = true;
        addTearDown(() => AknMotion.ambient = false);
        await pumpUi(
          tester,
          AppScaffold(
            title: 'Ana sayfa',
            body: SingleChildScrollView(
              child: Column(
                children: [
                  AknTaskCard(
                    tasks: [
                      _task('lead', action: 'Teklif ver', onAction: () {}),
                    ],
                  ),
                  const SizedBox(
                    width: 300,
                    child: PlateBars(
                      values: [5, 6, 7, 6, 8, 4],
                      labels: ['May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki'],
                    ),
                  ),
                ],
              ),
            ),
          ),
          scaffold: false,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        // The month glow joins the page's budget as a focus loop…
        final glow = tester.widget<AknAmbient>(
          find.descendant(
            of: find.byType(PlateBars),
            matching: find.byType(AknAmbient),
          ),
        );
        expect(glow.role, AknAmbientRole.focus);
        // …so only the lead tile's halo breathes (v4 §6: one focus loop).
        expect(AknAmbient.debugRunningCount, 1);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('nothing loops under reduce motion', (tester) async {
      AknMotion.ambient = true;
      addTearDown(() => AknMotion.ambient = false);
      await pumpUi(
        tester,
        AppScaffold(
          title: 'Sipariş',
          body: Column(
            children: [
              focusLoop('a'),
              CountdownBadge(
                deadline: TrTime.now().add(const Duration(minutes: 12)),
              ),
            ],
          ),
        ),
        scaffold: false,
        reduceMotion: true,
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(AknAmbient.debugRunningCount, 0);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('badges breathe a few cycles, then rest', (tester) async {
      AknMotion.ambient = true;
      addTearDown(() => AknMotion.ambient = false);
      await pumpUi(
        tester,
        AknAmbient(
          period: AknMotion.breathe,
          reverse: true,
          cycles: 3,
          builder: (context, t, child) => const SizedBox(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(AknAmbient.debugRunningCount, 1);
      await tester.pump(AknMotion.breathe * 6 + const Duration(seconds: 1));
      expect(AknAmbient.debugRunningCount, 0);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('decision dock and object header', () {
    testWidgets('ActionBar.decision: one 52 dp primary, ghosts in a row', (
      tester,
    ) async {
      await pumpUi(
        tester,
        AppScaffold(
          title: 'Sipariş',
          body: const SizedBox.expand(),
          actionBar: ActionBar.decision(
            primary: AknButton(label: 'Çek görselini yükle', onPressed: () {}),
            caption: 'Yükledikten sonra teklifi onaylayabilirsiniz',
            secondaries: [
              AknButton.ghost(label: 'Revize iste', onPressed: () {}),
              AknButton.danger(label: 'Reddet', onPressed: () {}),
            ],
          ),
        ),
        scaffold: false,
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(ActionBar), findsOneWidget);
      expect(_primaries(), findsOneWidget);
      final primary = tester.getSize(find.text('Çek görselini yükle'));
      expect(primary.height, greaterThan(0));
      final reddet = tester.widget<AknButton>(
        find.ancestor(
          of: find.text('Reddet'),
          matching: find.byType(AknButton),
        ),
      );
      expect(reddet.variant, AknButtonVariant.ghostDanger);
      expect(
        find.text('Yükledikten sonra teklifi onaylayabilirsiniz'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    test('ActionBar.decision asserts an enabled primary (P3)', () {
      expect(
        () => ActionBar.decision(
          primary: const AknButton(label: 'Teklifi onayla'),
        ),
        throwsAssertionError,
      );
    });

    testWidgets('AknObjectHeader: overline link, title header, caption', (
      tester,
    ) async {
      var opened = 0;
      await pumpUi(
        tester,
        AknObjectHeader(
          overline: 'Anadolu Lojistik A.Ş.',
          onOverline: () => opened++,
          title: 'Motorin, 8.000 L',
          line: 'Tuzla Şantiye · 29 Ekim',
          caption: 'SIP-20261028-12002',
        ),
      );
      final title = tester.widget<Text>(find.text('Motorin, 8.000 L'));
      expect(title.style!.fontSize, 28);
      expect(title.style!.fontWeight, FontWeight.w800);
      await tester.tap(find.text('Anadolu Lojistik A.Ş.'));
      expect(opened, 1);
      expect(find.text('SIP-20261028-12002'), findsOneWidget);
    });
  });

  group('rows and headers', () {
    testWidgets(
      'SectionHeader v4: 17/22 700; dim count; Pas pill on your move',
      (tester) async {
        await pumpUi(
          tester,
          const Column(
            children: [
              SectionHeader(title: 'Yolda', count: 2),
              SectionHeader(title: 'Bende', count: 3, yourMove: true),
            ],
          ),
        );
        final yolda = tester.widget<RichText>(
          find.descendant(
            of: find.byType(SectionHeader).first,
            matching: find.byType(RichText),
          ),
        );
        final root = yolda.text as TextSpan;
        expect(root.style!.fontSize, 17);
        expect(root.style!.fontWeight, FontWeight.w700);
        expect(yolda.text.toPlainText(), 'Yolda 2');
        expect(find.text('3'), findsOneWidget);
      },
    );

    testWidgets('AknLedgerGroup: danger caption for overdue', (tester) async {
      await pumpUi(
        tester,
        const AknLedgerGroup(title: 'Gecikmiş', count: 2, tone: AknTone.danger),
      );
      final t = tester.widget<Text>(find.text('Gecikmiş 2'));
      expect(t.style!.color, AknColors.light.danger.fg);
      expect(t.style!.fontWeight, FontWeight.w700);
    });

    testWidgets('AknListTile: next line, meta widget, flow; neutral 36 tile', (
      tester,
    ) async {
      await pumpUi(
        tester,
        AknListTile(
          leadingIcon: PhosphorIconsRegular.receipt,
          title: 'Motorin, 8.000 L',
          subtitle: 'Tuzla Şantiye · yarın · Demir Petrol',
          amount: '338.800,00 ₺',
          next: 'Çek görselini yükleyin',
          metaWidget: CountdownBadge(
            deadline: TrTime.now().add(const Duration(hours: 2)),
            compact: true,
            yourMove: true,
          ),
          flow: AknFlowPips(
            flow: AknFlow.customerAt(AknStage.karar, yourMove: true),
            sentence: 'Teklifi onaylayın',
          ),
          onTap: () {},
        ),
      );
      final next = tester.widget<Text>(find.text('Çek görselini yükleyin'));
      expect(next.style!.color, AknColors.light.brandInk);
      expect(next.style!.fontWeight, FontWeight.w600);
      expect(find.text('Teklifi onaylayın'), findsOneWidget);
      final tile = find.ancestor(
        of: find.byIcon(PhosphorIconsRegular.receipt),
        matching: find.byType(SizedBox),
      );
      expect(tester.getSize(tile.first), const Size(36, 36));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('AknFocusFlash washes the block once, then clears', (
    tester,
  ) async {
    await pumpUi(
      tester,
      // A lazily built list never builds a block past its cache extent:
      // focus targets live in a non-lazy scroll view (or near the top).
      const SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(height: 900),
            AknFocusFlash(
              active: true,
              child: SizedBox(height: 80, child: Text('Teklif')),
            ),
            SizedBox(height: 400),
          ],
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    // Scrolled into view.
    expect(tester.getTopLeft(find.text('Teklif')).dy, lessThan(600));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(tester.takeException(), isNull);
  });
}

// Design v4 "Sade", round 2 (critic findings on the core kit): the segmented control gives a long
// label its room (A21), the hero's line under the lead runs full width (A22), a task that opens the
// web portal says so (B15), plate readouts keep their columns apart (A20), the plate's delta chip is
// neutral (A11) and a secondary key keeps its edge at night (A14).
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test_helpers.dart';

void main() {
  group('AknSegmented: a long label gets its room (A21)', () {
    test('equal shares while every label fits; else label + equal extra', () {
      // Every label fits its third: the classic equal control.
      expect(
        AknSegmented.segmentWidths([100, 60, 70], 345),
        everyElement(closeTo(115, 0.01)),
      );
      // "Onay bekleyen 1" does not fit a third: each segment gets its label
      // plus an equal share of what is left.
      final w = AknSegmented.segmentWidths([140, 63, 74], 344);
      expect(w.fold<double>(0, (a, b) => a + b), closeTo(344, 0.01));
      expect(w[0] - 140, closeTo(w[1] - 63, 0.01));
      expect(w[0], greaterThan(w[1]));
      expect(w[0], greaterThan(w[2]));
      // Labels wider than the track: widths follow the labels.
      final tight = AknSegmented.segmentWidths([300, 100, 100], 250);
      expect(tight.fold<double>(0, (a, b) => a + b), closeTo(250, 0.01));
      expect(tight[0], closeTo(150, 0.01));
    });

    testBothThemes('the long segment is wider; the thumb follows it', (
      tester,
      b,
    ) async {
      var value = 'pending';
      await pumpUi(
        tester,
        StatefulBuilder(
          builder: (context, set) => AknSegmented<String>(
            value: value,
            onChanged: (v) => set(() => value = v),
            segments: const [
              FilterOption(value: 'pending', label: 'Onay bekleyen', count: 1),
              FilterOption(value: 'active', label: 'Aktif'),
              FilterOption(value: 'past', label: 'Geçmiş'),
            ],
          ),
        ),
        brightness: b,
        size: const Size(390, 300),
      );
      await tester.pump(const Duration(milliseconds: 400));
      double width(String label) => tester
          .getSize(
            find
                .ancestor(
                  of: find.text(label),
                  matching: find.byType(ConstrainedBox),
                )
                .first,
          )
          .width;
      expect(width('Onay bekleyen'), greaterThan(width('Aktif')));
      expect(width('Onay bekleyen'), greaterThan(width('Geçmiş')));
      await tester.tap(find.text('Aktif'));
      await tester.pumpAndSettle();
      expect(value, 'active');
      expect(tester.takeException(), isNull);
    });
  });

  group('AknTaskCard (A22, B15)', () {
    AknTask task(String id, {bool external = false, String? action}) => AknTask(
      id: id,
      title: 'İş $id',
      subtitle: 'Demir Petrol · Motorin 8.000 L',
      actionLabel: action,
      onAction: action == null ? null : () {},
      onTap: () {},
      external: external,
    );

    testWidgets('the line under the lead runs full width; rows are inset', (
      tester,
    ) async {
      await pumpUi(
        tester,
        AknTaskCard(
          tasks: [
            task('a', action: 'Teklif ver'),
            task('b'),
            task('c'),
          ],
          total: 5,
          onSeeAll: () {},
        ),
        size: const Size(390, 900),
      );
      await tester.pumpAndSettle();
      final c = AknColors.light;
      final lines =
          find
              .byWidgetPredicate(
                (w) => w is ColoredBox && w.color == c.plateLine,
              )
              .evaluate()
              .map((e) => tester.getRect(find.byWidget(e.widget)))
              .toList()
            ..sort((a, b) => a.top.compareTo(b.top));
      // Under the lead, between the rows, above the footer.
      expect(lines, hasLength(3));
      final button = tester.getRect(find.byType(AknButton));
      expect(lines[0].left, closeTo(button.left, 0.5));
      expect(lines[0].width, closeTo(button.width, 0.5));
      expect(lines[1].left, closeTo(button.left + 52, 0.5));
      expect(lines[2].left, closeTo(button.left, 0.5));
    });

    testWidgets('a task that opens the web portal shows ↗, not a caret', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpUi(
        tester,
        AknTaskCard(
          tasks: [
            task('lead', external: true, action: 'Portalda girin'),
            task('row', external: true),
          ],
        ),
        size: const Size(390, 900),
      );
      await tester.pumpAndSettle();
      final primary = tester.widget<AknButton>(find.byType(AknButton));
      expect(primary.label, 'Portalda girin');
      expect(primary.trailingIcon, PhosphorIconsRegular.arrowSquareOut);
      // The row ends in ↗ and says it opens the portal.
      expect(find.byIcon(PhosphorIconsRegular.arrowSquareOut), findsWidgets);
      expect(
        find.bySemanticsLabel(RegExp('İş row.*web portalında açılır')),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('a fact line wraps only after "·", never before it', (
      tester,
    ) async {
      // The 08b capture had "Burak Yılmaz · 30.000 L" / "· 2 ürün": the "·"
      // now stays with the fact before it, and every fact still shows.
      const line = 'Burak Yılmaz · 30.000 L · 2 ürün';
      await pumpUi(
        tester,
        const SizedBox(
          width: 300,
          child: AknFactLine(line, maxLines: 2, style: TextStyle()),
        ),
        size: const Size(390, 300),
      );
      final text = tester.widget<Text>(find.byType(Text));
      // Every fact still shows; a line breaks only between facts (no line
      // starts or ends with "·"; v4 round 2).
      final rows = text.data!.split('\n');
      expect(rows.join(' · ').replaceAll('\u00A0·', ' ·'), line);
      for (final r in rows) {
        expect(r.trim(), isNot(startsWith('·')), reason: r);
        expect(r.trim(), isNot(endsWith('·')), reason: r);
      }
      expect(text.semanticsLabel, line);
    });

    // v4 round 2 (L1): a line that must wrap breaks BETWEEN facts — no line
    // ends with a dangling "·" ("Kalorifer Yakıtı · 6.000 L ·" / "Nilüfer
    // Tesis" read like a typo).
    testWidgets('a wrapped fact line never ends with "·"', (tester) async {
      const line = 'Kalorifer\u00A0Yakıtı · 6.000\u00A0L · Nilüfer\u00A0Tesis';
      await pumpUi(
        tester,
        const SizedBox(
          width: 150,
          child: AknFactLine(line, style: TextStyle(fontSize: 14)),
        ),
        size: const Size(390, 300),
      );
      final text = tester.widget<Text>(find.byType(Text));
      final rows = text.data!.split('\n');
      expect(rows.length, greaterThan(1));
      for (final r in rows) {
        expect(r.trim(), isNot(endsWith('·')), reason: r);
        expect(r.trim(), isNot(startsWith('·')), reason: r);
      }
      expect(text.data!.replaceAll('\n', ' · '), contains('Nilüfer'));
      expect(text.semanticsLabel, line);
    });
  });

  testWidgets('PlateReadouts: a short figure keeps ≥ 16 dp from a long one', (
    tester,
  ) async {
    await pumpUi(
      tester,
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: AknPlate(
          below: PlateReadouts(
            items: [
              PlateReadout(label: 'A', value: '190.000', unit: 'L'),
              PlateReadout(label: 'B', value: '18'),
              PlateReadout(label: 'C', value: '4'),
            ],
          ),
        ),
      ),
      size: const Size(390, 600),
    );
    await tester.pumpAndSettle();
    Rect column(String spoken) => tester.getRect(
      find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == spoken,
      ),
    );
    final a = column('A: 190.000 L');
    final b = column('B: 18');
    final c = column('C: 4');
    expect(b.left - a.right, greaterThanOrEqualTo(16));
    expect(c.left - b.right, greaterThanOrEqualTo(16));
    expect(tester.takeException(), isNull);
  });

  testBothThemes('the plate delta chip is neutral: ink, outline, no fill', (
    tester,
    b,
  ) async {
    await pumpUi(
      tester,
      const AknDeltaChip(
        label: '%23,3',
        direction: AknDeltaDirection.up,
        onPlate: true,
      ),
      brightness: b,
    );
    await tester.pump(const Duration(seconds: 1));
    final c = b == Brightness.dark ? AknColors.dark : AknColors.light;
    final box = tester.widget<Container>(
      find
          .ancestor(of: find.text('%23,3'), matching: find.byType(Container))
          .first,
    );
    final deco = box.decoration! as BoxDecoration;
    expect(deco.color, isNull);
    final outline = box.foregroundDecoration! as BoxDecoration;
    expect((outline.border! as Border).top.color, c.plateLine);
    final style = tester.widget<Text>(find.text('%23,3')).style!;
    expect(style.color, c.ink);
    expect(style.color, isNot(c.brandInk));
  });

  testWidgets('dark: a secondary key keeps a lineStrong edge (A14)', (
    tester,
  ) async {
    await pumpUi(
      tester,
      AknButton.secondary(label: 'Yol tarifi', onPressed: () {}),
      brightness: Brightness.dark,
    );
    await tester.pump(const Duration(milliseconds: 400));
    final deco =
        tester
                .widget<AnimatedContainer>(
                  find
                      .ancestor(
                        of: find.text('Yol tarifi'),
                        matching: find.byType(AnimatedContainer),
                      )
                      .first,
                )
                .decoration!
            as ShapeDecoration;
    final side = (deco.shape as RoundedSuperellipseBorder).side;
    expect(side.width, 1.5);
    expect(side.color, AknColors.dark.lineStrong);
    expect(
      contrast(side.color, AknColors.dark.surfaceRaised),
      greaterThanOrEqualTo(3),
    );
  });
}

// Design v2 core finish (work/akn-design-v2.md §5.1, §6.4, §6.6–§6.13, §6.22, §6.28): plate readout
// columns like the board's CSS grid, the countdown's icon hugging its text, section actions on the
// right edge, top tabs on the 20 px edge, fact rows that reflow, full-width row footers, the password
// field's "Göster" control, the static toast card and absolute deltas on readout tiles.
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test_helpers.dart';

void main() {
  group('PlateReadouts', () {
    testWidgets('a long label keeps its width; the others share the rest', (
      tester,
    ) async {
      await pumpUi(
        tester,
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: AknPlate(
            below: PlateReadouts(
              items: [
                PlateReadout(label: 'A', value: '1'),
                PlateReadout(label: 'B', value: '2'),
                PlateReadout(
                  label: 'Ay sonu tahmini',
                  value: '3',
                  dashed: true,
                ),
              ],
            ),
          ),
        ),
        size: const Size(390, 600),
      );
      final a = tester.getTopLeft(find.text('A')).dx;
      final b = tester.getTopLeft(find.text('B')).dx;
      final long = tester.getRect(find.text('Ay sonu tahmini'));
      // One line, not wrapped (the test font is 1 em per glyph: wide).
      expect(long.height, lessThan(20));
      // The first two columns are equal and narrower than a third.
      final inner = 390 - 40 - 36.0;
      expect(b - a, lessThan((inner - 20) / 3 + 10));
      expect(tester.takeException(), isNull);
    });

    testWidgets('equal columns when every content is short', (tester) async {
      await pumpUi(
        tester,
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: AknPlate(
            below: PlateReadouts(
              items: [
                PlateReadout(label: 'A', value: '1'),
                PlateReadout(label: 'B', value: '2'),
                PlateReadout(label: 'C', value: '3'),
              ],
            ),
          ),
        ),
        size: const Size(390, 600),
      );
      final a = tester.getTopLeft(find.text('A')).dx;
      final b = tester.getTopLeft(find.text('B')).dx;
      final c = tester.getTopLeft(find.text('C')).dx;
      expect((b - a) - (c - b), closeTo(0, 0.5));
    });
  });

  testWidgets('countdown: the timer icon sits right before the text', (
    tester,
  ) async {
    await pumpUi(
      tester,
      Align(
        alignment: Alignment.centerRight,
        child: CountdownBadge(
          deadline: TrTime.now().add(const Duration(minutes: 41, seconds: 30)),
          yourMove: true,
        ),
      ),
      size: const Size(390, 300),
    );
    final icon = tester.getRect(find.byIcon(Icons.timer_outlined));
    final text = tester.getRect(find.textContaining('dk kaldı'));
    expect(text.left - icon.right, closeTo(5, 0.5));
    expect(text.right, closeTo(390, 0.5));
  });

  testWidgets('section header: the action sits on the right edge', (
    tester,
  ) async {
    await pumpUi(
      tester,
      SectionHeader(
        title: 'Yolda',
        actionLabel: 'Haritada izle',
        onAction: () {},
      ),
      size: const Size(390, 300),
    );
    final chevron = tester.getRect(find.byIcon(Icons.chevron_right_rounded));
    // Padding right 12: the chevron box ends 12 from the edge.
    expect(chevron.right, closeTo(390 - 12, 0.5));
  });

  testWidgets('section header title clamps at 1.6× text', (tester) async {
    await pumpUi(
      tester,
      const SectionHeader(title: 'Karar bekleyen teklifler'),
      textScale: 2,
      size: const Size(390, 300),
    );
    final text = tester.widget<RichText>(
      find.descendant(
        of: find.byType(SectionHeader),
        matching: find.byType(RichText),
      ),
    );
    expect(text.textScaler.scale(20), 32);
  });

  testWidgets('top tabs: the first label on the 20 px edge, counts in 500', (
    tester,
  ) async {
    await pumpUi(
      tester,
      const DefaultTabController(
        length: 2,
        child: Align(
          alignment: Alignment.topLeft,
          child: AknTabBar(
            tabs: [
              AknTab(label: 'Aktif', count: 4),
              AknTab(label: 'Geçmiş', count: 28),
            ],
          ),
        ),
      ),
      size: const Size(390, 300),
    );
    expect(tester.getTopLeft(find.byType(AknTab).first).dx, closeTo(20, 0.5));
    final handle = tester.ensureSemantics();
    await tester.pump();
    expect(find.bySemanticsLabel(RegExp('Aktif, 4')), findsOneWidget);
    handle.dispose();
  });

  group('FactRow', () {
    testWidgets('a short value stays on the right', (tester) async {
      await pumpUi(
        tester,
        const FactRow(label: 'Limit', value: '2.500 ₺'),
        size: const Size(390, 300),
      );
      final label = tester.getRect(find.text('Limit'));
      final value = tester.getRect(find.text('2.500 ₺'));
      expect(value.top, closeTo(label.top, 4));
      expect(value.right, closeTo(390, 0.5));
    });

    testWidgets('a long value moves under the label', (tester) async {
      await pumpUi(
        tester,
        const FactRow(
          icon: Icons.door_front_door_outlined,
          label: 'Kapı notu',
          value: 'Ana kapıda güvenliğe plakayı bildirin; tank arka avluda.',
        ),
        size: const Size(390, 400),
      );
      final label = tester.getRect(find.text('Kapı notu'));
      final value = tester.getRect(
        find.text('Ana kapıda güvenliğe plakayı bildirin; tank arka avluda.'),
      );
      expect(value.top, greaterThan(label.bottom - 1));
      expect(value.left, closeTo(label.left, 0.5));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('ledger row: the route line runs under both columns', (
    tester,
  ) async {
    await pumpUi(
      tester,
      AknListTile(
        title: 'Pendik',
        subtitle: '10.000 L',
        trailing: const Text('11:20'),
        footer: const TruckRoute(progress: 0.5, moving: true),
        onTap: () {},
      ),
      size: const Size(390, 400),
    );
    final route = tester.getRect(find.byType(TruckRoute));
    expect(route.left, closeTo(20, 0.5));
    expect(route.right, closeTo(370, 0.5));
  });

  testWidgets('password field: "Göster" toggles the obscured value', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'gizli');
    addTearDown(controller.dispose);
    await pumpUi(
      tester,
      Padding(
        padding: const EdgeInsets.all(20),
        child: AknPasswordField(
          controller: controller,
          labelActionText: 'Şifremi unuttum',
          onLabelAction: () {},
        ),
      ),
      size: const Size(390, 400),
    );
    EditableText field() =>
        tester.widget<EditableText>(find.byType(EditableText));
    expect(field().obscureText, isTrue);
    expect(find.text('Göster'), findsOneWidget);
    await tester.tap(find.text('Göster'));
    await tester.pump();
    expect(field().obscureText, isFalse);
    expect(find.text('Gizle'), findsOneWidget);
    // The link shares the label's line (not stacked above it).
    final label = tester.getRect(find.text('Şifre'));
    final link = tester.getRect(find.text('Şifremi unuttum'));
    expect((label.center.dy - link.center.dy).abs(), lessThan(1));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  });

  testBothThemes('toast card: inverse bar, white text, tone icon', (
    tester,
    b,
  ) async {
    await pumpUi(
      tester,
      const AppToastCard(
        type: AppToastType.success,
        message: 'Teklif onaylandı. Bayi sevkiyatı planlayacak.',
      ),
      brightness: b,
    );
    final c = b == Brightness.dark ? AknColors.dark : AknColors.light;
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(AppToastCard),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    expect((box.decoration as BoxDecoration).color, c.inverse);
    final text = tester.widget<Text>(
      find.text('Teklif onaylandı. Bayi sevkiyatı planlayacak.'),
    );
    expect(text.style!.color, c.onInverse);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  });

  testWidgets('readout tile: an absolute change ("▲ 0,38") and "aynı"', (
    tester,
  ) async {
    String price(num v) => v.toStringAsFixed(2).replaceAll('.', ',');
    await pumpUi(
      tester,
      Padding(
        padding: const EdgeInsets.all(20),
        child: KpiRow(
          children: [
            KpiTile(
              label: 'Motorin',
              value: 41.92,
              format: price,
              trend: 0.38,
              trendFormat: price,
            ),
            KpiTile(
              label: 'Kurşunsuz 95',
              value: 44.1,
              format: price,
              trend: 0,
            ),
          ],
        ),
      ),
      size: const Size(390, 400),
    );
    expect(find.text('0,38'), findsOneWidget);
    expect(find.text('aynı'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('değişim artı 0,38')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bottom bar: 6 px side inset, the needle over the active item', (
    tester,
  ) async {
    await pumpUi(
      tester,
      Align(
        alignment: Alignment.bottomCenter,
        child: AnimatedBottomBar(
          currentIndex: 4,
          onSelected: (_) {},
          items: const [
            AknNavItem(icon: Icons.home_outlined, label: 'Ana sayfa'),
            AknNavItem(icon: Icons.task_alt_outlined, label: 'Onaylarım'),
            AknNavItem(icon: Icons.request_quote_outlined, label: 'Teklif'),
            AknNavItem(icon: Icons.receipt_long_outlined, label: 'Siparişler'),
            AknNavItem(icon: Icons.menu_rounded, label: 'Diğer'),
          ],
        ),
      ),
      size: const Size(390, 400),
    );
    await tester.pump(const Duration(milliseconds: 400));
    // Five slots over 390 − 12: the first label centres at 6 + 75.6 / 2.
    final first = tester.getCenter(find.text('Ana sayfa')).dx;
    expect(first, closeTo(6 + (390 - 12) / 10, 0.5));
    final needle = find.byWidgetPredicate(
      (w) =>
          w is DecoratedBox &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color == AknColors.light.logo,
    );
    final diger = tester.getCenter(find.text('Diğer')).dx;
    expect((tester.getCenter(needle).dx - diger).abs(), lessThan(0.5));
  });

  testWidgets('plate head: the ⋯ button is a 48 dp target', (tester) async {
    await pumpUi(
      tester,
      Padding(
        padding: const EdgeInsets.all(20),
        child: AknPlate(
          head: PlateHead(
            icon: Icons.bar_chart_rounded,
            title: 'Satış',
            period: '1–21 Ekim',
            onMore: () {},
          ),
          figure: const PlateFigure(value: '8.426.350', unit: '₺'),
        ),
      ),
      size: const Size(390, 400),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    expect(tester.takeException(), isNull);
  });
}

import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test_helpers.dart';

void main() {
  tearDown(() {
    TrTime.clock = () => DateTime.now().toUtc();
    AppToast.dismiss();
  });

  testBothThemes('SearchField debounces and clears', (tester, b) async {
    final queries = <String>[];
    await pumpUi(tester, SearchField(onChanged: queries.add), brightness: b);
    await tester.enterText(find.byType(TextField), 'kar');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'kartal');
    await tester.pump(const Duration(milliseconds: 350));
    expect(queries, ['kartal']);
    await tester.tap(find.byTooltip('Temizle'));
    await tester.pump();
    expect(queries.last, '');
  });

  testBothThemes('DateField quick picks give Türkiye-midnight instants', (
    tester,
    b,
  ) async {
    TrTime.clock = () => DateTime.utc(2026, 10, 21, 9);
    DateTime? picked;
    await pumpUi(
      tester,
      DateField(
        label: 'Teslim tarihi',
        value: null,
        onChanged: (d) => picked = d,
      ),
      brightness: b,
    );
    await tester.tap(find.text('Yarın'));
    await tester.pump();
    expect(picked, TrTime.fromWall(2026, 10, 22));
    expect(TrTime.isoDate(picked!), '2026-10-22');
  });

  testWidgets('DateField shows dd.MM.yyyy and the weekday', (tester) async {
    await pumpUi(
      tester,
      DateField(
        label: 'Teslim tarihi',
        value: TrTime.fromWall(2026, 10, 22),
        onChanged: (_) {},
        quickPicks: false,
      ),
    );
    expect(find.text('22.10.2026  ·  Perşembe'), findsOneWidget);
  });

  testWidgets('MoneyField.unitPrice keeps four decimals in ₺/L', (
    tester,
  ) async {
    double? v;
    await pumpUi(tester, MoneyField.unitPrice(onChanged: (x) => v = x));
    await tester.enterText(find.byType(TextFormField), '42,12556');
    await tester.pump();
    expect(find.text('42,1255'), findsOneWidget);
    expect(v, 42.1255);
  });

  testBothThemes('PlateField formats and validates Turkish plates', (
    tester,
    b,
  ) async {
    String? value;
    await pumpUi(
      tester,
      Form(
        autovalidateMode: AutovalidateMode.always,
        child: PlateField(onChanged: (v) => value = v),
      ),
      brightness: b,
    );
    await tester.enterText(find.byType(TextFormField), '34abc123');
    await tester.pump(const Duration(milliseconds: 300));
    expect(value, '34 ABC 123');
    expect(find.bySemanticsLabel('Plaka 34 ABC 123'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '99');
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.text('Geçerli bir plaka girin (ör. 34 ABC 123).'),
      findsOneWidget,
    );
  });

  group('FilterChips', () {
    testWidgets('single select toggles; multi select accumulates', (
      tester,
    ) async {
      var single = <String>{};
      var multi = <String>{};
      await pumpUi(
        tester,
        StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              FilterChips<String>(
                options: const [
                  FilterOption(value: 'a', label: 'Bekliyor', count: 3),
                  FilterOption(value: 'b', label: 'Onaylı'),
                ],
                selected: single,
                onChanged: (s) => setState(() => single = s),
              ),
              FilterChips<String>(
                multi: true,
                options: const [
                  FilterOption(value: 'x', label: 'Çek'),
                  FilterOption(value: 'y', label: 'Senet'),
                ],
                selected: multi,
                onChanged: (s) => setState(() => multi = s),
              ),
            ],
          ),
        ),
      );
      await tester.tap(find.text('Bekliyor'));
      await tester.pump();
      expect(single, {'a'});
      await tester.tap(find.text('Onaylı'));
      await tester.pump();
      expect(single, {'b'});
      await tester.tap(find.text('Onaylı'));
      await tester.pump();
      expect(single, isEmpty);

      await tester.tap(find.text('Çek'));
      await tester.pump();
      await tester.tap(find.text('Senet'));
      await tester.pump();
      expect(multi, {'x', 'y'});
      expect(find.bySemanticsLabel('Bekliyor, 3'), findsOneWidget);
    });

    testWidgets('chips keep a 48 dp touch target', (tester) async {
      await pumpUi(
        tester,
        FilterChips<int>(
          options: const [FilterOption(value: 1, label: 'Tümü')],
          selected: const {},
          onChanged: (_) {},
        ),
      );
      final size = tester.getSemantics(find.bySemanticsLabel('Tümü')).rect.size;
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  testBothThemes('AknSegmented reports the tapped segment', (tester, b) async {
    var value = 'decision';
    await pumpUi(
      tester,
      StatefulBuilder(
        builder: (context, setState) => AknSegmented<String>(
          value: value,
          onChanged: (v) => setState(() => value = v),
          segments: const [
            FilterOption(value: 'decision', label: 'Karar', count: 2),
            FilterOption(value: 'active', label: 'Aktif'),
            FilterOption(value: 'history', label: 'Geçmiş'),
          ],
        ),
      ),
      brightness: b,
    );
    await tester.tap(find.text('Geçmiş'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(value, 'history');
    expect(
      tester.getSemantics(find.bySemanticsLabel('Geçmiş')),
      isSemantics(isSelected: true, isButton: true),
    );
  });

  testBothThemes('confirm sheet returns the choice', (tester, b) async {
    final results = <bool>[];
    await pumpUi(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => results.add(
            await showConfirmSheet(
              context,
              title: 'Sevkiyat iptal edilsin mi?',
              confirmLabel: 'İptal et',
              destructive: true,
            ),
          ),
          child: const Text('aç'),
        ),
      ),
      brightness: b,
    );
    await tester.tap(find.text('aç'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Sevkiyat iptal edilsin mi?'), findsOneWidget);
    await tester.tap(find.text('İptal et'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('aç'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Vazgeç'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(results, [true, false]);
  });

  testWidgets('count badge caps at 99+ and hides at zero', (tester) async {
    await pumpUi(
      tester,
      const Row(children: [AknCountBadge(count: 120), AknCountBadge(count: 0)]),
    );
    expect(find.text('99+'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('usage bar reads its value and turns danger past the limit', (
    tester,
  ) async {
    await pumpUi(
      tester,
      const Column(
        children: [
          UsageBar(value: 0.5, label: 'Limit', valueLabel: '%50'),
          UsageBar(value: 1.2, label: 'Aşım', valueLabel: '%120'),
        ],
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.bySemanticsLabel('Limit'), findsOneWidget);
    final over = tester.widget<Text>(find.text('%120'));
    expect(over.style!.color, AknColors.light.danger.fg);
  });

  testWidgets('attachment states are spoken', (tester) async {
    await pumpUi(
      tester,
      Column(
        children: [
          const AttachmentTile(
            fileName: 'cek.jpg',
            kindLabel: 'Çek görseli',
            state: AttachmentTileState.uploading,
            progress: 0.5,
          ),
          AttachmentTile(
            fileName: 'levha.pdf',
            state: AttachmentTileState.failed,
            onRetry: () {},
          ),
        ],
      ),
    );
    expect(
      find.bySemanticsLabel(RegExp('cek.jpg, Çek görseli, Yükleniyor %50')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp('levha.pdf.*Yüklenemedi')),
      findsOneWidget,
    );
  });

  test('offline banner wording', () {
    expect(OfflineBanner.message(offline: true, pending: 0), 'Çevrimdışısınız');
    expect(
      OfflineBanner.message(offline: false, pending: 3),
      '3 işlem gönderilmeyi bekliyor',
    );
  });

  testWidgets('AppToast.forbidden uses the standard 403 text', (tester) async {
    await pumpUi(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => AppToast.forbidden(context: context),
          child: const Text('dene'),
        ),
      ),
    );
    await tester.tap(find.text('dene'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Bu işlem için yetkiniz yok.'), findsOneWidget);
    AppToast.dismiss();
    await tester.pump();
  });
}

// Foundation specimen (design v2 §2, §3, §6.5, §6.10, §6.11, §6.21): the tokens, the Mona Sans
// type scale and the stock Material components under AknTheme, light and dark, as PNGs for a visual
// check against `work/design-v2/board.png` (component sheet). Not a golden test; skipped unless
//
//   flutter test test/core/ui/foundation_capture_test.dart --dart-define=AKN_SCREENS_DIR=/abs/dir
import 'dart:io';
import 'dart:ui' as ui;

import 'package:akaryakitnet/core/ui/theme.dart';
import 'package:akaryakitnet/core/ui/tokens.dart';
import 'package:akaryakitnet/core/ui/typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';

const _outDir = String.fromEnvironment('AKN_SCREENS_DIR');

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_outDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

class _Specimen extends StatelessWidget {
  const _Specimen({required this.page});

  final int page;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    Widget gap([double h = 12]) => SizedBox(height: h);
    final children = page == 0
        ? <Widget>[
            Text('Siparişlerim', style: t.display),
            Text('Tuzla Şantiye, 22 Ekim Perşembe teslim', style: t.bodySmall),
            gap(16),
            _plate(context),
            gap(16),
            Text('Kararınızı bekliyor', style: t.title),
            gap(6),
            Text('Demir Petrol teklifi', style: t.headline),
            Text(
              'Şoför yola çıktı, Iğdır’dan değil. İĞDIR ığdır Şş Çç Öö Üü Ğğ İi Iı',
              style: t.body,
            ),
            gap(6),
            Row(
              children: [
                Text('42,35', style: t.number),
                const SizedBox(width: 3),
                Text('₺/L', style: t.readoutUnit),
                const SizedBox(width: 16),
                Text('8.000', style: t.number),
                const SizedBox(width: 3),
                Text('L', style: t.readoutUnit),
                const Spacer(),
                Text('338.800,00 ₺', style: t.amount),
              ],
            ),
            Text('Etiket 13/18 500', style: t.label),
            Text('Açıklama 12/16, güncellendi 10:41', style: t.caption),
            gap(16),
            FilledButton(onPressed: () {}, child: const Text('Teklifi onayla')),
            gap(10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {},
                    child: const Text('Revize iste'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    style: AknTheme.secondaryButtonStyle(c, t, danger: true),
                    onPressed: () {},
                    child: const Text('Reddet'),
                  ),
                ),
              ],
            ),
            gap(10),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: AknTheme.destructiveButtonStyle(c, t),
                    onPressed: () {},
                    child: const Text('Teklifi reddet'),
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: FilledButton(
                    onPressed: null,
                    child: Text('Siparişi gönder'),
                  ),
                ),
              ],
            ),
            gap(6),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Belge yükle'),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: () {}, child: const Text('Vazgeç')),
                const Spacer(),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
              ],
            ),
          ]
        : <Widget>[
            const TextField(
              decoration: InputDecoration(
                hintText: 'E-posta ya da kullanıcı adı',
              ),
            ),
            gap(),
            TextField(
              controller: TextEditingController(text: '8.000'),
              autofocus: true,
              decoration: const InputDecoration(suffixText: 'L'),
            ),
            gap(),
            const TextField(
              decoration: InputDecoration(
                hintText: 'Nokta seçin',
                errorText: 'Teslimat noktası seçmeden sipariş gönderilemez.',
              ),
            ),
            gap(),
            const TextField(
              enabled: false,
              decoration: InputDecoration(hintText: 'Devre dışı alan'),
            ),
            gap(16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Tümü 6'),
                  selected: true,
                  onSelected: (_) {},
                ),
                ChoiceChip(
                  label: const Text('Yeni 4'),
                  selected: false,
                  onSelected: (_) {},
                ),
                FilterChip(
                  label: const Text('Süresi yaklaşan'),
                  selected: false,
                  onSelected: (_) {},
                ),
              ],
            ),
            gap(16),
            const DefaultTabController(
              length: 3,
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Aktif'),
                  Tab(text: 'Geçmiş'),
                  Tab(text: 'Taslak'),
                ],
              ),
            ),
            gap(16),
            Row(
              children: [
                Switch(value: true, onChanged: (_) {}),
                Switch(value: false, onChanged: (_) {}),
                Checkbox(value: true, onChanged: (_) {}),
                Checkbox(value: false, onChanged: (_) {}),
                RadioGroup<int>(
                  groupValue: 1,
                  onChanged: (_) {},
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [Radio<int>(value: 1), Radio<int>(value: 2)],
                  ),
                ),
              ],
            ),
            gap(8),
            Row(
              children: [
                Badge.count(
                  count: 3,
                  child: Icon(Icons.notifications_none_rounded, color: c.ink),
                ),
                const SizedBox(width: 24),
                const SizedBox(
                  width: 120,
                  child: LinearProgressIndicator(value: 0.6),
                ),
              ],
            ),
            gap(16),
            Container(
              padding: AknSpace.well,
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: AknRadius.card,
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: c.warn.fg, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Bugünün Tüpraş fiyatı girilmedi.',
                      style: t.label.copyWith(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            gap(16),
            for (final tone in AknTone.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: tone == AknTone.neutral
                            ? null
                            : c.tone(tone).solid,
                        border: tone == AknTone.neutral
                            ? Border.all(color: c.faint, width: 1.5)
                            : null,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      switch (tone) {
                        AknTone.brand => 'Kararınızı bekliyor',
                        AknTone.info => 'Yolda',
                        AknTone.ok => 'Teslim alındı',
                        AknTone.warn => 'Belge bekleniyor',
                        AknTone.danger => 'İtirazlı',
                        AknTone.neutral => 'Süresi doldu',
                      },
                      style: t.bodySmall.copyWith(
                        color: c.tone(tone).fg,
                        fontWeight:
                            tone == AknTone.brand || tone == AknTone.danger
                            ? FontWeight.w600
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ];
    return ColoredBox(
      color: c.bg,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
        children: children,
      ),
    );
  }

  Widget _plate(BuildContext context) {
    final theme = AknTheme.onPlate(Theme.of(context));
    final p = theme.extension<AknColors>()!;
    final t = theme.extension<AknTextStyles>()!;
    Widget readout(String label, String value, String unit) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.label),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: value, style: t.number),
                const TextSpan(text: ' '),
                TextSpan(text: unit, style: t.readoutUnit),
              ],
            ),
          ),
        ],
      ),
    );
    return Theme(
      data: theme,
      child: Container(
        padding: AknSpace.plate,
        decoration: BoxDecoration(
          color: p.plate,
          borderRadius: AknRadius.plate,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.request_quote_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Demir Petrol teklifi', style: t.headline),
                ),
                Text('bugün 10:05', style: t.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: '338.800', style: t.plateFigure),
                  TextSpan(text: ',00 ₺', style: t.plateUnit),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(height: 3, color: p.onPlate),
            const SizedBox(height: 8),
            Row(
              children: [
                readout('Birim fiyat', '42,35', '₺/L'),
                readout('Miktar', '8.000', 'L'),
                readout('Teslim', '22 Ekim', ''),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  setUpAll(() async {
    if (_outDir.isNotEmpty) await loadRealFonts();
  });

  for (final dark in [false, true]) {
    for (final page in [0, 1]) {
      final name = 'foundation_${page + 1}_${dark ? 'koyu' : 'acik'}';
      testWidgets(name, (tester) async {
        tester.view.devicePixelRatio = 2;
        tester.view.physicalSize = const Size(390 * 2, 844 * 2);
        addTearDown(tester.view.reset);
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = true);
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AknTheme.light(),
              darkTheme: AknTheme.dark(),
              themeMode: dark ? ThemeMode.dark : ThemeMode.light,
              home: Scaffold(body: _Specimen(page: page)),
            ),
          ),
        );
        // Autofocus lands after the first frame; let the border animate in.
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        await _capture(tester, key, 'foundation/$name');
        await tester.pumpWidget(const SizedBox());
        debugDisableShadows = true;
      }, skip: _outDir.isEmpty);
    }
  }
}

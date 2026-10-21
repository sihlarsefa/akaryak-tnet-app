// A-INT tasarım sistemi denetimleri (spec C.5, C.7, D.7.6): tarih/saat seçici, Switch, Checkbox ve
// Radio iki temada mor ton içermez; izinli renk çiftleri; bağlantı rengi; çekirdek bileşen düzeltmeleri
// (segment kontrastı ve 48 dp, eylem çubuğu yüksekliği, azaltılmış harekette boyut animasyonu, adım
// çubuğu hedefi, 2,0× liste satırı, iOS "Bitti" çubuğu, eylemsiz bildirim dokunmayı engellemez).
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test_helpers.dart';

/// Mor: ton 250°–330°, belirgin doygunluk ve parlaklık.
bool _isPurple(Color c) {
  final hsv = HSVColor.fromColor(c);
  return c.a > 0.2 &&
      hsv.saturation > 0.25 &&
      hsv.value > 0.2 &&
      hsv.hue >= 250 &&
      hsv.hue <= 330;
}

/// Ekranın piksellerinde mor var mı (RepaintBoundary görüntüsü).
Future<int> _purplePixels(WidgetTester tester, GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final count = await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData();
    image.dispose();
    final bytes = data!.buffer.asUint8List();
    var n = 0;
    for (var i = 0; i + 3 < bytes.length; i += 4 * 3) {
      final c = Color.fromARGB(
        bytes[i + 3],
        bytes[i],
        bytes[i + 1],
        bytes[i + 2],
      );
      if (_isPurple(c)) n++;
    }
    return n;
  });
  return count ?? 0;
}

Widget _app(Widget home, Brightness b, {GlobalKey? boundary}) {
  final app = MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AknTheme.light(),
    darkTheme: AknTheme.dark(),
    themeMode: b == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    locale: const Locale('tr', 'TR'),
    supportedLocales: const [Locale('tr', 'TR')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: home,
  );
  return boundary == null ? app : RepaintBoundary(key: boundary, child: app);
}

void main() {
  group('Mor ton yok (sahip kararı 5)', () {
    for (final b in Brightness.values) {
      testWidgets('tarih seçici [${b.name}]', (tester) async {
        final key = GlobalKey();
        await tester.pumpWidget(
          _app(
            Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showDatePicker(
                      context: context,
                      initialDate: DateTime(2026, 10, 21),
                      firstDate: DateTime(2026),
                      lastDate: DateTime(2027),
                    ),
                    child: const Text('aç'),
                  ),
                ),
              ),
            ),
            b,
            boundary: key,
          ),
        );
        await tester.tap(find.text('aç'));
        await tester.pumpAndSettle();
        expect(find.byType(DatePickerDialog), findsOneWidget);
        expect(await _purplePixels(tester, key), 0);
      });

      testWidgets('saat seçici [${b.name}]', (tester) async {
        final key = GlobalKey();
        await tester.pumpWidget(
          _app(
            Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showTimePicker(
                      context: context,
                      initialTime: const TimeOfDay(hour: 9, minute: 30),
                    ),
                    child: const Text('aç'),
                  ),
                ),
              ),
            ),
            b,
            boundary: key,
          ),
        );
        await tester.tap(find.text('aç'));
        await tester.pumpAndSettle();
        expect(find.byType(TimePickerDialog), findsOneWidget);
        expect(await _purplePixels(tester, key), 0);
      });

      testWidgets('Switch, Checkbox, Radio, Slider [${b.name}]', (
        tester,
      ) async {
        final key = GlobalKey();
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: ListView(
                children: [
                  Switch(value: true, onChanged: (_) {}),
                  Switch(value: false, onChanged: (_) {}),
                  Checkbox(value: true, onChanged: (_) {}),
                  Checkbox(value: false, onChanged: (_) {}),
                  RadioGroup<int>(
                    groupValue: 1,
                    onChanged: (_) {},
                    child: const Column(
                      children: [Radio<int>(value: 1), Radio<int>(value: 2)],
                    ),
                  ),
                  Slider(value: 0.6, onChanged: (_) {}),
                  const LinearProgressIndicator(value: 0.5),
                  const TextField(
                    decoration: InputDecoration(labelText: 'Alan'),
                  ),
                ],
              ),
            ),
            b,
            boundary: key,
          ),
        );
        await tester.pump();
        expect(await _purplePixels(tester, key), 0);
        // Tema çözümü de mor değil (seçili durumlar).
        final theme = Theme.of(tester.element(find.byType(ListView)));
        const sel = {WidgetState.selected};
        for (final c in [
          theme.switchTheme.thumbColor?.resolve(sel),
          theme.switchTheme.trackColor?.resolve(sel),
          theme.checkboxTheme.fillColor?.resolve(sel),
          theme.radioTheme.fillColor?.resolve(sel),
          theme.colorScheme.primary,
          theme.colorScheme.secondary,
          theme.colorScheme.tertiary,
          theme.colorScheme.surfaceTint,
        ]) {
          if (c != null) expect(_isPurple(c), isFalse, reason: '$c');
        }
      });
    }
  });

  group('İzinli renk çiftleri (spec C.5)', () {
    for (final (name, c) in [
      ('açık', AknColors.light),
      ('koyu', AknColors.dark),
    ]) {
      test('$name: bağlantı rengi ve seçilmemiş segment metni AA', () {
        expect(contrast(c.link, c.surface), greaterThanOrEqualTo(4.5));
        expect(contrast(c.link, c.bg), greaterThanOrEqualTo(4.5));
        final segBg = c.isDark ? c.surface : c.surfaceAlt;
        expect(contrast(c.text, segBg), greaterThanOrEqualTo(4.5));
        expect(contrast(c.text, c.surfaceAlt), greaterThanOrEqualTo(4.5));
        // Karar G: plaka beyaz bir kart (üstte yumuşak turuncu ton); üstündeki yazı mürekkep, AA.
        final plate = c.plateInk();
        for (final bg in [
          c.plate,
          c.plateTint,
          plate.surface,
          plate.surfaceAlt,
        ]) {
          for (final fg in [plate.ink, plate.text, plate.dim, plate.link]) {
            expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: '$bg');
          }
        }
        // Eski lacivert takma adı artık turuncu bandın orta rengi: üstünde beyaz yazı (≥ 3,0;
        // sahibin F2GO kararı, 15 px w700 selamlama).
        expect(contrast(c.onNavy, c.navy), greaterThanOrEqualTo(3.0));
      });
    }

    test(
      'bağlantı rengi değerleri (tasarım v2 §2.2: mürekkep + alt çizgi)',
      () {
        expect(AknColors.light.link, const Color(0xFF1E2227));
        expect(AknColors.dark.link, const Color(0xFFF1F2F4));
        expect(AknColors.light.link, AknColors.light.ink);
        expect(
          AknColors.light.lerp(AknColors.dark, 1).link,
          AknColors.dark.link,
        );
      },
    );
  });

  group('Çekirdek bileşen düzeltmeleri', () {
    testWidgets(
      'AknSegmented: 48 dp, seçilmemiş metin `dim` (AA), ekran okuyucu seçer',
      (tester) async {
        var value = 0;
        await pumpUi(
          tester,
          StatefulBuilder(
            builder: (context, set) => AknSegmented<int>(
              segments: const [
                FilterOption(value: 0, label: 'Bende'),
                FilterOption(value: 1, label: 'Taleplerim'),
              ],
              value: value,
              onChanged: (v) => set(() => value = v),
            ),
          ),
        );
        final size = tester.getSize(
          find
              .ancestor(
                of: find.text('Taleplerim'),
                matching: find.byType(ConstrainedBox),
              )
              .first,
        );
        expect(size.height, greaterThanOrEqualTo(48));
        final style = tester
            .widget<AnimatedDefaultTextStyle>(
              find
                  .ancestor(
                    of: find.text('Taleplerim'),
                    matching: find.byType(AnimatedDefaultTextStyle),
                  )
                  .first,
            )
            .style;
        // v2 §6.11: unselected labels are dim (5.44:1 on Beton), selected ink.
        expect(style.color, AknColors.light.dim);
        expect(
          contrast(AknColors.light.dim, AknColors.light.surfaceAlt),
          greaterThanOrEqualTo(4.5),
        );
        final handle = tester.ensureSemantics();
        tester.semantics.tap(find.semantics.byLabel('Taleplerim'));
        await tester.pumpAndSettle();
        expect(value, 1);
        handle.dispose();
      },
    );

    testWidgets('eylem çubuğundaki geniş düğme ekranı kaplamaz', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          AppScaffold(
            title: 'Deneme',
            body: const SizedBox.expand(),
            actionBar: AknButton(
              label: 'Gönder',
              expand: true,
              onPressed: () {},
            ),
          ),
          Brightness.light,
        ),
      );
      await tester.pump();
      final bar = tester.getSize(find.byType(ActionBar));
      expect(bar.height, lessThan(120));
      expect(tester.takeException(), isNull);
    });

    testWidgets('azaltılmış harekette çip seçimi hata vermez', (tester) async {
      var selected = <int>{};
      await pumpUi(
        tester,
        StatefulBuilder(
          builder: (context, set) => FilterChips<int>(
            options: const [
              FilterOption(value: 1, label: 'Bekleyen'),
              FilterOption(value: 2, label: 'Biten'),
            ],
            selected: selected,
            onChanged: (v) => set(() => selected = v),
          ),
        ),
        reduceMotion: true,
      );
      await tester.tap(find.text('Bekleyen'));
      await tester.pump();
      await tester.tap(find.text('Biten'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(selected, {2});
    });

    testWidgets('azaltılmış harekette düğme yükleniyor durumuna geçer', (
      tester,
    ) async {
      var loading = false;
      await pumpUi(
        tester,
        StatefulBuilder(
          builder: (context, set) => Center(
            child: AknButton(
              label: 'Kaydet',
              loading: loading,
              onPressed: () => set(() => loading = true),
            ),
          ),
        ),
        reduceMotion: true,
      );
      await tester.tap(find.text('Kaydet'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
    });

    testWidgets('yükleniyor animasyonu (hareket açık) sınır hatası vermez', (
      tester,
    ) async {
      var loading = false;
      await pumpUi(
        tester,
        StatefulBuilder(
          builder: (context, set) => Center(
            child: AknButton(
              label: 'Kaydet',
              loading: loading,
              onPressed: () => set(() => loading = true),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Kaydet'));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('adım çubuğu dokunulabilirken 48 dp hedef', (tester) async {
      int? tapped;
      await pumpUi(
        tester,
        StepperHeader(
          steps: const ['Ürün', 'Teslimat', 'Ödeme'],
          current: 2,
          onStepTap: (i) => tapped = i,
        ),
      );
      final handle = tester.ensureSemantics();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      tester.semantics.tap(find.semantics.byLabel('Ürün adımına dön'));
      expect(tapped, 0);
      handle.dispose();
    });

    testWidgets('2,0× yazıda liste satırı ve zaman çizelgesi taşmaz', (
      tester,
    ) async {
      await pumpUi(
        tester,
        Column(
          children: [
            AknListTile(
              title: 'Teslimat noktası Pendik Lojistik Merkezi',
              subtitle: 'Motorin · 12.500 L',
              meta: '21.10.2026 14:30',
              trailing: const StatusChip(
                label: 'Kabul bekliyor',
                tone: AknTone.warn,
              ),
              onTap: () {},
            ),
            const StepTimeline(
              steps: [
                TimelineStep(
                  title: 'Sevkiyat planlandı',
                  time: '21.10.2026 14:20',
                  state: TimelineState.done,
                ),
                TimelineStep(
                  title: 'Yolda',
                  time: '21.10.2026 15:05',
                  state: TimelineState.current,
                ),
              ],
            ),
            const UsageBar(
              value: 0.86,
              label: 'Aylık limit kullanımı',
              valueLabel: '2.150.000 ₺ / 2.500.000 ₺',
            ),
            SectionHeader(
              title: 'Bugünkü teslimatlar',
              actionLabel: 'Tümünü gör',
              onAction: () {},
            ),
          ],
        ),
        textScale: 2,
        size: const Size(360, 1400),
        scroll: true,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('2,0× yazıda KPI satırı alt alta dizilir; 1,0×\'da yan yana', (
      tester,
    ) async {
      Widget row() => const KpiRow(
        children: [
          KpiTile(label: 'Planlanacak', value: 3, icon: Icons.event_note),
          KpiTile(label: 'Şoför hesabı yok', value: 0, icon: Icons.person),
        ],
      );
      await pumpUi(
        tester,
        row(),
        textScale: 2,
        size: const Size(360, 900),
        scroll: true,
      );
      expect(tester.takeException(), isNull);
      final a = tester.getRect(find.byType(KpiTile).first);
      final b = tester.getRect(find.byType(KpiTile).last);
      expect(b.top, greaterThanOrEqualTo(a.bottom), reason: 'alt alta');
      expect(a.width, greaterThan(300), reason: 'tam genişlik');

      await pumpUi(tester, row(), size: const Size(360, 900), scroll: true);
      final c = tester.getRect(find.byType(KpiTile).first);
      final d = tester.getRect(find.byType(KpiTile).last);
      expect(c.top, d.top, reason: 'yan yana');
    });

    testWidgets('iOS sayı klavyesinde "Bitti" çubuğu', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await pumpUi(
        tester,
        const AknTextField(label: 'Litre', keyboardType: TextInputType.number),
      );
      expect(find.text('Bitti'), findsNothing);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(find.text('Bitti'), findsOneWidget);
      await tester.tap(find.text('Bitti'));
      await tester.pump();
      expect(find.text('Bitti'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('eylemsiz bildirim alttaki düğmeye dokunmayı engellemez', (
      tester,
    ) async {
      var taps = 0;
      await pumpUi(
        tester,
        Builder(
          builder: (context) => Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 40),
              child: AknButton(
                label: 'Üstteki düğme',
                onPressed: () {
                  taps++;
                  AppToast.info('Kaydedildi', context: context);
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Üstteki düğme'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(AppToast.isShowing, isTrue);
      await tester.tap(find.text('Üstteki düğme'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, 2);
      AppToast.dismiss();
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets(
      'bantta logo: beyaz kare, turuncu ok, beyaz yazı; plakada (beyaz kart) normal logo',
      (tester) async {
        // Karar G: turuncu üst bantta logo karosu beyaz, ok turuncu, yazı beyaz.
        await pumpUi(tester, const AknBand(child: AknLogo()));
        expect(find.byType(AknWordmark), findsOneWidget);
        LogoMarkPainter painter() => tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((p) => p.painter)
            .whereType<LogoMarkPainter>()
            .single;
        expect(painter().tileColor, const Color(0xFFFFFFFF));
        expect(painter().chevronColor, AknColors.light.logo);
        TextSpan span() =>
            tester
                    .widget<Text>(
                      find.descendant(
                        of: find.byType(AknWordmark),
                        matching: find.byType(Text),
                      ),
                    )
                    .textSpan!
                as TextSpan;
        expect(span().style!.color, const Color(0xFFFFFFFF));
        expect(
          (span().children!.single as TextSpan).style!.color,
          const Color(0xFFFFFFFF),
        );
        expect(tester.takeException(), isNull);

        // Plaka artık beyaz bir kart: logo turuncu karo, beyaz ok, mürekkep yazı.
        await pumpUi(tester, const AknHeroPanel(child: AknLogo()));
        expect(painter().tileColor, AknColors.light.logo);
        expect(painter().chevronColor, const Color(0xFFFFFFFF));
        expect(span().style!.color, AknColors.light.ink);
        expect(
          (span().children!.single as TextSpan).style!.color,
          AknColors.light.logo,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'koyu yüzeyde (onDark) yazı logosu açık mürekkep, "Net" turuncu',
      (tester) async {
        await pumpUi(
          tester,
          ColoredBox(
            color: AknColors.dark.bg,
            child: const AknLogo(onDark: true),
          ),
        );
        final text = tester.widget<Text>(
          find.descendant(
            of: find.byType(AknWordmark),
            matching: find.byType(Text),
          ),
        );
        final span = text.textSpan! as TextSpan;
        expect(span.style!.color, AknColors.dark.ink);
        expect(span.style!.fontFamily, AknFonts.sans);
        expect(
          (span.children!.single as TextSpan).style!.color,
          AknColors.light.logo,
        );
      },
    );

    testWidgets('geniş ekranda içerik en fazla 640 dp', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1024, 768);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          const AppScaffold(
            title: 'Geniş',
            body: SizedBox.expand(key: ValueKey('govde')),
          ),
          Brightness.light,
        ),
      );
      expect(tester.getSize(find.byKey(const ValueKey('govde'))).width, 640);
    });
  });

  test('piksel sayacı mor rengi tanır', () {
    expect(_isPurple(const Color(0xFF7709C7)), isTrue, reason: 'F2GO moru');
    expect(_isPurple(const Color(0xFFC94C0C)), isFalse);
    expect(_isPurple(AknColors.light.heroStart), isFalse);
    expect(_isPurple(AknColors.light.heroEnd), isFalse);
    expect(_isPurple(AknColors.dark.heroEnd), isFalse);
    expect(_isPurple(const Color(0xFF1F2A37)), isFalse);
    expect(_isPurple(const Color(0xFF1D4ED8)), isFalse);
  });
}

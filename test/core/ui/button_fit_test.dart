// Düğme etiketleri dar satırlarda bütün kalır (spec C.7; 360 / 393 dp telefon, gerçek Roboto ile):
// - AknButton (tam genişlik) sığmayan etikette önce iç boşluğu daraltır, sonra simgeyi bırakır, sonra
//   kelime sınırında iki satıra geçer; son çare tek satırı küçültür. Kelimenin ortasından kırmaz,
//   "…" ile kesmez.
// - Onay karar çubuğu: ikincil kararlar satıra sığmıyorsa kendi satırına geçer, "Onayla" tam genişlik.
// - Teslimat kabulü: iki etiket simgeleriyle yan yana (2:3) sığmıyorsa "Teslimatı onayla" üstte,
//   "İtiraz et" altında tam genişlik.
// - Ekip: "Şifre bağlantısı gönder" anahtarın altında, tek satır.
import 'package:akaryakitnet/core/models/enums.dart';
import 'package:akaryakitnet/core/offline/connectivity.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/approvals/data/approval_models.dart';
import 'package:akaryakitnet/features/approvals/presentation/widgets/decision_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../features/bayi/support/bayi_app.dart';
import '../../features/customer_more/cm_test_utils.dart' as cm;
import '../../support/fonts.dart';

/// Etiketin çizimi: satır sayısı, kelime içinde kırılma, küçültme oranı, kesilme.
typedef LabelLayout = ({int lines, bool midWord, double scale, bool cut});

LabelLayout labelLayout(WidgetTester tester, String label) {
  final f = find.descendant(
    of: find.byType(AknButton),
    matching: find.text(label),
  );
  expect(f, findsWidgets, reason: label);
  final p = tester.renderObject<RenderParagraph>(f.first);
  final text = p.text.toPlainText();
  final tops = <double>[];
  for (var i = 0; i < text.length; i++) {
    final boxes = p.getBoxesForSelection(
      TextSelection(baseOffset: i, extentOffset: i + 1),
    );
    tops.add(
      boxes.isEmpty ? (tops.isEmpty ? 0.0 : tops.last) : boxes.first.top,
    );
  }
  var lines = 1;
  var midWord = false;
  for (var i = 1; i < text.length; i++) {
    if (tops[i] > tops[i - 1] + 0.5) {
      lines++;
      if (text[i - 1] != ' ' && text[i] != ' ') midWord = true;
    }
  }
  var scale = 1.0;
  final fitted = find.ancestor(of: f.first, matching: find.byType(FittedBox));
  if (fitted.evaluate().isNotEmpty) {
    final box = tester.renderObject<RenderBox>(fitted.first);
    scale = (box.size.width / p.size.width).clamp(0.0, 1.0);
  }
  return (
    lines: lines,
    midWord: midWord,
    scale: scale,
    cut: p.didExceedMaxLines,
  );
}

/// 1,0×'te: tek satır, küçültülmeden, kesilmeden.
void expectWhole(WidgetTester tester, String label) {
  final l = labelLayout(tester, label);
  expect(l.lines, 1, reason: '"$label" tek satır');
  expect(l.midWord, isFalse, reason: '"$label" kelime içinden kırılmaz');
  expect(l.cut, isFalse, reason: '"$label" kesilmez');
  expect(l.scale, greaterThan(0.99), reason: '"$label" küçültülmez');
}

/// Büyük yazıda: kelime içinden kırılmaz, kesilmez (iki satır ya da küçültülmüş tek satır olabilir).
void expectReadable(WidgetTester tester, String label) {
  final l = labelLayout(tester, label);
  expect(l.midWord, isFalse, reason: '"$label" kelime içinden kırılmaz');
  expect(l.cut, isFalse, reason: '"$label" kesilmez');
  expect(l.lines, lessThanOrEqualTo(2), reason: '"$label"');
}

Future<void> pumpSurface(
  WidgetTester tester,
  Widget child, {
  double width = 360,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [isOnlineProvider.overrideWithValue(true)],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AknTheme.light(),
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: c!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
}

/// Ekranlardaki yan yana düğme satırları (genişlik: sayfa ve kart iç boşlukları düşülmüş).
Widget row(
  double width,
  List<(int flex, Widget button)> buttons, {
  double gap = 10,
}) => Scaffold(
  body: Center(
    child: SizedBox(
      width: width,
      child: Row(
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Expanded(flex: buttons[i].$1, child: buttons[i].$2),
          ],
        ],
      ),
    ),
  ),
);

ApprovalDetail detailWith(List<ApprovalDecision> modes) =>
    ApprovalDetail.fromJson({
      'id': 1,
      'concurrencyToken': 't',
      'modes': [for (final m in modes) m.code],
      'modeLabels': [for (final m in modes) m.label],
    });

void main() {
  // Ölçüler gerçek yazı tipiyle anlamlı; SDK önbelleğinde yoksa bu dosya atlanır.
  final skip = realFontsAvailable() ? null : 'Roboto bulunamadı';
  setUpAll(loadRealFonts);

  group('AknButton yarım genişlik satırlarda (360 dp)', () {
    final cases = <String, (double, List<(int, Widget)>, double)>{
      // Şoför ana sayfası: kahraman kartı (sayfa 16 + kart 14 boşluk).
      'şoför: Yol tarifi / Teslim et': (
        300,
        [
          (
            1,
            AknButton.secondary(
              label: 'Yol tarifi',
              icon: Icons.directions_rounded,
              expand: true,
              onPressed: () {},
            ),
          ),
          (
            1,
            AknButton(
              label: 'Teslim et',
              icon: Icons.task_alt_rounded,
              expand: true,
              onPressed: () {},
            ),
          ),
        ],
        10,
      ),
      // Teslimat noktası kartı.
      'teslimat noktası: Yol tarifi / Haritada aç': (
        296,
        [
          (
            1,
            AknButton(
              label: 'Yol tarifi',
              icon: Icons.directions_rounded,
              expand: true,
              onPressed: () {},
            ),
          ),
          (
            1,
            AknButton.secondary(
              label: 'Haritada aç',
              icon: Icons.map_outlined,
              expand: true,
              onPressed: () {},
            ),
          ),
        ],
        10,
      ),
      // Tahsilat ayrıntısı eylem çubuğu.
      'tahsilat: Siparişi aç / Durumu değiştir': (
        328,
        [
          (
            1,
            AknButton.secondary(
              label: 'Siparişi aç',
              icon: Icons.receipt_long_rounded,
              expand: true,
              onPressed: () {},
            ),
          ),
          (
            2,
            AknButton(
              label: 'Durumu değiştir',
              icon: Icons.published_with_changes_rounded,
              expand: true,
              onPressed: () {},
            ),
          ),
        ],
        12,
      ),
      // Onay: ek bilgi geldi çubuğu.
      'onay: Reddet / Bilgi alındı': (
        328,
        [
          (
            1,
            AknButton.secondary(
              label: 'Reddet',
              icon: Icons.close_rounded,
              expand: true,
              onPressed: () {},
            ),
          ),
          (
            2,
            AknButton(
              label: 'Bilgi alındı',
              icon: Icons.check_rounded,
              expand: true,
              onPressed: () {},
            ),
          ),
        ],
        12,
      ),
      // Saha formu ayrıntısı (iptal simgesi 48 dp düşülmüş).
      'saha formu: Düzenle / Onaya gönder': (
        268,
        [
          (
            1,
            AknButton.secondary(
              label: 'Düzenle',
              icon: Icons.edit_outlined,
              expand: true,
              onPressed: () {},
            ),
          ),
          (
            1,
            AknButton(
              label: 'Onaya gönder',
              icon: Icons.send_rounded,
              expand: true,
              onPressed: () {},
            ),
          ),
        ],
        12,
      ),
    };

    for (final e in cases.entries) {
      final labels = [for (final b in e.value.$2) (b.$2 as AknButton).label];
      testWidgets('${e.key}: 1,0× tek satır', (tester) async {
        await pumpSurface(tester, row(e.value.$1, e.value.$2, gap: e.value.$3));
        for (final l in labels) {
          expectWhole(tester, l);
        }
        expect(tester.takeException(), isNull);
      }, skip: skip != null);

      testWidgets('${e.key}: 2,0× kelime içinden kırılmaz', (tester) async {
        await pumpSurface(
          tester,
          row(e.value.$1, e.value.$2, gap: e.value.$3),
          textScale: 2,
        );
        for (final l in labels) {
          expectReadable(tester, l);
        }
        expect(tester.takeException(), isNull);
      }, skip: skip != null);
    }

    testWidgets('sığan etikette simge ve tam iç boşluk korunur', (
      tester,
    ) async {
      await pumpSurface(
        tester,
        row(328, [
          (
            1,
            AknButton(
              label: 'Devam',
              trailingIcon: Icons.arrow_forward_rounded,
              expand: true,
              onPressed: () {},
            ),
          ),
        ]),
      );
      expectWhole(tester, 'Devam');
      expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
    }, skip: skip != null);
  });

  group('Onay karar çubuğu', () {
    final scenarios = <String, List<ApprovalDecision>>{
      'onayla + reddet': [ApprovalDecision.approve, ApprovalDecision.reject],
      'onayla + ek bilgi + reddet': [
        ApprovalDecision.approve,
        ApprovalDecision.requestInfo,
        ApprovalDecision.reject,
      ],
      'finans: dört karar': [
        ApprovalDecision.approve,
        ApprovalDecision.conditionalApprove,
        ApprovalDecision.requestInfo,
        ApprovalDecision.reject,
      ],
    };
    for (final width in [360.0, 393.0]) {
      for (final s in scenarios.entries) {
        testWidgets(
          '${s.key} @${width.toInt()}: etiketler tek satır, bütün',
          (tester) async {
            final d = detailWith(s.value);
            await pumpSurface(
              tester,
              AppScaffold(
                title: 'Onay',
                showBell: false,
                body: const SizedBox.expand(),
                actionBar: DecisionBar(detail: d, onDecision: (_) {}),
              ),
              width: width,
            );
            final labels = <String>[
              d.modeLabel(ApprovalDecision.approve),
              d.modeLabel(ApprovalDecision.reject),
              if (s.value.length == 3)
                d.modeLabel(ApprovalDecision.requestInfo),
              if (s.value.length == 4) 'Diğer',
            ];
            for (final l in labels) {
              expectWhole(tester, l);
            }
            expect(tester.takeException(), isNull);
          },
          skip: skip != null,
        );
      }
    }

    testWidgets(
      'dört karar @360: ikinciller kendi satırında, Onayla tam genişlik',
      (tester) async {
        await pumpSurface(
          tester,
          AppScaffold(
            title: 'Onay',
            showBell: false,
            body: const SizedBox.expand(),
            actionBar: DecisionBar(
              detail: detailWith(const [
                ApprovalDecision.approve,
                ApprovalDecision.conditionalApprove,
                ApprovalDecision.requestInfo,
                ApprovalDecision.reject,
              ]),
              onDecision: (_) {},
            ),
          ),
        );
        final approve = tester.getRect(
          find.widgetWithText(AknButton, ApprovalDecision.approve.label),
        );
        final reject = tester.getRect(
          find.widgetWithText(AknButton, ApprovalDecision.reject.label),
        );
        expect(approve.width, greaterThan(300));
        // v2 dock (§7.8, §7.13): the primary has the full width and the
        // secondaries sit on their own row (above or below it).
        expect(
          reject.bottom <= approve.top || reject.top >= approve.bottom,
          isTrue,
        );
      },
      skip: skip != null,
    );
  });

  testWidgets(
    'teslimat kabulü @360: "İtiraz et" ve "Teslimatı onayla" bütün',
    (tester) async {
      final env = (await tester.runAsync(cm.CmEnv.create))!;
      addTearDown(env.dispose);
      final id = env.world.shipments.firstWhere((s) => s['status'] == 2)['id'];
      await cm.pumpCmApp(
        tester,
        env,
        location: '/shipments/$id',
        size: const Size(360, 640),
      );
      await cm.pumpFor(tester, const Duration(seconds: 1));
      expectWhole(tester, 'İtiraz et');
      expectWhole(tester, 'Teslimatı onayla');
      // Yan yana ise itiraz en az 2/5 pay (eskiden 1/4 pay: "i"ye düşüyordu); iki etiket simgeleriyle
      // sığmazsa alt alta, tam genişlik.
      final dispute = tester.getRect(
        find.widgetWithText(AknButton, 'İtiraz et'),
      );
      expect(dispute.width, greaterThan(120));
      await cm.finish(tester);
    },
    skip: skip != null,
  );

  testWidgets('ekip @360: "Şifre bağlantısı gönder" tek satır', (tester) async {
    final app = await BayiTestApp.start(
      tester,
      persona: 'sahip',
      location: '/bayi/staff',
      size: const Size(360, 2600),
    );
    expectWhole(tester, 'Şifre bağlantısı gönder');
    await app.finish(tester);
  }, skip: skip != null);
}

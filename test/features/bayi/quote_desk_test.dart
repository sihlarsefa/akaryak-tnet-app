// Teklifler (teklif masası, v4 §5 13): "Önerilen fiyatları yaz", "Seçilenlere aynı fiyat/tarih", toplu
// gönderim ve satır başına sonuç
// (finansa giden uyarı tonunda), gönderim sonrası tazeleme, geri sayımın yalnızca süre dolumu açıkken
// görünmesi, teklif engeli ve görüntüleme yetkisi.
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/bayi/application/desk_controller.dart';
import 'package:akaryakitnet/features/bayi/data/desk_models.dart';
import 'package:akaryakitnet/features/bayi/fake/desk_fake.dart';
import 'package:akaryakitnet/features/bayi/fake/fake_support.dart';
import 'package:akaryakitnet/features/bayi/presentation/desk/desk_row_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bayi_app.dart';

// Satırlar tembel kurulur ve kaydırınca sıra kayar; satırı sipariş kimliğiyle bul.
Finder _card(int orderId) => find.byKey(ValueKey(orderId));

Finder _rowField(int orderId) =>
    find.descendant(of: _card(orderId), matching: find.byType(TextField));

Finder _rowCheck(int orderId) =>
    find.descendant(of: _card(orderId), matching: find.byType(Checkbox));

void main() {
  testWidgets(
    'Önerileri uygula + toplu gönderim: satır sonuçları, finansa giden uyarı tonunda',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'siparis',
        location: '/quote-desk',
      );
      final rows = app.container.read(quoteDeskProvider).rows;
      expect(rows.length, greaterThanOrEqualTo(5));
      expect(find.byType(DeskRowCard), findsWidgets);
      expect(
        find.byType(CountdownBadge),
        findsWidgets,
        reason: 'süre dolumu açık',
      );
      // v4: "Süresi yaklaşan" Filtre sayfasında (tek anahtar: Tümü | Yeni | Revize).
      expect(find.text('Süresi yaklaşan'), findsNothing);
      await scrollTap(tester, find.bySemanticsLabel('Filtre'));
      expect(find.text('Süresi yaklaşan'), findsOneWidget);
      await scrollTap(tester, find.text('Tamam'));

      await scrollTap(tester, find.text('Önerilen fiyatları yaz'));
      final s = app.container.read(quoteDeskProvider);
      final withSuggestion = rows
          .where((r) => r.suggestedUnitPrice != null)
          .length;
      expect(s.selected.length, withSuggestion);
      expect(
        s.draftOf(rows.first.orderId).price,
        rows.first.suggestedUnitPrice,
      );
      expect(
        find.textContaining('Teklifleri gönder ($withSuggestion) · '),
        findsOneWidget,
      );

      await scrollTap(
        tester,
        find.textContaining('Teklifleri gönder ($withSuggestion)'),
      );
      expect(find.text('Teklif sonuçları'), findsOneWidget);
      expect(find.textContaining('finans onayına gönderildi'), findsWidgets);
      final financeChip = tester.widget<StatusChip>(
        find.widgetWithText(StatusChip, 'Finans onayına gönderildi'),
      );
      expect(financeChip.tone, AknTone.warn);
      final quotedChips = find.widgetWithText(StatusChip, 'Teklif gönderildi');
      expect(quotedChips, findsNWidgets(withSuggestion - 1));
      await scrollTap(tester, find.text('Tamam'));
      // Gönderim sonrası masa tazelendi: teklif verilen ve finansa giden satırlar düştü.
      final after = app.container.read(quoteDeskProvider);
      expect(after.rows.length, rows.length - withSuggestion);
      expect(after.header!.financeHeld, greaterThan(s.header!.financeHeld));
      expect(tester.takeException(), isNull);
      await app.finish(tester);
    },
  );

  testWidgets(
    'Seçilenlere aynı fiyat / tarih yalnızca seçili satırlara yazılır',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'siparis',
        location: '/quote-desk',
      );
      final rows = app.container.read(quoteDeskProvider).rows;
      await scrollTap(tester, _rowCheck(rows[0].orderId));
      await scrollTap(tester, _rowCheck(rows[1].orderId));
      expect(app.container.read(quoteDeskProvider).selected, {
        rows[0].orderId,
        rows[1].orderId,
      });
      await scrollTap(tester, find.text('Aynı fiyatı uygula'));
      expect(find.text('Seçilenlere aynı fiyat / tarih'), findsOneWidget);
      final sheetPrice = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextField),
      );
      await tester.enterText(sheetPrice.first, '41,9');
      await BayiTestApp.settle(tester);
      await scrollTap(tester, find.text('Seçilenlere uygula'));
      final s = app.container.read(quoteDeskProvider);
      expect(s.draftOf(rows[0].orderId).price, 41.9);
      expect(s.draftOf(rows[1].orderId).price, 41.9);
      expect(s.draftOf(rows[2].orderId).price, isNull);
      await app.finish(tester);
    },
  );

  testWidgets(
    'satıra yazılan fiyat satırı seçer; çakışma sonucu satırda kalır',
    (tester) async {
      late int target;
      final app = await BayiTestApp.start(
        tester,
        persona: 'siparis',
        location: '/quote-desk',
        setup: (h) {
          target = fakeDeskOrderIds(h.world, 'siparis').first;
          injectDeskOutcome(h.world, target, outcome: 'conflict');
        },
      );
      final rows = app.container.read(quoteDeskProvider).rows;
      expect(rows.any((r) => r.orderId == target), isTrue);
      await reveal(tester, _rowField(target).first);
      await tester.enterText(_rowField(target).first, '41,5');
      await BayiTestApp.settle(tester);
      expect(app.container.read(quoteDeskProvider).selected, {target});
      await scrollTap(tester, find.textContaining('Teklifleri gönder (1)'));
      expect(
        find.widgetWithText(StatusChip, 'Başka bir işlemle güncellendi'),
        findsWidgets,
      );
      await scrollTap(tester, find.text('Tamam'));
      final s = app.container.read(quoteDeskProvider);
      expect(s.rows.any((r) => r.orderId == target), isTrue);
      expect(s.outcomes[target]?.outcome, DeskOutcome.conflict);
      await reveal(tester, _card(target));
      expect(
        find.descendant(
          of: _card(target),
          matching: find.text('Başka bir işlemle güncellendi'),
        ),
        findsOneWidget,
      );
      await app.finish(tester);
    },
  );

  testWidgets('fiyatsız seçili satır gönderilmez, satırda hata gösterilir', (
    tester,
  ) async {
    final app = await BayiTestApp.start(
      tester,
      persona: 'siparis',
      location: '/quote-desk',
    );
    final rows = app.container.read(quoteDeskProvider).rows;
    await reveal(tester, _rowField(rows[0].orderId).first);
    await tester.enterText(_rowField(rows[0].orderId).first, '41,25');
    await BayiTestApp.settle(tester);
    await scrollTap(tester, _rowCheck(rows[1].orderId));
    await scrollTap(tester, find.textContaining('Teklifleri gönder (2)'));
    final s = app.container.read(quoteDeskProvider);
    expect(s.rowErrors[rows[1].orderId], 'Birim fiyat girin.');
    expect(find.text('Teklif sonuçları'), findsNothing);
    expect(find.text('Birim fiyat girin.'), findsOneWidget);
    await app.finish(tester);
  });

  testWidgets('süre dolumu kapalıyken geri sayım ve "Süresi yaklaşan" yok', (
    tester,
  ) async {
    final app = await BayiTestApp.start(
      tester,
      persona: 'siparis',
      location: '/quote-desk',
      setup: (h) => setExpiryEnabled(h.world, false),
    );
    expect(find.byType(DeskRowCard), findsWidgets);
    expect(find.byType(CountdownBadge), findsNothing);
    expect(find.text('Süresi yaklaşan'), findsNothing);
    await app.finish(tester);
  });

  testWidgets('teklif engeli: afiş, satır içi alan ve gönderim yok', (
    tester,
  ) async {
    final app = await BayiTestApp.start(
      tester,
      persona: 'siparis',
      location: '/quote-desk',
      setup: (h) => setFakeQuotingBlocked(h.world, true),
    );
    expect(find.text('Yeni teklif verilemez'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('Önerilen fiyatları yaz'), findsNothing);
    expect(find.byType(DeskRowCard), findsWidgets);
    await app.finish(tester);
  });

  testWidgets('görüntüleyici masayı görür, teklif veremez', (tester) async {
    final app = await BayiTestApp.start(
      tester,
      persona: 'izleyici',
      location: '/quote-desk',
    );
    expect(find.byType(DeskRowCard), findsWidgets);
    expect(find.textContaining('teklif verme yetkiniz yok'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(TextField), findsNothing);
    await app.finish(tester);
  });

  testWidgets('cari süzgeci (?customerId=) ve sekme sayıları', (tester) async {
    final app = await BayiTestApp.start(
      tester,
      persona: 'siparis',
      location: '/quote-desk?customerId=101',
    );
    final s = app.container.read(quoteDeskProvider);
    expect(s.customerId, 101);
    expect(s.rows.every((r) => r.customerId == 101), isTrue);
    expect(find.byType(InputChip), findsOneWidget);
    await scrollTap(tester, find.byTooltip('Cari süzgecini kaldır'));
    expect(app.container.read(quoteDeskProvider).customerId, isNull);
    await app.finish(tester);
  });

  testWidgets(
    '2,0× yazıda toplu araçlar tek düğmede; çubuk listeyi örtmez (A-INT)',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'siparis',
        location: '/quote-desk',
        textScale: 2,
        size: const Size(360, 640),
      );
      expect(find.text('Toplu işlemler'), findsOneWidget);
      expect(find.text('Önerilen fiyatları yaz'), findsNothing);
      // Çubuk ekranın yarısından azını kaplar.
      final bar = tester.getRect(
        find
            .ancestor(
              of: find.text('Toplu işlemler'),
              matching: find.byType(Column),
            )
            .first,
      );
      expect(bar.height, lessThan(320));

      await tester.tap(find.text('Toplu işlemler'));
      await BayiTestApp.settle(tester);
      expect(find.text('Önerilen fiyatları yaz'), findsOneWidget);
      expect(find.text('Tümünü seç'), findsOneWidget);
      await tester.tap(find.text('Önerilen fiyatları yaz'));
      await BayiTestApp.settle(tester);
      final s = app.container.read(quoteDeskProvider);
      expect(s.selected, isNotEmpty, reason: 'öneriler yazıldı ve seçildi');
      expect(
        find.text('Önerilen fiyatları yaz'),
        findsNothing,
        reason: 'sayfa kapandı',
      );
      expect(tester.takeException(), isNull);
      await app.finish(tester);
    },
  );

  testWidgets(
    'v4: bant durumu ve tek anahtar; satırda hap yok; fiyat yazınca birincil gelir; son alımlar',
    (tester) async {
      final app = await BayiTestApp.start(
        tester,
        persona: 'siparis',
        location: '/quote-desk',
        size: const Size(390, 844),
      );
      expect(
        find.textContaining('sipariş teklif bekliyor', findRichText: true),
        findsOneWidget,
      );
      expect(find.byType(AknSegmented<DeskView>), findsOneWidget);
      expect(find.byType(FilterChips<DeskView>), findsNothing);
      // Satırda durum hapı yok; ilk kart 260 dp'nin üstünde başlar (bant + anahtar + Tümünü seç).
      expect(
        find.descendant(
          of: find.byType(DeskRowCard),
          matching: find.byType(AknLamp),
        ),
        findsNothing,
      );
      expect(tester.getRect(find.byType(DeskRowCard).first).top, lessThan(260));
      // Fiyat yazılana kadar birincil yok; yazınca "Teklifleri gönder (1) · tutar" gelir.
      expect(find.textContaining('Teklifleri gönder'), findsNothing);
      final rows = app.container.read(quoteDeskProvider).rows;
      await tester.enterText(_rowField(rows.first.orderId).first, '41,5');
      await BayiTestApp.settle(tester);
      expect(find.textContaining('Teklifleri gönder (1) · '), findsOneWidget);
      // "Son: …" dokununca son alımlar sayfası.
      final last = find.descendant(
        of: _card(rows.first.orderId),
        matching: find.textContaining('Son: '),
      );
      if (last.evaluate().isNotEmpty) {
        await scrollTap(tester, last.first);
        expect(find.text('Son alımlar'), findsOneWidget);
      }
      await app.finish(tester);
    },
  );
}

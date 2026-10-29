// Finans (spec D.3 A5): süzgeçler → `finance/customers` sorgu parametreleri, satırdan karta geçiş,
// kart bölümleri, tasarım v2 (kart plakası "Kullanılabilir limit", ledger satırları, " · " yok) ve C.7
// erişilebilirlik matrisi.
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/finance/presentation/finance_card_page.dart';
import 'package:akaryakitnet/features/finance/presentation/finance_customers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../approvals/a5_test_kit.dart';

/// Listenin son sorgusu. v4: bant durumu ve "Bekleyen n" için bekleyenlerin sayısı ayrıca istenir
/// (`status=pending`, ilk sayfa); süzgeç değişince son istek listenindir.
Map<String, dynamic> lastQuery(A5App app) =>
    app.log.last('GET', 'finance/customers')!.queryParameters;

/// Tasarım v2 §10.1: ekrandaki hiçbir metinde " · " yok.
void expectNoMiddleDots(WidgetTester tester) {
  final texts = [
    for (final e in find.byType(Text).evaluate())
      (e.widget as Text).data ??
          (e.widget as Text).textSpan?.toPlainText() ??
          '',
  ];
  expect(texts.where((t) => t.contains(' · ')), isEmpty);
}

/// Bandın Filtre sayfasını açar.
Future<void> openFilters(WidgetTester tester) =>
    tapFinder(tester, find.byType(AknFilterButton));

/// Açık Filtre sayfasını kapatır.
Future<void> closeSheet(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(AppSheet))).pop();
  await pumpFor(tester);
}

void main() {
  testWidgets('süzgeçler sorguya gider ve listeyi daraltır', (tester) async {
    final app = await pumpA5(tester, persona: 'finans', location: '/finance');
    expect(
      app.log
          .all('GET', 'finance/customers')
          .any((r) => r.queryParameters['status'] == null),
      isTrue,
    );
    expect(find.byType(FinanceRowCard), findsWidgets);

    // Durum: tek seçici (v4 §5 09); "Onaylı" ekranda yalnızca seçicide.
    await tapText(tester, 'Onaylı');
    expect(lastQuery(app)['status'], 'approved');
    // Risk ve gözden geçirme: bandın Filtre sayfasında.
    await openFilters(tester);
    await tapFinder(tester, inSheet(find.text('Risk C')));
    expect('${lastQuery(app)['risk']}', '3');
    await tapFinder(tester, inSheet(find.text('Gözden geçirmesi geçen')));
    expect('${lastQuery(app)['overdue']}', 'true');
    await closeSheet(tester);
    // Onaylı + Risk C + gözden geçirmesi geçen: yalnızca Marmara İnşaat.
    expect(find.byType(FinanceRowCard), findsOneWidget);
    expect(find.text('Marmara İnşaat Taahhüt Ltd. Şti.'), findsOneWidget);

    // Tek risk sınıfı seçilir: yenisi öncekinin yerine geçer.
    await openFilters(tester);
    await tapFinder(tester, inSheet(find.text('Risk A')));
    expect('${lastQuery(app)['risk']}', '1');
    await closeSheet(tester);
    expect(find.byType(FinanceRowCard), findsNothing);
    expect(find.text('Filtreleri temizle'), findsOneWidget);
    await tapText(tester, 'Filtreleri temizle');
    expect(lastQuery(app)['status'], isNull);
    expect(lastQuery(app)['risk'], isNull);
    await finish(tester);
  });

  testWidgets('arama metni sorguya gider (⌕ şeridi; VKN de aranır)', (
    tester,
  ) async {
    final app = await pumpA5(tester, persona: 'finans', location: '/finance');
    expect(find.byType(TextField), findsNothing, reason: 'arama ⌕ ardında');
    await tapFinder(tester, find.bySemanticsLabel('Carilerde ara'));
    await tester.enterText(find.byType(TextField).first, 'ege');
    await pumpFor(tester);
    expect(lastQuery(app)['q'], 'ege');
    expect(find.text('Ege Tarım Kooperatifi'), findsOneWidget);
    expect(find.byType(FinanceRowCard), findsOneWidget);
    await finish(tester);
  });

  testWidgets('?filter=review gözden geçirmesi geçenlerle açılır', (
    tester,
  ) async {
    final app = await pumpA5(
      tester,
      persona: 'finans',
      location: '/finance?filter=review',
    );
    expect(
      app.log
          .all('GET', 'finance/customers')
          .any((r) => '${r.queryParameters['overdue']}' == 'true'),
      isTrue,
    );
    // Filtre düğmesinin rozeti etkin süzgeci sayar.
    final button = tester.widget<AknFilterButton>(find.byType(AknFilterButton));
    expect(button.count, 1);
    await finish(tester);
  });

  testWidgets('satır finans kartını açar: bölümler ve karar geçmişi', (
    tester,
  ) async {
    final app = await pumpA5(tester, persona: 'finans', location: '/finance');
    await tapText(tester, 'Anadolu Lojistik A.Ş.', first: true);
    expect(find.byType(FinanceCardPage), findsOneWidget);
    expect(app.log.last('GET', 'finance/customers/501'), isNotNull);
    const sections = {'Limit', 'Finans koşulları', 'Karar geçmişi'};
    final seen = <String>{};
    for (var i = 0; i < 12 && seen.length < sections.length; i++) {
      for (final s in sections) {
        if (find.text(s).evaluate().isNotEmpty) seen.add(s);
      }
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -300));
      await pumpFor(tester, const Duration(milliseconds: 400));
    }
    expect(seen, sections);
    await finish(tester);
  });

  testWidgets('başka bayinin kartı bulunamadı ekranı gösterir', (tester) async {
    await pumpA5(
      tester,
      persona: 'finans',
      location: '/finance/customers/9999',
    );
    expect(find.byType(FinanceCardPage), findsOneWidget);
    expect(find.text('Bu finans kartı artık görüntülenemiyor'), findsOneWidget);
    await finish(tester);
  });

  group('tasarım v4', () {
    testWidgets(
      'liste: defter satırları; "Onaylı" yalnızca seçicide, VKN ve risk çipi yok; Dikkat önce',
      (tester) async {
        await pumpA5(tester, persona: 'finans', location: '/finance');
        expect(find.byType(FinanceRowCard), findsWidgets);
        expect(find.byType(AknCard), findsNothing);
        expect(find.byType(AknListTile), findsWidgets);
        expect(find.byType(AknChip), findsNothing, reason: 'çip satırı yok');
        final rows = find.byType(FinanceRowCard);
        expect(
          find.descendant(of: rows, matching: find.text('Onaylı')),
          findsNothing,
          reason: 'normal durum yazılmaz',
        );
        expect(
          find.text('Onaylı'),
          findsOneWidget,
          reason: 'yalnızca seçicide',
        );
        expect(
          find.descendant(of: rows, matching: find.textContaining('VKN')),
          findsNothing,
        );
        expect(find.byType(AknLamp), findsNothing, reason: 'hap yok');
        final groups = tester
            .widgetList<AknLedgerGroup>(find.byType(AknLedgerGroup))
            .toList();
        expect(groups.first.title, 'Dikkat');
        // Finans onayı bekleyen cari Pas satırla söylenir; bant durumu aynı sayı.
        expect(find.text('Finans onayınızı bekliyor'), findsWidgets);
        expect(find.textContaining('finans onayınızı bekliyor'), findsWidgets);
        await finish(tester);
      },
    );

    testWidgets(
      'kart: tek plaka "Kullanılabilir limit" + Limit / Kullanılan / Kullanım',
      (tester) async {
        await pumpA5(
          tester,
          persona: 'finans',
          location: '/finance/customers/501',
        );
        expect(find.byType(AknPlate), findsOneWidget);
        final plate = find.byType(AknPlate);
        expect(
          find.descendant(
            of: plate,
            matching: find.text('Kullanılabilir limit'),
          ),
          findsOneWidget,
        );
        for (final label in ['Limit', 'Kullanılan', 'Kullanım']) {
          expect(
            find.descendant(of: plate, matching: find.text(label)),
            findsOneWidget,
            reason: label,
          );
        }
        expect(find.byType(PlateMeter), findsOneWidget);
        expect(
          find.byType(PlateBang),
          findsNothing,
          reason: 'kullanım %80 altı',
        );
        expectNoMiddleDots(tester);
        await finish(tester);
      },
    );

    testWidgets('limitin %80\'i aşıldıysa plakada "!" ve kalın söz', (
      tester,
    ) async {
      await pumpA5(
        tester,
        persona: 'finans',
        location: '/finance/customers/502',
      );
      final plate = find.byType(AknPlate);
      expect(
        find.descendant(of: plate, matching: find.byType(PlateBang)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: plate, matching: find.textContaining('kullanıldı')),
        findsOneWidget,
      );
      await finish(tester);
    });
  });

  group('C.7 Finans', () {
    a11yMatrix('cari finans listesi', persona: 'finans', location: '/finance');
    a11yMatrix(
      'finans kartı',
      persona: 'finans',
      location: '/finance/customers/502',
    );
  });
}

// Finans (spec D.3 A5): süzgeçler → `finance/customers` sorgu parametreleri, satırdan karta geçiş,
// kart bölümleri, tasarım v2 (kart plakası "Kullanılabilir limit", ledger satırları, " · " yok) ve C.7
// erişilebilirlik matrisi.
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/approvals/presentation/approval_detail_page.dart';
import 'package:akaryakitnet/features/finance/copy.dart';
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
    // Ünvanın sonundaki "Ltd. Şti." bölünmez boşlukla bağlı (v4 A19: "Şti." tek kalmaz).
    expect(
      find.text(bindLegalSuffix('Marmara İnşaat Taahhüt Ltd. Şti.')),
      findsOneWidget,
    );

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
    await tapText(
      tester,
      bindLegalSuffix('Anadolu Lojistik A.Ş.'),
      first: true,
    );
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

  // v4 tur 2 (B1): "Finans onayınızı bekliyor" çıkmaz sokak değildir — satır ve kart kararın
  // verildiği talebi açar; sıra başkasındaysa Pas yok.
  group('tur 2: karar izleyenin sırası', () {
    testWidgets(
      'finans: Pas satır talebi doğrudan açar; bant sayısı = Pas satırlar = Bende',
      (tester) async {
        final app = await pumpA5(
          tester,
          persona: 'finans',
          location: '/finance',
        );
        // Bant: Bende'deki yeni cari talepleri; satırlar: aynı sayıda Pas satır.
        final bende = app.server.world.approvals
            .where(
              (a) =>
                  a['type'] == 6 &&
                  (a['status'] == 0 || a['status'] == 4) &&
                  (a['eligibleUserIds'] as List).contains('u-finans'),
            )
            .length;
        expect(bende, greaterThan(0));
        expect(
          find.textContaining(
            FinanceCopy.pendingStatus(bende),
            findRichText: true,
          ),
          findsOneWidget,
        );
        final yours = find.descendant(
          of: find.byType(FinanceRowCard),
          matching: find.textContaining(
            FinanceCopy.pendingYourMove,
            findRichText: true,
          ),
        );
        expect(yours, findsNWidgets(bende));
        // Satır kartı değil talebi açar: karar orada (alt çubukta karar düğmeleri).
        await tapFinder(tester, yours.first);
        expect(find.byType(ApprovalDetailPage), findsOneWidget);
        expect(find.byType(FinanceCardPage), findsNothing);
        expect(find.text('Onaylarım'), findsNothing);
        await finish(tester);
      },
    );

    testWidgets(
      'finans kartı: bekleyen kartta alt çubukta "Karar ver" → talep; uyarı yok',
      (tester) async {
        await pumpA5(
          tester,
          persona: 'finans',
          location: '/finance/customers/506',
        );
        expect(find.byType(FinanceCardPage), findsOneWidget);
        // Eski uyarı ("Onaylarım'daki … talebinden verin") yok; karar alt çubukta.
        expect(find.textContaining('Onaylarım'), findsNothing);
        expect(find.byType(AknBanner), findsNothing);
        final decide = find.byKey(const ValueKey('finance-decide'));
        expect(decide, findsOneWidget);
        expect(find.text(FinanceCopy.decide), findsOneWidget);
        // Limiti olmayan cari "limitsiz" değil "Tanımlanmadı" (B16).
        expect(find.textContaining('limitsiz'), findsNothing);
        await tapFinder(tester, decide);
        expect(find.byType(ApprovalDetailPage), findsOneWidget);
        await finish(tester);
      },
    );

    testWidgets(
      'finans uzmanı (talep onun değil): Pas yok, kart açılır, alt çubuk yok',
      (tester) async {
        await pumpA5(tester, persona: 'finansuzman', location: '/finance');
        expect(
          find.textContaining(FinanceCopy.pendingYourMove, findRichText: true),
          findsNothing,
        );
        expect(
          find.textContaining(
            FinanceCopy.pendingElsewhereStatus(1),
            findRichText: true,
          ),
          findsOneWidget,
          reason: 'bant sakin: sıra başkasında',
        );
        final elsewhere = find.descendant(
          of: find.byType(FinanceRowCard),
          matching: find.textContaining(
            FinanceCopy.pendingElsewhere,
            findRichText: true,
          ),
        );
        expect(elsewhere, findsOneWidget);
        await tapFinder(tester, elsewhere);
        expect(find.byType(FinanceCardPage), findsOneWidget);
        expect(find.byKey(const ValueKey('finance-decide')), findsNothing);
        await finish(tester);
      },
    );

    testWidgets(
      'satır: istisnalar tek satırda " · " ile; sağlıklı çubuk sakin, %90 ve üstü tehlike',
      (tester) async {
        await pumpA5(tester, persona: 'finans', location: '/finance');
        // Körfez Nakliyat: gecikme + karşılıksız çek → tek satır; tutar ana sayfanın "Vadesi geçen 1
        // ödeme 247.200 ₺"ı ile aynı. Tehlike varken yaklaşan gözden geçirme yazılmaz (v4 tur 2).
        final korfez = find.ancestor(
          of: find.text('Körfez Nakliyat ve Ticaret'),
          matching: find.byType(FinanceRowCard),
        );
        expect(korfez, findsOneWidget);
        final line = find.descendant(
          of: korfez,
          matching: find.textContaining(
            'Gecikme 247.200 ₺ · karşılıksız çek',
            findRichText: true,
          ),
        );
        expect(line, findsOneWidget);
        expect(
          find.descendant(
            of: korfez,
            matching: find.textContaining('gün sonra', findRichText: true),
          ),
          findsNothing,
        );
        // Marmara İnşaat: yalnızca uyarı, mürekkeple (turuncu "sıra sizde" ile karışmaz).
        final marmara = find.ancestor(
          of: find.text(bindLegalSuffix('Marmara İnşaat Taahhüt Ltd. Şti.')),
          matching: find.byType(FinanceRowCard),
        );
        expect(marmara, findsOneWidget);
        expect(
          find.descendant(
            of: marmara,
            matching: find.textContaining(
              'Gözden geçirme tarihi geçti',
              findRichText: true,
            ),
          ),
          findsOneWidget,
        );
        // Çubuk renkleri: %90 altı sakin (turuncu ya da yeşil değil), üstü tehlike.
        for (final bar in tester.widgetList<UsageBar>(find.byType(UsageBar))) {
          expect(
            bar.tone,
            bar.value >= financeUsageDangerAt
                ? AknTone.danger
                : AknTone.neutral,
          );
        }
        await finish(tester);
      },
    );
  });

  test(
    'bindLegalSuffix: ünvan sonundaki kısaltmalar önceki sözcüğe bağlanır',
    () {
      expect(
        bindLegalSuffix('Marmara İnşaat Taahhüt Ltd. Şti.'),
        'Marmara İnşaat Taahhüt\u00A0Ltd.\u00A0Şti.',
      );
      expect(
        bindLegalSuffix('Doğu Marmara Gıda San. A.Ş.'),
        'Doğu Marmara Gıda\u00A0San.\u00A0A.Ş.',
      );
      expect(bindLegalSuffix('Ege Tarım Kooperatifi'), 'Ege Tarım Kooperatifi');
      expect(bindLegalSuffix('A.Ş.'), 'A.Ş.');
    },
  );

  group('C.7 Finans', () {
    a11yMatrix('cari finans listesi', persona: 'finans', location: '/finance');
    a11yMatrix(
      'finans kartı',
      persona: 'finans',
      location: '/finance/customers/502',
    );
  });
}

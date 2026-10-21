// Finans (spec D.3 A5): süzgeçler → `finance/customers` sorgu parametreleri, satırdan karta geçiş,
// kart bölümleri ve C.7 erişilebilirlik matrisi.
import 'package:akaryakitnet/features/finance/presentation/finance_card_page.dart';
import 'package:akaryakitnet/features/finance/presentation/finance_customers_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../approvals/a5_test_kit.dart';

Map<String, dynamic> lastQuery(A5App app) =>
    app.log.last('GET', 'finance/customers')!.queryParameters;

void main() {
  testWidgets('süzgeçler sorguya gider ve listeyi daraltır', (tester) async {
    final app = await pumpA5(tester, persona: 'finans', location: '/finance');
    expect(lastQuery(app)['status'], isNull);
    expect(find.byType(FinanceRowCard), findsWidgets);

    // Süzgeç çipi başlıkta, satırlardaki durum çiplerinden önce.
    await tapText(tester, 'Onaylı', first: true);
    expect(lastQuery(app)['status'], 'approved');
    await tapText(tester, 'Risk C', first: true);
    expect('${lastQuery(app)['risk']}', '3');
    await tapText(tester, 'Gözden geçirmesi geçen');
    expect('${lastQuery(app)['overdue']}', 'true');
    // Onaylı + Risk C + gözden geçirmesi geçen: yalnızca Marmara İnşaat.
    expect(find.byType(FinanceRowCard), findsOneWidget);
    expect(find.text('Marmara İnşaat Taahhüt Ltd. Şti.'), findsOneWidget);

    // Tek risk sınıfı seçilir: yenisi öncekinin yerine geçer.
    await tapText(tester, 'Risk A', first: true);
    expect('${lastQuery(app)['risk']}', '1');
    expect(find.byType(FinanceRowCard), findsNothing);
    expect(find.text('Filtreleri temizle'), findsOneWidget);
    await tapText(tester, 'Filtreleri temizle');
    expect(lastQuery(app)['status'], isNull);
    expect(lastQuery(app)['risk'], isNull);
    await finish(tester);
  });

  testWidgets('arama metni sorguya gider', (tester) async {
    final app = await pumpA5(tester, persona: 'finans', location: '/finance');
    await tester.enterText(find.byType(TextField).first, 'ege');
    await pumpFor(tester);
    expect(lastQuery(app)['q'], 'ege');
    expect(find.text('Ege Tarım Kooperatifi'), findsOneWidget);
    expect(find.byType(FinanceRowCard), findsOneWidget);
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

  group('C.7 Finans', () {
    a11yMatrix('cari finans listesi', persona: 'finans', location: '/finance');
    a11yMatrix(
      'finans kartı',
      persona: 'finans',
      location: '/finance/customers/502',
    );
  });
}

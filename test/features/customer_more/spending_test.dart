import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/core/utils/format.dart';
import 'package:akaryakitnet/features/customer_more/application/spending_controller.dart';
import 'package:akaryakitnet/features/customer_more/copy.dart';
import 'package:akaryakitnet/features/customer_more/data/customer_more_repository.dart';
import 'package:akaryakitnet/features/customer_more/data/spending.dart';
import 'package:akaryakitnet/features/customer_more/presentation/spending/spending_charts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cm_test_utils.dart';

void main() {
  testWidgets('harcamalar sunucu toplamlarını gösterir (uygulama hesaplamaz)', (
    tester,
  ) async {
    final env = (await tester.runAsync(CmEnv.create))!;
    addTearDown(env.dispose);
    final report = (await tester.runAsync(
      () => env.container
          .read(customerMoreRepositoryProvider)
          .spending(SpendingRange.lastMonths(12)),
    ))!;
    expect(report.months, hasLength(12));
    expect(report.totalOrders, greaterThan(0));

    await pumpCmApp(tester, env, location: '/spending');
    await pumpFor(tester, const Duration(seconds: 2));

    // Plaka (tek): sunucu toplamları; okumalar litre, ortalama ₺/L ve sipariş.
    expect(find.byType(AknPlate), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp(
          '^Toplam harcama ${RegExp.escape(Fmt.money(report.totalAmount))}.*'
          'ortalama ${RegExp.escape(Fmt.unitPrice(report.avgUnitPrice))}, '
          '${report.totalOrders} sipariş',
        ),
      ),
      findsOneWidget,
    );
    expect(find.text(Fmt.integer(report.totalOrders)), findsWidgets);
    expect(find.text(CmCopy.spendingCaption), findsOneWidget);

    // Sütun başına semantik: "Ekim 2026: 1.234,56 ₺" (Tutar ölçüsü).
    final m = report.months.lastWhere((x) => x.orderCount > 0);
    expect(
      find.bySemanticsLabel('${m.label}: ${Fmt.money(m.amount)}'),
      findsOneWidget,
    );

    // Litre ölçüsü: "Ekim 2026: 12.500 L".
    await tester.tap(find.text('Litre'));
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(
      find.bySemanticsLabel('${m.label}: ${Fmt.liters(m.liters)}'),
      findsOneWidget,
    );

    // Sütuna dokununca değer paneli.
    await tester.tap(
      find.bySemanticsLabel('${m.label}: ${Fmt.liters(m.liters)}'),
    );
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(find.text('${m.orderCount} sipariş'), findsWidgets);

    // Ürün sekmesi: sunucu kırılımları (en fazla 5 + Diğer).
    await tester.tap(find.text('Ürün'));
    await pumpFor(tester, const Duration(milliseconds: 800));
    expect(find.byType(BucketBars), findsOneWidget);
    for (final b in topBuckets(report.byProduct)) {
      expect(find.text(b.name), findsWidgets);
    }
    await finish(tester);
  });

  testWidgets('aralık 36 ayı aşamaz', (tester) async {
    final env = (await tester.runAsync(CmEnv.create))!;
    addTearDown(env.dispose);
    await pumpCmApp(tester, env, location: '/spending');
    await pumpFor(tester, const Duration(seconds: 1));
    await tester.ensureVisible(find.text('Son 36 ay'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Son 36 ay'));
    await pumpFor(tester, const Duration(seconds: 1));
    final req = env.requests.lastWhere(
      (r) => r.path == 'customers/me/spending',
    );
    expect(req.method, 'GET');
    final report = (await tester.runAsync(
      () => env.container
          .read(customerMoreRepositoryProvider)
          .spending(SpendingRange.lastMonths(36)),
    ))!;
    expect(report.months, hasLength(36));
    final wide = (await tester.runAsync(
      () => env.container
          .read(customerMoreRepositoryProvider)
          .spending(SpendingRange.lastMonths(48)),
    ))!;
    expect(wide.months.length, lessThanOrEqualTo(36), reason: 'sunucu kırpar');
    await finish(tester);
  });

  test('eksen yardımcıları', () {
    expect(niceMax(0), 1);
    expect(niceMax(1250000), 2000000);
    expect(niceMax(12500), 20000);
    expect(compactNumber(1250000), '1,25 Mn');
    expect(compactNumber(12500), '12,5 B');
  });

  testWidgets('aylık grafik: dokunma alanı 48 dp ve etiketli', (tester) async {
    final months = [
      for (var i = 1; i <= 12; i++)
        SpendingMonth(
          year: 2026,
          month: i,
          orderCount: i,
          liters: i * 1000.0,
          amount: i * 42000.0,
          avgUnitPrice: 42,
        ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: AknTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: MonthBarChart(months: months, metric: SpendingMetric.liters),
          ),
        ),
      ),
    );
    await pumpFor(tester, const Duration(milliseconds: 600));
    expect(
      find.bySemanticsLabel('Ekim 2026: ${Fmt.liters(10000)}'),
      findsOneWidget,
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  });
}

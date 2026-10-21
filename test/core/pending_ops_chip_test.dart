import 'package:akaryakitnet/core/offline/outbox_op.dart';
import 'package:akaryakitnet/core/offline/outbox_providers.dart';
import 'package:akaryakitnet/core/offline/pending_ops_chip.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

OutboxOp _op(String id, OutboxStatus status, {String? error}) {
  final now = DateTime.utc(2026, 10, 21, 9);
  return OutboxOp(
    id: id,
    userId: 'u-sofor',
    type: 'driver.deliver',
    payload: const {},
    idempotencyKey: 'k-$id',
    label: 'SVK-0000500$id teslimatı',
    status: status,
    lastError: error,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _pump(WidgetTester tester, List<OutboxOp> ops) =>
    tester.pumpWidget(
      ProviderScope(
        overrides: [outboxOpsProvider.overrideWith((ref) => Stream.value(ops))],
        child: MaterialApp(
          theme: AknTheme.light(),
          home: const Scaffold(body: Center(child: PendingOpsChip())),
        ),
      ),
    );

void main() {
  testWidgets('bekleyen yoksa görünmez', (tester) async {
    await _pump(tester, [_op('1', OutboxStatus.done)]);
    await tester.pump();
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('bekleyen sayısını gösterir; dokununca liste açılır', (
    tester,
  ) async {
    await _pump(tester, [
      _op('1', OutboxStatus.failed, error: 'İnternet bağlantısı yok.'),
      _op('2', OutboxStatus.pending),
    ]);
    await tester.pump();
    expect(find.text('2 işlem gönderilmeyi bekliyor'), findsOneWidget);
    await tester.tap(find.byType(PendingOpsChip));
    await tester.pumpAndSettle();
    expect(find.text('Bekleyen işlemler'), findsOneWidget);
    expect(find.text('SVK-00005001 teslimatı'), findsOneWidget);
    expect(find.byTooltip('Tekrar dene'), findsNWidgets(2));
    expect(find.byTooltip('Vazgeç'), findsNothing);
  });

  testWidgets('reddedilen işlem önceliklidir', (tester) async {
    await _pump(tester, [
      _op('1', OutboxStatus.needsAttention, error: 'Litre planlanandan fazla.'),
      _op('2', OutboxStatus.pending),
    ]);
    await tester.pump();
    expect(find.text('1 işlem ilgilenmenizi bekliyor'), findsOneWidget);
    await tester.tap(find.byType(PendingOpsChip));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Vazgeç'), findsOneWidget);
    expect(find.textContaining('Litre planlanandan fazla.'), findsOneWidget);
  });
}

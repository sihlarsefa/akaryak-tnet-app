// Price- and limit-sensitive actions use FRESH data (2026-11-02): screens may open from the cache, but
//
// * placing an order: just before "Gönder" the prices (payments/options) and the ordering status
//   (limit, finance) must have been read from the server within Freshness.decision; otherwise both are
//   read again, and a changed price or a blocked station stops the submit with a clear message;
// * accepting a quote: a quote shown from the cache (or older than Freshness.decision) is read again
//   first; a changed quote is not approved — the customer sees the new one.
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/customer_orders/api.dart';
import 'package:akaryakitnet/features/customer_orders/application/order_view_controller.dart';
import 'package:akaryakitnet/features/customer_orders/application/wizard_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/a2_support.dart';

void main() {
  late A2Env env;

  setUp(() async {
    env = await A2Env.create();
  });

  group('order wizard: fresh prices and limits before submit', () {
    Future<(ProviderContainer, OrderWizardController, int)> openWizard() async {
      final c = await env.signedIn('musteri');
      addTearDown(c.dispose);
      final sub = c.listen(orderWizardProvider, (_, _) {});
      addTearDown(sub.close);
      final ctrl = c.read(orderWizardProvider.notifier);
      await ctrl.init(const WizardLaunch());
      final w = c.read(orderWizardProvider);
      expect(w.ready, isTrue);
      final productId = c.read(orderFormProvider).data!.products.first.id;
      ctrl.updateLine(w.draft.lines.first.uid, productId: productId, liters: 5000);
      await ctrl.loadPayment();
      expect(c.read(orderWizardProvider).prices[productId], isNotNull);
      return (c, ctrl, productId);
    }

    DateTime later() => DateTime.now().toUtc().add(const Duration(minutes: 2));

    test('just read: ok without asking again', () async {
      final (_, ctrl, _) = await openWizard();
      final r = await ctrl.ensureFreshForSubmit();
      expect(r.ok, isTrue);
    });

    test('older than Freshness.decision, prices unchanged: read again, ok', () async {
      final (_, ctrl, _) = await openWizard();
      final r = await ctrl.ensureFreshForSubmit(now: later());
      expect(r.ok, isTrue, reason: r.message);
    });

    test('price changed meanwhile: not sent; the new price is shown, the next tap sends', () async {
      final (c, ctrl, productId) = await openWizard();
      final before = c.read(orderWizardProvider).prices[productId]!;
      final p = env.world.product(productId)!;
      p['listPrice'] = ((p['listPrice'] as num).toDouble() + 1.25);
      final r = await ctrl.ensureFreshForSubmit(now: later());
      expect(r.kind, FreshCheckKind.changed);
      expect(r.message, OrdersCopy.freshPricesChanged);
      expect(
        c.read(orderWizardProvider).prices[productId],
        closeTo(before + 1.25, 1e-6),
        reason: 'the summary now shows the new price',
      );
      expect((await ctrl.ensureFreshForSubmit()).ok, isTrue, reason: 'just read');
    });

    test('the station stopped taking orders (limit, finance): blocked with the reason', () async {
      final (c, ctrl, _) = await openWizard();
      final stationId = c.read(orderWizardProvider).draft.stationId!;
      final link = A2Fake.link(env.world, 101, stationId)!;
      link['orderingBlocked'] = 'Cari limitiniz doldu.';
      final r = await ctrl.ensureFreshForSubmit(now: later());
      expect(r.kind, FreshCheckKind.blocked);
      expect(r.message, 'Cari limitiniz doldu.');
    });

    test('fresh prices cannot be read (503): not sent with the old prices', () async {
      final (_, ctrl, _) = await openWizard();
      env.server.get(
        'payments/options',
        (req) => throw FakeResponse.problem(503, 'unavailable', 'Hizmet geçici olarak kullanılamıyor.'),
      );
      final r = await ctrl.ensureFreshForSubmit(now: later());
      expect(r.kind, FreshCheckKind.failed);
      expect(r.message, OrdersCopy.freshPricesFailed);
    });
  });

  group('accepting a quote shown from the cache', () {
    late int o2;
    setUp(() {
      final o = env.world.orders.firstWhere(
        (o) => o['status'] == 2 && o['customerId'] == 101,
      );
      o2 = o['id'] as int;
      // Açık hesap: belge gerekmez, birincil "Teklifi onayla" olur.
      o['paymentMethodCode'] = 'ACIK_HESAP';
    });

    /// Opens the order once (fills the cache), then reopens it with a slow server: the cached view
    /// shows at once while the fresh read is still on its way.
    Future<ProviderContainer> reopenFromCache(WidgetTester tester, {void Function(JsonMap order)? meanwhile}) async {
      final first = (await tester.runAsync(() => env.signedIn('musteri')))!;
      await pumpA2(tester, first, initialLocation: '/orders/$o2');
      await pumpUntil(tester, find.byType(AknFlowLine));
      await pumpReal(tester);
      await tearDownUi(tester);
      first.dispose();
      meanwhile?.call(env.world.order(o2)!);
      final c = (await tester.runAsync(() => env.signedIn('musteri')))!;
      addTearDown(c.dispose);
      env.server
        ..latencyEnabled = true
        ..minLatency = const Duration(seconds: 2)
        ..maxLatency = const Duration(seconds: 2);
      addTearDown(() => env.server.latencyEnabled = false);
      await pumpA2(tester, c, initialLocation: '/orders/$o2');
      await tester.pump(const Duration(milliseconds: 200));
      final s = c.read(orderViewProvider(o2));
      expect(s.fromCache, isTrue, reason: 'opened from the cache');
      return c;
    }

    Finder approve() => find.descendant(
      of: find.byType(ActionBar),
      matching: find.widgetWithText(AknButton, OrdersCopy.approve),
    );

    testWidgets('the bayi changed the price meanwhile: no approval, "Teklif güncellendi"', (tester) async {
      await reopenFromCache(
        tester,
        meanwhile: (o) {
          final q = (o['quotes'] as List).last as Map;
          q['unitPriceTry'] = (q['unitPriceTry'] as num).toDouble() + 2;
          q['totalAmountTry'] = (q['totalAmountTry'] as num).toDouble() + 2000;
        },
      );
      expect(approve(), findsOneWidget);
      await tester.tap(approve());
      await tester.pump();
      expect(find.text(OrdersCopy.freshQuoteChecking), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(OrdersCopy.freshQuoteChanged), findsOneWidget);
      expect(find.text('Teklifi onaylıyor musunuz?'), findsNothing, reason: 'no recap with an old price');
      expect(env.world.order(o2)!['status'], 2, reason: 'still waiting for the decision');
      await tearDownUi(tester);
    });

    testWidgets('unchanged: read again, then the approval recap opens', (tester) async {
      await reopenFromCache(tester);
      await tester.tap(approve());
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('Teklifi onaylıyor musunuz?'), findsOneWidget);
      expect(find.text(OrdersCopy.freshQuoteChanged), findsNothing);
      await tearDownUi(tester);
    });
  });
}

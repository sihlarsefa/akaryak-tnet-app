// The » Akış line (design v4 §3b, §9 core test): labels show at 320 dp in the web's words, never
// "Aşama x / y"; the bayi line; the vertical timeline at large text; the row pips.
import 'package:akaryakitnet/core/models/enums.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ui_test_helpers.dart';

void main() {
  group('AknFlowLine (» Akış)', () {
    testWidgets('labels shown at 320 dp, customer words, never "Aşama"', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpUi(
        tester,
        Center(
          child: SizedBox(
            width: 320,
            child: AknFlowLine(
              flow: AknFlow.customer(
                AknStatus.lampFor(
                  OrderStatus.awaitingApproval,
                  const StatusViewer.customer(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      for (final s in AknFlow.customerStops) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
      expect(find.textContaining('Aşama'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Aşama')), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('Onay adımında, sıra sizde')),
        findsOneWidget,
      );
      // The current stop is Pas 800 on the viewer's move.
      final current = tester.widget<Text>(find.text('Onay'));
      final style = DefaultTextStyle.of(
        tester.element(find.text('Onay')),
      ).style.merge(current.style);
      expect(style.fontWeight, FontWeight.w800);
      expect(style.color, AknColors.light.brandInk);
      semantics.dispose();
    });

    testWidgets('bayi words; at 1.3× text a vertical timeline', (tester) async {
      await pumpUi(
        tester,
        SizedBox(
          width: 350,
          child: AknFlowLine(
            flow: AknFlow.bayiAt(AknStage.teklif, yourMove: true),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      for (final s in AknFlow.bayiStops) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
      await pumpUi(
        tester,
        SizedBox(
          width: 350,
          child: AknFlowLine(flow: AknFlow.bayiAt(AknStage.karar)),
        ),
        textScale: 1.3,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(StepTimeline), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('stops: customer and bayi, delivered and problem', () {
      final delivered = AknFlow.customer(
        AknStatus.lampFor(
          ShipmentStatus.accepted,
          const StatusViewer.customer(),
        ),
      );
      expect(delivered.delivered, isTrue);
      expect(delivered.currentLabel, 'Teslim');
      final rejected = AknFlow.bayi(
        AknStatus.lampFor(
          OrderStatus.rejected,
          const StatusViewer.bayi(canQuote: true),
        ),
      );
      expect(rejected.problem, isTrue);
      expect(rejected.currentLabel, 'Müşteri onayı');
      final moving = AknFlow.customerAt(AknStage.yolda);
      expect(moving.moving, isTrue);
      expect(moving.currentLabel, 'Yolda');
    });

    testWidgets('pips: one segment per stop and the » mini tile', (
      tester,
    ) async {
      await pumpUi(
        tester,
        SizedBox(
          width: 340,
          child: AknFlowPips(
            flow: AknFlow.customerAt(AknStage.yolda),
            sentence: 'Yolda · varış 09:00',
          ),
        ),
      );
      expect(find.text('Yolda · varış 09:00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'pips in a list are quiet: your move reads ink, Pas only when urgent',
      (tester) async {
        Future<Color?> sentenceColor({required bool urgent}) async {
          await pumpUi(
            tester,
            SizedBox(
              width: 340,
              child: AknFlowPips(
                flow: AknFlow.bayiAt(AknStage.teklif, yourMove: true),
                sentence: 'Teklif verin',
                urgent: urgent,
              ),
            ),
          );
          return tester.widget<Text>(find.text('Teklif verin')).style!.color;
        }

        // P5: a move due in more than 3 h is ink; within 3 h it turns Pas.
        expect(await sentenceColor(urgent: false), AknColors.light.ink);
        expect(await sentenceColor(urgent: true), AknColors.light.brandInk);
        // Not the viewer's move: dim.
        await pumpUi(
          tester,
          SizedBox(
            width: 340,
            child: AknFlowPips(
              flow: AknFlow.bayiAt(AknStage.karar),
              sentence: 'Müşteri kararında',
            ),
          ),
        );
        expect(
          tester.widget<Text>(find.text('Müşteri kararında')).style!.color,
          AknColors.light.dim,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}

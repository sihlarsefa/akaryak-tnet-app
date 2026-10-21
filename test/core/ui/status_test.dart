import 'package:akaryakitnet/core/models/enums.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every server enum value has a style with icon and Turkish label', () {
    for (final values in allCodedEnums) {
      for (final v in values) {
        final s = AknStatus.of(v);
        expect(s.label.trim(), isNotEmpty, reason: '$v');
        expect(s.icon, isA<IconData>(), reason: '$v');
        if (v is ApprovalType) {
          expect(s.label, v.shortLabel);
        } else {
          expect(s.label, v.label, reason: '$v');
        }
      }
    }
  });

  group('tone table (spec C.5)', () {
    void tones<T extends CodedEnum>(
      StatusStyle Function(T) style,
      Map<T, AknTone> expected,
    ) {
      expected.forEach((value, tone) {
        expect(style(value).tone, tone, reason: '$value');
      });
    }

    test('order', () {
      tones(AknStatus.order, {
        OrderStatus.approved: AknTone.ok,
        OrderStatus.completed: AknTone.ok,
        OrderStatus.awaitingApproval: AknTone.warn,
        OrderStatus.rejected: AknTone.danger,
        OrderStatus.awaitingQuote: AknTone.info,
        OrderStatus.revisionRequested: AknTone.info,
        OrderStatus.expired: AknTone.neutral,
        OrderStatus.unknown: AknTone.neutral,
      });
      expect(AknStatus.order(OrderStatus.completed).solid, isTrue);
      expect(AknStatus.order(OrderStatus.approved).solid, isFalse);
    });

    test('shipment', () {
      tones(AknStatus.shipment, {
        ShipmentStatus.accepted: AknTone.ok,
        ShipmentStatus.reported: AknTone.warn,
        ShipmentStatus.disputed: AknTone.danger,
        ShipmentStatus.planned: AknTone.info,
        ShipmentStatus.inTransit: AknTone.brand,
        ShipmentStatus.cancelled: AknTone.neutral,
      });
    });

    test('approval and SLA', () {
      tones(AknStatus.approval, {
        ApprovalStatus.approved: AknTone.ok,
        ApprovalStatus.pending: AknTone.warn,
        ApprovalStatus.rejected: AknTone.danger,
        ApprovalStatus.infoRequested: AknTone.info,
        ApprovalStatus.cancelled: AknTone.neutral,
      });
      tones(AknStatus.sla, {
        ApprovalSlaState.dueSoon: AknTone.warn,
        ApprovalSlaState.overdue: AknTone.danger,
      });
    });

    test('payment', () {
      tones(AknStatus.payment, {
        PaymentStatus.collected: AknTone.ok,
        PaymentStatus.pending: AknTone.warn,
        PaymentStatus.bounced: AknTone.danger,
        PaymentStatus.documentUploaded: AknTone.info,
        PaymentStatus.refunded: AknTone.neutral,
        PaymentStatus.cancelled: AknTone.neutral,
        PaymentStatus.none: AknTone.neutral,
      });
    });

    test('finance', () {
      tones(AknStatus.finance, {
        OrderFinanceStatus.approved: AknTone.ok,
        OrderFinanceStatus.conditionallyApproved: AknTone.ok,
        OrderFinanceStatus.pending: AknTone.warn,
        OrderFinanceStatus.rejected: AknTone.danger,
        OrderFinanceStatus.infoRequested: AknTone.info,
      });
    });

    test('lead', () {
      tones(AknStatus.lead, {
        LeadStatus.approved: AknTone.ok,
        LeadStatus.converted: AknTone.ok,
        LeadStatus.infoRequested: AknTone.warn,
        LeadStatus.rejected: AknTone.danger,
        LeadStatus.submitted: AknTone.info,
        LeadStatus.inReview: AknTone.info,
        LeadStatus.draft: AknTone.neutral,
        LeadStatus.cancelled: AknTone.neutral,
      });
      expect(AknStatus.lead(LeadStatus.converted).solid, isTrue);
    });

    test('field form', () {
      tones(AknStatus.fieldForm, {
        FieldOrderFormStatus.approved: AknTone.ok,
        FieldOrderFormStatus.converted: AknTone.ok,
        FieldOrderFormStatus.pendingApproval: AknTone.warn,
        FieldOrderFormStatus.rejected: AknTone.danger,
        FieldOrderFormStatus.draft: AknTone.neutral,
        FieldOrderFormStatus.cancelled: AknTone.neutral,
      });
      expect(AknStatus.fieldForm(FieldOrderFormStatus.converted).solid, isTrue);
    });

    test('barem band, both server vocabularies', () {
      expect(AknStatus.band('auto').tone, AknTone.ok);
      expect(AknStatus.band('ok').tone, AknTone.ok);
      expect(AknStatus.band('manager').tone, AknTone.warn);
      expect(AknStatus.band('mid').tone, AknTone.warn);
      expect(AknStatus.band('reject').tone, AknTone.danger);
      expect(AknStatus.band('senior').tone, AknTone.brand);
      expect(AknStatus.band('low').tone, AknTone.brand);
      expect(AknStatus.band('exception').tone, AknTone.brand);
      expect(AknStatus.band(null).tone, AknTone.neutral);
      expect(AknStatus.band('auto', label: 'Otomatik').label, 'Otomatik');
    });
  });

  test('server labels win when present', () {
    final s = OrderStatus.approved.statusStyle;
    expect(s.withLabel('Onaylandı (bayi)').label, 'Onaylandı (bayi)');
    expect(s.withLabel('  ').label, s.label);
    expect(s.withLabel(null), same(s));
  });

  test('server tone keys and notification severity', () {
    expect(AknStatus.toneFromKey('ok'), AknTone.ok);
    expect(AknStatus.toneFromKey('WARN'), AknTone.warn);
    expect(AknStatus.toneFromKey('danger'), AknTone.danger);
    expect(AknStatus.toneFromKey('info'), AknTone.info);
    expect(AknStatus.toneFromKey('neutral'), AknTone.neutral);
    expect(AknStatus.toneFromKey('is-violet'), AknTone.brand);
    expect(AknStatus.toneFromKey(null), AknTone.neutral);
    expect(AknStatus.toneFromSeverity(0), AknTone.info);
    expect(AknStatus.toneFromSeverity(1), AknTone.ok);
    expect(AknStatus.toneFromSeverity(2), AknTone.warn);
    expect(AknStatus.toneFromSeverity(3), AknTone.danger);
    expect(
      AknStatus.custom('Limit aşıldı', tone: 'danger').tone,
      AknTone.danger,
    );
  });

  testWidgets('StatusChip shows icon and label, never colour alone', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AknTheme.light(),
        home: Scaffold(
          body: StatusChip.style(ShipmentStatus.inTransit.statusStyle),
        ),
      ),
    );
    expect(find.text('Yolda'), findsOneWidget);
    expect(find.byIcon(Icons.local_shipping_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('Yolda'), findsOneWidget);
  });
}

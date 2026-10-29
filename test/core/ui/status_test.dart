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

  group('generic lamp tones (design v2 §2.4): orange only via lampFor', () {
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
        OrderStatus.awaitingApproval: AknTone.info,
        OrderStatus.created: AknTone.info,
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
        ShipmentStatus.reported: AknTone.info,
        ShipmentStatus.disputed: AknTone.danger,
        ShipmentStatus.planned: AknTone.info,
        ShipmentStatus.inTransit: AknTone.info,
        ShipmentStatus.cancelled: AknTone.neutral,
      });
    });

    test('approval and SLA', () {
      tones(AknStatus.approval, {
        ApprovalStatus.approved: AknTone.ok,
        ApprovalStatus.pending: AknTone.info,
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
        PaymentStatus.pending: AknTone.info,
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
        OrderFinanceStatus.pending: AknTone.info,
        OrderFinanceStatus.rejected: AknTone.danger,
        OrderFinanceStatus.infoRequested: AknTone.info,
      });
    });

    test('lead', () {
      tones(AknStatus.lead, {
        LeadStatus.approved: AknTone.ok,
        LeadStatus.converted: AknTone.ok,
        LeadStatus.infoRequested: AknTone.info,
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
        FieldOrderFormStatus.pendingApproval: AknTone.info,
        FieldOrderFormStatus.rejected: AknTone.danger,
        FieldOrderFormStatus.draft: AknTone.neutral,
        FieldOrderFormStatus.cancelled: AknTone.neutral,
      });
      expect(AknStatus.fieldForm(FieldOrderFormStatus.converted).solid, isTrue);
    });

    test('company request', () {
      tones(AknStatus.companyRequest, {
        CustomerOrderRequestStatus.pending: AknTone.info,
        CustomerOrderRequestStatus.approved: AknTone.ok,
        CustomerOrderRequestStatus.rejected: AknTone.danger,
        CustomerOrderRequestStatus.cancelled: AknTone.neutral,
      });
    });

    test('no generic style claims "your move" (rule 3)', () {
      for (final values in allCodedEnums) {
        for (final v in values) {
          expect(AknStatus.of(v).tone, isNot(AknTone.brand), reason: '$v');
        }
      }
    });

    test('barem band, both server vocabularies', () {
      expect(AknStatus.band('auto').tone, AknTone.ok);
      expect(AknStatus.band('ok').tone, AknTone.ok);
      expect(AknStatus.band('manager').tone, AknTone.warn);
      expect(AknStatus.band('mid').tone, AknTone.warn);
      expect(AknStatus.band('reject').tone, AknTone.danger);
      // A higher approval is a warning, not "your move".
      expect(AknStatus.band('senior').tone, AknTone.warn);
      expect(AknStatus.band('low').tone, AknTone.warn);
      expect(AknStatus.band('exception').tone, AknTone.warn);
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

  group('viewer-aware lamps (§10.3)', () {
    const approver = StatusViewer.customer();
    const requester = StatusViewer.customer(canDecide: false);
    const desk = StatusViewer.bayi(canQuote: true);
    const dispatch = StatusViewer.bayi(canPlan: true);
    const finance = StatusViewer.bayi(canDecide: true);
    const viewer = StatusViewer.bayi();

    void lamp(
      StatusLamp l,
      AknTone tone,
      String label, {
      AknStage? stage,
      bool problem = false,
      bool complete = false,
    }) {
      expect(l.tone, tone, reason: label);
      expect(l.label, label);
      if (stage != null) expect(l.stage, stage, reason: label);
      expect(l.problem, problem, reason: label);
      expect(l.complete, complete, reason: label);
      expect(l.yourMove, tone == AknTone.brand);
    }

    test('order: awaiting quote', () {
      const s = OrderStatus.awaitingQuote;
      lamp(
        AknStatus.lampFor(s, approver),
        AknTone.info,
        'Teklif bekleniyor',
        stage: AknStage.teklif,
      );
      lamp(
        AknStatus.lampFor(s, desk),
        AknTone.brand,
        'Teklif verin',
        stage: AknStage.teklif,
      );
      lamp(AknStatus.lampFor(s, viewer), AknTone.info, 'Teklif bekleniyor');
    });

    test('order: awaiting the customer decision', () {
      const s = OrderStatus.awaitingApproval;
      lamp(
        AknStatus.lampFor(s, approver),
        AknTone.brand,
        'Teklifi onaylayın',
        stage: AknStage.karar,
      );
      lamp(AknStatus.lampFor(s, requester), AknTone.info, 'Onay bekleniyor');
      lamp(AknStatus.lampFor(s, desk), AknTone.info, 'Müşteri kararında');
    });

    test('order: revision, approved, completed, rejected, expired', () {
      lamp(
        AknStatus.lampFor(OrderStatus.revisionRequested, approver),
        AknTone.info,
        'Revize istendi',
      );
      lamp(
        AknStatus.lampFor(OrderStatus.revisionRequested, desk),
        AknTone.brand,
        'Revize istendi',
      );
      lamp(
        AknStatus.lampFor(OrderStatus.approved, approver),
        AknTone.info,
        'Sevkiyat planlanıyor',
        stage: AknStage.plan,
      );
      lamp(
        AknStatus.lampFor(OrderStatus.approved, dispatch),
        AknTone.brand,
        'Sevkiyat planlayın',
        stage: AknStage.plan,
      );
      lamp(
        AknStatus.lampFor(OrderStatus.completed, approver),
        AknTone.ok,
        'Tamamlandı',
        stage: AknStage.teslim,
        complete: true,
      );
      lamp(
        AknStatus.lampFor(OrderStatus.rejected, desk),
        AknTone.danger,
        'Reddedildi',
        stage: AknStage.karar,
        problem: true,
      );
      lamp(
        AknStatus.lampFor(OrderStatus.expired, approver),
        AknTone.neutral,
        'Süresi doldu',
      );
    });

    test('an approved order with a shipment reads as the shipment', () {
      lamp(
        AknStatus.lampFor(
          OrderStatus.approved,
          approver,
          shipment: ShipmentStatus.inTransit,
        ),
        AknTone.info,
        'Yolda',
        stage: AknStage.yolda,
      );
      lamp(
        AknStatus.lampFor(
          OrderStatus.approved,
          approver,
          shipment: ShipmentStatus.reported,
        ),
        AknTone.brand,
        'Teslimatı onaylayın',
        stage: AknStage.teslim,
      );
      // Completed + accepted stays "Tamamlandı".
      lamp(
        AknStatus.lampFor(
          OrderStatus.completed,
          approver,
          shipment: ShipmentStatus.accepted,
        ),
        AknTone.ok,
        'Tamamlandı',
        complete: true,
      );
    });

    test('shipment', () {
      lamp(
        AknStatus.lampFor(ShipmentStatus.planned, desk),
        AknTone.info,
        'Planlandı',
        stage: AknStage.plan,
      );
      lamp(
        AknStatus.lampFor(ShipmentStatus.reported, approver),
        AknTone.brand,
        'Teslimatı onaylayın',
      );
      lamp(
        AknStatus.lampFor(ShipmentStatus.reported, dispatch),
        AknTone.info,
        'Kabul bekliyor',
      );
      lamp(
        AknStatus.lampFor(ShipmentStatus.accepted, dispatch),
        AknTone.ok,
        'Teslim alındı',
        complete: true,
      );
      lamp(
        AknStatus.lampFor(ShipmentStatus.disputed, approver),
        AknTone.danger,
        'İtirazlı',
        problem: true,
      );
      lamp(
        AknStatus.lampFor(ShipmentStatus.cancelled, approver),
        AknTone.neutral,
        'İptal',
        problem: true,
      );
    });

    test('company request and approval center', () {
      // v4 §3.2: the viewer's move is an imperative.
      lamp(
        AknStatus.lampFor(CustomerOrderRequestStatus.pending, approver),
        AknTone.brand,
        'Talebi onaylayın',
        stage: AknStage.onay,
      );
      expect(
        AknStatus.companyRequestLamp(
          CustomerOrderRequestStatus.pending,
          approver,
          requester: 'Burak Yılmaz',
        ).label,
        "Burak Yılmaz'ın talebini onaylayın",
      );
      expect(
        AknStatus.companyRequestLamp(
          CustomerOrderRequestStatus.pending,
          requester,
          actor: 'Selin Aydın',
        ).label,
        'Şirket onayında · Selin Aydın',
      );
      lamp(
        AknStatus.lampFor(CustomerOrderRequestStatus.pending, requester),
        AknTone.info,
        'Şirket onayında',
        stage: AknStage.onay,
      );
      lamp(
        AknStatus.lampFor(ApprovalStatus.pending, finance),
        AknTone.brand,
        'Karar verin',
      );
      lamp(
        AknStatus.lampFor(ApprovalStatus.pending, viewer),
        AknTone.info,
        'Onay bekleniyor',
      );
      lamp(
        AknStatus.lampFor(
          ApprovalStatus.pending,
          finance,
          sla: ApprovalSlaState.overdue,
        ),
        AknTone.danger,
        'Süresi geçti',
      );
    });

    test('server labels are the fallback', () {
      // A status without a viewer-aware phrase keeps the server label.
      final l = AknStatus.lampFor(
        PaymentStatus.collected,
        approver,
        serverLabel: 'Tahsil edildi (EFT)',
      );
      expect(l.label, 'Tahsil edildi (EFT)');
      expect(l.tone, AknTone.ok);
      expect(l.stage, isNull);
      expect(
        AknStatus.lampFor(
          OrderStatus.unknown,
          approver,
          serverLabel: 'Arşivde',
        ).label,
        'Arşivde',
      );
      // The viewer-aware phrase wins over the generic server label.
      expect(
        AknStatus.lampFor(
          OrderStatus.awaitingApproval,
          approver,
          serverLabel: 'Onay bekleniyor',
        ).label,
        'Teklifi onaylayın',
      );
    });

    test('stage strip stops and indices', () {
      expect(AknStage.stops().map((s) => s.label), [
        'Talep',
        'Teklif',
        'Karar',
        'Plan',
        'Yolda',
        'Teslim',
      ]);
      expect(AknStage.stops(companyApproval: true), hasLength(7));
      expect(AknStage.karar.indexIn(), 2);
      expect(AknStage.karar.indexIn(companyApproval: true), 3);
      expect(AknStage.onay.indexIn(), -1);
      final l = AknStatus.lampFor(OrderStatus.awaitingApproval, approver);
      expect(l.stageIndex(), 2);
      expect(l.stageIndex(companyApproval: true), 3);
      expect(l.style.label, 'Teklifi onaylayın');
      expect(l.style.tone, AknTone.brand);
    });

    test('v4 stops on the » line (customer and bayi words)', () {
      expect(
        [for (final s in AknStage.values) s.customerStop],
        [0, 0, 1, 2, 3, 3, 4],
      );
      expect(
        [for (final s in AknStage.values) s.bayiStop],
        [0, 0, 0, 1, 2, 2, 3],
      );
      // One lamp covers the decision and its missing document.
      expect(
        AknStatus.orderLamp(
          OrderStatus.awaitingApproval,
          approver,
          missingDocument: AknStatus.uploadPhrase(AttachmentKind.chequeImage),
        ).label,
        'Çek görselini yükleyin',
      );
      expect(
        AknStatus.uploadAction(AttachmentKind.transferReceipt),
        'Dekontu yükle',
      );
      expect(
        AknStatus.orderLamp(
          OrderStatus.awaitingQuote,
          approver,
          actor: 'Demir Petrol',
        ).label,
        'Demir Petrol teklif hazırlıyor',
      );
      expect(AknStatus.withGenitive('Selin Aydın'), "Selin Aydın'ın");
      expect(AknStatus.withGenitive('Elif Demir'), "Elif Demir'in");
      expect(AknStatus.withGenitive('Ali'), "Ali'nin");
    });
  });

  testWidgets('StatusChip shows the label, never colour alone', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AknTheme.light(),
        home: Scaffold(
          body: StatusChip.style(ShipmentStatus.inTransit.statusStyle),
        ),
      ),
    );
    expect(find.text('Yolda'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Yolda')), findsOneWidget);
  });
}

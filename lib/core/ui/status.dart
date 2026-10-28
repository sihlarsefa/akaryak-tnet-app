import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/enums.dart';
import '../utils/turkish_text.dart';
import 'tokens.dart';

/// Tone, icon and Turkish label of one status value. Status is never shown by
/// colour alone: it renders as a tinted pill — the tone's soft well, a dot
/// with a halo and the label (`StatusChip` / `AknLamp`, design v3 §4); the
/// icon stays in the data for semantics.
@immutable
class StatusStyle {
  const StatusStyle({
    required this.tone,
    required this.icon,
    required this.label,
    this.solid = false,
  });

  final AknTone tone;
  final IconData icon;
  final String label;

  /// Terminal successes (Tamamlandı, Dönüştürüldü): the pill shows a check
  /// disc instead of the dot.
  final bool solid;

  /// Prefers the server's `*Label` when it sends one.
  StatusStyle withLabel(String? serverLabel) {
    final l = serverLabel?.trim();
    if (l == null || l.isEmpty || l == label) return this;
    return StatusStyle(tone: tone, icon: icon, label: l, solid: solid);
  }

  StatusStyle copyWith({
    AknTone? tone,
    IconData? icon,
    String? label,
    bool? solid,
  }) => StatusStyle(
    tone: tone ?? this.tone,
    icon: icon ?? this.icon,
    label: label ?? this.label,
    solid: solid ?? this.solid,
  );

  @override
  bool operator ==(Object other) =>
      other is StatusStyle &&
      other.tone == tone &&
      other.icon == icon &&
      other.label == label &&
      other.solid == solid;

  @override
  int get hashCode => Object.hash(tone, icon, label, solid);

  @override
  String toString() => 'StatusStyle($label, $tone${solid ? ', solid' : ''})';
}

/// Maps every server enum (`core/models/enums.dart`) to a [StatusStyle].
///
/// Pill tones (design v3 §2, §4): `brand` = "your move" (soft orange well,
/// breathing orange dot, Pas label) — only the viewer-aware [lampFor] can
/// know that, so the generic table below never uses it; `info` = in
/// progress, someone else's move (ink dot on the grey well); `ok` green;
/// `warn` ochre (a warning: due soon, needs a higher approval); `danger`
/// red; `neutral` = closed (hollow ring, dim label).
///
/// | | ok | warn | danger | info (in progress) | neutral (closed) |
/// |---|---|---|---|---|---|
/// | Order | Approved; Completed (solid) | | Rejected | Created, AwaitingQuote, AwaitingApproval, RevisionRequested | Expired |
/// | Shipment | Accepted | | Disputed | Planned, InTransit, Reported | Cancelled |
/// | Approval | Approved | SLA DueSoon | Rejected; SLA Overdue | Pending, InfoRequested | Cancelled |
/// | Payment | Collected | | Bounced | Pending, DocumentUploaded | Refunded, Cancelled, None |
/// | Finance | Approved, Conditional | | Rejected, Suspended | Pending, InfoRequested | NotRequired |
/// | Lead | Approved; Converted (solid) | | Rejected | Submitted, InReview, InfoRequested | Draft, Cancelled |
/// | Field form | Approved; Converted (solid) | | Rejected | PendingApproval | Draft, Cancelled |
/// | Company request | Approved | | Rejected | Pending | Cancelled |
/// | Barem band | auto | manager, senior, exception, unknown | out of range | | none |
abstract final class AknStatus {
  static const _unknownIcon = PhosphorIconsRegular.question;

  static StatusStyle _s(
    AknTone tone,
    IconData icon,
    CodedEnum e, {
    bool solid = false,
  }) => StatusStyle(tone: tone, icon: icon, label: e.label, solid: solid);

  static StatusStyle order(OrderStatus s) => switch (s) {
    OrderStatus.created => _s(AknTone.info, PhosphorIconsFill.receipt, s),
    OrderStatus.awaitingQuote => _s(AknTone.info, PhosphorIconsFill.invoice, s),
    OrderStatus.awaitingApproval => _s(
      AknTone.info,
      PhosphorIconsRegular.hourglassHigh,
      s,
    ),
    OrderStatus.approved => _s(AknTone.ok, PhosphorIconsFill.checkCircle, s),
    OrderStatus.rejected => _s(AknTone.danger, PhosphorIconsFill.xCircle, s),
    OrderStatus.revisionRequested => _s(
      AknTone.info,
      PhosphorIconsRegular.pencilSimple,
      s,
    ),
    OrderStatus.expired => _s(
      AknTone.neutral,
      PhosphorIconsRegular.hourglassLow,
      s,
    ),
    OrderStatus.completed => _s(
      AknTone.ok,
      PhosphorIconsFill.checkCircle,
      s,
      solid: true,
    ),
    OrderStatus.unknown => _s(AknTone.neutral, _unknownIcon, s),
  };

  static StatusStyle shipment(ShipmentStatus s) => switch (s) {
    ShipmentStatus.planned => _s(
      AknTone.info,
      PhosphorIconsRegular.calendarDot,
      s,
    ),
    ShipmentStatus.inTransit => _s(AknTone.info, PhosphorIconsFill.truck, s),
    ShipmentStatus.reported => _s(
      AknTone.info,
      PhosphorIconsFill.listChecks,
      s,
    ),
    ShipmentStatus.accepted => _s(AknTone.ok, PhosphorIconsFill.sealCheck, s),
    ShipmentStatus.disputed => _s(
      AknTone.danger,
      PhosphorIconsFill.warningOctagon,
      s,
    ),
    ShipmentStatus.cancelled => _s(
      AknTone.neutral,
      PhosphorIconsRegular.prohibit,
      s,
    ),
    ShipmentStatus.unknown => _s(AknTone.neutral, _unknownIcon, s),
  };

  static StatusStyle approval(ApprovalStatus s) => switch (s) {
    ApprovalStatus.pending => _s(
      AknTone.info,
      PhosphorIconsRegular.hourglassHigh,
      s,
    ),
    ApprovalStatus.approved => _s(AknTone.ok, PhosphorIconsFill.checkCircle, s),
    ApprovalStatus.rejected => _s(AknTone.danger, PhosphorIconsFill.xCircle, s),
    ApprovalStatus.cancelled => _s(
      AknTone.neutral,
      PhosphorIconsRegular.prohibit,
      s,
    ),
    ApprovalStatus.infoRequested => _s(
      AknTone.info,
      PhosphorIconsFill.chatCircleDots,
      s,
    ),
    ApprovalStatus.unknown => _s(AknTone.neutral, _unknownIcon, s),
  };

  static StatusStyle sla(ApprovalSlaState s) => switch (s) {
    ApprovalSlaState.none => _s(AknTone.neutral, PhosphorIconsRegular.clock, s),
    ApprovalSlaState.onTime => _s(
      AknTone.neutral,
      PhosphorIconsRegular.clock,
      s,
    ),
    ApprovalSlaState.dueSoon => _s(AknTone.warn, PhosphorIconsRegular.alarm, s),
    ApprovalSlaState.overdue => _s(
      AknTone.danger,
      PhosphorIconsRegular.alarm,
      s,
    ),
    ApprovalSlaState.unknown => _s(AknTone.neutral, _unknownIcon, s),
  };

  static StatusStyle decision(ApprovalDecision d) => switch (d) {
    ApprovalDecision.approve => _s(
      AknTone.ok,
      PhosphorIconsFill.checkCircle,
      d,
    ),
    ApprovalDecision.conditionalApprove => _s(
      AknTone.ok,
      PhosphorIconsRegular.listChecks,
      d,
    ),
    ApprovalDecision.requestInfo => _s(
      AknTone.info,
      PhosphorIconsFill.chatCircleDots,
      d,
    ),
    ApprovalDecision.reject => _s(AknTone.danger, PhosphorIconsFill.xCircle, d),
    ApprovalDecision.unknown => _s(AknTone.neutral, _unknownIcon, d),
  };

  /// Approval types are categories, not states: neutral tone, distinct icon.
  static StatusStyle approvalType(ApprovalType t) {
    final icon = switch (t) {
      ApprovalType.fieldOrderProfit => PhosphorIconsRegular.trendUp,
      ApprovalType.limitChange => PhosphorIconsFill.gauge,
      ApprovalType.companyOrderRequest => PhosphorIconsFill.listChecks,
      ApprovalType.orderFinance => PhosphorIconsFill.bank,
      ApprovalType.fieldFormFinance => PhosphorIconsRegular.clipboardText,
      ApprovalType.customerOnboarding => PhosphorIconsRegular.userPlus,
      ApprovalType.leadFinance => PhosphorIconsRegular.userCheck,
      ApprovalType.unknown => PhosphorIconsFill.checkCircle,
    };
    return StatusStyle(tone: AknTone.neutral, icon: icon, label: t.shortLabel);
  }

  static StatusStyle payment(PaymentStatus s) => switch (s) {
    PaymentStatus.none => _s(
      AknTone.neutral,
      PhosphorIconsRegular.minusCircle,
      s,
    ),
    PaymentStatus.pending => _s(AknTone.info, PhosphorIconsRegular.clock, s),
    PaymentStatus.documentUploaded => _s(
      AknTone.info,
      PhosphorIconsRegular.fileArrowUp,
      s,
    ),
    PaymentStatus.collected => _s(
      AknTone.ok,
      PhosphorIconsRegular.handCoins,
      s,
    ),
    PaymentStatus.bounced => _s(
      AknTone.danger,
      PhosphorIconsRegular.receiptX,
      s,
    ),
    PaymentStatus.refunded => _s(
      AknTone.neutral,
      PhosphorIconsRegular.arrowUUpLeft,
      s,
    ),
    PaymentStatus.cancelled => _s(
      AknTone.neutral,
      PhosphorIconsRegular.prohibit,
      s,
    ),
    PaymentStatus.unknown => _s(AknTone.neutral, _unknownIcon, s),
  };

  static StatusStyle finance(OrderFinanceStatus s) => switch (s) {
    OrderFinanceStatus.notRequired => _s(
      AknTone.neutral,
      PhosphorIconsRegular.minusCircle,
      s,
    ),
    OrderFinanceStatus.pending => _s(AknTone.info, PhosphorIconsFill.bank, s),
    OrderFinanceStatus.approved => _s(
      AknTone.ok,
      PhosphorIconsFill.shieldCheck,
      s,
    ),
    OrderFinanceStatus.conditionallyApproved => _s(
      AknTone.ok,
      PhosphorIconsRegular.listChecks,
      s,
    ),
    OrderFinanceStatus.infoRequested => _s(
      AknTone.info,
      PhosphorIconsFill.chatCircleDots,
      s,
    ),
    OrderFinanceStatus.rejected => _s(
      AknTone.danger,
      PhosphorIconsFill.shieldSlash,
      s,
    ),
    OrderFinanceStatus.unknown => _s(AknTone.neutral, _unknownIcon, s),
  };

  static StatusStyle financeProfile(FinanceProfileStatus s) => switch (s) {
    FinanceProfileStatus.pending => _s(
      AknTone.info,
      PhosphorIconsRegular.hourglassHigh,
      s,
    ),
    FinanceProfileStatus.approved => _s(
      AknTone.ok,
      PhosphorIconsFill.shieldCheck,
      s,
    ),
    FinanceProfileStatus.conditional => _s(
      AknTone.ok,
      PhosphorIconsRegular.listChecks,
      s,
    ),
    FinanceProfileStatus.infoRequested => _s(
      AknTone.info,
      PhosphorIconsFill.chatCircleDots,
      s,
    ),
    FinanceProfileStatus.rejected => _s(
      AknTone.danger,
      PhosphorIconsFill.shieldSlash,
      s,
    ),
    FinanceProfileStatus.suspended => _s(
      AknTone.danger,
      PhosphorIconsFill.pauseCircle,
      s,
    ),
    FinanceProfileStatus.unknown => _s(AknTone.neutral, _unknownIcon, s),
  };

  static StatusStyle lead(LeadStatus s) => switch (s) {
    LeadStatus.draft => _s(AknTone.neutral, PhosphorIconsRegular.notePencil, s),
    LeadStatus.submitted => _s(
      AknTone.info,
      PhosphorIconsRegular.paperPlaneRight,
      s,
    ),
    LeadStatus.inReview => _s(
      AknTone.info,
      PhosphorIconsRegular.listMagnifyingGlass,
      s,
    ),
    LeadStatus.infoRequested => _s(
      AknTone.info,
      PhosphorIconsFill.chatCircleDots,
      s,
    ),
    LeadStatus.approved => _s(AknTone.ok, PhosphorIconsFill.checkCircle, s),
    LeadStatus.converted => _s(
      AknTone.ok,
      PhosphorIconsRegular.userCheck,
      s,
      solid: true,
    ),
    LeadStatus.rejected => _s(AknTone.danger, PhosphorIconsFill.xCircle, s),
    LeadStatus.cancelled => _s(
      AknTone.neutral,
      PhosphorIconsRegular.prohibit,
      s,
    ),
    LeadStatus.unknown => _s(AknTone.neutral, _unknownIcon, s),
  };

  static StatusStyle fieldForm(FieldOrderFormStatus s) => switch (s) {
    FieldOrderFormStatus.draft => _s(
      AknTone.neutral,
      PhosphorIconsRegular.notePencil,
      s,
    ),
    FieldOrderFormStatus.pendingApproval => _s(
      AknTone.info,
      PhosphorIconsRegular.hourglassHigh,
      s,
    ),
    FieldOrderFormStatus.approved => _s(
      AknTone.ok,
      PhosphorIconsFill.checkCircle,
      s,
    ),
    FieldOrderFormStatus.rejected => _s(
      AknTone.danger,
      PhosphorIconsFill.xCircle,
      s,
    ),
    FieldOrderFormStatus.converted => _s(
      AknTone.ok,
      PhosphorIconsFill.receipt,
      s,
      solid: true,
    ),
    FieldOrderFormStatus.cancelled => _s(
      AknTone.neutral,
      PhosphorIconsRegular.prohibit,
      s,
    ),
    FieldOrderFormStatus.unknown => _s(AknTone.neutral, _unknownIcon, s),
  };

  static StatusStyle instrument(InstrumentStatus s) => switch (s) {
    InstrumentStatus.received => _s(
      AknTone.info,
      PhosphorIconsRegular.trayArrowDown,
      s,
    ),
    InstrumentStatus.inPortfolio => _s(
      AknTone.neutral,
      PhosphorIconsFill.folder,
      s,
    ),
    InstrumentStatus.deposited => _s(AknTone.info, PhosphorIconsFill.bank, s),
    InstrumentStatus.collected => _s(
      AknTone.ok,
      PhosphorIconsRegular.handCoins,
      s,
    ),
    InstrumentStatus.bounced => _s(
      AknTone.danger,
      PhosphorIconsRegular.receiptX,
      s,
    ),
    InstrumentStatus.returned => _s(
      AknTone.neutral,
      PhosphorIconsRegular.arrowUUpLeft,
      s,
    ),
    InstrumentStatus.protested => _s(
      AknTone.danger,
      PhosphorIconsRegular.gavel,
      s,
    ),
    InstrumentStatus.unknown => _s(AknTone.neutral, _unknownIcon, s),
  };

  static StatusStyle instrumentKind(InstrumentKind k) => switch (k) {
    InstrumentKind.cheque => _s(AknTone.neutral, PhosphorIconsRegular.money, k),
    InstrumentKind.promissoryNote => _s(
      AknTone.neutral,
      PhosphorIconsRegular.fileText,
      k,
    ),
    InstrumentKind.letterOfGuarantee => _s(
      AknTone.neutral,
      PhosphorIconsFill.sealCheck,
      k,
    ),
    InstrumentKind.unknown => _s(AknTone.neutral, _unknownIcon, k),
  };

  static StatusStyle companyRequest(CustomerOrderRequestStatus s) =>
      switch (s) {
        CustomerOrderRequestStatus.pending => _s(
          AknTone.info,
          PhosphorIconsRegular.hourglassHigh,
          s,
        ),
        CustomerOrderRequestStatus.approved => _s(
          AknTone.ok,
          PhosphorIconsFill.checkCircle,
          s,
        ),
        CustomerOrderRequestStatus.rejected => _s(
          AknTone.danger,
          PhosphorIconsFill.xCircle,
          s,
        ),
        CustomerOrderRequestStatus.cancelled => _s(
          AknTone.neutral,
          PhosphorIconsRegular.arrowUUpLeft,
          s,
        ),
        CustomerOrderRequestStatus.unknown => _s(
          AknTone.neutral,
          _unknownIcon,
          s,
        ),
      };

  static StatusStyle customerRole(CustomerUserRole r) => switch (r) {
    CustomerUserRole.requester => _s(
      AknTone.neutral,
      PhosphorIconsRegular.user,
      r,
    ),
    CustomerUserRole.approver => _s(
      AknTone.neutral,
      PhosphorIconsRegular.userCheck,
      r,
    ),
    CustomerUserRole.admin => _s(
      AknTone.neutral,
      PhosphorIconsRegular.userCircleGear,
      r,
    ),
    CustomerUserRole.unknown => _s(AknTone.neutral, _unknownIcon, r),
  };

  static StatusStyle risk(RiskClass r) => switch (r) {
    RiskClass.none => _s(AknTone.neutral, PhosphorIconsRegular.shield, r),
    RiskClass.a => _s(AknTone.ok, PhosphorIconsFill.shield, r),
    RiskClass.b => _s(AknTone.info, PhosphorIconsFill.shield, r),
    RiskClass.c => _s(AknTone.warn, PhosphorIconsFill.shield, r),
    RiskClass.d => _s(AknTone.danger, PhosphorIconsFill.shieldWarning, r),
    RiskClass.unknown => _s(AknTone.neutral, _unknownIcon, r),
  };

  static StatusStyle attachmentKind(AttachmentKind k) {
    final icon = switch (k) {
      AttachmentKind.chequeImage => PhosphorIconsRegular.money,
      AttachmentKind.promissoryNoteImage => PhosphorIconsRegular.fileText,
      AttachmentKind.transferReceipt => PhosphorIconsFill.receipt,
      AttachmentKind.posSlip => PhosphorIconsRegular.cashRegister,
      AttachmentKind.letterOfGuarantee => PhosphorIconsFill.sealCheck,
      AttachmentKind.dbsContract => PhosphorIconsRegular.handshake,
      AttachmentKind.taxPlate => PhosphorIconsFill.identificationBadge,
      AttachmentKind.signatureCircular => PhosphorIconsRegular.signature,
      AttachmentKind.tradeRegistryGazette => PhosphorIconsRegular.newspaper,
      AttachmentKind.activityCertificate => PhosphorIconsRegular.certificate,
      AttachmentKind.visitPhoto => PhosphorIconsRegular.camera,
      AttachmentKind.riskReportPdf => PhosphorIconsRegular.filePdf,
      AttachmentKind.financeNote => PhosphorIconsRegular.note,
      AttachmentKind.deliveryPhoto => PhosphorIconsRegular.image,
      AttachmentKind.deliverySignature => PhosphorIconsRegular.signature,
      AttachmentKind.disputePhoto => PhosphorIconsRegular.warningOctagon,
      AttachmentKind.other => PhosphorIconsRegular.paperclip,
      AttachmentKind.unknown => PhosphorIconsRegular.file,
    };
    return StatusStyle(tone: AknTone.neutral, icon: icon, label: k.label);
  }

  static StatusStyle ownerType(AttachmentOwnerType t) {
    final icon = switch (t) {
      AttachmentOwnerType.order => PhosphorIconsFill.receipt,
      AttachmentOwnerType.paymentInstrument => PhosphorIconsRegular.money,
      AttachmentOwnerType.stationCustomer => PhosphorIconsRegular.link,
      AttachmentOwnerType.customer => PhosphorIconsRegular.buildings,
      AttachmentOwnerType.customerLead => PhosphorIconsRegular.storefront,
      AttachmentOwnerType.riskReport => PhosphorIconsRegular.presentationChart,
      AttachmentOwnerType.approvalRequest => PhosphorIconsFill.checkCircle,
      AttachmentOwnerType.customerCollateral => PhosphorIconsFill.shield,
      AttachmentOwnerType.fieldOrderForm => PhosphorIconsRegular.clipboardText,
      AttachmentOwnerType.shipment => PhosphorIconsFill.truck,
      AttachmentOwnerType.unknown => PhosphorIconsRegular.file,
    };
    return StatusStyle(tone: AknTone.neutral, icon: icon, label: t.label);
  }

  /// Saha formu barem band (`band.key` of the v2 preview). Both server
  /// vocabularies are understood: `auto / manager / senior / exception /
  /// reject` and `ok / mid / low / exception / reject / unknown`.
  static StatusStyle band(String? key, {String? label}) {
    final k = (key ?? '').trim().asciiLower;
    final (tone, icon, fallback) = switch (k) {
      'auto' ||
      'ok' => (AknTone.ok, PhosphorIconsFill.lightning, 'Otomatik onay'),
      'manager' ||
      'mid' => (AknTone.warn, PhosphorIconsFill.users, 'Yönetici onayı'),
      'unknown' => (
        AknTone.warn,
        PhosphorIconsRegular.question,
        'Kârlılık belirsiz',
      ),
      'senior' ||
      'low' => (AknTone.warn, PhosphorIconsRegular.certificate, 'Üst onay'),
      'exception' => (AknTone.warn, PhosphorIconsFill.star, 'İstisna onayı'),
      'reject' || 'out' || 'outofrange' || 'out_of_range' => (
        AknTone.danger,
        PhosphorIconsRegular.prohibit,
        'Barem dışı',
      ),
      _ => (AknTone.neutral, PhosphorIconsRegular.minus, 'Bant yok'),
    };
    final l = label?.trim();
    return StatusStyle(
      tone: tone,
      icon: icon,
      label: l == null || l.isEmpty ? fallback : l,
    );
  }

  /// Server tone keys (`facts[].tone`, `band.tone`, `severity`) → [AknTone].
  static AknTone toneFromKey(String? key) =>
      switch ((key ?? '').trim().asciiLower) {
        'ok' || 'success' || 'positive' || 'is-ok' => AknTone.ok,
        'warn' || 'warning' || 'is-warn' => AknTone.warn,
        'danger' || 'error' || 'negative' || 'is-danger' => AknTone.danger,
        'info' || 'is-info' => AknTone.info,
        'brand' || 'accent' || 'is-brand' || 'is-violet' => AknTone.brand,
        _ => AknTone.neutral,
      };

  /// Notification severity (0 info, 1 ok, 2 warn, 3 danger) → [AknTone].
  static AknTone toneFromSeverity(int? severity) => switch (severity) {
    1 => AknTone.ok,
    2 => AknTone.warn,
    3 => AknTone.danger,
    _ => AknTone.info,
  };

  /// Default icon of a tone (banners, toasts, facts).
  static IconData toneIcon(AknTone tone) => switch (tone) {
    AknTone.ok => PhosphorIconsFill.checkCircle,
    AknTone.warn => PhosphorIconsFill.warning,
    AknTone.danger => PhosphorIconsFill.warningCircle,
    AknTone.info => PhosphorIconsFill.info,
    AknTone.brand => PhosphorIconsFill.lightning,
    AknTone.neutral => PhosphorIconsRegular.circle,
  };

  /// A style for any server-described status (`{label, tone}`).
  static StatusStyle custom(String label, {String? tone, IconData? icon}) {
    final t = toneFromKey(tone);
    return StatusStyle(tone: t, icon: icon ?? toneIcon(t), label: label);
  }

  /// Style of any [CodedEnum] (dispatch on its type). Throws for an enum
  /// type this file does not know, so the completeness test catches gaps.
  static StatusStyle of(CodedEnum e) => switch (e) {
    final OrderStatus s => order(s),
    final ShipmentStatus s => shipment(s),
    final ApprovalType s => approvalType(s),
    final ApprovalStatus s => approval(s),
    final ApprovalDecision s => decision(s),
    final ApprovalSlaState s => sla(s),
    final PaymentStatus s => payment(s),
    final OrderFinanceStatus s => finance(s),
    final LeadStatus s => lead(s),
    final FieldOrderFormStatus s => fieldForm(s),
    final AttachmentKind s => attachmentKind(s),
    final AttachmentOwnerType s => ownerType(s),
    final InstrumentKind s => instrumentKind(s),
    final InstrumentStatus s => instrument(s),
    final CustomerUserRole s => customerRole(s),
    final FinanceProfileStatus s => financeProfile(s),
    final RiskClass s => risk(s),
    final CustomerOrderRequestStatus s => companyRequest(s),
    _ => throw UnsupportedError('No status style for ${e.runtimeType}'),
  };

  // ───────────── Viewer-aware lamps (design v2 §10.3) ─────────────

  /// The lamp a [viewer] sees for [status]: tone + label + StageStrip stop.
  /// The same order reads "Kararınızı bekliyor" (your move, orange) to the
  /// customer's approver and "Müşteri kararında" (ink) to the bayi.
  ///
  /// Knows [OrderStatus] (pass the order's [shipment] once one exists: an
  /// approved order then reads as its shipment), [ShipmentStatus],
  /// [CustomerOrderRequestStatus] and [ApprovalStatus] (with its [sla]).
  /// Any other status, or a value without a viewer-aware phrase, falls back
  /// to [serverLabel] (then the enum label) on the generic tone of [of].
  static StatusLamp lampFor(
    CodedEnum status,
    StatusViewer viewer, {
    String? serverLabel,
    ShipmentStatus? shipment,
    ApprovalSlaState? sla,
  }) => switch (status) {
    final OrderStatus s => orderLamp(
      s,
      viewer,
      shipment: shipment,
      serverLabel: serverLabel,
    ),
    final ShipmentStatus s => shipmentLamp(s, viewer, serverLabel: serverLabel),
    final CustomerOrderRequestStatus s => companyRequestLamp(
      s,
      viewer,
      serverLabel: serverLabel,
    ),
    final ApprovalStatus s => approvalLamp(
      s,
      viewer,
      sla: sla,
      serverLabel: serverLabel,
    ),
    _ => StatusLamp.fromStyle(of(status).withLabel(serverLabel)),
  };

  /// Order lamp (§10.3). An approved order with a [shipment] reads as the
  /// shipment ("Planlandı", "Yolda", "Teslimatı onaylayın" …).
  static StatusLamp orderLamp(
    OrderStatus s,
    StatusViewer viewer, {
    ShipmentStatus? shipment,
    String? serverLabel,
  }) {
    if (shipment != null &&
        shipment != ShipmentStatus.unknown &&
        (s == OrderStatus.approved || s == OrderStatus.completed)) {
      if (s == OrderStatus.approved || shipment != ShipmentStatus.accepted) {
        return shipmentLamp(shipment, viewer);
      }
    }
    final icon = order(s).icon;
    final customer = viewer.isCustomer;
    StatusLamp lamp(
      AknTone tone,
      String label,
      AknStage stage, {
      bool complete = false,
      bool problem = false,
      bool solid = false,
    }) => StatusLamp(
      tone: tone,
      label: label,
      icon: icon,
      stage: stage,
      complete: complete,
      problem: problem,
      solid: solid,
    );
    return switch (s) {
      OrderStatus.created => lamp(
        AknTone.info,
        _fallback(serverLabel, s),
        AknStage.talep,
      ),
      OrderStatus.awaitingQuote =>
        !customer && viewer.canQuote
            ? lamp(AknTone.brand, 'Teklif verin', AknStage.teklif)
            : lamp(AknTone.info, 'Teklif bekleniyor', AknStage.teklif),
      OrderStatus.awaitingApproval =>
        customer
            ? viewer.canDecide
                  ? lamp(AknTone.brand, 'Kararınızı bekliyor', AknStage.karar)
                  : lamp(AknTone.info, 'Onay bekleniyor', AknStage.karar)
            : lamp(AknTone.info, 'Müşteri kararında', AknStage.karar),
      OrderStatus.revisionRequested =>
        !customer && viewer.canQuote
            ? lamp(AknTone.brand, 'Revize istendi', AknStage.teklif)
            : lamp(AknTone.info, 'Revize istendi', AknStage.teklif),
      OrderStatus.approved =>
        !customer && viewer.canPlan
            ? lamp(AknTone.brand, 'Sevkiyat planlayın', AknStage.plan)
            : lamp(AknTone.info, 'Sevkiyat planlanıyor', AknStage.plan),
      OrderStatus.completed => lamp(
        AknTone.ok,
        'Tamamlandı',
        AknStage.teslim,
        complete: true,
        solid: true,
      ),
      OrderStatus.rejected => lamp(
        AknTone.danger,
        'Reddedildi',
        AknStage.karar,
        problem: true,
      ),
      OrderStatus.expired => lamp(
        AknTone.neutral,
        'Süresi doldu',
        AknStage.karar,
      ),
      OrderStatus.unknown => StatusLamp.fromStyle(
        order(s).withLabel(serverLabel),
      ),
    };
  }

  /// Shipment lamp (§10.3).
  static StatusLamp shipmentLamp(
    ShipmentStatus s,
    StatusViewer viewer, {
    String? serverLabel,
  }) {
    final icon = shipment(s).icon;
    StatusLamp lamp(
      AknTone tone,
      String label,
      AknStage stage, {
      bool complete = false,
      bool problem = false,
    }) => StatusLamp(
      tone: tone,
      label: label,
      icon: icon,
      stage: stage,
      complete: complete,
      problem: problem,
    );
    return switch (s) {
      ShipmentStatus.planned => lamp(AknTone.info, 'Planlandı', AknStage.plan),
      ShipmentStatus.inTransit => lamp(AknTone.info, 'Yolda', AknStage.yolda),
      ShipmentStatus.reported =>
        viewer.isCustomer && viewer.canDecide
            ? lamp(AknTone.brand, 'Teslimatı onaylayın', AknStage.teslim)
            : lamp(AknTone.info, 'Kabul bekliyor', AknStage.teslim),
      ShipmentStatus.accepted => lamp(
        AknTone.ok,
        'Teslim alındı',
        AknStage.teslim,
        complete: true,
      ),
      ShipmentStatus.disputed => lamp(
        AknTone.danger,
        'İtirazlı',
        AknStage.teslim,
        problem: true,
      ),
      ShipmentStatus.cancelled => lamp(
        AknTone.neutral,
        'İptal',
        AknStage.plan,
        problem: true,
      ),
      ShipmentStatus.unknown => StatusLamp.fromStyle(
        shipment(s).withLabel(serverLabel),
      ),
    };
  }

  /// Company order request lamp (§10.3): "Onayınızı bekliyor" for the
  /// customer's approver, "Şirket onayında" for the requester.
  static StatusLamp companyRequestLamp(
    CustomerOrderRequestStatus s,
    StatusViewer viewer, {
    String? serverLabel,
  }) {
    final icon = companyRequest(s).icon;
    return switch (s) {
      CustomerOrderRequestStatus.pending =>
        viewer.canDecide
            ? StatusLamp(
                tone: AknTone.brand,
                label: 'Onayınızı bekliyor',
                icon: icon,
                stage: AknStage.onay,
              )
            : StatusLamp(
                tone: AknTone.info,
                label: 'Şirket onayında',
                icon: icon,
                stage: AknStage.onay,
              ),
      CustomerOrderRequestStatus.approved => StatusLamp(
        tone: AknTone.ok,
        label: _fallback(serverLabel, s),
        icon: icon,
        stage: AknStage.teklif,
      ),
      CustomerOrderRequestStatus.rejected => StatusLamp(
        tone: AknTone.danger,
        label: 'Reddedildi',
        icon: icon,
        stage: AknStage.onay,
        problem: true,
      ),
      CustomerOrderRequestStatus.cancelled => StatusLamp(
        tone: AknTone.neutral,
        label: _fallback(serverLabel, s),
        icon: icon,
        stage: AknStage.onay,
        problem: true,
      ),
      CustomerOrderRequestStatus.unknown => StatusLamp.fromStyle(
        companyRequest(s).withLabel(serverLabel),
      ),
    };
  }

  /// Approval-center lamp (§7.13): "Onayınızı bekliyor" (your move) when the
  /// viewer decides, else "Onay bekleniyor"; an overdue [sla] turns it into
  /// the danger lamp "Süresi geçti".
  static StatusLamp approvalLamp(
    ApprovalStatus s,
    StatusViewer viewer, {
    ApprovalSlaState? sla,
    String? serverLabel,
  }) {
    final icon = approval(s).icon;
    if (s == ApprovalStatus.pending) {
      if (sla == ApprovalSlaState.overdue) {
        return StatusLamp(
          tone: AknTone.danger,
          label: 'Süresi geçti',
          icon: AknStatus.sla(ApprovalSlaState.overdue).icon,
        );
      }
      return viewer.canDecide
          ? StatusLamp(
              tone: AknTone.brand,
              label: 'Onayınızı bekliyor',
              icon: icon,
            )
          : StatusLamp(
              tone: AknTone.info,
              label: 'Onay bekleniyor',
              icon: icon,
            );
    }
    return StatusLamp.fromStyle(approval(s).withLabel(serverLabel));
  }

  static String _fallback(String? serverLabel, CodedEnum e) {
    final l = serverLabel?.trim();
    return l == null || l.isEmpty ? e.label : l;
  }
}

extension OrderStatusStyleX on OrderStatus {
  StatusStyle get statusStyle => AknStatus.order(this);
}

extension ShipmentStatusStyleX on ShipmentStatus {
  StatusStyle get statusStyle => AknStatus.shipment(this);
}

extension ApprovalStatusStyleX on ApprovalStatus {
  StatusStyle get statusStyle => AknStatus.approval(this);
}

extension ApprovalSlaStyleX on ApprovalSlaState {
  StatusStyle get statusStyle => AknStatus.sla(this);
}

extension ApprovalTypeStyleX on ApprovalType {
  StatusStyle get statusStyle => AknStatus.approvalType(this);
}

extension ApprovalDecisionStyleX on ApprovalDecision {
  StatusStyle get statusStyle => AknStatus.decision(this);
}

extension PaymentStatusStyleX on PaymentStatus {
  StatusStyle get statusStyle => AknStatus.payment(this);
}

extension OrderFinanceStatusStyleX on OrderFinanceStatus {
  StatusStyle get statusStyle => AknStatus.finance(this);
}

extension FinanceProfileStatusStyleX on FinanceProfileStatus {
  StatusStyle get statusStyle => AknStatus.financeProfile(this);
}

extension LeadStatusStyleX on LeadStatus {
  StatusStyle get statusStyle => AknStatus.lead(this);
}

extension FieldOrderFormStatusStyleX on FieldOrderFormStatus {
  StatusStyle get statusStyle => AknStatus.fieldForm(this);
}

extension InstrumentStatusStyleX on InstrumentStatus {
  StatusStyle get statusStyle => AknStatus.instrument(this);
}

extension InstrumentKindStyleX on InstrumentKind {
  StatusStyle get statusStyle => AknStatus.instrumentKind(this);
}

extension CompanyRequestStatusStyleX on CustomerOrderRequestStatus {
  StatusStyle get statusStyle => AknStatus.companyRequest(this);
}

extension CustomerUserRoleStyleX on CustomerUserRole {
  StatusStyle get statusStyle => AknStatus.customerRole(this);
}

extension RiskClassStyleX on RiskClass {
  StatusStyle get statusStyle => AknStatus.risk(this);
}

extension AttachmentKindStyleX on AttachmentKind {
  StatusStyle get statusStyle => AknStatus.attachmentKind(this);
}

extension AttachmentOwnerTypeStyleX on AttachmentOwnerType {
  StatusStyle get statusStyle => AknStatus.ownerType(this);
}

/// Which side of the market a [StatusViewer] sits on.
enum StatusSide { customer, bayi }

/// Who is looking at a status, and what they may do (§10.3): the pill says
/// "your move" (orange) only to the person who can act.
@immutable
class StatusViewer {
  /// A customer user. [canDecide]: company admin / approver (decides quotes,
  /// accepts deliveries, approves company requests); false for requesters.
  const StatusViewer.customer({this.canDecide = true})
    : side = StatusSide.customer,
      canQuote = false,
      canPlan = false;

  /// A bayi user. [canQuote]: owner, manager, order desk; [canPlan]: owner,
  /// manager, dispatch; [canDecide]: approvers in the approval center
  /// (finance, sales manager …).
  const StatusViewer.bayi({
    this.canQuote = false,
    this.canPlan = false,
    this.canDecide = false,
  }) : side = StatusSide.bayi;

  final StatusSide side;
  final bool canDecide;
  final bool canQuote;
  final bool canPlan;

  bool get isCustomer => side == StatusSide.customer;
  bool get isBayi => side == StatusSide.bayi;

  @override
  bool operator ==(Object other) =>
      other is StatusViewer &&
      other.side == side &&
      other.canDecide == canDecide &&
      other.canQuote == canQuote &&
      other.canPlan == canPlan;

  @override
  int get hashCode => Object.hash(side, canDecide, canQuote, canPlan);
}

/// The stops of an order's journey on the StageStrip (§6.14): Talep, Onay,
/// Teklif, Karar, Plan, Yolda, Teslim. "Onay" (company approval) shows only
/// when the customer uses it.
enum AknStage {
  talep('Talep'),
  onay('Onay'),
  teklif('Teklif'),
  karar('Karar'),
  plan('Plan'),
  yolda('Yolda'),
  teslim('Teslim');

  const AknStage(this.label);

  final String label;

  /// The stops shown on a strip, with or without company approval.
  static List<AknStage> stops({bool companyApproval = false}) => [
    for (final s in values)
      if (s != onay || companyApproval) s,
  ];

  /// Index of this stop on the strip, or -1 when it is not shown ("Onay"
  /// without company approval).
  int indexIn({bool companyApproval = false}) =>
      stops(companyApproval: companyApproval).indexOf(this);
}

/// A viewer-aware status (§10.3): what the lamp says, in which tone, and
/// where the order stands on the StageStrip.
@immutable
class StatusLamp {
  const StatusLamp({
    required this.tone,
    required this.label,
    required this.icon,
    this.stage,
    this.complete = false,
    this.problem = false,
    this.solid = false,
  });

  /// A lamp from a generic [StatusStyle] (no stage).
  factory StatusLamp.fromStyle(StatusStyle style) => StatusLamp(
    tone: style.tone,
    label: style.label,
    icon: style.icon,
    solid: style.solid,
  );

  final AknTone tone;
  final String label;

  /// Kept for semantics (the pill draws a dot).
  final IconData icon;

  /// The current StageStrip stop, when the status belongs to the order
  /// journey.
  final AknStage? stage;

  /// Every stop is done (Tamamlandı, Teslim alındı).
  final bool complete;

  /// The journey stopped at [stage] (red, iptal, itiraz): the strip draws a
  /// danger disc there and the line ends.
  final bool problem;

  /// Terminal success: label 600.
  final bool solid;

  /// Orange pill: the viewer's move.
  bool get yourMove => tone == AknTone.brand;

  /// The generic style (for `StatusChip.style`).
  StatusStyle get style =>
      StatusStyle(tone: tone, icon: icon, label: label, solid: solid);

  /// [stage]'s index on the strip (null without a stage; -1 when the stop is
  /// hidden).
  int? stageIndex({bool companyApproval = false}) =>
      stage?.indexIn(companyApproval: companyApproval);

  @override
  bool operator ==(Object other) =>
      other is StatusLamp &&
      other.tone == tone &&
      other.label == label &&
      other.icon == icon &&
      other.stage == stage &&
      other.complete == complete &&
      other.problem == problem &&
      other.solid == solid;

  @override
  int get hashCode =>
      Object.hash(tone, label, icon, stage, complete, problem, solid);

  @override
  String toString() =>
      'StatusLamp($label, $tone${stage == null ? '' : ', ${stage!.name}'})';
}

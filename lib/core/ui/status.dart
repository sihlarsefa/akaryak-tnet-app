import 'package:flutter/material.dart';

import '../models/enums.dart';
import '../utils/turkish_text.dart';
import 'tokens.dart';

/// Tone, icon and Turkish label of one status value. Status is never shown by
/// colour alone: chips always render the icon and the label (spec C.7).
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

  /// Filled chip for terminal successes (Tamamlandı, Dönüştürüldü).
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

/// Maps every server enum (`core/models/enums.dart`) to a [StatusStyle]
/// following the tone table of spec C.5:
///
/// | | ok | warn | danger | info | neutral / other |
/// |---|---|---|---|---|---|
/// | Order | Approved; Completed (solid) | AwaitingApproval | Rejected | AwaitingQuote, RevisionRequested | Expired |
/// | Shipment | Accepted | Reported | Disputed | Planned | InTransit = brand; Cancelled |
/// | Approval | Approved | Pending; SLA DueSoon | Rejected; SLA Overdue | InfoRequested | Cancelled |
/// | Payment | Collected | Pending | Bounced | DocumentUploaded | Refunded, Cancelled, None |
/// | Finance | Approved, Conditional | Pending | Rejected | InfoRequested | |
/// | Lead | Approved; Converted (solid) | InfoRequested | Rejected | Submitted, InReview | Draft, Cancelled |
/// | Field form | Approved; Converted (solid) | PendingApproval | Rejected | | Draft, Cancelled |
/// | Barem band | auto | manager | out of range | | senior / exception = brand |
abstract final class AknStatus {
  static const _unknownIcon = Icons.help_outline_rounded;

  static StatusStyle _s(
    AknTone tone,
    IconData icon,
    CodedEnum e, {
    bool solid = false,
  }) => StatusStyle(tone: tone, icon: icon, label: e.label, solid: solid);

  static StatusStyle order(OrderStatus s) => switch (s) {
    OrderStatus.created => _s(AknTone.neutral, Icons.receipt_long_rounded, s),
    OrderStatus.awaitingQuote => _s(
      AknTone.info,
      Icons.request_quote_rounded,
      s,
    ),
    OrderStatus.awaitingApproval => _s(
      AknTone.warn,
      Icons.hourglass_top_rounded,
      s,
    ),
    OrderStatus.approved => _s(AknTone.ok, Icons.check_circle_rounded, s),
    OrderStatus.rejected => _s(AknTone.danger, Icons.cancel_rounded, s),
    OrderStatus.revisionRequested => _s(AknTone.info, Icons.edit_rounded, s),
    OrderStatus.expired => _s(AknTone.neutral, Icons.timer_off_rounded, s),
    OrderStatus.completed => _s(
      AknTone.ok,
      Icons.task_alt_rounded,
      s,
      solid: true,
    ),
    OrderStatus.unknown => _s(AknTone.neutral, _unknownIcon, s),
  };

  static StatusStyle shipment(ShipmentStatus s) => switch (s) {
    ShipmentStatus.planned => _s(AknTone.info, Icons.event_rounded, s),
    ShipmentStatus.inTransit => _s(
      AknTone.brand,
      Icons.local_shipping_rounded,
      s,
    ),
    ShipmentStatus.reported => _s(AknTone.warn, Icons.fact_check_rounded, s),
    ShipmentStatus.accepted => _s(AknTone.ok, Icons.verified_rounded, s),
    ShipmentStatus.disputed => _s(AknTone.danger, Icons.report_rounded, s),
    ShipmentStatus.cancelled => _s(AknTone.neutral, Icons.block_rounded, s),
    ShipmentStatus.unknown => _s(AknTone.neutral, _unknownIcon, s),
  };

  static StatusStyle approval(ApprovalStatus s) => switch (s) {
    ApprovalStatus.pending => _s(AknTone.warn, Icons.hourglass_top_rounded, s),
    ApprovalStatus.approved => _s(AknTone.ok, Icons.check_circle_rounded, s),
    ApprovalStatus.rejected => _s(AknTone.danger, Icons.cancel_rounded, s),
    ApprovalStatus.cancelled => _s(AknTone.neutral, Icons.block_rounded, s),
    ApprovalStatus.infoRequested => _s(
      AknTone.info,
      Icons.contact_support_rounded,
      s,
    ),
    ApprovalStatus.unknown => _s(AknTone.neutral, _unknownIcon, s),
  };

  static StatusStyle sla(ApprovalSlaState s) => switch (s) {
    ApprovalSlaState.none => _s(AknTone.neutral, Icons.schedule_rounded, s),
    ApprovalSlaState.onTime => _s(AknTone.neutral, Icons.schedule_rounded, s),
    ApprovalSlaState.dueSoon => _s(AknTone.warn, Icons.alarm_rounded, s),
    ApprovalSlaState.overdue => _s(AknTone.danger, Icons.alarm_off_rounded, s),
    ApprovalSlaState.unknown => _s(AknTone.neutral, _unknownIcon, s),
  };

  static StatusStyle decision(ApprovalDecision d) => switch (d) {
    ApprovalDecision.approve => _s(AknTone.ok, Icons.check_circle_rounded, d),
    ApprovalDecision.conditionalApprove => _s(
      AknTone.ok,
      Icons.rule_rounded,
      d,
    ),
    ApprovalDecision.requestInfo => _s(
      AknTone.info,
      Icons.contact_support_rounded,
      d,
    ),
    ApprovalDecision.reject => _s(AknTone.danger, Icons.cancel_rounded, d),
    ApprovalDecision.unknown => _s(AknTone.neutral, _unknownIcon, d),
  };

  /// Approval types are categories, not states: neutral tone, distinct icon.
  static StatusStyle approvalType(ApprovalType t) {
    final icon = switch (t) {
      ApprovalType.fieldOrderProfit => Icons.trending_up_rounded,
      ApprovalType.limitChange => Icons.speed_rounded,
      ApprovalType.companyOrderRequest => Icons.fact_check_rounded,
      ApprovalType.orderFinance => Icons.account_balance_rounded,
      ApprovalType.fieldFormFinance => Icons.assignment_rounded,
      ApprovalType.customerOnboarding => Icons.person_add_alt_1_rounded,
      ApprovalType.leadFinance => Icons.how_to_reg_rounded,
      ApprovalType.unknown => Icons.task_alt_rounded,
    };
    return StatusStyle(tone: AknTone.neutral, icon: icon, label: t.shortLabel);
  }

  static StatusStyle payment(PaymentStatus s) => switch (s) {
    PaymentStatus.none => _s(AknTone.neutral, Icons.remove_circle_outline, s),
    PaymentStatus.pending => _s(AknTone.warn, Icons.schedule_rounded, s),
    PaymentStatus.documentUploaded => _s(
      AknTone.info,
      Icons.upload_file_rounded,
      s,
    ),
    PaymentStatus.collected => _s(AknTone.ok, Icons.paid_rounded, s),
    PaymentStatus.bounced => _s(AknTone.danger, Icons.money_off_rounded, s),
    PaymentStatus.refunded => _s(AknTone.neutral, Icons.undo_rounded, s),
    PaymentStatus.cancelled => _s(AknTone.neutral, Icons.block_rounded, s),
    PaymentStatus.unknown => _s(AknTone.neutral, _unknownIcon, s),
  };

  static StatusStyle finance(OrderFinanceStatus s) => switch (s) {
    OrderFinanceStatus.notRequired => _s(
      AknTone.neutral,
      Icons.remove_circle_outline,
      s,
    ),
    OrderFinanceStatus.pending => _s(
      AknTone.warn,
      Icons.account_balance_rounded,
      s,
    ),
    OrderFinanceStatus.approved => _s(
      AknTone.ok,
      Icons.verified_user_rounded,
      s,
    ),
    OrderFinanceStatus.conditionallyApproved => _s(
      AknTone.ok,
      Icons.rule_rounded,
      s,
    ),
    OrderFinanceStatus.infoRequested => _s(
      AknTone.info,
      Icons.contact_support_rounded,
      s,
    ),
    OrderFinanceStatus.rejected => _s(AknTone.danger, Icons.gpp_bad_rounded, s),
    OrderFinanceStatus.unknown => _s(AknTone.neutral, _unknownIcon, s),
  };

  static StatusStyle financeProfile(FinanceProfileStatus s) => switch (s) {
    FinanceProfileStatus.pending => _s(
      AknTone.warn,
      Icons.hourglass_top_rounded,
      s,
    ),
    FinanceProfileStatus.approved => _s(
      AknTone.ok,
      Icons.verified_user_rounded,
      s,
    ),
    FinanceProfileStatus.conditional => _s(AknTone.ok, Icons.rule_rounded, s),
    FinanceProfileStatus.infoRequested => _s(
      AknTone.info,
      Icons.contact_support_rounded,
      s,
    ),
    FinanceProfileStatus.rejected => _s(
      AknTone.danger,
      Icons.gpp_bad_rounded,
      s,
    ),
    FinanceProfileStatus.suspended => _s(
      AknTone.danger,
      Icons.pause_circle_rounded,
      s,
    ),
    FinanceProfileStatus.unknown => _s(AknTone.neutral, _unknownIcon, s),
  };

  static StatusStyle lead(LeadStatus s) => switch (s) {
    LeadStatus.draft => _s(AknTone.neutral, Icons.edit_note_rounded, s),
    LeadStatus.submitted => _s(AknTone.info, Icons.send_rounded, s),
    LeadStatus.inReview => _s(AknTone.info, Icons.manage_search_rounded, s),
    LeadStatus.infoRequested => _s(
      AknTone.warn,
      Icons.contact_support_rounded,
      s,
    ),
    LeadStatus.approved => _s(AknTone.ok, Icons.check_circle_rounded, s),
    LeadStatus.converted => _s(
      AknTone.ok,
      Icons.how_to_reg_rounded,
      s,
      solid: true,
    ),
    LeadStatus.rejected => _s(AknTone.danger, Icons.cancel_rounded, s),
    LeadStatus.cancelled => _s(AknTone.neutral, Icons.block_rounded, s),
    LeadStatus.unknown => _s(AknTone.neutral, _unknownIcon, s),
  };

  static StatusStyle fieldForm(FieldOrderFormStatus s) => switch (s) {
    FieldOrderFormStatus.draft => _s(
      AknTone.neutral,
      Icons.edit_note_rounded,
      s,
    ),
    FieldOrderFormStatus.pendingApproval => _s(
      AknTone.warn,
      Icons.hourglass_top_rounded,
      s,
    ),
    FieldOrderFormStatus.approved => _s(
      AknTone.ok,
      Icons.check_circle_rounded,
      s,
    ),
    FieldOrderFormStatus.rejected => _s(
      AknTone.danger,
      Icons.cancel_rounded,
      s,
    ),
    FieldOrderFormStatus.converted => _s(
      AknTone.ok,
      Icons.receipt_long_rounded,
      s,
      solid: true,
    ),
    FieldOrderFormStatus.cancelled => _s(
      AknTone.neutral,
      Icons.block_rounded,
      s,
    ),
    FieldOrderFormStatus.unknown => _s(AknTone.neutral, _unknownIcon, s),
  };

  static StatusStyle instrument(InstrumentStatus s) => switch (s) {
    InstrumentStatus.received => _s(
      AknTone.info,
      Icons.move_to_inbox_rounded,
      s,
    ),
    InstrumentStatus.inPortfolio => _s(
      AknTone.neutral,
      Icons.folder_rounded,
      s,
    ),
    InstrumentStatus.deposited => _s(
      AknTone.info,
      Icons.account_balance_rounded,
      s,
    ),
    InstrumentStatus.collected => _s(AknTone.ok, Icons.paid_rounded, s),
    InstrumentStatus.bounced => _s(AknTone.danger, Icons.money_off_rounded, s),
    InstrumentStatus.returned => _s(AknTone.neutral, Icons.undo_rounded, s),
    InstrumentStatus.protested => _s(AknTone.danger, Icons.gavel_rounded, s),
    InstrumentStatus.unknown => _s(AknTone.neutral, _unknownIcon, s),
  };

  static StatusStyle instrumentKind(InstrumentKind k) => switch (k) {
    InstrumentKind.cheque => _s(AknTone.neutral, Icons.money_rounded, k),
    InstrumentKind.promissoryNote => _s(
      AknTone.neutral,
      Icons.description_rounded,
      k,
    ),
    InstrumentKind.letterOfGuarantee => _s(
      AknTone.neutral,
      Icons.verified_rounded,
      k,
    ),
    InstrumentKind.unknown => _s(AknTone.neutral, _unknownIcon, k),
  };

  static StatusStyle companyRequest(CustomerOrderRequestStatus s) =>
      switch (s) {
        CustomerOrderRequestStatus.pending => _s(
          AknTone.warn,
          Icons.hourglass_top_rounded,
          s,
        ),
        CustomerOrderRequestStatus.approved => _s(
          AknTone.ok,
          Icons.check_circle_rounded,
          s,
        ),
        CustomerOrderRequestStatus.rejected => _s(
          AknTone.danger,
          Icons.cancel_rounded,
          s,
        ),
        CustomerOrderRequestStatus.cancelled => _s(
          AknTone.neutral,
          Icons.undo_rounded,
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
      Icons.person_outline_rounded,
      r,
    ),
    CustomerUserRole.approver => _s(
      AknTone.neutral,
      Icons.how_to_reg_rounded,
      r,
    ),
    CustomerUserRole.admin => _s(
      AknTone.neutral,
      Icons.admin_panel_settings_rounded,
      r,
    ),
    CustomerUserRole.unknown => _s(AknTone.neutral, _unknownIcon, r),
  };

  static StatusStyle risk(RiskClass r) => switch (r) {
    RiskClass.none => _s(AknTone.neutral, Icons.shield_outlined, r),
    RiskClass.a => _s(AknTone.ok, Icons.shield_rounded, r),
    RiskClass.b => _s(AknTone.info, Icons.shield_rounded, r),
    RiskClass.c => _s(AknTone.warn, Icons.shield_rounded, r),
    RiskClass.d => _s(AknTone.danger, Icons.gpp_maybe_rounded, r),
    RiskClass.unknown => _s(AknTone.neutral, _unknownIcon, r),
  };

  static StatusStyle attachmentKind(AttachmentKind k) {
    final icon = switch (k) {
      AttachmentKind.chequeImage => Icons.money_rounded,
      AttachmentKind.promissoryNoteImage => Icons.description_rounded,
      AttachmentKind.transferReceipt => Icons.receipt_long_rounded,
      AttachmentKind.posSlip => Icons.point_of_sale_rounded,
      AttachmentKind.letterOfGuarantee => Icons.verified_rounded,
      AttachmentKind.dbsContract => Icons.handshake_rounded,
      AttachmentKind.taxPlate => Icons.badge_rounded,
      AttachmentKind.signatureCircular => Icons.draw_rounded,
      AttachmentKind.tradeRegistryGazette => Icons.newspaper_rounded,
      AttachmentKind.activityCertificate => Icons.workspace_premium_rounded,
      AttachmentKind.visitPhoto => Icons.photo_camera_rounded,
      AttachmentKind.riskReportPdf => Icons.picture_as_pdf_rounded,
      AttachmentKind.financeNote => Icons.sticky_note_2_rounded,
      AttachmentKind.deliveryPhoto => Icons.photo_camera_back_rounded,
      AttachmentKind.deliverySignature => Icons.gesture_rounded,
      AttachmentKind.disputePhoto => Icons.report_gmailerrorred_rounded,
      AttachmentKind.other => Icons.attach_file_rounded,
      AttachmentKind.unknown => Icons.insert_drive_file_rounded,
    };
    return StatusStyle(tone: AknTone.neutral, icon: icon, label: k.label);
  }

  static StatusStyle ownerType(AttachmentOwnerType t) {
    final icon = switch (t) {
      AttachmentOwnerType.order => Icons.receipt_long_rounded,
      AttachmentOwnerType.paymentInstrument => Icons.money_rounded,
      AttachmentOwnerType.stationCustomer => Icons.link_rounded,
      AttachmentOwnerType.customer => Icons.apartment_rounded,
      AttachmentOwnerType.customerLead => Icons.storefront_rounded,
      AttachmentOwnerType.riskReport => Icons.assessment_rounded,
      AttachmentOwnerType.approvalRequest => Icons.task_alt_rounded,
      AttachmentOwnerType.customerCollateral => Icons.shield_rounded,
      AttachmentOwnerType.fieldOrderForm => Icons.assignment_rounded,
      AttachmentOwnerType.shipment => Icons.local_shipping_rounded,
      AttachmentOwnerType.unknown => Icons.insert_drive_file_rounded,
    };
    return StatusStyle(tone: AknTone.neutral, icon: icon, label: t.label);
  }

  /// Saha formu barem band (`band.key` of the v2 preview). Both server
  /// vocabularies are understood: `auto / manager / senior / exception /
  /// reject` and `ok / mid / low / exception / reject / unknown`.
  static StatusStyle band(String? key, {String? label}) {
    final k = (key ?? '').trim().asciiLower;
    final (tone, icon, fallback) = switch (k) {
      'auto' || 'ok' => (AknTone.ok, Icons.bolt_rounded, 'Otomatik onay'),
      'manager' || 'mid' => (
        AknTone.warn,
        Icons.supervisor_account_rounded,
        'Yönetici onayı',
      ),
      'unknown' => (
        AknTone.warn,
        Icons.help_outline_rounded,
        'Kârlılık belirsiz',
      ),
      'senior' ||
      'low' => (AknTone.brand, Icons.workspace_premium_rounded, 'Üst onay'),
      'exception' => (AknTone.brand, Icons.star_rounded, 'İstisna onayı'),
      'reject' ||
      'out' ||
      'outofrange' ||
      'out_of_range' => (AknTone.danger, Icons.block_rounded, 'Barem dışı'),
      _ => (AknTone.neutral, Icons.remove_rounded, 'Bant yok'),
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
    AknTone.ok => Icons.check_circle_rounded,
    AknTone.warn => Icons.warning_amber_rounded,
    AknTone.danger => Icons.error_rounded,
    AknTone.info => Icons.info_rounded,
    AknTone.brand => Icons.bolt_rounded,
    AknTone.neutral => Icons.circle_outlined,
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

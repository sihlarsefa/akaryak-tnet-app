import 'package:flutter/material.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../data/approval_models.dart';

/// Satırın durum görünümü. Cari tarafında bayinin iç süreci "Bayi değerlendirmesi" olarak görünür.
StatusStyle approvalStatusStyle(
  ApprovalRow row, {
  required bool customerSide,
  bool canProvideInfo = false,
}) {
  if (customerSide && row.type != ApprovalType.companyOrderRequest) {
    switch (row.status) {
      case ApprovalStatus.pending:
        return const StatusStyle(
          tone: AknTone.warn,
          icon: Icons.hourglass_top_rounded,
          label: 'Bayi değerlendirmesi',
        );
      case ApprovalStatus.infoRequested:
        return StatusStyle(
          tone: canProvideInfo ? AknTone.brand : AknTone.info,
          icon: Icons.contact_support_rounded,
          label: canProvideInfo
              ? 'Yanıtınız bekleniyor'
              : 'Ek bilgi bekleniyor',
        );
      default:
        break;
    }
  }
  return AknStatus.approval(row.status).withLabel(row.statusLabel);
}

/// SLA çipi (yalnızca bayi / merkez görünümünde, açık taleplerde).
StatusStyle? slaStyle(ApprovalRow row) {
  if (!row.status.isOpen) return null;
  return switch (row.slaState) {
    ApprovalSlaState.overdue => AknStatus.sla(ApprovalSlaState.overdue),
    ApprovalSlaState.dueSoon => AknStatus.sla(ApprovalSlaState.dueSoon),
    _ => null,
  };
}

/// Satırın izleyiciye göre lambası (tasarım v2 §7.13): bekleyen talep, karar veren için "Onayınızı
/// bekliyor" (turuncu, sıra sizde), diğerleri için "Onay bekleniyor"; süresi geçen talep kırmızı
/// "Süresi geçti". Cari tarafında bayinin iç süreci tek lamba ("Bayi değerlendirmesi").
StatusLamp approvalRowLamp(
  ApprovalRow row, {
  required bool customerSide,
  bool canProvideInfo = false,
}) {
  final internal = customerSide && row.type != ApprovalType.companyOrderRequest;
  if (internal || row.status != ApprovalStatus.pending) {
    return StatusLamp.fromStyle(
      approvalStatusStyle(
        row,
        customerSide: customerSide,
        canProvideInfo: canProvideInfo,
      ),
    );
  }
  return AknStatus.approvalLamp(
    row.status,
    customerSide
        ? StatusViewer.customer(canDecide: row.canDecide)
        : StatusViewer.bayi(canDecide: row.canDecide),
    sla: row.slaState,
    serverLabel: row.statusLabel,
  );
}

/// Sunucu özetindeki " · " ayırıcılarını v2 yazımına çevirir (", ").
String plainSummary(String? s) => (s ?? '').replaceAll(' · ', ', ').trim();

/// Onaylarım satırı (tasarım v2 §7.13 defter satırı):
///
/// ```
/// Sipariş finans: Marmara İnşaat Taahhüt Ltd. Şti.   1.052.500,00 ₺
/// SIP-20261021-12005, Çek, 60 gün vade, …                3 sa önce
/// ● Onayınızı bekliyor                          ⏱ 1 sa 20 dk kaldı
/// Talep: Deniz Koç, kademe 1/2
/// ```
///
/// Başlık onaylanacak şeyi söyler (tür: karşı taraf); sağda tutar (ya da litre) ve zaman; durum
/// satırında izleyiciye göre lamba ve son tarih geri sayımı. Renk tek başına değil: lamba metni de
/// söyler.
class ApprovalCard extends StatelessWidget {
  const ApprovalCard({
    super.key,
    required this.row,
    required this.onTap,
    required this.customerSide,
  });

  final ApprovalRow row;
  final VoidCallback onTap;

  /// Kullanıcı cari mi (bayi iç ayrıntısı gösterilmez).
  final bool customerSide;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final internal =
        customerSide && row.type != ApprovalType.companyOrderRequest;
    // Cariye yöneltilen ek bilgi isteği: yanıtı cari verir (listede eylem bekleyen satır).
    final needsReply =
        internal &&
        row.status == ApprovalStatus.infoRequested &&
        (row.type == ApprovalType.orderFinance ||
            row.type == ApprovalType.customerOnboarding);
    final lamp = approvalRowLamp(
      row,
      customerSide: customerSide,
      canProvideInfo: needsReply,
    );
    // Karşı taraf: cari için bayi (şirket içi talepte talep eden); bayi için cari. Cari kaydı olmayan
    // taleplerde (ön kayıt, yeni cari) özetin ilk parçası firmanın adıdır.
    final summaryParts = (row.summary ?? '').split(' · ');
    final summaryHead = summaryParts.first.trim();
    final fromSummary =
        !customerSide &&
        row.customerTitle == null &&
        summaryHead.isNotEmpty &&
        summaryParts.length > 1;
    final counterpart = customerSide
        ? (row.type == ApprovalType.companyOrderRequest
              ? row.requestedByName
              : row.stationTitle)
        : (row.customerTitle ?? (fromSummary ? summaryHead : null));
    final headline = counterpart ?? row.requestedByName ?? row.title;
    final detailLine = fromSummary
        ? summaryParts.skip(1).join(', ')
        : plainSummary(row.summary);
    final number = row.subjectNumber;
    final amount = row.amount;
    final when = TurkishText.lower(Fmt.relative(row.createdAt));
    final levels = !internal && row.hasLevels && row.status.isOpen
        ? 'kademe ${row.currentLevelNo}/${row.levelCount}'
        : null;
    final open = row.status.isOpen;
    final due = row.dueAt;
    final countdown =
        !internal &&
        open &&
        due != null &&
        row.slaState != ApprovalSlaState.overdue &&
        due.isAfter(DateTime.now().toUtc());
    final requester = !customerSide && row.requestedByName != null
        ? 'Talep: ${row.requestedByName}'
        : null;
    final note = [?requester, ?levels].join(', ');
    final subtitle = [
      ?number,
      if (!internal && detailLine.isNotEmpty) detailLine,
    ].join(', ');

    final semantic = [
      row.displayTypeLabel,
      ?number,
      headline,
      lamp.label,
      ?levels,
      if (amount != null) Fmt.money(amount),
      when,
    ].join(', ');

    return Semantics(
      button: true,
      label: semantic,
      excludeSemantics: true,
      onTap: onTap,
      child: AknListTile(
        title: '${row.displayTypeLabel}: $headline',
        subtitle: subtitle.isEmpty ? null : subtitle,
        subtitleMaxLines: 2,
        amount: amount != null
            ? Fmt.money(amount)
            : (row.liters != null ? Fmt.liters(row.liters) : null),
        amountMeta: amount != null || row.liters != null ? when : null,
        meta: amount == null && row.liters == null ? when : null,
        status: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AknStatusLine(
              lamp: AknLamp.status(lamp),
              trailing: countdown
                  ? CountdownBadge(
                      deadline: due,
                      yourMove: lamp.yourMove,
                      subject: 'Onay süresi',
                    )
                  : null,
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(note, style: t.label.copyWith(color: c.dim)),
            ],
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../data/approval_models.dart';
import '../../shared/layout.dart';

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
          tone: AknTone.info,
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

/// Onaylarım satırı: tür ve numara, karşı taraf, sunucu özeti, tutar, durum / SLA / kademe çipleri.
/// Kararımı bekleyen satır turuncu şeritle, süresi geçen kırmızı şeritle işaretlenir (renk tek başına
/// değil: çip metni de söyler).
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
    final c = context.akn;
    final t = context.aknText;
    final internal =
        customerSide && row.type != ApprovalType.companyOrderRequest;
    // Cariye yöneltilen ek bilgi isteği: yanıtı cari verir (listede eylem bekleyen satır).
    final needsReply =
        internal &&
        row.status == ApprovalStatus.infoRequested &&
        (row.type == ApprovalType.orderFinance ||
            row.type == ApprovalType.customerOnboarding);
    final status = approvalStatusStyle(
      row,
      customerSide: customerSide,
      canProvideInfo: needsReply,
    );
    final sla = internal ? null : slaStyle(row);
    final typeStyle = AknStatus.approvalType(row.type);
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
        ? summaryParts.skip(1).join(' · ')
        : row.summary;
    final number = row.subjectNumber;
    final amount = row.amount;
    final when = Fmt.relative(row.createdAt);
    final accent = row.canDecide || needsReply
        ? AknTone.brand
        : (sla?.tone == AknTone.danger ? AknTone.danger : null);
    final levels = !internal && row.hasLevels && row.status.isOpen
        ? 'Kademe ${row.currentLevelNo}/${row.levelCount}'
        : null;

    final large = isLargeText(context);
    final amountText = amount != null
        ? AmountText(Fmt.money(amount), style: t.amount)
        : (row.liters != null
              ? AmountText(Fmt.liters(row.liters), style: t.amount)
              : null);
    final semantic = [
      row.displayTypeLabel,
      ?number,
      headline,
      status.label,
      ?sla?.label,
      ?levels,
      if (amount != null) Fmt.money(amount),
      if (row.canDecide) 'kararınızı bekliyor',
      when,
    ].join(', ');

    return AknCard(
      onTap: onTap,
      accent: accent,
      semanticLabel: semantic,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AknIconBox(icon: typeStyle.icon, tone: status.tone, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [row.displayTypeLabel, ?number].join(' · '),
                        style: t.captionStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        headline,
                        style: t.bodyStrong,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (!internal && (detailLine?.isNotEmpty ?? false)) ...[
                        const SizedBox(height: 2),
                        Text(
                          detailLine!,
                          style: t.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      // Büyük yazıda tutar ve zaman başlığın altına iner.
                      if (large) ...[
                        if (amountText != null) ...[
                          const SizedBox(height: 4),
                          Shrinkable(child: amountText),
                        ],
                        Text(when, style: t.caption),
                      ],
                    ],
                  ),
                ),
                if (!large) ...[
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      ?amountText,
                      const SizedBox(height: 2),
                      Text(when, style: t.caption),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Shrinkable(
                  child: StatusChip.style(status, size: StatusChipSize.small),
                ),
                if (sla != null)
                  Shrinkable(
                    child: StatusChip.style(sla, size: StatusChipSize.small),
                  ),
                if (levels != null)
                  Shrinkable(
                    child: StatusChip(
                      label: levels,
                      tone: AknTone.neutral,
                      icon: Icons.layers_rounded,
                      size: StatusChipSize.small,
                    ),
                  ),
                if (row.canDecide)
                  const Shrinkable(
                    child: StatusChip(
                      label: 'Kararınız bekleniyor',
                      tone: AknTone.brand,
                      icon: Icons.touch_app_rounded,
                      size: StatusChipSize.small,
                    ),
                  ),
                if (!customerSide &&
                    row.requestedByName != null &&
                    counterpart != null)
                  Text(
                    'Talep: ${row.requestedByName}',
                    style: t.caption.copyWith(color: c.dim),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

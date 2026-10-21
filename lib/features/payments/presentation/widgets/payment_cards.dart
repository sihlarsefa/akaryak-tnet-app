import 'package:flutter/material.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../../approvals/api.dart';
import '../../copy.dart';
import '../../data/payment_models.dart';

/// Vade ipucunun tonu: geciken kırmızı, bugün / 3 gün içinde sarı.
AknTone dueTone({required bool overdue, DateTime? due}) {
  if (overdue) return AknTone.danger;
  if (due == null) return AknTone.neutral;
  final days = TrTime.dayDiff(TrTime.now(), due);
  if (days <= 3) return AknTone.warn;
  return AknTone.neutral;
}

/// Ödeme satırı: sipariş no, cari, ödeme satırı, tutar (tahminiyse belirtilir), durum ve vade.
class PaymentRowCard extends StatelessWidget {
  const PaymentRowCard({super.key, required this.row, required this.onTap});

  final PaymentRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final status = AknStatus.payment(
      row.paymentStatus,
    ).withLabel(row.paymentStatusLabel);
    final overdue = row.isOverdue || row.overdueDays > 0;
    final tone = dueTone(overdue: overdue, due: row.dueDate);
    final amount = row.displayAmount;
    final large = isLargeText(context);
    final amountBox = Column(
      crossAxisAlignment: large
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        if (amount != null)
          Shrinkable(child: AmountText(Fmt.money(amount), style: t.amount)),
        if (row.isEstimate) Text('tahmini', style: t.caption),
      ],
    );
    final semantic = [
      row.orderNumber,
      row.customerTitle,
      row.paymentLine,
      status.label,
      ?row.dueHint,
      if (amount != null)
        '${row.isEstimate ? 'tahmini ' : ''}${Fmt.money(amount)}',
      ?row.financeLabel,
    ].join(', ');
    return AknCard(
      onTap: onTap,
      accent: overdue || row.paymentStatus == PaymentStatus.bounced
          ? AknTone.danger
          : null,
      semanticLabel: semantic,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AknIconBox(
                  icon: PaymentsCopy.methodIcon(row.methodCode),
                  tone: status.tone,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(row.orderNumber, style: t.captionStrong),
                      const SizedBox(height: 2),
                      Text(
                        row.customerTitle,
                        style: t.bodyStrong,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (row.paymentLine.isNotEmpty)
                        Text(row.paymentLine, style: t.bodySmall),
                      // Büyük yazıda tutar başlığın altına iner.
                      if (large) ...[const SizedBox(height: 4), amountBox],
                    ],
                  ),
                ),
                if (!large) ...[const SizedBox(width: 12), amountBox],
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Shrinkable(
                  child: StatusChip.style(status, size: StatusChipSize.small),
                ),
                if (row.dueHint != null)
                  Shrinkable(
                    child: StatusChip(
                      label: row.dueHint!,
                      tone: tone,
                      icon: overdue
                          ? Icons.alarm_off_rounded
                          : Icons.event_rounded,
                      size: StatusChipSize.small,
                    ),
                  ),
                if (row.financeLabel != null)
                  Shrinkable(
                    child: StatusChip.style(
                      AknStatus.finance(
                        row.financeStatus,
                      ).withLabel(row.financeLabel),
                      size: StatusChipSize.small,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Çek / senet satırı: tür ve seri no, cari, banka / borçlu, tutar, vade, durum.
class InstrumentRowCard extends StatelessWidget {
  const InstrumentRowCard({
    super.key,
    required this.instrument,
    required this.onTap,
  });

  final Instrument instrument;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final i = instrument;
    final status = AknStatus.instrument(i.status).withLabel(i.statusLabel);
    final kind = AknStatus.instrumentKind(i.kind);
    final tone = i.isOpen
        ? dueTone(overdue: i.isOverdue, due: i.dueDate)
        : AknTone.neutral;
    final source = [
      ?i.bankName,
      ?i.branchName,
      if (i.bankName == null && i.debtorName != i.customerTitle) ?i.debtorName,
    ].join(' · ');
    final large = isLargeText(context);
    final amountBox = Column(
      crossAxisAlignment: large
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        Shrinkable(child: AmountText(Fmt.money(i.amount), style: t.amount)),
        Text('vade ${Fmt.date(i.dueDate)}', style: t.caption),
      ],
    );
    final semantic = [
      i.displayKindLabel,
      ?i.serialNo,
      i.customerTitle,
      if (source.isNotEmpty) source,
      Fmt.money(i.amount),
      'vade ${Fmt.date(i.dueDate)}',
      ?i.dueHint,
      status.label,
    ].join(', ');
    return AknCard(
      onTap: onTap,
      accent:
          i.isOverdue ||
              i.status == InstrumentStatus.bounced ||
              i.status == InstrumentStatus.protested
          ? AknTone.danger
          : null,
      semanticLabel: semantic,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AknIconBox(icon: kind.icon, tone: status.tone),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [i.displayKindLabel, ?i.serialNo].join(' · '),
                        style: t.captionStrong,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        i.customerTitle,
                        style: t.bodyStrong,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (source.isNotEmpty) Text(source, style: t.bodySmall),
                      if (large) ...[const SizedBox(height: 4), amountBox],
                    ],
                  ),
                ),
                if (!large) ...[const SizedBox(width: 12), amountBox],
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
                if (i.dueHint != null)
                  Shrinkable(
                    child: StatusChip(
                      label: i.dueHint!,
                      tone: tone,
                      icon: i.isOverdue
                          ? Icons.alarm_off_rounded
                          : Icons.event_rounded,
                      size: StatusChipSize.small,
                    ),
                  ),
                if (i.orderNumber != null)
                  Text('Sipariş ${i.orderNumber}', style: t.caption),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

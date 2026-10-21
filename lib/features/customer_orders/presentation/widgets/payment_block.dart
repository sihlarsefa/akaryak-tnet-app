import 'package:flutter/material.dart';

import '../../../../core/models/models.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/order_view_controller.dart';
import '../../copy.dart';
import '../../data/payment_models.dart';
import 'common.dart';

String _methodName(String? code) => switch (code) {
  PaymentCodes.cash => 'Nakit',
  PaymentCodes.transfer => 'Havale / EFT',
  PaymentCodes.card => 'Kredi / banka kartı',
  PaymentCodes.dbs => 'DBS',
  PaymentCodes.cheque => 'Çek',
  PaymentCodes.promissoryNote => 'Senet',
  PaymentCodes.openAccount => 'Açık hesap',
  PaymentCodes.guarantee => 'Teminat mektubu',
  PaymentCodes.utts => 'Taşıt tanıma (UTTS)',
  PaymentCodes.advance => 'Ön ödemeli bakiye',
  null => 'Belirtilmedi',
  _ => code,
};

/// "Çek · 30 gün · vade 20.11.2026".
String paymentLineOf(OrderDetail d) {
  final parts = <String>[_methodName(d.paymentMethodCode)];
  final t = d.paymentTermDays;
  if (t != null && t > 0) parts.add('$t gün');
  final inst = d.paymentInstallments;
  if (inst != null && inst > 1) parts.add('$inst taksit');
  if (d.paymentDueDate != null) {
    parts.add(
      '${(t ?? 0) > 0 ? 'vade' : 'ödeme'} ${Fmt.date(d.paymentDueDate)}',
    );
  }
  return parts.join(' · ');
}

/// Ödeme kartı: yöntem, vade, tahsilat durumu, ödeme belgesi (eksikse yükleme çağrısı).
class PaymentBlock extends StatelessWidget {
  const PaymentBlock({super.key, required this.view, this.onUpload});

  final OrderView view;
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final d = view.detail;
    final target = view.documentTarget;
    final docs = target == null
        ? const <Attachment>[]
        : view.documents
              .where((a) => a.isActive && a.kind == target.kind)
              .toList();
    final instrument = PaymentCodes.isInstrument(d.paymentMethodCode);
    return SectionCard(
      title: 'Ödeme',
      icon: Icons.payments_rounded,
      accent: view.paymentDocumentMissing ? AknTone.warn : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FactRow(label: 'Yöntem', value: paymentLineOf(d)),
          if (d.paymentMethodCode != null)
            FactRow(
              label: 'Tahsilat',
              value: d.paymentStatus.label,
              tone: d.paymentStatus.statusStyle.tone,
            ),
          if (d.estimatedAmount != null)
            FactRow(
              label: 'Tahmini tutar',
              value: Fmt.money(d.estimatedAmount),
            ),
          if (target != null) ...[
            const SizedBox(height: 6),
            if (docs.isNotEmpty)
              for (final a in docs)
                AttachmentTile(
                  fileName: a.fileName,
                  kindLabel: a.kindLabelFromServer ?? a.kind.label,
                  sizeBytes: a.sizeBytes,
                  contentType: a.contentType,
                  subtitle: a.createdAt == null
                      ? null
                      : 'Yüklendi ${Fmt.relative(a.createdAt)}',
                  state: AttachmentTileState.done,
                )
            else if (view.paymentDocumentMissing)
              AknBanner(
                tone: AknTone.warn,
                icon: Icons.photo_camera_outlined,
                title: '${target.label} bekleniyor',
                message: target.isUploadable
                    ? 'Görseli yükleyin; yüklenmeden teklif onaylanamaz.'
                    : (target.message ??
                          'Bu belgeyi yükleme yetkiniz yok; şirket yöneticinize başvurun.'),
                actionLabel: target.isUploadable && onUpload != null
                    ? 'Görseli yükle'
                    : null,
                onAction: onUpload,
              )
            else if (target.isUploadable && onUpload != null)
              Align(
                alignment: Alignment.centerLeft,
                child: AknButton.secondary(
                  label: target.kind == AttachmentKind.transferReceipt
                      ? 'Dekont ekle'
                      : '${target.label} ekle',
                  icon: Icons.attach_file_rounded,
                  size: AknButtonSize.small,
                  onPressed: onUpload,
                ),
              ),
            if (instrument && docs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 16, color: c.dim),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${OrdersCopy.instrumentHint}.',
                        style: t.caption.copyWith(color: c.dim),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

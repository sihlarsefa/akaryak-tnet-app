import 'package:flutter/material.dart';

import '../../../../core/models/models.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../application/order_view_controller.dart';
import '../../copy.dart';
import '../../data/payment_models.dart';
import 'order_parts.dart';

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

/// Yöntem cümle içinde: "Çek ile", "Nakit", "Ön ödemeli bakiyeden".
String _methodPhrase(String? code) => switch (code) {
  PaymentCodes.cash => 'Nakit',
  PaymentCodes.openAccount => 'Açık hesap',
  PaymentCodes.advance => 'Ön ödemeli bakiyeden',
  null => 'Ödeme belirtilmedi',
  _ => '${_methodName(code)} ile',
};

/// "Çek, 30 gün, vade 20.11.2026".
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
  return parts.join(', ');
}

/// "Çek ile, 30 gün vade" / "Kredi / banka kartı ile, 3 taksit".
String paymentSentenceOf(OrderDetail d) {
  final parts = <String>[_methodPhrase(d.paymentMethodCode)];
  final t = d.paymentTermDays;
  if (t != null && t > 0) parts.add('$t gün vade');
  final inst = d.paymentInstallments;
  if (inst != null && inst > 1) parts.add('$inst taksit');
  if (parts.length == 1 && parts.first.endsWith(' ile')) {
    return '${parts.first} ödeme';
  }
  return parts.join(', ');
}

/// Belirtme hâli (sözcük ünlü uyumuyla): "çek görseli" → "çek görselini", "dekont" → "dekontu".
/// Belge adları iyelik ekli tamlamalardır ("… görseli", "… dekontu"); ünlüyle biten sözcüğe "n" +
/// ünlü eklenir.
String accusative(String noun) {
  final w = noun.trim();
  if (w.isEmpty) return w;
  const vowels = 'aeıioöuü';
  final last = w[w.length - 1];
  final vs = w.split('').where(vowels.contains).toList();
  final v = vs.isEmpty ? 'e' : vs.last;
  final suffix = switch (v) {
    'a' || 'ı' => 'ı',
    'e' || 'i' => 'i',
    'o' || 'u' => 'u',
    _ => 'ü',
  };
  return vowels.contains(last) ? '${w}n$suffix' : '$w$suffix';
}

/// Plakanın altındaki ödeme satırı (§7.8): "Çek ile, 30 gün vade. Çek görseli yüklendi." (yeşil
/// onay). Zorunlu belge eksikse koyu sarı kuyu "Onaylamak için çek görselini yükleyin" + "Belge
/// yükle".
class PaymentFactLine extends StatelessWidget {
  const PaymentFactLine({super.key, required this.view, this.onUpload});

  final OrderView view;
  final VoidCallback? onUpload;

  @override
  Widget build(BuildContext context) {
    final d = view.detail;
    final target = view.documentTarget;
    final sentence = '${paymentSentenceOf(d)}.';
    if (target != null && view.paymentDocumentMissing) {
      final label = accusative(TurkishText.lower(target.label));
      return AknBanner(
        tone: AknTone.warn,
        icon: Icons.photo_camera_outlined,
        title: 'Onaylamak için $label yükleyin',
        message: target.isUploadable
            ? sentence
            : (target.message ??
                  '$sentence Bu belgeyi yükleme yetkiniz yok; şirket yöneticinize başvurun.'),
        actionLabel: target.isUploadable && onUpload != null
            ? 'Belge yükle'
            : null,
        onAction: onUpload,
      );
    }
    if (target != null && view.hasPaymentDocument) {
      return FactLine(
        icon: Icons.check_circle_rounded,
        tone: AknTone.ok,
        text: '$sentence ${target.label} yüklendi.',
      );
    }
    return FactLine(icon: Icons.payments_outlined, text: sentence);
  }
}

/// "Ödeme" bölümü: yöntem, tahsilat durumu, tahmini tutar ve ödeme belgesi (eksikse yükleme).
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
    return OrderSection(
      title: 'Ödeme',
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
            const SizedBox(height: 8),
            if (docs.isNotEmpty)
              for (final a in docs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AttachmentTile(
                    fileName: a.fileName,
                    kindLabel: a.kindLabelFromServer ?? a.kind.label,
                    sizeBytes: a.sizeBytes,
                    contentType: a.contentType,
                    subtitle: a.createdAt == null
                        ? null
                        : 'Yüklendi ${TurkishText.lower(Fmt.relative(a.createdAt))}',
                    state: AttachmentTileState.done,
                  ),
                )
            // Zorunlu belge eksikse yükleme çağrısı plakanın altındaki uyarıdadır.
            else if (target.isUploadable &&
                onUpload != null &&
                !view.paymentDocumentMissing)
              AttachmentTile(
                fileName: target.label,
                kindLabel: 'İsteğe bağlı',
                onUpload: onUpload,
                actionLabel: 'Ekle',
              ),
            if (instrument && docs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${OrdersCopy.instrumentHint}.',
                  style: t.bodySmall.copyWith(color: c.dim),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

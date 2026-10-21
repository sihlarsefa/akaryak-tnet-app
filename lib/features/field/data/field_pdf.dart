import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/akn_pdf.dart';
import '../../../core/utils/format.dart';
import 'field_models.dart';

/// Saha sipariş formu PDF'i (web `Documents/FieldOrderForm` düzeni; cihazda üretilir, paylaşılır).
///
/// Dış belge müşteriye imzalatılır: maliyet / kâr alanı yoktur. İç belge ([FieldDocument.internal]) yalnızca
/// maliyet görebilene gelir ve "müşteriye verilmez" uyarısı taşır. Mali belge değildir.
abstract final class FieldOrderPdf {
  static const footerNote =
      'Saha sipariş formudur; mali belge değildir, e-fatura yerine geçmez. '
      'Onaylanan fiyat müşteriye teklif olarak iletilir.';

  static const internalFooterNote =
      'İç kullanım içindir: maliyet ve kâr bilgisi içerir, müşteriye verilmez.';

  static String fileName(FieldDocument d) =>
      '${d.isInternal ? 'Ic-siparis-formu' : 'Siparis-formu'}-${d.formNumber}.pdf';

  static Future<Uint8List> build(FieldDocument d) => AknPdf.buildA4(
    title: d.isInternal ? 'İç sipariş formu' : 'Saha sipariş formu',
    subtitle: d.statusLabel,
    number: d.formNumber,
    date: d.submittedAt ?? d.createdAt,
    footerNote: d.isInternal ? internalFooterNote : footerNote,
    body: (t) => [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: _party('Bayi', d.station)),
          pw.SizedBox(width: 10),
          pw.Expanded(child: _party('Müşteri', d.customer)),
        ],
      ),
      _section('Ödeme ve sevk', [
        AknPdf.row('Ödeme yöntemi', d.paymentMethodName),
        AknPdf.row(
          'Vade',
          d.paymentTermDays == 0 ? 'Peşin' : '${d.paymentTermDays} gün',
        ),
        if (d.shipDate != null) AknPdf.row('Sevk tarihi', Fmt.date(d.shipDate)),
        if (d.paymentDueDate != null)
          AknPdf.row('Ödeme tarihi', Fmt.date(d.paymentDueDate)),
        if (d.distributorName != null)
          AknPdf.row('Anadağıtım', d.distributorName),
        if (d.terminalName != null) AknPdf.row('Terminal', d.terminalName),
      ]),
      AknPdf.table(
        headers: const [
          '#',
          'Ürün',
          'Teslimat noktası',
          'Teslim',
          'Litre',
          '₺/L',
          'Tutar ₺',
        ],
        rows: [
          for (final l in d.lines)
            [
              '${l.no}',
              l.productName,
              l.orderNumber == null
                  ? l.deliveryPointName
                  : '${l.deliveryPointName}\nSipariş ${l.orderNumber}',
              Fmt.date(l.requestedDeliveryDate),
              Fmt.number(l.quantityLiters, maxFraction: 3),
              Fmt.number(l.unitPrice, minFraction: 2, maxFraction: 4),
              Fmt.number(l.amount, minFraction: 2, maxFraction: 2),
            ],
        ],
        align: const {
          0: pw.Alignment.centerRight,
          4: pw.Alignment.centerRight,
          5: pw.Alignment.centerRight,
          6: pw.Alignment.centerRight,
        },
      ),
      AknPdf.totalBox(
        'Form tutarı',
        Fmt.money(d.totalAmount),
        hint: '${Fmt.liters(d.totalLiters)} · KDV dahil teklif fiyatlarıyla',
      ),
      if (d.note != null) _section('Not', [_text(d.note!)]),
      _section('Hazırlayan', [
        AknPdf.row(
          'Satış temsilcisi',
          d.salesRepresentativeName ?? d.createdByName,
        ),
        if (d.approvalKind != null)
          AknPdf.row(
            'Onay',
            [d.approvalKind, d.approvedByName].whereType<String>().join(' · '),
          ),
        if (d.printedBy.isNotEmpty) AknPdf.row('Yazdıran', d.printedBy),
      ]),
      if (d.internal != null) ..._internal(d.internal!),
      AknPdf.signatures(const ['Müşteri yetkilisi', 'Satış temsilcisi']),
    ],
  );

  static List<pw.Widget> _internal(FieldDocInternal i) => [
    pw.SizedBox(height: 6),
    _section('İç açılım', [
      if (i.refineryLocationLabel != null)
        AknPdf.row('Tüpraş lokasyonu', i.refineryLocationLabel),
      AknPdf.row('Satış vadesi', '${i.termDays} gün'),
      if (i.purchaseTermDays != null)
        AknPdf.row('Alım vadesi', '${i.purchaseTermDays} gün'),
      if (i.purchaseTermPercent != null)
        AknPdf.row('Alım şartı', Fmt.percent(i.purchaseTermPercent)),
      if (i.valorPercent != null)
        AknPdf.row('Valör', Fmt.percent(i.valorPercent, maxFraction: 2)),
      if (i.otherPercent != null)
        AknPdf.row('Diğer', Fmt.percent(i.otherPercent, maxFraction: 2)),
      if (i.collateralRatioPercent != null)
        AknPdf.row('Teminat oranı', Fmt.percent(i.collateralRatioPercent)),
      if (i.transportTotal != null)
        AknPdf.row('Nakliye', Fmt.money(i.transportTotal)),
      if (i.formProfitPercent != null)
        AknPdf.row(
          'Form kâr %',
          Fmt.percent(i.formProfitPercent, maxFraction: 2),
          bold: true,
        ),
      if (i.netProfit != null)
        AknPdf.row('Net kâr (KDV hariç)', Fmt.money(i.netProfit), bold: true),
      if (i.baremOutcome != null)
        AknPdf.row(
          'Barem',
          [i.baremOutcome, i.baremChip].whereType<String>().join(' · '),
        ),
      if (i.financeStatusLabel != null)
        AknPdf.row(
          'Finans',
          [
            i.financeStatusLabel,
            i.financeReasons,
          ].whereType<String>().join(' · '),
        ),
    ]),
    if (i.lines.isNotEmpty)
      AknPdf.table(
        headers: const [
          '#',
          'Ürün',
          'Litre',
          'Tüpraş ₺/m³',
          'Maliyet ₺/m³',
          'Fatura ₺/m³',
          'Kâr %',
        ],
        rows: [
          for (final l in i.lines)
            [
              '${l.no}',
              l.tuprasOverridden
                  ? '${l.productName} (Tüpraş elle)'
                  : l.productName,
              Fmt.number(l.quantityLiters, maxFraction: 3),
              Fmt.number(l.tuprasPriceM3, minFraction: 2, maxFraction: 2),
              Fmt.number(l.costM3, minFraction: 2, maxFraction: 2),
              Fmt.number(l.invoicePriceM3, minFraction: 2, maxFraction: 2),
              Fmt.percent(l.profitPercent, maxFraction: 2),
            ],
        ],
        align: const {
          0: pw.Alignment.centerRight,
          2: pw.Alignment.centerRight,
          3: pw.Alignment.centerRight,
          4: pw.Alignment.centerRight,
          5: pw.Alignment.centerRight,
          6: pw.Alignment.centerRight,
        },
      ),
    if (i.approvals.isNotEmpty)
      _section('Onay izi', [
        for (final a in i.approvals)
          AknPdf.row(
            '${a.levelLabel} · ${a.decisionLabel}',
            [
              a.approverName,
              if (a.decidedAt != null) Fmt.dateTime(a.decidedAt),
              a.note,
            ].whereType<String>().join(' · '),
          ),
      ]),
  ];

  static pw.Widget _party(String title, FieldDocParty p) => _section(title, [
    pw.Text(
      p.title,
      style: pw.TextStyle(
        fontSize: 10,
        fontWeight: pw.FontWeight.bold,
        color: AknPdf.ink,
      ),
    ),
    pw.SizedBox(height: 3),
    if (p.code != null) _small('Kod: ${p.code}'),
    if (p.taxNumber != null)
      _small(
        'VKN/TCKN: ${p.taxNumber}${p.taxOffice == null ? '' : ' · ${p.taxOffice}'}',
      ),
    if (p.address != null) _small(p.address!),
    if (p.place.isNotEmpty) _small(p.place),
    if (p.phone != null) _small('Tel: ${Fmt.phone(p.phone)}'),
    if (p.email != null) _small(p.email!),
  ]);

  /// Başlıklı bölüm (cümle düzeni; büyük harf dönüşümü yok).
  static pw.Widget _section(String title, List<pw.Widget> children) =>
      pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: AknPdf.line, width: 0.8),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: AknPdf.brand,
              ),
            ),
            pw.SizedBox(height: 6),
            ...children,
          ],
        ),
      );

  static pw.Widget _small(String s) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 1),
    child: pw.Text(
      s,
      style: const pw.TextStyle(fontSize: 8.5, color: AknPdf.text),
    ),
  );

  static pw.Widget _text(String s) => pw.Text(
    s,
    style: const pw.TextStyle(
      fontSize: 9.5,
      color: PdfColor.fromInt(0xFF0F172A),
    ),
  );
}

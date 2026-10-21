import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/akn_pdf.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/turkish_text.dart';
import 'doc_spec.dart';

/// [DocSpec] → A4 PDF (lacivert/turuncu kurumsal kimlik, gömülü Roboto ile Türkçe karakterler).
abstract final class DocRenderer {
  static const _navy = AknPdf.navy;
  static const _brand = AknPdf.brand;
  static const _logo = AknPdf.logo;
  static const _ink = AknPdf.ink;
  static const _text = AknPdf.text;
  static const _dim = AknPdf.dim;
  static const _line = AknPdf.line;
  static const _soft = AknPdf.soft;
  static const _brandSoft = PdfColor.fromInt(0xFFFDF5EF);

  static const _margin = 12 * PdfPageFormat.mm;
  static double get _contentWidth => PdfPageFormat.a4.width - 2 * _margin;

  static PdfColor _tone(DocTone t) => switch (t) {
    DocTone.ok => const PdfColor.fromInt(0xFF047857),
    DocTone.warn => const PdfColor.fromInt(0xFFB45309),
    DocTone.danger => const PdfColor.fromInt(0xFFB91C1C),
    DocTone.brand => _brand,
    DocTone.info => const PdfColor.fromInt(0xFF1D4ED8),
    DocTone.neutral => _text,
  };

  static PdfColor _toneBg(DocTone t) => switch (t) {
    DocTone.ok => const PdfColor.fromInt(0xFFECFDF5),
    DocTone.warn => const PdfColor.fromInt(0xFFFFFBEB),
    DocTone.danger => const PdfColor.fromInt(0xFFFEF2F2),
    DocTone.brand => _brandSoft,
    DocTone.info => const PdfColor.fromInt(0xFFEFF6FF),
    DocTone.neutral => _soft,
  };

  /// PDF baytları.
  static Future<Uint8List> render(DocSpec d) async {
    final t = await AknPdf.theme();
    final doc = pw.Document(
      title: '${d.title} ${d.code}',
      author: DocSpec.platformName,
      creator: DocSpec.platformName,
      subject: d.title,
      theme: pw.ThemeData.withFont(base: t.regular, bold: t.bold),
    );
    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4.copyWith(
            marginLeft: _margin,
            marginRight: _margin,
            marginTop: _margin,
            marginBottom: _margin,
          ),
          theme: pw.ThemeData.withFont(base: t.regular, bold: t.bold),
          buildForeground: d.watermark == null
              ? null
              : (ctx) => _watermark(d.watermark!, d.stamp?.tone),
        ),
        header: (ctx) => ctx.pageNumber == 1 ? _header(d, t) : pw.SizedBox(),
        footer: (ctx) => _footer(ctx, d),
        build: (ctx) => [
          for (final b in d.blocks) ...[
            ..._blockWidgets(b),
            pw.SizedBox(height: 8),
          ],
        ],
      ),
    );
    return doc.save();
  }

  // ------------------------------------------------------------------ Başlık ve alt bilgi

  static pw.Widget _watermark(String text, DocTone? tone) => pw.Center(
    child: pw.Transform.rotate(
      angle: -math.pi / 7,
      child: pw.Opacity(
        opacity: 0.08,
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 84,
            fontWeight: pw.FontWeight.bold,
            color: tone == DocTone.danger ? _tone(DocTone.danger) : _navy,
          ),
        ),
      ),
    ),
  );

  static pw.Widget _header(DocSpec d, AknPdfTheme t) {
    final stamp = d.stamp;
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          // Marka şeridi: işaret + AkaryakıtNet | gönderen bayi
          pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: _line)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Image(t.mark, width: 26, height: 26),
                pw.SizedBox(width: 6),
                pw.RichText(
                  text: pw.TextSpan(
                    children: [
                      pw.TextSpan(
                        text: 'Akaryakıt',
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: _navy,
                        ),
                      ),
                      pw.TextSpan(
                        text: 'Net',
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: _logo,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 16),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        d.issuerTitle,
                        textAlign: pw.TextAlign.right,
                        style: pw.TextStyle(
                          fontSize: 9.5,
                          fontWeight: pw.FontWeight.bold,
                          color: _ink,
                        ),
                      ),
                      if (d.issuerLine != null && d.issuerLine!.isNotEmpty)
                        pw.Text(
                          d.issuerLine!,
                          textAlign: pw.TextAlign.right,
                          style: const pw.TextStyle(fontSize: 8, color: _dim),
                        ),
                    ],
                  ),
                ),
                if (d.brand != null) ...[
                  pw.SizedBox(width: 8),
                  _chip(d.brand!, DocTone.brand),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 10),
          // Başlık: tür, ad, numara | mühür | barkod + QR
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      TurkishText.upper(d.kicker),
                      style: pw.TextStyle(
                        fontSize: 7.5,
                        fontWeight: pw.FontWeight.bold,
                        color: _brand,
                        letterSpacing: 0.6,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      d.title,
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: _navy,
                      ),
                    ),
                    if (d.subtitle != null)
                      pw.Text(
                        d.subtitle!,
                        style: const pw.TextStyle(fontSize: 9, color: _dim),
                      ),
                    pw.SizedBox(height: 6),
                    pw.Row(
                      children: [
                        pw.Text(
                          '${d.numberLabel}  ',
                          style: const pw.TextStyle(fontSize: 8.5, color: _dim),
                        ),
                        pw.Text(
                          d.number,
                          style: pw.TextStyle(
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                            color: _brand,
                          ),
                        ),
                        if (d.seq != null) ...[
                          pw.SizedBox(width: 8),
                          _chip(d.seq!, DocTone.neutral),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (stamp != null) ...[
                pw.SizedBox(width: 8),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _tone(stamp.tone), width: 1.4),
                    borderRadius: const pw.BorderRadius.all(
                      pw.Radius.circular(4),
                    ),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        stamp.text,
                        style: pw.TextStyle(
                          fontSize: 9.5,
                          fontWeight: pw.FontWeight.bold,
                          color: _tone(stamp.tone),
                          letterSpacing: 0.6,
                        ),
                      ),
                      if (stamp.sub != null && stamp.sub!.isNotEmpty)
                        pw.Text(
                          stamp.sub!,
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            color: _tone(stamp.tone),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              pw.SizedBox(width: 10),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.code128(),
                    data: d.barcode,
                    width: 118,
                    height: 30,
                    drawText: true,
                    // Varsayılan Courier (Type1) yerine gömülü yazı tipi.
                    textStyle: pw.TextStyle(
                      font: t.regular,
                      fontSize: 7,
                      color: _ink,
                    ),
                  ),
                  if (d.qrUrl != null) ...[
                    pw.SizedBox(height: 6),
                    pw.Row(
                      mainAxisSize: pw.MainAxisSize.min,
                      children: [
                        if (d.qrCaption != null)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(right: 4),
                            child: pw.Text(
                              d.qrCaption!,
                              style: const pw.TextStyle(
                                fontSize: 7,
                                color: _dim,
                              ),
                            ),
                          ),
                        pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: d.qrUrl!,
                          width: 46,
                          height: 46,
                          drawText: false,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _footer(pw.Context ctx, DocSpec d) {
    final printed = d.printedAt == null
        ? '${DocSpec.platformName}\'ten oluşturuldu.'
        : '${Fmt.dateTime(d.printedAt)}${d.printedBy.trim().isEmpty ? '' : ' · ${d.printedBy}'} tarafından ${DocSpec.platformName}\'ten oluşturuldu.';
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 6),
      padding: const pw.EdgeInsets.only(top: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _line, width: 0.6)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  DocSpec.legalFooter,
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                    color: _text,
                  ),
                ),
                pw.Text(
                  printed,
                  style: const pw.TextStyle(fontSize: 7, color: _dim),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                d.code,
                style: pw.TextStyle(
                  fontSize: 7.5,
                  fontWeight: pw.FontWeight.bold,
                  color: _ink,
                ),
              ),
              pw.Text(
                'Sayfa ${ctx.pageNumber}/${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 7, color: _dim),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ Bloklar

  /// Uzun tablolar sayfalara bölünebilsin diye başlık ve tablo ayrı üst düzey parçalardır.
  static List<pw.Widget> _blockWidgets(DocBlock b) {
    if (b is DocTableBlock && b.heading != null) {
      return [_boxHeader(b.heading!, small: b.small), _table(b)];
    }
    return [_block(b)];
  }

  static pw.Widget _block(DocBlock b) => switch (b) {
    DocMetaBlock() => _meta(b),
    DocPartiesBlock() => pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: _party(b.left)),
        pw.SizedBox(width: 8),
        pw.Expanded(child: _party(b.right)),
      ],
    ),
    DocAddressBlock() => _box(
      b.heading,
      small: b.small,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: 14,
                height: 14,
                margin: const pw.EdgeInsets.only(right: 6, top: 1),
                decoration: const pw.BoxDecoration(
                  color: _brandSoft,
                  shape: pw.BoxShape.circle,
                ),
                child: pw.Center(
                  child: pw.Container(
                    width: 5,
                    height: 5,
                    decoration: const pw.BoxDecoration(
                      color: _brand,
                      shape: pw.BoxShape.circle,
                    ),
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      b.name,
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: _ink,
                      ),
                    ),
                    pw.Text(
                      b.address,
                      style: const pw.TextStyle(fontSize: 8.5, color: _text),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    b.city.isEmpty ? Fmt.dash : b.city,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: _navy,
                    ),
                  ),
                  pw.Text(
                    b.district,
                    style: const pw.TextStyle(fontSize: 8.5, color: _dim),
                  ),
                ],
              ),
            ],
          ),
          if (b.details.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            _kvRows(b.details),
          ],
        ],
      ),
    ),
    DocTableBlock() => _table(b),
    DocTotalBlock() => pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _navy, width: 0.9),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  b.label,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: _ink,
                  ),
                ),
                if (b.hint != null)
                  pw.Text(
                    b.hint!,
                    style: const pw.TextStyle(fontSize: 7.5, color: _dim),
                  ),
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Text(
            b.value,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: _brand,
            ),
          ),
        ],
      ),
    ),
    DocKvBlock() => _box(b.heading, small: b.small, child: _kvRows(b.rows)),
    DocKpisBlock() => _kpis(b),
    DocCalloutBlock() => pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: pw.BoxDecoration(
        color: _toneBg(b.tone),
        border: pw.Border(left: pw.BorderSide(color: _tone(b.tone), width: 3)),
      ),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: b.title,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: _tone(b.tone),
              ),
            ),
            if (b.text != null)
              pw.TextSpan(
                text: ' ${b.text}',
                style: const pw.TextStyle(fontSize: 9, color: _text),
              ),
          ],
        ),
      ),
    ),
    DocTextBlock(:final text, :final fine, :final statement) =>
      statement
          ? pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: const pw.BoxDecoration(
                color: _soft,
                borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Text(
                text,
                style: const pw.TextStyle(
                  fontSize: 10.5,
                  color: _ink,
                  lineSpacing: 3,
                ),
              ),
            )
          : pw.Text(
              text,
              style: pw.TextStyle(
                fontSize: fine ? 7.5 : 9,
                color: fine ? _dim : _text,
              ),
            ),
    DocNotesBlock(:final lines) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final l in lines)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '•  ',
                  style: const pw.TextStyle(fontSize: 8.5, color: _brand),
                ),
                pw.Expanded(
                  child: pw.Text(
                    l,
                    style: const pw.TextStyle(fontSize: 8.5, color: _text),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
    DocFillBlock() =>
      b.heading == null
          ? _fill(b.cells, 4)
          : _box(b.heading!, small: b.small, child: _fill(b.cells, 4)),
    DocPlateBlock() => _box(
      b.heading,
      small: b.small,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                width: 110,
                padding: const pw.EdgeInsets.symmetric(vertical: 7),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _ink, width: 1.2),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(3),
                  ),
                ),
                child: pw.Center(
                  child: pw.Text(
                    b.plate ?? 'PLAKA',
                    style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: b.plate == null ? _line : _ink,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              pw.SizedBox(width: 10),
              for (final f in b.fields)
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        f.label,
                        style: const pw.TextStyle(fontSize: 7.5, color: _dim),
                      ),
                      pw.Text(
                        f.value,
                        style: pw.TextStyle(
                          fontSize: 9.5,
                          fontWeight: pw.FontWeight.bold,
                          color: _ink,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (b.fill.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            _fill(b.fill, b.fill.length, inset: true),
          ],
        ],
      ),
    ),
    DocTimelineBlock() => _box(
      b.heading,
      small: b.small,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          for (final e in b.items)
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: _line, width: 0.4),
                ),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 74,
                    child: pw.Text(
                      e.time,
                      style: const pw.TextStyle(fontSize: 8, color: _dim),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          e.what,
                          style: pw.TextStyle(
                            fontSize: 8.5,
                            fontWeight: pw.FontWeight.bold,
                            color: _ink,
                          ),
                        ),
                        if (e.note != null)
                          pw.Text(
                            e.note!,
                            style: const pw.TextStyle(
                              fontSize: 8,
                              color: _text,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (e.who != null)
                    pw.Text(
                      e.who!,
                      style: const pw.TextStyle(fontSize: 8, color: _dim),
                    ),
                ],
              ),
            ),
          if (b.more != null)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(
                b.more!,
                style: const pw.TextStyle(fontSize: 7.5, color: _dim),
              ),
            ),
        ],
      ),
    ),
    DocSignaturesBlock(:final boxes) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < boxes.length; i++) ...[
            if (i > 0) pw.SizedBox(width: 10),
            pw.Expanded(child: _sign(boxes[i])),
          ],
        ],
      ),
    ),
  };

  static pw.Widget _chip(String text, DocTone tone) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: pw.BoxDecoration(
      color: _toneBg(tone),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
    ),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 7.5,
        fontWeight: pw.FontWeight.bold,
        color: _tone(tone),
      ),
    ),
  );

  static pw.Widget _boxHeader(
    String heading, {
    String? small,
    bool brand = false,
  }) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: pw.BoxDecoration(
      color: brand ? _navy : _soft,
      borderRadius: const pw.BorderRadius.only(
        topLeft: pw.Radius.circular(6),
        topRight: pw.Radius.circular(6),
      ),
    ),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            TurkishText.upper(heading),
            style: pw.TextStyle(
              fontSize: 7.5,
              fontWeight: pw.FontWeight.bold,
              color: brand ? PdfColors.white : _dim,
              letterSpacing: 0.6,
            ),
          ),
        ),
        if (small != null)
          pw.Text(
            small,
            style: pw.TextStyle(
              fontSize: 7.5,
              color: brand ? PdfColors.white : _dim,
            ),
          ),
      ],
    ),
  );

  static pw.Widget _box(
    String heading, {
    String? small,
    required pw.Widget child,
    bool brand = false,
  }) => pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _line, width: 0.8),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _boxHeader(heading, small: small, brand: brand),
        pw.Padding(padding: const pw.EdgeInsets.all(8), child: child),
      ],
    ),
  );

  static pw.Widget _kvRows(List<DocKv> rows) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      for (final r in rows)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 78,
                child: pw.Text(
                  r.label,
                  style: const pw.TextStyle(fontSize: 8, color: _dim),
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  r.value,
                  style: pw.TextStyle(
                    fontSize: 8.5,
                    color: r.accent ? _brand : _ink,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  static pw.Widget _meta(DocMetaBlock b) => pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _line, width: 0.8),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
    ),
    child: pw.Row(
      children: [
        for (var i = 0; i < b.cells.length; i++)
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              decoration: i == 0
                  ? null
                  : const pw.BoxDecoration(
                      border: pw.Border(
                        left: pw.BorderSide(color: _line, width: 0.6),
                      ),
                    ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    b.cells[i].label,
                    style: const pw.TextStyle(fontSize: 7.5, color: _dim),
                  ),
                  pw.SizedBox(height: 1),
                  pw.Text(
                    b.cells[i].value,
                    style: pw.TextStyle(
                      fontSize: 9.5,
                      fontWeight: pw.FontWeight.bold,
                      color: b.cells[i].accent ? _brand : _ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  static pw.Widget _party(DocPartyCard p) => _box(
    p.heading,
    small: p.code,
    brand: p.brand,
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          p.title,
          style: pw.TextStyle(
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
        if (p.subtitle != null)
          pw.Text(
            p.subtitle!,
            style: const pw.TextStyle(fontSize: 8, color: _dim),
          ),
        if (p.rows.isNotEmpty) ...[pw.SizedBox(height: 4), _kvRows(p.rows)],
      ],
    ),
  );

  static pw.Widget _table(DocTableBlock b) {
    pw.Widget cell(
      String text, {
      bool header = false,
      bool numeric = false,
      bool bold = false,
      bool muted = false,
    }) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Text(
        text,
        textAlign: numeric ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: header ? 7.5 : 8.5,
          fontWeight: header || bold ? pw.FontWeight.bold : null,
          color: header ? PdfColors.white : (muted ? _dim : _ink),
        ),
      ),
    );

    return pw.Table(
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: _line, width: 0.5),
      ),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: _navy),
          children: [
            for (var c = 0; c < b.headers.length; c++)
              cell(b.headers[c], header: true, numeric: b.numeric.contains(c)),
          ],
        ),
        for (var r = 0; r < b.rows.length; r++)
          pw.TableRow(
            decoration: r == b.highlightRow
                ? const pw.BoxDecoration(color: _brandSoft)
                : (r.isOdd ? const pw.BoxDecoration(color: _soft) : null),
            children: [
              for (var c = 0; c < b.rows[r].length; c++)
                cell(
                  b.rows[r][c],
                  numeric: b.numeric.contains(c),
                  bold: c == 0 || r == b.highlightRow,
                  muted: b.mutedRows.contains(r),
                ),
            ],
          ),
        if (b.footer != null)
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _soft),
            children: [
              for (var c = 0; c < b.footer!.length; c++)
                cell(b.footer![c], numeric: b.numeric.contains(c), bold: true),
            ],
          ),
      ],
    );
  }

  static pw.Widget _kpis(DocKpisBlock b) {
    final row = pw.Row(
      children: [
        for (var i = 0; i < b.cells.length; i++) ...[
          if (i > 0) pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 6,
              ),
              decoration: pw.BoxDecoration(
                color: _toneBg(b.cells[i].tone),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    b.cells[i].label,
                    style: const pw.TextStyle(fontSize: 7.5, color: _dim),
                  ),
                  pw.SizedBox(height: 2),
                  pw.RichText(
                    text: pw.TextSpan(
                      children: [
                        pw.TextSpan(
                          text: b.cells[i].value,
                          style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: b.cells[i].tone == DocTone.neutral
                                ? _ink
                                : _tone(b.cells[i].tone),
                          ),
                        ),
                        if (b.cells[i].unit != null)
                          pw.TextSpan(
                            text: ' ${b.cells[i].unit}',
                            style: const pw.TextStyle(fontSize: 8, color: _dim),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
    final progress = b.progress;
    final body = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        row,
        if (progress != null) ...[
          pw.SizedBox(height: 6),
          pw.Container(
            height: 5,
            decoration: const pw.BoxDecoration(
              color: _soft,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
            ),
            child: pw.Row(
              children: [
                if (progress.accepted > 0)
                  pw.Expanded(
                    flex: math.max(1, (progress.accepted * 1000).round()),
                    child: pw.Container(color: _tone(DocTone.ok)),
                  ),
                if (progress.inProcess > 0)
                  pw.Expanded(
                    flex: math.max(1, (progress.inProcess * 1000).round()),
                    child: pw.Container(color: _tone(DocTone.warn)),
                  ),
                if (progress.accepted + progress.inProcess < 0.999)
                  pw.Expanded(
                    flex: math.max(
                      1,
                      ((1 - progress.accepted - progress.inProcess) * 1000)
                          .round(),
                    ),
                    child: pw.SizedBox(),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
    return b.heading == null
        ? body
        : _box(b.heading!, small: b.small, child: body);
  }

  static pw.Widget _fill(
    List<DocFillCell> cells,
    int cols, {
    bool inset = false,
  }) {
    const gap = 6.0;
    final inner = _contentWidth - (inset ? 18 : 0);
    final unit = (inner - gap * (cols - 1)) / cols;
    return pw.Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [
        for (final c in cells)
          pw.Container(
            width: c.full ? inner : (c.wide ? unit * 2 + gap : unit),
            height: c.full ? 40 : 30,
            padding: const pw.EdgeInsets.all(4),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _line, width: 0.8),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Stack(
              children: [
                pw.Text(
                  c.label,
                  style: const pw.TextStyle(fontSize: 7, color: _dim),
                ),
                if (c.unit != null)
                  pw.Positioned(
                    right: 0,
                    bottom: 0,
                    child: pw.Text(
                      c.unit!,
                      style: const pw.TextStyle(fontSize: 7.5, color: _dim),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  static pw.Widget _sign(DocSignBox s) => pw.Container(
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: _line, width: 0.8),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: _soft,
          child: pw.Row(
            children: [
              pw.Text(
                s.title,
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                  color: _ink,
                ),
              ),
              if (s.sub != null) ...[
                pw.SizedBox(width: 4),
                pw.Expanded(
                  child: pw.Text(
                    s.sub!,
                    style: const pw.TextStyle(fontSize: 7.5, color: _dim),
                  ),
                ),
              ],
            ],
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _signLine('Ad soyad', s.name),
              pw.SizedBox(height: 6),
              _signLine('Tarih / saat', null),
              pw.SizedBox(height: 6),
              pw.Container(
                height: 46,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _line, width: 0.6),
                  borderRadius: const pw.BorderRadius.all(
                    pw.Radius.circular(4),
                  ),
                ),
                child: pw.Center(
                  child: pw.Text(
                    'İmza · Kaşe',
                    style: const pw.TextStyle(fontSize: 7.5, color: _line),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  static pw.Widget _signLine(String label, String? value) => pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 2),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _dim, width: 0.5)),
    ),
    child: pw.Row(
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 7.5, color: _dim)),
        pw.SizedBox(width: 6),
        pw.Expanded(
          child: pw.Text(
            value ?? '',
            style: const pw.TextStyle(fontSize: 8.5, color: _ink),
          ),
        ),
      ],
    ),
  );
}

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../utils/external_activity.dart';
import '../utils/format.dart';
import '../utils/tr_time.dart';
import '../utils/turkish_text.dart';

/// PDF teması: gömülü Roboto (Türkçe karakterler) ve » işareti.
class AknPdfTheme {
  const AknPdfTheme({
    required this.regular,
    required this.bold,
    required this.mark,
  });
  final pw.Font regular;
  final pw.Font bold;
  final pw.MemoryImage mark;
}

/// Uygulama içi PDF belgelerinin ortak tabanı (F2GO `islem_makbuzu.dart` uyarlaması, lacivert/turuncu).
/// Sipariş, irsaliye ve saha formu belgeleri (A3, A6) bu yardımcılarla kurulur:
///
/// ```dart
/// final bytes = await AknPdf.buildA4(
///   title: 'Sipariş Özeti', number: order.orderNumber, date: order.createdAt,
///   body: (t) => [AknPdf.section('Sipariş', [AknPdf.row('Ürün', order.productName)])],
/// );
/// await AknPdf.share(bytes, 'Siparis-${order.orderNumber}.pdf');
/// ```
abstract final class AknPdf {
  static const navy = PdfColor.fromInt(0xFF1F2A37);
  static const brand = PdfColor.fromInt(0xFFC94C0C);
  static const logo = PdfColor.fromInt(0xFFFF5001);
  static const ink = PdfColor.fromInt(0xFF0F172A);
  static const text = PdfColor.fromInt(0xFF334155);
  static const dim = PdfColor.fromInt(0xFF64748B);
  static const line = PdfColor.fromInt(0xFFE5E9F0);
  static const soft = PdfColor.fromInt(0xFFF1F5F9);
  static const ok = PdfColor.fromInt(0xFF047857);

  static AknPdfTheme? _theme;

  /// Yazı tipleri ve işaret (bir kez yüklenir).
  static Future<AknPdfTheme> theme() async {
    final cached = _theme;
    if (cached != null) return cached;
    final regular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );
    final bold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
    );
    final mark = pw.MemoryImage(
      (await rootBundle.load(
        'assets/brand/akn-mark-512.png',
      )).buffer.asUint8List(),
    );
    return _theme = AknPdfTheme(regular: regular, bold: bold, mark: mark);
  }

  /// A4 çok sayfalı belge: başlık, gövde, altbilgi (sayfa no + oluşturulma zamanı).
  static Future<Uint8List> buildA4({
    required String title,
    required List<pw.Widget> Function(AknPdfTheme theme) body,
    String? subtitle,
    String? number,
    DateTime? date,
    String? footerNote,
    String author = 'AkaryakıtNet',
  }) async {
    final t = await theme();
    final doc = pw.Document(
      title: title,
      author: author,
      theme: pw.ThemeData.withFont(base: t.regular, bold: t.bold),
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.copyWith(
          marginLeft: 16 * PdfPageFormat.mm,
          marginRight: 16 * PdfPageFormat.mm,
          marginTop: 14 * PdfPageFormat.mm,
          marginBottom: 14 * PdfPageFormat.mm,
        ),
        header: (ctx) => ctx.pageNumber == 1
            ? header(
                t,
                title: title,
                subtitle: subtitle,
                number: number,
                date: date,
              )
            : pw.SizedBox(),
        footer: (ctx) => footer(ctx, note: footerNote),
        build: (ctx) => body(t),
      ),
    );
    return doc.save();
  }

  /// Belge başlığı: işaret + marka, sağda belge adı / numara / tarih.
  static pw.Widget header(
    AknPdfTheme t, {
    required String title,
    String? subtitle,
    String? number,
    DateTime? date,
  }) => pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 14),
    padding: const pw.EdgeInsets.only(bottom: 10),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: line, width: 1)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Image(t.mark, width: 30, height: 30),
        pw.SizedBox(width: 8),
        pw.RichText(
          text: pw.TextSpan(
            children: [
              pw.TextSpan(
                text: 'Akaryakıt',
                style: pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                  color: navy,
                ),
              ),
              pw.TextSpan(
                text: 'Net',
                style: pw.TextStyle(
                  fontSize: 15,
                  fontWeight: pw.FontWeight.bold,
                  color: logo,
                ),
              ),
            ],
          ),
        ),
        pw.Spacer(),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 13,
                fontWeight: pw.FontWeight.bold,
                color: ink,
              ),
            ),
            if (subtitle != null)
              pw.Text(
                subtitle,
                style: const pw.TextStyle(fontSize: 9, color: dim),
              ),
            if (number != null)
              pw.Text(
                number,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: brand,
                ),
              ),
            if (date != null)
              pw.Text(
                Fmt.dateTime(date),
                style: const pw.TextStyle(fontSize: 9, color: dim),
              ),
          ],
        ),
      ],
    ),
  );

  /// Başlıklı bölüm (açık gri zemin).
  static pw.Widget section(String title, List<pw.Widget> children) =>
      pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: line, width: 0.8),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              TurkishText.upper(title),
              style: pw.TextStyle(
                fontSize: 8.5,
                fontWeight: pw.FontWeight.bold,
                color: dim,
                letterSpacing: 0.8,
              ),
            ),
            pw.SizedBox(height: 6),
            ...children,
          ],
        ),
      );

  /// Etiket — değer satırı.
  static pw.Widget row(
    String label,
    String? value, {
    bool bold = false,
    PdfColor? color,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 130,
          child: pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 9.5, color: dim),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            Fmt.orDash(value),
            style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color ?? ink,
            ),
          ),
        ),
      ],
    ),
  );

  /// Tablo (başlık satırı lacivert).
  static pw.Widget table({
    required List<String> headers,
    required List<List<String>> rows,
    Map<int, pw.Alignment>? align,
  }) => pw.TableHelper.fromTextArray(
    headers: headers,
    data: rows,
    headerStyle: pw.TextStyle(
      fontSize: 8.5,
      fontWeight: pw.FontWeight.bold,
      color: PdfColors.white,
    ),
    headerDecoration: const pw.BoxDecoration(color: navy),
    cellStyle: const pw.TextStyle(fontSize: 9, color: ink),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    rowDecoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: line, width: 0.5)),
    ),
    oddRowDecoration: const pw.BoxDecoration(color: soft),
    cellAlignments: align,
  );

  /// Vurgulu toplam kutusu.
  static pw.Widget totalBox(String label, String value, {String? hint}) =>
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 6, bottom: 10),
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: navy, width: 0.9),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        ),
        child: pw.Row(
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  label,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: ink,
                  ),
                ),
                if (hint != null)
                  pw.Text(
                    hint,
                    style: const pw.TextStyle(fontSize: 8, color: dim),
                  ),
              ],
            ),
            pw.Spacer(),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: brand,
              ),
            ),
          ],
        ),
      );

  /// QR kodu (belge numarası ya da doğrulama bağlantısı).
  static pw.Widget qr(String data, {double size = 26}) => pw.BarcodeWidget(
    barcode: pw.Barcode.qrCode(),
    data: data,
    width: size * PdfPageFormat.mm,
    height: size * PdfPageFormat.mm,
    drawText: false,
  );

  /// İmza alanları (Teslim eden / Teslim alan).
  static pw.Widget signatures(
    List<String> labels, {
    Map<String, pw.ImageProvider>? images,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 18),
    child: pw.Row(
      children: [
        for (final l in labels) ...[
          pw.Expanded(
            child: pw.Column(
              children: [
                pw.SizedBox(
                  height: 46,
                  child: images?[l] == null
                      ? pw.SizedBox()
                      : pw.Image(images![l]!, fit: pw.BoxFit.contain),
                ),
                pw.Container(height: 0.8, color: dim),
                pw.SizedBox(height: 3),
                pw.Text(
                  l,
                  style: const pw.TextStyle(fontSize: 8.5, color: dim),
                ),
              ],
            ),
          ),
          if (l != labels.last) pw.SizedBox(width: 24),
        ],
      ],
    ),
  );

  /// Altbilgi: not + sayfa + oluşturulma zamanı.
  static pw.Widget footer(pw.Context ctx, {String? note}) => pw.Container(
    margin: const pw.EdgeInsets.only(top: 8),
    padding: const pw.EdgeInsets.only(top: 6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: line, width: 0.6)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Text(
            note ??
                'Bu belge AkaryakıtNet uygulamasından oluşturulmuştur; bilgilendirme amaçlıdır.',
            style: const pw.TextStyle(fontSize: 7, color: dim),
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Text(
          'Sayfa ${ctx.pageNumber}/${ctx.pagesCount} · ${Fmt.dateTime(TrTime.now())}',
          style: const pw.TextStyle(fontSize: 7, color: dim),
        ),
      ],
    ),
  );

  /// Paylaşım menüsü (WhatsApp, e-posta, Dosyalar). Dönüş kilidi tetiklemez ([ExternalActivity]).
  static Future<bool> share(Uint8List bytes, String fileName) =>
      ExternalActivity.run(
        () => Printing.sharePdf(bytes: bytes, filename: fileName),
      );

  /// Yazdırma penceresi (AirPrint / Android yazdırma).
  static Future<bool> printDocument(Uint8List bytes, String name) =>
      ExternalActivity.run(
        () => Printing.layoutPdf(name: name, onLayout: (_) async => bytes),
      );
}

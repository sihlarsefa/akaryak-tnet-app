import 'package:akaryakitnet/core/pdf/akn_pdf.dart';
import 'package:akaryakitnet/core/utils/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'A4 belge: marka başlığı, Türkçe karakterler, tablo, toplam, imza',
    () async {
      final bytes = await AknPdf.buildA4(
        title: 'Sipariş Özeti',
        subtitle: 'Anadolu Lojistik A.Ş.',
        number: 'SIP-20261021-12002',
        date: DateTime.utc(2026, 10, 21, 11, 5),
        body: (t) => [
          AknPdf.section('Sipariş', [
            AknPdf.row('Ürün', 'Motorin'),
            AknPdf.row('Teslimat noktası', 'Tuzla Şantiye — İĞÜŞÖÇ ığüşöç'),
            AknPdf.row('Not', null),
          ]),
          AknPdf.table(
            headers: const ['Ürün', 'Litre', 'Birim fiyat', 'Tutar'],
            rows: [
              [
                'Motorin',
                Fmt.liters(8000),
                Fmt.unitPrice(42.35),
                Fmt.money(338800),
              ],
            ],
          ),
          AknPdf.totalBox(
            'Tahmini toplam',
            Fmt.money(338800),
            hint: 'KDV dahil',
          ),
          AknPdf.qr('SIP-20261021-12002'),
          AknPdf.signatures(const ['Teslim eden', 'Teslim alan']),
        ],
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(
        bytes.length,
        greaterThan(20000),
        reason: 'gömülü yazı tipi ve işaret',
      );
    },
  );
}

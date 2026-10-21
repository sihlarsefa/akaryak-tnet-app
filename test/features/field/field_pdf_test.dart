// Saha sipariş formu PDF'i (dış ve iç belge): sahte sunucunun belge JSON'undan üretilir; Türkçe
// karakterli A4 PDF, dosya adı, iç belgede maliyet bölümü.
import 'package:akaryakitnet/features/field/data/field_pdf.dart';
import 'package:akaryakitnet/features/field/data/field_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'field_test_kit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('dış ve iç sipariş formu PDF olarak üretilir', () async {
    final h = await FieldHarness.create();
    final c = h.container();
    addTearDown(() {
      c.dispose();
      h.dispose();
    });
    await loginAs(c, 'satis');
    final repo = c.read(fieldRepositoryProvider);

    final external = await repo.document(7001, internal: false);
    expect(external.isInternal, isFalse);
    expect(external.customer.title, 'Ege Tarım Kooperatifi');
    expect(external.lines, hasLength(2));
    final a = await FieldOrderPdf.build(external);
    expect(String.fromCharCodes(a.take(5)), '%PDF-');
    expect(a.length, greaterThan(20000), reason: 'gömülü Türkçe yazı tipi');
    expect(
      FieldOrderPdf.fileName(external),
      contains(RegExp(r'SSF-\d{8}-000007')),
    );
    expect(FieldOrderPdf.fileName(external), endsWith('.pdf'));

    final internal = await repo.document(7001, internal: true);
    expect(internal.isInternal, isTrue);
    expect(internal.internal!.lines, hasLength(2));
    final b = await FieldOrderPdf.build(internal);
    expect(String.fromCharCodes(b.take(5)), '%PDF-');
    expect(
      FieldOrderPdf.fileName(internal),
      isNot(FieldOrderPdf.fileName(external)),
    );
    expect(FieldOrderPdf.footerNote, contains('mali belge değildir'));
  });
}

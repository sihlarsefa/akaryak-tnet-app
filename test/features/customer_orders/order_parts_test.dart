// Tasarım v2 sipariş parçalarının saf yardımcıları: kısa bayi adı (plaka başlığı "Demir Petrol
// teklifi"), Türkçe belirtme hâli ("çek görselini"), ödeme cümlesi ("Çek ile, 30 gün vade"),
// büyük figür için tutar bölme ("338.800" + ",00") ve sipariş başlığı ("Motorin, 8.000 L").
import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/features/customer_orders/presentation/widgets/order_parts.dart';
import 'package:akaryakitnet/features/customer_orders/presentation/widgets/payment_block.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('kısa bayi adı: hukuki ekler ve sondaki sektör sözcüğü atılır', () {
    expect(shortCompany('Demir Petrol Akaryakıt Ltd. Şti.'), 'Demir Petrol');
    expect(shortCompany('Kuzey Enerji A.Ş.'), 'Kuzey Enerji');
    expect(shortCompany('Akaryakıt Ltd. Şti.'), 'Akaryakıt');
    expect(shortCompany('Körfez Nakliyat ve Ticaret'), 'Körfez Nakliyat');
    expect(shortCompany(null), '');
  });

  test(
    'belirtme hâli ünlü uyumuyla (belge adları iyelik ekli tamlamalardır)',
    () {
      expect(accusative('çek görseli'), 'çek görselini');
      expect(accusative('senet görseli'), 'senet görselini');
      expect(accusative('havale / eft dekontu'), 'havale / eft dekontunu');
      expect(accusative('dekont'), 'dekontu');
    },
  );

  test('tutar bölme ve sipariş başlığı', () {
    expect(splitMoney(338800), ('338.800', ',00'));
    expect(splitMoney(1263000.5), ('1.263.000', ',50'));
    expect(orderTitle('Motorin', 8000), 'Motorin, 8.000 L');
    expect(orderTitle(null, 2000), '2.000 L');
  });

  test('ödeme cümlesi: yöntem + vade / taksit; vadesiz yöntem "ile ödeme"', () {
    OrderDetail detail({String? code, int? term, int? inst}) =>
        OrderDetail.fromJson({
          'id': 1,
          'orderNumber': 'SIP-1',
          'status': 2,
          'quantityLiters': 8000,
          'productName': 'Motorin',
          'paymentMethodCode': code,
          'paymentTermDays': term,
          'paymentInstallments': inst,
        });
    expect(
      paymentSentenceOf(detail(code: 'CEK', term: 30)),
      'Çek ile, 30 gün vade',
    );
    expect(paymentSentenceOf(detail(code: 'HAVALE')), 'Havale / EFT ile ödeme');
    expect(paymentSentenceOf(detail(code: 'NAKIT')), 'Nakit');
    expect(
      paymentLineOf(detail(code: 'CEK', term: 30)),
      startsWith('Çek, 30 gün'),
    );
  });
}

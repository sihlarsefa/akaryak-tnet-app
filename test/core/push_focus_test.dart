// v4 tur 2 (L3): kilit ekranından, soğuk açılıştan ve balonun "Aç"ından açılan bildirim, Bildirimler'deki
// satırla aynı bloğu açar (`?focus=`): teklif, teslimat ya da talep. Bilgi veren olay rotasını korur.
import 'package:akaryakitnet/core/push/push_focus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('karar isteyen olaylar bloğuyla açılır', () {
    expect(
      withPushFocus('/orders/12002', 'order.quote_ready'),
      '/orders/12002?focus=quote',
    );
    expect(
      withPushFocus('/shipments/5003', 'shipment.reported'),
      '/shipments/5003?focus=delivery',
    );
    expect(
      withPushFocus('/approvals/9001', 'approval.pending'),
      '/approvals/9001?focus=request',
    );
    expect(
      withPushFocus('/bayi/orders/12009', 'order.created'),
      '/bayi/orders/12009?focus=quote',
    );
  });

  test(
    'teklif veremeyen için "Yeni sipariş" bilgidir; bilinmeyen olay ve rota olduğu gibi',
    () {
      expect(
        withPushFocus('/bayi/orders/12009', 'order.created', canQuote: false),
        '/bayi/orders/12009',
      );
      expect(
        withPushFocus('/orders/12003', 'shipment.dispatched'),
        '/orders/12003',
      );
      expect(
        withPushFocus('/notifications', 'approval.pending'),
        '/notifications',
      );
      expect(withPushFocus('/orders/12002', null), '/orders/12002');
      expect(
        withPushFocus('/orders/12002?focus=documents', 'order.quote_ready'),
        '/orders/12002?focus=documents',
      );
    },
  );
}

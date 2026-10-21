// Android bildirim kanalları (spec B.4, D.7.3): sunucunun kategori → kanal tablosuyla aynı kimlikler;
// bilinmeyen kategori yedek kanala (`akn_default`, sunucu `Push:AndroidChannelId`) düşer.
import 'package:akaryakitnet/core/push/local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('kategori kanalları sunucuyla aynı', () {
    const server = {
      'orders': ('akn_orders', 'Siparişler'),
      'quotes': ('akn_quotes', 'Teklifler'),
      'shipments': ('akn_shipments', 'Teslimatlar'),
      'approvals': ('akn_approvals', 'Onaylar'),
      'payments': ('akn_payments', 'Tahsilat'),
      'field': ('akn_field', 'Saha'),
      'system': ('akn_system', 'Sistem'),
    };
    server.forEach((category, expected) {
      final c = LocalNotifications.channelFor(category);
      expect(c.id, expected.$1, reason: category);
      expect(c.name, expected.$2, reason: category);
    });
    expect(LocalNotifications.channels, hasLength(server.length));
  });

  test('bilinmeyen kategori yedek kanala düşer', () {
    expect(LocalNotifications.channelFor('yeni').id, 'akn_default');
    expect(LocalNotifications.channelFor(null).id, 'akn_default');
    expect(LocalNotifications.fallback.id, LocalNotifications.channelId);
  });

  test('küçük simge beyaz » (drawable/ic_stat_akn)', () {
    expect(LocalNotifications.smallIcon, '@drawable/ic_stat_akn');
  });
}

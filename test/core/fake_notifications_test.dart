// v4 tur 2 (A9, B11, B17): sahte dünyanın bildirimleri uygulamanın geri kalanıyla çelişmez — yoldaki
// litre sevkiyatın litresi, teslim bildiriminin saati teslim saati, bayi kısa adıyla; karar isteyen
// bildirimde son saat önce gelir; şirket içi talep iki ürün ve iki noktadır.
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/utils/format.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:akaryakitnet/core/utils/turkish_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Roller v5 öncesi akış (eski sunucu, geçiş yapılmamış cari): şirket içi talep bildirimi (9003).
  final w = FakeWorld.seeded(companyApprovals: true);
  JsonMap note(String user, String code) => w.notifications.firstWhere(
    (n) => n['userId'] == 'u-$user' && n['eventCode'] == code,
  );

  test('yola çıktı: yoldaki sevkiyatın litresi ve varış saati', () {
    final moving = w.shipments.firstWhere((s) => s['status'] == 1);
    final body = note('musteri', 'shipment.dispatched')['body'] as String;
    expect(body, startsWith('${Fmt.liters(moving['plannedLiters'] as num)} '));
    expect(body, contains('10.000 L motorin'));
    expect(body, isNot(contains('20.000 L')));
    final arrival = TrTime.parseLocal(moving['scheduledAt'] as String?);
    expect(body, endsWith('Varış ${Fmt.time(arrival)}.'));
    // Yola çıkış varıştan önce.
    final left = TrTime.parseLocal(moving['dispatchedAt'] as String?)!;
    expect(left.isBefore(arrival!), isTrue);
  });

  test('teslimatı onaylayın: bildirim teslim anında, bayi kısa adıyla', () {
    final reported = w.shipments.firstWhere((s) => s['status'] == 2);
    final n = note('musteri', 'shipment.reported');
    expect(
      DateTime.parse(n['createdAt'] as String),
      TrTime.parseLocal(reported['deliveredAt'] as String?),
    );
    expect(n['body'], startsWith('Demir Petrol 11.950 L motorin teslim etti.'));
  });

  test('teklif hazır: son saat önce, bayi kısa adıyla, iki satıra sığar', () {
    final body = note('onay', 'order.quote_ready')['body'] as String;
    expect(
      body,
      matches(
        RegExp(
          r"^(yarın )?\d\d:\d\d'(y?[ae]) kadar karar verin: Demir Petrol, ",
        ),
      ),
    );
    expect(body, contains('Tuzla Şantiye için 8.000 L motorin teklifi'));
    expect(body, isNot(contains('Ltd.')));
    // Gece yarısını geçen son saat "yarın" der (6 harf daha).
    expect(body.length, lessThanOrEqualTo(body.startsWith('yarın') ? 92 : 86));
  });

  test('yeni sipariş (bayi): son saat önce, "teklif verin"', () {
    final n = note('sahip', 'order.created');
    expect(
      n['body'],
      matches(
        RegExp(
          r"^((yarın|bugün) )?\d\d:\d\d'(y?[ae]) kadar teklif verin: Körfez Nakliyat ",
        ),
      ),
    );
    expect(n['route'], startsWith('/bayi/orders/'));
  });

  test('şirket içi talep: iki ürün, iki nokta (B11)', () {
    expect(
      note('onay', 'approval.pending')['body'],
      'Burak Yılmaz 2 noktaya 30.000 L yakıt talep etti.',
    );
    final a = w.approval(9003)!;
    expect(a['summary'], startsWith('Motorin, Kalorifer Yakıtı · 30.000 L · '));
    expect(a['summary'], isNot(contains('Pendik')));
  });

  test('saatin yönelme eki ve firmanın kısa adı', () {
    expect(TurkishText.timeDative('08:26'), "08:26'ya");
    expect(TurkishText.timeDative('21:00'), "21:00'e");
    expect(TurkishText.timeDative('10:30'), "10:30'a");
    expect(TurkishText.timeDative('16:50'), "16:50'ye");
    expect(TurkishText.timeDative('10:00'), "10:00'a");
    expect(TurkishText.timeDative('11:15'), "11:15'e");
    expect(
      TurkishText.shortCompany('Demir Petrol Akaryakıt Ltd. Şti.'),
      'Demir Petrol',
    );
    expect(
      TurkishText.shortCompany('Körfez Nakliyat ve Ticaret'),
      'Körfez Nakliyat',
    );
    expect(Fmt.whole('Tuzla Şantiye'), 'Tuzla\u00A0Şantiye');
    expect(
      Fmt.whole('Çok uzun bir teslimat noktası adı burada'),
      'Çok uzun bir teslimat noktası adı burada',
    );
  });
}

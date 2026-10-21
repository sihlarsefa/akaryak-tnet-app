import 'dart:typed_data';

import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/network/app_failure.dart';
import 'package:akaryakitnet/core/network/fake/core_fakes.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/driver_harness.dart';

/// Sahte uçlar sunucu sözleşmesiyle (B7) aynı kuralları ve mesajları uygular.
void main() {
  late DriverHarness h;
  late ProviderContainer c;

  setUp(() async {
    h = await DriverHarness.create();
    c = h.container();
    await DriverHarness.login(c, 'sofor');
  });

  tearDown(() {
    c.dispose();
    h.dispose();
  });

  Future<JsonMap> post(String path, JsonMap body) => c
      .read(apiClientProvider)
      .post<JsonMap>(path, body: body, parse: JsonReader.asMap);

  Future<JsonMap> get(String path) =>
      c.read(apiClientProvider).get<JsonMap>(path, parse: JsonReader.asMap);

  int idWhere(int status) =>
      h.world.shipments.firstWhere(
            (s) => s['status'] == status && s['driverUserId'] == 'u-sofor',
          )['id']
          as int;

  Future<String> upload(int shipmentId, int kind) async {
    final dto = fakeAttachment(
      h.world,
      ownerType: 10,
      ownerId: shipmentId,
      kind: kind,
      fileName: 'x.jpg',
      contentType: 'image/jpeg',
      bytes: Uint8List.fromList(sampleJpeg),
    );
    return dto['publicId'] as String;
  }

  Matcher business(String message) => throwsA(
    isA<BusinessFailure>().having((f) => f.message, 'message', message),
  );

  test(
    'ayrıntı sözleşme alanları: zorunluluklar, eylemler, saat penceresi',
    () async {
      await get('driver/shipments');
      final id = idWhere(0);
      final d = JsonReader(await get('driver/shipments/$id'));
      expect(d.str('code'), 'SVK-${id.toString().padLeft(8, '0')}');
      expect(d.str('scheduledAt'), endsWith('+03:00'));
      expect(d.obj('requirements').boolean('photo'), isTrue);
      expect(d.obj('requirements').boolean('signature'), isTrue);
      expect(d.obj('actions').boolean('canStart'), isTrue);
      expect(d.obj('actions').boolean('canDeliver'), isFalse);
      expect(d.nonEmpty('windowStart'), isNotNull);
      expect(d.boolean('hasCoordinates'), isTrue);
    },
  );

  test(
    'yola çıkış: zaten yoldaysa aynı ayrıntı; teslim edilmişse hata',
    () async {
      await get('driver/shipments');
      final inTransit = idWhere(1);
      final again = await post('driver/shipments/$inTransit/start', {});
      expect(again['status'], 1);
      final disputed = idWhere(4);
      expect(
        post('driver/shipments/$disputed/start', {}),
        business('Bu sevkiyat zaten teslim edildi.'),
      );
    },
  );

  test('teslim kuralları: planlı, litre, başka sevkiyatın fotoğrafı', () async {
    await get('driver/shipments');
    final planned = idWhere(0);
    final id = idWhere(1);
    expect(
      post('driver/shipments/$planned/deliver', {
        'deliveredLiters': 10,
        'deliveryDocumentNo': 'A',
      }),
      business('Teslim bildirmek için önce yola çıkın.'),
    );
    expect(
      post('driver/shipments/$id/deliver', {
        'deliveredLiters': 999999,
        'deliveryDocumentNo': 'A',
      }),
      business('Teslim edilen litre planlanan litreyi aşamaz.'),
    );
    final foreign = await upload(planned, 30);
    expect(
      post('driver/shipments/$id/deliver', {
        'deliveredLiters': 100,
        'deliveryDocumentNo': 'A',
        'photoIds': [foreign],
      }),
      business(
        'Teslim fotoğraflarından biri bu sevkiyata ait değil ya da silinmiş; fotoğrafı yeniden ekleyin.',
      ),
    );
    final photo = await upload(id, 30);
    expect(
      post('driver/shipments/$id/deliver', {
        'deliveredLiters': 100,
        'deliveryDocumentNo': 'A',
        'photoIds': [photo],
        'signatureWaiver': {'reason': 3, 'note': 'a'},
        'latitude': 40.1,
        'longitude': 29.1,
      }),
      business(
        '"Diğer" seçildiğinde imzanın neden alınamadığını kısaca yazın.',
      ),
    );
  });

  test('cihaz saati makulse kullanılır, değilse sunucu saati', () async {
    await get('driver/shipments');
    final id = idWhere(1);
    final photo = await upload(id, 30);
    final sig = await upload(id, 31);
    final s0 = h.world.shipments.firstWhere((x) => x['id'] == id);
    s0['dispatchedAt'] = FakeWorld.local(
      DateTime.now().toUtc().subtract(const Duration(hours: 1)),
    );
    final device = DateTime.now().toUtc().subtract(const Duration(minutes: 3));
    await post('driver/shipments/$id/deliver', {
      'deliveredLiters': 9000,
      'deliveryDocumentNo': 'IRS-1',
      'photoIds': [photo],
      'signatureId': sig,
      'deviceTime': device.toIso8601String(),
    });
    final s = h.world.shipments.firstWhere((x) => x['id'] == id);
    expect(s['timeSource'], 'device');

    // Çok eski cihaz saati (72 saatten eski): sunucu saati.
    final other = idWhere(4);
    final p2 = await upload(other, 30);
    final s2 = await upload(other, 31);
    await post('driver/shipments/$other/deliver', {
      'deliveredLiters': 5000,
      'deliveryDocumentNo': 'IRS-2',
      'photoIds': [p2],
      'signatureId': s2,
      'deviceTime': DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 4))
          .toIso8601String(),
    });
    expect(
      h.world.shipments.firstWhere((x) => x['id'] == other)['timeSource'],
      'server',
    );

    // Aynı litre + irsaliye tekrar: 200 (çevrimdışı kuyruk tekrarı).
    final same = await post('driver/shipments/$id/deliver', {
      'deliveredLiters': 9000,
      'deliveryDocumentNo': 'irs-1',
    });
    expect(same['status'], 2);
    // Farklı: 409 already_reported.
    expect(
      post('driver/shipments/$id/deliver', {
        'deliveredLiters': 8000,
        'deliveryDocumentNo': 'IRS-1',
      }),
      throwsA(
        isA<ConflictFailure>().having(
          (f) => f.conflictCode,
          'code',
          'already_reported',
        ),
      ),
    );
  });

  test(
    'müşteri ve şoför olmayan erişim reddedilir; başka şoförün kaydı 404',
    () async {
      final customer = h.container(freshDevice: true);
      addTearDown(customer.dispose);
      await DriverHarness.login(customer, 'musteri');
      expect(
        customer
            .read(apiClientProvider)
            .get<Object?>('driver/shipments', parse: (j) => j),
        throwsA(isA<ForbiddenFailure>()),
      );
      final owner = h.container(freshDevice: true);
      addTearDown(owner.dispose);
      await DriverHarness.login(owner, 'sahip');
      await get('driver/shipments');
      final mine = idWhere(1);
      expect(
        owner
            .read(apiClientProvider)
            .get<Object?>('driver/shipments/$mine', parse: (j) => j),
        throwsA(isA<NotFoundFailure>()),
      );
    },
  );
}

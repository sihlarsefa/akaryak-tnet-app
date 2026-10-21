// Onaylarım akışları (spec D.3 A5 testleri): karar çubuğu yalnızca `modes`, zorunlu notlar, koşullu
// onay formu → yalnızca formun anahtarlarıyla `conditions` (her finans türü), çakışma → yenile,
// belirsiz sonuçta aynı Idempotency-Key, istenen türle ek bilgi yanıtı, cari görünümü, şirket içi
// talep sonucu ve "Merkeze ilet".
import 'package:akaryakitnet/core/models/enums.dart';
import 'package:akaryakitnet/core/network/network_providers.dart';
import 'package:akaryakitnet/features/approvals/fake/a5_fake_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'a5_test_kit.dart';

void main() {
  group('karar çubuğu yalnızca modes', () {
    testWidgets('saha formu kârlılık (satış müdürü): Onayla ve Reddet', (
      tester,
    ) async {
      await pumpA5(tester, persona: 'satis', location: '/approvals/9002');
      expect(find.text('Onayla'), findsOneWidget);
      expect(find.text('Reddet'), findsOneWidget);
      expect(find.text('Diğer'), findsNothing);
      expect(find.text('Ek bilgi iste'), findsNothing);
      expect(find.text('Koşullu onayla'), findsNothing);
      await finish(tester);
    });

    testWidgets(
      'sipariş finansı (finans): dört karar; ikisi "Diğer kararlar"da',
      (tester) async {
        await pumpA5(tester, persona: 'finans', location: '/approvals/9001');
        expect(find.text('Onayla'), findsOneWidget);
        expect(find.text('Reddet'), findsOneWidget);
        await tapText(tester, 'Diğer');
        expect(find.text('Diğer kararlar'), findsOneWidget);
        expect(find.text('Ek bilgi iste'), findsOneWidget);
        expect(find.text('Koşullu onayla'), findsOneWidget);
        await finish(tester);
      },
    );

    testWidgets('karar veremeyene decisionHint, çubuk yok', (tester) async {
      await pumpA5(tester, persona: 'finans', location: '/approvals/9010');
      expect(find.text('Limit talepleri merkezde onaylanır.'), findsOneWidget);
      expect(find.text('Onayla'), findsNothing);
      expect(find.text('Reddet'), findsNothing);
      await finish(tester);
    });
  });

  testWidgets('zorunlu notlar: ret gerekçesi boş ya da kısa gönderilmez', (
    tester,
  ) async {
    final app = await pumpA5(
      tester,
      persona: 'finans',
      location: '/approvals/9001',
    );
    await tapText(tester, 'Reddet');
    expect(find.text('Talebi reddet'), findsOneWidget);
    await tapText(tester, 'Reddet', last: true);
    expect(find.text('Reddetmek için gerekçe yazın.'), findsOneWidget);
    await typeInto(tester, 'Ret gerekçesi', 'kısa');
    await tapText(tester, 'Reddet', last: true);
    expect(find.text('Gerekçe en az 10 karakter olmalı.'), findsOneWidget);
    expect(app.log.all('POST', '/decide'), isEmpty);
    await typeInto(
      tester,
      'Ret gerekçesi',
      'Limit aşımı kabul edilemez; peşin ödeme isteyin.',
    );
    await tapText(tester, 'Reddet', last: true);
    final req = app.log.last('POST', 'approvals/9001/decide')!;
    expect((req.data as Map)['decision'], 4);
    expect(req.headers['Idempotency-Key'], isNotNull);
    expect(find.text('Talep reddedildi.'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('ek bilgi isteği: not zorunlu, istenen belge türü gönderilir', (
    tester,
  ) async {
    final app = await pumpA5(
      tester,
      persona: 'finans',
      location: '/approvals/9001',
    );
    await tapText(tester, 'Diğer');
    await tapText(tester, 'Ek bilgi iste');
    await tapText(tester, 'Ek bilgi iste', last: true);
    expect(find.text('Ne istediğinizi yazın.'), findsOneWidget);
    await tapText(tester, 'Çek görseli');
    await typeInto(tester, 'Ne istiyorsunuz', 'Çek görselini yükleyin.');
    await tapText(tester, 'Ek bilgi iste', last: true);
    final body = app.log.last('POST', 'approvals/9001/decide')!.data as Map;
    expect(body['decision'], 3);
    expect(body['requiredAttachmentKind'], AttachmentKind.chequeImage.code);
    expect(body.containsKey('conditions'), isFalse);
    await finish(tester);
  });

  group('koşullu onay formu → yalnızca formun anahtarları', () {
    Future<Map> conditional(
      WidgetTester tester,
      int id,
      Future<void> Function() fill,
    ) async {
      final app = await pumpA5(
        tester,
        persona: 'finans',
        location: '/approvals/$id',
      );
      await tapText(tester, 'Diğer');
      await tapText(tester, 'Koşullu onayla');
      expect(find.text('Koşullu onayla'), findsWidgets);
      await fill();
      await tapText(tester, 'Koşullu onayla', last: true);
      final body = app.log.last('POST', 'approvals/$id/decide')!.data as Map;
      expect(body['decision'], 2);
      return body['conditions'] as Map;
    }

    testWidgets('sipariş finansı: yöntem ve vade', (tester) async {
      final c = await conditional(tester, 9001, () async {
        await tapText(tester, 'Havale / EFT (peşin)');
        await typeInto(tester, 'Vade (gün)', '15');
      });
      expect(c, {'methodCode': 'HAVALE', 'termDays': 15});
      await finish(tester);
    });

    testWidgets('saha formu finansı: yalnızca vade', (tester) async {
      final c = await conditional(tester, 9006, () async {
        await typeInto(tester, 'Vade (gün)', '20');
      });
      expect(c, {'termDays': 20});
      await finish(tester);
    });

    testWidgets('yeni cari: limit ve risk sınıfı', (tester) async {
      final c = await conditional(tester, 9007, () async {
        await typeInto(tester, 'Onaylanan limit', '350000');
        await tapText(tester, 'C');
      });
      expect(c, {'limitAmount': 350000, 'riskClass': 3});
      await finish(tester);
    });

    testWidgets('ön kayıt: dönem ve teminat oranı', (tester) async {
      final c = await conditional(tester, 9008, () async {
        await tapText(tester, 'Haftalık');
        await typeInto(tester, 'Teminat oranı', '200');
      });
      expect(c, {'limitPeriod': 'Haftalık', 'collateralRatioPercent': 200});
      await finish(tester);
    });

    testWidgets('koşul ya da not olmadan gönderilmez', (tester) async {
      final app = await pumpA5(
        tester,
        persona: 'finans',
        location: '/approvals/9001',
      );
      await tapText(tester, 'Diğer');
      await tapText(tester, 'Koşullu onayla');
      await tapText(tester, 'Koşullu onayla', last: true);
      expect(
        find.text(
          'En az bir koşulu değiştirin ya da koşulu karar notuna yazın.',
        ),
        findsOneWidget,
      );
      expect(app.log.all('POST', '/decide'), isEmpty);
      await finish(tester);
    });
  });

  testWidgets(
    'çakışma (409): "Bu kayıt sizden sonra güncellendi" → Yenile → yeniden',
    (tester) async {
      final app = await pumpA5(
        tester,
        persona: 'finans',
        location: '/approvals/9001',
      );
      // Başka bir kullanıcı talebi değiştirdi.
      A5FakeStore.of(app.server.world).approvalExtras[9001]!.token =
          'baska-surum';
      await tapText(tester, 'Onayla');
      await typeInto(tester, 'Karar notu', 'Uygun.');
      await tapText(tester, 'Onayla', last: true);
      expect(find.text('Bu kayıt sizden sonra güncellendi'), findsOneWidget);
      await tapText(tester, 'Yenile');
      expect(find.text('Bu kayıt sizden sonra güncellendi'), findsNothing);
      // Yazılan not korunur; güncel sürümle tekrar gönderilir.
      expect(find.text('Uygun.'), findsOneWidget);
      await tapText(tester, 'Onayla', last: true);
      expect(find.text('Talep onaylandı.'), findsOneWidget);
      final decides = app.log.all('POST', 'approvals/9001/decide');
      expect(decides, hasLength(2));
      expect(
        decides.first.headers['Idempotency-Key'],
        isNot(decides.last.headers['Idempotency-Key']),
      );
      await finish(tester);
    },
  );

  testWidgets('zaman aşımı sonrası aynı anahtarla tekrar (satış müdürü)', (
    tester,
  ) async {
    final app = await pumpA5(
      tester,
      persona: 'satis',
      location: '/approvals/9002',
    );
    var failed = false;
    app.container
        .read(dioProvider)
        .interceptors
        .add(
          InterceptorsWrapper(
            onResponse: (r, h) {
              if (!failed && r.requestOptions.path.contains('/decide')) {
                failed = true;
                h.reject(
                  DioException.receiveTimeout(
                    timeout: const Duration(seconds: 30),
                    requestOptions: r.requestOptions,
                  ),
                );
                return;
              }
              h.next(r);
            },
          ),
        );
    await tapText(tester, 'Onayla');
    await tapText(tester, 'Onayla', last: true);
    await pumpFor(tester);
    final decides = app.log.all('POST', 'approvals/9002/decide');
    expect(decides.length, greaterThanOrEqualTo(2));
    final keys = decides.map((d) => d.headers['Idempotency-Key']).toSet();
    expect(keys, hasLength(1), reason: 'belirsiz sonuçta aynı anahtar');
    final store = A5FakeStore.of(app.server.world);
    final approvals = store.approvalExtras[9002]!.events.where(
      (e) => e['eventType'] == ApprovalEventKind.approved.code,
    );
    expect(approvals, hasLength(1), reason: 'karar ikinci kez kaydedilmez');
    expect(find.text('Talep onaylandı.'), findsOneWidget);
    await finish(tester);
  });

  group('ek bilgi yanıtı (cari)', () {
    testWidgets(
      'istenen tür önceden seçili yüklenir; yanıt gider; durum "Bayi değerlendirmesi"',
      (tester) async {
        final app = await pumpA5(
          tester,
          persona: 'musteri',
          location: '/approvals/9005',
        );
        expect(find.text('Sizden ek bilgi istendi'), findsOneWidget);
        expect(
          find.textContaining('İstenen belge: Çek görseli'),
          findsOneWidget,
        );
        await tapText(tester, 'Çek görseli ekle');
        expect(app.files.lastKind, AttachmentKind.chequeImage);
        final upload = app.log.last('POST', 'attachments')!;
        final fields = {
          for (final f in (upload.data as FormData).fields) f.key: f.value,
        };
        expect(
          fields['ownerType'],
          '${AttachmentOwnerType.approvalRequest.code}',
        );
        expect(fields['ownerId'], '9005');
        expect(fields['kind'], '${AttachmentKind.chequeImage.code}');
        expect(find.textContaining('İstenen belge eklendi'), findsOneWidget);
        await typeInto(tester, 'Yanıtınız', 'Çek görseli eklendi.');
        await tapText(tester, 'Yanıtla');
        final reply = app.log.last('POST', 'approvals/9005/provide-info')!;
        expect((reply.data as Map)['note'], 'Çek görseli eklendi.');
        expect((reply.data as Map)['resume'], isFalse);
        await pumpFor(tester);
        expect(find.text('Bayi değerlendirmesi'), findsWidgets);
        expect(find.text('Sizden ek bilgi istendi'), findsNothing);
        await finish(tester);
      },
    );

    testWidgets('istenen belge eklenmeden yanıtlarken uyarır', (tester) async {
      final app = await pumpA5(
        tester,
        persona: 'musteri',
        location: '/approvals/9005',
      );
      await typeInto(tester, 'Yanıtınız', 'Görseli yarın ileteceğiz.');
      await tapText(tester, 'Yanıtla');
      expect(find.text('İstenen belge eklenmedi'), findsOneWidget);
      await tapText(tester, 'Vazgeç');
      expect(app.log.all('POST', 'provide-info'), isEmpty);
      await finish(tester);
    });

    testWidgets('cari görünümü SLA, kademe ve adımları göstermez', (
      tester,
    ) async {
      await pumpA5(tester, persona: 'musteri', location: '/approvals/9005');
      expect(find.textContaining('Kalan'), findsNothing);
      expect(find.textContaining('Kademe'), findsNothing);
      expect(find.text('Onay adımları'), findsNothing);
      expect(find.text('Olay günlüğü'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Süreç'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Süreç'), findsOneWidget);
      expect(find.textContaining('Risk'), findsNothing);
      await finish(tester);
    });
  });

  testWidgets('onaylayan tarafı: "Bilgi alındı" talebi incelemeye alır', (
    tester,
  ) async {
    final app = await pumpA5(
      tester,
      persona: 'finans',
      location: '/approvals/9004',
    );
    expect(find.textContaining('Ek bilgi bekleniyor'), findsOneWidget);
    await tapText(tester, 'Bilgi alındı');
    await tapText(tester, 'İncelemeye al');
    final body =
        app.log.last('POST', 'approvals/9004/provide-info')!.data as Map;
    expect(body['resume'], isTrue);
    expect(find.textContaining('yeniden incelemede'), findsOneWidget);
    await finish(tester);
  });

  testWidgets(
    'şirket içi talep onayı: satır sonuçları ve başarısızları aktar',
    (tester) async {
      final app = await pumpA5(
        tester,
        persona: 'onay',
        location: '/approvals/9003',
      );
      await tapText(tester, 'Onayla');
      await tapText(tester, 'Onayla', last: true);
      await pumpFor(tester);
      expect(find.text('Talep sonucu'), findsOneWidget);
      expect(
        find.text('1 sipariş oluşturuldu · 1 satır oluşturulamadı'),
        findsOneWidget,
      );
      expect(app.log.last('GET', 'order-requests/3001'), isNotNull);
      await tapText(tester, 'Başarısız satırları yeni siparişe aktar');
      expect(find.text('stub:/orders/new?fromRequest=3001'), findsOneWidget);
      await finish(tester);
    },
  );

  group('ön kayıt "Merkeze ilet"', () {
    testWidgets('finans (approve.finance.lead): görünür ve iletir', (
      tester,
    ) async {
      final app = await pumpA5(
        tester,
        persona: 'finans',
        location: '/approvals/9009',
      );
      expect(find.text('Merkeze ilet'), findsOneWidget);
      await tapText(tester, 'Merkeze ilet');
      await tapText(tester, 'Merkeze ilet', last: true);
      expect(app.log.last('POST', 'leads/8003/forward-hq'), isNotNull);
      expect(find.text('Ön kayıt merkez onayına iletildi.'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('yetkinliği olmayan (satış müdürü) görmez', (tester) async {
      await pumpA5(tester, persona: 'satis', location: '/approvals/9009');
      expect(find.text('Merkeze ilet'), findsNothing);
      await finish(tester);
    });
  });

  testWidgets('liste: tür süzgeci sorguya gider, satır ayrıntıyı açar', (
    tester,
  ) async {
    final app = await pumpA5(tester, persona: 'finans', location: '/approvals');
    await tapText(tester, 'Ön kayıt');
    final req = app.log.last('GET', '/approvals')!;
    expect(req.queryParameters['type'], ApprovalType.leadFinance.code);
    expect(find.textContaining('Akdeniz Gıda'), findsWidgets);
    await tapText(tester, 'Akdeniz Gıda');
    expect(find.text('Ön kayıt finans onayı'), findsWidgets);
    await finish(tester);
  });

  testWidgets('çevrimdışı: karar düğmeleri kapalı', (tester) async {
    await pumpA5(
      tester,
      persona: 'finans',
      location: '/approvals/9001',
      overrides: [offlineOverride],
    );
    expect(
      find.text('Çevrimdışısınız; karar vermek için bağlantı gerekli.'),
      findsOneWidget,
    );
    await finish(tester);
  });
}

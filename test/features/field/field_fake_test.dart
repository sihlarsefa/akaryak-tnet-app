// Saha sahte uçları + istemci modelleri (spec B.9): kapsam, skip/take, barem bandı (maliyetsiz /
// maliyetli), gönderim, onay senkronu, ön kayıt kuralları. Ağ yok.
import 'dart:typed_data';

import 'package:akaryakitnet/core/models/enums.dart';
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/network/app_failure.dart';
import 'package:akaryakitnet/core/network/fake/core_fakes.dart';
import 'package:akaryakitnet/features/field/data/field_models.dart';
import 'package:akaryakitnet/features/field/data/field_repository.dart';
import 'package:akaryakitnet/features/field/fake/field_fake_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'field_test_kit.dart';

void main() {
  late FieldHarness h;
  late ProviderContainer c;
  late RequestLog log;
  final opened = <(FieldHarness, ProviderContainer)>[];

  FieldRepository repo() => c.read(fieldRepositoryProvider);

  Future<void> as(String persona) async {
    h = await FieldHarness.create();
    c = h.container();
    opened.add((h, c));
    log = RequestLog()..attach(c);
    await loginAs(c, persona);
  }

  tearDown(() {
    for (final (harness, container) in opened) {
      container.dispose();
      harness.dispose();
    }
    opened.clear();
  });

  group('formlar · kapsam ve sayfalama', () {
    test('temsilci yalnızca kendi formlarını, maliyetsiz görür', () async {
      await as('saha');
      final page = await repo().forms(const FieldFormsQuery());
      expect(page.includeCosts, isFalse);
      expect(page.items.map((f) => f.id).toSet(), {
        7001,
        7002,
        7003,
        6998,
        7005,
        7008,
        7009,
      });
      expect(page.totalCount, 7);
    });

    test(
      'satış müdürü ekibin formlarını maliyetli görür; temsilciye göre süzer',
      () async {
        await as('satis');
        final all = await repo().forms(const FieldFormsQuery());
        expect(all.includeCosts, isTrue);
        expect(all.totalCount, 9);
        final murat = await repo().forms(
          const FieldFormsQuery(salesRepresentativeId: 32),
        );
        expect(murat.items.map((f) => f.id).toSet(), {7006, 7007});
      },
    );

    test(
      'durum süzgeci tekrarlanan anahtarla gider; skip/take sayfalar',
      () async {
        await as('satis');
        final state = h.state;
        for (var i = 0; i < 30; i++) {
          state.forms.add(
            state.newForm(
              id: 7200 + i,
              number: 'SSF-TEST-${i.toString().padLeft(6, '0')}',
              customerId: 101,
              createdBy: 'u-mudur',
              repId: 32,
              createdAt: DateTime.now().toUtc().subtract(Duration(minutes: i)),
              lines: [
                state.newLine(
                  productId: 1,
                  deliveryPointId: 1001,
                  liters: 1000,
                  price: 42,
                ),
              ],
            ),
          );
        }
        final first = await repo().forms(const FieldFormsQuery(statuses: [0]));
        final q = log.last('GET', 'field-orders')!.uri;
        expect(q.queryParametersAll['statuses'], ['0']);
        expect(q.queryParameters['skip'], '0');
        expect(q.queryParameters['take'], '25');
        expect(first.items, hasLength(25));
        expect(first.totalCount, 32); // 30 yeni + 7007 + 7009 taslak
        final second = await repo().forms(
          const FieldFormsQuery(statuses: [0]),
          skip: 25,
        );
        expect(
          log.last('GET', 'field-orders')!.uri.queryParameters['skip'],
          '25',
        );
        expect(second.items, hasLength(7));
        expect({
          ...first.items.map((f) => f.id),
          ...second.items.map((f) => f.id),
        }, hasLength(32));

        await repo().forms(const FieldFormsQuery(statuses: [1, 2]));
        expect(
          log.last('GET', 'field-orders')!.uri.queryParametersAll['statuses'],
          ['1', '2'],
        );
      },
    );

    test(
      'portföy skip/take ile gelir; temsilci olmayana iş kuralı hatası',
      () async {
        await as('saha');
        final p = await repo().portfolio(take: 1);
        expect(p.totalCount, 2);
        expect(p.items, hasLength(1));
        final uri = log.last('GET', 'me/portfolio')!.uri;
        expect(uri.queryParameters['skip'], '0');
        expect(uri.queryParameters['take'], '1');
        final rest = await repo().portfolio(skip: 1, take: 1);
        expect(rest.items.single.customerId, isNot(p.items.single.customerId));
      },
    );

    test('temsilci kaydı olmayan kullanıcıda portföy hata verir', () async {
      await as('satis');
      await expectLater(repo().portfolio(), throwsA(isA<BusinessFailure>()));
    });

    test('temsilci listesi: temsilciye boş, müdüre pasif işaretli', () async {
      await as('saha');
      expect(await repo().reps(), isEmpty);
      await as('satis');
      final reps = await repo().reps();
      expect(reps.map((r) => r.name), ['Deniz Koç', 'Murat Şen', 'Selda Ak']);
      expect(reps.last.isInactive, isTrue);
    });
  });

  group('önizleme · barem bandı', () {
    Future<FieldPreview> preview(JsonMap req) => repo().preview(req);

    test('temsilci bandı görür, maliyet alanları gelmez', () async {
      await as('saha');
      final p = await preview(formRequest());
      expect(p.showCosts, isFalse);
      expect(p.band.key, 'ok');
      expect(p.band.label, 'Otomatik onay');
      expect(p.band.hint, 'Form gönderilince doğrudan siparişe dönüşür.');
      expect(p.lines.single.profitPercent, isNull);
      expect(p.lines.single.costM3, isNull);
      expect(p.chip, isNull);
      expect(p.formProfitPercent, isNull);
      expect(p.totalAmount, closeTo(336800, 0.01));
      expect(p.limitBlocking, isFalse);
      expect(p.financeRequired, isFalse);
    });

    test(
      'eşikler: İdeal %6 / Mümkün %5 / Min %4 / ret / gerekçeli istisna',
      () async {
        await as('saha');
        expect((await preview(formRequest(price: 41.70))).band.key, 'mid');
        final low = await preview(formRequest(price: 41.30));
        expect(low.band.key, 'low');
        expect(low.band.label, 'Üst onay');
        final reject = await preview(formRequest(price: 40.90));
        expect(reject.band.isReject, isTrue);
        expect(reject.band.label, 'Otomatik ret');
        final shortReason = await preview(
          formRequest(price: 40.90, exception: true, justification: 'kısa'),
        );
        expect(shortReason.band.key, 'reject');
        final exception = await preview(
          formRequest(
            price: 40.90,
            exception: true,
            justification:
                'Stratejik müşteri; yıllık anlaşma görüşmesi sürüyor.',
          ),
        );
        expect(exception.band.key, 'exception');
        expect(exception.band.label, 'İstisna onayı');
      },
    );

    test(
      'vade valörü kârı düşürür; 90 günü aşan vade üst onaya çıkar',
      () async {
        await as('saha');
        // 30 gün açık hesap: %6,31 − 30 × 0,04 = %5,11 → yönetici.
        final p30 = await preview(formRequest(method: 'ACIK_HESAP', term: 30));
        expect(p30.band.key, 'mid');
        expect(p30.financeRequired, isTrue);
        expect(p30.financeReasons.single, contains('Vadeli yöntem'));
        final p120 = await preview(
          formRequest(price: 47, method: 'ACIK_HESAP', term: 120),
        );
        expect(p120.band.key, 'low');
        expect(p120.band.hint, contains('Barem dışı koşul'));
      },
    );

    test(
      'bayat Tüpraş referansı uyarı ekler ve otomatik onayı kapatır',
      () async {
        await as('saha');
        final p = await preview(formRequest(location: 'KIRIKKALE', price: 43));
        expect(
          p.notices.single,
          contains('Bugünkü Tüpraş referans fiyatı girilmedi'),
        );
        expect(p.band.key, 'mid');
        expect(p.hint, isNot(contains('Bugünkü Tüpraş')));
      },
    );

    test(
      'Tüpraş fiyatını düşürmek otomatik onayı kapatır ve satırı işaretler',
      () async {
        await as('saha');
        final p = await preview(formRequest(tupras: 36000));
        expect(p.overriddenLines, [1]);
        expect(p.band.key, 'mid');
      },
    );

    test('maliyet görebilen satış müdürü kâr ve maliyeti görür', () async {
      await as('satis');
      final p = await preview(formRequest());
      expect(p.showCosts, isTrue);
      expect(p.lines.single.profitPercent, closeTo(6.31, 0.01));
      expect(p.lines.single.costM3, closeTo(39600, 0.01));
      expect(p.chip, contains('İdeal %6'));
      expect(p.formProfitPercent, closeTo(6.31, 0.01));
    });

    test('litre limiti aşılınca gönderimi engelleyen limit mesajı', () async {
      await as('saha');
      final p = await preview(formRequest(liters: 200000));
      expect(p.limitBlocking, isTrue);
      expect(p.limitMessage, startsWith('Aylık limit aşılıyor'));
      expect(p.blockingReason, p.limitMessage);
      expect(p.financeRequired, isTrue);
    });
  });

  group('formlar · kayıt ve gönderim', () {
    test(
      'taslak (Idempotency-Key) → gönder → otomatik onay → sipariş',
      () async {
        await as('saha');
        final ordersBefore = h.server.world.orders.length;
        final form = await repo().createForm(
          formRequest(),
          idempotencyKey: 'k-1',
        );
        expect(form.status, FieldOrderFormStatus.draft);
        expect(form.formNumber, startsWith('SSF-'));
        // Aynı anahtar + aynı gövde: ikinci form açılmaz.
        final again = await repo().createForm(
          formRequest(),
          idempotencyKey: 'k-1',
        );
        expect(again.id, form.id);
        expect(h.state.forms.where((f) => f['id'] == form.id), hasLength(1));

        final result = await repo().submitForm(
          form.id,
          concurrencyToken: form.concurrencyToken,
          idempotencyKey: 's-1',
        );
        expect(idempotencyKeyOf(log.last('POST', '/submit')!), 's-1');
        expect(result.status, FieldOrderFormStatus.converted);
        expect(result.autoApproved, isTrue);
        expect(result.convertedOrderIds, hasLength(1));
        expect(h.server.world.orders.length, ordersBefore + 1);
        final detail = await repo().form(form.id);
        expect(detail.orders.single.orderId, result.convertedOrderIds.single);
      },
    );

    test('yönetici bandı onaya düşer; Onaylarım kararı forma yansır', () async {
      await as('saha');
      final form = await repo().createForm(formRequest(price: 41.70));
      final r = await repo().submitForm(form.id, idempotencyKey: 's-2');
      expect(r.status, FieldOrderFormStatus.pendingApproval);
      expect(r.requiredApprovalLevel, 1);
      final approval = h.server.world.approvals.lastWhere(
        (a) => a['subjectId'] == form.id,
      );
      expect(approval['id'], greaterThanOrEqualTo(9601));
      expect(approval['type'], 1);
      expect(approval['eligibleUserIds'], contains('u-satis'));
      // Onaylarım'da onaylandı.
      approval['status'] = 1;
      final after = await repo().form(form.id);
      expect(after.form.status, FieldOrderFormStatus.converted);
    });

    test(
      'vadeli çek finans onayı ister; ek bilgi istenince "Yanıtla" açılır',
      () async {
        await as('saha');
        final form = await repo().createForm(
          formRequest(method: 'CEK', term: 30, price: 43.60),
        );
        final r = await repo().submitForm(form.id);
        expect(r.status, FieldOrderFormStatus.approved);
        expect(r.financeStatus, OrderFinanceStatus.pending);
        final detail = await repo().form(form.id);
        final fa = detail.form.financeApprovalRequestId!;
        h.server.world.approval(fa)!['status'] = 4;
        final info = await repo().form(form.id);
        expect(info.form.financeInfoOpen, isTrue);
        expect(info.form.financeStatus, OrderFinanceStatus.infoRequested);
      },
    );

    test('düşük kâr otomatik reddedilir', () async {
      await as('saha');
      final form = await repo().createForm(formRequest(price: 40.90));
      final r = await repo().submitForm(form.id);
      expect(r.status, FieldOrderFormStatus.rejected);
      expect(r.autoRejected, isTrue);
    });

    test('eşzamanlılık belirteci eskiyse sunucu metni döner', () async {
      await as('saha');
      final form = await repo().createForm(formRequest());
      await repo().updateForm(form.id, {
        ...formRequest(liters: 9000),
        'concurrencyToken': form.concurrencyToken,
      });
      await expectLater(
        repo().updateForm(form.id, {
          ...formRequest(liters: 9500),
          'concurrencyToken': form.concurrencyToken,
        }),
        throwsA(
          isA<BusinessFailure>().having(
            (f) => f.message,
            'message',
            'Form bu arada başka biri tarafından değiştirildi. Sayfayı yenileyip tekrar deneyin.',
          ),
        ),
      );
    });

    test('portföy dışı cari reddedilir', () async {
      await as('saha');
      await expectLater(
        repo().createForm(formRequest(customerId: 101, pointId: 1001)),
        throwsA(
          isA<BusinessFailure>().having(
            (f) => f.message,
            'message',
            'Bu cari portföyünüzde değil.',
          ),
        ),
      );
    });

    test(
      'dönüşüm hatası: yeniden dene yalnızca FieldApprovals:Duzenler',
      () async {
        await as('saha');
        final f = (await repo().form(7008)).form;
        expect(f.conversionError, startsWith('Teslimat noktası için uygun'));
        expect(f.decisionText, 'Fiyat uygun.');
        await expectLater(
          repo().retryConversion(7008),
          throwsA(isA<ForbiddenFailure>()),
        );
        await as('satis');
        final r = await repo().retryConversion(7008);
        expect(r.status, FieldOrderFormStatus.converted);
        final after = (await repo().form(7008)).form;
        expect(after.conversionError, isNull);
        expect(after.decisionText, 'Fiyat uygun.');
      },
    );

    test('iç sipariş formu yalnızca maliyet görene', () async {
      await as('saha');
      final ext = await repo().document(7001, internal: false);
      expect(ext.isInternal, isFalse);
      expect(ext.lines, hasLength(2));
      await expectLater(
        repo().document(7001, internal: true),
        throwsA(isA<ForbiddenFailure>()),
      );
      await as('satis');
      final internal = await repo().document(7001, internal: true);
      expect(internal.isInternal, isTrue);
    });

    test('taslak e-postayla gönderilemez', () async {
      await as('saha');
      await expectLater(
        repo().emailDocument(7009),
        throwsA(isA<BusinessFailure>()),
      );
      expect(await repo().emailDocument(7001), contains('sıraya alındı'));
    });
  });

  group('ön kayıtlar', () {
    test('scope=all: temsilciye 403, finans ve satış müdürüne tümü', () async {
      await as('saha');
      final mine = await repo().leads(const LeadsQuery());
      expect(mine.items.map((l) => l.id).toSet(), {
        8001,
        8002,
        8003,
        8005,
        8006,
      });
      await expectLater(
        repo().leads(const LeadsQuery(all: true)),
        throwsA(isA<ForbiddenFailure>()),
      );
      await as('finans');
      final all = await repo().leads(const LeadsQuery(all: true));
      expect(all.totalCount, 6);
      expect(log.last('GET', 'leads')!.uri.queryParameters['scope'], 'all');
      final info = await repo().leads(
        const LeadsQuery(all: true, status: 'info'),
      );
      expect(info.items.single.id, 8001);
    });

    test('VKN denetimi: biçim, bayide kayıtlı, başka bayide kayıtlı', () async {
      await as('saha');
      final valid = FieldFakeState.vkn('123456789');
      final wrong = '${valid.substring(0, 9)}${(int.parse(valid[9]) + 1) % 10}';
      final bad = await repo().checkDuplicate(wrong);
      expect(bad.formatError, 'VKN doğrulanamadı; numarayı kontrol edin.');
      final short = await repo().checkDuplicate('12345');
      expect(short.formatError, 'VKN 10, TCKN 11 haneli olmalıdır.');
      expect((await repo().checkDuplicate(valid)).formatError, isNull);
      final here = await repo().checkDuplicate('1234567808');
      expect(here.linkedInThisStation, isTrue);
      expect(here.blocksSubmit, isTrue);
      final elsewhere = await repo().checkDuplicate(
        FieldFakeState.vkn('765432109'),
        excludeId: 8003,
      );
      expect(elsewhere.existsElsewhere, isTrue);
      expect(elsewhere.blocksSubmit, isFalse);
      final open = await repo().checkDuplicate(FieldFakeState.vkn('481516234'));
      expect(open.openLeadNumber, 'ONK-00012');
    });

    test('seçenekler: web KVKK cümlesi ve zorunlu vergi levhası', () async {
      await as('saha');
      final o = await repo().leadOptions();
      expect(
        o.kvkkText,
        'Firma yetkilisi, kişisel verilerinin cari açılışı, finansal değerlendirme (risk raporu dahil) ve '
        'iletişim amacıyla bayi ve AkaryakıtNet tarafından işlenmesine açık rıza verdi.',
      );
      expect(o.kvkkMethods.first, 'Islak imzalı form');
      expect(o.requiredKinds.single, AttachmentKind.taxPlate);
    });

    test('eksik ön kayıt finansa gönderilemez (sunucu metni)', () async {
      await as('saha');
      final saved = await repo().createLead({
        'companyTitle': 'Deneme Ltd.',
        'taxNumber': '',
      }, idempotencyKey: 'l-1');
      expect(saved.created, isTrue);
      expect(saved.leadNumber, startsWith('ONK-'));
      await expectLater(
        repo().submitLead(saved.id, concurrencyToken: saved.concurrencyToken),
        throwsA(
          isA<BusinessFailure>().having(
            (f) => f.message,
            'message',
            'Finansa göndermek için eksik: VKN / TCKN zorunludur, Vergi dairesi, '
                'İl, İlçe, En az bir yetkili, En az bir ürün için aylık litre, '
                'KVKK açık rızası, Vergi levhası (Evrak).',
          ),
        ),
      );
    });

    test(
      'ek bilgi istenen ön kayıt yeniden gönderilince aynı talep açılır',
      () async {
        await as('saha');
        final world = h.server.world;
        final detail = await repo().lead(8001);
        expect(detail.status, LeadStatus.infoRequested);
        expect(detail.canSubmit, isTrue);
        expect(detail.hasTaxPlate, isFalse);
        await expectLater(
          repo().submitLead(8001),
          throwsA(
            isA<BusinessFailure>().having(
              (f) => f.message,
              'message',
              'Finansa göndermek için eksik: Vergi levhası (Evrak).',
            ),
          ),
        );
        // Yeni vergi levhası yüklendi (ek bilgi yanıtı).
        fakeAttachment(
          world,
          ownerType: AttachmentOwnerType.customerLead.code,
          ownerId: 8001,
          kind: AttachmentKind.taxPlate.code,
          fileName: 'levha.png',
          contentType: 'image/png',
          bytes: Uint8List.fromList(samplePng),
        );
        expect(
          await repo().submitLead(8001),
          'Ön kayıt finans onayına gönderildi.',
        );
        expect(world.approval(9004)!['status'], 0);
        final after = await repo().lead(8001);
        expect(after.status, LeadStatus.submitted);
        expect(after.approvalRequestId, 9004);
        expect(after.canEdit, isFalse);
      },
    );

    test('istatistik: dönüşüm oranı', () async {
      await as('saha');
      final s = await repo().leadStats();
      expect(s.total, 5);
      expect(s.draft, 1);
      expect(s.converted, 1);
      expect(s.submitted, 4);
      expect(s.conversionRatePercent, 25);
    });

    test(
      'merkeze iletme yalnızca başka bayide kayıtlı ve finansta bekleyen',
      () async {
        await as('finans');
        final d = await repo().lead(8003);
        expect(d.existsElsewhere, isTrue);
        await expectLater(
          repo().forwardLeadToHq(8002),
          throwsA(isA<BusinessFailure>()),
        );
        expect(
          await repo().forwardLeadToHq(8003),
          'Ön kayıt merkez onayına iletildi.',
        );
        expect((await repo().lead(8003)).isForwardedToHq, isTrue);
      },
    );
  });
}

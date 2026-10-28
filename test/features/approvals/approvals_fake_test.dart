// A5 sahte deposunun sözleşme davranışı (spec §B.8 ve contract-changes B5): modlar, cari görünümü
// ayıklaması, karar kuralları (belirteç, not, koşul anahtarları), kademeli onay, şirket içi talep
// sonucu ve tahsilat geçişleri. Modellerin sahte JSON'dan okunması da burada denenir.
import 'package:akaryakitnet/core/models/enums.dart';
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/network/fake/fake_personas.dart';
import 'package:akaryakitnet/core/network/fake/fake_server.dart';
import 'package:akaryakitnet/core/network/fake/fake_world.dart';
import 'package:akaryakitnet/features/approvals/data/approval_models.dart';
import 'package:akaryakitnet/features/approvals/fake/a5_fake_store.dart';
import 'package:akaryakitnet/features/finance/data/finance_models.dart';
import 'package:akaryakitnet/features/payments/data/payment_models.dart';
import 'package:flutter_test/flutter_test.dart';

FakePersona p(String key) => findFakePersona(key)!;

Matcher fakeStatus(int status, {String? code, String? field}) =>
    isA<FakeResponse>()
        .having((r) => r.status, 'status', status)
        .having((r) => (r.body as Map?)?['code'], 'code', code ?? anything)
        .having(
          (r) => ((r.body as Map?)?['errors'] as Map?)?.keys,
          'errors',
          field == null ? anything : contains(field),
        );

void main() {
  late FakeWorld world;
  late A5FakeStore store;

  setUp(() {
    world = FakeWorld.seeded();
    store = A5FakeStore.of(world);
  });

  ApprovalDetail detail(String persona, int id) =>
      ApprovalDetail.fromJson(store.detail(p(persona), world.approval(id)!));

  group('ayrıntı', () {
    test('finans: sipariş finansında dört karar ve yöntem / vade formu', () {
      final d = detail('finans', 9001);
      expect(d.modes, [
        ApprovalDecision.approve,
        ApprovalDecision.conditionalApprove,
        ApprovalDecision.requestInfo,
        ApprovalDecision.reject,
      ]);
      expect(d.modeLabels, hasLength(4));
      expect(d.conditionForm!.keys, {'methodCode', 'termDays'});
      expect(d.conditionForm!.fields.first.current, 'CEK');
      expect(d.customerView, isFalse);
      expect(d.summary.facts.map((f) => f.label), contains('Risk sınıfı'));
      expect(d.summary.warnings, isNotEmpty);
      expect(d.summary.links.stationCustomerId, 502);
      expect(d.concurrencyToken, isNotEmpty);
      expect(d.decisionHint, isNull);
      expect(d.row.createdAt!.isUtc, isTrue);
    });

    test('kredi formu türe göre değişir (yeni cari %100, ön kayıt %500)', () {
      final onboarding = detail('finans', 9007).conditionForm!;
      final lead = detail('finans', 9008).conditionForm!;
      const credit = {
        'limitAmount',
        'limitPeriod',
        'maxTermDays',
        'allowedMethodCodes',
        'riskClass',
        'collateralRatioPercent',
        'nextReviewDate',
      };
      expect(onboarding.keys, credit);
      expect(lead.keys, credit);
      double max(ConditionForm f) =>
          f.fields.firstWhere((x) => x.key == 'collateralRatioPercent').max!;
      expect(max(onboarding), 100);
      expect(max(lead), 500);
      expect(
        onboarding.fields.firstWhere((x) => x.key == 'riskClass').suggestion,
        '2',
      );
      expect(detail('finans', 9006).conditionForm!.keys, {
        'methodCode',
        'termDays',
      });
    });

    test('karar veremeyene neden (decisionHint) gelir, modlar boş', () {
      final limit = detail('finans', 9010);
      expect(limit.modes, isEmpty);
      expect(limit.decisionHint, 'Limit talepleri merkezde onaylanır.');
      final own = detail('saha', 9002);
      expect(own.modes, isEmpty);
      expect(own.decisionHint, 'Kendi talebinizi onaylayamazsınız.');
      // Merkez limit talebini onaylar.
      expect(detail('merkez', 9010).modes, [
        ApprovalDecision.approve,
        ApprovalDecision.reject,
      ]);
    });

    test('maliyet satırları yalnızca karar verebilene', () {
      expect(
        detail('satis', 9002).summary.facts.map((f) => f.label),
        contains('Kâr oranı'),
      );
      expect(
        detail('saha', 9002).summary.facts.map((f) => f.label),
        isNot(contains('Kâr oranı')),
      );
    });

    test('cari görünümü: SLA, kademe, onaylayan ve iç değerlendirme yok', () {
      final d = detail('musteri', 9005);
      expect(d.customerView, isTrue);
      expect(d.row.dueAt, isNull);
      expect(d.row.slaState, ApprovalSlaState.none);
      expect(d.row.levelCount, 1);
      expect(d.summary.band, isNull);
      expect(d.summary.warnings, isEmpty);
      expect(d.summary.links.stationCustomerId, isNull);
      expect(d.summary.links.orderId, isNotNull);
      final labels = d.summary.facts.map((f) => f.label).toList();
      expect(labels, isNot(contains('Risk sınıfı')));
      expect(labels, isNot(contains('Limit kullanımı')));
      expect(labels, isNot(contains('Gerekçe')));
      expect(
        d.steps.every(
          (s) => s.name == 'Bayi değerlendirmesi' && s.decidedByName == null,
        ),
        isTrue,
      );
      expect(d.modes, isEmpty);
      expect(d.conditionForm, isNull);
      expect(d.canProvideInfo, isTrue);
      expect(d.canResumeInfo, isFalse);
      expect(d.infoRequest!.requiredAttachmentKind, AttachmentKind.chequeImage);
      expect(d.infoRequest!.uploadKind, AttachmentKind.chequeImage);
      expect(d.infoRequest!.requiredKindUploaded, isFalse);
      expect(d.infoRequest!.note, isNot(contains('İstenen belge')));
    });

    test('onaylayan tarafı ek bilgi beklerken "Bilgi alındı" ve ret', () {
      final d = detail('finans', 9005);
      expect(d.canResumeInfo, isTrue);
      expect(d.canProvideInfo, isFalse);
      expect(d.modes, [ApprovalDecision.reject]);
    });

    test('liste satırı (cari): özet, son tarih ve SLA ayıklanır', () {
      final row = ApprovalRow.fromJson(
        JsonReader.of(store.row(p('musteri'), world.approval(9005)!)),
      );
      expect(row.summary, isNull);
      expect(row.dueAt, isNull);
      expect(row.slaState, ApprovalSlaState.none);
      // Bayi personeli talebi gören cari kullanıcısı değil: talep eden adı gizli.
      expect(row.requestedByName, isNull);
    });

    test('kapsamlar: Bende eylem bekleyenler, Taleplerim kendi talepleri', () {
      final musteri = store.inbox(p('musteri'), 0).map((a) => a['id']);
      expect(musteri, containsAll([9003, 9005]));
      expect(store.inbox(p('talep'), 1).map((a) => a['id']), contains(9003));
      expect(store.inbox(p('saha'), 1).map((a) => a['id']), contains(9002));
      // Bayi şirket içi talebi görmez.
      expect(
        store.inbox(p('sahip'), 3).map((a) => a['id']),
        isNot(contains(9003)),
      );
    });
  });

  group('karar kuralları', () {
    JsonMap a(int id) => world.approval(id)!;
    JsonReader body(Map<String, Object?> m) => JsonReader.of(m);

    test('belirteç eksikse 400, eskiyse 409', () {
      expect(
        () => store.decide(p('finans'), a(9001), body({'decision': 1})),
        throwsA(fakeStatus(400, code: 'validation', field: 'concurrencyToken')),
      );
      expect(
        () => store.decide(
          p('finans'),
          a(9001),
          body({'decision': 1, 'concurrencyToken': 'eski'}),
        ),
        throwsA(fakeStatus(409, code: 'concurrency_conflict')),
      );
    });

    test('ret ve ek bilgide not zorunlu; yerel türde ret ≥ 10 karakter', () {
      final token = detail('finans', 9001).concurrencyToken;
      expect(
        () => store.decide(
          p('finans'),
          a(9001),
          body({'decision': 4, 'concurrencyToken': token, 'note': 'kısa'}),
        ),
        throwsA(fakeStatus(400, field: 'note')),
      );
      expect(
        () => store.decide(
          p('finans'),
          a(9001),
          body({'decision': 3, 'concurrencyToken': token}),
        ),
        throwsA(fakeStatus(400, field: 'note')),
      );
    });

    test('ret gerekçesi alt sınırı sunucuyla aynı: yerel 10, saha formu '
        'kârlılık yansıması 3, diğer yansımalar 1', () {
      // Sunucu `ApprovalTypes.MinRejectNoteLength` (canlı: approvals/10/decide "ok" → 400
      // "Ret gerekçesi en az 3 karakter olmalı (saha personeline iletilir).").
      expect(
        ApprovalType.orderFinance.minRejectNoteLength(isMirror: false),
        10,
      );
      expect(
        ApprovalType.fieldOrderProfit.minRejectNoteLength(isMirror: true),
        3,
      );
      expect(ApprovalType.limitChange.minRejectNoteLength(isMirror: true), 1);
      expect(
        ApprovalType.companyOrderRequest.minRejectNoteLength(isMirror: true),
        1,
      );

      final d = detail('satis', 9002);
      expect(d.type, ApprovalType.fieldOrderProfit);
      expect(d.row.isMirror, isTrue);
      expect(d.minRejectNoteLength, 3);
      expect(
        () => store.decide(
          p('satis'),
          a(9002),
          body({
            'decision': 4,
            'concurrencyToken': d.concurrencyToken,
            'note': 'ok',
          }),
        ),
        throwsA(fakeStatus(400, field: 'note')),
      );
      final result = store.decide(
        p('satis'),
        a(9002),
        body({
          'decision': 4,
          'concurrencyToken': d.concurrencyToken,
          'note': 'Kâr',
        }),
      );
      expect(result['status'], ApprovalStatus.rejected.code);
    });

    test('formda olmayan koşul anahtarı reddedilir', () {
      final token = detail('finans', 9001).concurrencyToken;
      expect(
        () => store.decide(
          p('finans'),
          a(9001),
          body({
            'decision': 2,
            'concurrencyToken': token,
            'conditions': {'limitAmount': 5},
          }),
        ),
        throwsA(fakeStatus(400, field: 'conditions.limitAmount')),
      );
      final result = store.decide(
        p('finans'),
        a(9001),
        body({
          'decision': 2,
          'concurrencyToken': token,
          'conditions': {'methodCode': 'HAVALE', 'termDays': 0},
        }),
      );
      expect(result['status'], ApprovalStatus.approved.code);
      final order = world.order(detail('finans', 9001).summary.links.orderId)!;
      expect(order['paymentMethodCode'], 'HAVALE');
      expect(
        order['financeStatus'],
        OrderFinanceStatus.conditionallyApproved.code,
      );
    });

    test(
      'kademeli onay: ilk kademe sonra ikinci kademe; aynı kişi iki kez onaylayamaz',
      () {
        final token = detail('finans', 9006).concurrencyToken;
        final first = store.decide(
          p('finans'),
          a(9006),
          body({'decision': 1, 'concurrencyToken': token}),
        );
        expect(first['isFinal'], isFalse);
        expect(first['currentLevelNo'], 2);
        final again = detail('finans', 9006);
        expect(again.modes, isEmpty);
        expect(again.decisionHint, contains('zaten onayladınız'));
        expect(detail('sahip', 9006).modes, contains(ApprovalDecision.approve));
      },
    );

    test('şirket içi talep onayı: satır sonuçları ve oluşan sipariş', () {
      final token = detail('onay', 9003).concurrencyToken;
      final before = world.orders.length;
      final result = store.decide(
        p('onay'),
        a(9003),
        body({'decision': 1, 'concurrencyToken': token}),
      );
      expect(result['message'], contains('1 satır oluşturulamadı'));
      expect(world.orders.length, before + 1);
      final req = CompanyRequest.fromJson(
        store.companyRequests.firstWhere((r) => r['id'] == 3001),
      );
      expect(req.status, CustomerOrderRequestStatus.approved);
      expect(req.createdCount, 1);
      expect(req.failedCount, 1);
      expect(req.lines.first.orderNumber, isNotNull);
      expect(req.lines.last.error, isNotNull);
    });

    test('ek bilgi yanıtı talebi yeniden incelemeye alır', () {
      final message = store.provideInfo(
        p('musteri'),
        a(9005),
        body({'note': 'Çek görseli eklendi.'}),
      );
      expect(message, contains('finans ekibine iletildi'));
      expect(a(9005)['status'], ApprovalStatus.pending.code);
      expect(
        () => store.provideInfo(p('musteri'), a(9005), body({})),
        throwsA(fakeStatus(409)),
      );
    });

    test('merkeze iletme yalnızca VKN başka bayide kayıtlı ön kayıtta', () {
      expect(store.forwardLead(p('finans'), 8003), contains('merkez onayına'));
      expect(
        () => store.forwardLead(p('finans'), 8002),
        throwsA(fakeStatus(400, code: 'business_rule')),
      );
      expect(
        () => store.forwardLead(p('satis'), 8003),
        throwsA(fakeStatus(403)),
      );
    });
  });

  group('finans ve tahsilat', () {
    test('finans kartı modele okunur', () {
      final card = FinanceCard.fromJson(store.financeCard(502));
      expect(card.profile.status, FinanceProfileStatus.conditional);
      expect(card.profile.riskClass, RiskClass.c);
      expect(card.profile.limitUsage!.ratio, closeTo(0.94, 0.001));
      expect(card.profile.collaterals, isNotEmpty);
      expect(
        card.reviews.first.decision,
        FinanceDecisionKind.conditionallyApproved,
      );
      expect(card.riskReports.first.lines, hasLength(3));
      expect(store.financeLinkIds(1), contains(506));
    });

    test('ödeme geçişleri sunucu kataloğunun aynası', () {
      expect(A5FakeStore.paymentTransitions(1, 'CEK'), [2, 3, 6]);
      expect(A5FakeStore.paymentTransitions(2, 'CEK'), [3, 4, 6]);
      expect(A5FakeStore.paymentTransitions(2, 'HAVALE'), [3, 6]);
      expect(A5FakeStore.paymentTransitions(3, 'AVANS'), [5]);
      expect(A5FakeStore.instrumentTransitions(5), [7, 4, 6]);
    });

    test(
      'ödeme ayrıntısı: geçişler yalnızca yetkiliye; belge ve not kuralları',
      () {
        final order = world.orders.firstWhere(
          (o) => o['paymentMethodCode'] == 'CEK' && o['status'] == 2,
        );
        final forAccounting = PaymentDetail.fromJson(
          store.paymentDetail(p('muhasebe'), order),
        );
        expect(forAccounting.allowedTransitions, [
          PaymentStatus.documentUploaded,
          PaymentStatus.collected,
          PaymentStatus.cancelled,
        ]);
        expect(forAccounting.noteRequiredFor, [PaymentStatus.cancelled]);
        expect(forAccounting.documentKind, AttachmentKind.chequeImage);
        expect(forAccounting.instrument, isNotNull);
        expect(forAccounting.documents, isNotEmpty);
        final forFinance = PaymentDetail.fromJson(
          store.paymentDetail(p('finans'), order),
        );
        expect(forFinance.allowedTransitions, isEmpty);
        expect(
          () => store.changePaymentStatus(
            p('muhasebe'),
            order,
            JsonReader.of({
              'toStatus': 6,
              'concurrencyToken': forAccounting.concurrencyToken,
            }),
          ),
          throwsA(fakeStatus(400, field: 'note')),
        );
        store.changePaymentStatus(
          p('muhasebe'),
          order,
          JsonReader.of({
            'toStatus': 2,
            'concurrencyToken': forAccounting.concurrencyToken,
          }),
        );
        expect(order['paymentStatus'], PaymentStatus.documentUploaded.code);
        expect(
          () => store.changePaymentStatus(
            p('muhasebe'),
            order,
            JsonReader.of({
              'toStatus': 3,
              'concurrencyToken': forAccounting.concurrencyToken,
            }),
          ),
          throwsA(fakeStatus(409)),
        );
      },
    );

    test('portföy satırı: geçişler ve not zorunluları', () {
      final bounced = store.instruments.firstWhere((i) => i['status'] == 5);
      final row = Instrument.fromJson(
        JsonReader.of(store.instrumentJson(p('muhasebe'), bounced)),
      );
      expect(row.allowedTransitions, [
        InstrumentStatus.protested,
        InstrumentStatus.collected,
        InstrumentStatus.returned,
      ]);
      expect(row.noteRequiredFor, [
        InstrumentStatus.protested,
        InstrumentStatus.returned,
      ]);
      final readOnly = Instrument.fromJson(
        JsonReader.of(store.instrumentJson(p('siparis'), bounced)),
      );
      expect(readOnly.allowedTransitions, isEmpty);
    });
  });
}

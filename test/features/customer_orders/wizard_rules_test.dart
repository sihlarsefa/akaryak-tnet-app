// Sihirbaz kuralları (spec A.4 A2): bayi seçici, satırlar, teslimat (en erken tarih, tank uyarısı),
// ödeme (vade seçenekleri, çek/senet vadesi sınırı, tutar/vade uyuşmazlığı, avans), istek gövdesi,
// şirket içi onay tahmini ve Türkçe saat eki.
import 'package:akaryakitnet/core/models/models.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:akaryakitnet/features/customer_orders/application/wizard_models.dart';
import 'package:akaryakitnet/features/customer_orders/application/wizard_rules.dart';
import 'package:akaryakitnet/features/customer_orders/copy.dart';
import 'package:akaryakitnet/features/customer_orders/data/form_models.dart';
import 'package:akaryakitnet/features/customer_orders/data/home_models.dart';
import 'package:akaryakitnet/features/customer_orders/data/payment_models.dart';
import 'package:flutter_test/flutter_test.dart';

OrderFormOptions _form() => OrderFormOptions.fromJson({
  'customerId': 101,
  'products': [
    {'id': 1, 'name': 'Motorin', 'sortOrder': 1},
    {'id': 2, 'name': 'Kurşunsuz Benzin 95', 'sortOrder': 2},
  ],
  'deliveryPoints': [
    {
      'id': 1001,
      'name': 'Pendik Lojistik Merkezi',
      'tankCapacityLiters': 30000,
      'deliveryWindowStart': '08:00:00',
      'deliveryWindowEnd': '18:00:00',
    },
    {'id': 1002, 'name': 'Tuzla Şantiye', 'tankCapacityLiters': 15000},
  ],
});

PaymentMethodOption _cheque() => PaymentMethodOption.fromJson(
  JsonReader.of({
    'code': 'CEK',
    'name': 'Çek',
    'shortName': 'Çek',
    'isDeferred': true,
    'requiresFinance': true,
    'documentKind': 1,
    'documentRequired': true,
    'minTermDays': 1,
    'maxTermDays': 60,
    'defaultTermDays': 30,
    'fields': [
      {'key': 'serialNo', 'label': 'Çek no', 'type': 'text', 'required': true},
      {'key': 'amount', 'label': 'Tutar', 'type': 'money', 'required': true},
      {
        'key': 'dueDate',
        'label': 'Vade tarihi',
        'type': 'date',
        'required': true,
      },
    ],
  }),
);

PaymentOptions _options({double? advance}) => PaymentOptions.fromJson(
  JsonReader.of({
    'enabled': true,
    'defaultMethodCode': 'HAVALE',
    'advanceBalance': advance,
    'methods': [
      {
        'code': 'CEK',
        'name': 'Çek',
        'shortName': 'Çek',
        'isDeferred': true,
        'requiresFinance': true,
        'minTermDays': 1,
        'maxTermDays': 60,
        'defaultTermDays': 30,
        'fields': [
          {
            'key': 'serialNo',
            'label': 'Çek no',
            'type': 'text',
            'required': true,
          },
          {
            'key': 'amount',
            'label': 'Tutar',
            'type': 'money',
            'required': true,
          },
          {
            'key': 'dueDate',
            'label': 'Vade tarihi',
            'type': 'date',
            'required': true,
          },
        ],
      },
      {'code': 'AVANS', 'name': 'Ön ödemeli bakiye'},
      {
        'code': 'HAVALE',
        'name': 'Havale / EFT',
        'fields': [
          {'key': 'bank', 'label': 'Banka', 'type': 'text', 'maxLength': 5},
        ],
      },
    ],
  }),
);

void main() {
  final today = TrTime.todayStart();
  final tomorrow = TrTime.addDays(today, 1);

  OrderDraft draft({
    List<DraftLine>? lines,
    int? stationId = 1,
    int? pointId = 1001,
    DateTime? date,
    DraftPayment payment = const DraftPayment(),
  }) => OrderDraft(
    stationId: stationId,
    lines: lines ?? [DraftLine.create(productId: 1, liters: 10000)],
    pointId: pointId,
    date: date ?? tomorrow,
    payment: payment,
  );

  group('Ürünler', () {
    test(
      'birden çok bayide seçim zorunlu; sipariş alamayan bayi engellenir',
      () {
        const stations = [
          StationOption(id: 1, title: 'Demir'),
          StationOption(
            id: 2,
            title: 'Kuzey',
            canOrder: false,
            blockReason: 'Finans onayı bekleniyor.',
          ),
        ];
        final noStation = WizardRules.products(
          draft(stationId: null),
          stations: stations,
          form: _form(),
        );
        expect(noStation.single.field, 'station');
        final blocked = WizardRules.products(
          draft(stationId: 2),
          stations: stations,
          form: _form(),
        );
        expect(blocked.single.message, 'Finans onayı bekleniyor.');
        expect(
          WizardRules.products(draft(), stations: stations, form: _form()),
          isEmpty,
        );
        // Tek bayi: seçici yok, denetim yok.
        expect(
          WizardRules.products(
            draft(stationId: null),
            stations: const [StationOption(id: 1, title: 'Demir')],
            form: _form(),
          ),
          isEmpty,
        );
      },
    );

    test('satır: ürün, litre > 0, en çok 3 ondalık, satışta olmayan ürün', () {
      final form = _form();
      expect(WizardRules.lineError(DraftLine.create(), form), 'Ürün seçin.');
      expect(
        WizardRules.lineError(DraftLine.create(productId: 1), form),
        'Litre girin.',
      );
      expect(
        WizardRules.lineError(
          DraftLine.create(productId: 1, liters: 10.1234),
          form,
        ),
        'Litre en çok üç ondalık hane içerebilir.',
      );
      expect(
        WizardRules.lineError(DraftLine.create(productId: 9, liters: 10), form),
        contains('satışta değil'),
      );
      expect(
        WizardRules.lineError(
          DraftLine.create(productId: 1, liters: 12500.5),
          form,
        ),
        isNull,
      );
      final many = draft(
        lines: [
          for (var i = 0; i < 21; i++)
            DraftLine.create(productId: 1, liters: 1),
        ],
      );
      expect(
        WizardRules.products(
          many,
          stations: const [],
          form: form,
        ).map((i) => i.message),
        contains('Tek seferde en çok 20 satır gönderilebilir.'),
      );
    });

    test('tahmini tutar: fiyatı bilinmeyen ürün varsa bilinmiyor', () {
      final d = draft(
        lines: [
          DraftLine.create(productId: 1, liters: 1000),
          DraftLine.create(productId: 2, liters: 500),
        ],
      );
      expect(Estimate.of(d, {1: 42.10, 2: 44.85}).value, 42100 + 22425);
      expect(Estimate.of(d, {1: 42.10}).unknown, isTrue);
      expect(Estimate.of(draft(lines: [DraftLine.create()]), {}).empty, isTrue);
    });
  });

  group('Teslimat', () {
    test('nokta ve tarih zorunlu; en erken tarihten önce olamaz', () {
      final form = _form();
      expect(
        WizardRules.delivery(
          draft(pointId: null),
          form: form,
          minDate: tomorrow,
        ).map((i) => i.field),
        ['point'],
      );
      final early = WizardRules.delivery(
        draft(date: today),
        form: form,
        minDate: tomorrow,
      );
      expect(early.single.field, 'date');
      expect(early.single.message, contains(Fmt0.date(tomorrow)));
      expect(
        WizardRules.delivery(draft(), form: form, minDate: tomorrow),
        isEmpty,
      );
    });

    test(
      'tank uyarısı: noktaya giden toplam litre kapasiteyi aşınca (engellemez)',
      () {
        final form = _form();
        final d = draft(
          lines: [
            DraftLine.create(productId: 1, liters: 20000),
            DraftLine.create(productId: 2, liters: 12000),
            DraftLine.create(
              productId: 1,
              liters: 9000,
            ).copyWith(custom: true, pointId: 1002),
          ],
        );
        final w = WizardRules.tankWarnings(d, form);
        expect(w, hasLength(1));
        expect(w.single.blocking, isFalse);
        expect(w.single.message, contains('Pendik Lojistik Merkezi'));
        expect(w.single.message, contains('32.000 L'));
        expect(w.single.message, contains('30.000 L'));
        expect(d.litersByPoint(), {1001: 32000, 1002: 9000});
      },
    );

    test('satır bazında nokta ve tarih', () {
      final l = DraftLine.create(
        productId: 1,
        liters: 1,
      ).copyWith(custom: true, pointId: 1002, date: TrTime.addDays(today, 3));
      final d = draft(lines: [l]);
      expect(d.pointOf(l), 1002);
      expect(d.dateOf(l), TrTime.addDays(today, 3));
      expect(d.pointOf(l.copyWith(custom: false)), 1001);
    });
  });

  group('Ödeme', () {
    test(
      'vade seçenekleri sınırlar içinde, varsayılan ve mevcut değer dahil',
      () {
        final m = _cheque();
        final opts = WizardRules.termOptions(m, 37);
        expect(opts.first, 1);
        expect(opts.last, 60);
        expect(opts, containsAll([7, 30, 37, 45, 60]));
        expect(opts, isNot(contains(0)));
        expect(WizardRules.defaultTerm(m), 30);
      },
    );

    test('çek vadesi: teslimden en çok maxTerm gün; vade (gün) belgeden', () {
      final m = _cheque();
      final due = TrTime.addDays(tomorrow, 75);
      final err = WizardRules.instrumentDueError(m, tomorrow, due);
      expect(err, contains('en geç'));
      expect(err, contains('75 gün sonra'));
      expect(
        WizardRules.instrumentDueError(
          m,
          tomorrow,
          TrTime.addDays(tomorrow, 45),
        ),
        isNull,
      );
      expect(
        WizardRules.termFromDue(m, tomorrow, TrTime.addDays(tomorrow, 45)),
        45,
      );
      expect(
        WizardRules.termFromDue(m, tomorrow, today),
        1,
        reason: 'teslimden önce → en kısa vade',
      );
    });

    test(
      'alan denetimi: zorunlu, tutar biçimi, geçmiş vade, uzunluk, vade seçimi',
      () {
        final o = _options();
        final d = draft(
          payment: DraftPayment(
            methodCode: 'CEK',
            fields: {
              'amount': 'abc',
              'dueDate': TrTime.isoDate(TrTime.addDays(today, -1)),
            },
          ),
        );
        final issues = WizardRules.payment(
          d,
          options: o,
          estimate: const Estimate(value: 1),
        );
        final byField = {for (final i in issues) i.field: i.message};
        expect(byField['term'], 'Çek için vade (gün) seçin.');
        expect(byField['serialNo'], 'Çek no zorunludur.');
        expect(byField['amount'], contains('geçerli bir tutar'));
        expect(byField['dueDate'], 'Vade tarihi geçmiş bir tarih olamaz.');
        final havale = draft(
          payment: const DraftPayment(
            methodCode: 'HAVALE',
            fields: {'bank': 'Ziraat Bankası'},
          ),
        );
        expect(
          WizardRules.payment(
            havale,
            options: o,
            estimate: const Estimate(value: 1),
          ).single.message,
          'Banka en çok 5 karakter olabilir.',
        );
      },
    );

    test('avans: bakiye tahmini tutarı karşılamıyorsa hata', () {
      final d = draft(
        payment: const DraftPayment(methodCode: 'AVANS', termDays: 0),
      );
      final low = WizardRules.payment(
        d,
        options: _options(advance: 1000),
        estimate: const Estimate(value: 421000),
      );
      expect(low.single.field, 'advance');
      expect(low.single.message, contains('bakiye yetersiz'));
      expect(
        WizardRules.payment(
          d,
          options: _options(advance: 500000),
          estimate: const Estimate(value: 421000),
        ),
        isEmpty,
      );
    });

    test(
      'çek uyuşmazlık uyarıları: tutar tahminden farklı, vade teslim + vadeden farklı',
      () {
        final o = _options();
        final d = draft(
          payment: DraftPayment(
            methodCode: 'CEK',
            termDays: 30,
            fields: {
              'amount': '400.000,00',
              'dueDate': TrTime.isoDate(TrTime.addDays(tomorrow, 45)),
            },
          ),
        );
        final w = WizardRules.paymentWarnings(
          d,
          options: o,
          estimate: const Estimate(value: 421000),
        );
        expect(w.map((x) => x.field), containsAll(['amount', 'dueDate']));
        expect(w.every((x) => !x.blocking), isTrue);
        final same = draft(
          payment: DraftPayment(
            methodCode: 'CEK',
            termDays: 30,
            fields: {
              'amount': '421.000,00',
              'dueDate': TrTime.isoDate(TrTime.addDays(tomorrow, 30)),
            },
          ),
        );
        expect(
          WizardRules.paymentWarnings(
            same,
            options: o,
            estimate: const Estimate(value: 421000),
          ),
          isEmpty,
        );
      },
    );

    test('ödeme özeti ve ödeme tarihi (çekte belgenin vadesi)', () {
      final m = _cheque();
      final due = TrTime.addDays(tomorrow, 40);
      final d = draft(
        payment: DraftPayment(
          methodCode: 'CEK',
          termDays: 40,
          fields: {'dueDate': TrTime.isoDate(due)},
        ),
      );
      expect(WizardRules.paymentDueDate(d, m), due);
      expect(
        WizardRules.paymentSummary(d, m),
        'Çek · 40 gün · vade ${Fmt0.date(due)}',
      );
    });
  });

  group('İstek gövdesi', () {
    test(
      'tutar kanonik, not yalnızca şirket içi onayda, satır bazında nokta/tarih',
      () {
        final o = _options();
        final l2 = DraftLine.create(
          productId: 2,
          liters: 3000.5,
        ).copyWith(custom: true, pointId: 1002, date: TrTime.addDays(today, 4));
        final d = draft(
          lines: [DraftLine.create(productId: 1, liters: 10000), l2],
          payment: const DraftPayment(
            methodCode: 'CEK',
            termDays: 30,
            fields: {
              'serialNo': 'A1',
              'amount': '421.000,50',
              'dueDate': '2026-12-01',
            },
          ),
        ).copyWith(note: 'Acil', templateId: 702, paymentGroupKey: 'g-1');
        final direct = WizardRules.buildRequest(
          d,
          options: o,
          companyRequestPredicted: false,
        );
        final json = direct.toJson();
        expect(json['note'], isNull);
        expect(json['templateId'], 702);
        expect(json['paymentGroupKey'], 'g-1');
        expect(json['requestedDeliveryDate'], TrTime.isoDate(tomorrow));
        final lines = (json['lines'] as List).cast<Map<String, dynamic>>();
        expect(lines.first.containsKey('deliveryPointId'), isFalse);
        expect(lines[1]['deliveryPointId'], 1002);
        expect(
          lines[1]['requestedDeliveryDate'],
          TrTime.isoDate(TrTime.addDays(today, 4)),
        );
        final payment = json['payment'] as Map<String, dynamic>;
        expect(payment['methodCode'], 'CEK');
        expect(payment['termDays'], 30);
        expect((payment['details'] as Map)['amount'], '421000.50');
        final request = WizardRules.buildRequest(
          d,
          options: o,
          companyRequestPredicted: true,
        );
        expect(request.toJson()['note'], 'Acil');
      },
    );

    test('ödeme kapalıysa yöntem gönderilmez', () {
      final d = draft(
        payment: const DraftPayment(methodCode: 'CEK', termDays: 30),
      );
      final off = PaymentOptions.fromJson(JsonReader.of({'enabled': false}));
      expect(
        WizardRules.buildRequest(
          d,
          options: off,
          companyRequestPredicted: false,
        ).payment,
        isNull,
      );
    });
  });

  group('Şirket içi onay tahmini (sunucu kuralı portu)', () {
    test('litre eşiği, tutar eşiği, tutar bilinmiyorsa güvenli taraf', () {
      const both = CompanyApprovalRule(
        required: true,
        aboveLitres: 20000,
        aboveAmount: 750000,
      );
      expect(both.predicts(totalLiters: 20001, estimatedAmount: 1), isTrue);
      expect(both.predicts(totalLiters: 1000, estimatedAmount: 750001), isTrue);
      expect(both.predicts(totalLiters: 1000, estimatedAmount: 1000), isFalse);
      expect(
        both.predicts(totalLiters: 1000),
        isFalse,
        reason: 'litre eşiği karar verir',
      );
      const amountOnly = CompanyApprovalRule(
        required: true,
        aboveAmount: 750000,
      );
      expect(
        amountOnly.predicts(totalLiters: 1),
        isTrue,
        reason: 'tutar bilinmiyor → onay',
      );
      const every = CompanyApprovalRule(required: true, aboveLitres: 0);
      expect(every.predicts(totalLiters: 1, estimatedAmount: 1), isTrue);
      const off = CompanyApprovalRule();
      expect(off.predicts(totalLiters: 99999, estimatedAmount: 9e9), isFalse);
    });
  });

  group('Taslak saklama', () {
    test('JSON gidiş-dönüşü', () {
      final d =
          draft(
            lines: [
              DraftLine.create(productId: 1, liters: 10000),
              DraftLine.create(
                productId: 2,
                liters: 5,
              ).copyWith(custom: true, pointId: 1002, date: tomorrow),
            ],
            payment: const DraftPayment(
              methodCode: 'CEK',
              termDays: 30,
              fields: {'amount': '1,00'},
              touched: true,
            ),
          ).copyWith(
            step: WizardStep.payment,
            saveAsTemplate: true,
            templateName: 'Ad',
            dirty: true,
          );
      final back = OrderDraft.fromJson(d.toJson());
      expect(back.toJson(), d.toJson());
      expect(back.lines[1].custom, isTrue);
      expect(back.step, WizardStep.payment);
    });
  });

  test('Türkçe saat eki (yönelme hâli)', () {
    expect(withDative('17:30'), "17:30'a");
    expect(withDative('18:00'), "18:00'e");
    expect(withDative('12:00'), "12:00'ye");
    expect(withDative('16:45'), "16:45'e");
    expect(withDative('10:00'), "10:00'a");
    expect(withDative('20:00'), "20:00'ye");
    expect(withDative('23:59'), "23:59'a");
    expect(withDative('09:06'), "09:06'ya");
    expect(withDative('13:00'), "13:00'e");
  });

  test('web QuoteDecisionPresets birebir', () {
    expect(QuoteDecisionPresets.revisionReasons, [
      'Fiyat yüksek, indirim rica ederiz',
      'Önceki alım fiyatımızın üzerinde',
      'Teslim tarihi uygun değil',
      'Miktarı değiştirmek istiyoruz',
      'Vade / ödeme koşulunu görüşelim',
    ]);
    expect(QuoteDecisionPresets.rejectReasons, [
      'Fiyat uygun değil',
      'İhtiyaç ortadan kalktı',
      'Başka tedarikçiden temin edildi',
    ]);
    expect(QuoteDecisionPresets.disputeReasons, [
      'Eksik litre teslim edildi',
      'İrsaliye bilgisi hatalı',
      'Yanlış ürün teslim edildi',
      'Teslimat noktası farklı',
    ]);
  });
}

/// Testte `Fmt` adını gölgelemeden tarih biçimi.
abstract final class Fmt0 {
  static String date(DateTime d) {
    final w = TrTime.wall(d);
    return '${w.day.toString().padLeft(2, '0')}.${w.month.toString().padLeft(2, '0')}.${w.year}';
  }
}

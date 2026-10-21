// Koşullu onay formu → `conditions` JSON (spec §B.8): yalnızca formun anahtarları, doğru tipler,
// boş / değişmeyen alanlar gönderilmez. Her finans türünün formu ayrı denenir.
import 'package:akaryakitnet/core/models/json.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:akaryakitnet/features/approvals/data/approval_models.dart';
import 'package:akaryakitnet/features/approvals/data/condition_values.dart';
import 'package:flutter_test/flutter_test.dart';

ConditionForm _form(List<Map<String, Object?>> fields) =>
    ConditionForm.fromJson(
      JsonReader.of({
        'fields': fields,
        'methodOptions': [
          {'code': 'NAKIT', 'name': 'Nakit (peşin)'},
          {'code': 'HAVALE', 'name': 'Havale / EFT (peşin)'},
          {'code': 'CEK', 'name': 'Çek', 'isDeferred': true},
          {'code': 'ACIK_HESAP', 'name': 'Açık hesap (cari vadeli)'},
        ],
        'periodOptions': [
          {'code': 'Aylık', 'label': 'Aylık'},
          {'code': 'Haftalık', 'label': 'Haftalık'},
          {'code': 'Günlük', 'label': 'Günlük'},
        ],
        'riskClassOptions': [
          {'code': '1', 'label': 'A (düşük risk)'},
          {'code': '2', 'label': 'B'},
          {'code': '3', 'label': 'C'},
          {'code': '4', 'label': 'D (yüksek risk)'},
        ],
      }),
    );

/// Sipariş finansı ve saha formu finansı: yöntem + vade.
ConditionForm paymentChangeForm() => _form([
  {
    'key': 'methodCode',
    'label': 'Ödeme yöntemi',
    'type': 'method',
    'current': 'CEK',
    'currentLabel': 'Çek',
  },
  {
    'key': 'termDays',
    'label': 'Vade (gün)',
    'type': 'int',
    'min': 0,
    'max': 365,
    'current': '60',
  },
]);

/// Yeni cari ve ön kayıt: limit, dönem, en uzun vade, yöntemler, risk, teminat, gözden geçirme.
ConditionForm creditForm({num collateralMax = 100}) => _form([
  {
    'key': 'limitAmount',
    'label': 'Onaylanan limit (₺)',
    'type': 'money',
    'min': 0,
    'max': 999999999999.99,
    'current': '400000',
  },
  {'key': 'limitPeriod', 'label': 'Limit dönemi', 'type': 'period'},
  {
    'key': 'maxTermDays',
    'label': 'En uzun vade (gün)',
    'type': 'int',
    'min': 0,
    'max': 365,
    'current': '30',
  },
  {
    'key': 'allowedMethodCodes',
    'label': 'İzinli ödeme yöntemleri',
    'type': 'methods',
    'current': 'HAVALE,CEK',
  },
  {
    'key': 'riskClass',
    'label': 'Risk sınıfı',
    'type': 'riskClass',
    'current': '2',
    'suggestion': '2',
  },
  {
    'key': 'collateralRatioPercent',
    'label': 'Teminat oranı (%)',
    'type': 'percent',
    'min': 0,
    'max': collateralMax,
    'current': '10',
  },
  {'key': 'nextReviewDate', 'label': 'Sonraki gözden geçirme', 'type': 'date'},
]);

void main() {
  group('OrderFinance / FieldFormFinance (yöntem + vade)', () {
    for (final type in ['OrderFinance', 'FieldFormFinance']) {
      test('$type: yalnızca formun anahtarları, tamsayı vade', () {
        final form = paymentChangeForm();
        final c = ConditionValueCodec.build(form, {
          'methodCode': 'HAVALE',
          'termDays': '15',
          // Formda olmayan anahtar hiçbir zaman gitmez.
          'limitAmount': '500000',
        });
        expect(c, {'methodCode': 'HAVALE', 'termDays': 15});
        expect(c['termDays'], isA<int>());
        expect(form.keys, {'methodCode', 'termDays'});
      });
    }

    test('boş ve mevcut değerle aynı alan "değişmez" sayılır', () {
      final form = paymentChangeForm();
      expect(ConditionValueCodec.build(form, {}), isEmpty);
      expect(
        ConditionValueCodec.build(form, {
          'methodCode': 'CEK',
          'termDays': '60',
        }),
        isEmpty,
      );
      expect(ConditionValueCodec.build(form, {'termDays': '  '}), isEmpty);
    });

    test('aralık dışı vade ve bayide açık olmayan yöntem reddedilir', () {
      final form = paymentChangeForm();
      final e = ConditionValueCodec.validate(form, {
        'termDays': '400',
        'methodCode': 'SENET',
      });
      expect(e['termDays'], contains('365'));
      expect(e['methodCode'], isNotNull);
      expect(ConditionValueCodec.validate(form, {'termDays': '30'}), isEmpty);
    });
  });

  group('CustomerOnboarding / LeadFinance (kredi koşulları)', () {
    test('CustomerOnboarding: tipler sunucu DTO\'su gibi', () {
      final form = creditForm();
      final c = ConditionValueCodec.build(form, {
        'limitAmount': '250000.5',
        'limitPeriod': 'Haftalık',
        'maxTermDays': '45',
        'allowedMethodCodes': 'HAVALE,ACIK_HESAP',
        'riskClass': '3',
        'collateralRatioPercent': '25',
        'nextReviewDate': '2027-10-21',
      });
      expect(c, {
        'limitAmount': 250000.5,
        'limitPeriod': 'Haftalık',
        'maxTermDays': 45,
        'allowedMethodCodes': ['HAVALE', 'ACIK_HESAP'],
        'riskClass': 3,
        'collateralRatioPercent': 25,
        'nextReviewDate': '2027-10-21',
      });
      expect(c['riskClass'], isA<int>());
      expect(c['allowedMethodCodes'], isA<List<String>>());
    });

    test('LeadFinance: teminat %500\'e kadar, onboarding %100', () {
      final lead = creditForm(collateralMax: 500);
      expect(
        ConditionValueCodec.validate(lead, {'collateralRatioPercent': '150'}),
        isEmpty,
      );
      final onboarding = creditForm();
      expect(
        ConditionValueCodec.validate(onboarding, {
          'collateralRatioPercent': '150',
        })['collateralRatioPercent'],
        contains('%100'),
      );
      expect(
        ConditionValueCodec.build(lead, {'collateralRatioPercent': '150'}),
        {'collateralRatioPercent': 150},
      );
    });

    test('yöntem listesi sırasız karşılaştırılır; aynı küme gönderilmez', () {
      final form = creditForm();
      expect(
        ConditionValueCodec.build(form, {'allowedMethodCodes': 'CEK,HAVALE'}),
        isEmpty,
      );
      expect(ConditionValueCodec.build(form, {'allowedMethodCodes': 'CEK'}), {
        'allowedMethodCodes': ['CEK'],
      });
    });

    test('geçmiş gözden geçirme tarihi ve geçersiz risk sınıfı reddedilir', () {
      final form = creditForm();
      final today = TrTime.fromWall(2026, 10, 21);
      final e = ConditionValueCodec.validate(form, {
        'nextReviewDate': '2026-10-20',
        'riskClass': '7',
      }, today: today);
      expect(e['nextReviewDate'], isNotNull);
      expect(e['riskClass'], isNotNull);
      expect(
        ConditionValueCodec.validate(form, {
          'nextReviewDate': '2026-10-21',
        }, today: today),
        isEmpty,
      );
    });

    test('özet metni Türkçe biçimli', () {
      final form = creditForm();
      final text = ConditionValueCodec.describe(form, {
        'limitAmount': 250000,
        'riskClass': 3,
        'allowedMethodCodes': ['HAVALE', 'CEK'],
      });
      expect(text, contains('250.000,00 ₺'));
      expect(text, contains('Risk sınıfı: C'));
      expect(text, contains('Havale / EFT (peşin), Çek'));
    });
  });

  test('sayılar değişmez kültürde yazılır', () {
    expect(ConditionValueCodec.canonical(150000.5), '150000.5');
    expect(ConditionValueCodec.canonical(25), '25');
    expect(ConditionValueCodec.canonical(25.0), '25');
    expect(ConditionValueCodec.splitCodes(' CEK, HAVALE,,CEK '), [
      'CEK',
      'HAVALE',
    ]);
  });
}

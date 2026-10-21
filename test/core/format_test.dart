import 'package:akaryakitnet/core/models/enums.dart';
import 'package:akaryakitnet/core/utils/format.dart';
import 'package:akaryakitnet/core/utils/tr_number.dart';
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:akaryakitnet/core/utils/turkish_text.dart';
import 'package:akaryakitnet/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Türkçe sayı ve tutar', () {
    test('para: 1.234,56 ₺', () {
      expect(Fmt.money(1234.56), '1.234,56 ₺');
      expect(Fmt.money(0), '0,00 ₺');
      expect(Fmt.money(-1234567.891), '-1.234.567,89 ₺');
      expect(Fmt.money(999.999), '1.000,00 ₺');
      expect(Fmt.money(null), '—');
      expect(Fmt.moneyWhole(1234.6), '1.235 ₺');
    });

    test('litre: 12.500 L', () {
      expect(Fmt.liters(12500), '12.500 L');
      expect(Fmt.liters(12500.5), '12.500,5 L');
      expect(Fmt.liters(0.125), '0,125 L');
      expect(Fmt.liters(1000000), '1.000.000 L');
    });

    test('birim fiyat ve diğerleri', () {
      expect(Fmt.unitPrice(42.1), '42,10 ₺/L');
      expect(Fmt.unitPrice(42.1255), '42,1255 ₺/L');
      expect(Fmt.pricePerM3(42125), '42.125,00 ₺/m³');
      expect(Fmt.percent(45), '%45');
      expect(Fmt.percent(45.25), '%45,3');
      expect(Fmt.moneyCompact(850000), '850 bin ₺');
      expect(Fmt.moneyCompact(1250000), '1,3 mn ₺');
      expect(Fmt.moneyCompact(2400000000), '2,4 mr ₺');
      expect(Fmt.fileSize(1536 * 1024), '1,5 MB');
      expect(Fmt.number(-0.001, maxFraction: 2), '0', reason: '-0 gösterilmez');
    });

    test('Türkçe sayı girişi', () {
      expect(TrNumber.parse('12.500'), 12500);
      expect(TrNumber.parse('12.500,75'), 12500.75);
      expect(TrNumber.parse('42,13'), 42.13);
      expect(
        TrNumber.parse('12.5'),
        12.5,
        reason: 'yapıştırılan İngilizce biçim',
      );
      expect(TrNumber.parse('1.250.000'), 1250000);
      expect(TrNumber.parse('₺ 1.234,50'), 1234.5);
      expect(TrNumber.parse('-5'), -5);
      expect(TrNumber.parse('abc'), isNull);
      expect(TrNumber.parse(''), isNull);
      expect(TrNumber.decimals('12,125'), 3);
    });
  });

  group('Türkiye saati', () {
    final instant = DateTime.utc(2026, 10, 21, 11, 5); // 14:05 TR

    test('tarih ve saat Türkiye duvar saatiyle', () {
      expect(Fmt.date(instant), '21.10.2026');
      expect(Fmt.time(instant), '14:05');
      expect(Fmt.dateTime(instant), '21.10.2026 14:05');
      expect(Fmt.longDate(instant), '21 Ekim 2026');
      expect(Fmt.dayMonth(instant), '21 Eki');
      expect(Fmt.weekday(instant), 'Çarşamba');
      expect(
        Fmt.date(DateTime.utc(2026, 10, 21, 22)),
        '22.10.2026',
        reason: '22:00 UTC = ertesi gün 01:00 TR',
      );
    });

    test('ISO biçimleri', () {
      expect(TrTime.isoDate(instant), '2026-10-21');
      expect(TrTime.isoLocal(instant), '2026-10-21T14:05:00');
      expect(TrTime.isoOffset(instant), '2026-10-21T14:05:00+03:00');
      expect(TrTime.parseLocal('2026-10-21T14:05:00'), instant);
      expect(TrTime.parseDate('2026-10-22'), TrTime.fromWall(2026, 10, 22));
      expect(TrTime.dayDiff(instant, DateTime.utc(2026, 10, 22, 6)), 1);
    });

    test('göreli zaman ve gün etiketi', () {
      final now = instant;
      expect(
        Fmt.relative(now.subtract(const Duration(seconds: 20)), now: now),
        'Az önce',
      );
      expect(
        Fmt.relative(now.subtract(const Duration(minutes: 5)), now: now),
        '5 dk önce',
      );
      expect(
        Fmt.relative(now.subtract(const Duration(hours: 3)), now: now),
        '3 sa önce',
      );
      expect(
        Fmt.relative(now.subtract(const Duration(hours: 22)), now: now),
        'Dün 16:05',
      );
      expect(
        Fmt.relative(now.subtract(const Duration(days: 9)), now: now),
        '12.10.2026',
      );
      expect(
        Fmt.dayLabel(now.add(const Duration(hours: 20)), now: now),
        'Yarın',
      );
      expect(Fmt.dayLabel(now, now: now), 'Bugün');
      expect(
        Fmt.dayLabel(now.subtract(const Duration(days: 1)), now: now),
        'Dün',
      );
    });

    test('geri sayım', () {
      expect(Fmt.countdown(const Duration(days: 2, hours: 3)), '2 g 3 sa');
      expect(
        Fmt.countdown(const Duration(hours: 2, minutes: 15)),
        '2 sa 15 dk',
      );
      expect(Fmt.countdown(const Duration(minutes: 45)), '45 dk');
      expect(Fmt.countdown(const Duration(seconds: 30)), '30 sn');
      expect(Fmt.countdown(const Duration(seconds: -1)), 'Süresi doldu');
    });
  });

  group('Metin', () {
    test('telefon ve plaka', () {
      expect(Fmt.phone('5321234567'), '0532 123 45 67');
      expect(Fmt.phone('+90 532 123 45 67'), '0532 123 45 67');
      expect(Fmt.phone('02620000001'), '0262 000 00 01');
      expect(Fmt.plate('34abc123'), '34 ABC 123');
      expect(Fmt.plate('41 DMR 101'), '41 DMR 101');
    });

    test('Türkçe arama', () {
      expect(TurkishText.lower('İSTANBUL ILGAZ'), 'istanbul ılgaz');
      expect(TurkishText.upper('istanbul ılgaz'), 'İSTANBUL ILGAZ');
      expect(TurkishText.matches('ŞİŞLİ Şantiye', 'sisli'), isTrue);
      expect(
        TurkishText.matches('Gebze', 'ğ'),
        isTrue,
        reason: 'aksansız eşleşir',
      );
      expect(TurkishText.matches('Gebze', 'izmit'), isFalse);
      expect(TurkishText.matches('Çağlayan', 'caglayan'), isTrue);
      expect(TurkishText.initials('Ahmet Yılmaz'), 'AY');
      expect(TurkishText.initials('ilker'), 'İ');
    });
  });

  group('Doğrulayıcılar', () {
    test('VKN / TCKN (sunucuyla aynı algoritma)', () {
      expect(Validators.isValidVkn('1234567808'), isTrue);
      expect(Validators.isValidVkn('1234567802'), isFalse);
      expect(Validators.isValidTckn('10000000146'), isTrue);
      expect(Validators.isValidTckn('10000000147'), isFalse);
      expect(Validators.taxNumber(''), 'VKN / TCKN zorunludur.');
      expect(Validators.taxNumber('123'), 'VKN 10, TCKN 11 haneli olmalıdır.');
      expect(Validators.taxNumber('123 456 78 08'), isNull);
      expect(
        Validators.taxNumber('1234567802'),
        'VKN doğrulanamadı; numarayı kontrol edin.',
      );
    });

    test('telefon, e-posta, plaka, pozitif sayı', () {
      expect(Validators.normalizePhone('0532 123 45 67'), '905321234567');
      expect(
        Validators.normalizePhone('0262 000 00 01'),
        isNull,
        reason: 'sabit hat değil cep',
      );
      expect(Validators.mobilePhone('5321234567'), isNull);
      expect(Validators.email('a@b.co'), isNull);
      expect(Validators.email('ab.co'), isNotNull);
      expect(Validators.plate('34 ABC 123'), isNull);
      expect(Validators.plate('99 ABC 123'), isNotNull);
      expect(
        Validators.positiveNumber(8000.5, max: 8000),
        'En fazla 8000 girilebilir.',
      );
      expect(Validators.positiveNumber(0), isNotNull);
      expect(
        Validators.positiveNumber(12.1234),
        'En fazla 3 ondalık hane girilebilir.',
      );
      expect(Validators.positiveNumber(12.123), isNull);
    });
  });

  group('Enum etiketleri', () {
    test(
      'her değerin Türkçe etiketi var, kodlar benzersiz, bilinmeyen yedek var',
      () {
        for (final values in allCodedEnums) {
          final known = values.where((e) => !e.isUnknown).toList();
          final unknowns = values.where((e) => e.isUnknown).toList();
          expect(
            unknowns,
            hasLength(1),
            reason: '${values.first.runtimeType} unknown yedeği',
          );
          expect(
            known.map((e) => e.code).toSet(),
            hasLength(known.length),
            reason: '${values.first.runtimeType} kodları',
          );
          for (final e in values) {
            expect(e.label.trim(), isNotEmpty, reason: '$e etiketi');
          }
        }
      },
    );

    test('sunucu kodları', () {
      expect(OrderStatus.fromCode(7), OrderStatus.completed);
      expect(ShipmentStatus.fromCode(2).label, 'Kabul bekliyor');
      expect(ApprovalType.fromCode(6).shortLabel, 'Yeni cari');
      expect(ApprovalType.orderFinance.isFinance, isTrue);
      expect(ApprovalType.limitChange.isFinance, isFalse);
      expect(PaymentStatus.fromCode(4).label, 'Karşılıksız');
      expect(OrderFinanceStatus.fromCode(3).label, 'Koşullu onaylandı');
      expect(LeadStatus.fromCode(5).label, 'Cariye dönüştürüldü');
      expect(FieldOrderFormStatus.fromCode(4).label, 'Siparişe dönüştü');
      expect(AttachmentKind.fromCode(31), AttachmentKind.deliverySignature);
      expect(AttachmentOwnerType.fromCode(10), AttachmentOwnerType.shipment);
      expect(InstrumentStatus.fromCode(7).label, 'Protesto edildi');
      expect(CustomerUserRole.fromCode(null), CustomerUserRole.admin);
      expect(CustomerUserRole.fromCode(1).canApprove, isFalse);
      expect(ApprovalDecision.reject.requiresNote, isTrue);
      expect(ApprovalSlaState.fromCode(3).label, 'Süresi geçti');
      expect(
        OrderStatus.fromCode(-1),
        OrderStatus.unknown,
        reason: 'unknown kodu sunucudan gelirse yine unknown',
      );
    });
  });
}

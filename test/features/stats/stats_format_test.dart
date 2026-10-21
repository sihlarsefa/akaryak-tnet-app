// İstatistik biçimleri (tr-TR): kısa tutar / litre, yüzde, fark, birim fiyat, süre, aralık, ekran okuyucu.
import 'package:akaryakitnet/core/utils/tr_time.dart';
import 'package:akaryakitnet/features/stats/presentation/stats_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kısa tutar', () {
    test('Mn, B ve birimsiz', () {
      expect(StatsFmt.moneyCompact(21500000), '21,5 Mn ₺');
      expect(StatsFmt.moneyCompact(21000000), '21 Mn ₺');
      expect(StatsFmt.moneyCompact(820000), '820 B ₺');
      expect(StatsFmt.moneyCompact(15300), '15,3 B ₺');
      expect(StatsFmt.moneyCompact(1234), '1,2 B ₺');
      expect(StatsFmt.moneyCompact(950), '950 ₺');
      expect(StatsFmt.moneyCompact(0), '0 ₺');
      expect(StatsFmt.moneyCompact(1200000000), '1,2 Mr ₺');
      expect(StatsFmt.moneyCompact(-820000), '-820 B ₺');
      expect(StatsFmt.moneyCompact(null), '—');
    });

    test('yuvarlanınca üst birime geçer (1.000 B değil 1 Mn)', () {
      expect(StatsFmt.moneyCompact(999960), '1 Mn ₺');
      expect(StatsFmt.moneyCompact(999.6), '1 B ₺');
      expect(StatsFmt.moneyCompact(999949999), '999,9 Mn ₺');
      expect(StatsFmt.moneyCompact(999960000), '1 Mr ₺');
    });

    test('sayaç kareleri hedefin biriminde yazılır', () {
      expect(StatsFmt.moneyCompactAt(0, 21500000), '0 Mn ₺');
      expect(StatsFmt.moneyCompactAt(10750000, 21500000), '10,8 Mn ₺');
      expect(StatsFmt.moneyCompactAt(21500000, 21500000), '21,5 Mn ₺');
      expect(StatsFmt.litersCompactAt(250000, 512000), '250.000 L');
    });

    test('eksen sayısı', () {
      expect(StatsFmt.compactNumber(20000000), '20 Mn');
      expect(StatsFmt.compactNumber(500000), '500 B');
      expect(StatsFmt.compactNumber(40), '40');
    });
  });

  group('litre', () {
    test('kısa litre', () {
      expect(StatsFmt.litersCompact(512000), '512.000 L');
      expect(StatsFmt.litersCompact(1200000), '1,2 Mn L');
      expect(StatsFmt.litersCompact(999999.6), '1 Mn L');
      expect(StatsFmt.litersCompact(950), '950 L');
      expect(StatsFmt.litersCompact(null), '—');
    });

    test('tam değerler (sayfa)', () {
      expect(StatsFmt.liters(512000.4), '512.000 L');
      expect(StatsFmt.money(21500000.4), '21.500.000 ₺');
      expect(StatsFmt.count(42), '42');
      expect(StatsFmt.count(12500), '12.500');
    });
  });

  group('oran ve fark', () {
    test('yüzde', () {
      expect(StatsFmt.rate(0.92), '%92');
      expect(StatsFmt.rate(0.788, decimals: 1), '%78,8');
      expect(StatsFmt.rate(1), '%100');
      expect(StatsFmt.rate(null), '—');
    });

    test('değişim: önceki yoksa ya da sıfırsa null', () {
      expect(StatsFmt.change(21.5, 19.8), closeTo(8.5859, 1e-3));
      expect(StatsFmt.change(10, 0), isNull);
      expect(StatsFmt.change(10, null), isNull);
      expect(StatsFmt.change(null, 10), isNull);
    });

    test('fark metni', () {
      expect(StatsFmt.delta(8.6), '▲ %8,6');
      expect(StatsFmt.delta(8.64), '▲ %8,6');
      expect(StatsFmt.delta(-3.24), '▼ %3,2');
      expect(StatsFmt.delta(12), '▲ %12');
      expect(StatsFmt.delta(0.01), '= %0');
      expect(StatsFmt.deltaSpoken(8.6), 'yüzde 8,6 artış');
      expect(StatsFmt.deltaSpoken(-3.2), 'yüzde 3,2 azalış');
      expect(StatsFmt.deltaSpoken(0), 'değişim yok');
    });

    test('birim fiyatta düşüş iyidir', () {
      expect(StatsFmt.deltaIsGood(5), isTrue);
      expect(StatsFmt.deltaIsGood(-5), isFalse);
      expect(StatsFmt.deltaIsGood(-1.2, lowerIsBetter: true), isTrue);
      expect(StatsFmt.deltaIsGood(1.2, lowerIsBetter: true), isFalse);
      expect(StatsFmt.deltaIsGood(0.01), isNull);
    });
  });

  test('birim fiyat iki hane', () {
    expect(StatsFmt.unitPrice(42.5), '42,50 ₺/L');
    expect(StatsFmt.unitPrice(41.987), '41,99 ₺/L');
    expect(StatsFmt.unitPrice(null), '—');
  });

  test('süre', () {
    expect(StatsFmt.minutes(34), '34 dk');
    expect(StatsFmt.minutes(80), '1 sa 20 dk');
    expect(StatsFmt.minutes(120), '2 sa');
    expect(StatsFmt.minutes(60 * 27), '1 g 3 sa');
    expect(StatsFmt.minutes(null), '—');
  });

  test('ekran okuyucu', () {
    expect(StatsFmt.moneySpoken(21500000), '21,5 milyon lira');
    expect(StatsFmt.moneySpoken(820000), '820 bin lira');
    expect(StatsFmt.moneySpoken(950), '950 lira');
    expect(StatsFmt.litersSpoken(1200000), '1,2 milyon litre');
    expect(StatsFmt.litersSpoken(512000), '512.000 litre');
  });

  test('dönem aralığı (Türkiye takvimi)', () {
    final a = TrTime.fromWall(2026, 10, 1);
    final b = TrTime.fromWall(2026, 10, 21, 14);
    expect(StatsFmt.range(a, b), '1–21 Ekim 2026');
    expect(
      StatsFmt.range(TrTime.fromWall(2026, 7, 24), b),
      '24 Tem – 21 Eki 2026',
    );
    expect(
      StatsFmt.range(TrTime.fromWall(2025, 1, 1), b),
      '1 Oca 2025 – 21 Eki 2026',
    );
    expect(StatsFmt.range(a, a), '1 Ekim 2026');
    expect(StatsFmt.range(null, b), '—');
  });
}

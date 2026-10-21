import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../core/utils/format.dart';
import '../../../core/utils/tr_number.dart';
import '../../../core/utils/tr_time.dart';
import '../data/form_models.dart';
import '../data/home_models.dart';
import '../data/payment_models.dart';
import '../data/place_models.dart';
import 'wizard_models.dart';

/// Tahmini tutar: Σ litre × geçerli ₺/L (2 hane). Fiyatı bilinmeyen satır varsa [unknown].
@immutable
class Estimate {
  const Estimate({this.value, this.unknown = false, this.empty = false});

  final double? value;

  /// Bir ürünün fiyatı bilinmiyor (bağlı değil / fiyat yok).
  final bool unknown;

  /// Hesaplanacak satır yok.
  final bool empty;

  static Estimate of(OrderDraft draft, Map<int, double> prices) {
    var total = 0.0;
    var counted = 0;
    for (final l in draft.lines) {
      final liters = l.liters ?? 0;
      if (l.productId == null || liters <= 0) continue;
      final p = prices[l.productId];
      if (p == null || p <= 0) return const Estimate(unknown: true);
      total += liters * p;
      counted++;
    }
    if (counted == 0) return const Estimate(empty: true);
    return Estimate(value: (total * 100).roundToDouble() / 100);
  }

  /// Satırın tahmini tutarı.
  static double? line(DraftLine l, Map<int, double> prices) {
    final p = prices[l.productId];
    final liters = l.liters ?? 0;
    if (p == null || liters <= 0) return null;
    return (liters * p * 100).roundToDouble() / 100;
  }
}

/// Uyarı (engellemez) ya da hata (adımı geçirmez).
@immutable
class RuleIssue {
  const RuleIssue(this.message, {this.blocking = true, this.field});
  final String message;
  final bool blocking;

  /// İlgili alan (`amount`, `dueDate`, `term`, satır uid …).
  final String? field;

  @override
  String toString() => 'RuleIssue($field: $message)';
}

/// Sihirbaz kuralları (spec A.4 A2 kuralları + web ödeme seçicisi `akn-payment-picker.js` portu).
abstract final class WizardRules {
  static const maxLines = 20;
  static const maxLiters = 999999999.0;
  static const maxMoney = 999999999.99;
  static const maxNote = 1000;
  static const maxTemplateName = 100;

  /// Vade adımları (web `TERM_STEPS`).
  static const termSteps = [
    0,
    1,
    3,
    7,
    10,
    14,
    15,
    20,
    30,
    45,
    60,
    75,
    90,
    105,
    120,
    150,
    180,
  ];

  // ------------------------------------------------------------------ Ürünler

  /// Satır hataları (uid → mesaj) ve bayi hatası (`station`).
  static List<RuleIssue> products(
    OrderDraft d, {
    required List<StationOption> stations,
    required OrderFormOptions? form,
  }) {
    final out = <RuleIssue>[];
    if (stations.length > 1) {
      final s = stations.where((x) => x.id == d.stationId).firstOrNull;
      if (s == null) {
        out.add(const RuleIssue('Bayi seçin.', field: 'station'));
      } else if (!s.canOrder) {
        out.add(
          RuleIssue(
            s.blockReason ?? 'Bu bayide şu an sipariş veremezsiniz.',
            field: 'station',
          ),
        );
      }
    }
    if (d.lines.isEmpty) {
      out.add(const RuleIssue('En az bir ürün satırı ekleyin.'));
    }
    if (d.lines.length > maxLines) {
      out.add(const RuleIssue('Tek seferde en çok 20 satır gönderilebilir.'));
    }
    for (final l in d.lines) {
      final err = lineError(l, form);
      if (err != null) out.add(RuleIssue(err, field: l.uid));
    }
    return out;
  }

  static String? lineError(DraftLine l, OrderFormOptions? form) {
    if (l.productId == null) return 'Ürün seçin.';
    if (form != null && form.product(l.productId) == null) {
      return 'Ürün artık satışta değil; başka bir ürün seçin.';
    }
    final v = l.liters;
    if (v == null || v <= 0) return 'Litre girin.';
    if (v > maxLiters) return 'Litre en çok 999.999.999 olabilir.';
    if (((v * 1000).round() - v * 1000).abs() > 1e-6) {
      return 'Litre en çok üç ondalık hane içerebilir.';
    }
    return null;
  }

  // ------------------------------------------------------------------ Teslimat

  static List<RuleIssue> delivery(
    OrderDraft d, {
    required OrderFormOptions? form,
    DateTime? minDate,
  }) {
    final out = <RuleIssue>[];
    final today = TrTime.todayStart();
    final earliest = minDate != null && minDate.isAfter(today)
        ? minDate
        : today;
    if (d.pointId == null || (form != null && form.point(d.pointId) == null)) {
      out.add(const RuleIssue('Teslimat noktası seçin.', field: 'point'));
    }
    final date = d.date;
    if (date == null) {
      out.add(const RuleIssue('Teslim tarihi seçin.', field: 'date'));
    } else if (TrTime.dayDiff(earliest, date) < 0) {
      out.add(
        RuleIssue(
          'Teslim tarihi en erken ${Fmt.date(earliest)} olabilir.',
          field: 'date',
        ),
      );
    }
    for (final l in d.lines.where((x) => x.custom)) {
      final p = d.pointOf(l);
      if (p == null || (form != null && form.point(p) == null)) {
        out.add(RuleIssue('Satırın teslimat noktasını seçin.', field: l.uid));
      }
      final ld = d.dateOf(l);
      if (ld != null && TrTime.dayDiff(earliest, ld) < 0) {
        out.add(
          RuleIssue(
            'Satırın teslim tarihi en erken ${Fmt.date(earliest)} olabilir.',
            field: l.uid,
          ),
        );
      }
    }
    return out;
  }

  /// Tank uyarıları: noktaya giden toplam litre tank kapasitesini aşıyor (engellemez).
  static List<RuleIssue> tankWarnings(OrderDraft d, OrderFormOptions? form) {
    if (form == null) return const [];
    final out = <RuleIssue>[];
    d.litersByPoint().forEach((pointId, liters) {
      final p = form.point(pointId);
      final cap = p?.tankCapacityLiters;
      if (p == null || cap == null || cap <= 0 || liters <= cap) return;
      out.add(
        RuleIssue(
          '${p.name}: toplam ${Fmt.liters(liters)} tank kapasitesini '
          '(${Fmt.liters(cap)}) aşıyor. Teslimat birden fazla sevkiyata bölünebilir; '
          'gerekirse litreyi azaltın.',
          blocking: false,
          field: 'tank:$pointId',
        ),
      );
    });
    return out;
  }

  // ------------------------------------------------------------------ Ödeme

  /// Seçilebilir vadeler (web `termOptions`).
  static List<int> termOptions(PaymentMethodOption m, [int? current]) {
    final min = max(0, m.minTermDays);
    final mx = m.maxTermDays;
    final set = <int>{};
    void add(int? v) {
      if (v != null && v >= min && v <= mx) set.add(v);
    }

    termSteps.forEach(add);
    add(min);
    add(mx);
    add(m.defaultTermDays);
    add(current);
    return set.toList()..sort();
  }

  /// Varsayılan vade: kayıtlı, yoksa yöntemin varsayılanı, yoksa en kısa.
  static int? defaultTerm(PaymentMethodOption m) {
    if (!m.hasTerm) return 0;
    final d = m.defaultTermDays;
    if (d != null && d >= m.minTermDays && d <= m.maxTermDays) return d;
    return null;
  }

  /// Kullanıcının yazdığı tutar (geçersizse null).
  static double? parseMoney(String? text) {
    final v = TrNumber.parse(text);
    if (v == null || v <= 0) return null;
    return v;
  }

  /// Sunucuya giden kanonik tutar (`125000.50`).
  static String canonicalMoney(double v) => v.toStringAsFixed(2);

  /// Çek / senet vadesi sınırı (sunucu `InstrumentDueError` ile aynı): teslimden en çok maxTerm gün.
  static String? instrumentDueError(
    PaymentMethodOption m,
    DateTime delivery,
    DateTime due,
  ) {
    if (!m.hasTerm) return null;
    final days = TrTime.dayDiff(delivery, due);
    if (days <= m.maxTermDays) return null;
    return '${m.displayName} vade tarihi en geç '
        '${Fmt.date(TrTime.addDays(delivery, m.maxTermDays))} olabilir '
        '(teslimden en çok ${m.maxTermDays} gün; girilen tarih $days gün sonra).';
  }

  /// Çek / senet vadesinden vade (gün): teslimden önceki tarihte en kısa vade.
  static int termFromDue(
    PaymentMethodOption m,
    DateTime delivery,
    DateTime due,
  ) => max(m.minTermDays, TrTime.dayDiff(delivery, due));

  /// Ödeme alanı hataları (alan anahtarı → mesaj) + genel hatalar.
  static List<RuleIssue> payment(
    OrderDraft d, {
    required PaymentOptions? options,
    required Estimate estimate,
  }) {
    final out = <RuleIssue>[];
    if (options == null) return out;
    if (!options.enabled) return out;
    final blocked = options.blockedReason;
    if (blocked != null) {
      out.add(RuleIssue(blocked, field: 'blocked'));
      return out;
    }
    final m = options.method(d.payment.methodCode);
    if (m == null) return out;
    final p = d.payment;
    if (m.hasTerm && p.termDays == null) {
      out.add(
        RuleIssue('${m.displayName} için vade (gün) seçin.', field: 'term'),
      );
    }
    final today = TrTime.todayStart();
    for (final f in m.fields) {
      final v = (p.fields[f.key] ?? '').trim();
      String? err;
      if (v.isEmpty) {
        if (f.required) err = '${f.label} zorunludur.';
      } else {
        switch (f.type) {
          case 'money':
            final n = parseMoney(v);
            if (n == null) {
              err = '${f.label} geçerli bir tutar olmalı (ör. 125.000,50).';
            } else if (n > maxMoney) {
              err = '${f.label} en çok 999.999.999,99 ₺ olabilir.';
            }
          case 'date':
            final dt = TrTime.parseDate(v);
            if (dt == null) {
              err = '${f.label} geçerli bir tarih olmalı.';
            } else if (f.key == 'dueDate' && TrTime.dayDiff(today, dt) < 0) {
              err = 'Vade tarihi geçmiş bir tarih olamaz.';
            } else if (f.key == 'dueDate' && m.isInstrument && d.date != null) {
              err = instrumentDueError(m, d.date!, dt);
            }
          case 'number':
            if (!RegExp(r'^\d+$').hasMatch(v)) {
              err = '${f.label} pozitif bir tam sayı olmalı.';
            }
          default:
            final maxLen = f.maxLength;
            if (maxLen != null && v.length > maxLen) {
              err = '${f.label} en çok $maxLen karakter olabilir.';
            }
        }
      }
      if (err != null) out.add(RuleIssue(err, field: f.key));
    }
    if (m.code == PaymentCodes.advance) {
      final bal = options.advanceBalance;
      final est = estimate.value;
      if (bal != null && est != null && est > bal) {
        out.add(
          RuleIssue(
            'Ön ödemeli bakiye yetersiz: kullanılabilir ${Fmt.money(bal)}, '
            'tahmini tutar ${Fmt.money(est)}.',
            field: 'advance',
          ),
        );
      }
    }
    return out;
  }

  /// Ödeme uyarıları (engellemez): çek / senet tutarı tahmini tutardan farklı, vade teslimden önce.
  static List<RuleIssue> paymentWarnings(
    OrderDraft d, {
    required PaymentOptions? options,
    required Estimate estimate,
  }) {
    final out = <RuleIssue>[];
    final m = options?.method(d.payment.methodCode);
    if (m == null || !m.isInstrument) return out;
    final amount = parseMoney(d.payment.fields['amount']);
    final est = estimate.value;
    if (amount != null && est != null) {
      final diff = (amount - est).abs();
      if (diff >= 1 && diff / est > 0.005) {
        out.add(
          RuleIssue(
            '${m.displayName} tutarı (${Fmt.money(amount)}) tahmini tutardan '
            '(${Fmt.money(est)}) farklı. Kesin tutar teklifle belirlenir; farkı '
            'bayinizle netleştirin.',
            blocking: false,
            field: 'amount',
          ),
        );
      }
    }
    final due = TrTime.parseDate(d.payment.fields['dueDate']);
    final date = d.date;
    if (due != null && date != null) {
      final days = TrTime.dayDiff(date, due);
      if (days < 0) {
        out.add(
          RuleIssue(
            'Vade tarihi teslim tarihinden önce; ödeme tarihi olarak '
            '${Fmt.date(due)} kaydedilir.',
            blocking: false,
            field: 'dueDate',
          ),
        );
      } else if (d.payment.termDays != null &&
          days != d.payment.termDays &&
          days >= m.minTermDays) {
        out.add(
          RuleIssue(
            'Vade tarihi teslim + ${d.payment.termDays} gün '
            '(${Fmt.date(TrTime.addDays(date, d.payment.termDays!))}) ile aynı değil; '
            'ödeme tarihi belgenin vadesi (${Fmt.date(due)}) olur.',
            blocking: false,
            field: 'dueDate',
          ),
        );
      }
    }
    return out;
  }

  /// Ödeme tarihi: çek / senette belgenin vadesi, aksi halde teslim + vade.
  static DateTime? paymentDueDate(OrderDraft d, PaymentMethodOption? m) {
    if (m == null || d.date == null) return null;
    if (m.isInstrument) {
      final due = TrTime.parseDate(d.payment.fields['dueDate']);
      if (due != null) return due;
    }
    final t = d.payment.termDays ?? (m.hasTerm ? null : 0);
    if (t == null) return null;
    return TrTime.addDays(d.date!, t);
  }

  /// "Çek · 60 gün · vade 20.12.2026".
  static String paymentSummary(OrderDraft d, PaymentMethodOption? m) {
    if (m == null) return 'Belirtilmedi';
    final parts = <String>[m.displayName];
    final t = d.payment.termDays;
    if (t != null && t > 0) {
      parts.add('$t gün');
    } else if (!m.hasTerm) {
      parts.add('peşin');
    }
    final inst = d.payment.installments;
    if (inst != null && inst > 1) parts.add('$inst taksit');
    final due = paymentDueDate(d, m);
    if (due != null) {
      parts.add('${(t ?? 0) > 0 ? 'vade' : 'ödeme'} ${Fmt.date(due)}');
    }
    return parts.join(' · ');
  }

  // ------------------------------------------------------------------ İstek

  /// Gönderilecek gövde. Para alanları kanonik biçime (`0.00`) çevrilir.
  static PlaceOrderRequest buildRequest(
    OrderDraft d, {
    required PaymentOptions? options,
    required bool companyRequestPredicted,
  }) {
    final m = options != null && options.enabled
        ? options.method(d.payment.methodCode)
        : null;
    PaymentSelection? payment;
    if (m != null) {
      final details = <String, String>{};
      for (final f in m.fields) {
        final v = (d.payment.fields[f.key] ?? '').trim();
        if (v.isEmpty) continue;
        if (f.type == 'money') {
          final n = parseMoney(v);
          details[f.key] = n == null ? v : canonicalMoney(n);
        } else {
          details[f.key] = v;
        }
      }
      payment = PaymentSelection(
        methodCode: m.code,
        termDays: m.hasTerm ? d.payment.termDays : 0,
        installments: m.hasInstallments ? d.payment.installments : null,
        details: details,
      );
    }
    final lines = <PlaceOrderLine>[
      for (final l in d.lines)
        PlaceOrderLine(
          productId: l.productId!,
          quantityLiters: _round3(l.liters ?? 0),
          deliveryPointId: l.custom ? d.pointOf(l) : null,
          requestedDeliveryDate: l.custom ? d.dateOf(l) : null,
        ),
    ];
    return PlaceOrderRequest(
      stationId: d.stationId ?? 0,
      deliveryPointId: d.pointId ?? 0,
      requestedDeliveryDate: d.date ?? TrTime.todayStart(),
      lines: lines,
      payment: payment,
      paymentGroupKey: d.paymentGroupKey,
      note: companyRequestPredicted && d.note.trim().isNotEmpty
          ? d.note.trim()
          : null,
      templateId: d.templateId,
    );
  }

  static double _round3(double v) => (v * 1000).roundToDouble() / 1000;
}

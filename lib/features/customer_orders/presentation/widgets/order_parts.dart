import 'package:flutter/material.dart';

import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/permissions.dart';
import '../../../../core/models/models.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../../../core/utils/turkish_text.dart';

/// Ortak sipariş parçaları (tasarım v2 "Turuncu Plaka"): kısa adlar, gün metinleri, bölüm başlığı,
/// olgu satırı ve izleyiciye göre durum lambası.

/// "Motorin, 8.000 L".
String orderTitle(String? product, double liters) {
  final p = product?.trim();
  return p == null || p.isEmpty
      ? Fmt.liters(liters)
      : '$p, ${Fmt.liters(liters)}';
}

/// "22 Ekim".
String dayMonthLong(DateTime? instant) {
  if (instant == null) return Fmt.dash;
  final w = TrTime.wall(instant);
  return '${w.day} ${Fmt.monthNames[w.month - 1]}';
}

/// "22 Ekim Perşembe".
String dayMonthWeekday(DateTime? instant) {
  if (instant == null) return Fmt.dash;
  return '${dayMonthLong(instant)} ${Fmt.weekday(instant)}';
}

/// Cümle içinde gün: "bugün", "yarın", "dün", değilse "22 Ekim".
String relativeDay(DateTime? instant) {
  if (instant == null) return Fmt.dash;
  final diff = TrTime.dayDiff(TrTime.now(), instant);
  return switch (diff) {
    0 => 'bugün',
    1 => 'yarın',
    -1 => 'dün',
    _ => dayMonthLong(instant),
  };
}

/// "bugün 10:05", "dün 14:20", "18 Ekim 09:12".
String relativeMoment(DateTime? instant) {
  if (instant == null) return Fmt.dash;
  return '${relativeDay(instant)} ${Fmt.time(instant)}';
}

/// Unvandaki hukuki ekleri ve sondaki sektör sözcüklerini atar: "Demir Petrol Akaryakıt Ltd. Şti."
/// → "Demir Petrol". En az iki sözcük kalır; kısaltılamıyorsa unvan aynen döner.
String shortCompany(String? title) {
  final original = (title ?? '').trim();
  var s = original;
  if (s.isEmpty) return s;
  final legal = RegExp(
    r'(\s+(ltd\.?|şti\.?|a\.?ş\.?|san\.?|tic\.?|ve|limited|şirketi|anonim))+\.?$',
    caseSensitive: false,
  );
  const sector = {
    'akaryakıt',
    'petrol ürünleri',
    'ticaret',
    'sanayi',
    'dağıtım',
    'pazarlama',
  };
  var changed = true;
  while (changed) {
    changed = false;
    final stripped = s.replaceFirst(legal, '').trim();
    if (stripped != s && stripped.isNotEmpty) {
      s = stripped;
      changed = true;
    }
    for (final word in sector) {
      final lower = TurkishText.lower(s);
      if (lower.endsWith(' $word')) {
        final rest = s.substring(0, s.length - word.length - 1).trim();
        if (rest.split(RegExp(r'\s+')).length >= 2) {
          s = rest;
          changed = true;
        }
      }
    }
  }
  return s.isEmpty ? original : s;
}

/// Müşteri izleyicisi: kararı veren (yönetici / onaylayan) "sıra sizde" lambasını görür.
StatusViewer customerViewer(AccessPolicy policy) =>
    StatusViewer.customer(canDecide: policy.can(Pg.customerQuotes, Perm.edit));

/// Siparişin müşteriye görünen lambası (§10.3): finans incelemesi sürerken finans lambası,
/// değilse sipariş / sevkiyat lambası.
StatusLamp orderLampFor(
  StatusViewer viewer, {
  required OrderStatus status,
  String? serverLabel,
  ShipmentStatus? shipment,
  OrderFinanceStatus finance = OrderFinanceStatus.notRequired,
  String? financeLabel,
}) {
  if (finance.isAwaitingDecision) {
    final s = AknStatus.finance(finance).withLabel(financeLabel);
    return StatusLamp(
      tone: AknTone.info,
      label: finance == OrderFinanceStatus.infoRequested
          ? 'Finans ek bilgi istedi'
          : 'Finans onayında',
      icon: s.icon,
      stage: AknStage.talep,
    );
  }
  if (finance == OrderFinanceStatus.rejected) {
    return StatusLamp(
      tone: AknTone.danger,
      label: 'Finans reddetti',
      icon: AknStatus.finance(finance).icon,
      stage: AknStage.talep,
      problem: true,
    );
  }
  return AknStatus.lampFor(
    status,
    viewer,
    serverLabel: serverLabel,
    shipment: shipment,
  );
}

/// Bölüm (§4.5): başlık 20/26 + içerik, kutu yok. İçerik 20 px kenar boşluğuyla gelir; ledger
/// satırları için [bleed] (tam genişlik).
class OrderSection extends StatelessWidget {
  const OrderSection({
    super.key,
    required this.title,
    required this.child,
    this.count,
    this.caption,
    this.actionLabel,
    this.onAction,
    this.bleed = false,
  });

  final String title;
  final Widget child;
  final int? count;
  final String? caption;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool bleed;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      SectionHeader(
        title: title,
        count: count,
        caption: caption,
        actionLabel: actionLabel,
        onAction: onAction,
      ),
      if (bleed)
        child
      else
        Padding(padding: AknSpace.pagePadding, child: child),
    ],
  );
}

/// Bir olgu cümlesi (§7.8 ödeme satırı): 20 px simge (tonun rengi) + 15/22 metin.
class FactLine extends StatelessWidget {
  const FactLine({
    super.key,
    required this.icon,
    required this.text,
    this.tone,
    this.strong,
  });

  final IconData icon;
  final String text;

  /// Simgenin rengi (ok yeşil, warn koyu sarı …); null ise soluk.
  final AknTone? tone;

  /// Cümlenin sonuna kalın eklenen kısım.
  final String? strong;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final color = tone == null ? c.dim : c.tone(tone!).fg;
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: text,
                children: [
                  if (strong != null)
                    TextSpan(
                      text: strong,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                ],
              ),
              style: t.body.copyWith(color: c.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// Büyük figür için tutarı ikiye böler: "338.800" + ",00".
(String, String?) splitMoney(double value) {
  final s = Fmt.number(value, minFraction: 2, maxFraction: 2);
  final i = s.lastIndexOf(',');
  if (i < 0) return (s, null);
  return (s.substring(0, i), s.substring(i));
}

/// Ekran okuyucu için tutar: "338.800,00 lira".
String spokenMoney(double? value) => value == null
    ? Fmt.dash
    : '${Fmt.number(value, minFraction: 2, maxFraction: 2)} lira';

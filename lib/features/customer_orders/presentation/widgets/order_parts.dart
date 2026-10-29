import 'package:flutter/material.dart';

import '../../../../core/auth/access_policy.dart';
import '../../../../core/auth/permissions.dart';
import '../../../../core/models/models.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../data/payment_models.dart';

/// Ortak sipariş parçaları (tasarım v3 "Akış"): kısa adlar, gün metinleri, aşama simgesi, bölüm
/// kartı, olgu satırı ve izleyiciye göre durum lambası.

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

/// Siparişin müşteriye görünen lambası (§10.3; v4 §3.2 müşteri sözcükleri): bayinin finansı
/// incelerken "Bayinizde inceleniyor", bilgi isterken "Bayiniz bilgi istiyor" (karar verebilen için
/// sıra sizde); değilse sipariş / sevkiyat lambası. Karar verebilen müşterinin teklifinde ödeme
/// belgesi eksikse tek lamba belgeyi söyler ([missingDocument]: "Çek görselini yükleyin"); teklifi
/// hazırlayan bayi [actor] ile adlandırılır ("Demir Petrol teklif hazırlıyor").
StatusLamp orderLampFor(
  StatusViewer viewer, {
  required OrderStatus status,
  String? serverLabel,
  ShipmentStatus? shipment,
  OrderFinanceStatus finance = OrderFinanceStatus.notRequired,
  String? financeLabel,
  String? actor,
  String? missingDocument,
}) {
  if (finance.isAwaitingDecision) {
    final s = AknStatus.finance(finance).withLabel(financeLabel);
    final asked = finance == OrderFinanceStatus.infoRequested;
    return StatusLamp(
      tone: asked && viewer.canDecide ? AknTone.brand : AknTone.info,
      label: asked ? 'Bayiniz bilgi istiyor' : 'Bayinizde inceleniyor',
      icon: s.icon,
      stage: AknStage.talep,
    );
  }
  if (finance == OrderFinanceStatus.rejected) {
    return StatusLamp(
      tone: AknTone.danger,
      label: 'Bayiniz onaylamadı',
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
    actor: actor,
    missingDocument: missingDocument,
  );
}

/// Eksik ödeme belgesinin buyruğu ("Çek görselini yükleyin"); belge türü bilinmiyorsa satırın ödeme
/// yöntemi kodundan (çek, senet, havale) çıkarılır.
String? missingDocumentPhrase({
  required bool missing,
  AttachmentKind? kind,
  String? methodCode,
}) {
  if (!missing) return null;
  final k = kind ?? attachmentKindForMethod(methodCode);
  return AknStatus.uploadPhrase(k ?? AttachmentKind.unknown);
}

/// Ödeme yönteminin istediği belge (sunucunun yöntem kodları: CEK, SENET, HAVALE …).
AttachmentKind? attachmentKindForMethod(String? code) =>
    switch ((code ?? '').trim().asciiUpper) {
      PaymentCodes.cheque => AttachmentKind.chequeImage,
      PaymentCodes.promissoryNote => AttachmentKind.promissoryNoteImage,
      PaymentCodes.transfer => AttachmentKind.transferReceipt,
      _ => null,
    };

/// Siparişin aşamasını anlatan simge: teklif bekleniyor (kum saati), karar (teklif), plan
/// (takvim), yolda (tır), teslim (kontrol listesi), tamam (mühür), sorun.
IconData orderStageIcon(StatusLamp lamp) {
  if (lamp.problem) return PhosphorIconsRegular.warningOctagon;
  if (lamp.complete) return PhosphorIconsRegular.sealCheck;
  return switch (lamp.stage) {
    AknStage.talep ||
    AknStage.onay ||
    AknStage.teklif => PhosphorIconsRegular.hourglassMedium,
    AknStage.karar => PhosphorIconsRegular.invoice,
    AknStage.plan => PhosphorIconsRegular.calendarCheck,
    AknStage.yolda => PhosphorIconsRegular.truck,
    AknStage.teslim => PhosphorIconsRegular.listChecks,
    null => PhosphorIconsRegular.gasPump,
  };
}

/// Kart içindeki satırların dolgusu (defter satırıyla aynı iç kenar).
const a2RowPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 12);

/// Bölüm (tasarım v4 §4): çekirdeğin [SectionHeader]'ı (17/22 700, sayı soluk metin, sağda
/// eylem) ve altında tek defter kartı ([AknLedger]: beyaz r20, yalnızca ince gölge). İçerik kartın
/// 20 px iç kenarıyla gelir; satırlar için [bleed] (satırlar kendi dolgusunu taşır, aralarında
/// içeriden çizgi).
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
        padding: const EdgeInsets.fromLTRB(24, 22, 12, 6),
      ),
      AknLedger(
        children: [
          if (bleed)
            child
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
              child: child,
            ),
        ],
      ),
    ],
  );
}

/// Bir olgu cümlesi: tonun renginde 20 px simge (karo yok) + 15/22 metin.
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
    final style = t.body.copyWith(color: c.ink);
    final tn = tone;
    final color = tn == null || tn == AknTone.neutral || tn == AknTone.info
        ? c.dim
        : c.tone(tn).fg;
    // Simge ilk satırın ortasında durur (çok satırlı cümlede üstte kalır).
    final line = MediaQuery.textScalerOf(context).scale(15) * 22 / 15;
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: ((line - 20) / 2).clamp(0, 8)),
            child: ExcludeSemantics(child: Icon(icon, size: 20, color: color)),
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
              style: style,
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

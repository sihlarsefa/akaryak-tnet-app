import 'package:flutter/material.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../copy.dart';
import '../../data/approval_models.dart';

/// Satırın durum görünümü. Cari tarafında bayinin iç süreci "Bayi değerlendirmesi" olarak görünür.
StatusStyle approvalStatusStyle(
  ApprovalRow row, {
  required bool customerSide,
  bool canProvideInfo = false,
}) {
  if (customerSide && row.type != ApprovalType.companyOrderRequest) {
    switch (row.status) {
      case ApprovalStatus.pending:
        return const StatusStyle(
          tone: AknTone.warn,
          icon: PhosphorIconsRegular.hourglassHigh,
          label: 'Bayinizde inceleniyor',
        );
      case ApprovalStatus.infoRequested:
        return StatusStyle(
          tone: canProvideInfo ? AknTone.brand : AknTone.info,
          icon: PhosphorIconsFill.chatCircleDots,
          label: canProvideInfo ? 'Bayiniz bilgi istiyor' : 'Bilgi bekleniyor',
        );
      default:
        break;
    }
  }
  return AknStatus.approval(row.status).withLabel(row.statusLabel);
}

/// SLA çipi (yalnızca bayi / merkez görünümünde, açık taleplerde).
StatusStyle? slaStyle(ApprovalRow row) {
  if (!row.status.isOpen) return null;
  return switch (row.slaState) {
    ApprovalSlaState.overdue => AknStatus.sla(ApprovalSlaState.overdue),
    ApprovalSlaState.dueSoon => AknStatus.sla(ApprovalSlaState.dueSoon),
    _ => null,
  };
}

/// Satırın izleyiciye göre lambası (ayrıntı başlığı): bekleyen talep, karar veren için "Karar
/// verin" (Pas, sıra sizde), diğerleri için "Onay bekleniyor"; süresi geçen talep kırmızı. Cari
/// tarafında bayinin iç süreci tek lamba ("Bayinizde inceleniyor").
StatusLamp approvalRowLamp(
  ApprovalRow row, {
  required bool customerSide,
  bool canProvideInfo = false,
}) {
  final internal = customerSide && row.type != ApprovalType.companyOrderRequest;
  if (internal || row.status != ApprovalStatus.pending) {
    return StatusLamp.fromStyle(
      approvalStatusStyle(
        row,
        customerSide: customerSide,
        canProvideInfo: canProvideInfo,
      ),
    );
  }
  return AknStatus.approvalLamp(
    row.status,
    customerSide
        ? StatusViewer.customer(canDecide: row.canDecide)
        : StatusViewer.bayi(canDecide: row.canDecide),
    sla: row.slaState,
    serverLabel: row.statusLabel,
  );
}

/// Sunucu özetindeki " · " ayırıcılarını düz yazıma çevirir (", ").
String plainSummary(String? s) => (s ?? '').replaceAll(' · ', ', ').trim();

/// Belge / sipariş numarası gibi kod mu ("SSF-20261028-000002", "TLP-00031"): satırda yazılmaz
/// (v4 P4: kodlar yalnızca ayrıntıda kopyalanabilir alt yazı).
bool _isCode(String s) =>
    RegExp(r'^[A-ZÇĞİÖŞÜ]{2,5}-[\d-]+$').hasMatch(s.trim());

/// Cümlenin ilk harfini küçültür ("Açık hesap 30 gün" → "açık hesap 30 gün"); kısaltma ve
/// özel ad gibi duranlar (ikinci harfi büyük, ör. "VKN") olduğu gibi kalır.
String _lowerFirst(String s) {
  if (s.length < 2) return TurkishText.lower(s);
  final second = s.substring(1, 2);
  if (second != TurkishText.lower(second)) return s;
  return '${TurkishText.lower(s.substring(0, 1))}${s.substring(1)}';
}

/// "2 g", "5 sa", "40 dk": gecikmenin en büyük birimi.
String overdueShort(Duration d) {
  if (d.inDays > 0) return '${d.inDays} g';
  if (d.inHours > 0) return '${d.inHours} sa';
  return '${d.inMinutes.clamp(1, 59)} dk';
}

/// "bugün 10:05", "dün 14:20", "21 Eki"; [withDay] false iken bugün ve dün yalnızca saat (satır
/// zaten "Bugün" / "Dün" grubunda).
String rowStamp(DateTime? at, {bool withDay = true}) {
  if (at == null) return '';
  final diff = TrTime.dayDiff(TrTime.now(), at);
  if (diff == 0) return withDay ? 'bugün ${Fmt.time(at)}' : Fmt.time(at);
  if (diff == -1) return withDay ? 'dün ${Fmt.time(at)}' : Fmt.time(at);
  return Fmt.dayMonth(at);
}

/// Satırın sağındaki tutar: kuruşsuzsa tam ("840.000 ₺"), yoksa kuruşlu; tutar yoksa litre.
String? rowAmount(ApprovalRow row) {
  final a = row.amount;
  if (a != null) {
    final whole = (a - a.roundToDouble()).abs() < 0.005;
    return whole ? Fmt.moneyWhole(a) : Fmt.money(a);
  }
  return row.liters == null ? null : Fmt.liters(row.liters);
}

/// Satırın nasıl göründüğü (Onaylar listesinin bağlamı).
enum ApprovalRowMode {
  /// Bende: karar bekleyen (tür · koşullar, sağda geri sayım / gecikme / zaman).
  decide,

  /// Bende › "Yanıt bekleniyor": talep edenden yanıt beklenir (nötr).
  waiting,

  /// Taleplerim, Kararlarım, Tümü: tür · sonuç, sağda zaman.
  history,
}

/// Onay satırı (tasarım v4 §5 08, 08b): bir defterin ([AknLedger]) içinde [AknListTile].
///
/// ```
/// [▢] Körfez Nakliyat ve Ticaret                               840.000 ₺
///     Saha formu finansı · açık hesap 30 gün                  2 g gecikti
/// ```
///
/// * Solda türün 36 dp nötr kutusu; L1 karşı taraf (bayide cari, carinin şirket talebinde talep
///   eden, carinin diğer taleplerinde bayi) ve sağda tutar; L2 tek soluk satır: tür · koşullar
///   (Bende), "Ek bilgi istendi · Deniz Koç" (yanıt bekleniyor) ya da tür · sonuç (geçmiş); sağda
///   kısa geri sayım, "2 g gecikti" (tehlike) ya da zaman.
/// * L3 yalnızca istisnada: sıra izleyicideyse fiil satırı ("Bilgi gönderin", Pas).
/// * Talep eden, kademe ve belge numarası ayrıntıya taşındı (v4 P4); turuncu kenar ve hap yok.
class ApprovalRowTile extends StatelessWidget {
  const ApprovalRowTile({
    super.key,
    required this.row,
    required this.onTap,
    required this.customerSide,
    this.mode = ApprovalRowMode.decide,
    this.viewerId,
    this.dayGrouped = false,
  });

  final ApprovalRow row;
  final VoidCallback onTap;

  /// Satır gün grubunda ("Bugün", "Dün"): zaman günsüz yazılır ("14:20"; v4 P4 bir kez).
  final bool dayGrouped;

  /// Kullanıcı cari mi (bayi iç ayrıntısı gösterilmez).
  final bool customerSide;
  final ApprovalRowMode mode;

  /// Oturumdaki kullanıcı (kendi talebinde ek bilgi istendiyse sıra onda).
  final String? viewerId;

  /// Karşı taraf: cari için bayi (şirket içi talepte talep eden); bayi için cari. Cari kaydı
  /// olmayan taleplerde (ön kayıt, yeni cari) özetin ilk parçası firmanın adıdır.
  ({String title, List<String> rest}) _who() {
    final parts = [
      for (final p in (row.summary ?? '').split(' · '))
        if (p.trim().isNotEmpty && !_isCode(p)) p.trim(),
    ];
    if (customerSide) {
      final company = row.type == ApprovalType.companyOrderRequest;
      // Kendi talebim: başlık istenen şey ("30.000 L Motorin"), kendi adım değil.
      if (company && _mine && parts.isNotEmpty) {
        return (title: parts.first, rest: parts.sublist(1));
      }
      final name = company ? row.requestedByName : row.stationTitle;
      return (title: name ?? ApprovalsCopy.typeName(row.type), rest: parts);
    }
    final customer = row.customerTitle;
    if (customer != null) {
      return (
        title: customer,
        rest: [
          for (final p in parts)
            if (p != customer) p,
        ],
      );
    }
    if (parts.length > 1) return (title: parts.first, rest: parts.sublist(1));
    return (
      title: row.requestedByName ?? ApprovalsCopy.typeName(row.type),
      rest: parts,
    );
  }

  /// Koşullar (L2'nin ikinci olgusu): ilk parça; tek sözcüklük ödeme yöntemi ("Çek") ise ardından
  /// gelenle ("çek, 45 gün vade"). Tutar sağda yazıyorsa tutarlı parçalar atlanır (v4 P4: bir kez).
  String? _termsOf(List<String> parts) => _terms([
    for (final p in parts)
      if (row.amount == null || !p.contains('₺')) p,
  ]);

  static String? _terms(List<String> rest) {
    if (rest.isEmpty) return null;
    final first = rest.first;
    final short = !RegExp(r'\d').hasMatch(first) && first.length <= 12;
    final text = short && rest.length > 1 ? '$first, ${rest[1]}' : first;
    return _lowerFirst(text);
  }

  bool get _mine => viewerId != null && row.requestedByUserId == viewerId;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final who = _who();
    final type = ApprovalsCopy.typeName(row.type);
    final open = row.status.isOpen;
    final now = TrTime.now();
    final due = row.dueAt;
    final overdue =
        !customerSide &&
        open &&
        (row.slaState == ApprovalSlaState.overdue ||
            (due != null && !due.isAfter(now)));
    // Talebi açan benim ve benden ek bilgi istendi: sıra bende.
    final replyMine =
        _mine && row.status == ApprovalStatus.infoRequested && !customerSide;
    final customerReply =
        customerSide &&
        row.status == ApprovalStatus.infoRequested &&
        row.type != ApprovalType.companyOrderRequest;

    final String subtitle;
    // Bende'de koşullar yalnızca satıra sığarsa yazılır (yarım söz kalmaz); yoksa yalnızca tür.
    String? terms;
    switch (mode) {
      case ApprovalRowMode.waiting:
        final asked = row.requestedByName;
        final first = TurkishText.searchKey(who.title.split(' ').first);
        final counterpart =
            asked != null &&
            first.isNotEmpty &&
            TurkishText.searchKey(asked).startsWith(first);
        subtitle = counterpart
            ? ApprovalsCopy.askedCustomer
            : [
                'Ek bilgi istendi',
                if (asked != null && !_mine) asked,
              ].join(' · ');
      case ApprovalRowMode.decide when !customerSide:
        subtitle = type;
        terms = _termsOf(who.rest);
      case _ when customerSide:
        final outcome = ApprovalsCopy.customerOutcome(
          row.type,
          row.status,
          canReply: customerReply,
        );
        subtitle = row.type == ApprovalType.companyOrderRequest
            ? [type, _lowerFirst(outcome)].join(' · ')
            : outcome;
      case _:
        subtitle = [type, ApprovalsCopy.outcome(row.status)].join(' · ');
    }

    // Sağdaki kısa bilgi: gecikme (tehlike), geri sayım (≤ 3 sa Pas), yoksa zaman.
    Widget? meta;
    String? spokenMeta;
    final metaStyle = t.label.copyWith(
      fontWeight: FontWeight.w500,
      color: c.dim,
      fontFeatures: AknNumerals.tabular,
    );
    if (mode == ApprovalRowMode.decide && overdue && due != null) {
      final late = '${overdueShort(now.difference(due))} gecikti';
      spokenMeta = late;
      meta = Text(
        late,
        maxLines: 1,
        softWrap: false,
        style: metaStyle.copyWith(
          fontWeight: FontWeight.w600,
          color: c.danger.fg,
        ),
      );
    } else if (mode == ApprovalRowMode.decide &&
        open &&
        due != null &&
        due.isAfter(now) &&
        !customerSide) {
      meta = CountdownBadge(
        deadline: due,
        yourMove: row.canDecide,
        compact: true,
        subject: 'Karar süresi',
      );
      spokenMeta = 'karar süresi ${CountdownBadge.spoken(due.difference(now))}';
    } else {
      final stamp = rowStamp(row.createdAt);
      final shown = dayGrouped
          ? rowStamp(row.createdAt, withDay: false)
          : stamp;
      if (shown.isNotEmpty) {
        spokenMeta = stamp;
        meta = Text(shown, maxLines: 1, softWrap: false, style: metaStyle);
      }
    }

    final next = replyMine || customerReply ? ApprovalsCopy.replyNext : null;
    final amount = rowAmount(row);
    final full = terms == null ? subtitle : '$subtitle · $terms';
    final semantic = [who.title, full, ?amount, ?spokenMeta, ?next].join(', ');

    Widget tile(String line) => AknListTile(
      leadingIcon: AknStatus.approvalType(row.type).icon,
      title: who.title,
      subtitle: line,
      amount: amount,
      metaWidget: meta,
      next: next,
      semanticLabel: semantic,
      onTap: onTap,
    );
    if (terms == null) return tile(subtitle);
    return LayoutBuilder(
      builder: (context, box) {
        final scaler = MediaQuery.textScalerOf(context);
        // Büyük yazıda satır alt alta dizilir; ikinci satır tüm genişliği kullanır.
        if (!box.hasBoundedWidth || scaler.scale(10) >= 13) return tile(full);
        double width(String text, TextStyle style) {
          final tp = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final w = tp.width;
          tp.dispose();
          return w;
        }

        // Sağdaki kısa bilgi: yazı + (geri sayımda) simge.
        final metaText =
            mode == ApprovalRowMode.decide && overdue && due != null
            ? '${overdueShort(now.difference(due))} gecikti'
            : (due != null && due.isAfter(now)
                  ? Fmt.countdown(due.difference(now))
                  : rowStamp(row.createdAt, withDay: !dayGrouped));
        final metaWidth =
            width(metaText, metaStyle.copyWith(fontWeight: FontWeight.w700)) +
            19 +
            12;
        // Satırın iç boşluğu (20 + 20) ve öndeki 36 dp kutu + 14 dp aralık.
        final room = box.maxWidth - 40 - 50 - metaWidth;
        final fits = width(full, t.bodySmall) <= room;
        return tile(fits ? full : subtitle);
      },
    );
  }
}

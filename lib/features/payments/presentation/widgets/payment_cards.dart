import 'package:flutter/material.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../../approvals/api.dart' show isLargeText;
import '../../data/payment_models.dart';

/// Vade ipucunun tonu (tasarım v2 §2.4): geciken kırmızı, bugün ya da 3 gün içinde Pas ("acil sayı"),
/// diğerleri sönük.
AknTone dueTone({required bool overdue, DateTime? due}) {
  if (overdue) return AknTone.danger;
  if (due == null) return AknTone.neutral;
  final days = TrTime.dayDiff(TrTime.now(), due);
  if (days <= 3) return AknTone.brand;
  return AknTone.neutral;
}

/// Vade günü: "21 Kasım" (bu yıl), değilse "21 Kasım 2027".
String dueDay(DateTime? at) {
  if (at == null) return Fmt.dash;
  final w = TrTime.wall(at);
  final day = '${w.day} ${Fmt.monthNames[w.month - 1]}';
  return w.year == TrTime.wall(TrTime.now()).year ? day : '$day ${w.year}';
}

/// Sunucunun vade ipucu ("bugün", "3 gün kaldı", "5 gün gecikti") satırın sağına uygun biçimde.
String dueHintText(String hint) => hint == 'bugün' ? 'Vadesi bugün' : hint;

/// Vade süresi: "Peşin" ya da "30 gün".
String termText(int? termDays) => termDays == null
    ? Fmt.dash
    : termDays == 0
    ? 'Peşin'
    : '$termDays gün';

/// Durum satırının sağındaki vade ipucu (§6.13 düzeni): takvim simgesi 17 + 14/20 metin; sönük 500,
/// 3 gün içinde Pas 600, gecikmede kırmızı 600 ve dolu simge.
class DueHint extends StatelessWidget {
  const DueHint({super.key, required this.text, required this.tone});

  final String text;
  final AknTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final color = switch (tone) {
      AknTone.danger => c.danger.fg,
      AknTone.brand => c.brandInk,
      AknTone.warn => c.warn.fg,
      _ => c.dim,
    };
    final strong = tone == AknTone.danger || tone == AknTone.brand;
    final style = t.bodySmall.copyWith(
      color: color,
      fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
    );
    final size = MediaQuery.textScalerOf(context).scale(17).clamp(17.0, 30.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          tone == AknTone.danger
              ? Icons.event_busy_rounded
              : Icons.event_outlined,
          size: size,
          color: color,
        ),
        const SizedBox(width: 6),
        Flexible(child: Text(text, style: style)),
      ],
    );
  }
}

/// Çek / senet durumunun lambası: portföydeki açık belge "süreçte" (mürekkep), sonuçlananlar kendi
/// tonunda (tahsil yeşil, karşılıksız / protesto kırmızı, iade kapalı).
StatusStyle instrumentLamp(Instrument i) {
  final base = AknStatus.instrument(i.status).withLabel(i.statusLabel);
  return i.isOpen ? base.copyWith(tone: AknTone.info) : base;
}

/// Ödemenin finans durumu satırda yalnızca beklenen bir şey varsa yazılır (onaylı olan gürültüdür).
bool financeWorthShowing(OrderFinanceStatus s) =>
    s == OrderFinanceStatus.pending ||
    s == OrderFinanceStatus.infoRequested ||
    s == OrderFinanceStatus.rejected;

/// Ödeme satırı (tasarım v2 §6.8, §7.14): cari, sağda tutar; ikinci satırda sipariş no ve yöntem,
/// sağda vade günü (tahminiyse "tahmini" ve vade ikinci satıra geçer); durum satırında lamba ve vade
/// ipucu. Finans onayı bekleyen, bilgi istenen ya da reddedilen ödemede finans durumu ikinci satırda.
class PaymentRowCard extends StatelessWidget {
  const PaymentRowCard({super.key, required this.row, required this.onTap});

  final PaymentRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = AknStatus.payment(
      row.paymentStatus,
    ).withLabel(row.paymentStatusLabel);
    final overdue = row.isOverdue || row.overdueDays > 0;
    final amount = row.displayAmount;
    final finance = financeWorthShowing(row.financeStatus)
        ? (row.financeLabel ?? row.financeStatus.label)
        : null;
    final second = [
      row.orderNumber,
      ?row.methodName,
      if (row.installments != null && row.installments! > 1)
        '${row.installments} taksit',
      if (row.isEstimate && row.dueDate != null) 'vade ${dueDay(row.dueDate)}',
      if (finance != null) lowerFirst(finance),
    ].join(', ');
    final hint = row.dueHint;
    final semantic = [
      row.customerTitle,
      if (amount != null)
        '${row.isEstimate ? 'tahmini ' : ''}${Fmt.money(amount)}',
      row.orderNumber,
      ?row.methodName,
      if (row.termDays != null) 'vade ${termText(row.termDays)}',
      if (row.dueDate != null) 'son ödeme günü ${dueDay(row.dueDate)}',
      status.label,
      if (hint != null) dueHintText(hint),
      ?finance,
    ].join(', ');
    return AknListTile(
      title: row.customerTitle,
      subtitle: second,
      amount: amount == null ? null : Fmt.money(amount),
      amountMeta: row.isEstimate
          ? 'tahmini'
          : (row.dueDate == null ? null : 'vade ${dueDay(row.dueDate)}'),
      status: AknStatusLine(
        lamp: AknLamp.style(status),
        trailing: hint == null
            ? null
            : DueHint(
                text: dueHintText(hint),
                tone: dueTone(overdue: overdue, due: row.dueDate),
              ),
      ),
      semanticLabel: semantic,
      onTap: onTap,
    );
  }
}

/// Çek / senet satırı: cari, sağda tutar; ikinci satırda tür ve seri no, banka ve şube (ya da borçlu),
/// sağda vade günü; durum satırında lamba ve vade ipucu.
class InstrumentRowCard extends StatelessWidget {
  const InstrumentRowCard({
    super.key,
    required this.instrument,
    required this.onTap,
    this.showCustomer = true,
  });

  final Instrument instrument;
  final VoidCallback onTap;

  /// Ödeme ayrıntısında cari zaten başlıkta: satır başlığı tür ve seri no olur.
  final bool showCustomer;

  @override
  Widget build(BuildContext context) {
    final i = instrument;
    final status = instrumentLamp(i);
    final source = instrumentSource(i);
    final kind = [i.displayKindLabel, ?i.serialNo].join(' ');
    final second = showCustomer
        ? [kind, if (source.isNotEmpty) source].join(', ')
        : source;
    final hint = i.isOpen ? i.dueHint : null;
    final semantic = [
      i.customerTitle,
      Fmt.money(i.amount),
      i.displayKindLabel,
      ?i.serialNo,
      if (source.isNotEmpty) source,
      'vade ${dueDay(i.dueDate)}',
      status.label,
      if (hint != null) dueHintText(hint),
      if (i.orderNumber != null) 'sipariş ${i.orderNumber}',
    ].join(', ');
    return AknListTile(
      title: showCustomer ? i.customerTitle : kind,
      subtitle: second.isEmpty ? null : second,
      amount: Fmt.money(i.amount),
      amountMeta: i.dueDate == null ? null : 'vade ${dueDay(i.dueDate)}',
      status: AknStatusLine(
        lamp: AknLamp.style(status),
        trailing: hint == null
            ? null
            : DueHint(
                text: dueHintText(hint),
                tone: dueTone(overdue: i.isOverdue, due: i.dueDate),
              ),
      ),
      semanticLabel: semantic,
      onTap: onTap,
    );
  }
}

/// Belgenin kaynağı: banka ve şube ("Ziraat Bankası Pendik"), banka yoksa cariden farklı borçlu.
String instrumentSource(Instrument i) {
  if (i.bankName != null) return [i.bankName!, ?i.branchName].join(' ');
  final debtor = i.debtorName;
  return debtor != null && debtor != i.customerTitle ? debtor : '';
}

/// Plakanın göstergeleri: normal yazıda [PlateReadouts] sütunları; büyük yazıda (1,3× ve üstü)
/// etiket / değer satırları — uzun bir değer ("Havale / EFT", "2.500.000 ₺") etiketin altına iner ve
/// satıra sığar (sayaç sütunları büyük yazıda tek satıra sığmaz).
Widget plateReadouts(BuildContext context, List<PlateReadout> items) {
  if (!isLargeText(context)) return PlateReadouts(items: items);
  return FactList(
    facts: [
      for (final r in items)
        FactRow(
          label: r.label,
          value: r.unit == null ? r.value : '${r.value} ${r.unit}',
        ),
    ],
  );
}

/// Bir ledger satırını listede yerine koyar: ilk satırın üstünde değil, sonrakilerin üstünde 20 px
/// içeriden başlayan ince çizgi.
class LedgerItem extends StatelessWidget {
  const LedgerItem({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => index == 0
      ? child
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [const AknLedgerDivider(), child],
        );
}

/// Bölüm (tasarım v2 §4.5): başlık (20/26) ve içerik, kutu yok. [padded] içerik 20 px kenarla girer;
/// ledger satırları kendi kenarlarını verir.
class LedgerSection extends StatelessWidget {
  const LedgerSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.count,
    this.padded = true,
  });

  final String title;
  final String? subtitle;
  final int? count;
  final Widget child;
  final bool padded;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      SectionHeader(title: title, subtitle: subtitle, count: count),
      if (padded)
        Padding(padding: AknSpace.pagePadding, child: child)
      else
        child,
    ],
  );
}

/// Olgu listesi: etiket / değer satırları, aralarında ince çizgi (kutu yok).
class FactList extends StatelessWidget {
  const FactList({super.key, required this.facts});

  final List<Widget> facts;

  @override
  Widget build(BuildContext context) {
    final line = context.akn.line;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < facts.length; i++) ...[
          if (i > 0) SizedBox(height: 1, child: ColoredBox(color: line)),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: facts[i],
          ),
        ],
      ],
    );
  }
}

/// Liste başındaki tek satır süzgeç dizisi: kapsam çipleri ([leading]), ince ayraç, durum çipleri
/// ([trailing]); 20 px kenar boşluğu ve kayarken sonda yumuşak geçiş.
class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.leading, this.trailing = const []});

  final List<Widget> leading;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final scaler = MediaQuery.textScalerOf(context);
    final children = <Widget>[
      for (var i = 0; i < leading.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        leading[i],
      ],
      if (leading.isNotEmpty && trailing.isNotEmpty) ...[
        const SizedBox(width: 12),
        ExcludeSemantics(
          child: SizedBox(
            width: 1,
            height: scaler.scale(20).clamp(20.0, 36.0),
            child: ColoredBox(color: c.line),
          ),
        ),
        const SizedBox(width: 12),
      ],
      for (var i = 0; i < trailing.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        trailing[i],
      ],
    ];
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final stop = rect.width <= 0
            ? 1.0
            : (1 - AknSpace.page / rect.width).clamp(0.0, 1.0);
        return LinearGradient(
          colors: const [Colors.black, Colors.black, Colors.transparent],
          stops: [0, stop, 1],
        ).createShader(rect);
      },
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: AknSpace.pagePadding,
        child: Row(children: children),
      ),
    );
  }
}

/// Liste sonundaki açıklama cümlesi (§7.7: "Teslim edilen ve iptal olan siparişler Geçmiş
/// sekmesinde.").
class ListFootnote extends StatelessWidget {
  const ListFootnote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
    child: Text(
      text,
      style: context.aknText.bodySmall.copyWith(color: context.akn.dim),
    ),
  );
}

/// İlk harfi küçültür (cümle içinde durum adı: "finans onayında").
String lowerFirst(String s) {
  if (s.isEmpty) return s;
  final first = s.characters.first;
  final lower = switch (first) {
    'I' => 'ı',
    'İ' => 'i',
    _ => first.toLowerCase(),
  };
  return '$lower${s.substring(first.length)}';
}

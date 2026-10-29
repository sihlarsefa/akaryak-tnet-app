import 'package:flutter/material.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../../approvals/api.dart' show isLargeText;
import '../../copy.dart';
import '../../data/payment_models.dart';

/// Vade ipucunun tonu (tasarım v3): geciken kırmızı, bugün ya da 3 gün içinde Pas ("sıra sizde"
/// turuncusu), diğerleri sönük.
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
              ? PhosphorIconsRegular.calendarX
              : PhosphorIconsRegular.calendarDot,
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

/// Satırın sağındaki kısa vade bilgisi (v4 `AknListTile.metaWidget`): 13/18; gecikmede tehlike 600,
/// 3 gün içinde Pas 600, diğerleri sönük 500.
class DueMeta extends StatelessWidget {
  const DueMeta({super.key, required this.text, required this.tone});

  final String text;
  final AknTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final strong = tone == AknTone.danger || tone == AknTone.brand;
    return Text(
      text,
      maxLines: 1,
      softWrap: false,
      style: context.aknText.label.copyWith(
        fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
        color: switch (tone) {
          AknTone.danger => c.danger.fg,
          AknTone.brand => c.brandInk,
          _ => c.dim,
        },
        fontFeatures: AknNumerals.tabular,
      ),
    );
  }
}

/// Ödeme satırı (tasarım v4 §4 defter satırı): L1 cari ve tutar ("tahmini" altında); L2 yöntem ·
/// taksit · vade günü, sağda kısa vade ipucu ("5 gün gecikti" tehlike, "3 gün kaldı" Pas); L3
/// yalnızca istisnada: belgesi yüklenen ödemede "Belgeyi kontrol edin" (Pas), finans onayı / bilgi /
/// ret ya da karşılıksız, iade, iptal ve tahsil edildi gibi sonuçlar (küçük lamba). Bekleyen ödeme
/// normal durumdur, yazılmaz (v4 P4); sipariş numarası ayrıntıda.
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
      ?row.methodName,
      if (row.installments != null && row.installments! > 1)
        '${row.installments} taksit',
      if (row.dueDate != null) 'vade ${dueDay(row.dueDate)}',
    ].join(' · ');
    final hint = row.dueHint;
    final checking = row.paymentStatus == PaymentStatus.documentUploaded;
    // Normal durum (bekliyor) yazılmaz; belge kontrolü fiil satırıdır.
    final exception = row.paymentStatus != PaymentStatus.pending && !checking;
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
      subtitle: second.isEmpty ? null : second,
      // Tahmini tutar "≈" ile (v4 §5 13 diliyle); ekran okuyucu "tahmini" der.
      amount: amount == null
          ? null
          : '${row.isEstimate ? '≈ ' : ''}${rowMoney(amount)}',
      metaWidget: hint == null
          ? null
          : DueMeta(
              text: dueHintText(hint),
              tone: dueTone(overdue: overdue, due: row.dueDate),
            ),
      next: checking ? PaymentsCopy.checkNext : null,
      status: !exception && finance == null
          ? null
          : AknStatusLine(
              lamp: exception ? AknLamp.style(status) : null,
              trailing: finance == null || exception
                  ? null
                  : _FinanceNote(finance, status: row.financeStatus),
            ),
      semanticLabel: semantic,
      onTap: onTap,
    );
  }
}

/// Çek / senet satırı (tasarım v4 §4 defter satırı): L1 cari (ödeme ayrıntısında tür ve seri no) ve
/// tutar; L2 tür ve seri no · banka ve şube (ya da borçlu) · vade günü, sağda kısa vade ipucu; L3
/// yalnızca sonuçlanan belgede durum lambası (portföydeki açık belge normaldir).
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
    final second = [
      if (showCustomer) kind,
      if (source.isNotEmpty) source,
      if (i.dueDate != null) 'vade ${dueDay(i.dueDate)}',
    ].join(' · ');
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
      amount: rowMoney(i.amount),
      metaWidget: hint == null
          ? null
          : DueMeta(
              text: dueHintText(hint),
              tone: dueTone(overdue: i.isOverdue, due: i.dueDate),
            ),
      status: i.isOpen ? null : AknStatusLine(lamp: AknLamp.style(status)),
      semanticLabel: semantic,
      onTap: onTap,
    );
  }
}

/// Satır tutarı: kuruşsuzsa tam ("247.200 ₺"), yoksa kuruşlu.
String rowMoney(double? v) {
  if (v == null) return Fmt.dash;
  return (v - v.roundToDouble()).abs() < 0.005
      ? Fmt.moneyWhole(v)
      : Fmt.money(v);
}

/// Ödemenin finans durumu (satırın üçüncü satırı, istisna): sola yaslı söz; ret tehlike tonunda.
class _FinanceNote extends StatelessWidget {
  const _FinanceNote(this.text, {required this.status});

  final String text;
  final OrderFinanceStatus status;

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: Text(
      text,
      style: context.aknText.label.copyWith(
        fontWeight: FontWeight.w600,
        color: status == OrderFinanceStatus.rejected
            ? context.akn.danger.fg
            : context.akn.dim,
      ),
    ),
  );
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

/// Kart içindeki ödeme / belge satırının iç boşluğu: 16 yan, 14 dikey.
const EdgeInsets kPaymentRowPadding = EdgeInsets.fromLTRB(16, 14, 16, 14);

/// Bir satırı listede yerine koyar (tasarım v3 liste kartı): sayfa zemininde süzülen beyaz kart (20
/// köşe, yumuşak kart gölgesi; koyu temada 1 px ince çizgi), içerik köşelere kırpılır. Satır kendi
/// basılı hâlini çizer (Beton dolgu ve 0,97 içeride); kart sabit kalır (çift ölçek yok). [index] eski
/// çizgili düzenden kalır.
class LedgerItem extends StatelessWidget {
  const LedgerItem({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => PaymentCardSurface(child: child);
}

/// Beyaz kart yüzeyi (tasarım v3): 20 köşe, kart gölgesi ([pressed] iken yalnızca temas gölgesi);
/// koyu temada 1 px ince çizgi içeriğin üstünde; içerik köşelere kırpılır.
class PaymentCardSurface extends StatelessWidget {
  const PaymentCardSurface({
    super.key,
    required this.child,
    this.pressed = false,
  });

  final Widget child;
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final d = pressed ? AknMotion.press : AknMotion.pressOut;
    return AnimatedContainer(
      duration: AknMotion.of(context, d),
      curve: AknMotion.standard,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AknRadius.card,
        boxShadow: pressed ? AknShadows.pressed(c) : AknShadows.card(c),
      ),
      foregroundDecoration: c.isDark
          ? BoxDecoration(
              borderRadius: AknRadius.card,
              border: Border.all(color: c.line),
            )
          : null,
      // İçerik kartta olduğunu bilir (defter satırları düz, okumalar kuyu).
      child: AknCardScope(
        child: ClipRRect(borderRadius: AknRadius.card, child: child),
      ),
    );
  }
}

/// Bölüm (tasarım v3): sayfa zemininde süzülen beyaz kart; içinde başlık (sayı, alt yazı) ve içerik.
/// [padded] içerik 18 px kenarla girer; satırlar kendi kenarlarını verir.
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
    child: PaymentCardSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 58),
            child: SectionHeader(
              title: title,
              subtitle: subtitle,
              count: count,
              padding: const EdgeInsets.fromLTRB(18, 10, 8, 0),
            ),
          ),
          if (padded)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
              child: child,
            )
          else
            child,
        ],
      ),
    ),
  );
}

/// Olgu listesi: etiket / değer satırları, aralarında ince çizgi (tasarım v3: `lineSoft`).
class FactList extends StatelessWidget {
  const FactList({super.key, required this.facts});

  final List<Widget> facts;

  @override
  Widget build(BuildContext context) {
    final line = context.akn.lineSoft;
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
  // Türkçe kurallarla (I → ı, İ → i); çıplak büyük/küçük harf çevirisi kullanılmaz.
  return '${TurkishText.lower(first)}${s.substring(first.length)}';
}

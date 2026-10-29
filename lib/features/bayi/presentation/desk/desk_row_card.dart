import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../application/bayi_grants.dart';
import '../../application/desk_controller.dart';
import '../../data/desk_models.dart';
import '../widgets/bayi_widgets.dart';

/// Sonuç tonu (`routedToFinance` uyarı tonunda; spec A.4).
AknTone outcomeTone(DeskOutcome o) => switch (o) {
  DeskOutcome.quoted => AknTone.ok,
  DeskOutcome.routedToFinance => AknTone.warn,
  DeskOutcome.conflict => AknTone.warn,
  DeskOutcome.invalid => AknTone.danger,
  DeskOutcome.error => AknTone.danger,
};

IconData outcomeIcon(DeskOutcome o) => switch (o) {
  DeskOutcome.quoted => PhosphorIconsFill.checkCircle,
  DeskOutcome.routedToFinance => PhosphorIconsFill.bank,
  DeskOutcome.conflict => PhosphorIconsRegular.cloudWarning,
  DeskOutcome.invalid => PhosphorIconsRegular.warningCircle,
  DeskOutcome.error => PhosphorIconsFill.warningCircle,
};

/// Teklifler satırı (tasarım v4 "Sade" §5 13; kartı [PagedListBody] çizer — içinde alan var):
///
/// ```
/// [☐] Körfez Nakliyat ve Ticaret                               ⏱ 41 dk
///     Motorin · 10.000 L · Körfez Garaj
///     [ Birim fiyat            Öneri 41,55 ] [ Teslim 29 Eki ]
///     ≈ 415.500 ₺ (fiyat yazılınca)          Son: 41,55 ₺/L · 27 Eki ›
/// ```
///
/// Seçim kutusu solda (seçilen kart turuncu yumuşak zemine geçer); müşteri adı dokununca siparişi
/// açar. Boş fiyat alanı boş görünür (v4 B10: ipucu fiyat gibi okunmaz); önerilen fiyat yalnızca
/// alanın içindeki hayalet "Öneri 41,55"tedir ve dokununca yazılır; bir şey yazılınca hayalet çekilir.
/// Teslim varsayılan olarak istenen gündür. "≈ tutar" yalnızca fiyat yazılınca görünür ve yazdıkça
/// sayar; "Son: …" dokununca son alımları açar. İkinci satırda her olgu kendi içinde bölünmez (satır
/// yalnızca " · " yerinde kırılır, A17). Hap ve ödeme satırı yok (ödeme yalnızca engelliyorsa,
/// kırmızı not). Revize istenmişse müşterinin notu ve önceki teklif tek satırda. Gönderim sonucu ve
/// satır hatası süzülerek belirir.
class DeskRowCard extends ConsumerStatefulWidget {
  const DeskRowCard({
    super.key,
    required this.row,
    required this.draft,
    required this.selected,
    required this.editable,
    this.deadline,
    this.outcome,
    this.error,
  });

  final DeskRow row;
  final DeskDraft draft;
  final bool selected;

  /// Fiyat yazılabilir ve seçilebilir (Teklif masası Ekler, engel yok).
  final bool editable;
  final DateTime? deadline;
  final DeskSubmitResult? outcome;
  final String? error;

  @override
  ConsumerState<DeskRowCard> createState() => _DeskRowCardState();
}

class _DeskRowCardState extends ConsumerState<DeskRowCard> {
  late final TextEditingController _price = TextEditingController(
    text: widget.draft.priceText,
  );

  @override
  void didUpdateWidget(DeskRowCard old) {
    super.didUpdateWidget(old);
    final text = widget.draft.priceText;
    if (text != _price.text) {
      _price.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  QuoteDeskController get _desk => ref.read(quoteDeskProvider.notifier);

  Future<void> _pickDate(DateTime current) async {
    final today = TrTime.todayStart();
    DateTime local(DateTime i) {
      final w = TrTime.wall(i);
      return DateTime(w.year, w.month, w.day);
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: local(current),
      firstDate: local(today),
      lastDate: local(TrTime.addDays(today, 365)),
      helpText: 'Teklif teslim günü',
      cancelText: 'Vazgeç',
      confirmText: 'Seç',
    );
    if (picked != null && mounted) {
      _desk.setDate(
        widget.row.orderId,
        TrTime.fromWall(picked.year, picked.month, picked.day),
      );
    }
  }

  void _showHistory(DeskRow r) {
    final t = context.aknText;
    final c = context.akn;
    showAppSheet<void>(
      context: context,
      title: 'Son alımlar',
      subtitle: '${r.customerTitle} · ${r.productName}',
      builder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < r.recentPrices.length; i++) ...[
            if (i > 0) Divider(height: 1, thickness: 1, color: c.lineSoft),
            FactRow(
              label: [
                if (r.recentPrices[i].orderDate != null)
                  dayMonthLong(r.recentPrices[i].orderDate!),
                if (r.recentPrices[i].quantityLiters > 0)
                  Fmt.liters(r.recentPrices[i].quantityLiters),
              ].join(' · '),
              value: Fmt.unitPrice(r.recentPrices[i].unitPriceTry),
            ),
          ],
          if (r.suggestedLabel != null) ...[
            const SizedBox(height: 8),
            Text(
              'Öneri: ${r.suggestedLabel}',
              style: t.label.copyWith(
                fontWeight: FontWeight.w400,
                color: c.dim,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final r = widget.row;
    final grants = ref.watch(bayiGrantsProvider);
    final date = _desk.effectiveDate(r);
    final price = widget.draft.price;
    final outcome = widget.outcome;
    final chip = r.payChip;
    // Revize satırında önceki teklif öneri olarak gösterilmez (v4 tur 2).
    final suggestion = r.offeredUnitPrice;
    final requested = r.requestedDeliveryDate;

    // "≈ tutar": yalnızca yazılan fiyatla (v4 B10: öneriyle hesaplanmış tutar teklif verilmiş gibi
    // okunurdu) — yazdıkça sayar.
    final typed = price != null && price > 0;
    final amount = typed ? price * r.quantityLiters : null;

    final place = r.deliveryPointName ?? r.deliveryPointCity;
    // Her olgu kendi içinde bölünmez: "Nilüfer Tesis" ya da "Motorin 10.000 L" iki satıra
    // dağılmaz (v4 A17).
    final line2 = [
      r.productName,
      Fmt.liters(r.quantityLiters),
      ?place,
      if (!widget.editable && requested != null)
        '${dayMonthLong(requested)} teslim',
    ].map(_unbroken).join(' · ');

    // Ödeme yalnızca engelliyorsa (karşılıksız, finans reddi) kırmızı not.
    final payTone = chip == null
        ? AknTone.neutral
        : _worst(
            AknStatus.toneFromKey(chip.tone),
            AknStatus.toneFromKey(chip.financeTone),
          );
    final payBlocks = chip != null && payTone == AknTone.danger;

    final open = grants.viewOrders
        ? () => GoRouter.of(context).push(AppRoutes.bayiOrder(r.orderId))
        : null;
    final title = Text(
      r.customerTitle,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: t.bodyStrong.copyWith(height: 20 / 15, color: c.ink),
    );
    final names = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        title,
        const SizedBox(height: 2),
        // Satır yalnızca olgular arasında kırılır, sonda "·" kalmaz (v4 tur 2).
        AknFactLine(
          line2,
          style: t.label.copyWith(fontWeight: FontWeight.w400, color: c.dim),
        ),
      ],
    );
    final who = open == null
        ? names
        : Semantics(
            button: true,
            label: '${r.customerTitle}, $line2, siparişi aç',
            excludeSemantics: true,
            onTap: open,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: open,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: names,
              ),
            ),
          );
    final countdown = widget.deadline == null
        ? null
        : CountdownBadge(
            deadline: widget.deadline!,
            yourMove: widget.editable,
            compact: true,
            subject: 'Teklif süresi',
          );
    // Büyük yazıda geri sayım adın altına iner (yan yana sığmaz).
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final Widget head = large || countdown == null
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              who,
              if (countdown != null) ...[const SizedBox(height: 4), countdown],
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: who),
              const SizedBox(width: 10),
              countdown,
            ],
          );

    final last = r.recentPrices.isEmpty ? null : r.recentPrices.first;
    final lastText = last == null
        ? null
        : [
            'Son: ${Fmt.unitPrice(last.unitPriceTry)}',
            if (last.orderDate != null) Fmt.dayMonth(last.orderDate),
          ].join(' · ');
    final amountStyle = t.bodyStrong.copyWith(
      fontWeight: FontWeight.w700,
      color: c.ink,
      fontFeatures: AknNumerals.tabular,
    );
    final foot = Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 2,
      children: [
        if (amount != null)
          Semantics(
            label: 'Tahmini tutar ${Fmt.moneyWhole(amount)}',
            excludeSemantics: true,
            child: AnimatedNumber(
              value: amount.round(),
              from: amount.round(),
              format: (v) => '≈ ${Fmt.moneyWhole(v)}',
              style: amountStyle,
              fit: true,
            ),
          ),
        if (lastText != null)
          Semantics(
            button: true,
            label: 'Son alımlar: $lastText',
            excludeSemantics: true,
            onTap: () => _showHistory(r),
            child: InkWell(
              onTap: () => _showHistory(r),
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        lastText,
                        style: t.label.copyWith(
                          fontWeight: FontWeight.w500,
                          color: c.dim,
                          fontFeatures: AknNumerals.tabular,
                        ),
                      ),
                    ),
                    Icon(
                      PhosphorIconsRegular.caretRight,
                      size: 14,
                      color: c.dim,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        head,
        if (r.isRevision && r.latestRevisionNote != null) ...[
          const SizedBox(height: 6),
          _Note(
            dot: c.warn.solid,
            text: [
              'Revize: ${r.latestRevisionNote}',
              if (r.latestUnitPriceTry != null)
                'önceki teklif ${Fmt.unitPrice(r.latestUnitPriceTry)}',
            ].join(' · '),
          ),
        ],
        if (payBlocks) ...[
          const SizedBox(height: 6),
          _Note(
            dot: c.danger.solid,
            text: [
              chip.line,
              if (chip.statusLabel != null)
                TurkishText.lower(chip.statusLabel!),
              if (chip.financeLabel != null)
                TurkishText.lower(chip.financeLabel!),
            ].join(', '),
          ),
        ],
        if (widget.editable) ...[
          const SizedBox(height: 10),
          _Inputs(
            price: _price,
            date: date,
            suggestion: suggestion,
            // Bir şey yazıldıysa (öneri dahil) hayalet çekilir: alan yazılana kalır.
            applied: widget.draft.priceText.trim().isNotEmpty,
            orderNumber: r.orderNumber,
            onPrice: (text) => _desk.setPrice(r.orderId, text),
            onSuggest: suggestion == null
                ? null
                : () => _desk.setPrice(r.orderId, formatUnitPrice(suggestion)),
            onPickDate: () => _pickDate(date),
          ),
        ],
        if (amount != null || lastText != null) ...[
          const SizedBox(height: 6),
          foot,
        ],
        // Satır hatası ve gönderim sonucu süzülerek belirir (yükseklik kayar, içerik solup büyür).
        _Reveal(
          child: widget.error == null
              ? null
              : Padding(
                  key: ValueKey('error:${widget.error}'),
                  padding: const EdgeInsets.only(top: 8),
                  child: Semantics(
                    liveRegion: true,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(
                            PhosphorIconsFill.warningCircle,
                            size: 16,
                            color: c.danger.fg,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.error!,
                            style: t.label.copyWith(color: c.danger.fg),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        _Reveal(
          child: outcome == null
              ? null
              : Padding(
                  key: ValueKey('outcome:${outcome.outcome}:${outcome.label}'),
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StatusChip(
                        label: outcome.label,
                        tone: outcomeTone(outcome.outcome),
                        icon: outcomeIcon(outcome.outcome),
                      ),
                      if (outcome.message.isNotEmpty)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                            start: 16,
                            top: 2,
                          ),
                          child: Text(
                            outcome.message,
                            style: t.bodySmall.copyWith(color: c.dim),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );

    // Seçilen kart turuncu yumuşak zemine geçer (v3: seçili şey turuncu).
    return AnimatedContainer(
      duration: AknMotion.of(context, AknMotion.base),
      curve: AknMotion.standard,
      color: widget.selected ? c.brandSoft : c.brandSoft.withValues(alpha: 0),
      padding: EdgeInsetsDirectional.fromSTEB(
        widget.editable ? 4 : 16,
        12,
        16,
        10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.editable) ...[
            // 48 × 48 hedef; kutu başlığın ilk satırıyla aynı hizada kalsın diye 4 px yukarıda.
            Transform.translate(
              offset: const Offset(0, -6),
              child: SizedBox(
                width: 48,
                height: 48,
                child: Semantics(
                  label: 'Seç: ${r.orderNumber}, ${r.customerTitle}',
                  child: Checkbox(
                    value: widget.selected,
                    onChanged: (_) {
                      AknHaptics.selection();
                      _desk.toggle(r.orderId);
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(child: content),
        ],
      ),
    );
  }

  /// Olgunun sözcükleri bölünmez boşlukla bağlanır; sayı ile birimi de ([keepUnits]).
  static String _unbroken(String fact) =>
      keepUnits(fact).replaceAll(' ', '\u00A0');

  /// İki ton anahtarından daha dikkat isteyeni (tehlike > uyarı > diğerleri).
  static AknTone _worst(AknTone a, AknTone b) {
    int rank(AknTone t) => switch (t) {
      AknTone.danger => 3,
      AknTone.warn => 2,
      AknTone.ok => 1,
      _ => 0,
    };
    return rank(b) > rank(a) ? b : a;
  }
}

/// Satır içi kısa not: 6 dp tonlu nokta ve 13/18 mürekkep metin (en çok iki satır).
class _Note extends StatelessWidget {
  const _Note({required this.dot, required this.text});

  final Color dot;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        // "Revize: … onaylıyoruz." / "önceki teklif 39,80 ₺/L": satır sonunda "·" kalmaz (v4 tur 2).
        child: AknFactLine(
          text,
          maxLines: 2,
          style: context.aknText.label.copyWith(color: context.akn.ink),
        ),
      ),
    ],
  );
}

/// Kart içi durum değişimi (tasarım v3 §5): içerik gelince yükseklik süzülerek açılır, içerik solup
/// büyüyerek belirir; giderken tersine. [child] null iken yer kalmaz. Hareket azaltmada doğrudan.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = child;
    if (AknMotion.reduced(context)) return c ?? const SizedBox.shrink();
    return AknAnimatedSize(
      duration: AknMotion.slow,
      curve: AknMotion.emphasizedCurve,
      alignment: AlignmentDirectional.topStart,
      child: AnimatedSwitcher(
        duration: AknMotion.base,
        switchInCurve: Curves.linear,
        switchOutCurve: AknMotion.exit,
        layoutBuilder: (current, previous) => Stack(
          alignment: AlignmentDirectional.topStart,
          children: [...previous, ?current],
        ),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation.drive(CurveTween(curve: const Interval(0, 0.7))),
          child: ScaleTransition(
            alignment: AlignmentDirectional.centerStart.resolve(
              Directionality.of(context),
            ),
            scale: animation
                .drive(CurveTween(curve: AknMotion.pop))
                .drive(Tween<double>(begin: 0.92, end: 1)),
            child: child,
          ),
        ),
        child:
            c ?? const SizedBox(key: ValueKey('none'), width: double.infinity),
      ),
    );
  }
}

/// Birim fiyat (%60) ve teslim günü (%40); dar ekranda ya da büyük yazıda alt alta. Boş alan boş
/// görünür: önerisi olan satırda alanın içinde hayalet "Öneri 41,55" (dokununca yazar), önerisi
/// yoksa ipucu "Fiyat yazın" (v4 B10).
class _Inputs extends StatelessWidget {
  const _Inputs({
    required this.price,
    required this.date,
    required this.suggestion,
    required this.applied,
    required this.orderNumber,
    required this.onPrice,
    required this.onSuggest,
    required this.onPickDate,
  });

  final TextEditingController price;
  final DateTime date;
  final double? suggestion;
  final bool applied;
  final String orderNumber;
  final ValueChanged<String> onPrice;
  final VoidCallback? onSuggest;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    final suggest = s == null || applied || onSuggest == null
        ? null
        : _SuggestButton(
            value: formatUnitPrice(s),
            semanticLabel:
                'Önerilen fiyatı yaz: ${Fmt.unitPrice(s)}, $orderNumber',
            onTap: onSuggest!,
          );
    final priceField = AknTextField(
      label: 'Birim fiyat',
      controller: price,
      hint: suggest == null ? 'Fiyat yazın' : null,
      // Birim hayalet çekilince (bir şey yazılınca) görünür: dar alanda ikisi yan yana sığmaz.
      suffixText: suggest == null ? '₺/L' : null,
      suffixIcon: suggest,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [TrNumberInputFormatter(decimals: 4)],
      textInputAction: TextInputAction.done,
      onChanged: (_) => onPrice(price.text),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        if (constraints.maxWidth >= 240 && scale <= 1.3) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: priceField),
              const SizedBox(width: 10),
              Expanded(
                flex: 4,
                child: _DateButton(
                  date: date,
                  onTap: onPickDate,
                  compact: true,
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            priceField,
            const SizedBox(height: 10),
            _DateButton(date: date, onTap: onPickDate),
          ],
        );
      },
    );
  }
}

/// Fiyat alanının içindeki hayalet "Öneri 41,55": dokununca önerilen fiyatı yazar (14/20 600
/// mürekkep, değer tablo rakamlarıyla; 48 dp hedef). Önerilen fiyat yalnızca burada görünür. v4 tur 2:
/// çerçeveli küçük bir düğmedir (32 dp, r10, `lineStrong`), alana yazılmış bir değer gibi okunmaz.
class _SuggestButton extends StatelessWidget {
  const _SuggestButton({
    required this.value,
    required this.semanticLabel,
    required this.onTap,
  });

  /// "41,55".
  final String value;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semanticLabel,
    excludeSemantics: true,
    onTap: onTap,
    child: InkWell(
      onTap: () {
        AknHaptics.selection();
        onTap();
      },
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, end: 8),
          child: Center(
            widthFactor: 1,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.akn.lineStrong),
              ),
              child: Center(
                widthFactor: 1,
                child: Text(
                  'Öneri $value',
                  maxLines: 1,
                  softWrap: false,
                  style: context.aknText.label.copyWith(
                    fontWeight: FontWeight.w600,
                    color: context.akn.ink,
                    fontFeatures: AknNumerals.tabular,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Teslim günü alanı ("29 Eki"): etiket üstte, alan kutusu (14 köşe), takvim simgesi; dokununca tarih
/// seçici açılır.
class _DateButton extends StatelessWidget {
  const _DateButton({
    required this.date,
    required this.onTap,
    this.compact = false,
  });

  final DateTime date;
  final VoidCallback onTap;

  /// Dar sütunda takvim simgesi yok (gün kesilmesin).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final label = Fmt.dayMonth(date);
    // Satır yüksekliği yazı ölçeğiyle büyür (2,0× yazıda gün kesilmez); en az 28.
    final line = (MediaQuery.textScalerOf(context).scale(16) * 22 / 16)
        .clamp(28.0, double.infinity)
        .toDouble();
    return Semantics(
      button: true,
      label: 'Teslim günü: ${Fmt.longDate(date)}, değiştir',
      excludeSemantics: true,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const AknFieldLabel(text: 'Teslim'),
          // AknTextField etiketiyle aynı boşluk (8): satırdaki iki kutu aynı hizada başlar.
          const SizedBox(height: 8),
          InkWell(
            onTap: onTap,
            borderRadius: AknRadius.input,
            child: InputDecorator(
              decoration: AknTextField.decoration(
                context,
                lineHeight: line,
                suffixIcon: compact
                    ? null
                    : const Icon(PhosphorIconsRegular.calendarBlank, size: 20),
              ),
              child: SizedBox(
                height: line,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.body.copyWith(
                      fontSize: 16,
                      height: 22 / 16,
                      color: c.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

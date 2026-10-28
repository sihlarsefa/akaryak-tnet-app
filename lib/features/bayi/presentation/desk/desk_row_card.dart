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

/// Teklif masası kartının içeriği (tasarım v3 liste kartı; kartı [PagedListBody] çizer):
///
/// ```
/// [□] Körfez Nakliyat ve Ticaret                    421.000 ₺
///     SIP-20261020-12009, Motorin, 10.000 L, …       önerilen
///     ● Teklif verin                            ⏱ 41 dk kaldı
///     Son alımlar: 41,55 ₺/L (20 Eki), 41,70 ₺/L (18 Eki)
///     [ Birim fiyat  42,10 ₺/L ] [ Teslim 22 Eki Perşembe ]
/// ```
///
/// Seçim kutusu solda (24, işaretliyken mürekkep; seçilen kart turuncu yumuşak zemine geçer); sağ
/// sütunda önerilen ya da yazılan fiyatla tahmini tutar (tablo rakamları). Durum satırı izleyiciye göre
/// çip ("Teklif verin" turuncu) ve geri sayım (yalnızca süre dolumu açıkken; 30 dakikanın altında
/// kırmızı). Gönderim sonucu ve satır hatası süzülerek belirir. Masada rota çizgisi yok (yoğunluk).
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
    final suggestion = r.suggestedUnitPrice;
    final requested = r.requestedDeliveryDate;

    // Sağ sütun: yazılan fiyatla tahmini tutar, yoksa önerilen fiyatla.
    final typed = price != null && price > 0;
    final basis = typed ? price : suggestion;
    final amount = basis == null
        ? null
        : Fmt.moneyWhole(basis * r.quantityLiters);
    final amountMeta = basis == null ? null : (typed ? 'tahmini' : 'önerilen');

    final lamp = AknStatus.lampFor(
      r.status,
      StatusViewer.bayi(canQuote: widget.editable),
      serverLabel: r.statusLabel,
    );
    final status = AknStatusLine(
      lamp: AknLamp.status(lamp),
      trailing: widget.deadline == null
          ? null
          : CountdownBadge(
              deadline: widget.deadline!,
              yourMove: widget.editable,
              subject: 'Teklif süresi',
            ),
    );

    // Düzenlenebilir satırda istenen gün teslim alanında görünür; burada yinelenmez.
    final line2 = keepUnits(
      [
        r.orderNumber,
        r.productName,
        Fmt.liters(r.quantityLiters),
        ?r.deliveryPointName,
        if (!widget.editable && requested != null)
          '${dayMonthLong(requested)} teslim',
      ].join(', '),
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LedgerHead(
          title: r.customerTitle,
          subtitle: line2,
          amount: amount,
          amountMeta: amountMeta,
        ),
        const SizedBox(height: 8),
        status,
        if (chip != null) ...[
          const SizedBox(height: 6),
          RowNote(
            icon: PhosphorIconsRegular.money,
            text: [
              chip.line,
              if (chip.statusLabel != null)
                TurkishText.lower(chip.statusLabel!),
              if (chip.financeLabel != null)
                TurkishText.lower(chip.financeLabel!),
            ].join(', '),
            tone: _worst(
              AknStatus.toneFromKey(chip.tone),
              AknStatus.toneFromKey(chip.financeTone),
            ),
          ),
        ],
        if (r.recentPrices.isNotEmpty) ...[
          const SizedBox(height: 4),
          RowNote(
            icon: PhosphorIconsRegular.clockCounterClockwise,
            text:
                'Son alımlar: ${r.recentPrices.map((p) => '${Fmt.unitPrice(p.unitPriceTry)} (${Fmt.dayMonth(p.orderDate)})').join(', ')}',
          ),
        ],
        if (r.isRevision && r.latestRevisionNote != null) ...[
          const SizedBox(height: 10),
          AknBanner(
            tone: AknTone.info,
            icon: PhosphorIconsRegular.chatCircle,
            title: r.latestUnitPriceTry == null
                ? 'Carinin revize notu'
                : 'Revize notu, önceki teklif ${Fmt.unitPrice(r.latestUnitPriceTry)}',
            message: r.latestRevisionNote!,
          ),
        ],
        if (widget.editable) ...[
          const SizedBox(height: 12),
          _Inputs(
            price: _price,
            date: date,
            onPrice: (text) => _desk.setPrice(r.orderId, text),
            onPickDate: () => _pickDate(date),
          ),
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
        if (widget.editable && suggestion != null || grants.viewOrders) ...[
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              if (widget.editable && suggestion != null)
                _SuggestionChip(
                  price: suggestion,
                  note: r.suggestedLabel,
                  applied: price == suggestion,
                  orderNumber: r.orderNumber,
                  onUse: () =>
                      _desk.setPrice(r.orderId, formatUnitPrice(suggestion)),
                ),
              if (grants.viewOrders)
                AknInlineLink(
                  label: 'Siparişi aç',
                  onTap: () =>
                      GoRouter.of(context).push(AppRoutes.bayiOrder(r.orderId)),
                ),
            ],
          ),
        ],
      ],
    );

    // Seçilen kart turuncu yumuşak zemine geçer (v3: seçili şey turuncu).
    return AnimatedContainer(
      duration: AknMotion.of(context, AknMotion.base),
      curve: AknMotion.standard,
      color: widget.selected ? c.brandSoft : c.brandSoft.withValues(alpha: 0),
      padding: EdgeInsetsDirectional.fromSTEB(
        widget.editable ? 4 : 16,
        14,
        16,
        grants.viewOrders || widget.editable ? 4 : 14,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.editable) ...[
            // 48 × 48 hedef; kutu başlığın ilk satırıyla aynı hizada kalsın diye 4 px yukarıda.
            Transform.translate(
              offset: const Offset(0, -4),
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

class _Inputs extends StatelessWidget {
  const _Inputs({
    required this.price,
    required this.date,
    required this.onPrice,
    required this.onPickDate,
  });

  final TextEditingController price;
  final DateTime date;
  final ValueChanged<String> onPrice;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    final priceField = MoneyField.unitPrice(
      label: 'Birim fiyat',
      controller: price,
      onChanged: (_) => onPrice(price.text),
    );
    final dateField = _DateButton(date: date, onTap: onPickDate);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        if (constraints.maxWidth >= 280 && scale <= 1.3) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: priceField),
              const SizedBox(width: 10),
              Expanded(child: dateField),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [priceField, const SizedBox(height: 10), dateField],
        );
      },
    );
  }
}

/// Teslim günü alanı ("22 Eki Perşembe", tasarım v3): etiket üstte, beyaz alan kutusu (14 köşe, 1,5 px
/// çizgi), takvim simgesi; dokununca tarih seçici açılır.
class _DateButton extends StatelessWidget {
  const _DateButton({required this.date, required this.onTap});

  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final label = dayMonthLong(date);
    // Satır yüksekliği yazı ölçeğiyle büyür (2,0× yazıda gün adı kesilmez); en az 28.
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
          const SizedBox(height: 6),
          InkWell(
            onTap: onTap,
            borderRadius: AknRadius.input,
            child: InputDecorator(
              decoration: AknTextField.decoration(
                context,
                lineHeight: line,
                suffixIcon: const Icon(
                  PhosphorIconsRegular.calendarBlank,
                  size: 20,
                ),
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

/// Önerilen fiyat çipi: "Öneri 41,55 ₺/L"; dokununca fiyat alanına yazılır, yazılınca seçili görünür.
/// Yanında önerinin kaynağı ("son alım fiyatı") soluk metinle.
class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.price,
    required this.applied,
    required this.orderNumber,
    required this.onUse,
    this.note,
  });

  final double price;
  final String? note;
  final bool applied;
  final String orderNumber;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        AknChip(
          label: 'Öneri ${Fmt.unitPrice(price)}',
          selected: applied,
          semanticLabel: applied
              ? 'Önerilen fiyat yazıldı: ${Fmt.unitPrice(price)}, $orderNumber'
              : 'Önerilen fiyatı kullan: ${Fmt.unitPrice(price)}, $orderNumber',
          onTap: applied ? null : onUse,
          enabled: true,
        ),
        if (note != null && note!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              note!,
              style: t.label.copyWith(
                fontWeight: FontWeight.w400,
                color: c.dim,
              ),
            ),
          ),
      ],
    );
  }
}

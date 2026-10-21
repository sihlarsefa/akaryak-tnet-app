import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
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
  DeskOutcome.quoted => Icons.check_circle_rounded,
  DeskOutcome.routedToFinance => Icons.account_balance_rounded,
  DeskOutcome.conflict => Icons.sync_problem_rounded,
  DeskOutcome.invalid => Icons.error_outline_rounded,
  DeskOutcome.error => Icons.error_rounded,
};

/// Masa satırı: sipariş özeti, ödeme çipi, son alımlar, satır içi ₺/L ve teslim günü, öneri, tahmini
/// tutar, geri sayım (yalnızca süre dolumu açıkken) ve son gönderimin sonucu.
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
    final place = [?r.deliveryPointName, ?r.deliveryPointCity].join(', ');
    final suggestion = r.suggestedUnitPrice;
    final accent = outcome != null
        ? outcomeTone(outcome.outcome)
        : widget.error != null
        ? AknTone.danger
        : widget.selected
        ? AknTone.brand
        : null;
    return AknCard(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 14),
      accent: accent,
      borderColor: widget.selected ? c.brandLine : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.editable)
            Semantics(
              label: 'Seç: ${r.orderNumber}, ${r.customerTitle}',
              child: Checkbox(
                value: widget.selected,
                onChanged: (_) => _desk.toggle(r.orderId),
              ),
            )
          else
            const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            r.orderNumber,
                            style: t.label.copyWith(color: c.dim),
                          ),
                          FitStart(
                            child: StatusChip.style(
                              r.status.statusStyle.withLabel(
                                r.isRevision ? 'Revize' : 'Yeni',
                              ),
                              size: StatusChipSize.small,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.deadline != null)
                      FitEnd(
                        child: CountdownBadge(
                          deadline: widget.deadline!,
                          prefix: 'Kalan',
                          showRing: false,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(r.customerTitle, style: t.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  [
                    r.productName,
                    Fmt.liters(r.quantityLiters),
                    if (place.isNotEmpty) place,
                  ].join(' · '),
                  style: t.bodySmall,
                ),
                if (r.requestedDeliveryDate != null)
                  Text(
                    'İstenen teslim ${Fmt.date(r.requestedDeliveryDate)} ${Fmt.weekday(r.requestedDeliveryDate)}',
                    style: t.bodySmall,
                  ),
                if (chip != null) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ToneTag(
                        label: chip.statusLabel == null
                            ? chip.line
                            : '${chip.line} · ${chip.statusLabel}',
                        tone: AknStatus.toneFromKey(chip.tone),
                        icon: Icons.payments_outlined,
                      ),
                      if (chip.financeLabel != null)
                        ToneTag(
                          label: chip.financeLabel!,
                          tone: AknStatus.toneFromKey(chip.financeTone),
                          icon: Icons.account_balance_outlined,
                        ),
                    ],
                  ),
                ],
                if (r.isRevision && r.latestRevisionNote != null) ...[
                  const SizedBox(height: 8),
                  AknBanner(
                    tone: AknTone.info,
                    icon: Icons.chat_bubble_outline_rounded,
                    title: r.latestUnitPriceTry == null
                        ? 'Carinin revize notu'
                        : 'Revize notu · önceki teklif ${Fmt.unitPrice(r.latestUnitPriceTry)}',
                    message: r.latestRevisionNote!,
                  ),
                ],
                if (r.recentPrices.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Son alımlar: ${r.recentPrices.map((p) => '${Fmt.unitPrice(p.unitPriceTry)} (${Fmt.dayMonth(p.orderDate)})').join(' · ')}',
                    style: t.bodySmall,
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
                  if (suggestion != null) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        Text(
                          'Önerilen ${Fmt.unitPrice(suggestion)}${r.suggestedLabel == null ? '' : ' · ${r.suggestedLabel}'}',
                          style: t.bodySmall,
                        ),
                        if (price != suggestion)
                          AknButton.ghost(
                            label: 'Öneriyi kullan',
                            size: AknButtonSize.small,
                            semanticLabel:
                                'Önerilen fiyatı kullan: ${Fmt.unitPrice(suggestion)}, ${r.orderNumber}',
                            onPressed: () => _desk.setPrice(
                              r.orderId,
                              formatUnitPrice(suggestion),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (price != null && price > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Tahmini tutar ${Fmt.money(price * r.quantityLiters)}',
                      style: t.label.copyWith(color: c.text),
                    ),
                  ],
                ],
                if (widget.error != null) ...[
                  const SizedBox(height: 8),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      widget.error!,
                      style: t.bodySmall.copyWith(color: c.danger.fg),
                    ),
                  ),
                ],
                if (outcome != null) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusChip(
                        label: outcome.label,
                        tone: outcomeTone(outcome.outcome),
                        icon: outcomeIcon(outcome.outcome),
                        size: StatusChipSize.small,
                      ),
                      if (outcome.message.isNotEmpty)
                        Text(outcome.message, style: t.bodySmall),
                    ],
                  ),
                ],
                if (grants.viewOrders)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => GoRouter.of(
                        context,
                      ).push(AppRoutes.bayiOrder(r.orderId)),
                      child: const Text('Siparişi aç'),
                    ),
                  ),
              ],
            ),
          ),
        ],
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
        if (constraints.maxWidth >= 300 && scale <= 1.3) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: priceField),
              const SizedBox(width: 8),
              Expanded(flex: 5, child: dateField),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [priceField, const SizedBox(height: 8), dateField],
        );
      },
    );
  }
}

/// Kısa tarih seçici ("23.10 Cuma"); satır içi alan dar olduğu için.
class _DateButton extends StatelessWidget {
  const _DateButton({required this.date, required this.onTap});

  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final label = '${Fmt.dayMonth(date)} ${Fmt.weekday(date)}';
    return Semantics(
      button: true,
      label: 'Teslim günü: ${Fmt.longDate(date)}, değiştir',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AknRadius.input,
        child: InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Teslim',
            suffixIcon: Icon(Icons.calendar_month_rounded, size: 20),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.body.copyWith(fontSize: 16, color: c.ink),
          ),
        ),
      ),
    );
  }
}

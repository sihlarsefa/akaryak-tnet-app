import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../application/desk_controller.dart';
import '../../data/desk_models.dart';
import 'desk_row_card.dart';

/// "Seçilenlere aynı fiyat/tarih": tek fiyat ve/veya tek teslim günü tüm seçili satırlara yazılır.
Future<void> showBulkSameSheet(BuildContext context, WidgetRef ref) =>
    showAppSheet<void>(
      context: context,
      title: 'Seçilenlere aynı fiyat / tarih',
      subtitle: 'Boş bıraktığınız alan satırlarda değişmez.',
      builder: (_) => const _BulkSameSheet(),
    );

class _BulkSameSheet extends ConsumerStatefulWidget {
  const _BulkSameSheet();

  @override
  ConsumerState<_BulkSameSheet> createState() => _BulkSameSheetState();
}

class _BulkSameSheetState extends ConsumerState<_BulkSameSheet> {
  final _price = TextEditingController();
  DateTime? _date;
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  void _apply() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final price = MoneyField.parse(_price.text);
    if (price == null && _date == null) {
      Navigator.of(context).pop();
      return;
    }
    final n = ref
        .read(quoteDeskProvider.notifier)
        .applySame(price: price, date: _date);
    AppToast.success('$n siparişe uygulandı.', context: context);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final count = ref.watch(quoteDeskProvider.select((s) => s.selected.length));
    final today = TrTime.todayStart();
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count sipariş seçili', style: context.aknText.bodyStrong),
          const SizedBox(height: 12),
          MoneyField.unitPrice(
            label: 'Birim fiyat',
            controller: _price,
            max: QuoteDeskController.maxUnitPrice,
            validator: (v) =>
                v != null && v <= 0 ? 'Sıfırdan büyük bir değer girin.' : null,
          ),
          const SizedBox(height: 12),
          DateField(
            label: 'Teslim günü',
            value: _date,
            firstDate: today,
            lastDate: TrTime.addDays(today, 365),
            onChanged: (d) => setState(() => _date = d),
          ),
          const SizedBox(height: 20),
          AknButton(
            label: 'Seçilenlere uygula',
            icon: Icons.done_all_rounded,
            expand: true,
            onPressed: _apply,
          ),
        ],
      ),
    );
  }
}

/// Toplu gönderim sonuçları: satır başına sonuç (finansa gidenler uyarı tonunda).
Future<void> showDeskResultsSheet(BuildContext context, DeskSubmitSummary s) =>
    showAppSheet<void>(
      context: context,
      title: 'Teklif sonuçları',
      builder: (_) => _ResultsBody(summary: s),
    );

class _ResultsBody extends StatelessWidget {
  const _ResultsBody({required this.summary});

  final DeskSubmitSummary summary;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final s = summary;
    final lines = <(String, AknTone, IconData)>[
      if (s.quoted > 0)
        (
          '${s.quoted} teklif gönderildi',
          AknTone.ok,
          Icons.check_circle_rounded,
        ),
      if (s.routedToFinance > 0)
        (
          '${s.routedToFinance} sipariş finans onayına gönderildi',
          AknTone.warn,
          Icons.account_balance_rounded,
        ),
      if (s.failed > 0)
        (
          '${s.failed} satır gönderilemedi',
          AknTone.danger,
          Icons.error_outline_rounded,
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          liveRegion: true,
          container: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (text, tone, icon) in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(icon, color: context.akn.tone(tone).fg, size: 22),
                      const SizedBox(width: 10),
                      Expanded(child: Text(text, style: t.bodyStrong)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (s.routedToFinance > 0)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: AknBanner(
              tone: AknTone.warn,
              message:
                  'Teklif cari limitini aştığı için bu siparişler finans onayına gitti; teklif kaydedilmedi. Finans onaylayınca masaya döner.',
            ),
          ),
        const SizedBox(height: 4),
        for (final r in s.results)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AknCard(
              padding: const EdgeInsets.all(12),
              accent: outcomeTone(r.outcome),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.rows[r.orderId]?.customerTitle ?? 'Sipariş #${r.orderId}',
                    style: t.bodyStrong,
                  ),
                  Text(
                    [
                      s.rows[r.orderId]?.orderNumber ?? '#${r.orderId}',
                      if (s.rows[r.orderId] != null)
                        Fmt.liters(s.rows[r.orderId]!.quantityLiters),
                    ].join(' · '),
                    style: t.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  StatusChip(
                    label: r.label,
                    tone: outcomeTone(r.outcome),
                    icon: outcomeIcon(r.outcome),
                    size: StatusChipSize.small,
                  ),
                  if (r.message.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(r.message, style: t.bodySmall),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        AknButton(
          label: 'Tamam',
          expand: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Masa süzgeci: cari, ürün (yalnızca bekleyen siparişi olanlar) ve sıralama.
Future<void> showDeskFilterSheet(BuildContext context) => showAppSheet<void>(
  context: context,
  title: 'Süzgeç ve sıralama',
  builder: (_) => const _DeskFilterSheet(),
);

class _DeskFilterSheet extends ConsumerWidget {
  const _DeskFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(quoteDeskProvider);
    final c = ref.read(quoteDeskProvider.notifier);
    final t = context.aknText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Sıralama', style: t.bodyStrong),
        const SizedBox(height: 4),
        FilterChips<DeskSort>(
          padding: EdgeInsets.zero,
          allowEmpty: false,
          options: [
            for (final o in DeskSort.values)
              FilterOption(value: o, label: o.label),
          ],
          selected: {s.sort},
          onChanged: (v) => c.setSort(v.first),
        ),
        const SizedBox(height: 16),
        Text('Cari', style: t.bodyStrong),
        const SizedBox(height: 4),
        if (s.facets.customers.isEmpty)
          Text('Bekleyen siparişi olan cari yok.', style: t.bodySmall)
        else
          Wrap(
            spacing: 8,
            children: [
              for (final f in s.facets.customers)
                FilterChip(
                  label: Text('${f.title} (${f.count})'),
                  selected: s.customerId == f.id,
                  onSelected: (on) => c.setCustomer(on ? f.id : null),
                ),
            ],
          ),
        const SizedBox(height: 16),
        Text('Ürün', style: t.bodyStrong),
        const SizedBox(height: 4),
        if (s.facets.products.isEmpty)
          Text('Bekleyen sipariş yok.', style: t.bodySmall)
        else
          Wrap(
            spacing: 8,
            children: [
              for (final f in s.facets.products)
                FilterChip(
                  label: Text('${f.title} (${f.count})'),
                  selected: s.productId == f.id,
                  onSelected: (on) => c.setProduct(on ? f.id : null),
                ),
            ],
          ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: AknButton.secondary(
                label: 'Temizle',
                expand: true,
                onPressed: s.isFiltered ? c.clearFilters : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AknButton(
                label: 'Tamam',
                expand: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

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
          Text(
            '$count sipariş seçili',
            style: context.aknText.bodyStrong.copyWith(color: context.akn.ink),
          ),
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
            expand: true,
            onPressed: _apply,
          ),
        ],
      ),
    );
  }
}

/// Toplu gönderim sonuçları (tasarım v3): hepsi gönderildiyse önce başarı işareti çizilir (halka, onay,
/// küçük parıltı ve dokunsal geri bildirim); özet satırları ve satır başına sonuçlar art arda süzülür
/// (finansa gidenler uyarı tonunda).
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
    final c = context.akn;
    final s = summary;
    final lines = <(String, AknTone, IconData)>[
      if (s.quoted > 0)
        (
          '${s.quoted} teklif gönderildi',
          AknTone.ok,
          PhosphorIconsFill.checkCircle,
        ),
      if (s.routedToFinance > 0)
        (
          '${s.routedToFinance} sipariş finans onayına gönderildi',
          AknTone.warn,
          PhosphorIconsFill.bank,
        ),
      if (s.failed > 0)
        (
          '${s.failed} satır gönderilemedi',
          AknTone.danger,
          PhosphorIconsFill.warningCircle,
        ),
    ];
    final allGood = s.quoted > 0 && s.failed == 0 && s.routedToFinance == 0;
    return StaggerScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (allGood) ...[
            const Center(child: SuccessCheck(size: 64)),
            const SizedBox(height: 14),
          ],
          Semantics(
            liveRegion: true,
            container: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, (text, tone, icon)) in lines.indexed)
                  FadeUp(
                    delay: Duration(milliseconds: 90 * i),
                    offset: 10,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: c.tone(tone).bg,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, color: c.tone(tone).fg, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              text,
                              style: t.bodyStrong.copyWith(color: c.ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (s.routedToFinance > 0)
            const Padding(
              padding: EdgeInsets.only(top: 4, bottom: 8),
              child: AknBanner(
                tone: AknTone.warn,
                message:
                    'Teklif cari limitini aştığı için bu siparişler finans onayına gitti; teklif kaydedilmedi. Finans onaylayınca masaya döner.',
              ),
            ),
          const SizedBox(height: 4),
          // Satır başına sonuç: içeriden ince çizgiyle ayrılmış satırlar, art arda gelir.
          for (var i = 0; i < s.results.length; i++)
            StaggerItem(
              index: i + lines.length,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (i > 0)
                    Divider(height: 1, thickness: 1, color: c.lineSoft),
                  _ResultRow(
                    result: s.results[i],
                    row: s.rows[s.results[i].orderId],
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          AknButton(
            label: 'Tamam',
            expand: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.result, this.row});

  final DeskSubmitResult result;
  final DeskRow? row;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final r = result;
    final o = row;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            o?.customerTitle ?? 'Sipariş #${r.orderId}',
            style: t.headline.copyWith(color: c.ink),
          ),
          const SizedBox(height: 2),
          Text(
            [
              o?.orderNumber ?? '#${r.orderId}',
              if (o != null) o.productName,
              if (o != null) Fmt.liters(o.quantityLiters),
            ].join(', '),
            style: t.bodySmall.copyWith(color: c.dim),
          ),
          const SizedBox(height: 8),
          StatusChip(
            label: r.label,
            tone: outcomeTone(r.outcome),
            icon: outcomeIcon(r.outcome),
          ),
          if (r.message.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 16, top: 2),
              child: Text(r.message, style: t.bodySmall.copyWith(color: c.dim)),
            ),
        ],
      ),
    );
  }
}

/// Teklifler filtresi ("Filtre", v4 §5 13): süresi yaklaşan, cari, ürün (yalnızca bekleyen siparişi
/// olanlar) ve sıralama.
Future<void> showDeskFilterSheet(BuildContext context) => showAppSheet<void>(
  context: context,
  title: 'Filtre',
  builder: (_) => const _DeskFilterSheet(),
);

class _DeskFilterSheet extends ConsumerWidget {
  const _DeskFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(quoteDeskProvider);
    final c = ref.read(quoteDeskProvider.notifier);
    final t = context.aknText;
    final k = context.akn;
    final expiring = s.view == DeskView.expiringSoon;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (s.expiryEnabled) ...[
          Text('Süre', style: t.bodyStrong.copyWith(color: k.ink)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              AknChip(
                label: DeskView.expiringSoon.label,
                count: s.counts.of(DeskView.expiringSoon),
                selected: expiring,
                onTap: () =>
                    c.setView(expiring ? DeskView.all : DeskView.expiringSoon),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Text('Sıralama', style: t.bodyStrong.copyWith(color: k.ink)),
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
        Text('Cari', style: t.bodyStrong.copyWith(color: k.ink)),
        const SizedBox(height: 4),
        if (s.facets.customers.isEmpty)
          Text(
            'Bekleyen siparişi olan cari yok.',
            style: t.bodySmall.copyWith(color: k.dim),
          )
        else
          Wrap(
            spacing: 8,
            children: [
              for (final f in s.facets.customers)
                AknChip(
                  label: f.title,
                  count: f.count,
                  selected: s.customerId == f.id,
                  onTap: () =>
                      c.setCustomer(s.customerId == f.id ? null : f.id),
                ),
            ],
          ),
        const SizedBox(height: 16),
        Text('Ürün', style: t.bodyStrong.copyWith(color: k.ink)),
        const SizedBox(height: 4),
        if (s.facets.products.isEmpty)
          Text(
            'Bekleyen sipariş yok.',
            style: t.bodySmall.copyWith(color: k.dim),
          )
        else
          Wrap(
            spacing: 8,
            children: [
              for (final f in s.facets.products)
                AknChip(
                  label: f.title,
                  count: f.count,
                  selected: s.productId == f.id,
                  onTap: () => c.setProduct(s.productId == f.id ? null : f.id),
                ),
            ],
          ),
        const SizedBox(height: 20),
        AknButton(
          label: 'Tamam',
          expand: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: 8),
        AknButton.ghost(
          label: 'Filtreleri temizle',
          expand: true,
          onPressed: s.isFiltered || expiring
              ? () {
                  c.clearFilters();
                  if (expiring) c.setView(DeskView.all);
                }
              : null,
        ),
      ],
    );
  }
}

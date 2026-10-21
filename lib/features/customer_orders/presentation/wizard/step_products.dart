import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_number.dart';
import '../../application/home_controller.dart';
import '../../application/wizard_controller.dart';
import '../../application/wizard_models.dart';
import '../../application/wizard_rules.dart';
import '../../copy.dart';
import '../../data/form_models.dart';
import '../../data/home_models.dart';
import '../widgets/common.dart';
import '../widgets/contact_actions.dart';
import 'wizard_parts.dart';

/// Adım 1 (tasarım v2 §7.9 "Ürün"): bayi (birden çoksa), "Şablondan doldur", her satırda ürün
/// kartları (güncel fiyatıyla), büyük litre alanı ve hızlı litre çipleri; altta toplam litre ve
/// tahmini tutar göstergeleri.
class StepProducts extends ConsumerStatefulWidget {
  const StepProducts({super.key});

  @override
  ConsumerState<StepProducts> createState() => _StepProductsState();
}

class _StepProductsState extends ConsumerState<StepProducts> {
  final Map<String, TextEditingController> _liters = {};
  final Map<String, FocusNode> _focus = {};

  @override
  void dispose() {
    for (final c in _liters.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(DraftLine l) {
    final c = _liters.putIfAbsent(
      l.uid,
      () => TextEditingController(
        text: l.liters == null ? '' : Fmt.number(l.liters, maxFraction: 3),
      ),
    );
    final focused = _focus[l.uid]?.hasFocus ?? false;
    if (!focused && TrNumber.parse(c.text) != l.liters) {
      c.text = l.liters == null ? '' : Fmt.number(l.liters, maxFraction: 3);
    }
    return c;
  }

  Future<void> _pickTemplate(List<TemplateListItem> templates) async {
    final id = await showAppSheet<int>(
      context: context,
      title: OrdersCopy.fromTemplate,
      subtitle: 'Satırlar şablondan dolar; litreleri değiştirebilirsiniz.',
      padding: const EdgeInsets.only(bottom: 12),
      builder: (ctx) => AknLedger(
        children: [
          for (final t in templates)
            AknListTile(
              leadingIcon: Icons.bookmarks_outlined,
              title: t.name,
              subtitle: t.subtitle,
              onTap: () => Navigator.of(ctx).pop(t.id),
            ),
        ],
      ),
    );
    if (id == null || !mounted) return;
    final msg = await ref.read(orderWizardProvider.notifier).applyTemplate(id);
    if (msg != null && mounted) AppToast.info(msg, context: context);
  }

  @override
  Widget build(BuildContext context) {
    final w = ref.watch(orderWizardProvider);
    final ctrl = ref.read(orderWizardProvider.notifier);
    final home = ref.watch(customerHomeProvider).data;
    final form = ref.watch(orderFormProvider).data;
    final d = w.draft;
    final issues = w.showErrors
        ? WizardRules.products(
            d,
            stations: home?.stations ?? const [],
            form: form,
          )
        : const <RuleIssue>[];
    String? errorFor(String field) =>
        issues.where((i) => i.field == field).firstOrNull?.message;
    final stations = home?.stations ?? const [];
    final block = ctrl.orderingBlock;
    final templates = form?.templates ?? home?.templates ?? const [];
    final estimate = w.estimate;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (w.notice != null)
                WizardPad(
                  AknBanner(
                    tone: AknTone.info,
                    icon: Icons.info_outline_rounded,
                    message: w.notice!,
                  ),
                ),
              if (block != null)
                _OrderingBlocked(
                  reason: block,
                  infoRequested: w.ordering?.infoRequested ?? false,
                  approvalId: w.ordering?.openApprovalRequestId,
                ),
              if (stations.length > 1) ...[
                const WizardHeading('Bayi'),
                for (final s in stations)
                  ChoiceCard(
                    margin: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    title: s.title,
                    subtitle: s.canOrder
                        ? _limitNote(home?.limits, s.id)
                        : (s.blockReason ?? 'Şu an sipariş alınamıyor'),
                    leadingIcon: Icons.local_gas_station_outlined,
                    tag: s.id == home?.stationId ? 'Varsayılan' : null,
                    selected: d.stationId == s.id,
                    enabled: s.canOrder,
                    onTap: () => ctrl.setStation(s.id),
                  ),
                if (errorFor('station') != null)
                  WizardError(errorFor('station')!),
              ],
              WizardHeading(
                'Ürün ve litre',
                action: templates.isEmpty
                    ? null
                    : AknButton.ghost(
                        label: OrdersCopy.fromTemplate,
                        icon: Icons.bookmarks_outlined,
                        size: AknButtonSize.small,
                        onPressed: () => _pickTemplate(templates),
                      ),
              ),
              for (var i = 0; i < d.lines.length; i++)
                _LineEditor(
                  key: ValueKey(d.lines[i].uid),
                  index: i,
                  count: d.lines.length,
                  line: d.lines[i],
                  products: form?.products ?? const [],
                  prices: w.prices,
                  controller: _controllerFor(d.lines[i]),
                  focusNode: _focus.putIfAbsent(d.lines[i].uid, FocusNode.new),
                  error: errorFor(d.lines[i].uid),
                  onProduct: (id) =>
                      ctrl.updateLine(d.lines[i].uid, productId: id),
                  onLiters: (v) => ctrl.updateLine(
                    d.lines[i].uid,
                    liters: v,
                    clearLiters: v == null,
                  ),
                  onRemove: d.lines.length > 1
                      ? () => ctrl.removeLine(d.lines[i].uid)
                      : null,
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 4, 20, 0),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AknButton.ghost(
                    label: OrdersCopy.addLine,
                    icon: Icons.add_rounded,
                    size: AknButtonSize.small,
                    onPressed: d.lines.length >= WizardRules.maxLines
                        ? null
                        : ctrl.addLine,
                  ),
                ),
              ),
              WizardPad(
                top: 16,
                KpiRow(
                  children: [
                    KpiTile(
                      label: 'Toplam',
                      value: d.totalLiters,
                      format: (v) => Fmt.number(v, maxFraction: 3),
                      unit: 'L',
                      semanticLabel: 'Toplam ${Fmt.liters(d.totalLiters)}',
                    ),
                    KpiTile(
                      label: 'Tahmini tutar',
                      value: estimate.value,
                      format: (v) => Fmt.number(v.round()),
                      unit: '₺',
                      caption: estimate.value == null && estimate.unknown
                          ? OrdersCopy.priceUnknown
                          : null,
                      semanticLabel: estimate.value != null
                          ? 'Tahmini tutar ${Fmt.money(estimate.value)}'
                          : 'Tahmini tutar ${estimate.unknown ? OrdersCopy.priceUnknown : 'yok'}',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Limiti dolmak üzere olan bayide not (§7.9): "Limit kullanımı %92, limite yakın".
String? _limitNote(List<CustomerLimit>? limits, int stationId) {
  final l = limits?.where((x) => x.stationId == stationId && x.hasLimit);
  if (l == null || l.isEmpty) return null;
  final pct = l.map((x) => x.usedPct).reduce((a, b) => a > b ? a : b);
  if (pct < 80) return null;
  if (pct >= 100) {
    return 'Limit doldu; bayiniz siparişi finans onayına alabilir.';
  }
  return 'Limit kullanımı %${Fmt.number(pct)}, limite yakın';
}

class _OrderingBlocked extends ConsumerWidget {
  const _OrderingBlocked({
    required this.reason,
    required this.infoRequested,
    this.approvalId,
  });

  final String reason;
  final bool infoRequested;
  final int? approvalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final station = ref.watch(customerHomeProvider).data?.station;
    return WizardPad(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AknBanner(
            tone: infoRequested ? AknTone.warn : AknTone.danger,
            icon: infoRequested
                ? Icons.mark_email_unread_outlined
                : Icons.block_rounded,
            title: infoRequested
                ? 'Finans ek bilgi bekliyor'
                : 'Bu bayide şu an sipariş veremezsiniz',
            message: reason,
            actionLabel: infoRequested ? 'Yanıtla' : null,
            onAction: infoRequested
                ? () => context.push(
                    approvalId == null
                        ? AppRoutes.financeInfo
                        : AppRoutes.approval(approvalId!),
                  )
                : null,
          ),
          if (station != null) ...[
            const SizedBox(height: 8),
            StationContactButtons(station: station, dense: true),
          ],
        ],
      ),
    );
  }
}

/// Bir sipariş satırı: ürün kartları, litre alanı ve hızlı litre çipleri.
class _LineEditor extends StatelessWidget {
  const _LineEditor({
    super.key,
    required this.index,
    required this.count,
    required this.line,
    required this.products,
    required this.prices,
    required this.controller,
    required this.focusNode,
    required this.onProduct,
    required this.onLiters,
    this.error,
    this.onRemove,
  });

  static const quickLiters = [5000.0, 8000.0, 10000.0];

  final int index;
  final int count;
  final DraftLine line;
  final List<ProductOption> products;
  final Map<int, double> prices;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? error;
  final ValueChanged<int> onProduct;
  final ValueChanged<double?> onLiters;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final price = line.productId == null ? null : prices[line.productId];
    final lineAmount = Estimate.line(line, {
      if (line.productId != null && price != null) line.productId!: price,
    });
    return Padding(
      padding: EdgeInsets.fromLTRB(20, index == 0 ? 0 : 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (count > 1)
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Satır ${index + 1}',
                      style: t.label.copyWith(
                        color: c.ink,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (onRemove != null)
                  AknIconButton(
                    icon: Icons.delete_outline_rounded,
                    semanticLabel: 'Satır ${index + 1} sil',
                    onPressed: onRemove,
                  ),
              ],
            ),
          if (products.length <= 6)
            for (final p in products)
              ChoiceCard(
                margin: const EdgeInsets.only(bottom: 8),
                title: p.name,
                subtitle: prices[p.id] == null
                    ? null
                    : 'güncel fiyat ${Fmt.unitPrice(prices[p.id])}',
                selected: line.productId == p.id,
                onTap: () => onProduct(p.id),
              )
          else
            DropdownButtonFormField<int>(
              initialValue: line.productId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Ürün *'),
              items: [
                for (final p in products)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: (v) {
                if (v != null) onProduct(v);
              },
            ),
          const SizedBox(height: 8),
          LitersField(
            label: 'Litre',
            controller: controller,
            focusNode: focusNode,
            requiredValue: true,
            helper: lineAmount == null
                ? null
                : 'Tahmini ${Fmt.money(lineAmount)}',
            onChanged: onLiters,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final q in quickLiters)
                AknChip(
                  label: Fmt.liters(q),
                  selected: line.liters == q,
                  semanticLabel: '${Fmt.liters(q)} seç',
                  onTap: () {
                    controller.text = Fmt.number(q, maxFraction: 3);
                    onLiters(q);
                  },
                ),
            ],
          ),
          if (error != null) WizardError(error!, padding: EdgeInsets.zero),
        ],
      ),
    );
  }
}

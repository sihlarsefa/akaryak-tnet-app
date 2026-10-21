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
import '../widgets/common.dart';
import '../widgets/contact_actions.dart';

/// Adım 1: bayi (birden çoksa), "Şablondan başla", ürün + litre satırları.
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
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final t in templates)
            AknListTile(
              leadingIcon: Icons.bookmarks_rounded,
              leadingTone: AknTone.brand,
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
    final t = context.aknText;
    final c = context.akn;
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
                AknBanner(
                  tone: AknTone.info,
                  icon: Icons.info_outline_rounded,
                  message: w.notice!,
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                ),
              if (block != null)
                _OrderingBlocked(
                  reason: block,
                  infoRequested: w.ordering?.infoRequested ?? false,
                  approvalId: w.ordering?.openApprovalRequestId,
                ),
              if (stations.length > 1) ...[
                const _Title('Bayi'),
                for (final s in stations)
                  ChoiceCard(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    title: s.title,
                    subtitle: s.canOrder
                        ? 'Sipariş verilebilir'
                        : (s.blockReason ?? 'Şu an sipariş alınamıyor'),
                    leadingIcon: Icons.local_gas_station_rounded,
                    tag: s.id == home?.stationId ? 'Varsayılan' : null,
                    selected: d.stationId == s.id,
                    enabled: s.canOrder,
                    onTap: () => ctrl.setStation(s.id),
                  ),
                if (errorFor('station') != null)
                  _ErrorText(errorFor('station')!),
              ],
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
                child: TitleActionRow(
                  title: Semantics(
                    header: true,
                    child: Text('Ürün ve litre', style: t.headline),
                  ),
                  action: templates.isEmpty
                      ? null
                      : AknButton.ghost(
                          label: OrdersCopy.fromTemplate,
                          icon: Icons.bookmarks_outlined,
                          size: AknButtonSize.small,
                          onPressed: () => _pickTemplate(templates),
                        ),
                ),
              ),
              for (var i = 0; i < d.lines.length; i++)
                _LineCard(
                  key: ValueKey(d.lines[i].uid),
                  index: i,
                  count: d.lines.length,
                  line: d.lines[i],
                  products: form?.products ?? const [],
                  controller: _controllerFor(d.lines[i]),
                  focusNode: _focus.putIfAbsent(d.lines[i].uid, FocusNode.new),
                  price: w.prices[d.lines[i].productId],
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
                padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AknButton.ghost(
                    label: OrdersCopy.addLine,
                    icon: Icons.add_rounded,
                    onPressed: d.lines.length >= WizardRules.maxLines
                        ? null
                        : ctrl.addLine,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: AknCard(
                  color: c.surfaceAlt,
                  shadow: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FactRow(
                        label: 'Toplam',
                        value: Fmt.liters(d.totalLiters),
                      ),
                      FactRow(
                        label: 'Tahmini tutar',
                        value: estimate.value != null
                            ? Fmt.money(estimate.value)
                            : (estimate.unknown
                                  ? OrdersCopy.priceUnknown
                                  : Fmt.dash),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Semantics(
      header: true,
      child: Text(text, style: context.aknText.headline),
    ),
  );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
    child: Text(
      text,
      style: context.aknText.bodySmall.copyWith(color: context.akn.danger.fg),
    ),
  );
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AknBanner(
            tone: infoRequested ? AknTone.warn : AknTone.danger,
            icon: infoRequested
                ? Icons.mark_email_unread_rounded
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

class _LineCard extends StatelessWidget {
  const _LineCard({
    super.key,
    required this.index,
    required this.count,
    required this.line,
    required this.products,
    required this.controller,
    required this.focusNode,
    required this.onProduct,
    required this.onLiters,
    this.price,
    this.error,
    this.onRemove,
  });

  final int index;
  final int count;
  final DraftLine line;
  final List<ProductOption> products;
  final TextEditingController controller;
  final FocusNode focusNode;
  final double? price;
  final String? error;
  final ValueChanged<int> onProduct;
  final ValueChanged<double?> onLiters;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final lineAmount = Estimate.line(line, {
      if (line.productId != null && price != null) line.productId!: price!,
    });
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: AknCard(
        borderColor: error == null ? null : c.danger.line,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (count > 1)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Satır ${index + 1}',
                      style: t.label.copyWith(color: c.dim),
                    ),
                  ),
                  if (onRemove != null)
                    AknIconButton(
                      icon: Icons.delete_outline_rounded,
                      semanticLabel: 'Satır ${index + 1} sil',
                      color: c.dim,
                      onPressed: onRemove,
                    ),
                ],
              ),
            if (products.length <= 6)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in products)
                    ChoiceChip(
                      label: Text(p.name),
                      selected: line.productId == p.id,
                      onSelected: (_) => onProduct(p.id),
                    ),
                ],
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
            const SizedBox(height: 12),
            LitersField(
              label: 'Litre',
              controller: controller,
              focusNode: focusNode,
              requiredValue: true,
              helper: price == null
                  ? null
                  : '${Fmt.unitPrice(price)}${lineAmount == null ? '' : ' · tahmini ${Fmt.money(lineAmount)}'}',
              onChanged: onLiters,
            ),
            if (error != null) ...[
              const SizedBox(height: 6),
              Text(error!, style: t.bodySmall.copyWith(color: c.danger.fg)),
            ],
          ],
        ),
      ),
    );
  }
}

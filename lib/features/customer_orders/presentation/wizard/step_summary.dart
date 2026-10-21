import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../application/home_controller.dart';
import '../../application/ordering_config.dart';
import '../../application/wizard_controller.dart';
import '../../application/wizard_models.dart';
import '../../application/wizard_rules.dart';
import '../../copy.dart';
import '../widgets/common.dart';

/// Tahmini teklif penceresi: min(şimdi + 3 sa, gün sonu) (sunucu `OrderExpiryCalculator`
/// varsayılanı; bayinin ayarı farklıysa kesin süre gönderimden sonra gösterilir).
DateTime predictedQuoteWindow(DateTime now) {
  final later = now.add(const Duration(hours: 3));
  final w = TrTime.wall(now);
  final end = TrTime.fromWall(w.year, w.month, w.day, 23, 59);
  return later.isBefore(end) ? later : end;
}

/// Adım 4: özet, tahmini tutar, şirket içi onay uyarısı (Talep eden), teklif süresi notu,
/// "Onaylayana not" (yalnızca şirket içi onaya düşecekse), "Şablon olarak kaydet".
class StepSummary extends ConsumerStatefulWidget {
  const StepSummary({super.key});

  @override
  ConsumerState<StepSummary> createState() => _StepSummaryState();
}

class _StepSummaryState extends ConsumerState<StepSummary> {
  late final TextEditingController _note;
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    final d = ref.read(orderWizardProvider).draft;
    _note = TextEditingController(text: d.note);
    _name = TextEditingController(text: d.templateName);
  }

  @override
  void dispose() {
    _note.dispose();
    _name.dispose();
    super.dispose();
  }

  String _suggestName(OrderDraft d) {
    final form = ref.read(orderFormProvider).data;
    final products = {
      for (final l in d.lines) form?.product(l.productId)?.name,
    }.whereType<String>().toList();
    final point = form?.point(d.pointId)?.name;
    final p = products.length == 1 ? products.first : '${products.length} ürün';
    return point == null ? p : '$p – $point';
  }

  @override
  Widget build(BuildContext context) {
    final w = ref.watch(orderWizardProvider);
    final ctrl = ref.read(orderWizardProvider.notifier);
    final home = ref.watch(customerHomeProvider).data;
    final form = ref.watch(orderFormProvider).data;
    final config = ref.watch(orderingConfigValueProvider);
    final t = context.aknText;
    final c = context.akn;
    final d = w.draft;
    final m = w.method;
    final est = w.estimate;
    final predicted = ctrl.companyRequestPredicted;
    final rule = home?.companyApproval;
    final expiryOn = config.expiryEnabled(
      home?.dashboard.expiryEnabled ?? true,
    );
    final issues = w.showErrors
        ? ctrl.issuesFor(WizardStep.summary)
        : const <RuleIssue>[];
    String? errorFor(String f) =>
        issues.where((i) => i.field == f).firstOrNull?.message;
    final station = home?.stationById(d.stationId);
    final point = form?.point(d.pointId);
    final created = ctrl.created;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (w.notice != null && d.origin == DraftOrigin.reorder)
                AknBanner(
                  tone: AknTone.info,
                  icon: Icons.replay_rounded,
                  message: w.notice!,
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                ),
              if (d.origin == DraftOrigin.partial && created.isNotEmpty)
                AknBanner(
                  tone: AknTone.info,
                  icon: Icons.call_split_rounded,
                  title: 'Kalan satırlar',
                  message:
                      'Önceki gönderimde ${created.length} sipariş oluştu '
                      '(${created.map((o) => o.orderNumber).join(', ')}). '
                      'Kalan satırlar aynı ödeme grubuyla gönderilecek.',
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                ),
              if (predicted && rule != null)
                AknBanner(
                  tone: AknTone.info,
                  icon: Icons.how_to_reg_rounded,
                  title: 'Şirket içi onaya düşecek',
                  message:
                      '${rule.text} Onaylanınca siparişleriniz bayiye iletilir.',
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                ),
              SectionCard(
                title: 'Sipariş',
                icon: Icons.receipt_long_rounded,
                trailing: _EditButton(
                  semanticLabel: 'Ürünleri düzenle',
                  onPressed: () => ctrl.goTo(WizardStep.products),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (station != null && (home?.stations.length ?? 0) > 1)
                      FactRow(label: 'Bayi', value: station.title),
                    for (final l in d.lines)
                      _LineSummary(
                        product: form?.product(l.productId)?.name ?? 'Ürün',
                        liters: l.liters ?? 0,
                        amount: Estimate.line(l, w.prices),
                        custom: l.custom
                            ? [
                                form?.point(d.pointOf(l))?.name,
                                if (d.dateOf(l) != null) Fmt.date(d.dateOf(l)),
                              ].whereType<String>().join(' · ')
                            : null,
                      ),
                    const Divider(height: 20),
                    FactRow(label: 'Toplam', value: Fmt.liters(d.totalLiters)),
                  ],
                ),
              ),
              SectionCard(
                title: 'Teslimat',
                icon: Icons.place_rounded,
                trailing: _EditButton(
                  semanticLabel: 'Teslimatı düzenle',
                  onPressed: () => ctrl.goTo(WizardStep.delivery),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FactRow(label: 'Nokta', value: point?.name ?? Fmt.dash),
                    if (point?.windowLabel != null)
                      FactRow(label: 'Pencere', value: point!.windowLabel!),
                    FactRow(label: 'Tarih', value: Fmt.date(d.date)),
                  ],
                ),
              ),
              if (w.hasPaymentStep)
                SectionCard(
                  title: 'Ödeme',
                  icon: Icons.payments_rounded,
                  trailing: _EditButton(
                    semanticLabel: 'Ödemeyi düzenle',
                    onPressed: () => ctrl.goTo(WizardStep.payment),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FactRow(
                        label: 'Yöntem',
                        value: WizardRules.paymentSummary(d, m),
                      ),
                      if (m?.requiresFinance ?? false)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            OrdersCopy.financeHint,
                            style: t.bodySmall.copyWith(color: c.dim),
                          ),
                        ),
                      if (m?.isInstrument ?? false)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${m!.displayName} görselini sipariş oluşunca yükleyeceksiniz.',
                            style: t.bodySmall.copyWith(color: c.dim),
                          ),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: AknHeroPanel(
                  watermark: false,
                  child: Builder(
                    builder: (context) {
                      final t2 = context.aknText;
                      final c2 = context.akn;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tahmini tutar',
                            style: t2.label.copyWith(color: c2.dim),
                          ),
                          const SizedBox(height: 4),
                          AmountText(
                            est.value != null
                                ? Fmt.money(est.value)
                                : OrdersCopy.priceUnknown,
                            large: true,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            OrdersCopy.estimateNote,
                            style: t2.caption.copyWith(color: c2.dim),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              if (expiryOn && !predicted)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.schedule_rounded, size: 18, color: c.dim),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Teklif yaklaşık ${withDative(Fmt.time(predictedQuoteWindow(TrTime.now())))} '
                          'kadar geçerli; gün sonunda kapanır.',
                          style: t.bodySmall.copyWith(color: c.text),
                        ),
                      ),
                    ],
                  ),
                ),
              if (predicted)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: AknTextField(
                    controller: _note,
                    label: OrdersCopy.noteForApprover,
                    hint: 'Onaylayacak kişiye kısa bir not (isteğe bağlı)',
                    maxLines: 3,
                    minLines: 2,
                    maxLength: WizardRules.maxNote,
                    textCapitalization: TextCapitalization.sentences,
                    errorText: errorFor('note'),
                    onChanged: ctrl.setNote,
                  ),
                ),
              if (d.origin != DraftOrigin.partial)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: AknCard(
                    padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: d.saveAsTemplate,
                          title: Text(
                            OrdersCopy.saveAsTemplate,
                            style: t.bodyStrong,
                          ),
                          subtitle: Text(
                            d.templateId != null
                                ? 'Bu sipariş bir şablondan; yeni bir şablon olarak da saklayabilirsiniz.'
                                : 'Sonraki siparişlerde tek dokunuşla kullanın.',
                            style: t.bodySmall.copyWith(color: c.dim),
                          ),
                          onChanged: (v) {
                            ctrl.setSaveAsTemplate(v);
                            if (v && _name.text.trim().isEmpty) {
                              _name.text = _suggestName(d);
                              ctrl.setTemplateName(_name.text);
                            }
                          },
                        ),
                        if (d.saveAsTemplate)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: AknTextField(
                              controller: _name,
                              label: OrdersCopy.templateName,
                              maxLength: WizardRules.maxTemplateName,
                              textCapitalization: TextCapitalization.sentences,
                              errorText: errorFor('templateName'),
                              onChanged: ctrl.setTemplateName,
                            ),
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

class _LineSummary extends StatelessWidget {
  const _LineSummary({
    required this.product,
    required this.liters,
    this.amount,
    this.custom,
  });

  final String product;
  final double liters;
  final double? amount;
  final String? custom;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Semantics(
      label: [
        product,
        Fmt.liters(liters),
        if (amount != null) 'tahmini ${Fmt.money(amount)}',
        ?custom,
      ].join(', '),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Builder(
          builder: (context) {
            final info = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$product · ${Fmt.liters(liters)}', style: t.bodyStrong),
                if (custom != null && custom!.isNotEmpty)
                  Text(custom!, style: t.caption.copyWith(color: c.dim)),
              ],
            );
            final money = amount == null
                ? null
                : AmountText(
                    Fmt.money(amount),
                    style: t.bodySmall.copyWith(color: c.text),
                  );
            if (money == null) return info;
            if (isLargeText(context)) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [info, const SizedBox(height: 2), money],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: info),
                const SizedBox(width: 8),
                money,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Özet bölümündeki "Düzenle" (ilgili adıma döner).
class _EditButton extends StatelessWidget {
  const _EditButton({required this.semanticLabel, required this.onPressed});

  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => AknButton.ghost(
    label: 'Düzenle',
    icon: Icons.edit_outlined,
    size: AknButtonSize.small,
    semanticLabel: semanticLabel,
    onPressed: onPressed,
  );
}

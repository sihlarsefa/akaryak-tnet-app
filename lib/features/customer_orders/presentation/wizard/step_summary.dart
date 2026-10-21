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
import '../widgets/order_parts.dart';
import 'wizard_parts.dart';

/// Tahmini teklif penceresi: min(şimdi + 3 sa, gün sonu) (sunucu `OrderExpiryCalculator`
/// varsayılanı; bayinin ayarı farklıysa kesin süre gönderimden sonra gösterilir).
DateTime predictedQuoteWindow(DateTime now) {
  final later = now.add(const Duration(hours: 3));
  final w = TrTime.wall(now);
  final end = TrTime.fromWall(w.year, w.month, w.day, 23, 59);
  return later.isBefore(end) ? later : end;
}

/// Adım 4 (tasarım v2 §7.9 "Özet"): **sihirbaz plakası** (tahmini tutar; kural; Litre / Birim
/// fiyat / Teslim), teklif süresi notu, sipariş / teslimat / ödeme bilgileri ("Değiştir" ile ilgili
/// adıma döner), şirket içi onay uyarısı ve "Onaylayana not" (Talep eden), "Şablon olarak kaydet".
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
                WizardPad(
                  AknBanner(
                    tone: AknTone.info,
                    icon: Icons.replay_rounded,
                    message: w.notice!,
                  ),
                ),
              if (d.origin == DraftOrigin.partial && created.isNotEmpty)
                WizardPad(
                  AknBanner(
                    tone: AknTone.info,
                    icon: Icons.call_split_rounded,
                    title: 'Kalan satırlar',
                    message:
                        'Önceki gönderimde ${created.length} sipariş oluştu '
                        '(${created.map((o) => o.orderNumber).join(', ')}). '
                        'Kalan satırlar aynı ödeme grubuyla gönderilecek.',
                  ),
                ),
              if (predicted && rule != null)
                WizardPad(
                  AknBanner(
                    tone: AknTone.info,
                    icon: Icons.how_to_reg_outlined,
                    title: 'Şirket içi onaya düşecek',
                    message:
                        '${rule.text} Onaylanınca siparişleriniz bayiye iletilir.',
                  ),
                ),
              WizardPad(
                _SummaryPlate(
                  totalLiters: d.totalLiters,
                  estimate: est.value,
                  date: d.date,
                  station: shortCompany(station?.title),
                ),
              ),
              if (expiryOn && !predicted)
                WizardPad(
                  FactLine(
                    icon: Icons.timer_outlined,
                    text:
                        'Teklif yaklaşık ${withDative(Fmt.time(predictedQuoteWindow(TrTime.now())))} '
                        'kadar geçerli; gün sonunda kapanır.',
                  ),
                ),
              SectionHeader(
                title: 'Sipariş',
                actionLabel: 'Değiştir',
                onAction: () => ctrl.goTo(WizardStep.products),
              ),
              if (station != null && (home?.stations.length ?? 0) > 1)
                WizardPad(top: 0, FactRow(label: 'Bayi', value: station.title)),
              AknLedger(
                children: [
                  for (final l in d.lines)
                    AknListTile(
                      dense: true,
                      title: orderTitle(
                        form?.product(l.productId)?.name ?? 'Ürün',
                        l.liters ?? 0,
                      ),
                      subtitle: l.custom
                          ? [
                              form?.point(d.pointOf(l))?.name,
                              if (d.dateOf(l) != null)
                                dayMonthLong(d.dateOf(l)),
                            ].whereType<String>().join(', ')
                          : null,
                      amount: Estimate.line(l, w.prices) == null
                          ? null
                          : Fmt.money(Estimate.line(l, w.prices)),
                      amountMeta: Estimate.line(l, w.prices) == null
                          ? null
                          : 'tahmini',
                    ),
                ],
              ),
              SectionHeader(
                title: 'Teslimat',
                actionLabel: 'Değiştir',
                onAction: () => ctrl.goTo(WizardStep.delivery),
              ),
              WizardPad(
                top: 0,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FactRow(label: 'Nokta', value: point?.name ?? Fmt.dash),
                    if (point?.windowLabel != null)
                      FactRow(
                        label: 'Teslim saatleri',
                        value: point!.windowLabel!,
                      ),
                    FactRow(label: 'Tarih', value: dayMonthWeekday(d.date)),
                  ],
                ),
              ),
              if (w.hasPaymentStep) ...[
                SectionHeader(
                  title: 'Ödeme',
                  actionLabel: 'Değiştir',
                  onAction: () => ctrl.goTo(WizardStep.payment),
                ),
                WizardPad(
                  top: 0,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FactRow(
                        label: 'Yöntem',
                        value: WizardRules.paymentSummary(d, m),
                      ),
                      if (m?.requiresFinance ?? false)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            OrdersCopy.financeHint,
                            style: t.bodySmall.copyWith(color: c.dim),
                          ),
                        ),
                      if (m?.isInstrument ?? false)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${m!.displayName} görselini sipariş oluşunca yükleyeceksiniz.',
                            style: t.bodySmall.copyWith(color: c.dim),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (predicted)
                WizardPad(
                  top: 20,
                  AknTextField(
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
                WizardPad(
                  top: 20,
                  AknCard(
                    padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: d.saveAsTemplate,
                          title: Text(
                            OrdersCopy.saveAsTemplate,
                            style: t.bodyStrong.copyWith(color: c.ink),
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

/// Sihirbaz plakası (§5.2, §7.9): tahmini tutar, kural, Litre / Birim fiyat (tahmini) / Teslim.
/// Fiyat bilinmiyorsa figür litredir ("8.000 L") ve cümle tutarın teklifle belirleneceğini söyler.
class _SummaryPlate extends StatelessWidget {
  const _SummaryPlate({
    required this.totalLiters,
    required this.estimate,
    required this.date,
    required this.station,
  });

  final double totalLiters;
  final double? estimate;
  final DateTime? date;
  final String station;

  @override
  Widget build(BuildContext context) {
    final est = estimate;
    final liters = Fmt.number(totalLiters, maxFraction: 3);
    final avg = est == null || totalLiters <= 0 ? null : est / totalLiters;
    return AknPlate(
      head: PlateHead(
        icon: Icons.receipt_long_outlined,
        title: est == null ? 'Sipariş özeti' : 'Tahmini tutar',
        period: station.isEmpty ? null : station,
      ),
      figure: est == null
          ? PlateFigure(
              value: liters,
              unit: 'L',
              semanticLabel: 'Toplam ${Fmt.liters(totalLiters)}',
            )
          : PlateFigure(
              value: Fmt.number(est.round()),
              unit: '₺',
              semanticLabel: 'Tahmini tutar ${Fmt.number(est.round())} lira',
            ),
      delta: PlateDelta(
        sentence: est == null
            ? '${OrdersCopy.priceUnknown}; tutar bayinin teklifiyle belirlenir.'
            : 'Kesin tutar bayinin teklifiyle belirlenir.',
      ),
      below: PlateReadouts(
        items: [
          if (est != null)
            PlateReadout(label: 'Litre', value: liters, unit: 'L'),
          if (avg != null)
            PlateReadout(
              label: 'Birim fiyat',
              value: Fmt.number(avg, minFraction: 2, maxFraction: 2),
              unit: '₺/L',
              semanticLabel:
                  'Tahmini birim fiyat ${Fmt.number(avg, minFraction: 2, maxFraction: 2)} lira litre',
            ),
          PlateReadout(
            label: 'Teslim',
            value: dayMonthLong(date),
            semanticLabel: 'Teslim ${dayMonthWeekday(date)}',
          ),
        ],
      ),
    );
  }
}

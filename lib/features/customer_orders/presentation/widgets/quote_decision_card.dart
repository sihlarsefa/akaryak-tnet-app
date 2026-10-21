import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/models.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_time.dart';
import '../../application/order_view_controller.dart';
import '../../application/ordering_config.dart';
import '../../copy.dart';
import '../../data/order_models.dart';
import 'common.dart';

/// Teklif karar kartı (spec A.4): ₺/L, toplam, teslim tarihi (talepten farklıysa rozet), sürüm
/// ve zaman, sunucu saatine göre geri sayım (süre kapalıysa gizli), önceki alımlar ve sürüm geçmişi.
class QuoteDecisionCard extends ConsumerWidget {
  const QuoteDecisionCard({
    super.key,
    required this.view,
    this.onUploadDocument,
    this.decisionPending = false,
  });

  final OrderView view;
  final VoidCallback? onUploadDocument;

  /// Karar gönderiliyor / doğrulanıyor.
  final bool decisionPending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.aknText;
    final c = context.akn;
    final d = view.detail;
    final q = view.latestQuote;
    if (q == null) return const SizedBox.shrink();
    final config = ref.watch(orderingConfigValueProvider);
    final expiryOn = config.expiryEnabled(view.tracking?.expiryEnabled ?? true);
    final expires = d.expiresAt;
    final deliveryDiffers =
        q.deliveryDate != null &&
        d.requestedDeliveryDate != null &&
        !TrTime.isSameDay(q.deliveryDate!, d.requestedDeliveryDate!);
    final versions = view.quoteVersions;
    final comparison = view.tracking?.priceComparison;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: AknCard(
        accent: AknTone.warn,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _QuoteHeader(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text('Teklif hazır', style: t.headline),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'v${q.version}${q.createdAt == null ? '' : ' · ${Fmt.dayLabel(q.createdAt)} ${Fmt.time(q.createdAt)}'}',
                    style: t.caption.copyWith(color: c.dim),
                  ),
                ],
              ),
              badge: expiryOn && expires != null
                  ? CountdownBadge(
                      deadline: config.deviceDeadline(expires),
                      start: q.createdAt == null
                          ? null
                          : config.deviceDeadline(q.createdAt!),
                      prefix: 'Kalan',
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            Semantics(
              label:
                  'Birim fiyat ${Fmt.unitPrice(q.unitPriceTry)}, toplam ${Fmt.money(q.totalAmountTry)}',
              excludeSemantics: true,
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 12,
                runSpacing: 4,
                children: [
                  AmountText(Fmt.unitPrice(q.unitPriceTry), large: true),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: AmountText(
                      Fmt.money(q.totalAmountTry),
                      style: t.bodyStrong.copyWith(color: c.text),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            FactRow(label: 'Miktar', value: Fmt.liters(d.quantityLiters)),
            FactRow(
              label: 'Teslim tarihi',
              value: q.deliveryDate == null
                  ? Fmt.date(d.requestedDeliveryDate)
                  : Fmt.date(q.deliveryDate),
              tone: deliveryDiffers ? AknTone.warn : null,
            ),
            if (deliveryDiffers)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Wrap(
                  spacing: 6,
                  children: [
                    const StatusChip(
                      label: OrdersCopy.deliveryDiffers,
                      tone: AknTone.warn,
                      icon: Icons.event_busy_rounded,
                      size: StatusChipSize.small,
                    ),
                    Text(
                      'İstediğiniz: ${Fmt.date(d.requestedDeliveryDate)}',
                      style: t.caption.copyWith(color: c.dim),
                    ),
                  ],
                ),
              ),
            if (view.paymentDocumentMissing) ...[
              const SizedBox(height: 8),
              AknBanner(
                tone: AknTone.warn,
                icon: Icons.photo_camera_outlined,
                title:
                    '${view.documentTarget?.label ?? 'Ödeme belgesi'} bekleniyor',
                message:
                    '${view.documentTarget?.label ?? 'Belge'} yüklenmeden teklif onaylanamaz.',
                actionLabel: onUploadDocument == null ? null : 'Görseli yükle',
                onAction: onUploadDocument,
              ),
            ],
            if (view.advanceInsufficient) ...[
              const SizedBox(height: 8),
              AknBanner(
                tone: AknTone.danger,
                icon: Icons.account_balance_wallet_outlined,
                title: 'Ön ödemeli bakiye yetersiz',
                message:
                    'Kullanılabilir bakiye ${Fmt.money(view.advanceBalance)}, teklif tutarı '
                    '${Fmt.money(q.totalAmountTry)}. Bakiye yüklemek için bayinizle görüşün.',
              ),
            ],
            if (comparison != null && comparison.hasHistory) ...[
              const SizedBox(height: 12),
              _Comparison(comparison: comparison),
            ],
            if (versions.length > 1) ...[
              const SizedBox(height: 12),
              _Versions(versions: versions),
            ],
          ],
        ),
      ),
    );
  }
}

AknTone _diffTone(double? diff) {
  if (diff == null || diff == 0) return AknTone.neutral;
  return diff > 0 ? AknTone.warn : AknTone.ok;
}

String _diffText(double diff) {
  final sign = diff > 0 ? '+' : (diff < 0 ? '−' : '');
  return '$sign%${Fmt.number(diff.abs(), maxFraction: 1)}';
}

class _Comparison extends StatelessWidget {
  const _Comparison({required this.comparison});

  final QuotePriceComparison comparison;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final last = comparison.lastDiffPercent;
    final avg = comparison.averageDiffPercent;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: AknRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            OrdersCopy.previousPurchases,
            style: t.label.copyWith(color: c.text),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (last != null)
                StatusChip(
                  label: 'Son alıma göre ${_diffText(last)}',
                  tone: _diffTone(last),
                  icon: last > 0
                      ? Icons.trending_up_rounded
                      : (last < 0
                            ? Icons.trending_down_rounded
                            : Icons.trending_flat_rounded),
                  size: StatusChipSize.small,
                ),
              if (avg != null && comparison.previous.length > 1)
                StatusChip(
                  label: 'Ortalamaya göre ${_diffText(avg)}',
                  tone: _diffTone(avg),
                  icon: Icons.functions_rounded,
                  size: StatusChipSize.small,
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final p in comparison.previous.take(5))
            Semantics(
              label:
                  '${p.orderNumber}, ${Fmt.date(p.orderedAt)}, ${Fmt.unitPrice(p.unitPriceTry)}'
                  '${p.diffPercent == null ? '' : ', fark ${_diffText(p.diffPercent!)}'}',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(Fmt.date(p.orderedAt), style: t.bodySmall),
                          Text(
                            '${p.orderNumber} · ${Fmt.liters(p.quantityLiters)}',
                            style: t.caption.copyWith(color: c.dim),
                          ),
                        ],
                      ),
                    ),
                    AmountText(
                      Fmt.unitPrice(p.unitPriceTry),
                      style: t.bodySmall.copyWith(color: c.ink),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Versions extends StatelessWidget {
  const _Versions({required this.versions});

  /// Yeni önce.
  final List<Quote> versions;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(OrdersCopy.versions, style: t.label.copyWith(color: c.text)),
        const SizedBox(height: 6),
        for (var i = 0; i < versions.length; i++)
          () {
            final v = versions[i];
            final older = i + 1 < versions.length ? versions[i + 1] : null;
            final delta = older == null
                ? null
                : v.unitPriceTry - older.unitPriceTry;
            final deltaText = delta == null || delta == 0
                ? null
                : '${delta > 0 ? '+' : '−'}${Fmt.unitPrice(delta.abs())}';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('v${v.version}', style: t.bodyStrong),
                      AmountText(
                        Fmt.unitPrice(v.unitPriceTry),
                        style: t.bodySmall.copyWith(color: c.ink),
                      ),
                      if (deltaText != null)
                        StatusChip(
                          label: deltaText,
                          tone: delta! < 0 ? AknTone.ok : AknTone.warn,
                          size: StatusChipSize.small,
                        ),
                      if (v.createdAt != null)
                        Text(
                          Fmt.dateTime(v.createdAt),
                          style: t.caption.copyWith(color: c.dim),
                        ),
                    ],
                  ),
                  if (v.revisionNote != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'Revize notunuz: ${v.revisionNote}',
                        style: t.caption.copyWith(color: c.dim),
                      ),
                    ),
                ],
              ),
            );
          }(),
      ],
    );
  }
}

/// Revize / ret sayfası: web ön ayar çipleri + serbest metin. Not dönerse karar verilir.
Future<String?> showDecisionNoteSheet(
  BuildContext context, {
  required bool revise,
}) => showAppSheet<String>(
  context: context,
  title: revise ? 'Revize isteyin' : 'Teklifi reddedin',
  subtitle: revise ? OrdersCopy.reviseHint : OrdersCopy.rejectHint,
  builder: (ctx) => _DecisionNoteSheet(revise: revise),
);

class _DecisionNoteSheet extends StatefulWidget {
  const _DecisionNoteSheet({required this.revise});

  final bool revise;

  @override
  State<_DecisionNoteSheet> createState() => _DecisionNoteSheetState();
}

class _DecisionNoteSheetState extends State<_DecisionNoteSheet> {
  final _text = TextEditingController();
  final Set<String> _presets = {};
  bool _tried = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  List<String> get _options => widget.revise
      ? QuoteDecisionPresets.revisionReasons
      : QuoteDecisionPresets.rejectReasons;

  String get _note => [
    for (final o in _options)
      if (_presets.contains(o)) o,
    _text.text.trim(),
  ].where((s) => s.isNotEmpty).join('. ');

  void _submit() {
    final note = _note;
    if (widget.revise && note.isEmpty) {
      setState(() => _tried = true);
      return;
    }
    Navigator.of(context).pop(note);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final missing = widget.revise && _tried && _note.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Hazır nedenler', style: t.label.copyWith(color: c.dim)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in _options)
              FilterChip(
                label: Text(o),
                selected: _presets.contains(o),
                onSelected: (v) => setState(() {
                  if (v) {
                    _presets.add(o);
                  } else {
                    _presets.remove(o);
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        AknTextField(
          controller: _text,
          label: OrdersCopy.reasonLabel,
          hint: widget.revise
              ? 'ör. 41,90 ₺/L olursa onaylıyoruz'
              : 'İsteğe bağlı',
          maxLines: 4,
          minLines: 2,
          maxLength: 900,
          textCapitalization: TextCapitalization.sentences,
          errorText: missing
              ? 'Revize için bir neden seçin ya da yazın.'
              : null,
          onChanged: (_) {
            if (_tried) setState(() {});
          },
        ),
        const SizedBox(height: 16),
        if (widget.revise)
          AknButton(
            label: OrdersCopy.revise,
            icon: Icons.edit_note_rounded,
            expand: true,
            onPressed: _submit,
          )
        else
          AknButton.danger(
            label: OrdersCopy.reject,
            icon: Icons.block_rounded,
            expand: true,
            onPressed: _submit,
          ),
      ],
    );
  }
}

/// Onay özeti: "{toplam} · {litre} · teslim {tarih}".
Future<bool> showApproveRecap(
  BuildContext context, {
  required Quote quote,
  required OrderDetail order,
  String? paymentLine,
}) {
  final t = context.aknText;
  final delivery = quote.deliveryDate ?? order.requestedDeliveryDate;
  final recap =
      '${Fmt.money(quote.totalAmountTry)} · ${Fmt.liters(order.quantityLiters)} · teslim ${Fmt.date(delivery)}';
  return showConfirmSheet(
    context,
    title: 'Teklifi onaylıyor musunuz?',
    message: 'Onayladığınızda bayi sevkiyatı planlar.',
    confirmLabel: OrdersCopy.approve,
    icon: Icons.task_alt_rounded,
    tone: AknTone.ok,
    content: Column(
      children: [
        Semantics(
          label: recap,
          excludeSemantics: true,
          child: AmountText(
            recap,
            textAlign: TextAlign.center,
            style: t.headline,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${order.productName} · ${Fmt.unitPrice(quote.unitPriceTry)}'
          '${paymentLine == null ? '' : '\n$paymentLine'}',
          textAlign: TextAlign.center,
          style: t.bodySmall,
        ),
      ],
    ),
  );
}

/// Başlık + geri sayım: normal yazıda yan yana, büyük yazıda (≈%130+) alt alta (taşma olmaz).
class _QuoteHeader extends StatelessWidget {
  const _QuoteHeader({required this.title, this.badge});

  final Widget title;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final b = badge;
    if (b == null) return title;
    if (isLargeText(context)) {
      // Çok büyük yazıda rozet kart genişliğini aşarsa sığacak kadar küçülür (kesilmez).
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title,
          const SizedBox(height: 8),
          FitBadge(child: b),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: title),
        const SizedBox(width: 8),
        b,
      ],
    );
  }
}

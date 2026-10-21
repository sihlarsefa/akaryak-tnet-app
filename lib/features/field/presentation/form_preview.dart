import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/app_failure.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../application/form_wizard_controller.dart';
import '../copy.dart';
import '../data/field_models.dart';
import 'widgets/field_widgets.dart';

/// Canlı önizleme paneli (spec A.3 F2): bant çipi, ipucu, uyarılar, toplamlar, limit göstergesi, finans
/// gerekçeleri. Maliyet / kâr yalnızca `showCosts` iken (sunucu zaten göndermez).
class FieldPreviewPanel extends ConsumerWidget {
  const FieldPreviewPanel({
    super.key,
    required this.args,
    this.compact = false,
    this.showTotals = true,
  });

  final FormWizardArgs args;

  /// Alt sayfada (önizleme şeridinden açılınca).
  final bool compact;

  /// Toplam litre / form tutarı okumaları (özet adımında plaka gösterdiği için kapalı).
  final bool showTotals;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(formWizardProvider(args));
    final t = context.aknText;
    final c = context.akn;
    final p = s.preview;
    final ctrl = ref.read(formWizardProvider(args).notifier);

    if (p == null) {
      if (s.previewLoading) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: LoadingView(message: 'Onay bandı hesaplanıyor'),
        );
      }
      final e = s.previewError;
      return AknBanner(
        tone: e == null ? AknTone.info : AknTone.warn,
        icon: e is OfflineFailure ? Icons.cloud_off_rounded : null,
        message: e == null
            ? FieldCopy.previewIdle
            : e is OfflineFailure
            ? FieldCopy.previewOffline
            : e.message,
        actionLabel: e == null ? null : FieldCopy.retry,
        onAction: e == null ? null : ctrl.refreshPreview,
      );
    }

    final limitRatio = p.limitUsedPct == null ? null : p.limitUsedPct! / 100;
    final limitTone = switch (p.limitState) {
      'exceeded' || 'invalid' || 'none' => AknTone.danger,
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BandBlock(
          preview: p,
          loading: s.previewLoading,
          error: s.previewError,
          onRetry: ctrl.refreshPreview,
        ),
        if (showTotals) ...[
          const SizedBox(height: 12),
          KpiRow(
            children: [
              KpiTile(
                label: 'Toplam litre',
                value: p.totalLiters,
                format: Fmt.liters,
                caption: '${Fmt.cubicMeters(p.totalM3)}, ${p.lineCount} satır',
              ),
              KpiTile(
                label: 'Form tutarı',
                value: p.totalAmount,
                format: Fmt.money,
                caption: p.salesInvoice == null
                    ? null
                    : 'Satış faturası ${Fmt.money(p.salesInvoice)}',
              ),
            ],
          ),
        ],
        if (p.dueDate != null) ...[
          const SizedBox(height: 8),
          FactRow(
            label: 'Ödeme tarihi',
            value: '${Fmt.date(p.dueDate)}, ${Fmt.weekday(p.dueDate)}',
            icon: Icons.event_rounded,
          ),
        ],
        if (p.limitMessage != null || limitRatio != null) ...[
          const SizedBox(height: 12),
          if (limitRatio != null)
            UsageBar(
              value: limitRatio,
              tone: limitTone,
              label: 'Limit kullanımı (bu form dahil)',
              valueLabel: '%${p.limitUsedPct!.round()}',
            ),
          if (p.limitMessage != null) ...[
            const SizedBox(height: 6),
            p.limitBlocking
                ? AknBanner(tone: AknTone.danger, message: p.limitMessage!)
                : Text(p.limitMessage!, style: t.bodySmall),
          ],
        ],
        if (p.financeBlocked != null) ...[
          const SizedBox(height: 12),
          AknBanner(
            tone: AknTone.danger,
            title: 'Form gönderilemez',
            message: p.financeBlocked!,
          ),
        ] else if (p.financeRequired) ...[
          const SizedBox(height: 12),
          AknBanner(
            tone: AknTone.info,
            icon: Icons.account_balance_outlined,
            title: 'Finans onayına düşer',
            message: p.financeReasons.isEmpty
                ? 'Gönderilince finans onayı paralel yürür.'
                : p.financeReasons.join(', '),
          ),
        ],
        if (p.overriddenLines.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Tüpraş fiyatı elle girilen satırlar: ${p.overriddenLines.join(', ')}. Onay kartında gerekçe olarak görünür.',
            style: t.caption,
          ),
        ],
        if (p.showCosts) ...[
          const SizedBox(height: 12),
          _CostBlock(preview: p),
        ] else if (!compact) ...[
          const SizedBox(height: 8),
          Text(
            FieldCopy.previewNoCosts,
            style: t.caption.copyWith(color: c.dim),
          ),
        ],
      ],
    );
  }
}

class _BandBlock extends StatefulWidget {
  const _BandBlock({
    required this.preview,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final FieldPreview preview;
  final bool loading;
  final AppFailure? error;
  final VoidCallback onRetry;

  @override
  State<_BandBlock> createState() => _BandBlockState();
}

class _BandBlockState extends State<_BandBlock> {
  @override
  void didUpdateWidget(covariant _BandBlock old) {
    super.didUpdateWidget(old);
    // Bant değişince ekran okuyucuya bildirilir (her tuşta değil; yalnızca sonuç değişince).
    if (old.preview.band != widget.preview.band) {
      final view = View.maybeOf(context);
      if (view != null) {
        unawaited(
          SemanticsService.sendAnnouncement(
            view,
            'Onay bandı: ${widget.preview.band.label}',
            TextDirection.ltr,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    final t = context.aknText;
    final c = context.akn;
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: AknRadius.card,
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Onay bandı',
                  style: t.label.copyWith(
                    fontWeight: FontWeight.w600,
                    color: c.dim,
                  ),
                ),
              ),
              if (widget.loading)
                const ChevronSpinner(size: 18, semanticLabel: 'Hesaplanıyor'),
            ],
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: AknMotion.of(context, AknMotion.base),
            child: FieldBandChip(
              key: ValueKey(p.band.key + p.band.label),
              band: p.band,
            ),
          ),
          if (p.hint.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(p.hint, style: t.bodySmall.copyWith(color: c.ink)),
          ],
          for (final n in p.notices) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: c.warn.fg,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(n, style: t.bodySmall.copyWith(color: c.ink)),
                ),
              ],
            ),
          ],
          if (widget.error != null && !widget.loading) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.error is OfflineFailure
                        ? 'Son hesaplama gösteriliyor (bağlantı yok).'
                        : 'Son hesaplama gösteriliyor: ${widget.error!.message}',
                    style: t.caption.copyWith(color: c.dim),
                  ),
                ),
                AknButton.ghost(
                  label: FieldCopy.retry,
                  size: AknButtonSize.small,
                  onPressed: widget.onRetry,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CostBlock extends StatelessWidget {
  const _CostBlock({required this.preview});

  final FieldPreview preview;

  @override
  Widget build(BuildContext context) {
    final p = preview;
    final t = context.aknText;
    return Container(
      decoration: BoxDecoration(
        color: context.akn.surfaceAlt,
        borderRadius: AknRadius.card,
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: context.akn.dim,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Kârlılık (yalnızca bayi içi)',
                  style: t.label.copyWith(
                    fontWeight: FontWeight.w600,
                    color: context.akn.dim,
                  ),
                ),
              ),
            ],
          ),
          if (p.chip != null) ...[
            const SizedBox(height: 6),
            Text(p.chip!, style: t.bodyStrong),
          ],
          if (p.formProfitPercent != null)
            FactRow(
              label: 'Form kâr %',
              value: Fmt.percent(p.formProfitPercent, maxFraction: 2),
            ),
          if (p.marginPercent != null)
            FactRow(
              label: 'Marj',
              value: Fmt.percent(p.marginPercent, maxFraction: 2),
            ),
          if (p.netProfit != null)
            FactRow(
              label: 'Net kâr (KDV hariç)',
              value: Fmt.money(p.netProfit),
            ),
          if (p.reason != null) ...[
            const SizedBox(height: 4),
            Text(p.reason!, style: t.caption),
          ],
        ],
      ),
    );
  }
}

/// Alt çubuktaki önizleme şeridi: bant + tutar; dokununca ayrıntılar açılır.
class FieldPreviewStrip extends ConsumerWidget {
  const FieldPreviewStrip({super.key, required this.args});

  final FormWizardArgs args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(formWizardProvider(args));
    final t = context.aknText;
    final c = context.akn;
    final p = s.preview;
    final amount =
        p?.totalAmount ??
        (s.draft.estimatedAmount > 0 ? s.draft.estimatedAmount : null);
    final String status;
    if (p != null) {
      status = p.band.label;
    } else if (s.previewLoading) {
      status = 'Hesaplanıyor';
    } else if (s.previewError is OfflineFailure) {
      status = 'Önizleme için bağlantı yok';
    } else {
      status = 'Onay bandı hesaplanmadı';
    }
    return Semantics(
      button: true,
      label:
          'Önizleme: $status${amount == null ? '' : ', ${p == null ? 'tahmini ' : ''}${Fmt.money(amount)}'}. Ayrıntılar için dokunun.',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AknRadius.card,
        onTap: () => showAppSheet<void>(
          context: context,
          title: 'Önizleme',
          builder: (_) => FieldPreviewPanel(args: args, compact: true),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AknSpace.minTap),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Builder(
              builder: (context) {
                final head = <Widget>[
                  if (p != null)
                    Flexible(child: FieldBandChip(band: p.band, small: true))
                  else if (s.previewLoading)
                    const ChevronSpinner(size: 18, semanticLabel: null)
                  else
                    Icon(
                      s.previewError is OfflineFailure
                          ? Icons.cloud_off_rounded
                          : Icons.insights_rounded,
                      size: 18,
                      color: c.dim,
                    ),
                  if (p == null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(status, style: t.caption, maxLines: 2),
                    ),
                  ],
                ];
                final amountText = amount == null
                    ? null
                    : Text(
                        p == null
                            ? '≈ ${Fmt.money(amount)}'
                            : Fmt.money(amount),
                        style: t.amount.copyWith(fontSize: 15),
                      );
                final arrow = Icon(Icons.expand_less_rounded, color: c.dim);
                if (fieldLargeText(context)) {
                  // Büyük yazı: bant bir satırda, tutar altında.
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [...head, const Spacer(), arrow]),
                      ?amountText,
                    ],
                  );
                }
                return Row(
                  children: [...head, const Spacer(), ?amountText, arrow],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

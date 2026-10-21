import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

/// Sayfa bölümü (tasarım v2 §4.5): kutu yok — başlık (`title` 20/26) + içerik. Sağda ya bir not
/// ([caption], "son 12 ay") ya da bir gezinme ([actionLabel] + ›, mürekkep).
class StatsSection extends StatelessWidget {
  const StatsSection({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.caption,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? caption;
  final String? actionLabel;
  final VoidCallback? onAction;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      SectionHeader(
        title: title,
        subtitle: subtitle,
        caption: caption,
        actionLabel: onAction == null ? null : actionLabel,
        onAction: onAction,
        padding: const EdgeInsets.fromLTRB(20, 26, 12, 6),
      ),
      ...children,
    ],
  );
}

/// Defter satırı (beyaz sayfa): etiket solda, değer sağda; isteğe bağlı soluk not ve ton.
class StatsFactRow extends StatelessWidget {
  const StatsFactRow({
    super.key,
    required this.label,
    required this.value,
    this.note,
    this.tone,
  });

  final String label;
  final String value;
  final String? note;

  /// Sorunlu satır (gecikme): etiket ve değer ton renginde, kalın.
  final AknTone? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final tc = tone == null ? null : c.tone(tone!);
    final labelStyle = t.body.copyWith(
      color: tc?.fg ?? c.ink,
      fontWeight: tone == null ? FontWeight.w400 : FontWeight.w600,
    );
    final valueStyle = t.body.copyWith(
      fontWeight: FontWeight.w600,
      color: tc?.fg ?? c.ink,
    );
    return Semantics(
      label: [label, value, ?note].join(', '),
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AknSpace.minTap),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    text: label,
                    children: [
                      if (note != null)
                        TextSpan(
                          text: '  $note',
                          style: t.bodySmall.copyWith(color: c.dim),
                        ),
                    ],
                  ),
                  style: labelStyle,
                ),
              ),
              const SizedBox(width: 12),
              Text(value, style: valueStyle, maxLines: 1, softWrap: false),
            ],
          ),
        ),
      ),
    );
  }
}

/// Satırları 20 px içeriden hairline ile ayırır (yalnızca satırlar arasında).
class StatsDivided extends StatelessWidget {
  const StatsDivided({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final line = context.akn.line;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(height: 1, child: ColoredBox(color: line)),
            ),
          children[i],
        ],
      ],
    );
  }
}

/// Beyaz sayfada oran satırı: "%92 zamanında ……… hedef %90" (yüzde kalın).
class StatsRateLine extends StatelessWidget {
  const StatsRateLine({
    super.key,
    required this.rate,
    required this.label,
    this.trailing,
  });

  final String rate;
  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final style = t.body.copyWith(color: c.ink);
    return ExcludeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: rate,
                    style: style.copyWith(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: ' $label'),
                ],
              ),
              style: style,
            ),
          ),
          if (trailing != null)
            Text(trailing!, style: t.bodySmall.copyWith(color: c.dim)),
        ],
      ),
    );
  }
}

/// Beyaz sayfada büyük okuma: `number` rakam + birim ("42,34 ₺/L").
class StatsReadoutFigure extends StatelessWidget {
  const StatsReadoutFigure({super.key, required this.value, this.unit});

  final String value;
  final String? unit;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Text.rich(
      TextSpan(
        text: value,
        style: t.numberLarge.copyWith(color: c.ink),
        children: [
          if (unit != null)
            TextSpan(
              text: ' $unit',
              style: t.readoutUnit.copyWith(
                color: c.ink,
                fontSize: math.max(16, t.readoutUnit.fontSize ?? 16) + 2,
              ),
            ),
        ],
      ),
      maxLines: 1,
      softWrap: false,
    );
  }
}

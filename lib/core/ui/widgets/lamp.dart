import 'package:flutter/material.dart';

import '../motion.dart';
import '../status.dart';
import '../theme.dart';
import '../tokens.dart';

/// Lamp sizes: medium = 8 px dot + 14/20 label; small = 6 px dot + 13/18.
enum AknLampSize { small, medium }

/// Status as a lamp and a word (design v2 §6.12): a dot, a gap and the
/// Turkish label. No pill, no tint, no border, no icon — status is never
/// colour alone, the word always carries it.
///
/// Tone → dot / label:
/// * `brand` ("your move"): logo-orange dot, Pas label 600.
/// * `info` (in progress, someone else's move): ink dot, ink label.
/// * `ok` / `warn`: tone solid dot, tone label.
/// * `danger`: red dot, red label 600.
/// * `neutral` (closed, cancelled): hollow 1.5 px ring, dim label.
///
/// [solid] (terminal successes such as "Tamamlandı") sets the label to 600.
/// On the plate every tone prints black (the plate palette has no status
/// colours). The label wraps instead of being cut (unless [maxLines] is set).
///
/// ```dart
/// AknLamp.style(order.status.statusStyle.withLabel(order.statusLabel))
/// AknLamp.status(AknStatus.lampFor(order, viewer))
/// ```
class AknLamp extends StatelessWidget {
  const AknLamp({
    super.key,
    required this.label,
    required this.tone,
    this.solid = false,
    this.size = AknLampSize.medium,
    this.maxLines,
    this.semanticLabel,
    this.style,
  });

  /// A lamp for a generic [StatusStyle] (`order.status.statusStyle`).
  AknLamp.style(
    StatusStyle status, {
    super.key,
    this.size = AknLampSize.medium,
    this.maxLines,
    this.semanticLabel,
    this.style,
  }) : label = status.label,
       tone = status.tone,
       solid = status.solid;

  /// A lamp for a viewer-aware [StatusLamp] (`AknStatus.lampFor`).
  AknLamp.status(
    StatusLamp lamp, {
    super.key,
    this.size = AknLampSize.medium,
    this.maxLines,
    this.semanticLabel,
    this.style,
  }) : label = lamp.label,
       tone = lamp.tone,
       solid = lamp.solid;

  final String label;
  final AknTone tone;

  /// Label weight 600 (terminal success).
  final bool solid;
  final AknLampSize size;

  /// Null lets the label wrap (nothing is cut at large text).
  final int? maxLines;

  /// Screen-reader text (defaults to [label]).
  final String? semanticLabel;

  /// Overrides the label style (size, weight); the colour stays the tone's.
  final TextStyle? style;

  /// The label weight for [tone] (600 for "your move", danger and [solid]).
  static FontWeight weightFor(AknTone tone, {bool solid = false}) =>
      solid || tone == AknTone.brand || tone == AknTone.danger
      ? FontWeight.w600
      : FontWeight.w500;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final tc = c.tone(tone);
    final small = size == AknLampSize.small;
    final base = small
        ? t.label
        : t.bodySmall.copyWith(fontWeight: FontWeight.w500);
    final textStyle = base
        .merge(style)
        .copyWith(
          color: tc.fg,
          fontWeight: weightFor(tone, solid: solid),
        );
    final dot = small ? 6.0 : 8.0;
    final gap = small ? 6.0 : 8.0;
    final fontSize = textStyle.fontSize ?? 14;
    final lineHeight =
        MediaQuery.textScalerOf(context).scale(fontSize) *
        (textStyle.height ?? 20 / 14);
    final hollow = tone == AknTone.neutral;
    return Semantics(
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: lineHeight,
            child: Center(
              child: AnimatedContainer(
                duration: AknMotion.of(context, AknMotion.base),
                curve: AknMotion.standard,
                width: dot,
                height: dot,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hollow ? Colors.transparent : tc.solid,
                  border: hollow
                      ? Border.all(color: c.faint, width: 1.5)
                      : null,
                ),
              ),
            ),
          ),
          SizedBox(width: gap),
          Flexible(
            child: Text(
              label,
              style: textStyle,
              maxLines: maxLines,
              overflow: maxLines == null ? null : TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

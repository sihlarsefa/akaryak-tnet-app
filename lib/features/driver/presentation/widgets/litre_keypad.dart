import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../application/deliver_flow.dart';
import '../../copy.dart';

/// Büyük litre tuş takımı (eldivenle, güneş altında kullanılır): büyük ekran, 1–9, virgül, 0, sil
/// (basılı tutunca temizler). Tuşlar en az 56 dp, yazı büyüdükçe uzar.
class LitreKeypad extends StatelessWidget {
  const LitreKeypad({super.key, required this.onKey, this.onClear});

  final ValueChanged<String> onKey;
  final VoidCallback? onClear;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    [LitersKeypad.comma, '0', LitersKeypad.backspace],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in _rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                for (var i = 0; i < row.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _Key(
                      value: row[i],
                      onTap: () => onKey(row[i]),
                      onLongPress: row[i] == LitersKeypad.backspace
                          ? onClear
                          : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.value, required this.onTap, this.onLongPress});

  final String value;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final isBackspace = value == LitersKeypad.backspace;
    final isComma = value == LitersKeypad.comma;
    final label = isBackspace
        ? DriverCopy.keyDelete
        : isComma
        ? DriverCopy.keyComma
        : value;
    return Semantics(
      button: true,
      label: label,
      hint: isBackspace ? 'Basılı tutunca tümü silinir' : null,
      excludeSemantics: true,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Material(
        color: isBackspace || isComma ? c.surfaceAlt : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AknRadius.card,
          side: BorderSide(color: c.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            AknHaptics.selection();
            onTap();
          },
          onLongPress: onLongPress == null
              ? null
              : () {
                  AknHaptics.medium();
                  onLongPress!();
                },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: isBackspace
                    ? Icon(Icons.backspace_outlined, color: c.ink, size: 26)
                    : Text(
                        value,
                        style: t.amountLarge.copyWith(
                          fontSize: 26,
                          height: 32 / 26,
                          color: c.ink,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tuş takımının üstündeki büyük litre göstergesi.
class LitersDisplay extends StatelessWidget {
  const LitersDisplay({
    super.key,
    required this.text,
    this.error,
    this.warning,
  });

  /// Tuş takımı metni (`7950,5`).
  final String text;
  final String? error;
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final shown = LitersKeypad.display(text);
    final empty = text.isEmpty;
    final hasError = error != null;
    return Semantics(
      label: DriverCopy.stepLiters,
      value: empty ? 'Girilmedi' : '$shown litre',
      hint: hasError ? error : warning,
      liveRegion: true,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: AknRadius.card,
          border: Border.all(
            color: hasError ? c.danger.line : c.lineStrong,
            width: hasError ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      shown,
                      maxLines: 1,
                      style: t.display.copyWith(
                        fontSize: 40,
                        height: 48 / 40,
                        color: empty ? c.dim : c.ink,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('L', style: t.title.copyWith(color: c.dim)),
              ],
            ),
            if (hasError) ...[
              const SizedBox(height: 6),
              _Line(text: error!, tone: AknTone.danger),
            ] else if (warning != null) ...[
              const SizedBox(height: 6),
              _Line(text: warning!, tone: AknTone.warn),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.text, required this.tone});

  final String text;
  final AknTone tone;

  @override
  Widget build(BuildContext context) {
    final tc = context.akn.tone(tone);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(AknStatus.toneIcon(tone), size: 16, color: tc.fg),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: context.aknText.bodySmall.copyWith(color: tc.fg),
          ),
        ),
      ],
    );
  }
}

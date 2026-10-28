import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../application/deliver_flow.dart';
import '../../copy.dart';

/// Büyük litre tuş takımı (eldivenle, güneş altında kullanılır; tasarım v3 §4–5): 1–9, virgül, 0,
/// sil (basılı tutunca temizler). Rakam tuşları beyaz, r16, yumuşak kart gölgesi; virgül ve sil
/// kuyu renginde. Rakamlar Archivo 800 tablo rakamları. Basınca tuş 0,94'e küçülür,
/// gölgesi oturur ve zemini kuyu rengine döner (yaylı bırakış), her dokunuşta hafif titreşim.
/// Sürücü kipinde en az 64 dp (§6.30), yazı büyüdükçe uzar.
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
            padding: EdgeInsets.only(bottom: row == _rows.last ? 0 : 10),
            child: Row(
              children: [
                for (var i = 0; i < row.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
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

class _Key extends StatefulWidget {
  const _Key({required this.value, required this.onTap, this.onLongPress});

  final String value;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  static const BorderRadius _radius = BorderRadius.all(Radius.circular(16));
  bool _pressed = false;

  void _press(bool v) {
    if (v != _pressed) setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final value = widget.value;
    final isBackspace = value == LitersKeypad.backspace;
    final isComma = value == LitersKeypad.comma;
    final quiet = isBackspace || isComma;
    final label = isBackspace
        ? DriverCopy.keyDelete
        : isComma
        ? DriverCopy.keyComma
        : value;
    final reduced = AknMotion.reduced(context);
    final duration = _pressed ? AknMotion.press : AknMotion.pressOut;
    final rest = quiet
        ? c.surfaceAlt
        : (c.isDark ? c.surfaceRaised : c.surface);
    final fill = _pressed ? (quiet ? c.line : c.surfaceAlt) : rest;
    final glyph = isBackspace
        ? Icon(PhosphorIconsRegular.backspace, color: c.ink, size: 26)
        : Text(
            value,
            style: t.number.copyWith(
              fontSize: isComma ? 30 : 28,
              height: 34 / 28,
              fontWeight: FontWeight.w800,
              color: c.ink,
            ),
          );
    return Semantics(
      button: true,
      label: label,
      hint: isBackspace ? 'Basılı tutunca tümü silinir' : null,
      excludeSemantics: true,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _pressed && !reduced ? 0.94 : 1,
        duration: duration,
        curve: _pressed ? AknMotion.standard : AknMotion.spring,
        child: AnimatedContainer(
          duration: AknMotion.of(context, duration),
          curve: AknMotion.standard,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: _radius,
            border: c.isDark && !quiet ? Border.all(color: c.line) : null,
            boxShadow: quiet
                ? null
                : (_pressed ? AknShadows.pressed(c) : AknShadows.card(c)),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: _radius,
              splashFactory: NoSplash.splashFactory,
              highlightColor: Colors.transparent,
              hoverColor: Colors.transparent,
              onHighlightChanged: _press,
              onTap: () {
                AknHaptics.light();
                widget.onTap();
              },
              onLongPress: widget.onLongPress == null
                  ? null
                  : () {
                      AknHaptics.medium();
                      widget.onLongPress!();
                    },
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: context.minTap),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: glyph,
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

/// Plakasız büyük litre göstergesi (sihirbaz artık okumayı plakada gösterir; başka ekranlar için):
/// beyaz alan (r20, 1,5 px çizgi; hatada tehlike çizgisi), sağa yaslı büyük tablo rakamları
/// (sığmazsa küçülür), uyarı / hata satırı yumuşakça belirir.
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
            color: hasError ? c.danger.solid : c.line,
            width: hasError ? 2 : 1.5,
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
                      style: t.numberLarge.copyWith(
                        fontSize: 40,
                        height: 48 / 40,
                        color: empty ? c.dim : c.ink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('L', style: t.title.copyWith(color: c.dim)),
              ],
            ),
            AknAnimatedSize(
              alignment: Alignment.topCenter,
              child: hasError
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _Line(text: error!, tone: AknTone.danger),
                    )
                  : warning != null
                  ? Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _Line(text: warning!, tone: AknTone.warn),
                    )
                  : const SizedBox(width: double.infinity),
            ),
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

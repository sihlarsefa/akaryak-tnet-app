import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_number.dart';

/// Sayı girişi (Türkçe ayırıcılar; "," ya da "." ondalık). Dışarıdan değer değişirse (ör. ürün seçilince
/// önerilen fiyat) alan odakta değilken metin güncellenir; odaktan çıkınca biçim düzelir (spec C.7).
class FieldNumberInput extends StatefulWidget {
  const FieldNumberInput({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.decimals = 2,
    this.unit,
    this.helper,
    this.error,
    this.enabled = true,
    this.requiredMark = false,
    this.textInputAction = TextInputAction.next,
    this.integer = false,
  });

  final String label;
  final num? value;
  final ValueChanged<double?> onChanged;
  final int decimals;
  final String? unit;
  final String? helper;
  final String? error;
  final bool enabled;
  final bool requiredMark;
  final TextInputAction textInputAction;

  /// Yalnızca tam sayı (gün, adet).
  final bool integer;

  @override
  State<FieldNumberInput> createState() => _FieldNumberInputState();
}

class _FieldNumberInputState extends State<FieldNumberInput> {
  late final TextEditingController _controller = TextEditingController(
    text: _format(widget.value),
  );
  final _focus = FocusNode();

  String _format(num? v) => v == null
      ? ''
      : widget.integer
      ? '${v.round()}'
      : Fmt.number(v, maxFraction: widget.decimals);

  double? _parse(String s) {
    if (widget.integer) {
      final d = s.replaceAll(RegExp(r'\D'), '');
      return d.isEmpty ? null : double.tryParse(d);
    }
    return TrNumber.parse(s);
  }

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _normalize();
    });
  }

  void _normalize() {
    final v = _parse(_controller.text);
    final text = _format(v);
    if (text != _controller.text) _controller.text = text;
  }

  @override
  void didUpdateWidget(covariant FieldNumberInput old) {
    super.didUpdateWidget(old);
    if (_focus.hasFocus) return;
    final current = _parse(_controller.text);
    final next = widget.value?.toDouble();
    if (current != next) _controller.text = _format(next);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AknTextField(
      controller: _controller,
      focusNode: _focus,
      label: widget.label,
      helper: widget.helper,
      errorText: widget.error,
      enabled: widget.enabled,
      requiredMark: widget.requiredMark,
      textInputAction: widget.textInputAction,
      keyboardType: widget.integer
          ? TextInputType.number
          : const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: widget.integer
          ? [FilteringTextInputFormatter.digitsOnly]
          : [TrNumberInputFormatter(decimals: widget.decimals)],
      suffixText: widget.unit,
      style: context.aknText.amount.copyWith(fontSize: 16),
      onChanged: (s) => widget.onChanged(_parse(s)),
    );
  }
}

/// Metin girişi; dışarıdan gelen değer odak dışındayken metne yansır.
class FieldTextInput extends StatefulWidget {
  const FieldTextInput({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.helper,
    this.error,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.sentences,
    this.requiredMark = false,
    this.autofillHints,
    this.textInputAction,
    this.inputFormatters,
    this.prefixIcon,
  });

  final String label;
  final String? value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final String? helper;
  final String? error;
  final int? maxLength;
  final int? maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final bool requiredMark;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final IconData? prefixIcon;

  @override
  State<FieldTextInput> createState() => _FieldTextInputState();
}

class _FieldTextInputState extends State<FieldTextInput> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value ?? '',
  );
  final _focus = FocusNode();

  @override
  void didUpdateWidget(covariant FieldTextInput old) {
    super.didUpdateWidget(old);
    if (_focus.hasFocus) return;
    final v = widget.value ?? '';
    if (v != _controller.text) _controller.text = v;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AknTextField(
    controller: _controller,
    focusNode: _focus,
    label: widget.label,
    hint: widget.hint,
    helper: widget.helper,
    errorText: widget.error,
    maxLength: widget.maxLength,
    maxLines: widget.maxLines,
    minLines: widget.minLines,
    keyboardType: widget.keyboardType,
    textCapitalization: widget.textCapitalization,
    requiredMark: widget.requiredMark,
    autofillHints: widget.autofillHints,
    textInputAction:
        widget.textInputAction ??
        ((widget.maxLines ?? 1) > 1
            ? TextInputAction.newline
            : TextInputAction.next),
    inputFormatters: widget.inputFormatters,
    prefixIcon: widget.prefixIcon,
    onChanged: widget.onChanged,
  );
}

/// Seçim satırı: etiket + seçili değer; dokununca seçenekler alt sayfada (ChoiceCard) açılır.
class FieldPickerTile<T> extends StatelessWidget {
  const FieldPickerTile({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onSelected,
    this.placeholder = 'Seçin',
    this.error,
    this.enabled = true,
    this.icon,
    this.requiredMark = false,
  });

  final String label;
  final List<FieldPickerOption<T>> options;
  final T? value;
  final ValueChanged<T> onSelected;
  final String placeholder;
  final String? error;
  final bool enabled;
  final IconData? icon;
  final bool requiredMark;

  Future<void> _open(BuildContext context) async {
    final picked = await showAppSheet<T>(
      context: context,
      title: label,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final o in options)
            ChoiceCard(
              title: o.title,
              subtitle: o.subtitle,
              tag: o.tag,
              leadingIcon: o.icon,
              selected: o.value == value,
              margin: const EdgeInsets.only(bottom: 8),
              onTap: () => Navigator.of(ctx).pop(o.value),
            ),
        ],
      ),
    );
    if (picked != null) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    FieldPickerOption<T>? selected;
    for (final o in options) {
      if (o.value == value) selected = o;
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label:
          '$label${requiredMark ? ', zorunlu' : ''}: ${selected?.title ?? placeholder}',
      excludeSemantics: true,
      onTap: enabled ? () => _open(context) : null,
      child: InkWell(
        onTap: enabled ? () => _open(context) : null,
        borderRadius: AknRadius.input,
        child: InputDecorator(
          isEmpty: selected == null,
          decoration: InputDecoration(
            labelText: requiredMark ? '$label *' : label,
            errorText: error,
            enabled: enabled,
            prefixIcon: icon == null ? null : Icon(icon, size: 20),
            suffixIcon: const Icon(PhosphorIconsRegular.caretUpDown, size: 20),
          ),
          child: selected == null
              ? const SizedBox(height: 22)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      selected.title,
                      style: t.body.copyWith(fontSize: 16, color: c.ink),
                    ),
                    if (selected.subtitle != null)
                      Text(selected.subtitle!, style: t.caption),
                  ],
                ),
        ),
      ),
    );
  }
}

/// [FieldPickerTile] seçeneği.
@immutable
class FieldPickerOption<T> {
  const FieldPickerOption({
    required this.value,
    required this.title,
    this.subtitle,
    this.tag,
    this.icon,
  });

  final T value;
  final String title;
  final String? subtitle;
  final String? tag;
  final IconData? icon;
}

/// Açma / kapama satırı (en az 48 dp; etiket + açıklama).
class FieldSwitchTile extends StatelessWidget {
  const FieldSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: AknRadius.card,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AknSpace.minTap),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: t.body),
                      if (subtitle != null) Text(subtitle!, style: t.caption),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(value: value, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Onay kutusu satırı (KVKK, yöntemler).
class FieldCheckTile extends StatelessWidget {
  const FieldCheckTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.child,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Başlık yerine zengin içerik.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: AknRadius.card,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AknSpace.minTap),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 8),
                  child: child ?? Text(title, style: t.body),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Taslak olarak sakla" / "Çık" / "Devam et" (sihirbazdan kaydetmeden çıkış; spec C.5).
enum WizardLeaveChoice { save, discard, stay }

Future<WizardLeaveChoice> showWizardLeaveSheet(
  BuildContext context, {
  bool canSave = true,
}) async {
  final choice = await showAppSheet<WizardLeaveChoice>(
    context: context,
    showClose: false,
    builder: (ctx) {
      final t = ctx.aknText;
      final c = ctx.akn;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          const Center(
            child: AknIconBox(
              icon: PhosphorIconsRegular.notePencil,
              tone: AknTone.warn,
              size: 56,
            ),
          ),
          const SizedBox(height: 16),
          Semantics(
            header: true,
            child: Text(
              'Girdiğiniz bilgiler kaydedilmedi',
              style: t.headline,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            canSave
                ? 'Taslak olarak saklarsanız bağlantı olmasa da kaybolmaz; sonra devam edebilirsiniz.'
                : 'Çıkarsanız değişiklikler silinir.',
            style: t.body.copyWith(color: c.dim),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (canSave) ...[
            AknButton(
              label: 'Taslak olarak sakla',
              icon: PhosphorIconsRegular.floppyDisk,
              expand: true,
              onPressed: () => Navigator.of(ctx).pop(WizardLeaveChoice.save),
            ),
            const SizedBox(height: 8),
          ],
          AknButton.secondary(
            label: 'Devam et',
            expand: true,
            onPressed: () => Navigator.of(ctx).pop(WizardLeaveChoice.stay),
          ),
          const SizedBox(height: 4),
          AknButton.ghost(
            label: 'Kaydetmeden çık',
            expand: true,
            onPressed: () => Navigator.of(ctx).pop(WizardLeaveChoice.discard),
          ),
        ],
      );
    },
  );
  return choice ?? WizardLeaveChoice.stay;
}

/// Sihirbazın alt çubuğundaki düğme sırası (tasarım v3 §5): solda isteğe bağlı ikincil düğme ([left]:
/// "Geri", "Taslak kaydet") yana açılarak gelir ve gider, birincil düğme kalan yeri doldurur; adım
/// türü ([stepKey]) değişince ("İleri" ↔ "Onaya gönder") düğmeler solarak ve yaylanarak büyüyerek yer
/// değiştirir. Hareket azaltmada anında.
class FieldWizardButtons extends StatelessWidget {
  const FieldWizardButtons({
    super.key,
    required this.stepKey,
    required this.primary,
    this.left,
    this.gap = 12,
  });

  /// Düğmelerin türünü belirleyen değer (ör. son adım mı).
  final Object stepKey;
  final Widget primary;
  final Widget? left;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final duration = AknMotion.of(context, AknMotion.base);
    Widget swap(Widget child, String slot) => AnimatedSwitcher(
      duration: duration,
      switchInCurve: AknMotion.spring,
      switchOutCurve: AknMotion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(animation),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) =>
          Stack(alignment: Alignment.center, children: [...previous, ?current]),
      child: KeyedSubtree(key: ValueKey('$slot-$stepKey'), child: child),
    );
    final l = left;
    return LayoutBuilder(
      builder: (context, cons) {
        final half = math.max(0.0, (cons.maxWidth - gap) / 2);
        return Row(
          children: [
            AknAnimatedSize(
              duration: AknMotion.slow,
              curve: AknMotion.emphasizedCurve,
              alignment: AlignmentDirectional.centerStart,
              child: l == null
                  ? const SizedBox(width: 0, height: 0)
                  : Padding(
                      padding: EdgeInsetsDirectional.only(end: gap),
                      child: SizedBox(width: half, child: swap(l, 'left')),
                    ),
            ),
            Expanded(child: swap(primary, 'primary')),
          ],
        );
      },
    );
  }
}

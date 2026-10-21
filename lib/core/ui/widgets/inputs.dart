import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/debouncer.dart';
import '../../utils/format.dart';
import '../../utils/tr_number.dart';
import '../../utils/tr_time.dart';
import '../../utils/turkish_text.dart';
import '../../utils/validators.dart';
import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';
import 'filters.dart';
import 'plate_badge.dart';

/// Text field in the v2 style (§6.10): the label sits **above** the field
/// (13/18 500 ink, 6 px gap) with an optional right-aligned link in the
/// label row ("Şifremi unuttum"); the field is 52 px, r12, white with a 1 px
/// control border (3.14:1), value 16/22 ink, hint dim. Focus = 2 px orange
/// border and caret; error = 2 px red border and a line under the field
/// (`error_rounded` + a sentence that says what to do); disabled = Beton
/// fill, hairline border, faint text.
///
/// A thin, typed wrapper over [TextFormField]; use it inside a [Form] for
/// `validator`. Screen readers hear the label as the field's name.
class AknTextField extends StatelessWidget {
  const AknTextField({
    super.key,
    this.controller,
    this.initialValue,
    this.label,
    this.hint,
    this.helper,
    this.errorText,
    this.prefixIcon,
    this.suffixIcon,
    this.suffixText,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.enabled = true,
    this.readOnly = false,
    this.obscureText = false,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.requiredMark = false,
    this.onTap,
    this.textAlign = TextAlign.start,
    this.style,
    this.labelActionText,
    this.onLabelAction,
  });

  final TextEditingController? controller;
  final String? initialValue;
  final String? label;
  final String? hint;
  final String? helper;
  final String? errorText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final String? suffixText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool enabled;
  final bool readOnly;
  final bool obscureText;
  final bool autofocus;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;

  /// Appends " *" to the label.
  final bool requiredMark;
  final VoidCallback? onTap;
  final TextAlign textAlign;

  /// Value style (defaults to 16/22 ink; number fields use the counter
  /// voice).
  final TextStyle? style;

  /// Right-aligned link in the label row ("Şifremi unuttum"): ink 600 with
  /// an underline, never orange.
  final String? labelActionText;
  final VoidCallback? onLabelAction;

  /// Sayısal ve telefon klavyesi (iOS'ta Return tuşu yok → "Bitti" çubuğu).
  bool get _numericKeyboard {
    final i = keyboardType?.index;
    return i == TextInputType.number.index || i == TextInputType.phone.index;
  }

  /// The v2 field decoration (border, fill, paddings, hint, helper, error
  /// line) for a value of [lineHeight] logical px (22 for text, 28 for the
  /// counter voice). Use it for custom fields that must look like
  /// [AknTextField].
  static InputDecoration decoration(
    BuildContext context, {
    String? hint,
    String? helper,
    String? errorText,
    IconData? prefixIcon,
    Widget? suffixIcon,
    String? suffixText,
    bool enabled = true,
    double lineHeight = 22,
  }) {
    final c = context.akn;
    final t = context.aknText;
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: AknRadius.input,
      borderSide: BorderSide(color: color, width: width),
    );
    final vertical = ((52 - lineHeight) / 2).clamp(4.0, 24.0);
    return InputDecoration(
      filled: true,
      fillColor: enabled ? c.surface : c.surfaceAlt,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      // The decorator adds 4 px before the value: 12 + 4 = the 16 px inset.
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: vertical),
      border: border(c.lineStrong, 1),
      enabledBorder: border(c.lineStrong, 1),
      disabledBorder: border(c.line, 1),
      focusedBorder: border(c.brand, 2),
      errorBorder: border(c.danger.fg, 2),
      focusedErrorBorder: border(c.danger.fg, 2),
      hintText: hint,
      hintStyle: t.body.copyWith(
        fontSize: 16,
        height: 22 / 16,
        color: enabled ? c.dim : c.faint,
      ),
      hintMaxLines: 2,
      helperText: helper,
      helperStyle: t.label.copyWith(fontWeight: FontWeight.w400, color: c.dim),
      helperMaxLines: 3,
      error: errorText == null ? null : AknFieldError(errorText),
      errorMaxLines: 3,
      prefixIcon: prefixIcon == null
          ? null
          : Icon(prefixIcon, size: 20, color: enabled ? c.dim : c.faint),
      suffixIcon: suffixIcon,
      suffixIconColor: c.dim,
      prefixIconColor: c.dim,
      suffixText: suffixText,
      suffixStyle: t.body.copyWith(
        fontSize: 16,
        height: 22 / 16,
        fontWeight: FontWeight.w600,
        color: enabled ? c.dim : c.faint,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final doneBar = _numericKeyboard && KeyboardDoneAccessory.isShown;
    final valueStyle =
        style ??
        t.body.copyWith(
          fontSize: 16,
          height: 22 / 16,
          color: enabled ? c.ink : c.faint,
        );
    final lineHeight =
        (valueStyle.fontSize ?? 16) * (valueStyle.height ?? 1.375);
    final labelText = label == null
        ? null
        : (requiredMark ? '$label *' : label);
    Widget field = TextFormField(
      controller: controller,
      initialValue: controller == null ? initialValue : null,
      focusNode: focusNode,
      // iOS'ta klavyenin üstündeki "Bitti" çubuğu: alan klavyeye kaydırılırken çubuğun da üstünde
      // kalır (yazılan sayı çubuğun altında kalmaz).
      scrollPadding: doneBar
          ? const EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + KeyboardDoneAccessory.barHeight,
            )
          : const EdgeInsets.all(20),
      enabled: enabled,
      readOnly: readOnly,
      obscureText: obscureText,
      autofocus: autofocus,
      maxLines: obscureText ? 1 : maxLines,
      minLines: minLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      autofillHints: autofillHints,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      onTap: onTap,
      // Dışarı dokununca klavye kapanır (spec C.7).
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      textAlign: textAlign,
      style: valueStyle,
      cursorColor: c.brand,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      // No "12/50" counter under the field.
      buildCounter:
          (context, {required currentLength, required isFocused, maxLength}) =>
              null,
      errorBuilder: (context, error) => AknFieldError(error),
      decoration: decoration(
        context,
        hint: hint,
        helper: helper,
        errorText: errorText,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        suffixText: suffixText,
        enabled: enabled,
        lineHeight: lineHeight,
      ),
    );
    if (_numericKeyboard) field = KeyboardDoneAccessory(child: field);
    if (labelText == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AknFieldLabel(
          text: labelText,
          enabled: enabled,
          actionText: labelActionText,
          onAction: onLabelAction,
        ),
        SizedBox(
          height: labelActionText != null && onLabelAction != null ? 0 : 6,
        ),
        // The visible label is excluded from semantics; the field carries it
        // as its name (one node: "E-posta, metin alanı").
        Semantics(label: labelText, child: field),
      ],
    );
  }
}

/// The label row above a field (§6.10): 13/18 500 ink, optional
/// right-aligned link ("Şifremi unuttum", ink 600 + underline). The text is
/// excluded from semantics; give the field itself the label.
class AknFieldLabel extends StatelessWidget {
  const AknFieldLabel({
    super.key,
    required this.text,
    this.enabled = true,
    this.actionText,
    this.onAction,
  });

  final String text;
  final bool enabled;
  final String? actionText;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final label = ExcludeSemantics(
      child: Text(
        text,
        style: t.label.copyWith(color: enabled ? c.ink : c.dim),
      ),
    );
    if (actionText == null || onAction == null) return label;
    // The link keeps its 48 dp target; label and link share one line in the
    // middle of it (the field follows the row directly, no extra gap).
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: label),
        const SizedBox(width: 12),
        AknInlineLink(
          label: actionText!,
          onTap: onAction!,
          style: t.label.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Inline text link (§6.5): ink 600 with an underline (offset 3) — never
/// orange, never blue — and a 48 dp touch target ("Şifremi unuttum",
/// "Tablo olarak göster", "Bayinizden davet isteyin").
class AknInlineLink extends StatelessWidget {
  const AknInlineLink({
    super.key,
    required this.label,
    required this.onTap,
    this.style,
  });

  final String label;
  final VoidCallback onTap;

  /// Defaults to 15/20 600 ink.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final base =
        style ?? t.body.copyWith(height: 20 / 15, fontWeight: FontWeight.w600);
    final color = style?.color ?? c.link;
    return Semantics(
      link: true,
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AknSpace.minTap),
          child: Align(
            alignment: Alignment.centerLeft,
            widthFactor: 1,
            child: Text(
              label,
              style: base.copyWith(
                color: color,
                decoration: TextDecoration.underline,
                decorationColor: color,
                decorationThickness: 1.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The error line under a field (§6.10): `error_rounded` 16 + 13/18 500 in
/// the danger colour, aligned with the field's left edge. The sentence says
/// what to do ("Teslimat noktası seçmeden sipariş gönderilemez.").
class AknFieldError extends StatelessWidget {
  const AknFieldError(this.message, {super.key, this.inset = 16});

  final String message;

  /// How far the decorator indents its subtext; the line is pulled back by
  /// this much so it starts at the field edge (0 when used outside a field).
  final double inset;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final line = Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.error_rounded, size: 16, color: c.danger.fg),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(message, style: t.label.copyWith(color: c.danger.fg)),
          ),
        ],
      ),
    );
    if (inset == 0) return line;
    return Transform.translate(offset: Offset(-inset, 0), child: line);
  }
}

/// iOS sayı / telefon klavyesinin üstünde "Bitti" çubuğu (spec D.7): bu klavyelerde Return tuşu
/// olmadığı için kullanıcı klavyeyi kapatamaz. İçindeki alan odaklanınca kök katmana eklenir, odak
/// gidince kalkar; Android'de (klavyede onay tuşu var) hiçbir şey eklemez.
class KeyboardDoneAccessory extends StatefulWidget {
  const KeyboardDoneAccessory({super.key, required this.child});

  final Widget child;

  /// "Bitti" düğmesinin metni.
  static const label = 'Bitti';

  /// Çubuğun yüksekliği (klavyenin hemen üstünde; alanlar bu kadar ek payla kaydırılır).
  static const double barHeight = 48;

  /// Çubuk bu platformda gösterilir mi (yalnızca iOS).
  static bool get isShown => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  State<KeyboardDoneAccessory> createState() => _KeyboardDoneAccessoryState();
}

class _KeyboardDoneAccessoryState extends State<KeyboardDoneAccessory> {
  OverlayEntry? _entry;

  void _onFocus(bool focused) {
    if (focused && KeyboardDoneAccessory.isShown) {
      if (_entry != null) return;
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) return;
      _entry = OverlayEntry(builder: (_) => const _DoneBar());
      overlay.insert(_entry!);
    } else {
      _remove();
    }
  }

  void _remove() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  @override
  void dispose() {
    _remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: _onFocus,
    child: widget.child,
  );
}

class _DoneBar extends StatelessWidget {
  const _DoneBar();

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (inset <= 0) return const SizedBox.shrink();
    final c = context.akn;
    return Positioned(
      left: 0,
      right: 0,
      bottom: inset,
      child: Material(
        color: c.surfaceRaised,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: c.line)),
          ),
          child: SizedBox(
            height: KeyboardDoneAccessory.barHeight,
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
                child: const Text(KeyboardDoneAccessory.label),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Live Turkish number formatting while typing: `12500,5` → `12.500,5`.
///
/// * Digits and one decimal comma; a typed "." becomes the comma (numeric
///   keypads differ), grouping dots are re-inserted automatically.
/// * Decimals are limited to [decimals]; leading zeros are dropped.
/// * Deleting a grouping dot deletes the digit before it.
/// * Pasted text is parsed as a whole (`12.500,75`, `12500.75`).
/// * The caret keeps its place among the digits.
class TrNumberInputFormatter extends TextInputFormatter {
  TrNumberInputFormatter({this.decimals = 2, this.maxIntegerDigits = 12});

  final int decimals;
  final int maxIntegerDigits;

  static final _digit = RegExp(r'\d');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var raw = newValue.text;
    if (raw.isEmpty) return newValue;
    final delta = raw.length - oldValue.text.length;
    if (delta > 1) {
      // Paste / autofill: read the whole value (Turkish or English
      // separators), keep at most [decimals] decimals without rounding.
      final split = _splitPasted(raw);
      if (split == null) return oldValue;
      var (ints, frac) = split;
      if (ints.length > maxIntegerDigits) return oldValue;
      ints = ints.replaceFirst(RegExp(r'^0+(?=\d)'), '');
      if (ints.isEmpty) ints = '0';
      if (frac != null && frac.length > decimals) {
        frac = frac.substring(0, decimals);
      }
      final text = frac == null || frac.isEmpty || decimals == 0
          ? _group(ints)
          : '${_group(ints)},$frac';
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
    var caret = newValue.selection.end.clamp(0, raw.length);
    if (delta == -1 &&
        caret > 0 &&
        caret < oldValue.text.length &&
        oldValue.text[caret] == '.') {
      // Backspace over a grouping dot removes the digit before it.
      raw = raw.substring(0, caret - 1) + raw.substring(caret);
      caret -= 1;
    }
    final typedDot = delta == 1 && caret > 0 && raw[caret - 1] == '.'
        ? caret - 1
        : -1;
    final ints = StringBuffer();
    final frac = StringBuffer();
    var seenComma = false;
    var sigBeforeCaret = 0;
    for (var i = 0; i < raw.length; i++) {
      final ch = raw[i];
      final isComma = ch == ',' || (ch == '.' && i == typedDot);
      if (isComma) {
        if (decimals == 0 || seenComma) continue;
        seenComma = true;
        if (i < caret) sigBeforeCaret++;
        continue;
      }
      if (!_digit.hasMatch(ch)) continue;
      if (seenComma) {
        if (frac.length >= decimals) continue;
        frac.write(ch);
      } else {
        if (ints.length >= maxIntegerDigits) continue;
        ints.write(ch);
      }
      if (i < caret) sigBeforeCaret++;
    }
    var intText = ints.toString().replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (intText.isEmpty && seenComma) intText = '0';
    final grouped = _group(intText);
    final text = seenComma ? '$grouped,$frac' : grouped;
    var offset = 0;
    var seen = 0;
    while (offset < text.length && seen < sigBeforeCaret) {
      if (text[offset] != '.') seen++;
      offset++;
    }
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  /// Integer and fraction digits of a pasted number (`TrNumber` rules: a
  /// comma is the decimal separator; with dots only, groups of exactly
  /// three digits after each dot mean thousands, otherwise the dot is the
  /// decimal point).
  static (String, String?)? _splitPasted(String raw) {
    var s = raw.replaceAll(RegExp(r'[\s\u00a0₺Lm³/]'), '');
    if (s.startsWith('-')) s = s.substring(1);
    String ints;
    String? frac;
    final comma = s.indexOf(',');
    if (comma >= 0) {
      ints = s.substring(0, comma).replaceAll('.', '');
      frac = s.substring(comma + 1);
    } else if (s.contains('.')) {
      final parts = s.split('.');
      final grouping = parts.skip(1).every((p) => p.length == 3);
      if (grouping) {
        ints = parts.join();
      } else {
        ints = parts.first;
        frac = parts.skip(1).join();
      }
    } else {
      ints = s;
    }
    if (!RegExp(r'^\d*$').hasMatch(ints)) return null;
    if (frac != null && !RegExp(r'^\d*$').hasMatch(frac)) return null;
    if (ints.isEmpty && (frac == null || frac.isEmpty)) return null;
    return (ints, frac);
  }

  static String _group(String digits) {
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) b.write('.');
      b.write(digits[i]);
    }
    return b.toString();
  }
}

/// Shared implementation of [MoneyField] and [LitersField].
class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.label,
    required this.unit,
    required this.decimals,
    this.controller,
    this.initialValue,
    this.onChanged,
    this.min,
    this.max,
    this.requiredValue = false,
    this.helper,
    this.validator,
    this.enabled = true,
    this.focusNode,
    this.textInputAction,
    this.autofocus = false,
    this.maxErrorUnit,
  });

  final String label;
  final String unit;
  final int decimals;
  final TextEditingController? controller;
  final num? initialValue;
  final ValueChanged<double?>? onChanged;
  final num? min;
  final num? max;
  final bool requiredValue;
  final String? helper;
  final FormFieldValidator<double?>? validator;
  final bool enabled;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final String Function(num)? maxErrorUnit;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  TextEditingController? _own;

  TextEditingController get _controller => widget.controller ?? _own!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      final v = widget.initialValue;
      _own = TextEditingController(
        text: v == null ? '' : Fmt.number(v, maxFraction: widget.decimals),
      );
    }
  }

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  String? _validate(String? text) {
    final v = TrNumber.parse(text);
    if (v == null) {
      if (widget.requiredValue) return 'Bu alan zorunludur.';
      return widget.validator?.call(null);
    }
    final min = widget.min;
    final max = widget.max;
    final fmt = widget.maxErrorUnit ?? (n) => Fmt.number(n, maxFraction: 3);
    if (min != null && v < min) return 'En az ${fmt(min)} girilebilir.';
    if (max != null && v > max) return 'En fazla ${fmt(max)} girilebilir.';
    return widget.validator?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return AknTextField(
      controller: _controller,
      label: widget.label,
      helper: widget.helper,
      enabled: widget.enabled,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      textInputAction: widget.textInputAction ?? TextInputAction.done,
      requiredMark: widget.requiredValue,
      keyboardType: TextInputType.numberWithOptions(
        decimal: widget.decimals > 0,
      ),
      inputFormatters: [TrNumberInputFormatter(decimals: widget.decimals)],
      suffixText: widget.unit,
      // The counter voice: MonaSansCondensed 700 24/28.
      style: t.number.copyWith(color: widget.enabled ? c.ink : c.faint),
      validator: _validate,
      onChanged: (s) => widget.onChanged?.call(TrNumber.parse(s)),
    );
  }
}

/// Money input: Turkish separators while typing (`1.234,56`), `₺` suffix,
/// numeric keypad, the value in the counter voice. [MoneyField.unitPrice]
/// takes up to 4 decimals in ₺/L.
class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    this.label = 'Tutar',
    this.controller,
    this.initialValue,
    this.onChanged,
    this.decimals = 2,
    this.unit = '₺',
    this.min,
    this.max,
    this.requiredValue = false,
    this.helper,
    this.validator,
    this.enabled = true,
    this.focusNode,
    this.textInputAction,
    this.autofocus = false,
  });

  const MoneyField.unitPrice({
    super.key,
    this.label = 'Birim fiyat',
    this.controller,
    this.initialValue,
    this.onChanged,
    this.min,
    this.max,
    this.requiredValue = false,
    this.helper,
    this.validator,
    this.enabled = true,
    this.focusNode,
    this.textInputAction,
    this.autofocus = false,
  }) : decimals = 4,
       unit = '₺/L';

  final String label;
  final TextEditingController? controller;
  final num? initialValue;

  /// Parsed value (null when empty or invalid).
  final ValueChanged<double?>? onChanged;
  final int decimals;
  final String unit;
  final num? min;
  final num? max;
  final bool requiredValue;
  final String? helper;
  final FormFieldValidator<double?>? validator;
  final bool enabled;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final bool autofocus;

  /// Reads a value typed into a [MoneyField] / [LitersField].
  static double? parse(String? text) => TrNumber.parse(text);

  @override
  Widget build(BuildContext context) => _NumberField(
    label: label,
    unit: unit,
    decimals: decimals,
    controller: controller,
    initialValue: initialValue,
    onChanged: onChanged,
    min: min,
    max: max,
    requiredValue: requiredValue,
    helper: helper,
    validator: validator,
    enabled: enabled,
    focusNode: focusNode,
    textInputAction: textInputAction,
    autofocus: autofocus,
    maxErrorUnit: (n) =>
        '${Fmt.number(n, minFraction: 2, maxFraction: decimals)} $unit',
  );
}

/// Litre input: thousands separators (`12.500`), up to 3 decimals, `L`
/// suffix, numeric keypad, the value in the counter voice. With [max] (e.g.
/// planned litres) the helper reads "En fazla 12.500 L" and larger values
/// are rejected.
class LitersField extends StatelessWidget {
  const LitersField({
    super.key,
    this.label = 'Litre',
    this.controller,
    this.initialValue,
    this.onChanged,
    this.decimals = 3,
    this.min,
    this.max,
    this.requiredValue = false,
    this.helper,
    this.validator,
    this.enabled = true,
    this.focusNode,
    this.textInputAction,
    this.autofocus = false,
  });

  final String label;
  final TextEditingController? controller;
  final num? initialValue;
  final ValueChanged<double?>? onChanged;
  final int decimals;
  final num? min;
  final num? max;
  final bool requiredValue;
  final String? helper;
  final FormFieldValidator<double?>? validator;
  final bool enabled;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => _NumberField(
    label: label,
    unit: 'L',
    decimals: decimals,
    controller: controller,
    initialValue: initialValue,
    onChanged: onChanged,
    min: min,
    max: max,
    requiredValue: requiredValue,
    helper: helper ?? (max == null ? null : 'En fazla ${Fmt.liters(max)}'),
    validator: validator,
    enabled: enabled,
    focusNode: focusNode,
    textInputAction: textInputAction,
    autofocus: autofocus,
    maxErrorUnit: Fmt.liters,
  );
}

/// Date field ("22 Ekim Perşembe", Türkiye calendar) in the field look, with
/// the label above; opens the themed date picker. "Bugün / Yarın" quick
/// picks sit under it as chips. Values are Türkiye-midnight instants
/// (`TrTime.fromWall`).
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Tarih',
    this.firstDate,
    this.lastDate,
    this.quickPicks = true,
    this.helper,
    this.errorText,
    this.enabled = true,
    this.requiredMark = false,
    this.hint = 'Tarih seçin',
  });

  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final String label;

  /// Defaults to today.
  final DateTime? firstDate;

  /// Defaults to one year ahead.
  final DateTime? lastDate;
  final bool quickPicks;
  final String? helper;
  final String? errorText;
  final bool enabled;
  final bool requiredMark;

  /// Shown while no date is picked.
  final String hint;

  static DateTime _localDay(DateTime instant) {
    final w = TrTime.wall(instant);
    return DateTime(w.year, w.month, w.day);
  }

  /// "22 Ekim Perşembe" (the year is added when it is not this year).
  static String display(DateTime instant) {
    final w = TrTime.wall(instant);
    final thisYear = TrTime.wall(TrTime.now()).year;
    final month = Fmt.monthNames[w.month - 1];
    final year = w.year == thisYear ? '' : ' ${w.year}';
    return '${w.day} $month$year ${Fmt.weekday(instant)}';
  }

  Future<void> _pick(BuildContext context) async {
    final today = TrTime.todayStart();
    final first = _localDay(firstDate ?? today);
    final last = _localDay(lastDate ?? today.add(const Duration(days: 366)));
    var initial = _localDay(value ?? firstDate ?? today);
    if (initial.isBefore(first)) initial = first;
    if (initial.isAfter(last)) initial = last;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: label,
      cancelText: 'Vazgeç',
      confirmText: 'Seç',
      fieldLabelText: label,
      fieldHintText: 'gg.aa.yyyy',
      errorFormatText: 'Tarihi gg.aa.yyyy biçiminde girin.',
      errorInvalidText: 'Bu tarih seçilebilecek aralığın dışında.',
    );
    if (picked != null) {
      AknHaptics.selection();
      onChanged(TrTime.fromWall(picked.year, picked.month, picked.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final today = TrTime.todayStart();
    final tomorrow = TrTime.addDays(today, 1);
    final v = value;
    final labelText = requiredMark ? '$label *' : label;
    bool isDay(DateTime d) => v != null && TrTime.isSameDay(v, d);
    bool allowed(DateTime d) {
      final f = firstDate;
      final l = lastDate;
      if (f != null && TrTime.dayDiff(f, d) < 0) return false;
      if (l != null && TrTime.dayDiff(d, l) < 0) return false;
      return true;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AknFieldLabel(text: labelText, enabled: enabled),
        const SizedBox(height: 6),
        Semantics(
          button: true,
          enabled: enabled,
          label: '$labelText: ${v == null ? 'seçilmedi' : display(v)}',
          excludeSemantics: true,
          onTap: enabled ? () => _pick(context) : null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: enabled ? () => _pick(context) : null,
            child: InputDecorator(
              isEmpty: v == null,
              decoration: AknTextField.decoration(
                context,
                hint: hint,
                helper: helper,
                errorText: errorText,
                enabled: enabled,
                suffixIcon: Icon(
                  Icons.calendar_month_outlined,
                  size: 20,
                  color: enabled ? c.dim : c.faint,
                ),
              ),
              child: Text(
                v == null ? '' : display(v),
                style: t.body.copyWith(
                  fontSize: 16,
                  height: 22 / 16,
                  color: enabled ? c.ink : c.faint,
                ),
              ),
            ),
          ),
        ),
        if (quickPicks && enabled)
          Wrap(
            spacing: 8,
            children: [
              for (final (d, l) in [(today, 'Bugün'), (tomorrow, 'Yarın')])
                if (allowed(d))
                  AknChip(
                    label: l,
                    selected: isDay(d),
                    onTap: () => onChanged(d),
                  ),
            ],
          ),
      ],
    );
  }
}

/// Search well (§6.10): Beton, 44 high, r12, `search_rounded` 20 dim and a
/// dim placeholder; on focus it turns white with a 2 px orange border
/// (orange marks never sit on Beton). [onChanged] is debounced (300 ms); a
/// clear button appears with text.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    this.hint = 'Ara',
    this.onChanged,
    this.onSubmitted,
    this.controller,
    this.debounce = const Duration(milliseconds: 300),
    this.autofocus = false,
    this.trailing,
    this.focusNode,
  });

  final String hint;

  /// Debounced query.
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextEditingController? controller;
  final Duration debounce;
  final bool autofocus;

  /// E.g. a filter button.
  final Widget? trailing;
  final FocusNode? focusNode;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  late final Debouncer _debouncer = Debouncer(widget.debounce);
  FocusNode? _ownFocus;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChange);
    _focus.addListener(_onChange);
  }

  @override
  void didUpdateWidget(SearchField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_onChange);
      _focus.addListener(_onChange);
    }
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    _focus.removeListener(_onChange);
    if (widget.controller == null) _controller.dispose();
    _ownFocus?.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  void _changed(String s) {
    final cb = widget.onChanged;
    if (cb == null) return;
    _debouncer(() => cb(s.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final focused = _focus.hasFocus;
    final text = t.body.copyWith(height: 20 / 15, color: c.ink);
    OutlineInputBorder border(BorderSide side) =>
        OutlineInputBorder(borderRadius: AknRadius.input, borderSide: side);
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            autofocus: widget.autofocus,
            textInputAction: TextInputAction.search,
            onChanged: _changed,
            onSubmitted: (s) {
              _debouncer.cancel();
              widget.onChanged?.call(s.trim());
              widget.onSubmitted?.call(s.trim());
            },
            onTapOutside: (_) => _focus.unfocus(),
            style: text,
            cursorColor: c.brand,
            decoration: InputDecoration(
              hintText: widget.hint,
              hintStyle: text.copyWith(color: c.dim),
              isDense: true,
              filled: true,
              fillColor: focused ? c.surface : c.surfaceAlt,
              hoverColor: Colors.transparent,
              contentPadding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
              prefixIcon: Icon(Icons.search_rounded, color: c.dim, size: 20),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 44,
                minHeight: 44,
              ),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Temizle',
                      icon: Icon(Icons.close_rounded, color: c.dim, size: 20),
                      onPressed: () {
                        _controller.clear();
                        _debouncer.cancel();
                        widget.onChanged?.call('');
                      },
                    ),
              border: border(BorderSide.none),
              enabledBorder: border(BorderSide.none),
              focusedBorder: border(BorderSide(color: c.brand, width: 2)),
            ),
          ),
        ),
        if (widget.trailing != null) ...[
          const SizedBox(width: 8),
          widget.trailing!,
        ],
      ],
    );
  }
}

/// Turkish licence plate input: upper case, spaced as `34 ABC 123` once
/// valid, with a live [PlateBadge] preview.
class PlateField extends StatefulWidget {
  const PlateField({
    super.key,
    this.controller,
    this.initialValue,
    this.onChanged,
    this.label = 'Plaka',
    this.requiredValue = true,
    this.enabled = true,
    this.showPreview = true,
  });

  final TextEditingController? controller;
  final String? initialValue;

  /// Formatted plate (`34 ABC 123`) or the raw text while incomplete.
  final ValueChanged<String>? onChanged;
  final String label;
  final bool requiredValue;
  final bool enabled;
  final bool showPreview;

  @override
  State<PlateField> createState() => _PlateFieldState();
}

class _PlateFieldState extends State<PlateField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController(text: _initialText());

  String _initialText() {
    final v = widget.initialValue?.trim() ?? '';
    return Validators.plate(v) == null ? Fmt.plate(v) : v.asciiUpper;
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  bool get _valid => Validators.plate(_controller.text) == null;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AknTextField(
          controller: _controller,
          label: widget.label,
          hint: '34 ABC 123',
          enabled: widget.enabled,
          requiredMark: widget.requiredValue,
          textCapitalization: TextCapitalization.characters,
          keyboardType: TextInputType.visiblePassword,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[0-9A-Za-z ]')),
            const _UpperCaseFormatter(),
            LengthLimitingTextInputFormatter(11),
          ],
          validator: (s) => Validators.plate(s, required: widget.requiredValue),
          onChanged: (s) {
            setState(() {});
            widget.onChanged?.call(_valid ? Fmt.plate(s) : s.trim());
          },
          onSubmitted: (s) {
            if (_valid) {
              final f = Fmt.plate(s);
              _controller.value = TextEditingValue(
                text: f,
                selection: TextSelection.collapsed(offset: f.length),
              );
            }
          },
        ),
        if (widget.showPreview)
          AknAnimatedSize(
            child: _valid
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: PlateBadge(plate: Fmt.plate(_controller.text)),
                  )
                : const SizedBox(width: double.infinity),
          ),
      ],
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  const _UpperCaseFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.asciiUpper);
}

/// The "Göster / Gizle" control inside a password field (board, login):
/// `visibility_outlined` 20 + "Göster" 14/20 600 in ink, 16 px from the
/// field's right edge, a 48 dp target. Use it as `AknTextField.suffixIcon`
/// (or take [AknPasswordField], which wires it up).
class AknFieldRevealToggle extends StatelessWidget {
  const AknFieldRevealToggle({
    super.key,
    required this.revealed,
    required this.onToggle,
    this.showLabel = 'Göster',
    this.hideLabel = 'Gizle',
  });

  /// The value is visible (the control then offers "Gizle").
  final bool revealed;
  final VoidCallback onToggle;
  final String showLabel;
  final String hideLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final label = revealed ? hideLabel : showLabel;
    return Semantics(
      button: true,
      label: revealed ? 'Şifreyi gizle' : 'Şifreyi göster',
      excludeSemantics: true,
      onTap: onToggle,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AknSpace.minTap,
            minWidth: AknSpace.minTap,
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 8, end: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  revealed
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 20,
                  color: c.ink,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: t.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A password field (§6.10, board login): [AknTextField] with the
/// "Göster / Gizle" control on the right and an optional label link
/// ("Şifremi unuttum").
class AknPasswordField extends StatefulWidget {
  const AknPasswordField({
    super.key,
    this.controller,
    this.label = 'Şifre',
    this.hint,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.textInputAction,
    this.autofillHints = const [AutofillHints.password],
    this.validator,
    this.enabled = true,
    this.labelActionText,
    this.onLabelAction,
  });

  final TextEditingController? controller;
  final String label;
  final String? hint;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final FormFieldValidator<String>? validator;
  final bool enabled;
  final String? labelActionText;
  final VoidCallback? onLabelAction;

  @override
  State<AknPasswordField> createState() => _AknPasswordFieldState();
}

class _AknPasswordFieldState extends State<AknPasswordField> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return AknTextField(
      controller: w.controller,
      label: w.label,
      hint: w.hint,
      errorText: w.errorText,
      onChanged: w.onChanged,
      onSubmitted: w.onSubmitted,
      focusNode: w.focusNode,
      textInputAction: w.textInputAction,
      autofillHints: w.autofillHints,
      validator: w.validator,
      enabled: w.enabled,
      obscureText: !_revealed,
      keyboardType: TextInputType.visiblePassword,
      labelActionText: w.labelActionText,
      onLabelAction: w.onLabelAction,
      suffixIcon: AknFieldRevealToggle(
        revealed: _revealed,
        onToggle: () => setState(() => _revealed = !_revealed),
      ),
    );
  }
}

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
import 'plate_badge.dart';

/// Text field in the AkaryakıtNet style (floating label, 8 px radius, brand
/// focus ring, Turkish messages). A thin, typed wrapper over
/// [TextFormField]; use it inside a [Form] for `validator`.
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
  final TextStyle? style;

  /// Sayısal ve telefon klavyesi (iOS'ta Return tuşu yok → "Bitti" çubuğu).
  bool get _numericKeyboard {
    final i = keyboardType?.index;
    return i == TextInputType.number.index || i == TextInputType.phone.index;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final doneBar = _numericKeyboard && KeyboardDoneAccessory.isShown;
    final field = TextFormField(
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
      style: style ?? t.body.copyWith(fontSize: 16, color: c.ink),
      autovalidateMode: AutovalidateMode.onUserInteraction,
      decoration: InputDecoration(
        labelText: label == null ? null : (requiredMark ? '$label *' : label),
        hintText: hint,
        helperText: helper,
        errorText: errorText,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20),
        suffixIcon: suffixIcon,
        suffixText: suffixText,
        suffixStyle: t.bodyStrong.copyWith(color: c.dim),
        counterText: maxLength == null ? null : '',
      ),
    );
    return _numericKeyboard ? KeyboardDoneAccessory(child: field) : field;
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
      style: context.aknText.amount.copyWith(fontSize: 16),
      validator: _validate,
      onChanged: (s) => widget.onChanged?.call(TrNumber.parse(s)),
    );
  }
}

/// Money input: Turkish separators while typing (`1.234,56`), `₺` suffix,
/// numeric keypad. [MoneyField.unitPrice] takes up to 4 decimals in ₺/L.
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
/// suffix, numeric keypad. With [max] (e.g. planned litres) the helper reads
/// "En fazla 12.500 L" and larger values are rejected.
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

/// Date field (`dd.MM.yyyy`, Türkiye calendar) opening the themed date
/// picker, with "Bugün / Yarın" quick picks. Values are Türkiye-midnight
/// instants (`TrTime.fromWall`).
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

  static DateTime _localDay(DateTime instant) {
    final w = TrTime.wall(instant);
    return DateTime(w.year, w.month, w.day);
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
      errorFormatText: 'Geçerli bir tarih girin',
      errorInvalidText: 'Tarih aralık dışında',
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
    bool isDay(DateTime d) => v != null && TrTime.isSameDay(v, d);
    bool allowed(DateTime d) {
      final f = firstDate;
      final l = lastDate;
      if (f != null && TrTime.dayDiff(f, d) < 0) return false;
      if (l != null && TrTime.dayDiff(d, l) < 0) return false;
      return true;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          label: '$label: ${v == null ? 'seçilmedi' : Fmt.longDate(v)}',
          excludeSemantics: true,
          onTap: enabled ? () => _pick(context) : null,
          child: InkWell(
            onTap: enabled ? () => _pick(context) : null,
            borderRadius: AknRadius.input,
            child: InputDecorator(
              isEmpty: v == null,
              decoration: InputDecoration(
                labelText: requiredMark ? '$label *' : label,
                helperText: helper,
                errorText: errorText,
                enabled: enabled,
                suffixIcon: const Icon(Icons.calendar_month_rounded, size: 20),
              ),
              child: Text(
                v == null ? '' : '${Fmt.date(v)}  ·  ${Fmt.weekday(v)}',
                style: t.body.copyWith(fontSize: 16, color: c.ink),
              ),
            ),
          ),
        ),
        if (quickPicks && enabled) ...[
          const SizedBox(height: 2),
          Wrap(
            spacing: 8,
            children: [
              for (final (d, l) in [(today, 'Bugün'), (tomorrow, 'Yarın')])
                if (allowed(d))
                  _QuickChip(
                    label: l,
                    selected: isDay(d),
                    onTap: () {
                      AknHaptics.selection();
                      onChanged(d);
                    },
                  ),
            ],
          ),
        ],
      ],
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      // 48 dp touch target around the 36 dp chip.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AknSpace.minTap),
          child: Center(
            widthFactor: 1,
            child: InkWell(
              onTap: onTap,
              borderRadius: AknRadius.chip,
              child: AnimatedContainer(
                duration: AknMotion.of(context, AknMotion.fast),
                constraints: const BoxConstraints(minHeight: 36),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: selected ? c.brandSoft : c.surface,
                  borderRadius: AknRadius.chip,
                  border: Border.all(
                    color: selected ? c.brandLine : c.lineStrong,
                  ),
                ),
                child: Text(
                  label,
                  style: t.label.copyWith(
                    color: selected ? c.brandInk : c.text,
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

/// Pill search box with a debounced [onChanged] (300 ms) and a clear button.
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

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onText);
  }

  void _onText() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onText);
    if (widget.controller == null) _controller.dispose();
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
    final border = OutlineInputBorder(
      borderRadius: AknRadius.pillAll,
      borderSide: BorderSide(color: c.line),
    );
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            textInputAction: TextInputAction.search,
            onChanged: _changed,
            onSubmitted: (s) {
              _debouncer.cancel();
              widget.onChanged?.call(s.trim());
              widget.onSubmitted?.call(s.trim());
            },
            style: t.body.copyWith(fontSize: 16, color: c.ink),
            decoration: InputDecoration(
              hintText: widget.hint,
              isDense: true,
              filled: true,
              fillColor: c.isDark ? c.surfaceAlt : c.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              prefixIcon: Icon(Icons.search_rounded, color: c.dim, size: 22),
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
              border: border,
              enabledBorder: border,
              focusedBorder: border.copyWith(
                borderSide: BorderSide(color: c.brand, width: 1.6),
              ),
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
                    padding: const EdgeInsets.only(top: 10, left: 2),
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

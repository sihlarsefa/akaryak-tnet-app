import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../utils/debouncer.dart';
import '../../utils/format.dart';
import '../../utils/tr_number.dart';
import '../../utils/tr_time.dart';
import '../../utils/turkish_text.dart';
import '../../utils/validators.dart';
import '../driver_mode.dart';
import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';
import 'filters.dart';
import 'plate_badge.dart';

/// Text field in the v3 style (§4 Inputs): the label sits **above** the
/// field (`label` 13/18 600 ink, 8 px gap) with an optional right-aligned
/// link in the label row ("Şifremi unuttum"); the field is 52 px, white,
/// r14 with a 1.5 px control border, value 16/22 ink, hint dim; the helper
/// and the error line sit on the field's left edge under it. Driver mode:
/// 64 px with 17/24 text.
///
/// Motion: focus blooms the border into 2 px orange with a soft 4 px glow
/// around it (~170 ms) and the caret is orange; an error turns the border red
/// and **shakes** the field (±6 px, three times) while the message fades in
/// under it with a popping `warningCircle` (a sentence that says what to
/// do); disabled = `surfaceAlt` fill, hairline border, faint text.
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

  /// Value style (defaults to 16/22 ink; number fields use the tabular
  /// `number` figures).
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

  /// The value style: 16/22 (driver mode: `body` 17/24), uncoloured.
  static TextStyle _valueStyle(BuildContext context) {
    final t = context.aknText;
    return context.isDriverMode
        ? t.body
        : t.body.copyWith(fontSize: 16, height: 22 / 16);
  }

  /// The v3 field decoration (borders with the focus glow, fill, paddings,
  /// hint, helper, error line) for a value of [lineHeight] logical px (22
  /// for text, 28 for the number figures): 52 px high, 64 in driver mode.
  /// Use it for custom fields that must look like [AknTextField].
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
    final borders = AknTheme.inputBorders(c, snap: AknMotion.reduced(context));
    final height = context.driverMode?.fieldHeight ?? 52;
    final vertical = ((height - lineHeight) / 2).clamp(4.0, 24.0);
    final value = _valueStyle(context);
    Color iconColor(Set<WidgetState> s) => !enabled
        ? c.faint
        : s.contains(WidgetState.focused)
        ? c.ink
        : c.dim;
    return InputDecoration(
      filled: true,
      fillColor: enabled ? c.surface : c.surfaceAlt,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      floatingLabelBehavior: FloatingLabelBehavior.never,
      // The decorator adds 4 px before the value: 12 + 4 = the 16 px inset.
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: vertical),
      border: borders.rest,
      enabledBorder: borders.rest,
      disabledBorder: borders.disabled,
      focusedBorder: borders.focused,
      errorBorder: borders.error,
      focusedErrorBorder: borders.focusedError,
      hintText: hint,
      hintStyle: value.copyWith(color: enabled ? c.dim : c.faint),
      hintMaxLines: 2,
      // The helper sits on the field's left edge, like the label above and
      // the error line that replaces it.
      helper: helper == null ? null : _FieldHelper(helper, enabled: enabled),
      helperStyle: t.label.copyWith(fontWeight: FontWeight.w500, color: c.dim),
      helperMaxLines: 3,
      error: errorText == null ? null : AknFieldError(errorText),
      errorMaxLines: 3,
      prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20),
      suffixIcon: suffixIcon,
      suffixIconColor: WidgetStateColor.resolveWith(iconColor),
      prefixIconColor: WidgetStateColor.resolveWith(iconColor),
      suffixText: suffixText,
      suffixStyle: value.copyWith(
        fontWeight: FontWeight.w600,
        color: enabled ? c.dim : c.faint,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final doneBar = _numericKeyboard && KeyboardDoneAccessory.isShown;
    final valueStyle =
        style ??
        _valueStyle(context).copyWith(color: enabled ? c.ink : c.faint);
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
      cursorWidth: 2,
      cursorRadius: const Radius.circular(2),
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
    // The field (not its label) shakes when an error appears.
    field = _FieldShake(child: field);
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
          height: labelActionText != null && onLabelAction != null ? 0 : 8,
        ),
        // The visible label is excluded from semantics; the field carries it
        // as its name (one node: "E-posta, metin alanı").
        Semantics(label: labelText, child: field),
      ],
    );
  }
}

/// The label row above a field (§4 Inputs): `label` 13/18 600 ink (dim when
/// disabled), optional right-aligned link ("Şifremi unuttum", ink 600 +
/// underline). The text is excluded from semantics; give the field itself
/// the label.
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

/// Inline text link (§4): ink 600 with an underline (offset 3) — never
/// orange, never blue — a 48 dp touch target and a small press scale
/// ("Şifremi unuttum", "Tablo olarak göster", "Bayinizden davet isteyin").
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
            child: PressScale(
              scale: 0.95,
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
      ),
    );
  }
}

/// The error line under a field (§4 Inputs): a `warningCircle` 16 that pops
/// in + 13/18 600 in the danger colour, aligned with the field's left edge.
/// The sentence says what to do ("Teslimat noktası seçmeden sipariş
/// gönderilemez."). Inside an [AknTextField] (or [DateField]) a new error
/// also shakes the field (±6 px, three times); an error that is there from
/// the first frame does not.
class AknFieldError extends StatefulWidget {
  const AknFieldError(this.message, {super.key, this.inset = 16});

  final String message;

  /// How far the decorator indents its subtext; the line is pulled back by
  /// this much so it starts at the field edge (0 when used outside a field).
  final double inset;

  @override
  State<AknFieldError> createState() => _AknFieldErrorState();
}

class _AknFieldErrorState extends State<AknFieldError>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final scope = _FieldShake.maybeOf(context);
    // An error shown with the field's first frame neither pops nor shakes.
    if (scope != null && !scope.settled || AknMotion.reduced(context)) {
      _pop.value = 1;
    } else {
      _announce();
    }
  }

  @override
  void didUpdateWidget(AknFieldError old) {
    super.didUpdateWidget(old);
    if (old.message != widget.message && !AknMotion.reduced(context)) {
      _announce();
    }
  }

  void _announce() {
    _pop.forward(from: 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _FieldShake.maybeOf(context)?.shake();
    });
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final style = context.aknText.label.copyWith(color: c.danger.fg);
    // The icon grows with the text (16 → 22) and sits on the first line.
    final scaler = MediaQuery.textScalerOf(context);
    final lineHeight = scaler.scale(
      (style.fontSize ?? 13) * (style.height ?? 18 / 13),
    );
    final iconSize = scaler.scale(16).clamp(16.0, 22.0);
    final line = Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(
              top: math.max(0, (lineHeight - iconSize) / 2),
            ),
            child: ScaleTransition(
              scale: _pop.drive(
                Tween<double>(
                  begin: 0.3,
                  end: 1,
                ).chain(CurveTween(curve: AknMotion.pop)),
              ),
              child: Icon(
                PhosphorIconsFill.warningCircle,
                size: iconSize,
                color: c.danger.fg,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text(widget.message, style: style)),
        ],
      ),
    );
    return _OnFieldEdge(inset: widget.inset, child: line);
  }
}

/// Pulls a line under a field back by [inset] (the decorator's subtext
/// indent) so it starts on the field's edge.
class _OnFieldEdge extends StatelessWidget {
  const _OnFieldEdge({required this.inset, required this.child});

  final double inset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (inset == 0) return child;
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    return Transform.translate(
      offset: Offset(rtl ? inset : -inset, 0),
      child: child,
    );
  }
}

/// The helper line under a field (§4 Inputs): 13/18 500 dim (faint when
/// disabled), up to three lines, on the field's left edge — where the label
/// starts above and the error line takes its place.
class _FieldHelper extends StatelessWidget {
  const _FieldHelper(this.text, {required this.enabled});

  final String text;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return _OnFieldEdge(
      inset: 16,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          text,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: context.aknText.label.copyWith(
            fontWeight: FontWeight.w500,
            color: enabled ? c.dim : c.faint,
          ),
        ),
      ),
    );
  }
}

/// Shakes its field (±6 px, three times, 420 ms) when an [AknFieldError]
/// appears or changes inside it (v3 §5: errors shake). Never on the field's
/// first frame and never under reduce motion. The tree shape never changes,
/// so the field keeps its state.
class _FieldShake extends StatefulWidget {
  const _FieldShake({required this.child});

  final Widget child;

  static _FieldShakeState? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_ShakeScope>()?.state;

  @override
  State<_FieldShake> createState() => _FieldShakeState();
}

class _FieldShakeState extends State<_FieldShake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  /// False during the first frame: errors present from the start are calm.
  bool settled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => settled = true);
  }

  void shake() {
    if (!mounted || AknMotion.reduced(context)) return;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: _ShakeScope(state: this, child: widget.child),
      builder: (context, child) {
        final t = _c.value;
        final dx = t == 0 || t == 1
            ? 0.0
            : math.sin(t * math.pi * 6) * 6 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}

class _ShakeScope extends InheritedWidget {
  const _ShakeScope({required this.state, required super.child});

  final _FieldShakeState state;

  @override
  bool updateShouldNotify(_ShakeScope old) => old.state != state;
}

/// iOS sayı / telefon klavyesinin üstünde "Bitti" çubuğu (spec D.7): bu klavyelerde Return tuşu
/// olmadığı için kullanıcı klavyeyi kapatamaz. İçindeki alan odaklanınca kök katmana eklenir, odak
/// gidince kalkar; Android'de (klavyede onay tuşu var) hiçbir şey eklemez. v3: buzlu cam çubuk
/// (yükseltilmiş yüzey %86 + bulanıklık), turuncu "Bitti"; çubuk kayarak belirir.
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
    final t = context.aknText;
    return Positioned(
      left: 0,
      right: 0,
      bottom: inset,
      // Çubuk klavyeyle birlikte yukarı kayarak belirir.
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: AknMotion.of(context, AknMotion.base),
        curve: AknMotion.emphasizedCurve,
        builder: (context, v, child) => Opacity(
          opacity: v.clamp(0.0, 1.0),
          alwaysIncludeSemantics: true,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - v)),
            child: child,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surfaceRaised.withValues(alpha: 0.86),
                  border: Border(
                    top: BorderSide(color: c.line.withValues(alpha: 0.7)),
                  ),
                ),
                child: SizedBox(
                  height: KeyboardDoneAccessory.barHeight,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: c.brandInk,
                          textStyle: t.button,
                        ),
                        onPressed: () =>
                            FocusManager.instance.primaryFocus?.unfocus(),
                        child: const Text(KeyboardDoneAccessory.label),
                      ),
                    ),
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
    var s = raw.replaceAll(RegExp(r'[\s ₺Lm³/]'), '');
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
    // The figures (v3 §1): Archivo 800 with tabular digits, so a
    // value never changes width as it is typed — 22/28 (driver mode 26/32).
    // They are large already, so they stop growing at 1.5× text scale; the
    // label, helper and error keep scaling.
    final driver = context.isDriverMode;
    final base = driver ? 26.0 : 22.0;
    final line = driver ? 32.0 : 28.0;
    final shown = MediaQuery.textScalerOf(context).scale(base);
    final size = shown > base * 1.5 ? base * base * 1.5 / shown : base;
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
      style: t.number.copyWith(
        fontSize: size,
        height: line / base,
        color: widget.enabled ? c.ink : c.faint,
      ),
      validator: _validate,
      onChanged: (s) => widget.onChanged?.call(TrNumber.parse(s)),
    );
  }
}

/// Money input: Turkish separators while typing (`1.234,56`), `₺` suffix,
/// numeric keypad, the value in tabular figures. [MoneyField.unitPrice]
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
/// suffix, numeric keypad, the value in tabular figures. With [max] (e.g.
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
/// the label above; a press scales it a touch and opens the themed (orange)
/// date picker; a new date slides in over the old one. "Bugün / Yarın" quick
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
    AknHaptics.light();
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
    final c = context.akn;
    final today = TrTime.todayStart();
    final tomorrow = TrTime.addDays(today, 1);
    final v = value;
    final labelText = requiredMark ? '$label *' : label;
    final shown = v == null ? '' : display(v);
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
        const SizedBox(height: 8),
        Semantics(
          button: true,
          enabled: enabled,
          label: '$labelText: ${v == null ? 'seçilmedi' : display(v)}',
          excludeSemantics: true,
          onTap: enabled ? () => _pick(context) : null,
          child: _FieldShake(
            child: PressScale(
              enabled: enabled,
              scale: 0.98,
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
                      PhosphorIconsRegular.calendarDots,
                      size: 20,
                      color: enabled ? c.ink : c.faint,
                    ),
                  ),
                  child: AnimatedSwitcher(
                    duration: AknMotion.of(context, AknMotion.base),
                    layoutBuilder: (current, previous) => Stack(
                      alignment: AlignmentDirectional.centerStart,
                      children: [...previous, ?current],
                    ),
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                        position: a.drive(
                          Tween<Offset>(
                            begin: const Offset(0, 0.35),
                            end: Offset.zero,
                          ).chain(CurveTween(curve: AknMotion.emphasizedCurve)),
                        ),
                        child: child,
                      ),
                    ),
                    child: Text(
                      shown,
                      key: ValueKey(shown),
                      style: AknTextField._valueStyle(context).copyWith(
                        fontWeight: FontWeight.w500,
                        color: enabled ? c.ink : c.faint,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (quickPicks && enabled)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Wrap(
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
          ),
      ],
    );
  }
}

/// Search well (§4 Inputs): a `surfaceAlt` pill, 48 high, a
/// `magnifyingGlass` 20 and a dim placeholder. On focus it blooms white with
/// a 2 px orange border and a soft orange glow (~180 ms) and the glass turns
/// ink; the clear button pops in once there is text. [onChanged] is
/// debounced (300 ms).
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

class _SearchFieldState extends State<SearchField>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  late final Debouncer _debouncer = Debouncer(widget.debounce);
  late final AnimationController _focusT = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );
  FocusNode? _ownFocus;
  bool _hasText = false;

  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _hasText = _controller.text.isNotEmpty;
    _focusT.value = _focus.hasFocus ? 1 : 0;
    _controller.addListener(_onText);
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(SearchField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_onFocus);
      _focus.addListener(_onFocus);
      _onFocus();
    }
  }

  void _onText() {
    final has = _controller.text.isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  void _onFocus() {
    if (!mounted) return;
    AknMotion.animateTo(context, _focusT, _focus.hasFocus ? 1 : 0);
  }

  @override
  void dispose() {
    _controller.removeListener(_onText);
    _focus.removeListener(_onFocus);
    if (widget.controller == null) _controller.dispose();
    _ownFocus?.dispose();
    _debouncer.dispose();
    _focusT.dispose();
    super.dispose();
  }

  void _changed(String s) {
    final cb = widget.onChanged;
    if (cb == null) return;
    _debouncer(() => cb(s.trim()));
  }

  void _clear() {
    AknHaptics.selection();
    _controller.clear();
    _debouncer.cancel();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final text = t.body.copyWith(height: 20 / 15, color: c.ink);
    final glow = AknTheme.focusGlow(c);
    final clear = AnimatedSwitcher(
      duration: AknMotion.of(context, AknMotion.base),
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        alwaysIncludeSemantics: true,
        child: ScaleTransition(
          scale: a.drive(
            Tween<double>(
              begin: 0.3,
              end: 1,
            ).chain(CurveTween(curve: AknMotion.pop)),
          ),
          child: child,
        ),
      ),
      child: _hasText
          ? IconButton(
              key: const ValueKey('clear'),
              tooltip: 'Temizle',
              icon: Icon(PhosphorIconsRegular.x, color: c.dim, size: 20),
              onPressed: _clear,
            )
          : const SizedBox(key: ValueKey('rest'), width: 16),
    );
    final well = AnimatedBuilder(
      animation: _focusT,
      builder: (context, child) {
        final f = _focusT.value;
        return DecoratedBox(
          decoration: ShapeDecoration(
            color: Color.lerp(c.surfaceAlt, c.surface, f),
            shape: StadiumBorder(
              side: BorderSide(color: c.brand.withValues(alpha: f), width: 2),
            ),
            shadows: [
              BoxShadow(
                color: glow.withValues(alpha: glow.a * f),
                spreadRadius: 4 * f,
              ),
            ],
          ),
          child: IconTheme.merge(
            data: IconThemeData(color: Color.lerp(c.dim, c.ink, f)),
            child: child!,
          ),
        );
      },
      child: Row(
        children: [
          const SizedBox(
            width: 46,
            child: Icon(PhosphorIconsRegular.magnifyingGlass, size: 20),
          ),
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
              cursorWidth: 2,
              cursorRadius: const Radius.circular(2),
              decoration: InputDecoration(
                hintText: widget.hint,
                hintStyle: text.copyWith(color: c.dim),
                hintMaxLines: 1,
                isDense: true,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
              ),
            ),
          ),
          AknAnimatedSize(
            duration: AknMotion.fast,
            alignment: AlignmentDirectional.centerStart,
            child: clear,
          ),
        ],
      ),
    );
    return Row(
      children: [
        Expanded(
          // A tap on the glass (or the well's edge) focuses the field. Screen
          // readers use the text field's own node (labelled by the hint).
          child: GestureDetector(
            onTap: _focus.requestFocus,
            excludeFromSemantics: true,
            child: well,
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
/// valid, with a live [PlateBadge] preview that pops in under the field.
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
    final valid = _valid;
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
            alignment: Alignment.topLeft,
            child: AnimatedSwitcher(
              duration: AknMotion.of(context, AknMotion.base),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topLeft,
                children: [...previous, ?current],
              ),
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                alwaysIncludeSemantics: true,
                child: ScaleTransition(
                  alignment: Alignment.centerLeft,
                  scale: a.drive(
                    Tween<double>(
                      begin: 0.8,
                      end: 1,
                    ).chain(CurveTween(curve: AknMotion.pop)),
                  ),
                  child: child,
                ),
              ),
              child: valid
                  ? Padding(
                      key: const ValueKey('plate'),
                      padding: const EdgeInsets.only(top: 10),
                      child: PlateBadge(plate: Fmt.plate(_controller.text)),
                    )
                  : const SizedBox(
                      key: ValueKey('none'),
                      width: double.infinity,
                    ),
            ),
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
/// an `eye` 20 + "Göster" 14/20 600 in ink, 16 px from the field's right
/// edge, a 48 dp target. Toggling turns the eye into `eyeSlash` with a small
/// spin-and-pop (the word cross-fades); a press scales it a touch. Use it as
/// `AknTextField.suffixIcon` (or take [AknPasswordField], which wires it up).
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
    final swap = AknMotion.of(context, AknMotion.iconSwap);
    return Semantics(
      button: true,
      label: revealed ? 'Şifreyi gizle' : 'Şifreyi göster',
      excludeSemantics: true,
      onTap: onToggle,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          AknHaptics.selection();
          onToggle();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AknSpace.minTap,
            minWidth: AknSpace.minTap,
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 8, end: 16),
            child: PressScale(
              scale: 0.94,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedSwitcher(
                    duration: swap,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: RotationTransition(
                        turns: a.drive(Tween<double>(begin: -0.12, end: 0)),
                        child: ScaleTransition(
                          scale: a.drive(
                            Tween<double>(
                              begin: 0.5,
                              end: 1,
                            ).chain(CurveTween(curve: AknMotion.pop)),
                          ),
                          child: child,
                        ),
                      ),
                    ),
                    child: Icon(
                      revealed
                          ? PhosphorIconsRegular.eyeSlash
                          : PhosphorIconsRegular.eye,
                      key: ValueKey(revealed),
                      size: 20,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(width: 6),
                  AknAnimatedSize(
                    duration: swap,
                    alignment: AlignmentDirectional.centerStart,
                    child: AnimatedSwitcher(
                      duration: swap,
                      layoutBuilder: (current, previous) => Stack(
                        alignment: AlignmentDirectional.centerStart,
                        children: [...previous, ?current],
                      ),
                      child: Text(
                        label,
                        key: ValueKey(label),
                        style: t.bodySmall.copyWith(
                          fontWeight: FontWeight.w600,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A password field (§4 Inputs, board login): [AknTextField] with the
/// "Göster / Gizle" control on the right and an optional label link
/// ("Şifremi unuttum").
class AknPasswordField extends StatefulWidget {
  const AknPasswordField({
    super.key,
    this.controller,
    this.label = 'Şifre',
    this.hint,
    this.helper,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.textInputAction,
    this.autofillHints = const [AutofillHints.password],
    this.validator,
    this.enabled = true,
    this.requiredMark = false,
    this.labelActionText,
    this.onLabelAction,
  });

  final TextEditingController? controller;
  final String label;
  final String? hint;

  /// Line under the field (e.g. the password rules).
  final String? helper;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final FormFieldValidator<String>? validator;
  final bool enabled;

  /// Appends " *" to the label.
  final bool requiredMark;
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
      helper: w.helper,
      errorText: w.errorText,
      onChanged: w.onChanged,
      onSubmitted: w.onSubmitted,
      focusNode: w.focusNode,
      textInputAction: w.textInputAction,
      autofillHints: w.autofillHints,
      validator: w.validator,
      enabled: w.enabled,
      requiredMark: w.requiredMark,
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

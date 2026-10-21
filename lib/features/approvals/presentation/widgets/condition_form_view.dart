import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/tr_number.dart';
import '../../../../core/utils/tr_time.dart';
import '../../data/approval_models.dart';
import '../../data/condition_values.dart';

/// Koşullu onay formu: alanlar sunucunun `conditionForm` tanımından çizilir (türe göre değişir).
/// Alanlar boş başlar ("değişmez"); kartta / talepteki değer ve öneri alanın altında yazar, öneri
/// tek dokunuşla uygulanır. Değerler gönderilecek biçimde ([ConditionValues]) tutulur.
class ConditionFormView extends StatefulWidget {
  const ConditionFormView({
    super.key,
    required this.form,
    required this.values,
    required this.onChanged,
    this.errors = const {},
  });

  final ConditionForm form;
  final ConditionValues values;
  final void Function(String key, String? value) onChanged;

  /// Alan anahtarı → hata (`termDays` ya da sunucudan `conditions.termDays`).
  final Map<String, String> errors;

  @override
  State<ConditionFormView> createState() => _ConditionFormViewState();
}

class _ConditionFormViewState extends State<ConditionFormView> {
  final Map<String, TextEditingController> _controllers = {};

  TextEditingController _controller(ConditionField f) =>
      _controllers.putIfAbsent(f.key, () {
        final v = widget.values[f.key];
        String text = '';
        if (v != null && v.isNotEmpty) {
          final n = double.tryParse(v);
          text = n == null
              ? v
              : (f.type == ConditionFieldTypes.integer
                    ? '${n.round()}'
                    : Fmt.number(n, maxFraction: 2));
        }
        return TextEditingController(text: text);
      });

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? _error(String key) =>
      widget.errors[key] ?? widget.errors['conditions.$key'];

  void _set(ConditionField f, String? v) {
    final s = v?.trim();
    widget.onChanged(f.key, s == null || s.isEmpty ? null : s);
  }

  /// Öneriyi uygular (metin alanlarına da yazar).
  void _apply(ConditionField f, String value) {
    final c = _controllers[f.key];
    if (c != null) {
      final n = double.tryParse(value);
      c.text = n == null
          ? value
          : (f.type == ConditionFieldTypes.integer
                ? '${n.round()}'
                : Fmt.number(n, maxFraction: 2));
    }
    _set(f, value);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.form.hint != null) ...[
          Text(widget.form.hint!, style: t.bodySmall),
          const SizedBox(height: 12),
        ],
        for (final f in widget.form.fields)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _field(context, f),
          ),
      ],
    );
  }

  Widget _field(BuildContext context, ConditionField f) {
    final value = widget.values[f.key];
    final error = _error(f.key);
    final Widget input = switch (f.type) {
      ConditionFieldTypes.method => _choices(f, [
        for (final m in widget.form.methodOptions)
          FilterOption(value: m.code, label: m.name),
      ], value),
      ConditionFieldTypes.period => _choices(f, [
        for (final o in widget.form.periodOptions)
          FilterOption(value: o.code, label: o.label),
      ], value),
      ConditionFieldTypes.riskClass => _choices(f, [
        for (final o in widget.form.riskClassOptions)
          FilterOption(value: o.code, label: o.label),
      ], value),
      ConditionFieldTypes.methods => FilterChips<String>(
        padding: EdgeInsets.zero,
        multi: true,
        options: [
          for (final m in widget.form.methodOptions)
            FilterOption(value: m.code, label: m.name),
        ],
        selected: ConditionValueCodec.splitCodes(value).toSet(),
        onChanged: (s) => _set(
          f,
          ConditionValueCodec.joinCodes(
            // Seçim sırası yerine formdaki sıra.
            [
              for (final m in widget.form.methodOptions)
                if (s.contains(m.code)) m.code,
            ],
          ),
        ),
      ),
      ConditionFieldTypes.date => DateField(
        label: f.label,
        value: TrTime.parseDate(value),
        firstDate: TrTime.todayStart(),
        lastDate: TrTime.addDays(TrTime.todayStart(), 3 * 365),
        quickPicks: false,
        errorText: error,
        onChanged: (d) => _set(f, TrTime.isoDate(d)),
      ),
      ConditionFieldTypes.money || ConditionFieldTypes.percent => MoneyField(
        label: f.label,
        controller: _controller(f),
        unit: f.type == ConditionFieldTypes.percent ? '%' : '₺',
        decimals: 2,
        min: f.min,
        max: f.max,
        onChanged: (v) =>
            _set(f, v == null ? null : ConditionValueCodec.canonical(v)),
      ),
      _ => AknTextField(
        label: f.label,
        controller: _controller(f),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textInputAction: TextInputAction.next,
        errorText: error,
        onChanged: (s) => _set(f, s),
      ),
    };
    final usesOwnLabel =
        f.type == ConditionFieldTypes.date ||
        f.type == ConditionFieldTypes.money ||
        f.type == ConditionFieldTypes.percent ||
        f.type == ConditionFieldTypes.integer;
    return _FieldShell(
      label: usesOwnLabel ? null : f.label,
      current:
          f.currentLabel ??
          (f.current == null ? null : _display(f, f.current!)),
      hint: f.hint,
      suggestionLabel: f.suggestionLabel,
      onUseSuggestion:
          f.suggestion == null ||
              ConditionValueCodec.same(f, value, f.suggestion)
          ? null
          : () => _apply(f, f.suggestion!),
      error:
          usesOwnLabel &&
              f.type != ConditionFieldTypes.money &&
              f.type != ConditionFieldTypes.percent
          ? null
          : error,
      child: input,
    );
  }

  String _display(ConditionField f, String raw) {
    final n = TrNumber.parse(raw) ?? double.tryParse(raw);
    return ConditionValueCodec.display(widget.form, f, n ?? raw);
  }

  Widget _choices(
    ConditionField f,
    List<FilterOption<String>> options,
    String? value,
  ) => FilterChips<String>(
    padding: EdgeInsets.zero,
    options: options,
    selected: {?value},
    onChanged: (s) => _set(f, s.isEmpty ? null : s.first),
  );
}

/// Alan çerçevesi: etiket, giriş, "Şu an …", öneri (Uygula), ipucu ve hata.
class _FieldShell extends StatelessWidget {
  const _FieldShell({
    required this.child,
    this.label,
    this.current,
    this.hint,
    this.suggestionLabel,
    this.onUseSuggestion,
    this.error,
  });

  final Widget child;
  final String? label;
  final String? current;
  final String? hint;
  final String? suggestionLabel;
  final VoidCallback? onUseSuggestion;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ...[
          Text(label!, style: t.label),
          const SizedBox(height: 4),
        ],
        child,
        if (current != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              current!.contains(':') ? current! : 'Şu an: $current',
              style: t.caption,
            ),
          ),
        if (suggestionLabel != null)
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 14, color: c.info.fg),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  suggestionLabel!,
                  style: t.caption.copyWith(color: c.info.fg),
                ),
              ),
              if (onUseSuggestion != null)
                TextButton(
                  onPressed: onUseSuggestion,
                  child: const Text('Öneriyi kullan'),
                ),
            ],
          ),
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(hint!, style: t.caption),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              error!,
              style: t.captionStrong.copyWith(color: c.danger.fg),
            ),
          ),
      ],
    );
  }
}

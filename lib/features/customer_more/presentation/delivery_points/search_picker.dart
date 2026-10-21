import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/turkish_text.dart';

/// Aranabilir seçim sayfası (il / ilçe). [allowCustom] ile listede olmayan değer de seçilebilir.
Future<String?> showSearchPicker(
  BuildContext context, {
  required String title,
  required List<String> options,
  String? selected,
  bool allowCustom = false,
  String hint = 'Ara',
}) => showAppSheet<String>(
  context: context,
  title: title,
  scrollable: false,
  maxHeightFactor: 0.9,
  builder: (_) => _SearchPicker(
    options: options,
    selected: selected,
    allowCustom: allowCustom,
    hint: hint,
  ),
);

class _SearchPicker extends StatefulWidget {
  const _SearchPicker({
    required this.options,
    required this.selected,
    required this.allowCustom,
    required this.hint,
  });

  final List<String> options;
  final String? selected;
  final bool allowCustom;
  final String hint;

  @override
  State<_SearchPicker> createState() => _SearchPickerState();
}

class _SearchPickerState extends State<_SearchPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final matches = widget.options
        .where((o) => TurkishText.matches(o, _q))
        .toList();
    final custom = _q.trim();
    final showCustom =
        widget.allowCustom &&
        custom.isNotEmpty &&
        !widget.options.any(
          (o) => TurkishText.searchKey(o) == TurkishText.searchKey(custom),
        );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchField(
          hint: widget.hint,
          autofocus: false,
          debounce: Duration.zero,
          onChanged: (v) => setState(() => _q = v),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              if (showCustom)
                AknListTile(
                  leadingIcon: Icons.edit_rounded,
                  title: '"$custom" kullan',
                  subtitle: 'Listede yok',
                  onTap: () => Navigator.of(context).pop(custom),
                ),
              for (final o in matches)
                Semantics(
                  selected: o == widget.selected,
                  child: AknListTile(
                    title: o,
                    dense: true,
                    trailing: o == widget.selected
                        ? Icon(Icons.check_rounded, color: c.brand)
                        : null,
                    onTap: () => Navigator.of(context).pop(o),
                  ),
                ),
              if (matches.isEmpty && !showCustom)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Sonuç yok.',
                    style: t.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Seçim alanı görünümü (dokununca seçim sayfası açılır).
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.requiredMark = false,
    this.enabled = true,
    this.errorText,
    this.icon = Icons.expand_more_rounded,
  });

  final String label;
  final String? value;
  final VoidCallback onTap;
  final bool requiredMark;
  final bool enabled;
  final String? errorText;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final has = value != null && value!.trim().isNotEmpty;
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$label${requiredMark ? ', zorunlu' : ''}',
      value: has ? value : 'Seçilmedi',
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: AknRadius.input,
        child: InputDecorator(
          isEmpty: !has,
          decoration: InputDecoration(
            labelText: requiredMark ? '$label *' : label,
            errorText: errorText,
            enabled: enabled,
            suffixIcon: Icon(icon, color: c.dim),
          ),
          child: Text(
            has ? value! : '',
            style: t.body.copyWith(fontSize: 16, color: c.ink),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/debouncer.dart';

/// Siparişlerim arama kuyusu (tasarım v2 §6.10): Beton kuyu, r12, `search_rounded` 20 soluk,
/// yer tutucu soluk; odakta beyaz zemin ve 2 px turuncu kenar. Dokunma alanı 48 dp (Android
/// erişilebilirlik ölçüsü; çekirdek [SearchField] 44 dp çizer). Sorgu gecikmeli bildirilir.
class OrdersSearchWell extends StatefulWidget {
  const OrdersSearchWell({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.debounce = const Duration(milliseconds: 300),
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final Duration debounce;

  @override
  State<OrdersSearchWell> createState() => _OrdersSearchWellState();
}

class _OrdersSearchWellState extends State<OrdersSearchWell> {
  late final Debouncer _debouncer = Debouncer(widget.debounce);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
    _focus.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    _focus.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final text = t.body.copyWith(height: 20 / 15, color: c.ink);
    OutlineInputBorder border(BorderSide side) =>
        OutlineInputBorder(borderRadius: AknRadius.input, borderSide: side);
    return TextField(
      controller: widget.controller,
      focusNode: _focus,
      textInputAction: TextInputAction.search,
      onChanged: (s) => _debouncer(() => widget.onChanged(s.trim())),
      onSubmitted: (s) {
        _debouncer.cancel();
        widget.onChanged(s.trim());
      },
      onTapOutside: (_) => _focus.unfocus(),
      style: text,
      cursorColor: c.brand,
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: text.copyWith(color: c.dim),
        hintMaxLines: 1,
        isDense: true,
        filled: true,
        fillColor: _focus.hasFocus ? c.surface : c.surfaceAlt,
        hoverColor: Colors.transparent,
        contentPadding: const EdgeInsets.fromLTRB(0, 14, 12, 14),
        prefixIcon: Icon(Icons.search_rounded, color: c.dim, size: 20),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 48,
        ),
        suffixIcon: widget.controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Aramayı temizle',
                icon: Icon(Icons.close_rounded, color: c.dim, size: 20),
                onPressed: () {
                  widget.controller.clear();
                  _debouncer.cancel();
                  widget.onChanged('');
                },
              ),
        border: border(BorderSide.none),
        enabledBorder: border(BorderSide.none),
        focusedBorder: border(BorderSide(color: c.brand, width: 2)),
      ),
    );
  }
}

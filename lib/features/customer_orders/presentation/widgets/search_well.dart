import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';
import '../../../../core/utils/debouncer.dart';

/// Siparişlerim arama hapı (tasarım v3 §4 Inputs): `surfaceAlt` hap, büyüteç 20 soluk, yer tutucu
/// soluk; odakta zemin beyaza döner, 2 px turuncu kenar ve 4 px yumuşak turuncu hale yumuşakça
/// belirir, büyüteç mürekkebe geçer. Dokunma alanı 48 dp (Android erişilebilirlik ölçüsü; çekirdek
/// [SearchField] 44 dp çizer). Sorgu gecikmeli bildirilir.
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
    final focused = _focus.hasFocus;
    final duration = AknMotion.of(context, AknMotion.base);
    const none = InputBorder.none;
    return AnimatedContainer(
      duration: duration,
      curve: AknMotion.standard,
      decoration: BoxDecoration(
        color: focused ? c.surface : c.surfaceAlt,
        borderRadius: AknRadius.pillAll,
        // Kenar hep 2 px: odakta yalnızca rengi gelir, içerik kaymaz.
        border: Border.all(
          color: focused ? c.brand : c.surfaceAlt.withValues(alpha: 0),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: focused ? c.brandSoft : c.brandSoft.withValues(alpha: 0),
            spreadRadius: 4,
          ),
        ],
      ),
      child: TextField(
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
          filled: false,
          hoverColor: Colors.transparent,
          contentPadding: const EdgeInsets.fromLTRB(0, 14, 12, 14),
          prefixIcon: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: focused ? c.ink : c.dim),
            duration: duration,
            builder: (context, color, _) => Icon(
              PhosphorIconsRegular.magnifyingGlass,
              color: color,
              size: 20,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 46,
            minHeight: 48,
          ),
          suffixIcon: widget.controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Aramayı temizle',
                  icon: Icon(PhosphorIconsRegular.x, color: c.dim, size: 20),
                  onPressed: () {
                    AknHaptics.selection();
                    widget.controller.clear();
                    _debouncer.cancel();
                    widget.onChanged('');
                  },
                ),
          border: none,
          enabledBorder: none,
          focusedBorder: none,
        ),
      ),
    );
  }
}

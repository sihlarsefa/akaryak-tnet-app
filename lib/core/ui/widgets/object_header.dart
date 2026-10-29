import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../motion.dart';
import '../theme.dart';
import '../typography.dart';
import 'toast.dart';

/// The head of a detail page (design v4 §4 "AknObjectHeader"): what the
/// object is, in human words — no box and no tile (it replaces
/// `AknPageBand.decorationOf` / `tileOf` on detail pages).
///
/// ```
/// Anadolu Lojistik A.Ş. ›          overline: 15/20 600 ink link (optional)
/// Motorin, 8.000 L                 title: display 28/34 800
/// Tuzla Şantiye · 29 Ekim          line: 15/22 dim
/// SIP-20261028-12002               caption: 13/18 dim, long press copies
/// ```
///
/// The bar above it carries the object type ("Sipariş"); the title is the
/// screen's header for screen readers. Codes (SIP-, SSF-, TLP-) appear only
/// here, as the [caption] (P4).
class AknObjectHeader extends StatelessWidget {
  const AknObjectHeader({
    super.key,
    required this.title,
    this.overline,
    this.onOverline,
    this.line,
    this.caption,
    this.copyCaption = true,
    this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 16),
  });

  /// The object's human name ("Motorin, 8.000 L").
  final String title;

  /// The parent it belongs to ("Anadolu Lojistik A.Ş."): a link with › when
  /// [onOverline] is given.
  final String? overline;
  final VoidCallback? onOverline;

  /// Where and when ("Tuzla Şantiye · 29 Ekim").
  final String? line;

  /// The code ("SIP-20261028-12002"); a long press copies it.
  final String? caption;

  /// Long-pressing the [caption] copies it with a short toast.
  final bool copyCaption;
  final EdgeInsetsGeometry padding;

  Future<void> _copy(BuildContext context, String text) async {
    AknHaptics.light();
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    AppToast.success('$text kopyalandı', context: context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final o = overline;
    final l = line;
    final cap = caption;
    Widget? over;
    if (o != null && o.isNotEmpty) {
      final text = Text(
        o,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: t.bodyStrong.copyWith(
          height: 20 / 15,
          fontWeight: FontWeight.w600,
          color: c.ink,
        ),
      );
      over = onOverline == null
          ? text
          : Semantics(
              button: true,
              label: o,
              excludeSemantics: true,
              onTap: onOverline,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  AknHaptics.selection();
                  onOverline!();
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 32),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: text),
                      const SizedBox(width: 2),
                      Icon(
                        PhosphorIconsRegular.caretRight,
                        size: 16,
                        color: c.ink,
                      ),
                    ],
                  ),
                ),
              ),
            );
    }
    Widget? code;
    if (cap != null && cap.isNotEmpty) {
      final text = Text(
        cap,
        style: t.label.copyWith(
          fontWeight: FontWeight.w500,
          color: c.dim,
          fontFeatures: AknNumerals.tabular,
        ),
      );
      code = !copyCaption
          ? text
          : Semantics(
              label: cap,
              hint: 'Kopyalamak için basılı tutun',
              excludeSemantics: true,
              onLongPress: () => _copy(context, cap),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: () => _copy(context, cap),
                child: text,
              ),
            );
    }
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (over != null) ...[over, const SizedBox(height: 2)],
          Semantics(
            header: true,
            child: Text(title, style: t.display.copyWith(color: c.ink)),
          ),
          if (l != null && l.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(l, style: t.body.copyWith(color: c.dim)),
          ],
          if (code != null) ...[const SizedBox(height: 2), code],
        ],
      ),
    );
  }
}

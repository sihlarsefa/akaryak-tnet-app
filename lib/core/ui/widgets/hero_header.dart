import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// Deprecated header block (design v2 §6.28): the orange header strip is
/// gone. It now renders a **plain white header** on the page colour — a
/// `display` title (30/36 600, a screen-reader header), an optional
/// `bodySmall` subtitle, optional [leading] / [trailing] widgets, the
/// [chips] (off the plate an `AknHeroChip` renders as a lamp) and an
/// optional [child] — aligned on the 20 px edge.
///
/// Homes use `AknHomeHeader` (logo tile, company, person, bell); object
/// pages start their body with a `display` title. Keep this widget only for
/// old call sites.
///
/// ```dart
/// AknHeroHeader(
///   title: 'Profil',
///   subtitle: 'Demir Petrol Akaryakıt Ltd. Şti.',
///   trailing: const AknAvatar(name: 'Mehmet Demir', size: 56),
/// )
/// ```
///
/// [watermark] is ignored (no chevron watermarks anywhere). With [topInset]
/// the header also runs under the status bar (screens without an app bar):
/// it adds the status-bar height on top and sets the page's status icons
/// (dark on white, light in dark mode).
class AknHeroHeader extends StatelessWidget {
  const AknHeroHeader({
    super.key,
    this.title,
    this.titleWidget,
    this.subtitle,
    this.leading,
    this.trailing,
    this.chips = const <Widget>[],
    this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 16),
    this.watermark = true,
    this.topInset = false,
  });

  /// Page title ("Profil"): `display` 30/36 600, a screen-reader header.
  final String? title;

  /// Replaces [title].
  final Widget? titleWidget;

  /// The line under the title (`bodySmall` 14/20 dim).
  final String? subtitle;

  /// Left of the title block (e.g. an avatar).
  final Widget? leading;

  /// Right of the title block (e.g. an avatar).
  final Widget? trailing;

  /// Role chips and facts (`AknHeroChip`s render as lamps here); they wrap.
  final List<Widget> chips;

  /// Extra content under the chips.
  final Widget? child;
  final EdgeInsetsGeometry padding;

  /// Ignored in v2 (no watermark).
  final bool watermark;

  /// Run under the status bar (no app bar above).
  final bool topInset;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final top = topInset ? MediaQuery.paddingOf(context).top : 0.0;
    final Widget? head =
        titleWidget ??
        (title == null
            ? null
            : Semantics(
                header: true,
                child: Text(title!, style: t.display.copyWith(color: c.ink)),
              ));
    final Widget? sub = subtitle == null
        ? null
        : Text(
            subtitle!,
            style: t.bodySmall.copyWith(color: c.dim),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          );
    final hasText = head != null || sub != null;
    Widget block = ColoredBox(
      color: c.bg,
      child: Padding(
        padding: padding.add(EdgeInsets.only(top: top)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasText || leading != null || trailing != null)
              Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 12)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ?head,
                        if (head != null && sub != null)
                          const SizedBox(height: 4),
                        ?sub,
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    trailing!,
                  ],
                ],
              ),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 16, runSpacing: 8, children: chips),
            ],
            if (child != null) ...[
              SizedBox(height: hasText || chips.isNotEmpty ? 16 : 0),
              child!,
            ],
          ],
        ),
      ),
    );
    if (topInset) {
      block = AnnotatedRegion<SystemUiOverlayStyle>(
        value: AknTheme.overlayFor(c.brightness),
        child: block,
      );
    }
    return block;
  }
}

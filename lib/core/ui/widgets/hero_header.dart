import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../painters/hero_backdrop.dart';
import '../theme.dart';
import '../tokens.dart';
import 'cards.dart';

/// The orange home header block (spec §2, F2GO pattern "coloured top strip +
/// white cards").
///
/// Put it FIRST in the body of an `AppScaffold(hero: true)` — with no top
/// padding above it — and it continues the hero app bar's strip without a
/// seam: same horizontal gradient, a faint » watermark on the right, a slight
/// depth toward the bottom and a 28 px rounded bottom edge (the house style:
/// cards below start 16 px under it, they never overlap it).
///
/// Content is re-themed on the hero ([OnHero]): white text, dark-glass pills.
///
/// ```dart
/// AppScaffold(
///   hero: true,
///   titleWidget: const AknLogo(markSize: 28, onDark: true),
///   body: ListView(
///     padding: EdgeInsets.zero,
///     children: [
///       AknHeroHeader(
///         title: 'Günaydın, Ayşe',
///         subtitle: 'Demo Petrol · Kartal',
///         chips: const [AknHeroChip(label: 'Sahip'), AknHeroChip(label: 'Finans')],
///       ),
///       const SizedBox(height: 16),
///       // … white cards
///     ],
///   ),
/// )
/// ```
///
/// With [topInset] the block also runs under the status bar (screens
/// without an app bar): it adds the status-bar height on top and sets light
/// status icons.
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
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 24),
    this.watermark = true,
    this.topInset = false,
  });

  /// Greeting / page title ("Günaydın, Ayşe"): 22 w800, a screen-reader
  /// header.
  final String? title;

  /// Replaces [title].
  final Widget? titleWidget;

  /// Station / company name under the title.
  final String? subtitle;

  /// Left of the title block (e.g. an avatar).
  final Widget? leading;

  /// Right of the title block (e.g. a weather pill or an avatar).
  final Widget? trailing;

  /// Role chips and facts: use [AknHeroChip]s (wrap onto lines).
  final List<Widget> chips;

  /// Extra hero content under the chips (summary chips, a primary action).
  final Widget? child;
  final EdgeInsetsGeometry padding;
  final bool watermark;

  /// Run under the status bar (no app bar above).
  final bool topInset;

  @override
  Widget build(BuildContext context) {
    final top = topInset ? MediaQuery.paddingOf(context).top : 0.0;
    Widget block = ClipRRect(
      borderRadius: AknRadius.header,
      child: AknHeroBackground(
        style: AknHeroStyle.strip,
        watermark: watermark,
        highlight: false,
        depth: true,
        child: Padding(
          padding: padding.add(EdgeInsets.only(top: top)),
          child: OnHero(
            child: Builder(
              builder: (context) {
                final t = context.aknText;
                final Widget? head =
                    titleWidget ??
                    (title == null
                        ? null
                        : Semantics(
                            header: true,
                            child: Text(title!, style: t.title),
                          ));
                final Widget? sub = subtitle == null
                    ? null
                    : Text(
                        subtitle!,
                        style: t.body.copyWith(fontWeight: FontWeight.w500),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      );
                final hasText = head != null || sub != null;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasText || leading != null || trailing != null)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (leading != null) ...[
                            leading!,
                            const SizedBox(width: 12),
                          ],
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
                      Wrap(spacing: 8, runSpacing: 8, children: chips),
                    ],
                    if (child != null) ...[
                      SizedBox(height: hasText || chips.isNotEmpty ? 16 : 0),
                      child!,
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    if (topInset) {
      block = AnnotatedRegion<SystemUiOverlayStyle>(
        value: AknTheme.overlayOnHero,
        child: block,
      );
    }
    return block;
  }
}

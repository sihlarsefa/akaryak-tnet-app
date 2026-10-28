import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion.dart';
import '../theme.dart';

/// Deprecated header block: the orange header strip is gone. It renders a
/// **plain header** on the page colour — a `display` title (28/34 800, a
/// screen-reader header), an optional `bodySmall` subtitle, optional
/// [leading] / [trailing] widgets, the [chips] (off the plate an
/// `AknHeroChip` renders as a lamp) and an optional [child] — aligned on
/// the 20 px edge. The title row, the chips and the child fade up into
/// place one after another when it first appears (design v3 §5).
///
/// Homes use `AknHomeHeader` (the luminous orange band); object pages start
/// their body with a `display` title. Keep this widget only for old call
/// sites.
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
/// (dark on light, light in dark mode).
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

  /// Page title ("Profil"): `display` 28/34 800, a screen-reader header.
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

  /// Ignored (no watermark).
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
    const step = Duration(milliseconds: 70);
    Widget block = ColoredBox(
      color: c.bg,
      child: Padding(
        padding: padding.add(EdgeInsets.only(top: top)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasText || leading != null || trailing != null)
              _Rise(
                offset: 10,
                child: Row(
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
              ),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 12),
              _Rise(
                delay: step,
                child: Wrap(spacing: 16, runSpacing: 8, children: chips),
              ),
            ],
            if (child != null) ...[
              SizedBox(height: hasText || chips.isNotEmpty ? 16 : 0),
              _Rise(delay: step * 2, child: child!),
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

/// Fades its child up into place once ([offset] px, 360 ms, emphasized)
/// after [delay]; the wrappers stay in the tree afterwards, so the child is
/// never remounted. Static under reduce motion.
class _Rise extends StatefulWidget {
  const _Rise({
    required this.child,
    this.delay = Duration.zero,
    this.offset = 8,
  });

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  State<_Rise> createState() => _RiseState();
}

class _RiseState extends State<_Rise> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
  );
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else if (widget.delay <= Duration.zero) {
      _c.forward();
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) {
      final v = _c.value >= 1
          ? 1.0
          : AknMotion.emphasizedCurve.transform(_c.value);
      return Opacity(
        opacity: v,
        alwaysIncludeSemantics: true,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - v)),
          child: child,
        ),
      );
    },
  );
}

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';

/// Container transform for list → detail (order, shipment, approval cards;
/// spec C.6; design v3 §5): the tapped card grows into the detail page —
/// its squircle corners easing out to the page's square edges, the white
/// card colour flowing into the page colour while the contents fade
/// through — and shrinks back into the card on close.
///
/// The detail opens as an imperative route on the root navigator (above the
/// bottom bar, like the router's detail pages); the URL does not change, so
/// deep links keep using the router path. Use it for in-app taps; the same
/// detail widget can also be registered as the go_router page.
///
/// ```dart
/// AknOpenContainer<void>(
///   closedBuilder: (context, open) => OrderCard(order: o, onTap: open),
///   openBuilder: (context, close) => OrderDetailPage(id: o.id),
/// )
/// ```
///
/// The closed card should not draw its own border or shadow (the container
/// does: the v3 card shadow, plus a 1 px `line` in dark mode). The
/// transform runs [AknMotion.slow] (400 ms) each way. Reduce motion: plain
/// open, no transform.
class AknOpenContainer<T extends Object?> extends StatelessWidget {
  const AknOpenContainer({
    super.key,
    required this.closedBuilder,
    required this.openBuilder,
    this.onClosed,
    this.radius = 20,
    this.closedColor,
    this.tappable = false,
  });

  /// `open` starts the transform.
  final CloseContainerBuilder closedBuilder;

  /// `close` returns to the card (optionally with a value).
  final OpenContainerBuilder<T> openBuilder;
  final ClosedCallback<T?>? onClosed;

  /// The closed card's corner radius (v3 cards: 20).
  final double radius;
  final Color? closedColor;

  /// Make the whole closed card open on tap (no need to call `open`).
  final bool tappable;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final reduced = AknMotion.reduced(context);
    return OpenContainer<T>(
      useRootNavigator: true,
      tappable: tappable,
      transitionType: ContainerTransitionType.fadeThrough,
      transitionDuration: reduced ? Duration.zero : AknMotion.slow,
      closedColor: closedColor ?? c.surface,
      openColor: c.bg,
      middleColor: c.surface,
      closedElevation: 0,
      openElevation: 0,
      closedShadows: AknShadows.card(c),
      closedShape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.circular(radius),
        side: c.isDark ? BorderSide(color: c.line) : BorderSide.none,
      ),
      openShape: const RoundedSuperellipseBorder(),
      onClosed: onClosed,
      closedBuilder: closedBuilder,
      openBuilder: openBuilder,
    );
  }
}

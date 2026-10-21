import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';
import '../tokens.dart';

/// Container transform for list → detail (order, shipment, approval cards;
/// spec C.6): the tapped card grows into the detail page, which shrinks back
/// into the card on close.
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
/// does). Reduce motion: plain open, no transform.
class AknOpenContainer<T extends Object?> extends StatelessWidget {
  const AknOpenContainer({
    super.key,
    required this.closedBuilder,
    required this.openBuilder,
    this.onClosed,
    this.radius = AknRadius.md,
    this.closedColor,
    this.tappable = false,
  });

  /// `open` starts the transform.
  final CloseContainerBuilder closedBuilder;

  /// `close` returns to the card (optionally with a value).
  final OpenContainerBuilder<T> openBuilder;
  final ClosedCallback<T?>? onClosed;
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
      closedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: c.line),
      ),
      openShape: const RoundedRectangleBorder(),
      onClosed: onClosed,
      closedBuilder: closedBuilder,
      openBuilder: openBuilder,
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../tokens.dart';

/// Delivery route: depot dot → destination pin, travelled part solid, the
/// rest dashed, with a truck on the line.
///
/// * [progress] places the truck (0..1, animated on change).
/// * Without [progress] and with [moving] (InTransit) the truck glides once,
///   slowly, from 15 % to 85 % of the route and rests there (spec C.6: one
///   pass, no loop; it is a status strip, not a live position).
/// * Reduce motion or a screen reader: no gliding; the truck rests mid-route.
/// * The pin uses `ink`, so it stays visible on navy hero panels.
class TruckRoute extends StatefulWidget {
  const TruckRoute({
    super.key,
    this.progress,
    this.moving = false,
    this.height = 44,
    this.color,
    this.originLabel,
    this.destinationLabel,
    this.semanticLabel,
  });

  final double? progress;
  final bool moving;
  final double height;
  final Color? color;
  final String? originLabel;
  final String? destinationLabel;
  final String? semanticLabel;

  @override
  State<TruckRoute> createState() => _TruckRouteState();
}

class _TruckRouteState extends State<TruckRoute>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glide = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(TruckRoute old) {
    super.didUpdateWidget(old);
    _sync();
  }

  bool _still(BuildContext context) =>
      AknMotion.reduced(context) ||
      (MediaQuery.maybeAccessibleNavigationOf(context) ?? false);

  void _sync() {
    final run = widget.progress == null && widget.moving && !_still(context);
    if (run && !_glide.isAnimating && _glide.value == 0) {
      _glide.forward(from: 0);
    } else if (!run && _glide.isAnimating) {
      _glide.stop();
    }
  }

  @override
  void dispose() {
    _glide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AknColors>() ?? AknColors.light;
    final color = widget.color ?? c.brandBright;
    final labels =
        widget.originLabel != null || widget.destinationLabel != null;
    final t = Theme.of(context).textTheme.bodySmall;

    Widget route(double p) => LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = widget.height;
        final truck = h * 0.62;
        final inset = h * 0.25;
        final x = inset + (w - inset * 2) * p;
        return SizedBox(
          height: h,
          width: w,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: TruckRoutePainter(
                    progress: p,
                    color: color,
                    track: c.lineStrong,
                    inset: inset,
                    pin: c.ink,
                  ),
                ),
              ),
              Positioned(
                left: x - truck / 2,
                top: h / 2 - truck * 0.86,
                child: Icon(
                  Icons.local_shipping_rounded,
                  size: truck,
                  color: color,
                ),
              ),
            ],
          ),
        );
      },
    );

    final Widget line = widget.progress != null
        ? TweenAnimationBuilder<double>(
            tween: Tween<double>(end: widget.progress!.clamp(0.0, 1.0)),
            duration: AknMotion.of(context, AknMotion.slow),
            curve: AknMotion.emphasizedCurve,
            builder: (context, p, _) => route(p),
          )
        : AnimatedBuilder(
            animation: _glide,
            builder: (context, _) {
              if (!widget.moving || _still(context)) {
                return route(widget.moving ? 0.5 : 0);
              }
              final v = Curves.easeInOut.transform(_glide.value);
              return route(0.15 + 0.7 * v);
            },
          );

    return Semantics(
      label: widget.semanticLabel ?? 'Teslimat rotası',
      excludeSemantics: true,
      child: labels
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                line,
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.originLabel ?? '',
                        style: t,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.destinationLabel ?? '',
                        style: t,
                        maxLines: 1,
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            )
          : line,
    );
  }
}

class TruckRoutePainter extends CustomPainter {
  TruckRoutePainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.inset,
    required this.pin,
  });

  final double progress;
  final Color color;
  final Color track;
  final double inset;
  final Color pin;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * 0.62;
    final x0 = inset;
    final x1 = size.width - inset;
    final xp = x0 + (x1 - x0) * progress;
    final stroke = math.max(2.0, size.height * 0.07);

    // Remaining route: dashed.
    final dash = Paint()
      ..color = track
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    const dashLen = 6.0;
    const gap = 6.0;
    for (var x = xp; x < x1; x += dashLen + gap) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + dashLen, x1), y), dash);
    }
    // Travelled route: solid.
    canvas.drawLine(
      Offset(x0, y),
      Offset(xp, y),
      Paint()
        ..color = color
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
    // Origin dot.
    canvas.drawCircle(Offset(x0, y), stroke * 1.6, Paint()..color = color);
    canvas.drawCircle(
      Offset(x0, y),
      stroke * 0.7,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    // Destination pin.
    final r = size.height * 0.16;
    final pinPath = Path()
      ..moveTo(x1, y)
      ..quadraticBezierTo(x1 - r * 1.2, y - r * 1.4, x1 - r, y - r * 2.1)
      ..arcToPoint(
        Offset(x1 + r, y - r * 2.1),
        radius: Radius.circular(r),
        clockwise: true,
      )
      ..quadraticBezierTo(x1 + r * 1.2, y - r * 1.4, x1, y)
      ..close();
    canvas.drawPath(pinPath, Paint()..color = pin);
    canvas.drawCircle(
      Offset(x1, y - r * 2.1),
      r * 0.42,
      Paint()..color = const Color(0xFFFFFFFF),
    );
  }

  @override
  bool shouldRepaint(TruckRoutePainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.track != track ||
      old.inset != inset ||
      old.pin != pin;
}

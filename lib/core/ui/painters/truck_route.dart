import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../tokens.dart';

/// The route line (design v2 §6.15): origin dot → travelled part (solid ink)
/// → **the vehicle, which is the brand tile** (a logo-orange square with the
/// white ») → the rest of the way dashed → the destination ring.
///
/// * [progress] (0..1) places the vehicle; it glides 400 ms when the value
///   changes (an answer to data, never a loop). Without [progress], an
///   in-transit route ([moving]) rests mid-way and a planned one at the
///   origin. Reduce motion: no glide.
/// * [height] is 22 (rows, hero rows) or 16 (compact); larger values are
///   clamped to 24 so older call sites keep the v2 size.
/// * Optional labels under the line: origin left ("Dilovası deposu, 09:58
///   çıktı"), destination right ("18 km kaldı").
/// * The » tile is logo orange with a white glyph everywhere (the plate
///   card is white in the owner's decision G).
///
/// Give it a [semanticLabel] with the ETA: "Yolda. Dilovası deposundan
/// Pendik Lojistik Merkezine, tahmini varış 11:20."
class TruckRoute extends StatelessWidget {
  const TruckRoute({
    super.key,
    this.progress,
    this.moving = false,
    this.height = 22,
    this.color,
    this.originLabel,
    this.destinationLabel,
    this.semanticLabel,
  });

  final double? progress;
  final bool moving;
  final double height;

  /// Overrides the travelled line and origin colour (ink by default).
  final Color? color;
  final String? originLabel;
  final String? destinationLabel;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AknColors>() ?? AknColors.light;
    final h = height.clamp(14.0, 24.0);
    final target = (progress ?? (moving ? 0.5 : 0.0)).clamp(0.0, 1.0);
    final labels = originLabel != null || destinationLabel != null;
    final t = Theme.of(context).textTheme.bodySmall?.copyWith(color: c.dim);

    final line = TweenAnimationBuilder<double>(
      tween: Tween<double>(end: target),
      duration: AknMotion.of(context, AknMotion.routeGlide),
      curve: AknMotion.emphasizedCurve,
      builder: (context, p, _) => CustomPaint(
        size: Size(double.infinity, h),
        painter: TruckRoutePainter(
          progress: p,
          color: color ?? c.ink,
          track: c.faint,
          inset: 0,
          pin: c.ink,
          ringFill: c.bg,
          vehicle: c.logo,
          vehicleGlyph: const Color(0xFFFFFFFF),
        ),
      ),
    );

    return Semantics(
      label: semanticLabel ?? 'Teslimat rotası',
      excludeSemantics: true,
      child: labels
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: h, child: line),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        originLabel ?? '',
                        style: t,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        destinationLabel ?? '',
                        style: t,
                        maxLines: 2,
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            )
          : SizedBox(height: h, child: line),
    );
  }
}

/// Paints the v2 route line at any height (the board's geometry is drawn at
/// 22 px and scales with the height): origin dot r5 in [color], travelled
/// 3 px [color] line with a round cap, the [vehicle] tile (22 × 22, r5.5)
/// with a [vehicleGlyph] », the remaining 2.5 px dashed [track] (7 on, 6
/// off) and the destination ring (r5.5, 2.5 px [pin] stroke, [ringFill]
/// inside).
///
/// [vehicle] null draws no tile (callers that place their own marker);
/// [inset] adds extra space at both ends.
class TruckRoutePainter extends CustomPainter {
  TruckRoutePainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.inset,
    required this.pin,
    this.ringFill,
    this.vehicle,
    this.vehicleGlyph,
  });

  final double progress;
  final Color color;
  final Color track;
  final double inset;
  final Color pin;
  final Color? ringFill;
  final Color? vehicle;
  final Color? vehicleGlyph;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final h = math.min(size.height, 40.0);
    final s = h / 22;
    final y = size.height / 2;
    final rOrigin = 5 * s;
    final rDest = 5.5 * s;
    final destStroke = 2.5 * s;
    final tile = 22 * s;
    final x0 = inset + rOrigin;
    final x1 = size.width - inset - rDest - destStroke / 2;
    final hasVehicle = vehicle != null;
    final p = progress.clamp(0.0, 1.0);
    final lo = hasVehicle ? inset + tile / 2 : x0;
    final hi = hasVehicle ? size.width - inset - tile / 2 : x1;
    final xv = (x0 + (x1 - x0) * p).clamp(lo, math.max(lo, hi)).toDouble();

    // Remaining way: dashed.
    final dash = Paint()
      ..color = track
      ..strokeWidth = 2.5 * s;
    final dashFrom = hasVehicle ? xv + tile / 2 + 3 * s : xv;
    final dashTo = x1 - rDest;
    for (var x = dashFrom; x < dashTo; x += 13 * s) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + 7 * s, dashTo), y),
        dash,
      );
    }
    // Travelled way: solid, round cap.
    final travelledTo = hasVehicle ? xv - tile / 2 - 1 * s : xv;
    if (travelledTo > x0) {
      canvas.drawLine(
        Offset(x0, y),
        Offset(travelledTo, y),
        Paint()
          ..color = color
          ..strokeWidth = 3 * s
          ..strokeCap = StrokeCap.round,
      );
    }
    // Origin dot.
    canvas.drawCircle(Offset(x0, y), rOrigin, Paint()..color = color);
    // Destination ring.
    final dest = Offset(size.width - inset - rDest - destStroke / 2, y);
    if (ringFill != null) {
      canvas.drawCircle(dest, rDest, Paint()..color = ringFill!);
    }
    canvas.drawCircle(
      dest,
      rDest,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = destStroke
        ..color = pin,
    );
    if (!hasVehicle) return;
    // The vehicle: the brand tile with the ».
    final rect = Rect.fromCenter(
      center: Offset(xv, y),
      width: tile,
      height: tile,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(5.5 * s)),
      Paint()..color = vehicle!,
    );
    final glyph = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = vehicleGlyph ?? Colors.white;
    final o = rect.topLeft;
    Offset at(double dx, double dy) => o + Offset(dx * s, dy * s);
    canvas.drawPath(
      Path()
        ..moveTo(at(5.6, 6.3).dx, at(5.6, 6.3).dy)
        ..lineTo(at(10, 10.8).dx, at(10, 10.8).dy)
        ..lineTo(at(5.6, 15.4).dx, at(5.6, 15.4).dy)
        ..moveTo(at(11, 6.3).dx, at(11, 6.3).dy)
        ..lineTo(at(15.4, 10.8).dx, at(15.4, 10.8).dy)
        ..lineTo(at(11, 15.4).dx, at(11, 15.4).dy),
      glyph,
    );
  }

  @override
  bool shouldRepaint(TruckRoutePainter old) =>
      old.progress != progress ||
      old.color != color ||
      old.track != track ||
      old.inset != inset ||
      old.pin != pin ||
      old.ringFill != ringFill ||
      old.vehicle != vehicle ||
      old.vehicleGlyph != vehicleGlyph;
}

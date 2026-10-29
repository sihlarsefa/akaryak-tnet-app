import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../motion.dart';
import '../tokens.dart';

/// The route line (design v3 §4): origin dot → the travelled part, an
/// orange line that brightens towards the vehicle → **the vehicle, the brand
/// tile** (a logo-orange rounded square with the white » and a warm glow)
/// → the rest of the way dotted in graphite → the destination ring.
///
/// * [progress] (0..1) places the vehicle. On first build the vehicle
///   glides out from the origin to its place, and it glides again whenever
///   the value changes (emphasized curve). Without [progress], an in-transit
///   route ([moving]) rests mid-way and a planned one at the origin. Reduce
///   motion: no glide.
/// * While [moving], a soft ping ring breathes around the vehicle (ambient
///   motion, [AknAmbient]; still in tests and under reduce motion).
/// * [height] is 22 (rows, hero rows) or 16 (compact); larger values are
///   clamped to 24 so older call sites keep their size.
/// * Optional labels under the line: origin left ("Dilovası deposu, 09:58
///   çıktı"), destination right ("18 km kaldı").
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

  /// Overrides the travelled line and origin colour (the orange gradient by
  /// default).
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

    Widget paint(double p, double pulse) => CustomPaint(
      size: Size(double.infinity, h),
      painter: TruckRoutePainter(
        progress: p,
        color: color ?? c.brandBright,
        travelledStart: color == null ? c.brandFillStart : null,
        track: c.lineStrong,
        inset: 0,
        pin: c.ink,
        ringFill: c.surface,
        vehicle: c.logo,
        vehicleGlyph: const Color(0xFFFFFFFF),
        pulse: pulse,
      ),
    );

    final line = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: target),
      duration: AknMotion.of(context, const Duration(milliseconds: 700)),
      curve: AknMotion.emphasizedCurve,
      builder: (context, p, _) => moving
          ? AknAmbient(
              period: AknMotion.breathe,
              curve: Curves.linear,
              // The vehicle ping is a "you are here" loop: budgeted (v4 §6).
              role: AknAmbientRole.focus,
              builder: (context, pulse, _) => paint(p, pulse),
            )
          : paint(p, 0),
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
                const SizedBox(height: 8),
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

/// Paints the v3 route line at any height (the geometry is drawn at 22 px
/// and scales with the height): origin dot r5, the travelled 3 px line with
/// round caps ([travelledStart] → [color], or solid [color]), the [vehicle]
/// tile (22 × 22, r6) with a warm glow and a [vehicleGlyph] », the remaining
/// 2.5 px dotted [track] and the destination ring (r5.5, 2.5 px [pin]
/// stroke, [ringFill] inside).
///
/// [vehicle] null draws no tile (callers that place their own marker);
/// [inset] adds extra space at both ends; [pulse] (0..1, looping) draws the
/// ping ring that grows and fades around the vehicle (0 = none).
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
    this.travelledStart,
    this.pulse = 0,
  });

  final double progress;
  final Color color;
  final Color track;
  final double inset;
  final Color pin;
  final Color? ringFill;
  final Color? vehicle;
  final Color? vehicleGlyph;

  /// The travelled line's start colour (null: solid [color]).
  final Color? travelledStart;

  /// The vehicle's ping ring (0..1; 0 = none).
  final double pulse;

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

    // Remaining way: dotted, round caps.
    final dots = Paint()
      ..color = track
      ..strokeWidth = 2.5 * s
      ..strokeCap = StrokeCap.round;
    final dashFrom = hasVehicle ? xv + tile / 2 + 5 * s : xv + 4 * s;
    final dashTo = x1 - rDest - 4 * s;
    for (var x = dashFrom; x < dashTo; x += 8 * s) {
      canvas.drawLine(
        Offset(x, y),
        Offset(math.min(x + 2 * s, dashTo), y),
        dots,
      );
    }
    // Travelled way: solid, round caps, brightening towards the vehicle.
    final travelledTo = hasVehicle ? xv - tile / 2 - 3 * s : xv;
    final start = travelledStart;
    if (travelledTo > x0) {
      final paint = Paint()
        ..strokeWidth = 3 * s
        ..strokeCap = StrokeCap.round;
      if (start == null) {
        paint.color = color;
      } else {
        paint.shader = LinearGradient(
          colors: [start, color],
        ).createShader(Rect.fromLTRB(x0, y - 2, travelledTo, y + 2));
      }
      canvas.drawLine(Offset(x0, y), Offset(travelledTo, y), paint);
    }
    // Origin dot.
    canvas.drawCircle(Offset(x0, y), rOrigin, Paint()..color = start ?? color);
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
    final v = vehicle;
    if (v == null) return;
    final center = Offset(xv, y);
    // The live ping: a ring that grows out of the tile and fades.
    if (pulse > 0) {
      final grow = Curves.easeOutCubic.transform(pulse);
      final fade = 1 - pulse;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: center,
            width: tile + 12 * s * grow,
            height: tile + 12 * s * grow,
          ),
          Radius.circular(6 * s + 6 * s * grow),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * s
          ..color = v.withValues(alpha: v.a * 0.45 * fade),
      );
    }
    // The vehicle: the brand tile with the », on a warm glow.
    paintFlowMark(
      canvas,
      center,
      side: tile,
      tile: v,
      glyph: vehicleGlyph ?? Colors.white,
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
      old.vehicleGlyph != vehicleGlyph ||
      old.travelledStart != travelledStart ||
      old.pulse != pulse;
}

/// Paints the » mark (v4 §3b, the logo's »): a [side] × [side] rounded
/// tile (radius 6 at 22 px) in [tile] on a warm glow, with the white double
/// chevron. Shared by [TruckRoutePainter] and the Akış line, so "where is my
/// order / truck" looks the same everywhere.
void paintFlowMark(
  Canvas canvas,
  Offset center, {
  required double side,
  required Color tile,
  Color glyph = const Color(0xFFFFFFFF),
  double glow = 1,
}) {
  final s = side / 22;
  final rect = Rect.fromCenter(center: center, width: side, height: side);
  final rrect = RRect.fromRectAndRadius(rect, Radius.circular(6 * s));
  if (glow > 0) {
    canvas.drawRRect(
      rrect.shift(Offset(0, 2 * s)),
      Paint()
        ..color = tile.withValues(alpha: tile.a * 0.4 * glow)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * s),
    );
  }
  canvas.drawRRect(rrect, Paint()..color = tile);
  final pen = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.6 * s
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = glyph;
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
    pen,
  );
}

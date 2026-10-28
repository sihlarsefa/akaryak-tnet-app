import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../tokens.dart';

/// The six drawings of design v3 §4 (96 × 64 grid): soft filled objects —
/// white bodies with a 2 px graphite outline, round caps and joins, dark
/// tyres, light-grey details — and the orange accent of the brand (the »
/// on the tank, the needle, the last drop). No people. Empty and error
/// states set them on a floating `surfaceAlt` disc (`EmptyState`).
enum AknDrawing {
  /// Parked tanker; the orange accent is the brand » on its tank (no
  /// orders).
  tanker,

  /// Empty gauge; the orange accent is the needle resting at zero (no
  /// statistics).
  gauge,

  /// Pump nozzle with a hose; the orange accents are its grip and the last
  /// drop (no deliveries).
  nozzle,

  /// Two stacked pages, the front one with a folded corner; the orange
  /// accent is the title line (no files).
  document,

  /// A route with a gap; the orange accent is the vehicle — the brand tile
  /// with its » — stopped before it (errors).
  routeGap,

  /// A cloud with a slash; the orange accent is the slash (offline).
  cloudSlash,
}

/// Subjects of the empty and error states. Each one maps onto one of the six
/// [AknDrawing]s; [icon] is kept for callers that still show an icon.
enum AknIllustration {
  inbox(PhosphorIconsRegular.tray, AknDrawing.tanker),
  search(PhosphorIconsRegular.magnifyingGlass, AknDrawing.document),
  orders(PhosphorIconsFill.receipt, AknDrawing.tanker),
  delivery(PhosphorIconsFill.truck, AknDrawing.nozzle),
  documents(PhosphorIconsRegular.folderOpen, AknDrawing.document),
  approvals(PhosphorIconsFill.checkCircle, AknDrawing.document),
  notifications(PhosphorIconsRegular.bell, AknDrawing.document),
  customers(PhosphorIconsFill.usersThree, AknDrawing.tanker),
  payments(PhosphorIconsRegular.money, AknDrawing.document),
  field(PhosphorIconsRegular.storefront, AknDrawing.tanker),
  offline(PhosphorIconsRegular.cloudSlash, AknDrawing.cloudSlash),
  locked(PhosphorIconsRegular.lock, AknDrawing.document),
  error(PhosphorIconsRegular.warningCircle, AknDrawing.routeGap),
  done(PhosphorIconsRegular.checkCircle, AknDrawing.tanker),
  stats(PhosphorIconsFill.gauge, AknDrawing.gauge);

  const AknIllustration(this.icon, this.drawing);
  final IconData icon;
  final AknDrawing drawing;
}

/// A 96 × 64 drawing for empty, error and offline states (design v3 §4).
/// [size] is the width (the height is two thirds of it). Decorative: it is
/// excluded from semantics.
class EmptyIllustration extends StatelessWidget {
  const EmptyIllustration({
    super.key,
    this.subject = AknIllustration.inbox,
    this.size = 96,
    this.tone,
    this.drawing,
  });

  final AknIllustration subject;

  /// Width in logical px (96 by default).
  final double size;

  /// Deprecated: the drawings always use the graphite + orange palette.
  final AknTone? tone;

  /// Draws this instead of the [subject]'s drawing.
  final AknDrawing? drawing;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AknColors>() ?? AknColors.light;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(size, size * 64 / 96),
        painter: EmptyIllustrationPainter.themed(
          c,
          drawing: drawing ?? subject.drawing,
        ),
      ),
    );
  }
}

/// Paints one [AknDrawing] in the 96 × 64 grid, scaled to the canvas.
///
/// * [stroke]: the graphite outline (2 px);
/// * [accent]: the orange of the brand;
/// * [fill]: the body colour of every object (white; it also hides lines
///   behind tyres and hubs);
/// * [shade] (windows, hatches, the back page), [faint] (the ground, text
///   lines), [wheel] (tyres) and [accentSoft] (the puddle under the drop)
///   default to mixes of the colours above.
class EmptyIllustrationPainter extends CustomPainter {
  EmptyIllustrationPainter({
    required this.drawing,
    required this.stroke,
    required this.accent,
    required this.fill,
    Color? shade,
    Color? faint,
    Color? wheel,
    Color? accentSoft,
  }) : shade = shade ?? Color.lerp(fill, stroke, 0.16)!,
       faint = faint ?? Color.lerp(fill, stroke, 0.42)!,
       wheel = wheel ?? Color.lerp(stroke, const Color(0xFF000000), 0.35)!,
       accentSoft = accentSoft ?? Color.lerp(fill, accent, 0.18)!;

  /// The v3 palette of [c] (light: white bodies on graphite outlines; dark:
  /// raised graphite bodies with light outlines).
  factory EmptyIllustrationPainter.themed(
    AknColors c, {
    required AknDrawing drawing,
  }) {
    final dark = c.isDark;
    final body = dark ? Color.lerp(c.surfaceRaised, c.ink, 0.07)! : c.surface;
    final outline = dark ? c.dim : Color.lerp(c.dim, c.ink, 0.22)!;
    return EmptyIllustrationPainter(
      drawing: drawing,
      stroke: outline,
      accent: c.logo,
      fill: body,
      shade: dark ? Color.lerp(body, c.ink, 0.12)! : c.line,
      faint: Color.lerp(c.lineStrong, c.surfaceAlt, dark ? 0.35 : 0.25),
      wheel: dark ? c.bg : Color.lerp(c.ink, c.dim, 0.3),
      accentSoft: dark ? c.brandSoft : c.brandLine,
    );
  }

  final AknDrawing drawing;

  /// The outline colour (graphite).
  final Color stroke;

  /// The orange accent (`logo`).
  final Color accent;

  /// Body colour of the objects; also hides lines behind tyres and hubs.
  final Color fill;

  /// Secondary fills: windows, hatches, the page fold, the back page.
  final Color shade;

  /// The ground line and text lines.
  final Color faint;

  /// Tyres.
  final Color wheel;

  /// Soft orange fills (the puddle under the drop).
  final Color accentSoft;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width / 96, size.height / 64);
    canvas.save();
    canvas.translate((size.width - 96 * s) / 2, (size.height - 64 * s) / 2);
    canvas.scale(s);
    final p = _Pens(this);
    switch (drawing) {
      case AknDrawing.tanker:
        _tanker(canvas, p);
      case AknDrawing.gauge:
        _gauge(canvas, p);
      case AknDrawing.nozzle:
        _nozzle(canvas, p);
      case AknDrawing.document:
        _document(canvas, p);
      case AknDrawing.routeGap:
        _routeGap(canvas, p);
      case AknDrawing.cloudSlash:
        _cloudSlash(canvas, p);
    }
    canvas.restore();
  }

  void _tanker(Canvas canvas, _Pens p) {
    canvas.drawLine(const Offset(5, 56), const Offset(91, 56), p.ground);
    // The manhole on top of the tank.
    p.shape(
      canvas,
      Path()..addRRect(
        RRect.fromLTRBR(20, 12.5, 33, 18, const Radius.circular(2.5)),
      ),
      p.shade,
    );
    // The tank.
    p.shape(
      canvas,
      Path()
        ..addRRect(RRect.fromLTRBR(7, 17, 61, 45.5, const Radius.circular(14))),
      p.body,
    );
    // A soft highlight along the tank's upper curve.
    canvas.drawLine(const Offset(18, 21.5), const Offset(50, 21.5), p.sheen);
    // The brand » on the tank.
    canvas.drawPath(
      Path()
        ..moveTo(27.5, 25.5)
        ..lineTo(32.5, 31)
        ..lineTo(27.5, 36.5)
        ..moveTo(35, 25.5)
        ..lineTo(40, 31)
        ..lineTo(35, 36.5),
      p.accentLine,
    );
    // The cab and its window.
    p.shape(
      canvas,
      Path()
        ..moveTo(61, 27)
        ..lineTo(73, 27)
        ..quadraticBezierTo(75.6, 27, 77.3, 29)
        ..lineTo(84.6, 37.4)
        ..quadraticBezierTo(86, 39, 86, 41)
        ..lineTo(86, 45.5)
        ..lineTo(61, 45.5)
        ..close(),
      p.body,
    );
    canvas.drawPath(
      Path()
        ..moveTo(65, 30.5)
        ..lineTo(72.4, 30.5)
        ..lineTo(78.4, 37.4)
        ..lineTo(65, 37.4)
        ..close(),
      p.shade,
    );
    // Headlight.
    canvas.drawCircle(const Offset(83.2, 41.6), 1.5, p.accentFill);
    // Tyres with their hubs.
    for (final x in const [21.0, 43.0, 75.0]) {
      final o = Offset(x, 50);
      canvas.drawCircle(o, 6, p.wheel);
      canvas.drawCircle(o, 6, p.line);
      canvas.drawCircle(o, 2, p.body);
    }
  }

  void _gauge(Canvas canvas, _Pens p) {
    const center = Offset(48, 44);
    canvas.drawLine(const Offset(10, 56), const Offset(86, 56), p.ground);
    // Stand.
    p.shape(
      canvas,
      Path()..addRRect(
        RRect.fromLTRBR(32, 50.5, 64, 56, const Radius.circular(2.75)),
      ),
      p.shade,
    );
    p.shape(
      canvas,
      Path()..addRect(const Rect.fromLTRB(44, 44, 52, 50.5)),
      p.shade,
    );
    // The dial face.
    final dial = Rect.fromCircle(center: center, radius: 31);
    p.shape(
      canvas,
      Path()
        ..moveTo(17, 44)
        ..arcTo(dial, math.pi, math.pi, false)
        ..close(),
      p.body,
    );
    // The scale: a soft track with the empty zone tinted.
    final scale = Rect.fromCircle(center: center, radius: 22);
    canvas.drawArc(scale, math.pi * 1.08, math.pi * 0.84, false, p.track);
    canvas.drawArc(scale, math.pi * 1.08, math.pi * 0.2, false, p.softTrack);
    for (var i = 0; i <= 4; i++) {
      final dir = Offset.fromDirection(math.pi + i * math.pi / 4);
      canvas.drawLine(center + dir * 26, center + dir * 28.5, p.line);
    }
    // The needle resting at zero.
    canvas.drawLine(
      center,
      center + Offset.fromDirection(math.pi + 0.34) * 21,
      p.accentLine,
    );
    canvas.drawCircle(center, 4.2, p.accentFill);
    canvas.drawCircle(center, 1.6, p.body);
  }

  void _nozzle(Canvas canvas, _Pens p) {
    canvas.drawLine(const Offset(6, 56), const Offset(90, 56), p.ground);
    // The puddle under the last drop.
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(14, 56), width: 14, height: 3.6),
      p.accentSoftFill,
    );
    // Hose down to the ground.
    canvas.drawPath(
      Path()
        ..moveTo(58, 27)
        ..cubicTo(72, 27, 82, 33, 82, 46)
        ..lineTo(82, 55),
      p.hose,
    );
    // Spout.
    p.shape(
      canvas,
      Path()
        ..moveTo(34, 23.5)
        ..lineTo(14.6, 30.4)
        ..quadraticBezierTo(13, 31, 13.6, 32.6)
        ..lineTo(14.4, 34.8)
        ..quadraticBezierTo(15, 36.4, 16.6, 35.8)
        ..lineTo(34, 31.5)
        ..close(),
      p.body,
    );
    // Trigger guard and lever.
    canvas.drawPath(
      Path()
        ..moveTo(40, 35)
        ..lineTo(40, 42)
        ..quadraticBezierTo(40, 46, 44, 46)
        ..lineTo(55, 46)
        ..quadraticBezierTo(58, 46, 58, 43)
        ..lineTo(58, 35),
      p.line,
    );
    canvas.drawLine(const Offset(46, 35), const Offset(50, 41), p.line);
    // Body with its orange grip band.
    final body = RRect.fromLTRBR(34, 19, 59, 35, const Radius.circular(4.5));
    canvas.drawRRect(body, p.body);
    canvas.save();
    canvas.clipRRect(body);
    canvas.drawRect(const Rect.fromLTRB(51, 19, 59, 35), p.accentFill);
    canvas.restore();
    canvas.drawRRect(body, p.line);
    // The last drop, with a tiny highlight.
    final drop = Path()
      ..moveTo(14, 40.5)
      ..quadraticBezierTo(18.4, 45.6, 18.4, 48.3)
      ..arcToPoint(const Offset(9.6, 48.3), radius: const Radius.circular(4.4))
      ..quadraticBezierTo(9.6, 45.6, 14, 40.5)
      ..close();
    canvas.drawPath(drop, p.accentFill);
    canvas.drawLine(const Offset(12, 47.4), const Offset(12.2, 48.8), p.glint);
  }

  void _document(Canvas canvas, _Pens p) {
    canvas.drawLine(const Offset(14, 61), const Offset(82, 61), p.ground);
    // The page behind.
    p.shape(
      canvas,
      Path()
        ..addRRect(RRect.fromLTRBR(36, 10, 74, 59, const Radius.circular(4.5))),
      p.shade,
    );
    // The front page with its folded corner.
    p.shape(
      canvas,
      Path()
        ..moveTo(57, 5)
        ..lineTo(31.5, 5)
        ..quadraticBezierTo(27, 5, 27, 9.5)
        ..lineTo(27, 52.5)
        ..quadraticBezierTo(27, 57, 31.5, 57)
        ..lineTo(62.5, 57)
        ..quadraticBezierTo(67, 57, 67, 52.5)
        ..lineTo(67, 15)
        ..close(),
      p.body,
    );
    p.shape(
      canvas,
      Path()
        ..moveTo(57, 5)
        ..lineTo(57, 12)
        ..quadraticBezierTo(57, 15, 60, 15)
        ..lineTo(67, 15)
        ..close(),
      p.shade,
    );
    canvas.drawLine(const Offset(34, 21), const Offset(48, 21), p.accentLine);
    canvas.drawLine(const Offset(34, 30), const Offset(60, 30), p.text);
    canvas.drawLine(const Offset(34, 38), const Offset(60, 38), p.text);
    canvas.drawLine(const Offset(34, 46), const Offset(51, 46), p.text);
  }

  void _routeGap(Canvas canvas, _Pens p) {
    const y = 40.0;
    canvas.drawLine(const Offset(5, 56), const Offset(91, 56), p.ground);
    // The way so far, then the break.
    canvas.drawLine(const Offset(12, y), const Offset(40, y), p.line);
    canvas.drawLine(const Offset(40, y), const Offset(43, y - 5), p.line);
    canvas.drawLine(const Offset(53, y + 5), const Offset(56, y), p.line);
    // Small debris over the gap.
    canvas.drawLine(
      const Offset(45.5, y - 9),
      const Offset(46.5, y - 12),
      p.text,
    );
    canvas.drawLine(
      const Offset(50, y - 7.5),
      const Offset(52.2, y - 10),
      p.text,
    );
    // The rest of the way, dotted, up to the destination pin.
    for (var x = 61.0; x < 75; x += 6.5) {
      canvas.drawLine(Offset(x, y), Offset(x + 2.5, y), p.text);
    }
    canvas.drawCircle(const Offset(9, y), 3.5, p.body);
    canvas.drawCircle(const Offset(9, y), 3.5, p.line);
    p.shape(
      canvas,
      Path()
        ..moveTo(82, y + 1)
        ..cubicTo(78, y - 3.5, 73.5, y - 7.4, 73.5, y - 12)
        ..arcToPoint(
          const Offset(90.5, y - 12),
          radius: const Radius.circular(8.5),
        )
        ..cubicTo(90.5, y - 7.4, 86, y - 3.5, 82, y + 1)
        ..close(),
      p.body,
    );
    canvas.drawCircle(const Offset(82, y - 12), 3, p.shade);
    canvas.drawCircle(const Offset(82, y - 12), 3, p.line);
    // The vehicle — the brand tile with its » — stopped before the gap.
    final tile = RRect.fromLTRBR(
      19,
      y - 7.5,
      34,
      y + 7.5,
      const Radius.circular(4),
    );
    canvas.drawRRect(tile, p.accentFill);
    canvas.drawPath(
      Path()
        ..moveTo(22.6, y - 3.6)
        ..lineTo(26, y)
        ..lineTo(22.6, y + 3.6)
        ..moveTo(27.2, y - 3.6)
        ..lineTo(30.6, y)
        ..lineTo(27.2, y + 3.6),
      p.tileGlyph,
    );
  }

  void _cloudSlash(Canvas canvas, _Pens p) {
    canvas.drawLine(const Offset(10, 58), const Offset(86, 58), p.ground);
    final cloud = Path()
      ..moveTo(26, 50.8)
      ..lineTo(69.2, 50.8)
      ..arcToPoint(
        const Offset(71.6, 27),
        radius: const Radius.circular(12),
        clockwise: false,
      )
      ..arcToPoint(
        const Offset(38, 22),
        radius: const Radius.circular(18),
        clockwise: false,
      )
      ..arcToPoint(
        const Offset(26, 50.8),
        radius: const Radius.circular(14.4),
        clockwise: false,
      )
      ..close();
    p.shape(canvas, cloud, p.body);
    // The slash cuts through the cloud's outline.
    canvas.save();
    canvas.clipPath(cloud);
    canvas.drawLine(
      const Offset(23.6, 11.2),
      const Offset(76.4, 56.8),
      p.knockout,
    );
    canvas.restore();
    canvas.drawLine(
      const Offset(23.6, 11.2),
      const Offset(76.4, 56.8),
      p.accentLine,
    );
  }

  @override
  bool shouldRepaint(EmptyIllustrationPainter old) =>
      old.drawing != drawing ||
      old.stroke != stroke ||
      old.accent != accent ||
      old.fill != fill ||
      old.shade != shade ||
      old.faint != faint ||
      old.wheel != wheel ||
      old.accentSoft != accentSoft;
}

/// The paints of one drawing.
class _Pens {
  _Pens(EmptyIllustrationPainter c)
    : line = _stroke(c.stroke, 2),
      hose = _stroke(c.stroke, 2.6),
      text = _stroke(c.faint, 2),
      ground = _stroke(c.faint, 2),
      accentLine = _stroke(c.accent, 2.4),
      track = _stroke(c.shade, 3),
      softTrack = _stroke(c.accentSoft, 3),
      knockout = _stroke(c.fill, 6),
      sheen = _stroke(c.shade.withValues(alpha: c.shade.a * 0.9), 1.6),
      glint = _stroke(c.fill.withValues(alpha: 0.85), 1.4),
      tileGlyph = _stroke(const Color(0xFFFFFFFF), 1.9),
      body = Paint()..color = c.fill,
      shade = Paint()..color = c.shade,
      wheel = Paint()..color = c.wheel,
      lineFill = Paint()..color = c.stroke,
      accentFill = Paint()..color = c.accent,
      accentSoftFill = Paint()..color = c.accentSoft;

  final Paint line;
  final Paint hose;
  final Paint text;
  final Paint ground;
  final Paint accentLine;
  final Paint track;
  final Paint softTrack;
  final Paint knockout;
  final Paint sheen;
  final Paint glint;
  final Paint tileGlyph;
  final Paint body;
  final Paint shade;
  final Paint wheel;
  final Paint lineFill;
  final Paint accentFill;
  final Paint accentSoftFill;

  static Paint _stroke(Color color, double width) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = color;

  /// Fills [path] with [fill], then outlines it.
  void shape(Canvas canvas, Path path, Paint fill) {
    canvas.drawPath(path, fill);
    canvas.drawPath(path, line);
  }
}

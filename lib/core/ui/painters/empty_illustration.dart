import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';

/// The six line drawings of design v2 §11 (96 × 64): one style only — 2 px
/// dim strokes, round caps and joins, no fills, no people, and exactly one
/// logo-orange detail.
enum AknDrawing {
  /// Parked tanker; the orange detail is the tank window (no orders).
  tanker,

  /// Empty gauge; the orange detail is the needle resting at zero (no
  /// statistics).
  gauge,

  /// Pump nozzle with a hose; the orange detail is the last drop (no
  /// deliveries).
  nozzle,

  /// A page with a folded corner; the orange detail is the title line (no
  /// files).
  document,

  /// A route with a gap; the orange detail is the » that stopped before it
  /// (errors).
  routeGap,

  /// A cloud with a slash; the orange detail is the slash (offline).
  cloudSlash,
}

/// Subjects of the empty and error states. Each one maps onto one of the six
/// [AknDrawing]s; [icon] is kept for callers that still show an icon.
enum AknIllustration {
  inbox(Icons.inbox_rounded, AknDrawing.tanker),
  search(Icons.search_off_rounded, AknDrawing.document),
  orders(Icons.receipt_long_rounded, AknDrawing.tanker),
  delivery(Icons.local_shipping_rounded, AknDrawing.nozzle),
  documents(Icons.folder_open_rounded, AknDrawing.document),
  approvals(Icons.task_alt_rounded, AknDrawing.document),
  notifications(Icons.notifications_none_rounded, AknDrawing.document),
  customers(Icons.groups_rounded, AknDrawing.tanker),
  payments(Icons.payments_rounded, AknDrawing.document),
  field(Icons.storefront_rounded, AknDrawing.tanker),
  offline(Icons.cloud_off_rounded, AknDrawing.cloudSlash),
  locked(Icons.lock_outline_rounded, AknDrawing.document),
  error(Icons.error_outline_rounded, AknDrawing.routeGap),
  done(Icons.check_circle_outline_rounded, AknDrawing.tanker),
  stats(Icons.speed_rounded, AknDrawing.gauge);

  const AknIllustration(this.icon, this.drawing);
  final IconData icon;
  final AknDrawing drawing;
}

/// A calm 96 × 64 line drawing for empty, error and offline states (§11).
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

  /// Deprecated: the drawings are always dim with one orange detail.
  final AknTone? tone;

  /// Draws this instead of the [subject]'s drawing.
  final AknDrawing? drawing;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AknColors>() ?? AknColors.light;
    return ExcludeSemantics(
      child: CustomPaint(
        size: Size(size, size * 64 / 96),
        painter: EmptyIllustrationPainter(
          drawing: drawing ?? subject.drawing,
          stroke: c.dim,
          accent: c.logo,
          fill: c.bg,
        ),
      ),
    );
  }
}

/// Paints one [AknDrawing] in the 96 × 64 grid, scaled to the canvas.
class EmptyIllustrationPainter extends CustomPainter {
  EmptyIllustrationPainter({
    required this.drawing,
    required this.stroke,
    required this.accent,
    required this.fill,
  });

  final AknDrawing drawing;

  /// The line colour (`dim`).
  final Color stroke;

  /// The one orange detail (`logo`).
  final Color accent;

  /// Page colour, used to hide lines behind wheels and hubs.
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final s = math.min(size.width / 96, size.height / 64);
    canvas.save();
    canvas.translate((size.width - 96 * s) / 2, (size.height - 64 * s) / 2);
    canvas.scale(s);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = stroke;
    final detail = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = accent;
    final hide = Paint()..color = fill;
    switch (drawing) {
      case AknDrawing.tanker:
        _tanker(canvas, line, detail, hide);
      case AknDrawing.gauge:
        _gauge(canvas, line, detail, hide);
      case AknDrawing.nozzle:
        _nozzle(canvas, line, detail);
      case AknDrawing.document:
        _document(canvas, line, detail);
      case AknDrawing.routeGap:
        _routeGap(canvas, line, detail, hide);
      case AknDrawing.cloudSlash:
        _cloudSlash(canvas, line, detail);
    }
    canvas.restore();
  }

  void _tanker(Canvas canvas, Paint line, Paint detail, Paint hide) {
    canvas.drawRRect(
      RRect.fromLTRBR(6, 18, 62, 46, const Radius.circular(14)),
      line,
    );
    canvas.drawPath(
      Path()
        ..moveTo(62, 28)
        ..lineTo(76, 28)
        ..lineTo(86, 38)
        ..lineTo(86, 46)
        ..lineTo(62, 46)
        ..close(),
      line,
    );
    canvas.drawLine(const Offset(4, 56), const Offset(92, 56), line);
    for (final x in const [22.0, 46.0, 76.0]) {
      canvas.drawCircle(Offset(x, 50), 6, hide);
      canvas.drawCircle(Offset(x, 50), 6, line);
    }
    canvas.drawRRect(
      RRect.fromLTRBR(26, 26, 42, 38, const Radius.circular(2)),
      detail,
    );
  }

  void _gauge(Canvas canvas, Paint line, Paint detail, Paint hide) {
    const center = Offset(48, 46);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 30),
      math.pi,
      math.pi,
      false,
      line,
    );
    // Five ticks along the dial.
    for (var i = 0; i <= 4; i++) {
      final dir = Offset.fromDirection(math.pi + i * math.pi / 4);
      canvas.drawLine(center + dir * 23, center + dir * 27, line);
    }
    canvas.drawLine(const Offset(14, 56), const Offset(82, 56), line);
    // Needle resting at zero.
    canvas.drawLine(
      center,
      center + Offset.fromDirection(math.pi + 0.26) * 20,
      detail,
    );
    canvas.drawCircle(center, 3.5, hide);
    canvas.drawCircle(center, 3.5, line);
  }

  void _nozzle(Canvas canvas, Paint line, Paint detail) {
    // Spout.
    canvas.drawPath(
      Path()
        ..moveTo(34, 24)
        ..lineTo(14, 31)
        ..lineTo(16, 36)
        ..lineTo(34, 31),
      line,
    );
    // Body.
    canvas.drawRRect(
      RRect.fromLTRBR(34, 19, 58, 35, const Radius.circular(4)),
      line,
    );
    // Trigger guard and lever.
    canvas.drawPath(
      Path()
        ..moveTo(40, 35)
        ..lineTo(40, 42)
        ..quadraticBezierTo(40, 46, 44, 46)
        ..lineTo(56, 46)
        ..quadraticBezierTo(58, 46, 58, 44)
        ..lineTo(58, 35),
      line,
    );
    canvas.drawLine(const Offset(46, 35), const Offset(50, 41), line);
    // Hose down to the ground.
    canvas.drawPath(
      Path()
        ..moveTo(58, 27)
        ..cubicTo(72, 27, 82, 33, 82, 46)
        ..lineTo(82, 56),
      line,
    );
    canvas.drawLine(const Offset(8, 56), const Offset(90, 56), line);
    // The last drop.
    canvas.drawPath(
      Path()
        ..moveTo(14, 41)
        ..quadraticBezierTo(18, 46, 18, 48.5)
        ..arcToPoint(const Offset(10, 48.5), radius: const Radius.circular(4))
        ..quadraticBezierTo(10, 46, 14, 41)
        ..close(),
      detail,
    );
  }

  void _document(Canvas canvas, Paint line, Paint detail) {
    canvas.drawPath(
      Path()
        ..moveTo(58, 6)
        ..lineTo(32, 6)
        ..quadraticBezierTo(28, 6, 28, 10)
        ..lineTo(28, 54)
        ..quadraticBezierTo(28, 58, 32, 58)
        ..lineTo(64, 58)
        ..quadraticBezierTo(68, 58, 68, 54)
        ..lineTo(68, 16)
        ..close(),
      line,
    );
    canvas.drawPath(
      Path()
        ..moveTo(58, 6)
        ..lineTo(58, 13)
        ..quadraticBezierTo(58, 16, 61, 16)
        ..lineTo(68, 16),
      line,
    );
    canvas.drawLine(const Offset(35, 21), const Offset(49, 21), detail);
    canvas.drawLine(const Offset(35, 30), const Offset(61, 30), line);
    canvas.drawLine(const Offset(35, 38), const Offset(61, 38), line);
    canvas.drawLine(const Offset(35, 46), const Offset(52, 46), line);
  }

  void _routeGap(Canvas canvas, Paint line, Paint detail, Paint hide) {
    const y = 36.0;
    canvas.drawLine(const Offset(14, y), const Offset(40, y), line);
    // The break.
    canvas.drawLine(const Offset(40, y), const Offset(43, y - 5), line);
    canvas.drawLine(const Offset(53, y + 5), const Offset(56, y), line);
    // The rest of the way, dashed.
    for (var x = 60.0; x < 78; x += 7) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 3, 78), y), line);
    }
    canvas.drawCircle(const Offset(10, y), 4, hide);
    canvas.drawCircle(const Offset(10, y), 4, line);
    canvas.drawCircle(const Offset(84, y), 4.5, hide);
    canvas.drawCircle(const Offset(84, y), 4.5, line);
    // The » that stopped before the gap.
    canvas.drawPath(
      Path()
        ..moveTo(21, y - 13)
        ..lineTo(26, y - 8)
        ..lineTo(21, y - 3)
        ..moveTo(28, y - 13)
        ..lineTo(33, y - 8)
        ..lineTo(28, y - 3),
      detail,
    );
    canvas.drawLine(const Offset(6, 52), const Offset(90, 52), line);
  }

  void _cloudSlash(Canvas canvas, Paint line, Paint detail) {
    canvas.drawPath(
      Path()
        ..moveTo(30, 48)
        ..lineTo(66, 48)
        ..arcToPoint(
          const Offset(68, 28.2),
          radius: const Radius.circular(10),
          clockwise: false,
        )
        ..arcToPoint(
          const Offset(40, 24),
          radius: const Radius.circular(15),
          clockwise: false,
        )
        ..arcToPoint(
          const Offset(30, 48),
          radius: const Radius.circular(12),
          clockwise: false,
        )
        ..close(),
      line,
    );
    canvas.drawLine(const Offset(24, 12), const Offset(74, 58), detail);
  }

  @override
  bool shouldRepaint(EmptyIllustrationPainter old) =>
      old.drawing != drawing ||
      old.stroke != stroke ||
      old.accent != accent ||
      old.fill != fill;
}

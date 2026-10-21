import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../tokens.dart';
import 'logo_mark.dart';

/// Subjects of the calm line illustrations used by empty and error states.
enum AknIllustration {
  inbox(Icons.inbox_rounded),
  search(Icons.search_off_rounded),
  orders(Icons.receipt_long_rounded),
  delivery(Icons.local_shipping_rounded),
  documents(Icons.folder_open_rounded),
  approvals(Icons.task_alt_rounded),
  notifications(Icons.notifications_none_rounded),
  customers(Icons.groups_rounded),
  payments(Icons.payments_rounded),
  field(Icons.storefront_rounded),
  offline(Icons.cloud_off_rounded),
  locked(Icons.lock_outline_rounded),
  error(Icons.error_outline_rounded),
  done(Icons.check_circle_outline_rounded);

  const AknIllustration(this.icon);
  final IconData icon;
}

/// Soft disc + orbit with three dots + the subject icon + a small » accent.
/// Decorative (excluded from semantics).
class EmptyIllustration extends StatelessWidget {
  const EmptyIllustration({
    super.key,
    this.subject = AknIllustration.inbox,
    this.size = 112,
    this.tone,
  });

  final AknIllustration subject;
  final double size;

  /// Tints the disc and icon (danger for errors, ok for done). Null = slate.
  final AknTone? tone;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AknColors>() ?? AknColors.light;
    final t = tone == null ? null : c.tone(tone!);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: EmptyIllustrationPainter(
            disc: t?.bg ?? c.surfaceAlt,
            ring: t?.line ?? c.line,
            dot: c.lineStrong,
            accent: c.logo,
            inner: c.surface,
          ),
          child: Center(
            child: Icon(subject.icon, size: size * 0.34, color: t?.fg ?? c.dim),
          ),
        ),
      ),
    );
  }
}

class EmptyIllustrationPainter extends CustomPainter {
  EmptyIllustrationPainter({
    required this.disc,
    required this.ring,
    required this.dot,
    required this.accent,
    required this.inner,
  });

  final Color disc;
  final Color ring;
  final Color dot;
  final Color accent;
  final Color inner;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r * 0.86, Paint()..color = disc);
    canvas.drawCircle(c, r * 0.56, Paint()..color = inner);
    canvas.drawCircle(
      c,
      r * 0.56,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = ring,
    );
    // Orbit arc with three dots.
    final orbit = Rect.fromCircle(center: c, radius: r * 0.97);
    canvas.drawArc(
      orbit,
      math.pi * 0.95,
      math.pi * 0.55,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..color = ring,
    );
    for (final (a, col, rr) in [
      (math.pi * 0.95, dot, 2.6),
      (math.pi * 1.22, dot, 2.0),
      (math.pi * 1.5, accent, 3.0),
    ]) {
      canvas.drawCircle(
        Offset(c.dx + r * 0.97 * math.cos(a), c.dy + r * 0.97 * math.sin(a)),
        rr,
        Paint()..color = col,
      );
    }
    // Small » accent at the lower right.
    final s = r * 0.32 / 80;
    canvas.save();
    canvas.translate(c.dx + r * 0.5, c.dy + r * 0.42);
    canvas.scale(s);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = accent;
    canvas.drawPath(LogoMarkPainter.chevronPath(0), stroke);
    canvas.drawPath(LogoMarkPainter.chevronPath(1), stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(EmptyIllustrationPainter old) =>
      old.disc != disc ||
      old.ring != ring ||
      old.dot != dot ||
      old.accent != accent ||
      old.inner != inner;
}

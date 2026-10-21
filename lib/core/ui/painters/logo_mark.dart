import 'package:flutter/material.dart';

import '../motion.dart';
import '../tokens.dart';
import 'path_trim.dart';

/// The AkaryakıtNet mark: white » chevrons in the orange rounded square
/// (`assets/brand/akaryakitnet-symbol.svg`, drawn as vectors).
///
/// [progress] draws the chevrons in along their strokes (0 = none, 1 = full);
/// the second chevron trails the first. With [animate] the mark draws itself
/// in once (500 ms) when first shown; reduce motion shows it complete.
class LogoMark extends StatefulWidget {
  const LogoMark({
    super.key,
    this.size = 48,
    this.progress,
    this.animate = false,
    this.duration = const Duration(milliseconds: 500),
    this.showTile = true,
    this.chevronColor,
    this.tileColor,
    this.trackOpacity = 0,
    this.semanticLabel = 'AkaryakıtNet',
  });

  final double size;

  /// Externally driven draw-in progress; overrides [animate].
  final double? progress;
  final bool animate;
  final Duration duration;

  /// Draw the orange tile; false draws only the chevrons.
  final bool showTile;
  final Color? chevronColor;
  final Color? tileColor;

  /// Opacity of the undrawn part of the chevrons (a faint track).
  final double trackOpacity;

  /// Null hides the mark from screen readers (decorative use).
  final String? semanticLabel;

  @override
  State<LogoMark> createState() => _LogoMarkState();
}

class _LogoMarkState extends State<LogoMark>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.progress == null && widget.animate && _c == null) {
      _c = AnimationController(vsync: this, duration: widget.duration);
      if (AknMotion.reduced(context)) {
        _c!.value = 1;
      } else {
        _c!.forward();
      }
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AknColors>() ?? AknColors.light;
    Widget paint(double p) => CustomPaint(
      size: Size.square(widget.size),
      painter: LogoMarkPainter(
        progress: p,
        showTile: widget.showTile,
        tileColor: widget.tileColor ?? c.logo,
        chevronColor:
            widget.chevronColor ??
            (widget.showTile ? const Color(0xFFFFFFFF) : c.logo),
        trackOpacity: widget.trackOpacity,
      ),
    );
    final controller = _c;
    final Widget mark = widget.progress != null
        ? paint(widget.progress!)
        : controller == null
        ? paint(1)
        : AnimatedBuilder(
            animation: controller,
            builder: (context, _) =>
                paint(AknMotion.emphasizedCurve.transform(controller.value)),
          );
    final label = widget.semanticLabel;
    if (label == null) return ExcludeSemantics(child: mark);
    return Semantics(label: label, image: true, child: mark);
  }
}

/// Paints the mark at any size from the 80×80 SVG geometry.
class LogoMarkPainter extends CustomPainter {
  LogoMarkPainter({
    required this.progress,
    required this.showTile,
    required this.tileColor,
    required this.chevronColor,
    this.trackOpacity = 0,
  });

  final double progress;
  final bool showTile;
  final Color tileColor;
  final Color chevronColor;
  final double trackOpacity;

  /// Chevron paths in the 80-unit SVG space.
  static Path chevronPath(int index) {
    final dx = index == 0 ? 0.0 : 19.6;
    return Path()
      ..moveTo(22 + dx, 23.5)
      ..lineTo(38.3 + dx, 39.8)
      ..lineTo(22 + dx, 56.1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 80;
    canvas.save();
    canvas.translate((size.width - 80 * s) / 2, (size.height - 80 * s) / 2);
    canvas.scale(s);
    if (showTile) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(2, 2, 76, 76),
          const Radius.circular(18),
        ),
        Paint()..color = tileColor,
      );
    }
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = chevronColor;
    final p = progress.clamp(0.0, 1.0);
    for (var i = 0; i < 2; i++) {
      final path = chevronPath(i);
      // The second chevron trails the first by 30 % of the sweep.
      final local = i == 0
          ? (p / 0.7).clamp(0.0, 1.0)
          : ((p - 0.3) / 0.7).clamp(0.0, 1.0);
      if (trackOpacity > 0 && local < 1) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 9.8
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = chevronColor.withValues(
              alpha: chevronColor.a * trackOpacity,
            ),
        );
      }
      if (local <= 0) continue;
      if (local >= 1) {
        canvas.drawPath(path, stroke);
        continue;
      }
      final partial = trimPath(path, local);
      canvas.drawPath(partial, stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LogoMarkPainter old) =>
      old.progress != progress ||
      old.showTile != showTile ||
      old.tileColor != tileColor ||
      old.chevronColor != chevronColor ||
      old.trackOpacity != trackOpacity;
}

/// "Akaryakıt**Net**" wordmark. On navy (or dark) "Akaryakıt" is white; on
/// light surfaces it is the brand navy. "Net" is always the logo orange.
class AknWordmark extends StatelessWidget {
  const AknWordmark({
    super.key,
    this.fontSize = 24,
    this.onDark,
    this.semanticLabel = 'AkaryakıtNet',
  });

  final double fontSize;

  /// Force the light-on-dark variant; defaults to the theme brightness.
  final bool? onDark;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AknColors>() ?? AknColors.light;
    final dark = onDark ?? c.isDark;
    final base = TextStyle(
      fontSize: fontSize,
      height: 1.15,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.02 * fontSize,
      color: dark ? const Color(0xFFFFFFFF) : const Color(0xFF202E3D),
    );
    final text = Text.rich(
      TextSpan(
        text: 'Akaryakıt',
        style: base,
        children: [
          TextSpan(
            text: 'Net',
            style: base.copyWith(color: c.logo),
          ),
        ],
      ),
      maxLines: 1,
      softWrap: false,
      textScaler: TextScaler.noScaling,
    );
    final label = semanticLabel;
    if (label == null) return ExcludeSemantics(child: text);
    return Semantics(label: label, excludeSemantics: true, child: text);
  }
}

/// Mark + wordmark lock-up (login header, about screen).
class AknLogo extends StatelessWidget {
  const AknLogo({
    super.key,
    this.markSize = 40,
    this.onDark,
    this.animate = false,
  });

  final double markSize;
  final bool? onDark;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'AkaryakıtNet',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LogoMark(size: markSize, animate: animate, semanticLabel: null),
            SizedBox(width: markSize * 0.3),
            AknWordmark(
              fontSize: markSize * 0.56,
              onDark: onDark,
              semanticLabel: null,
            ),
          ],
        ),
      ),
    );
  }
}

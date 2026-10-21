import 'dart:ui';

/// The first [t] (0..1) of [path]'s length, for draw-in animations.
Path trimPath(Path path, double t) {
  if (t >= 1) return path;
  final out = Path();
  if (t <= 0) return out;
  final metrics = path.computeMetrics().toList();
  final total = metrics.fold<double>(0, (a, m) => a + m.length);
  var remaining = total * t;
  for (final PathMetric m in metrics) {
    if (remaining <= 0) break;
    final len = remaining.clamp(0.0, m.length);
    out.addPath(m.extractPath(0, len), Offset.zero);
    remaining -= len;
  }
  return out;
}

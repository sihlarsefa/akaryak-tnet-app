import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/ui/ui.dart';

/// İki seçenekli kayan anahtar ("Şifre ile" / "Numara ile"), tasarım v3: hap biçimli kuyu (`surfaceAlt`)
/// üstünde beyaz, gölgeli bir başparmak. Seçim değişince başparmak "akar": gidilen yöndeki kenarı önden
/// koşar, arkadaki kenarı biraz geriden yay eğrisiyle yetişir (kısa bir esneme, varınca bir an daralıp
/// yerine oturma; kuyunun dışına taşmaz). Seçilen bölümün etiketi kalınlaşır ve Pas'a döner; simge
/// verilirse (v4 girişte verilmez) o da turuncuya döner ve hafifçe zıplar. Her bölüm en az 48 dp; seçili
/// bölüm sesli okumada "seçili" duyurulur, ayrıca kalın yazı ve beyaz zeminle ayrılır (yalnızca renk değil).
class ModeSwitch<T> extends StatefulWidget {
  const ModeSwitch({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  final List<({T value, String label, IconData? icon})> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String? semanticLabel;

  @override
  State<ModeSwitch<T>> createState() => _ModeSwitchState<T>();
}

class _ModeSwitchState<T> extends State<ModeSwitch<T>>
    with SingleTickerProviderStateMixin {
  static const double _pad = 4;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AknMotion.needle,
    value: 1,
  );

  /// Başparmağın kenarları (bölüm biriminde: 0 = ilk bölümün solu).
  late double _fromLeft = _index.toDouble();
  late double _fromRight = _fromLeft + 1;

  int get _index =>
      math.max(0, widget.options.indexWhere((o) => o.value == widget.value));

  /// Önden koşan kenar: hızlı ve taşmasız.
  static const _lead = Interval(0, 0.7, curve: Curves.easeOutCubic);

  /// Geriden yetişen kenar: yay eğrisiyle ([AknMotion.spring]) hedefini biraz geçip geri oturur —
  /// başparmak varınca bir an daralıp yaylanır; taşma hep kuyunun içine doğrudur.
  static const _trail = Interval(0.14, 1, curve: AknMotion.spring);

  /// Şu anki kenarlar.
  (double, double) get _edges => _edgesAt(_index.toDouble(), _c.value);

  /// [to] bölümüne giderken [t] anındaki kenarlar (bölüm biriminde), kuyunun içinde ve en az 0,2
  /// bölüm genişliğinde.
  (double, double) _edgesAt(double to, double t) {
    final n = widget.options.length.toDouble();
    if (n <= 0) return (0, 0);
    final right = to >= _fromLeft;
    final l =
        _fromLeft + (to - _fromLeft) * (right ? _trail : _lead).transform(t);
    final r =
        _fromRight +
        (to + 1 - _fromRight) * (right ? _lead : _trail).transform(t);
    final left = l.clamp(0.0, math.max(0.0, n - 0.2)).toDouble();
    return (left, r.clamp(left + 0.2, math.max(left + 0.2, n)).toDouble());
  }

  @override
  void didUpdateWidget(ModeSwitch<T> old) {
    super.didUpdateWidget(old);
    if (old.value == widget.value) return;
    // Eski hedefe göre şu anki kenarlardan başla (kesintide sıçrama yok).
    final oldIndex = math.max(
      0,
      old.options.indexWhere((o) => o.value == old.value),
    );
    final (left, right) = _edgesAt(oldIndex.toDouble(), _c.value);
    _fromLeft = left;
    _fromRight = right;
    _c.value = 0;
    AknMotion.animateTo(context, _c, 1, curve: Curves.linear);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _select(int i) {
    final v = widget.options[i].value;
    if (v == widget.value) return;
    AknHaptics.selection();
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final n = widget.options.length;
    final index = widget.options.indexWhere((o) => o.value == widget.value);
    final duration = AknMotion.of(context, AknMotion.base);
    final thumb = c.isDark
        ? Color.lerp(c.surfaceRaised, c.ink, 0.07)!
        : c.surface;
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: AknRadius.pillAll,
          border: c.isDark ? Border.all(color: c.line) : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(_pad),
          child: Stack(
            children: [
              if (index >= 0 && n > 0)
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _ThumbPainter(
                        repaint: _c,
                        edges: () => _edges,
                        count: n,
                        color: thumb,
                        shadows: AknShadows.card(c),
                        border: c.isDark ? c.line : null,
                        rtl: Directionality.of(context) == TextDirection.rtl,
                      ),
                    ),
                  ),
                ),
              Row(
                children: [
                  for (var i = 0; i < n; i++)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: i == index,
                        inMutuallyExclusiveGroup: true,
                        label: widget.options[i].label,
                        excludeSemantics: true,
                        onTap: i == index ? null : () => _select(i),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _select(i),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: AknSpace.minTap,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (widget.options[i].icon
                                      case final IconData icon) ...[
                                    _PopIcon(
                                      icon: icon,
                                      selected: i == index,
                                      color: i == index ? c.brand : c.dim,
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Flexible(
                                    child: AnimatedDefaultTextStyle(
                                      duration: duration,
                                      curve: AknMotion.standard,
                                      style: t.label.copyWith(
                                        fontSize: 14,
                                        height: 20 / 14,
                                        // Seçili: panelin "buradasınız"ı (Pas); dim,
                                        // surfaceAlt üzerinde AA.
                                        color: i == index ? c.brandInk : c.dim,
                                        fontWeight: i == index
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                      ),
                                      child: Text(
                                        widget.options[i].label,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Başparmağı boyar (her karede yalnızca boya; yerleşim değişmez): yuvarlak hap, kart gölgesi.
class _ThumbPainter extends CustomPainter {
  _ThumbPainter({
    required Listenable repaint,
    required this.edges,
    required this.count,
    required this.color,
    required this.shadows,
    required this.border,
    required this.rtl,
  }) : super(repaint: repaint);

  final (double, double) Function() edges;
  final int count;
  final Color color;
  final List<BoxShadow> shadows;
  final Color? border;
  final bool rtl;

  @override
  void paint(Canvas canvas, Size size) {
    final slot = size.width / count;
    var (l, r) = edges();
    if (rtl) (l, r) = (count - r, count - l);
    final rect = Rect.fromLTRB(l * slot, 0, r * slot, size.height);
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(size.height / 2),
    );
    for (final s in shadows) {
      canvas.drawRRect(
        rrect.shift(s.offset).inflate(s.spreadRadius),
        s.toPaint(),
      );
    }
    canvas.drawRRect(rrect, Paint()..color = color);
    if (border != null) {
      canvas.drawRRect(
        rrect.deflate(0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = border!,
      );
    }
  }

  @override
  bool shouldRepaint(_ThumbPainter old) =>
      old.color != color ||
      old.count != count ||
      old.border != border ||
      old.rtl != rtl ||
      !listEquals(old.shadows, shadows);
}

/// Seçilince bir kez zıplayan simge (1 → 1,2 → 1, [AknMotion.pop]); renk yumuşakça geçer.
class _PopIcon extends StatefulWidget {
  const _PopIcon({
    required this.icon,
    required this.selected,
    required this.color,
  });

  final IconData icon;
  final bool selected;
  final Color color;

  @override
  State<_PopIcon> createState() => _PopIconState();
}

class _PopIconState extends State<_PopIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 360),
    value: 1,
  );

  @override
  void didUpdateWidget(_PopIcon old) {
    super.didUpdateWidget(old);
    if (widget.selected && !old.selected && !AknMotion.reduced(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: widget.color),
      duration: AknMotion.of(context, AknMotion.base),
      builder: (context, color, _) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Transform.scale(
          scale: 1 + 0.2 * math.sin(math.pi * _c.value),
          child: Icon(widget.icon, size: 18, color: color),
        ),
      ),
    );
  }
}

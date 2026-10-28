import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../ui/driver_mode.dart';
import '../ui/motion.dart';
import '../ui/theme.dart';
import '../ui/tokens.dart';

/// İmza çizgileri ve dışa aktarma.
class SignaturePadController extends ChangeNotifier {
  final List<List<Offset>> _strokes = [];
  Size _size = Size.zero;

  List<List<Offset>> get strokes => List.unmodifiable(_strokes);

  /// Anlamlı bir imza var mı (en az bir çizgi ve birkaç nokta).
  bool get isEmpty => _strokes.fold<int>(0, (n, s) => n + s.length) < 6;

  void _start(Offset p) {
    _strokes.add([p]);
    notifyListeners();
  }

  void _extend(Offset p) {
    if (_strokes.isEmpty) return;
    _strokes.last.add(p);
    notifyListeners();
  }

  void undo() {
    if (_strokes.isNotEmpty) {
      _strokes.removeLast();
      notifyListeners();
    }
  }

  void clear() {
    _strokes.clear();
    notifyListeners();
  }

  /// İmzayı PNG olarak verir (varsayılan 2×, beyaz zemin, grafit mürekkep). Boşsa null.
  Future<Uint8List?> toPng({
    double pixelRatio = 2,
    Color ink = const Color(0xFF15171A),
    Color? background = Colors.white,
  }) async {
    if (isEmpty || _size.isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(pixelRatio);
    if (background != null) {
      canvas.drawRect(Offset.zero & _size, Paint()..color = background);
    }
    _SignaturePainter.paintStrokes(canvas, _strokes, ink, 2.6);
    final image = await recorder.endRecording().toImage(
      (_size.width * pixelRatio).round(),
      (_size.height * pixelRatio).round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }
}

/// İmza alanı (spec C.4): parmakla çizilir, "Temizle" ve "Geri al" ile düzeltilir; PNG 2× dışa aktarılır.
///
/// Tasarım v3: beyaz kart (r16, 1,5 px çizgi); çizerken kenarlık turuncuya döner ve yumuşak turuncu bir
/// hale belirir (giriş alanı odağı gibi). Boşken ortada kalem simgesi ve ipucu, altta "×" işaretli
/// kesikli imza çizgisi; ilk çizgiyle ipucu söner, "Geri al" ve "Temizle" yaylanarak belirir. Pedin
/// içindeki ipucu, çizgi, düğmeler ve mürekkep zeminin rengine uyar: koyu temada beyaz "kâğıt" ped de
/// okunur kalır.
class SignaturePad extends StatefulWidget {
  const SignaturePad({
    super.key,
    required this.controller,
    this.height = 200,
    this.hint = 'Teslim alan kişi burada imzalasın',
    this.ink,
    this.background,
    this.borderColor,
  });

  final SignaturePadController controller;
  final double height;
  final String hint;
  final Color? ink;
  final Color? background;
  final Color? borderColor;

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  bool _drawing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(SignaturePad old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  void _setDrawing(bool v) {
    if (_drawing != v) setState(() => _drawing = v);
  }

  /// The palette of the pad's own chrome (hint, signing line, buttons, ink):
  /// it follows the pad's [background], so a white "paper" pad keeps dark,
  /// readable chrome in dark mode.
  static AknColors _padPalette(AknColors c, Color background) {
    final light =
        ThemeData.estimateBrightnessForColor(background) == Brightness.light;
    if (light == !c.isDark) return c;
    return light ? AknColors.light : AknColors.dark;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final background = widget.background ?? c.surface;
    final p = _padPalette(c, background);
    final ink = widget.ink ?? p.ink;
    final ctl = widget.controller;
    final empty = ctl.strokes.isEmpty;
    final fast = AknMotion.of(context, AknMotion.fast);
    return Semantics(
      label: 'İmza alanı',
      hint: ctl.isEmpty ? 'İmza atılmadı' : 'İmza atıldı',
      child: AnimatedContainer(
        duration: fast,
        curve: AknMotion.standard,
        height: widget.height,
        decoration: BoxDecoration(
          color: background,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          border: Border.all(
            color: _drawing ? c.brand : (widget.borderColor ?? c.line),
            width: _drawing ? 2 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _drawing ? c.brandSoft : c.brandSoft.withValues(alpha: 0),
              spreadRadius: 4,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, box) {
            ctl._size = Size(box.maxWidth, box.maxHeight);
            return Stack(
              children: [
                // The signing line: dashed, with the "×" where to start.
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 34,
                  height: 14,
                  child: CustomPaint(
                    painter: _BaselinePainter(
                      line: p.lineStrong.withValues(alpha: 0.7),
                      cross: p.dim,
                    ),
                  ),
                ),
                IgnorePointer(
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: empty ? 1 : 0,
                      duration: AknMotion.of(context, AknMotion.base),
                      child: AnimatedScale(
                        scale: empty ? 1 : 0.94,
                        duration: AknMotion.of(context, AknMotion.base),
                        curve: AknMotion.standard,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                PhosphorIconsRegular.signature,
                                size: 26,
                                color: p.dim,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                widget.hint,
                                textAlign: TextAlign.center,
                                style: t.bodySmall.copyWith(color: p.dim),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) {
                    HapticFeedback.selectionClick();
                    _setDrawing(true);
                    ctl._start(d.localPosition);
                  },
                  onPanUpdate: (d) => ctl._extend(d.localPosition),
                  onPanEnd: (_) => _setDrawing(false),
                  onPanCancel: () => _setDrawing(false),
                  child: CustomPaint(
                    painter: _SignaturePainter(ctl.strokes, ink),
                    size: Size.infinite,
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: AnimatedOpacity(
                    opacity: empty ? 0.45 : 1,
                    duration: AknMotion.of(context, AknMotion.base),
                    child: AnimatedScale(
                      scale: empty ? 0.92 : 1,
                      duration: AknMotion.of(context, AknMotion.pressOut),
                      curve: AknMotion.spring,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PadAction(
                            tooltip: 'Geri al',
                            icon: PhosphorIconsRegular.arrowUUpLeft,
                            palette: p,
                            onPressed: empty ? null : ctl.undo,
                          ),
                          _PadAction(
                            tooltip: 'Temizle',
                            icon: PhosphorIconsRegular.trash,
                            palette: p,
                            onPressed: empty ? null : ctl.clear,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A round 40 px well button (48 px target; 64 in driver mode) in the pad's
/// corner, in the pad's [palette].
class _PadAction extends StatelessWidget {
  const _PadAction({
    required this.tooltip,
    required this.icon,
    required this.palette,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final AknColors palette;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = palette;
    final target = AknDriverMode.maybeOf(context)?.minTap ?? AknSpace.minTap;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed == null
          ? null
          : () {
              AknHaptics.light();
              onPressed!();
            },
      constraints: BoxConstraints(minWidth: target, minHeight: target),
      style: IconButton.styleFrom(
        backgroundColor: c.surfaceAlt,
        disabledBackgroundColor: c.surfaceAlt,
        foregroundColor: c.ink,
        disabledForegroundColor: c.faint,
        fixedSize: const Size(40, 40),
        minimumSize: const Size(40, 40),
        shape: const CircleBorder(),
      ),
      icon: Icon(icon, size: 20),
    );
  }
}

/// The dashed signing line with a small "×" at its start.
class _BaselinePainter extends CustomPainter {
  _BaselinePainter({required this.line, required this.cross});

  final Color line;
  final Color cross;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height - 1;
    final dash = Paint()
      ..color = line
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var x = 22.0; x < size.width; x += 9) {
      canvas.drawLine(Offset(x, y), Offset(x + 4, y), dash);
    }
    final x = Paint()
      ..color = cross
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(2, y - 10), Offset(12, y), x);
    canvas.drawLine(Offset(12, y - 10), Offset(2, y), x);
  }

  @override
  bool shouldRepaint(_BaselinePainter old) =>
      old.line != line || old.cross != cross;
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes, this.ink);
  final List<List<Offset>> strokes;
  final Color ink;

  static void paintStrokes(
    Canvas canvas,
    List<List<Offset>> strokes,
    Color ink,
    double width,
  ) {
    final paint = Paint()
      ..color = ink
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    for (final s in strokes) {
      if (s.isEmpty) continue;
      if (s.length == 1) {
        canvas.drawCircle(
          s.first,
          width / 2,
          paint..style = PaintingStyle.fill,
        );
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (var i = 1; i < s.length - 1; i++) {
        final mid = Offset(
          (s[i].dx + s[i + 1].dx) / 2,
          (s[i].dy + s[i + 1].dy) / 2,
        );
        path.quadraticBezierTo(s[i].dx, s[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(s.last.dx, s.last.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  void paint(Canvas canvas, Size size) =>
      paintStrokes(canvas, strokes, ink, 2.6);

  @override
  bool shouldRepaint(_SignaturePainter old) => true;
}

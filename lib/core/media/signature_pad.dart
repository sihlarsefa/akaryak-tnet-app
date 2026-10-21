import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  /// İmzayı PNG olarak verir (varsayılan 2×, beyaz zemin, koyu mürekkep). Boşsa null.
  Future<Uint8List?> toPng({
    double pixelRatio = 2,
    Color ink = const Color(0xFF0F172A),
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = widget.ink ?? scheme.onSurface;
    final c = widget.controller;
    return Semantics(
      label: 'İmza alanı',
      hint: c.isEmpty ? 'İmza atılmadı' : 'İmza atıldı',
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          color: widget.background ?? scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.borderColor ?? scheme.outlineVariant,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, box) {
            c._size = Size(box.maxWidth, box.maxHeight);
            return Stack(
              children: [
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 40,
                  child: Container(height: 1, color: scheme.outlineVariant),
                ),
                if (c.strokes.isEmpty)
                  Center(
                    child: Text(
                      widget.hint,
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) {
                    HapticFeedback.selectionClick();
                    c._start(d.localPosition);
                  },
                  onPanUpdate: (d) => c._extend(d.localPosition),
                  child: CustomPaint(
                    painter: _SignaturePainter(c.strokes, ink),
                    size: Size.infinite,
                  ),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Geri al',
                        onPressed: c.strokes.isEmpty ? null : c.undo,
                        icon: const Icon(Icons.undo_rounded),
                      ),
                      IconButton(
                        tooltip: 'Temizle',
                        onPressed: c.strokes.isEmpty ? null : c.clear,
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ],
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

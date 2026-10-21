import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/enums.dart';

/// Çek / senet kırpma kılavuzu: fotoğraf kaydırılıp yakınlaştırılarak belge çerçeveye oturtulur;
/// "Kırp" çerçevenin içini PNG baytı olarak döndürür (sonra JPEG'e sıkıştırılır). "Olduğu gibi kullan"
/// kırpmadan döner (null).
class CropGuidePage extends StatefulWidget {
  const CropGuidePage({super.key, required this.image, required this.kind});

  final Uint8List image;
  final AttachmentKind kind;

  @override
  State<CropGuidePage> createState() => _CropGuidePageState();
}

class _CropGuidePageState extends State<CropGuidePage> {
  final _transform = TransformationController();
  ui.Image? _decoded;
  bool _busy = false;
  Rect _frame = Rect.zero;
  Size _imageBox = Size.zero;

  /// Çek ≈ 2,2 : 1; senet ≈ 1,9 : 1.
  double get _aspect => widget.kind == AttachmentKind.chequeImage ? 2.2 : 1.9;

  String get _title => widget.kind == AttachmentKind.chequeImage
      ? 'Çeki çerçeveye yerleştirin'
      : 'Senedi çerçeveye yerleştirin';

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    final codec = await ui.instantiateImageCodec(widget.image);
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _decoded = frame.image);
  }

  @override
  void dispose() {
    _transform.dispose();
    _decoded?.dispose();
    super.dispose();
  }

  Future<void> _crop() async {
    final img = _decoded;
    if (img == null || _frame.isEmpty || _imageBox.isEmpty) return;
    setState(() => _busy = true);
    try {
      // Çerçevenin görüntü kutusundaki karşılığı (dönüşümün tersi), sonra görüntü pikseline ölçek.
      final inverse = Matrix4.inverted(_transform.value);
      final tl = MatrixUtils.transformPoint(inverse, _frame.topLeft);
      final br = MatrixUtils.transformPoint(inverse, _frame.bottomRight);
      final fit = applyBoxFit(
        BoxFit.contain,
        Size(img.width.toDouble(), img.height.toDouble()),
        _imageBox,
      );
      final dest = Alignment.center.inscribe(
        fit.destination,
        Offset.zero & _imageBox,
      );
      final scale = img.width / dest.width;
      final src =
          Rect.fromPoints(
            Offset((tl.dx - dest.left) * scale, (tl.dy - dest.top) * scale),
            Offset((br.dx - dest.left) * scale, (br.dy - dest.top) * scale),
          ).intersect(
            Offset.zero & Size(img.width.toDouble(), img.height.toDouble()),
          );
      if (src.isEmpty) return;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        img,
        src,
        Offset.zero & src.size,
        Paint()..filterQuality = FilterQuality.high,
      );
      final out = await recorder.endRecording().toImage(
        src.width.round(),
        src.height.round(),
      );
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      out.dispose();
      if (data != null && mounted) {
        await HapticFeedback.lightImpact();
        if (mounted) Navigator.of(context).pop(data.buffer.asUint8List());
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_title),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text(
              'Olduğu gibi kullan',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
      body: _decoded == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : LayoutBuilder(
              builder: (context, c) {
                _imageBox = Size(c.maxWidth, c.maxHeight);
                final w = c.maxWidth - 32;
                final h = w / _aspect;
                _frame = Rect.fromCenter(
                  center: Offset(c.maxWidth / 2, c.maxHeight / 2),
                  width: w,
                  height: h,
                );
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    InteractiveViewer(
                      transformationController: _transform,
                      minScale: 0.5,
                      maxScale: 6,
                      boundaryMargin: const EdgeInsets.all(400),
                      child: Image.memory(
                        widget.image,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                      ),
                    ),
                    IgnorePointer(
                      child: CustomPaint(painter: _GuidePainter(_frame)),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 24 + MediaQuery.paddingOf(context).bottom,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'İki parmakla yakınlaştırın; belgenin kenarları çerçeveye denk gelsin.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton.icon(
                              onPressed: _busy ? null : _crop,
                              icon: _busy
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.crop_rounded),
                              label: const Text('Kırp ve kullan'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  _GuidePainter(this.frame);
  final Rect frame;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(frame, const Radius.circular(12));
    final scrim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      scrim,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );
    // Köşe vurguları.
    const l = 22.0;
    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFE8692B);
    for (final c in [
      frame.topLeft,
      frame.topRight,
      frame.bottomLeft,
      frame.bottomRight,
    ]) {
      final dx = c.dx == frame.left ? l : -l;
      final dy = c.dy == frame.top ? l : -l;
      canvas.drawLine(c, c.translate(dx, 0), corner);
      canvas.drawLine(c, c.translate(0, dy), corner);
    }
  }

  @override
  bool shouldRepaint(_GuidePainter old) => old.frame != frame;
}

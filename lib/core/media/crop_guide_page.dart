import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/enums.dart';
import '../ui/motion.dart';
import '../ui/painters/chevron_spinner.dart';
import '../ui/theme.dart';
import '../ui/tokens.dart';
import '../ui/widgets/buttons.dart';

/// Çek / senet kırpma kılavuzu: fotoğraf kaydırılıp yakınlaştırılarak belge çerçeveye oturtulur;
/// "Kırp" çerçevenin içini PNG baytı olarak döndürür (sonra JPEG'e sıkıştırılır). "Olduğu gibi kullan"
/// kırpmadan döner (null).
///
/// Tasarım v3: kamera gibi siyah sayfa; görsel gelince çerçeve yerine oturur (karartma açılır, turuncu
/// köşeler uzar), köşelerin ışığı hafifçe nefes alır; birincil düğme turuncu "Kırp ve kullan".
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
    final c = context.akn;
    final t = context.aknText;
    const white = Color(0xFFFFFFFF);
    final whiteDim = white.withValues(alpha: 0.8);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: white,
        title: Text(_title, style: t.headline.copyWith(color: white)),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: whiteDim,
              textStyle: t.label,
              minimumSize: const Size(48, 48),
            ),
            child: Text(
              'Olduğu gibi kullan',
              style: t.label.copyWith(color: whiteDim),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AnimatedSwitcher(
        duration: AknMotion.of(context, AknMotion.base),
        child: _decoded == null
            ? const Center(
                key: ValueKey('decoding'),
                child: ChevronSpinner(size: 24, color: white),
              )
            : LayoutBuilder(
                key: const ValueKey('guide'),
                builder: (context, box) {
                  _imageBox = Size(box.maxWidth, box.maxHeight);
                  final w = box.maxWidth - 32;
                  final h = w / _aspect;
                  _frame = Rect.fromCenter(
                    center: Offset(box.maxWidth / 2, box.maxHeight / 2),
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
                      // The frame locks on: the scrim opens, the corners
                      // grow, then their light breathes (ambient).
                      IgnorePointer(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: 1),
                          duration: AknMotion.of(context, AknMotion.emphasized),
                          curve: AknMotion.emphasizedCurve,
                          builder: (context, reveal, _) => AknAmbient(
                            period: AknMotion.breathe,
                            reverse: true,
                            builder: (context, glow, _) => CustomPaint(
                              painter: _GuidePainter(
                                _frame,
                                reveal: reveal,
                                glow: glow,
                                accent: c.brandBright,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: AknSpace.page,
                        right: AknSpace.page,
                        bottom: 24 + MediaQuery.paddingOf(context).bottom,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: 1),
                          duration: AknMotion.of(context, AknMotion.slow),
                          curve: AknMotion.emphasizedCurve,
                          builder: (context, v, child) => Opacity(
                            opacity: v,
                            child: Transform.translate(
                              offset: Offset(0, 16 * (1 - v)),
                              child: child,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    PhosphorIconsRegular.handPointing,
                                    size: 18,
                                    color: whiteDim,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'İki parmakla yakınlaştırın; belgenin kenarları çerçeveye denk gelsin.',
                                      textAlign: TextAlign.center,
                                      style: t.bodySmall.copyWith(
                                        color: whiteDim,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              AknButton(
                                label: 'Kırp ve kullan',
                                icon: PhosphorIconsRegular.crop,
                                expand: true,
                                loading: _busy,
                                loadingLabel: 'Kırpılıyor',
                                onPressed: _crop,
                              ),
                            ],
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

/// The crop guide: a scrim around the rounded frame, a thin white outline
/// and orange corner marks. [reveal] (0..1) opens the scrim and grows the
/// corners; [glow] (0..1, ambient) breathes a soft light under them.
class _GuidePainter extends CustomPainter {
  _GuidePainter(
    this.frame, {
    required this.reveal,
    required this.glow,
    required this.accent,
  });

  final Rect frame;
  final double reveal;
  final double glow;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (frame.isEmpty) return;
    // The frame settles from a little larger as it locks on.
    final grow = 1 + 0.04 * (1 - reveal);
    final f = Rect.fromCenter(
      center: frame.center,
      width: frame.width * grow,
      height: frame.height * grow,
    );
    final rrect = RRect.fromRectAndRadius(f, const Radius.circular(16));
    final scrim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      scrim,
      Paint()..color = Colors.black.withValues(alpha: 0.6 * reveal),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.85 * reveal),
    );
    // Köşe vurguları: kollar köşe yayından büyüyerek uzar.
    final l = 16 + 12 * reveal;
    final corners = Path();
    for (final c in [f.topLeft, f.topRight, f.bottomLeft, f.bottomRight]) {
      final dx = c.dx == f.left ? 1.0 : -1.0;
      final dy = c.dy == f.top ? 1.0 : -1.0;
      // Each mark hugs the frame's rounded corner.
      corners
        ..moveTo(c.dx + dx * l, c.dy)
        ..lineTo(c.dx + dx * 16, c.dy)
        ..arcToPoint(
          Offset(c.dx, c.dy + dy * 16),
          radius: const Radius.circular(16),
          clockwise: dx * dy < 0,
        )
        ..lineTo(c.dx, c.dy + dy * l);
    }
    if (glow > 0) {
      canvas.drawPath(
        corners,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..strokeCap = StrokeCap.round
          ..color = accent.withValues(alpha: 0.28 * glow * reveal)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawPath(
      corners,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = accent.withValues(alpha: reveal),
    );
  }

  @override
  bool shouldRepaint(_GuidePainter old) =>
      old.frame != frame ||
      old.reveal != reveal ||
      old.glow != glow ||
      old.accent != accent;
}

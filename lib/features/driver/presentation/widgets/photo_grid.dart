import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/media/attachment_gallery.dart';
import '../../../../core/ui/ui.dart';
import '../../copy.dart';
import '../../data/deliver_draft.dart';
import 'entrance.dart';

/// Teslim fotoğrafları ızgarası (tasarım v3): yerel dosyalar ve (düzeltmede) önceki teslimatın
/// fotoğrafları, r16 kareler. Yeni kare hafifçe büyüyerek belirir; her karede 48 dp "kaldır"
/// düğmesi (koyu yarı saydam daire); dokununca büyük önizleme. Sondaki "Ekle" karesi kesikli
/// çerçeveli, basınca küçülür.
class PhotoGrid extends StatelessWidget {
  const PhotoGrid({
    super.key,
    required this.photos,
    required this.onRemove,
    this.onAdd,
  });

  final List<DraftPhoto> photos;
  final ValueChanged<int> onRemove;

  /// Sondaki "ekle" karesi (kamera).
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 8.0;
        final columns = box.maxWidth >= 520 ? 4 : 3;
        final size = (box.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < photos.length; i++)
              SizedBox.square(
                key: ValueKey('${photos[i].path}|${photos[i].publicId}'),
                dimension: size,
                child: DriverFadeUp(
                  offset: 8,
                  scale: 0.9,
                  duration: AknMotion.slow,
                  curve: AknMotion.emphasizedCurve,
                  child: _PhotoTile(
                    photo: photos[i],
                    index: i,
                    onRemove: () => onRemove(i),
                  ),
                ),
              ),
            if (onAdd != null)
              SizedBox.square(
                dimension: size,
                child: _AddTile(onTap: onAdd!),
              ),
          ],
        );
      },
    );
  }
}

/// Fotoğraf karelerinin köşesi (v3: r16).
const BorderRadius _tileRadius = BorderRadius.all(Radius.circular(16));

class _PhotoTile extends ConsumerWidget {
  const _PhotoTile({
    required this.photo,
    required this.index,
    required this.onRemove,
  });

  final DraftPhoto photo;
  final int index;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.akn;
    final path = photo.path;
    final publicId = photo.publicId;
    Widget image;
    if (path != null) {
      image = Image.file(
        File(path),
        fit: BoxFit.cover,
        cacheWidth: 360,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _broken(c),
      );
    } else if (publicId != null) {
      final bytes = ref.watch(
        attachmentBytesProvider((publicId: publicId, approvalId: null)),
      );
      image = bytes.when(
        data: (b) => Image.memory(
          b,
          fit: BoxFit.cover,
          cacheWidth: 360,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _broken(c),
        ),
        loading: () => const Center(child: ChevronSpinner(size: 18)),
        error: (_, _) => _broken(c),
      );
    } else {
      image = _broken(c);
    }
    final label = photo.fromServer
        ? '${DriverCopy.photoPrevious}, fotoğraf ${index + 1}'
        : 'Teslim fotoğrafı ${index + 1}';
    return ClipRRect(
      borderRadius: _tileRadius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Semantics(
            image: true,
            button: true,
            label: label,
            hint: 'Büyütmek için dokunun',
            child: Material(
              color: c.surfaceAlt,
              child: InkWell(onTap: () => _preview(context), child: image),
            ),
          ),
          if (photo.fromServer)
            Positioned(
              left: 6,
              bottom: 6,
              child: ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AknColors.light.ink.withValues(alpha: 0.78),
                    borderRadius: AknRadius.tag,
                  ),
                  child: Text(
                    DriverCopy.photoPreviousTag,
                    style: context.aknText.caption.copyWith(
                      color: AknColors.light.surface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 0,
            top: 0,
            child: Semantics(
              button: true,
              label: '${DriverCopy.photoRemove} ${index + 1}',
              excludeSemantics: true,
              onTap: onRemove,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  AknHaptics.light();
                  onRemove();
                },
                child: SizedBox.square(
                  dimension: context.minTap,
                  child: Center(
                    child: PressScale(
                      scale: 0.88,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AknColors.light.ink.withValues(alpha: 0.72),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AknColors.light.surface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                        child: Icon(
                          PhosphorIconsRegular.x,
                          size: 18,
                          color: AknColors.light.surface,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _broken(AknColors c) => Center(
    child: Icon(PhosphorIconsRegular.imageBroken, color: c.dim, size: 28),
  );

  void _preview(BuildContext context) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _PhotoPreviewPage(photo: photo),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    return Semantics(
      button: true,
      label: DriverCopy.photoTake,
      excludeSemantics: true,
      onTap: onTap,
      child: PressScale(
        child: CustomPaint(
          foregroundPainter: _DashedBorderPainter(
            color: c.lineStrong,
            radius: _tileRadius,
          ),
          child: Material(
            color: c.surface,
            shape: const RoundedRectangleBorder(borderRadius: _tileRadius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                AknHaptics.light();
                onTap();
              },
              splashFactory: NoSplash.splashFactory,
              highlightColor: c.surfaceAlt,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 40,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: c.brandSoft,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            PhosphorIconsRegular.cameraPlus,
                            color: c.brandInk,
                            size: 22,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        DriverCopy.photoAdd,
                        style: t.label.copyWith(
                          color: c.ink,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Ekle" karesinin kesikli çerçevesi (1,5 px, 6 / 5 px).
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path()..addRRect(radius.toRRect(rect.deflate(0.75)));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final len = (d + 6).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(d, len), paint);
        d += 11;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

class _PhotoPreviewPage extends ConsumerWidget {
  const _PhotoPreviewPage({required this.photo});

  final DraftPhoto photo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = photo.path;
    final publicId = photo.publicId;
    const broken = Center(
      child: Icon(PhosphorIconsRegular.imageBroken, color: Colors.white70),
    );
    Widget image = broken;
    if (path != null) {
      image = Image.file(
        File(path),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => broken,
      );
    } else if (publicId != null) {
      image = ref
          .watch(
            attachmentBytesProvider((publicId: publicId, approvalId: null)),
          )
          .when(
            data: (b) => Image.memory(
              b,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => broken,
            ),
            loading: () => const Center(
              child: ChevronSpinner(size: 24, color: Colors.white),
            ),
            error: (_, _) => broken,
          );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: DriverCopy.close,
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(PhosphorIconsRegular.x),
        ),
      ),
      body: InteractiveViewer(
        minScale: 1,
        maxScale: 6,
        child: Center(child: image),
      ),
    );
  }
}

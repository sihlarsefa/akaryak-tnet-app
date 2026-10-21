import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/media/attachment_gallery.dart';
import '../../../../core/ui/ui.dart';
import '../../copy.dart';
import '../../data/deliver_draft.dart';

/// Teslim fotoğrafları ızgarası: yerel dosyalar ve (düzeltmede) önceki teslimatın fotoğrafları;
/// her karede 48 dp "kaldır" düğmesi; dokununca büyük önizleme.
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
                dimension: size,
                child: _PhotoTile(
                  photo: photos[i],
                  index: i,
                  onRemove: () => onRemove(i),
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
      borderRadius: AknRadius.card,
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
                    color: AknColors.light.ink,
                    borderRadius: BorderRadius.circular(AknRadius.xs),
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
                onTap: onRemove,
                child: SizedBox.square(
                  dimension: context.minTap,
                  child: Center(
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AknColors.light.ink,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AknColors.light.surface,
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

  static Widget _broken(AknColors c) =>
      Center(child: Icon(Icons.broken_image_outlined, color: c.dim, size: 28));

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
      child: Material(
        color: c.surfaceAlt,
        shape: const RoundedRectangleBorder(borderRadius: AknRadius.card),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_a_photo_outlined, color: c.ink, size: 28),
                  const SizedBox(height: 4),
                  Text(
                    DriverCopy.photoAdd,
                    style: t.label.copyWith(
                      color: c.ink,
                      fontWeight: FontWeight.w600,
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
    );
  }
}

class _PhotoPreviewPage extends ConsumerWidget {
  const _PhotoPreviewPage({required this.photo});

  final DraftPhoto photo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = photo.path;
    final publicId = photo.publicId;
    const broken = Center(
      child: Icon(Icons.broken_image_outlined, color: Colors.white70),
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
          icon: const Icon(Icons.close_rounded),
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

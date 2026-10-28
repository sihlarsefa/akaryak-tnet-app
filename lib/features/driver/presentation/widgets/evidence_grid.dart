import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/media/attachment_gallery.dart';
import '../../../../core/models/models.dart';
import '../../../../core/ui/ui.dart';
import 'entrance.dart';

/// Teslim kanıtı ekleri (fotoğraf, imza, itiraz fotoğrafı; tasarım v3): r16 küçük resim + altında
/// tür etiketi; kareler sırayla yükselerek belirir, basınca küçülür; dokununca tam ekran
/// görüntüleyici (yakınlaştırma, paylaş).
class EvidenceGrid extends StatelessWidget {
  const EvidenceGrid({super.key, required this.attachments});

  final List<Attachment> attachments;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 8.0;
        final columns = box.maxWidth >= 520 ? 4 : 3;
        final size = (box.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: 12,
          children: [
            for (var i = 0; i < attachments.length; i++)
              SizedBox(
                width: size,
                child: DriverStaggerItem(
                  index: i,
                  child: _EvidenceTile(
                    attachment: attachments[i],
                    size: size,
                    onTap: () =>
                        Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute<void>(
                            fullscreenDialog: true,
                            builder: (_) => AttachmentViewerPage(
                              attachments: attachments,
                              initialIndex: i,
                            ),
                          ),
                        ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _EvidenceTile extends ConsumerWidget {
  const _EvidenceTile({
    required this.attachment,
    required this.size,
    required this.onTap,
  });

  final Attachment attachment;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.akn;
    final t = context.aknText;
    final a = attachment;
    Widget content;
    if (a.isImage) {
      content = ref
          .watch(
            attachmentBytesProvider((publicId: a.publicId, approvalId: null)),
          )
          .when(
            data: (b) => Image.memory(
              b,
              fit: a.kind == AttachmentKind.deliverySignature
                  ? BoxFit.contain
                  : BoxFit.cover,
              cacheWidth: 360,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) =>
                  Icon(PhosphorIconsRegular.imageBroken, color: c.dim),
            ),
            loading: () => const Center(child: ChevronSpinner(size: 18)),
            error: (_, _) =>
                Icon(PhosphorIconsRegular.imageBroken, color: c.dim),
          );
    } else {
      content = Icon(
        a.isPdf ? PhosphorIconsRegular.filePdf : PhosphorIconsRegular.file,
        color: c.ink,
        size: 28,
      );
    }
    return Semantics(
      button: true,
      label: '${a.kindLabel}, ${a.fileName}',
      hint: 'Açmak için dokunun',
      onTap: onTap,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: size,
            child: PressScale(
              child: Material(
                color: a.kind == AttachmentKind.deliverySignature
                    ? AknColors.light.surface
                    : c.surfaceAlt,
                shape: RoundedRectangleBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(16)),
                  side: BorderSide(color: c.line),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    AknHaptics.selection();
                    onTap();
                  },
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: c.ink.withValues(alpha: 0.06),
                  child: a.isImage
                      ? SizedBox.expand(child: content)
                      : Center(child: content),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            a.kindLabel,
            style: t.caption.copyWith(
              color: c.dim,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

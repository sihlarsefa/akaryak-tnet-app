import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../auth/session_controller.dart';
import '../models/attachment.dart';
import '../ui/driver_mode.dart';
import '../ui/motion.dart';
import '../ui/painters/chevron_spinner.dart';
import '../ui/theme.dart';
import '../ui/tokens.dart';
import '../ui/widgets/skeletons.dart';
import '../utils/external_activity.dart';
import '../utils/format.dart';
import 'attachment_api.dart';

/// Ek içeriği (oturum boyunca bellekte; kullanıcı değişince yeniden okunur).
/// [approvalId] verilirse görüntüleme onay kaydına yazılır (spec B.5).
final attachmentBytesProvider =
    FutureProvider.family<Uint8List, ({String publicId, int? approvalId})>((
      ref,
      key,
    ) async {
      ref.watch(currentUserIdProvider);
      return ref
          .read(attachmentApiProvider)
          .content(key.publicId, approvalId: key.approvalId);
    });

/// Ek ızgarası (spec C.4): küçük resimler; dokununca tam ekran görüntüleyici (iki parmakla yakınlaştırma,
/// PDF önizleme, paylaş / yazdır).
///
/// Tasarım v3: r16 kareler basamaklı gelir (60 ms arayla yükselip belirir), basınca küçülür; görsel
/// yüklenirken yumuşak iskelet ışığı süzülür.
class AttachmentGallery extends StatelessWidget {
  const AttachmentGallery({
    super.key,
    required this.attachments,
    this.approvalId,
    this.crossAxisCount = 3,
    this.onDelete,
  });

  final List<Attachment> attachments;

  /// Onay ayrıntısında açılan ekler görüntüleme kaydına yazılır.
  final int? approvalId;
  final int crossAxisCount;

  /// Silme (yalnızca `canDelete` eklerde gösterilir).
  final void Function(Attachment attachment)? onDelete;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: attachments.length,
      itemBuilder: (context, i) => _Arrive(
        index: i,
        child: AttachmentThumb(
          attachment: attachments[i],
          approvalId: approvalId,
          onTap: () => Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute<void>(
              fullscreenDialog: true,
              builder: (_) => AttachmentViewerPage(
                attachments: attachments,
                initialIndex: i,
                approvalId: approvalId,
              ),
            ),
          ),
          onDelete: onDelete != null && attachments[i].canDelete
              ? () => onDelete!(attachments[i])
              : null,
        ),
      ),
    );
  }
}

/// A grid cell's entrance: fades in, rises 12 px and settles from 0.94,
/// 60 ms after the previous cell (capped). The structure never changes, so
/// the thumbnail inside is never rebuilt from scratch.
class _Arrive extends StatelessWidget {
  const _Arrive({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const each = 420;
    final delay = 60 * index.clamp(0, 8);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: AknMotion.of(context, Duration(milliseconds: each + delay)),
      curve: Interval(
        delay / (each + delay),
        1,
        curve: AknMotion.emphasizedCurve,
      ),
      child: child,
      builder: (context, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 12 * (1 - v)),
          child: Transform.scale(scale: 0.94 + 0.06 * v, child: child),
        ),
      ),
    );
  }
}

/// Tek ek küçük resmi: r16 kare; altta okunur bir karartma üstünde beyaz tür etiketi, silinebiliyorsa
/// sağ üstte cam bir "×".
class AttachmentThumb extends ConsumerWidget {
  const AttachmentThumb({
    super.key,
    required this.attachment,
    this.approvalId,
    this.onTap,
    this.onDelete,
  });

  final Attachment attachment;
  final int? approvalId;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.akn;
    final t = context.aknText;
    final a = attachment;
    Widget content;
    if (a.isImage) {
      final bytes = ref.watch(
        attachmentBytesProvider((publicId: a.publicId, approvalId: approvalId)),
      );
      content = bytes.when(
        data: (b) => Image.memory(
          b,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          cacheWidth: 360,
          frameBuilder: (context, child, frame, sync) => sync
              ? child
              : AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: AknMotion.of(context, AknMotion.base),
                  curve: AknMotion.standard,
                  child: child,
                ),
        ),
        loading: () => const Shimmer(
          semanticLabel: null,
          child: SkeletonBox(height: double.infinity, radius: 0),
        ),
        error: (_, _) => Center(
          child: Icon(PhosphorIconsRegular.imageBroken, color: c.dim, size: 26),
        ),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 26),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              a.isPdf ? PhosphorIconsFill.filePdf : PhosphorIconsRegular.file,
              color: a.isPdf ? c.brandBright : c.ink,
              size: 30,
            ),
            const SizedBox(height: 6),
            Text(
              a.fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: t.caption.copyWith(color: c.ink),
            ),
          ],
        ),
      );
    }
    return Semantics(
      button: true,
      label: '${a.kindLabel}, ${a.fileName}',
      child: PressScale(
        enabled: onTap != null,
        child: Material(
          color: c.surfaceAlt,
          shape: const RoundedSuperellipseBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            splashFactory: NoSplash.splashFactory,
            highlightColor: c.ink.withValues(alpha: 0.06),
            child: Stack(
              fit: StackFit.expand,
              children: [
                content,
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    // Grafit karartma: beyaz etiket her görselin üstünde AA kontrastta kalır.
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x0015171A), Color(0xC715171A)],
                        stops: [0, 0.55],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
                      child: Text(
                        a.kindLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.caption.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                if (onDelete != null)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: IconButton(
                      tooltip: 'Sil',
                      // 48 dp dokunma hedefi (spec C.7; sürücü modunda 64).
                      constraints: BoxConstraints(
                        minWidth:
                            AknDriverMode.maybeOf(context)?.minTap ??
                            AknSpace.minTap,
                        minHeight:
                            AknDriverMode.maybeOf(context)?.minTap ??
                            AknSpace.minTap,
                      ),
                      onPressed: onDelete,
                      icon: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0x8C15171A),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0x47FFFFFF)),
                        ),
                        child: const Icon(
                          PhosphorIconsBold.x,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tam ekran ek görüntüleyici: siyah sahne, başlıkta tür ve dosya bilgisi; yüklenirken beyaz »
/// yükleyici, sayfalar arasında kaydırılır.
class AttachmentViewerPage extends ConsumerStatefulWidget {
  const AttachmentViewerPage({
    super.key,
    required this.attachments,
    this.initialIndex = 0,
    this.approvalId,
  });

  final List<Attachment> attachments;
  final int initialIndex;
  final int? approvalId;

  @override
  ConsumerState<AttachmentViewerPage> createState() =>
      _AttachmentViewerPageState();
}

class _AttachmentViewerPageState extends ConsumerState<AttachmentViewerPage> {
  late final PageController _pages = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _share(Attachment a) async {
    final bytes = await ref.read(
      attachmentBytesProvider((
        publicId: a.publicId,
        approvalId: widget.approvalId,
      )).future,
    );
    await ExternalActivity.run(
      () => Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: a.contentType, name: a.fileName)],
        fileNameOverrides: [a.fileName],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.attachments[_index];
    final t = context.aknText;
    final whiteDim = Colors.white.withValues(alpha: 0.78);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: AnimatedSwitcher(
          duration: AknMotion.of(context, AknMotion.base),
          layoutBuilder: (current, previous) => Stack(
            alignment: AlignmentDirectional.centerStart,
            children: [...previous, ?current],
          ),
          child: Column(
            key: ValueKey(_index),
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                a.kindLabel,
                style: t.headline.copyWith(color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${a.fileName}, ${Fmt.fileSize(a.sizeBytes)}${a.createdAt == null ? '' : ', ${Fmt.dateTime(a.createdAt)}'}',
                style: t.caption.copyWith(
                  color: whiteDim,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        actions: [
          if (a.isImage)
            IconButton(
              tooltip: 'Paylaş',
              onPressed: () => _share(a),
              icon: const Icon(PhosphorIconsRegular.export),
            ),
        ],
      ),
      body: PageView.builder(
        controller: _pages,
        itemCount: widget.attachments.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) {
          final item = widget.attachments[i];
          final bytes = ref.watch(
            attachmentBytesProvider((
              publicId: item.publicId,
              approvalId: widget.approvalId,
            )),
          );
          return bytes.when(
            loading: () => const Center(
              child: ChevronSpinner(size: 24, color: Colors.white),
            ),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AknSpace.page),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      PhosphorIconsRegular.imageBroken,
                      size: 32,
                      color: whiteDim,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Belge açılamadı. Bağlantınızı kontrol edin.',
                      textAlign: TextAlign.center,
                      style: t.bodySmall.copyWith(color: whiteDim),
                    ),
                  ],
                ),
              ),
            ),
            data: (b) {
              if (item.isPdf) {
                return PdfPreview(
                  build: (_) async => b,
                  pdfFileName: item.fileName,
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  canDebug: false,
                  allowPrinting: true,
                  allowSharing: true,
                );
              }
              if (!item.isImage) {
                return Center(
                  child: Text(
                    'Bu dosya önizlenemiyor.',
                    style: t.bodySmall.copyWith(color: whiteDim),
                  ),
                );
              }
              return InteractiveViewer(
                minScale: 1,
                maxScale: 6,
                child: Center(
                  child: Image.memory(
                    b,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    frameBuilder: (context, child, frame, sync) => sync
                        ? child
                        : AnimatedOpacity(
                            opacity: frame == null ? 0 : 1,
                            duration: AknMotion.of(context, AknMotion.base),
                            curve: AknMotion.standard,
                            child: child,
                          ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

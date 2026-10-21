import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../auth/session_controller.dart';
import '../models/attachment.dart';
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
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: attachments.length,
      itemBuilder: (context, i) => AttachmentThumb(
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
    );
  }
}

/// Tek ek küçük resmi.
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
    final scheme = Theme.of(context).colorScheme;
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
        ),
        loading: () => const Center(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        error: (_, _) =>
            Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
      );
    } else {
      content = Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              a.isPdf
                  ? Icons.picture_as_pdf_rounded
                  : Icons.insert_drive_file_rounded,
              color: scheme.primary,
              size: 28,
            ),
            const SizedBox(height: 6),
            Text(
              a.fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      );
    }
    return Semantics(
      button: true,
      label: '${a.kindLabel}, ${a.fileName}',
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              content,
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  // Koyu şerit: beyaz etiket her görselin üstünde AA kontrastta kalır.
                  color: const Color(0xD90F172A),
                  child: Text(
                    a.kindLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
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
                    // 48 dp dokunma hedefi (spec C.7).
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: onDelete,
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      shadows: [Shadow(blurRadius: 4)],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tam ekran ek görüntüleyici.
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(a.kindLabel, style: const TextStyle(fontSize: 16)),
            Text(
              '${a.fileName} · ${Fmt.fileSize(a.sizeBytes)}${a.createdAt == null ? '' : ' · ${Fmt.dateTime(a.createdAt)}'}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          if (a.isImage)
            IconButton(
              tooltip: 'Paylaş',
              onPressed: () => _share(a),
              icon: const Icon(Icons.ios_share_rounded),
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
              child: CircularProgressIndicator(color: Colors.white),
            ),
            error: (e, _) => const Center(
              child: Text(
                'Belge açılamadı. Bağlantınızı kontrol edin.',
                style: TextStyle(color: Colors.white70),
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
                return const Center(
                  child: Text(
                    'Bu dosya önizlenemiyor.',
                    style: TextStyle(color: Colors.white70),
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

import 'package:flutter/material.dart';

import '../../utils/format.dart';
import '../../utils/turkish_text.dart';
import '../motion.dart';
import '../painters/progress_ring.dart';
import '../theme.dart';
import '../tokens.dart';

enum AttachmentTileState { idle, uploading, failed, done }

/// A document or photo row: thumbnail or type icon, name, kind and size,
/// and an upload state (progress ring, retry, done check) or actions.
class AttachmentTile extends StatelessWidget {
  const AttachmentTile({
    super.key,
    required this.fileName,
    this.kindLabel,
    this.sizeBytes,
    this.contentType,
    this.subtitle,
    this.thumbnail,
    this.state = AttachmentTileState.idle,
    this.progress,
    this.errorText,
    this.onTap,
    this.onRetry,
    this.onDelete,
  });

  final String fileName;

  /// "Çek görseli", "Vergi levhası".
  final String? kindLabel;
  final int? sizeBytes;

  /// `application/pdf`, `image/jpeg`… picks the icon.
  final String? contentType;

  /// Extra line (uploader, date).
  final String? subtitle;

  /// Image preview (e.g. `Image.memory`, `CachedNetworkImage`).
  final Widget? thumbnail;
  final AttachmentTileState state;

  /// 0..1 while uploading.
  final double? progress;
  final String? errorText;
  final VoidCallback? onTap;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;

  bool get _isPdf =>
      (contentType ?? '').contains('pdf') ||
      fileName.asciiLower.endsWith('.pdf');

  bool get _isImage =>
      (contentType ?? '').startsWith('image/') ||
      RegExp(
        r'\.(jpe?g|png|heic|webp)$',
        caseSensitive: false,
      ).hasMatch(fileName);

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final details = [
      ?kindLabel,
      if (sizeBytes != null) Fmt.fileSize(sizeBytes),
    ].join(' · ');
    final stateText = switch (state) {
      AttachmentTileState.uploading =>
        progress == null
            ? 'Yükleniyor'
            : 'Yükleniyor %${((progress ?? 0) * 100).round()}',
      AttachmentTileState.failed => errorText ?? 'Yüklenemedi',
      AttachmentTileState.done => 'Yüklendi',
      AttachmentTileState.idle => null,
    };
    final leading = ClipRRect(
      borderRadius: BorderRadius.circular(AknRadius.md - 2),
      child: SizedBox(
        width: 48,
        height: 48,
        child:
            thumbnail ??
            ColoredBox(
              color: _isPdf ? c.danger.bg : c.brandSoft,
              child: Icon(
                _isPdf
                    ? Icons.picture_as_pdf_rounded
                    : _isImage
                    ? Icons.image_rounded
                    : Icons.insert_drive_file_rounded,
                color: _isPdf ? c.danger.fg : c.brand,
                size: 24,
              ),
            ),
      ),
    );
    final Widget trailing = switch (state) {
      AttachmentTileState.uploading => ProgressRing(
        value: progress ?? 0,
        size: 30,
        strokeWidth: 3,
        semanticLabel: 'Yükleme',
      ),
      AttachmentTileState.failed => IconButton(
        tooltip: 'Tekrar dene',
        onPressed: onRetry,
        icon: Icon(Icons.refresh_rounded, color: c.danger.fg),
      ),
      AttachmentTileState.done => Icon(
        Icons.check_circle_rounded,
        color: c.ok.fg,
        size: 24,
      ),
      AttachmentTileState.idle =>
        onDelete != null
            ? IconButton(
                tooltip: 'Kaldır',
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline_rounded, color: c.dim),
              )
            : onTap != null
            ? Icon(Icons.open_in_new_rounded, color: c.faint, size: 20)
            : const SizedBox.shrink(),
    };
    return Semantics(
      label: [fileName, if (details.isNotEmpty) details, ?stateText].join(', '),
      button: onTap != null,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AknRadius.card,
          side: BorderSide(
            color: state == AttachmentTileState.failed
                ? c.danger.line
                : (c.isDark ? c.line : c.lineSoft),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fileName,
                        style: t.bodyStrong.copyWith(fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (details.isNotEmpty)
                        Text(details, style: t.caption, maxLines: 1),
                      if (subtitle != null)
                        Text(subtitle!, style: t.caption, maxLines: 1),
                      if (stateText != null &&
                          state != AttachmentTileState.idle)
                        AnimatedSwitcher(
                          duration: AknMotion.of(context, AknMotion.fast),
                          child: Text(
                            stateText,
                            key: ValueKey(stateText),
                            style: t.captionStrong.copyWith(
                              color: state == AttachmentTileState.failed
                                  ? c.danger.fg
                                  : state == AttachmentTileState.done
                                  ? c.ok.fg
                                  : c.brandInk,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                ExcludeSemantics(
                  excluding:
                      state != AttachmentTileState.failed && onDelete == null,
                  child: trailing,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

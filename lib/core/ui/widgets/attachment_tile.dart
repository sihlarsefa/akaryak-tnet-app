import 'package:flutter/material.dart';

import '../../utils/format.dart';
import '../../utils/turkish_text.dart';
import '../theme.dart';
import '../tokens.dart';
import 'buttons.dart';
import 'skeletons.dart';
import 'status_widgets.dart';

enum AttachmentTileState { idle, uploading, failed, done }

/// A document or photo (design v2 §6.27) in a group box (white, 1 px
/// hairline, r12): `description_outlined` 24 dim (or a thumbnail), the name
/// (15/22 600), a meta line (kind, size) and a status lamp, and a small
/// secondary button on the right ("Yükle", "Tekrar dene", "Görüntüle").
/// While uploading, a 2.5 px orange progress bar runs along the bottom.
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
    this.onUpload,
    this.actionLabel,
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

  /// Opens the file ("Görüntüle").
  final VoidCallback? onTap;
  final VoidCallback? onRetry;
  final VoidCallback? onDelete;

  /// Picks and uploads a file ("Yükle") while the slot is empty.
  final VoidCallback? onUpload;

  /// Replaces the trailing button's label.
  final String? actionLabel;

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
    ].join(', ');
    final (String? stateText, AknTone tone) = switch (state) {
      AttachmentTileState.uploading => (
        progress == null
            ? 'Yükleniyor'
            : 'Yükleniyor %${((progress ?? 0) * 100).round()}',
        AknTone.info,
      ),
      AttachmentTileState.failed => (
        errorText ?? 'Yüklenemedi',
        AknTone.danger,
      ),
      AttachmentTileState.done => ('Yüklendi', AknTone.ok),
      AttachmentTileState.idle => (null, AknTone.neutral),
    };
    final (String? buttonLabel, VoidCallback? buttonAction) = switch (state) {
      AttachmentTileState.failed when onRetry != null => (
        actionLabel ?? 'Tekrar dene',
        onRetry,
      ),
      AttachmentTileState.idle when onUpload != null => (
        actionLabel ?? 'Yükle',
        onUpload,
      ),
      AttachmentTileState.idle || AttachmentTileState.done when onTap != null =>
        (actionLabel ?? 'Görüntüle', onTap),
      _ => (null, null),
    };
    final leading = thumbnail != null
        ? ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(8)),
            child: SizedBox.square(dimension: 40, child: thumbnail),
          )
        : Icon(
            _isPdf
                ? Icons.picture_as_pdf_outlined
                : _isImage
                ? Icons.image_outlined
                : Icons.description_outlined,
            color: c.dim,
            size: 24,
          );

    final info = Semantics(
      container: true,
      button: onTap != null,
      label: [
        fileName,
        if (details.isNotEmpty) details,
        ?subtitle,
        ?stateText,
      ].join(', '),
      onTap: onTap,
      excludeSemantics: true,
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
                  style: t.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (details.isNotEmpty)
                  Text(
                    details,
                    style: t.label.copyWith(
                      fontWeight: FontWeight.w400,
                      color: c.dim,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: t.label.copyWith(
                      fontWeight: FontWeight.w400,
                      color: c.dim,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (stateText != null) ...[
                  const SizedBox(height: 4),
                  StatusChip(
                    label: stateText,
                    tone: tone,
                    size: StatusChipSize.small,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AknRadius.card,
        side: BorderSide(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        highlightColor: c.surfaceAlt,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                14,
                12,
                buttonLabel == null && onDelete == null ? 14 : 8,
                12,
              ),
              child: Row(
                children: [
                  Expanded(child: info),
                  if (buttonLabel != null) ...[
                    const SizedBox(width: 8),
                    AknButton.secondary(
                      label: buttonLabel,
                      size: AknButtonSize.small,
                      onPressed: buttonAction,
                    ),
                  ],
                  if (onDelete != null &&
                      state != AttachmentTileState.uploading)
                    IconButton(
                      tooltip: 'Kaldır',
                      onPressed: onDelete,
                      icon: Icon(Icons.delete_outline_rounded, color: c.dim),
                    ),
                ],
              ),
            ),
            if (state == AttachmentTileState.uploading)
              TopProgressBar(active: true, value: progress),
          ],
        ),
      ),
    );
  }
}

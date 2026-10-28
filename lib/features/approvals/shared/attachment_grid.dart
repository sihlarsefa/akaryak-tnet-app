import 'package:flutter/material.dart';

import '../../../core/media/attachment_gallery.dart';
import '../../../core/models/attachment.dart';
import '../../../core/models/enums.dart';
import 'layout.dart';

/// Belge ızgarası (onay ve tahsilat ayrıntısı). Küçük resimler görüntüleme kaydı yazmadan yüklenir;
/// dokununca tam ekran görüntüleyici [approvalId] ile açılır — onay talebinde açılan belge sunucuda
/// "Belge açıldı" olarak günlüğe yazılır (spec B.5). [onOpened] karar isteğinin
/// `viewedAttachmentIds` listesi için açılan belgeyi bildirir.
class A5AttachmentGrid extends StatelessWidget {
  const A5AttachmentGrid({
    super.key,
    required this.attachments,
    this.approvalId,
    this.onOpened,
    this.onDelete,
  });

  final List<Attachment> attachments;
  final int? approvalId;
  final ValueChanged<Attachment>? onOpened;
  final ValueChanged<Attachment>? onDelete;

  void _open(BuildContext context, int index) {
    onOpened?.call(attachments[index]);
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => AttachmentViewerPage(
          attachments: attachments,
          initialIndex: index,
          approvalId: approvalId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 520 ? 4 : 3;
        return GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: attachments.length,
          // Küçük resimler sırayla yükselir (durumları korunur; v3 §5).
          itemBuilder: (context, i) => A5StaggerItem(
            index: i,
            child: AttachmentThumb(
              attachment: attachments[i],
              onTap: () => _open(context, i),
              onDelete: onDelete != null && attachments[i].canDelete
                  ? () => onDelete!(attachments[i])
                  : null,
            ),
          ),
        );
      },
    );
  }
}

/// Yalnızca kimliği bilinen bir belgeyi (ör. geçmişteki dayanak belge, risk raporu PDF'i) açar.
void openAttachmentById(
  BuildContext context, {
  required String publicId,
  List<Attachment> known = const [],
  String fallbackName = 'belge',
  String fallbackType = 'application/octet-stream',
  int? approvalId,
}) {
  final list = known.where((a) => a.publicId == publicId).toList();
  final attachment = list.isNotEmpty
      ? list.first
      : Attachment(
          publicId: publicId,
          ownerType: AttachmentOwnerType.unknown,
          ownerId: 0,
          kind: AttachmentKind.other,
          fileName: fallbackName,
          contentType: fallbackType,
        );
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => AttachmentViewerPage(
        attachments: [attachment],
        approvalId: approvalId,
      ),
    ),
  );
}

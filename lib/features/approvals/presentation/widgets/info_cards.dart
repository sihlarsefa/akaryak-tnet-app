import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../data/approval_models.dart';
import '../../shared/uploads.dart';

/// Yanıt belgelerinin hedefi: onay talebi (sahip türü 7, kimlik = talep).
UploadTarget replyTarget(int approvalId) =>
    UploadTarget(AttachmentOwnerType.approvalRequest, approvalId);

/// İstenen belge bu oturumda ya da önceden eklendi mi.
bool requiredKindSatisfied(ApprovalDetail d, List<UploadItem> uploads) {
  final info = d.infoRequest;
  final kind = info?.requiredAttachmentKind;
  if (info == null || kind == null || kind.isUnknown) return true;
  if (info.requiredKindUploaded) return true;
  return uploads.any((u) => u.phase == UploadPhase.done && u.kind == kind);
}

/// "Sizden ek bilgi istendi" (talep eden tarafı; cari görünümünde en üstte): istek notu, istenen belge
/// türü (yükleme bu türle yapılır) ve durumu, yükleme satırları, yanıt alanı. "Yanıtla" alttaki
/// eylem çubuğundadır.
class InfoReplyCard extends ConsumerWidget {
  const InfoReplyCard({
    super.key,
    required this.detail,
    required this.note,
    this.noteFocus,
    this.noteError,
  });

  final ApprovalDetail detail;
  final TextEditingController note;
  final FocusNode? noteFocus;
  final String? noteError;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final kind = detail.infoRequest?.uploadKind ?? AttachmentKind.other;
    final file = await ref.read(a5FileSourceProvider).pick(context, kind);
    if (file == null) return;
    final added = await ref
        .read(uploadsProvider(replyTarget(detail.id)).notifier)
        .add(file, kind);
    if (added != null && context.mounted) {
      AppToast.success('${kind.label} eklendi.', context: context);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.akn;
    final t = context.aknText;
    final info = detail.infoRequest;
    final uploads = ref.watch(uploadsProvider(replyTarget(detail.id)));
    final kind = info?.requiredAttachmentKind;
    final satisfied = requiredKindSatisfied(detail, uploads);
    final kindLabel = info?.displayKindLabel;
    final uploadLabel = kind == null || kind.isUnknown
        ? 'Belge ekle'
        : '${kind.label} ekle';
    return AknCard(
      accent: AknTone.info,
      borderColor: c.info.line,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const AknIconBox(
                icon: Icons.contact_support_rounded,
                tone: AknTone.info,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Sizden ek bilgi istendi', style: t.headline),
                ),
              ),
            ],
          ),
          if (info?.note != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: c.info.bg,
                borderRadius: AknRadius.card,
              ),
              child: Text(info!.note!, style: t.body.copyWith(color: c.ink)),
            ),
          ],
          if (info?.requestedAt != null) ...[
            const SizedBox(height: 6),
            Text('İstek: ${Fmt.relative(info!.requestedAt)}', style: t.caption),
          ],
          if (kindLabel != null) ...[
            const SizedBox(height: 12),
            Semantics(
              container: true,
              label: satisfied
                  ? 'İstenen belge: $kindLabel, eklendi'
                  : 'İstenen belge: $kindLabel, henüz eklenmedi',
              excludeSemantics: true,
              child: Row(
                children: [
                  Icon(
                    satisfied
                        ? Icons.check_circle_rounded
                        : Icons.warning_amber_rounded,
                    size: 20,
                    color: satisfied ? c.ok.fg : c.warn.fg,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      satisfied
                          ? 'İstenen belge eklendi: $kindLabel'
                          : 'İstenen belge: $kindLabel — henüz eklenmedi',
                      style: t.bodyStrong.copyWith(
                        fontSize: 14,
                        color: satisfied ? c.ok.fg : c.warn.fg,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          UploadTiles(target: replyTarget(detail.id)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: AknButton.secondary(
              label: uploadLabel,
              icon: Icons.add_a_photo_rounded,
              onPressed: () => unawaited(_add(context, ref)),
            ),
          ),
          const SizedBox(height: 12),
          AknTextField(
            controller: note,
            focusNode: noteFocus,
            label: 'Yanıtınız',
            hint: 'İstenen bilgiyi yazın…',
            errorText: noteError,
            minLines: 3,
            maxLines: 6,
            maxLength: 1000,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 4),
          Text(
            'Yanıtladığınızda talep yeniden incelemeye alınır.',
            style: t.caption,
          ),
        ],
      ),
    );
  }
}

/// "Ek bilgi bekleniyor" (onaylayan tarafı): kim istedi, ne istendi; "Bilgi alındı" ya da ret.
class InfoWaitingCard extends StatelessWidget {
  const InfoWaitingCard({super.key, required this.detail});

  final ApprovalDetail detail;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final info = detail.infoRequest;
    final asked = detail.events.lastWhereOrNull(
      (e) => e.eventType == ApprovalEventType.infoRequested,
    );
    return AknCard(
      accent: AknTone.info,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const AknIconBox(
                icon: Icons.hourglass_top_rounded,
                tone: AknTone.info,
                size: 36,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  asked?.userName == null
                      ? 'Ek bilgi bekleniyor'
                      : 'Ek bilgi bekleniyor (${asked!.userName} istedi)',
                  style: t.bodyStrong,
                ),
              ),
            ],
          ),
          if (info?.note != null) ...[
            const SizedBox(height: 10),
            Text(info!.note!, style: t.body.copyWith(color: c.ink)),
          ],
          if (info?.displayKindLabel != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                StatusChip(
                  label: 'İstenen: ${info!.displayKindLabel}',
                  tone: info.requiredKindUploaded ? AknTone.ok : AknTone.info,
                  icon: info.requiredKindUploaded
                      ? Icons.check_circle_rounded
                      : Icons.description_rounded,
                  size: StatusChipSize.small,
                ),
                if (info.requiredKindUploaded)
                  const StatusChip(
                    label: 'Belge eklendi',
                    tone: AknTone.ok,
                    icon: Icons.attach_file_rounded,
                    size: StatusChipSize.small,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Bilgi ya da belge size başka yoldan ulaştıysa "Bilgi alındı" ile talebi incelemeye alın; yanıt gelmeyecekse gerekçe yazıp reddedin.',
            style: t.bodySmall,
          ),
        ],
      ),
    );
  }
}

extension _LastWhereOrNull<T> on List<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    for (var i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}

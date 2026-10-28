import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/turkish_text.dart';
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

/// "Sizden ek bilgi istendi" (talep eden tarafı; cari görünümünde en üstte; tasarım v3): sıra sizde
/// olduğu için kartın kenarı yumuşak turuncu, başta turuncu kuyuda soru simgesi; istek notu (kuyu),
/// istenen belge türü (yükleme bu türle yapılır) ve durumu (eklenince simge yaylanarak değişir),
/// yükleme satırları, yanıt alanı. "Yanıtla" alttaki eylem çubuğundadır.
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
      borderColor: c.brandLine,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const AknIconBox(
                icon: PhosphorIconsRegular.chatCircleDots,
                tone: AknTone.brand,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    'Sizden ek bilgi istendi',
                    style: t.headline.copyWith(color: c.ink),
                  ),
                ),
              ),
            ],
          ),
          if (info?.note != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: const BorderRadius.all(
                  Radius.circular(AknRadius.md),
                ),
              ),
              child: Text(info!.note!, style: t.body.copyWith(color: c.ink)),
            ),
          ],
          if (info?.requestedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'İstek: ${TurkishText.lower(Fmt.relative(info!.requestedAt))}',
              style: t.caption.copyWith(color: c.dim),
            ),
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
                  AnimatedSwitcher(
                    duration: AknMotion.of(context, AknMotion.iconSwap),
                    switchInCurve: AknMotion.pop,
                    transitionBuilder: (child, a) =>
                        ScaleTransition(scale: a, child: child),
                    child: Icon(
                      satisfied
                          ? PhosphorIconsFill.checkCircle
                          : PhosphorIconsFill.warning,
                      key: ValueKey(satisfied),
                      size: 20,
                      color: satisfied ? c.ok.fg : c.warn.fg,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      satisfied
                          ? 'İstenen belge eklendi: $kindLabel'
                          : 'İstenen belge: $kindLabel, henüz eklenmedi',
                      style: t.bodySmall.copyWith(
                        fontWeight: FontWeight.w600,
                        color: c.ink,
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
              icon: PhosphorIconsRegular.cameraPlus,
              size: AknButtonSize.small,
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
            style: t.caption.copyWith(color: c.dim),
          ),
        ],
      ),
    );
  }
}

/// "Ek bilgi bekleniyor" (onaylayan tarafı; tasarım v3 beyaz kart, kum saati kuyusu): kim istedi,
/// ne istendi; "Bilgi alındı" ya da ret.
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
    final kind = info?.displayKindLabel;
    return AknCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const AknIconBox(icon: PhosphorIconsRegular.hourglassHigh),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  asked?.userName == null
                      ? 'Ek bilgi bekleniyor'
                      : 'Ek bilgi bekleniyor (${asked!.userName} istedi)',
                  style: t.bodyStrong.copyWith(
                    color: c.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (info?.note != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: const BorderRadius.all(
                  Radius.circular(AknRadius.md),
                ),
              ),
              child: Text(info!.note!, style: t.body.copyWith(color: c.ink)),
            ),
          ],
          if (kind != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                AknLamp(
                  label: 'İstenen: $kind',
                  tone: info!.requiredKindUploaded ? AknTone.ok : AknTone.info,
                  size: AknLampSize.small,
                ),
                if (info.requiredKindUploaded)
                  const AknLamp(
                    label: 'Belge eklendi',
                    tone: AknTone.ok,
                    size: AknLampSize.small,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'Bilgi ya da belge size başka yoldan ulaştıysa "Bilgi alındı" ile talebi incelemeye alın; yanıt gelmeyecekse gerekçe yazıp reddedin.',
            style: t.bodySmall.copyWith(color: c.dim),
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

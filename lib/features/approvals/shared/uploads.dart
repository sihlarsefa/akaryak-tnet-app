/// A5 belge yükleme: kaynak seçimi (kamera / galeri), sıkıştırılmış JPEG ve ilerlemeli yükleme
/// (`api/v1/attachments`, Idempotency-Key ile; tekrar denemede aynı anahtar → sunucuda ikinci ek yok).
///
/// Kullanım: ek bilgi yanıtı (sahip ApprovalRequest = 7, tür = istenen tür ?? Diğer) ve tahsilatta
/// "Dekont ekle" (sahip Order = 1, tür = yöntemin belgesi).
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/media/attachment_api.dart';
import '../../../core/media/image_capture.dart';
import '../../../core/models/attachment.dart';
import '../../../core/models/enums.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/network/idempotency.dart';
import '../../../core/ui/ui.dart';
import 'failure_view.dart';

/// Seçilmiş, yüklenmeye hazır görsel.
@immutable
class PickedFile {
  const PickedFile({
    required this.bytes,
    required this.fileName,
    this.contentType = 'image/jpeg',
  });

  final Uint8List bytes;
  final String fileName;
  final String contentType;
}

/// Belge kaynağı (testlerde değiştirilir).
abstract interface class A5FileSource {
  /// Kullanıcıya kaynak sorar ve görseli hazırlar; vazgeçerse null.
  Future<PickedFile?> pick(BuildContext context, AttachmentKind kind);
}

/// Cihaz kaynağı: "Fotoğraf çek" / "Galeriden seç" sayfası, ardından [ImageCapture] (çek / senette
/// kırpma kılavuzu, EXIF silinir, uzun kenar ≤ 1600 px). Sayfa izin isteminden önce gerekçeyi söyler.
class DeviceFileSource implements A5FileSource {
  const DeviceFileSource();

  @override
  Future<PickedFile?> pick(BuildContext context, AttachmentKind kind) async {
    final source = await showAppSheet<CaptureSource>(
      context: context,
      title: '${kind.isUnknown ? 'Belge' : kind.label} ekle',
      subtitle:
          'Belgenin fotoğrafını çekin, galeriden ya da PDF olarak seçin. Belge yalnızca bu kayda '
          'eklenir.',
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AknListTile(
            leadingIcon: Icons.photo_camera_rounded,
            leadingTone: AknTone.brand,
            title: 'Fotoğraf çek',
            subtitle: 'Belgeyi düz bir zemine koyup çekin',
            onTap: () => Navigator.of(ctx).pop(CaptureSource.camera),
          ),
          AknListTile(
            leadingIcon: Icons.photo_library_rounded,
            title: 'Galeriden seç',
            onTap: () => Navigator.of(ctx).pop(CaptureSource.gallery),
          ),
          AknListTile(
            leadingIcon: Icons.picture_as_pdf_rounded,
            title: 'Dosya (PDF)',
            subtitle: 'Hazır belgeyi seçin',
            onTap: () => Navigator.of(ctx).pop(CaptureSource.file),
          ),
        ],
      ),
    );
    if (source == null || !context.mounted) return null;
    final image = await ImageCapture.pick(
      source: source,
      kind: kind,
      context: context,
    );
    if (image == null) return null;
    return PickedFile(
      bytes: image.bytes,
      fileName: image.fileName,
      contentType: image.contentType,
    );
  }
}

final a5FileSourceProvider = Provider<A5FileSource>(
  (ref) => const DeviceFileSource(),
);

/// Yükleme hedefi (aile anahtarı).
@immutable
class UploadTarget {
  const UploadTarget(this.ownerType, this.ownerId);

  final AttachmentOwnerType ownerType;
  final int ownerId;

  @override
  bool operator ==(Object other) =>
      other is UploadTarget &&
      other.ownerType == ownerType &&
      other.ownerId == ownerId;

  @override
  int get hashCode => Object.hash(ownerType, ownerId);
}

enum UploadPhase { uploading, failed, done }

/// Bu oturumda eklenen bir dosya.
@immutable
class UploadItem {
  const UploadItem({
    required this.localId,
    required this.file,
    required this.kind,
    required this.phase,
    required this.idempotencyKey,
    this.progress = 0,
    this.attachment,
    this.error,
  });

  final String localId;
  final PickedFile file;
  final AttachmentKind kind;
  final UploadPhase phase;
  final String idempotencyKey;
  final double progress;

  /// Sunucudaki ek (yüklendiyse).
  final Attachment? attachment;
  final String? error;

  UploadItem copyWith({
    UploadPhase? phase,
    double? progress,
    Attachment? attachment,
    String? Function()? error,
  }) => UploadItem(
    localId: localId,
    file: file,
    kind: kind,
    phase: phase ?? this.phase,
    idempotencyKey: idempotencyKey,
    progress: progress ?? this.progress,
    attachment: attachment ?? this.attachment,
    error: error == null ? this.error : error(),
  );
}

/// Bir kaydın bu oturumdaki yüklemeleri.
final uploadsProvider = NotifierProvider.autoDispose
    .family<UploadsController, List<UploadItem>, UploadTarget>(
      UploadsController.new,
    );

class UploadsController
    extends AutoDisposeFamilyNotifier<List<UploadItem>, UploadTarget> {
  int _seq = 0;

  @override
  List<UploadItem> build(UploadTarget arg) {
    ref.watch(currentUserIdProvider);
    return const [];
  }

  AttachmentApi get _api => ref.read(attachmentApiProvider);

  void _put(UploadItem item) {
    state = [
      for (final i in state)
        if (i.localId == item.localId) item else i,
    ];
  }

  UploadItem? _find(String localId) {
    for (final i in state) {
      if (i.localId == localId) return i;
    }
    return null;
  }

  /// Dosyayı ekler ve yükler. Başarıda sunucudaki eki döner; hatada null (öğe "tekrar dene" bekler).
  Future<Attachment?> add(
    PickedFile file,
    AttachmentKind kind, {
    String? note,
  }) async {
    final item = UploadItem(
      localId: 'u${++_seq}',
      file: file,
      kind: kind,
      phase: UploadPhase.uploading,
      idempotencyKey: newIdempotencyKey(),
    );
    state = [...state, item];
    return _upload(item, note: note);
  }

  Future<Attachment?> retry(String localId) async {
    final item = _find(localId);
    if (item == null || item.phase != UploadPhase.failed) return null;
    final next = item.copyWith(
      phase: UploadPhase.uploading,
      progress: 0,
      error: () => null,
    );
    _put(next);
    return _upload(next);
  }

  Future<Attachment?> _upload(UploadItem item, {String? note}) async {
    try {
      final result = await _api.uploadBytes(
        ownerType: arg.ownerType,
        ownerId: arg.ownerId,
        kind: item.kind,
        bytes: item.file.bytes,
        fileName: item.file.fileName,
        contentType: item.file.contentType,
        note: note,
        idempotencyKey: item.idempotencyKey,
        onProgress: (p) {
          final current = _find(item.localId);
          if (current != null && current.phase == UploadPhase.uploading) {
            _put(current.copyWith(progress: p));
          }
        },
      );
      final current = _find(item.localId);
      if (current != null) {
        _put(
          current.copyWith(
            phase: UploadPhase.done,
            progress: 1,
            attachment: result.attachment,
          ),
        );
      }
      return result.attachment;
    } catch (e) {
      final f = AppFailure.from(e);
      final current = _find(item.localId);
      if (current != null) {
        _put(
          current.copyWith(
            phase: UploadPhase.failed,
            error: () => failureText(f),
          ),
        );
      }
      return null;
    }
  }

  /// Öğeyi kaldırır; yüklendiyse ve silinebiliyorsa sunucudan da siler.
  Future<void> remove(String localId) async {
    final item = _find(localId);
    if (item == null) return;
    final a = item.attachment;
    if (a != null && a.canDelete) {
      try {
        await _api.delete(a.publicId);
      } catch (e) {
        // Silinemeyen ek listede kalır (sunucu reddetti); kullanıcı bilgilendirilir.
        _put(item.copyWith(error: () => failureText(AppFailure.from(e))));
        rethrow;
      }
    }
    state = [
      for (final i in state)
        if (i.localId != localId) i,
    ];
  }

  /// Yüklemesi tamamlanmış ekler.
  List<Attachment> get uploaded => [
    for (final i in state)
      if (i.attachment != null) i.attachment!,
  ];
}

/// Yükleme satırları (ilerleme halkası, tekrar dene, kaldır).
class UploadTiles extends ConsumerWidget {
  const UploadTiles({super.key, required this.target});

  final UploadTarget target;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(uploadsProvider(target));
    if (items.isEmpty) return const SizedBox.shrink();
    final ctrl = ref.read(uploadsProvider(target).notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final i in items)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: AttachmentTile(
              fileName: i.file.fileName,
              kindLabel: i.kind.label,
              sizeBytes: i.file.bytes.length,
              contentType: i.file.contentType,
              thumbnail: i.file.contentType.startsWith('image/')
                  ? Image.memory(
                      i.file.bytes,
                      fit: BoxFit.cover,
                      cacheWidth: 144,
                      gaplessPlayback: true,
                    )
                  : null,
              // Yüklenen dosya "Yüklendi" alt satırıyla durur; silinebiliyorsa kaldırılabilir.
              subtitle: i.phase == UploadPhase.done ? 'Yüklendi' : null,
              state: switch (i.phase) {
                UploadPhase.uploading => AttachmentTileState.uploading,
                UploadPhase.failed => AttachmentTileState.failed,
                UploadPhase.done =>
                  (i.attachment?.canDelete ?? false)
                      ? AttachmentTileState.idle
                      : AttachmentTileState.done,
              },
              progress: i.progress,
              errorText: i.error,
              onRetry: () => unawaited(ctrl.retry(i.localId)),
              onDelete:
                  i.phase == UploadPhase.done &&
                      (i.attachment?.canDelete ?? false)
                  ? () => unawaited(_remove(context, ctrl, i))
                  : null,
            ),
          ),
      ],
    );
  }

  Future<void> _remove(
    BuildContext context,
    UploadsController ctrl,
    UploadItem item,
  ) async {
    try {
      await ctrl.remove(item.localId);
    } on AppFailure catch (f) {
      if (context.mounted) showFailureToast(context, f);
    } catch (_) {}
  }
}

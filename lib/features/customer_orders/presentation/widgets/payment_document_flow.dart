import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/auth/session_controller.dart';
import '../../../../core/media/attachment_api.dart';
import '../../../../core/media/document_picker.dart' as core_doc;
import '../../../../core/media/image_capture.dart';
import '../../../../core/models/models.dart';
import '../../../../core/network/app_failure.dart';
import '../../../../core/network/idempotency.dart';
import '../../../../core/storage/prefs_store.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/log.dart';
import '../../application/loadable.dart';
import '../../copy.dart';
import '../../data/payment_models.dart';
import 'common.dart';

/// Görsel seçici (kamera / galeri; çek ve senette kırpma kılavuzu). Testler geçersiz kılar.
typedef DocumentPicker =
    Future<CapturedImage?> Function(
      BuildContext context,
      CaptureSource source,
      AttachmentKind kind,
    );

final a2DocumentPickerProvider = Provider<DocumentPicker>(
  (ref) =>
      (context, source, kind) =>
          ImageCapture.pick(source: source, kind: kind, context: context),
);

/// Belge yükleyici (Idempotency-Key ile; ilerleme 0..1). Testler geçersiz kılar.
typedef DocumentUploader =
    Future<void> Function({
      required PaymentUploadTarget target,
      required CapturedImage image,
      required String idempotencyKey,
      void Function(double progress)? onProgress,
    });

final a2DocumentUploaderProvider = Provider<DocumentUploader>(
  (ref) =>
      ({
        required target,
        required image,
        required idempotencyKey,
        onProgress,
      }) async {
        await ref
            .read(attachmentApiProvider)
            .uploadBytes(
              ownerType: target.ownerType,
              ownerId: target.ownerId,
              kind: target.kind,
              bytes: image.bytes,
              fileName: image.fileName,
              contentType: image.contentType,
              note: 'Sipariş ödeme belgesi',
              idempotencyKey: idempotencyKey,
              onProgress: onProgress,
            );
      },
);

/// Kamera izni ön sayfası (spec C.7): bir kez açıklanır; "Şimdi değil" 7 gün yeniden gösterilmez.
/// Kullanıcı kamerayı bilerek istediğinde 7 gün içinde doğrudan sistem izni sorulur.
Future<bool> ensureCameraPrimer(BuildContext context, WidgetRef ref) async {
  final uid = ref.read(currentUserIdProvider);
  PrefsStore? prefs;
  try {
    prefs = ref.read(prefsStoreProvider);
  } catch (_) {
    prefs = null;
  }
  if (uid == null || prefs == null) return true;
  if (prefs.getBool(A2Keys.cameraPrimerAccepted(uid))) return true;
  final declined = prefs.getInt(A2Keys.cameraPrimerDeclinedAt(uid));
  if (declined != null &&
      DateTime.now().millisecondsSinceEpoch - declined <
          const Duration(days: 7).inMilliseconds) {
    return true;
  }
  if (!context.mounted) return false;
  final ok = await showAppSheet<bool>(
    context: context,
    showClose: false,
    builder: (ctx) => const _CameraPrimer(),
  );
  if (ok ?? false) {
    await prefs.setBool(A2Keys.cameraPrimerAccepted(uid), true);
    return true;
  }
  await prefs.setInt(
    A2Keys.cameraPrimerDeclinedAt(uid),
    DateTime.now().millisecondsSinceEpoch,
  );
  return false;
}

class _CameraPrimer extends StatelessWidget {
  const _CameraPrimer();

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 4),
        const Align(
          alignment: AlignmentDirectional.centerStart,
          child: FadeUp(
            offset: 8,
            scale: 0.8,
            curve: AknMotion.pop,
            child: AknIconBox(
              icon: PhosphorIconsRegular.camera,
              tone: AknTone.brand,
              size: 52,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Semantics(
          header: true,
          child: Text(
            'Fotoğraf için kameranızı kullanacağız',
            style: t.title.copyWith(color: c.ink),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Çek, senet ya da dekontun fotoğrafını çekip siparişinize ekleyebilmeniz için '
          'kameraya erişim istenecek. Fotoğraf yalnızca ilgili siparişe eklenir.',
          style: t.body.copyWith(color: c.dim),
        ),
        const SizedBox(height: 24),
        AknButton(
          label: 'Devam',
          expand: true,
          onPressed: () => Navigator.of(context).pop(true),
        ),
        const SizedBox(height: 8),
        AknButton.ghost(
          label: 'Şimdi değil',
          expand: true,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}

/// Fotoğraf çek / galeriden seç (kamera için önce ön sayfa).
Future<CapturedImage?> pickDocumentImage(
  BuildContext context,
  WidgetRef ref, {
  required CaptureSource source,
  required AttachmentKind kind,
}) async {
  if (source == CaptureSource.camera) {
    final ok = await ensureCameraPrimer(context, ref);
    if (!ok || !context.mounted) return null;
  }
  return ref.read(a2DocumentPickerProvider)(context, source, kind);
}

/// Ödeme belgesi yükleme sayfası. Yüklendiyse true.
Future<bool> showPaymentDocumentSheet(
  BuildContext context, {
  required PaymentUploadTarget target,
  String? orderNumber,
  CapturedImage? preselected,
}) async {
  final done = await showAppSheet<bool>(
    context: context,
    title: '${target.label} yükleyin',
    subtitle: orderNumber,
    builder: (ctx) => PaymentDocumentPanel(
      target: target,
      orderNumber: orderNumber,
      preselected: preselected,
      onDone: () => Navigator.of(ctx).pop(true),
    ),
  );
  return done ?? false;
}

/// Belge seçme + yükleme paneli (sayfada ya da başarı ekranında gömülü).
class PaymentDocumentPanel extends ConsumerStatefulWidget {
  const PaymentDocumentPanel({
    super.key,
    required this.target,
    this.orderNumber,
    this.preselected,
    this.autoUpload = false,
    this.onDone,
    this.embedded = false,
  });

  final PaymentUploadTarget target;
  final String? orderNumber;

  /// Önceden seçili görsel (sihirbazda eklenen dekont). Panel henüz seçim aşamasındayken sonradan
  /// verilirse de alınır.
  final CapturedImage? preselected;

  /// [preselected] alınınca kendiliğinden yüklenir ("sipariş oluşunca yüklenecek").
  final bool autoUpload;
  final VoidCallback? onDone;

  /// Başarı ekranında kart içinde (başlık panel içinde gösterilir).
  final bool embedded;

  @override
  ConsumerState<PaymentDocumentPanel> createState() =>
      _PaymentDocumentPanelState();
}

enum _UploadPhase { pick, ready, uploading, done, failed }

class _PaymentDocumentPanelState extends ConsumerState<PaymentDocumentPanel> {
  CapturedImage? _image;
  _UploadPhase _phase = _UploadPhase.pick;
  double _progress = 0;
  String? _error;
  String? _key;

  @override
  void initState() {
    super.initState();
    final pre = widget.preselected;
    if (pre != null) _adopt(pre);
  }

  @override
  void didUpdateWidget(PaymentDocumentPanel old) {
    super.didUpdateWidget(old);
    final pre = widget.preselected;
    // Önceden seçili görsel sonradan geldi (ör. dosya okunması sürüyordu): kullanıcı henüz bir şey
    // seçmediyse alınır.
    if (pre != null &&
        pre.path != old.preselected?.path &&
        _phase == _UploadPhase.pick &&
        _image == null) {
      setState(() => _adopt(pre));
    }
  }

  void _adopt(CapturedImage image) {
    _image = image;
    _key = null;
    _phase = _UploadPhase.ready;
    if (widget.autoUpload) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            _phase == _UploadPhase.ready &&
            identical(_image, image)) {
          unawaited(_upload());
        }
      });
    }
  }

  bool get _instrument =>
      widget.target.kind == AttachmentKind.chequeImage ||
      widget.target.kind == AttachmentKind.promissoryNoteImage;

  Future<void> _pick(CaptureSource source) async {
    final img = await pickDocumentImage(
      context,
      ref,
      source: source,
      kind: widget.target.kind,
    );
    if (!mounted || img == null) return;
    setState(() {
      _image = img;
      _key = null;
      _phase = _UploadPhase.ready;
      _error = null;
    });
  }

  Future<void> _upload() async {
    final img = _image;
    if (img == null) return;
    _key ??= newIdempotencyKey();
    setState(() {
      _phase = _UploadPhase.uploading;
      _progress = 0;
      _error = null;
    });
    try {
      await ref.read(a2DocumentUploaderProvider)(
        target: widget.target,
        image: img,
        idempotencyKey: _key!,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      setState(() => _phase = _UploadPhase.done);
      AknHaptics.success();
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          '${widget.target.label} yüklendi',
          TextDirection.ltr,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted) widget.onDone?.call();
    } on AppFailure catch (f) {
      if (!mounted) return;
      AppLog.debug('Belge yüklenemedi: $f');
      setState(() {
        _phase = _UploadPhase.failed;
        _error = f.message;
        if (!f.isUncertain) _key = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final target = widget.target;
    if (!target.isUploadable) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AknBanner(
          tone: AknTone.info,
          icon: PhosphorIconsRegular.info,
          message:
              target.message ??
              'Bu belgeyi yükleme yetkiniz yok; şirket yöneticinize başvurun.',
        ),
      );
    }
    final img = _image;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.embedded) ...[
          Text('${target.label} yükleyin', style: a2SectionTitle(t, c)),
          const SizedBox(height: 4),
        ],
        Text(
          _instrument
              ? 'Görseli düz bir zeminde, köşeleri kılavuz çerçeveye oturacak şekilde çekin. '
                    'Tutar, vade ve seri numarası okunaklı olmalı.'
              : 'Dekontun fotoğrafını çekin ya da galeriden seçin.',
          style: t.body.copyWith(color: c.dim),
        ),
        const SizedBox(height: 12),
        if (img != null)
          AttachmentTile(
            fileName: img.fileName,
            kindLabel: target.label,
            sizeBytes: img.sizeBytes,
            contentType: img.contentType,
            thumbnail: img.isPdf
                ? null
                : Image.memory(
                    img.bytes,
                    fit: BoxFit.cover,
                    cacheWidth: 160,
                    errorBuilder: (_, _, _) =>
                        Icon(PhosphorIconsRegular.image, color: c.dim),
                  ),
            state: switch (_phase) {
              _UploadPhase.uploading => AttachmentTileState.uploading,
              _UploadPhase.done => AttachmentTileState.done,
              _UploadPhase.failed => AttachmentTileState.failed,
              _ => AttachmentTileState.idle,
            },
            progress: _progress,
            errorText: _error,
            onRetry: _phase == _UploadPhase.failed ? _upload : null,
            onDelete: _phase == _UploadPhase.ready
                ? () => setState(() {
                    _image = null;
                    _phase = _UploadPhase.pick;
                  })
                : null,
          ),
        if (img != null) const SizedBox(height: 12),
        if (_phase == _UploadPhase.done) ...[
          AknBanner(
            tone: AknTone.ok,
            icon: PhosphorIconsFill.checkCircle,
            message: _instrument
                ? '${target.label} yüklendi. ${OrdersCopy.instrumentHint}.'
                : '${target.label} yüklendi.',
          ),
        ] else if (_phase == _UploadPhase.ready ||
            _phase == _UploadPhase.uploading ||
            _phase == _UploadPhase.failed) ...[
          AknButton(
            label: _phase == _UploadPhase.failed ? 'Tekrar yükle' : 'Yükle',
            icon: PhosphorIconsRegular.cloudArrowUp,
            expand: true,
            loading: _phase == _UploadPhase.uploading,
            loadingLabel: 'Yükleniyor %${(_progress * 100).round()}',
            onPressed: _phase == _UploadPhase.uploading ? null : _upload,
          ),
          const SizedBox(height: 4),
          AknButton.ghost(
            label: 'Başka fotoğraf seç',
            expand: true,
            onPressed: _phase == _UploadPhase.uploading
                ? null
                : () => _pick(CaptureSource.camera),
          ),
        ] else ...[
          ButtonRowFor(
            children: [
              AknButton(
                label: 'Fotoğraf çek',
                icon: PhosphorIconsRegular.camera,
                expand: true,
                onPressed: () => _pick(CaptureSource.camera),
              ),
              AknButton.secondary(
                label: 'Galeriden seç',
                icon: PhosphorIconsRegular.images,
                expand: true,
                onPressed: () => _pick(CaptureSource.gallery),
              ),
            ],
          ),
          // Dekont ve diğer belgeler hazır PDF olabilir (çek / senet fotoğrafla, kılavuz çerçeveyle).
          if (!_instrument)
            Align(
              alignment: Alignment.centerLeft,
              child: AknButton.ghost(
                label: 'Dosya (PDF) seç',
                icon: PhosphorIconsRegular.filePdf,
                size: AknButtonSize.small,
                onPressed: () => _pick(CaptureSource.file),
              ),
            ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: AknButton.ghost(
              label: 'Kamera açılmıyor mu? Ayarları aç',
              size: AknButtonSize.small,
              onPressed: () async {
                try {
                  await Geolocator.openAppSettings();
                } catch (_) {}
              },
            ),
          ),
        ],
        if (img != null && _phase != _UploadPhase.done)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Dosya: ${Fmt.fileSize(img.sizeBytes)}, JPEG (konum bilgisi silinir)',
              style: t.caption.copyWith(color: c.dim),
            ),
          ),
      ],
    );
  }
}

/// İki düğmeyi yan yana; büyük yazıda alt alta.
class ButtonRowFor extends StatelessWidget {
  const ButtonRowFor({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ButtonRow(children: children);
}

/// Yolu verilen yerel görseli (sihirbazda seçilen dekont) okur; dosya yoksa null.
Future<CapturedImage?> readLocalImage(String? path) async {
  if (path == null) return null;
  try {
    final f = File(path);
    if (!await f.exists()) return null;
    final bytes = await f.readAsBytes();
    return CapturedImage(
      path: path,
      bytes: bytes,
      fileName: path.split(Platform.pathSeparator).last,
      contentType: core_doc.DocumentPicker.isPdf(bytes)
          ? 'application/pdf'
          : 'image/jpeg',
    );
  } catch (_) {
    return null;
  }
}

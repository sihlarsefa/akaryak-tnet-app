import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/media/image_capture.dart';
import '../../../../core/models/enums.dart';
import '../../../../core/network/app_failure.dart';
import '../../../../core/offline/connectivity.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/image_source.dart';
import '../../application/shipments_controller.dart';
import '../../copy.dart';
import '../../data/shipments.dart';
import '../cm_widgets.dart';

/// İtiraz akışı (tam ekran): önce itiraz fotoğrafları yüklenir (DisputePhoto), sonra açıklamayla itiraz
/// gönderilir; ardından "İtirazınız bayiye iletildi…" sonucu gösterilir. Sevkiyat zaten itirazlıysa
/// yalnızca fotoğraf eklenir.
class DisputePage extends ConsumerStatefulWidget {
  const DisputePage({super.key, required this.detail});

  final ShipmentDetail detail;

  @override
  ConsumerState<DisputePage> createState() => _DisputePageState();
}

class _DisputePageState extends ConsumerState<DisputePage> {
  static const maxPhotos = 6;
  static const minNote = 3;
  static const maxNote = 1000;
  static const presets = [
    'Eksik miktar',
    'Fazla miktar',
    'Ürün farklı',
    'Sızıntı / hasar',
    'Belge numarası uyuşmuyor',
  ];

  final _note = TextEditingController();
  final List<DisputePhoto> _photos = [];
  bool _sending = false;
  bool _checking = false;
  bool _done = false;

  ShipmentDetail get d => widget.detail;
  bool get _photoOnly => d.status == ShipmentStatus.disputed;
  bool get _dirty =>
      !_done && (_photos.isNotEmpty || _note.text.trim().isNotEmpty);
  bool get _uploading =>
      _photos.any((p) => !p.uploaded && !p.failed && p.error == null);
  bool get _noteValid {
    final n = _note.text.trim().length;
    return n >= minNote && n <= maxNote;
  }

  @override
  void initState() {
    super.initState();
    _note.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _add(CaptureSource source) async {
    final room = maxPhotos - _photos.length;
    if (room <= 0) return;
    final picker = ref.read(cmImagePickerProvider);
    final List<CapturedImage> images;
    if (source == CaptureSource.gallery) {
      images = await picker.pickMany(limit: room);
    } else {
      final one = await picker.pick(
        context,
        source,
        AttachmentKind.disputePhoto,
      );
      images = [?one];
    }
    if (!mounted || images.isEmpty) return;
    final added = [
      for (final img in images.take(room))
        DisputePhoto(localId: ShipmentCommands.newLocalId(), image: img),
    ];
    setState(() => _photos.addAll(added));
    for (final p in added) {
      unawaited(_upload(p));
    }
  }

  void _update(String localId, DisputePhoto Function(DisputePhoto) f) {
    if (!mounted) return;
    setState(() {
      final i = _photos.indexWhere((x) => x.localId == localId);
      if (i >= 0) _photos[i] = f(_photos[i]);
    });
  }

  Future<void> _upload(DisputePhoto p) async {
    _update(p.localId, (x) => x.copyWith(clearError: true, progress: 0));
    try {
      final id = await ref
          .read(shipmentCommandsProvider)
          .uploadPhoto(
            d.id,
            p,
            onProgress: (v) =>
                _update(p.localId, (x) => x.copyWith(progress: v)),
          );
      _update(p.localId, (x) => x.copyWith(uploadedPublicId: id, progress: 1));
    } catch (e) {
      _update(
        p.localId,
        (x) => x.copyWith(error: failureText(AppFailure.from(e))),
      );
    }
  }

  Future<void> _remove(DisputePhoto p) async {
    final id = p.uploadedPublicId;
    setState(() => _photos.removeWhere((x) => x.localId == p.localId));
    if (id != null) {
      try {
        await ref.read(shipmentCommandsProvider).removePhoto(id);
      } catch (_) {
        // Silinemezse itiraz yine gönderilebilir; bayi fotoğrafı görür.
      }
    }
  }

  Future<bool> _ensureUploaded() async {
    for (final p in _photos.where((x) => x.failed).toList()) {
      await _upload(p);
    }
    while (mounted && _uploading) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return !_photos.any((x) => !x.uploaded);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _checking = false;
    });
    try {
      final ok = await _ensureUploaded();
      if (!ok) {
        if (mounted) {
          AppToast.error(
            'Bazı fotoğraflar yüklenemedi. Tekrar deneyin ya da kaldırın.',
            context: context,
          );
        }
        return;
      }
      if (_photoOnly) {
        if (mounted) setState(() => _done = true);
        return;
      }
      await ref
          .read(shipmentCommandsProvider)
          .dispute(
            d.id,
            _note.text,
            onChecking: () {
              if (mounted) setState(() => _checking = true);
            },
          );
      if (!mounted) return;
      AknHaptics.success();
      setState(() => _done = true);
    } catch (e) {
      if (mounted) showFailureToast(context, e);
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _checking = false;
        });
      }
    }
  }

  Future<void> _close() async {
    if (_done) {
      Navigator.of(context).pop(true);
      return;
    }
    if (!_dirty) {
      Navigator.of(context).pop(false);
      return;
    }
    final leave = await showConfirmSheet(
      context,
      title: CmCopy.unsaved,
      message: 'İtiraz gönderilmedi. Yüklenen fotoğraflar sevkiyatta kalır.',
      confirmLabel: 'Çık',
      cancelLabel: 'Devam et',
      destructive: true,
    );
    if (leave && mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final online = ref.watch(isOnlineProvider);
    if (_done) {
      return AppScaffold(
        title: _photoOnly ? 'Fotoğraflar eklendi' : 'İtiraz gönderildi',
        automaticallyImplyLeading: false,
        showBell: false,
        body: ListView(
          children: [
            ResultView(
              title: _photoOnly
                  ? 'Fotoğraflar itiraza eklendi'
                  : 'İtirazınız iletildi',
              message: _photoOnly
                  ? 'Bayiniz eklediğiniz fotoğrafları görebilir.'
                  : CmCopy.disputeSent,
              primaryLabel: 'Teslimata dön',
              onPrimary: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );
    }
    final t = context.aknText;
    final c = context.akn;
    final canSend =
        online && !_sending && (_photoOnly ? _photos.isNotEmpty : _noteValid);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: AppScaffold(
        title: _photoOnly ? 'İtiraza fotoğraf ekle' : 'Teslimata itiraz et',
        subtitle: '${d.code}, ${d.orderNumber}',
        showBell: false,
        leading: IconButton(
          tooltip: 'Kapat',
          icon: const Icon(PhosphorIconsRegular.x),
          onPressed: _close,
        ),
        actionBar: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!online)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  CmCopy.offlineAction,
                  style: t.caption,
                  textAlign: TextAlign.center,
                ),
              )
            else if (_checking)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  CmCopy.disputeChecking,
                  style: t.caption,
                  textAlign: TextAlign.center,
                ),
              ),
            AknButton(
              label: _photoOnly ? 'Fotoğrafları ekle' : 'İtirazı gönder',
              expand: true,
              loading: _sending,
              loadingLabel: _checking ? CmCopy.disputeChecking : 'Gönderiliyor',
              onPressed: canSend ? _submit : null,
            ),
          ],
        ),
        // Kartlar birbiri ardına yükselerek gelir (v3 §5).
        body: CmRiseScope(
          child: ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            children: [
              if (d.isDelivered)
                CmRise(
                  key: const ValueKey('facts'),
                  index: 0,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: CmCard(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                      child: Column(
                        children: [
                          FactRow(
                            label: 'Teslim edilen',
                            value: Fmt.liters(d.deliveredLiters),
                          ),
                          FactRow(
                            label: 'Planlanan',
                            value: Fmt.liters(d.plannedLiters),
                          ),
                          if (d.deliveryDocumentNo != null)
                            FactRow(
                              label: 'İrsaliye no',
                              value: d.deliveryDocumentNo!,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              CmRise(
                key: const ValueKey('photos'),
                index: 1,
                child: CmSection(
                  title: _photoOnly
                      ? 'Fotoğraflar'
                      : '1. Fotoğraflar (isteğe bağlı)',
                  subtitle: CmCopy.disputePhotoHint,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final p in _photos)
                        AttachmentTile(
                          fileName: p.image.fileName,
                          kindLabel: 'İtiraz fotoğrafı',
                          sizeBytes: p.image.sizeBytes,
                          contentType: p.image.contentType,
                          thumbnail: Image.memory(
                            p.image.bytes,
                            fit: BoxFit.cover,
                            cacheWidth: 160,
                          ),
                          state: p.uploaded
                              ? AttachmentTileState.done
                              : (p.error != null
                                    ? AttachmentTileState.failed
                                    : AttachmentTileState.uploading),
                          progress: p.progress,
                          errorText: p.error,
                          onRetry: p.error == null ? null : () => _upload(p),
                          onDelete: _sending ? null : () => _remove(p),
                        ),
                      if (_photos.length < maxPhotos)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              AknButton.secondary(
                                label: 'Fotoğraf çek',
                                icon: PhosphorIconsRegular.camera,
                                size: AknButtonSize.small,
                                onPressed: _sending || !online
                                    ? null
                                    : () => _add(CaptureSource.camera),
                              ),
                              AknButton.secondary(
                                label: 'Galeriden seç',
                                icon: PhosphorIconsRegular.images,
                                size: AknButtonSize.small,
                                onPressed: _sending || !online
                                    ? null
                                    : () => _add(CaptureSource.gallery),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (!_photoOnly)
                CmRise(
                  key: const ValueKey('note'),
                  index: 2,
                  child: CmSection(
                    title: '2. Açıklama',
                    subtitle: CmCopy.disputeNoteHint,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 0,
                          children: [
                            for (final preset in presets)
                              ActionChip(
                                label: Text(preset),
                                onPressed: _sending
                                    ? null
                                    : () {
                                        final cur = _note.text.trim();
                                        _note.text = cur.isEmpty
                                            ? preset
                                            : (cur.contains(preset)
                                                  ? cur
                                                  : '$cur, $preset');
                                        _note.selection =
                                            TextSelection.collapsed(
                                              offset: _note.text.length,
                                            );
                                      },
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        AknTextField(
                          controller: _note,
                          label: 'İtiraz açıklaması',
                          requiredMark: true,
                          minLines: 3,
                          maxLines: 6,
                          maxLength: maxNote,
                          enabled: !_sending,
                          textCapitalization: TextCapitalization.sentences,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          helper:
                              '${_note.text.trim().length}/$maxNote karakter',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Gönderdiğinizde bayiniz bilgilendirilir. Düzeltme bildirildiğinde teslimatı yeniden onaylamanız istenir.',
                          style: t.caption.copyWith(color: c.dim),
                        ),
                      ],
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

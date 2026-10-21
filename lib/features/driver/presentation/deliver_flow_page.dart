import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/media/attachment_api.dart';
import '../../../core/media/signature_pad.dart';
import '../../../core/models/models.dart';
import '../../../core/network/app_failure.dart';
import '../../../core/offline/outbox_op.dart';
import '../../../core/offline/outbox_providers.dart';
import '../../../core/offline/outbox_store.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/format.dart';
import '../../../core/utils/turkish_text.dart';
import '../application/camera.dart';
import '../application/deliver_flow.dart';
import '../application/driver_home_state.dart';
import '../application/driver_lists.dart';
import '../application/driver_ops.dart';
import '../application/location.dart';
import '../copy.dart';
import '../data/deliver_draft.dart';
import '../data/driver_models.dart';
import '../driver_paths.dart';
import 'widgets/litre_keypad.dart';
import 'widgets/location_card.dart';
import 'widgets/op_status.dart';
import 'widgets/permission_primer.dart';
import 'widgets/photo_grid.dart';
import 'widgets/waiver_sheet.dart';

/// "Teslim et" / "Teslimatı düzelt" sihirbazı (spec A.4 A7): litre tuş takımı (en fazla planlanan) →
/// irsaliye no → teslim alan → fotoğraflar → imza ya da "İmza alınamıyor" → özet → kaydırarak onay.
/// Her adım yerelde saklanır (24 saat). Onaylanınca teslim bekleyen işlem olarak kuyruğa yazılır;
/// sonuç ekranı işlemin durumunu izler (gönderiliyor / kaydedildi / gönderildi / reddedildi + Düzelt).
class DeliverFlowPage extends ConsumerStatefulWidget {
  const DeliverFlowPage({super.key, required this.id});

  final int id;

  @override
  ConsumerState<DeliverFlowPage> createState() => _DeliverFlowPageState();
}

class _DeliverFlowPageState extends ConsumerState<DeliverFlowPage> {
  DeliverFlowModel? _model;
  late final LocationCapture _location;
  final SignaturePadController _pad = SignaturePadController();
  final TextEditingController _doc = TextEditingController();
  final TextEditingController _recipient = TextEditingController();
  final TextEditingController _note = TextEditingController();
  late final AppLifecycleListener _lifecycle;
  late final DriverDraftsController _drafts;

  /// Düzeltilen işlemin dosyaları (taslaktan çıkarılsa da silinmez; işlem hâlâ onlara sahip).
  Set<String> _protected = const {};

  /// Hata gösterilecek adımlar (kullanıcı "İleri" dedi).
  final Set<DeliverStep> _showErrors = {};
  String? _message;
  bool _cameraDenied = false;
  bool _autoPrimerTried = false;
  Key _slideKey = UniqueKey();

  /// Gönderilen işlem (sonuç ekranı).
  String? _submittedId;
  OutboxOp? _submitted;

  /// Kullanıcı çıkmayı seçti (geri hareketi engellenmez).
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _location = LocationCapture(ref.read(driverLocationServiceProvider));
    _drafts = ref.read(driverDraftsProvider.notifier);
    _lifecycle = AppLifecycleListener(
      onInactive: _persistInBackground,
      onHide: _persistInBackground,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _model?.dispose();
    _location.dispose();
    _pad.dispose();
    _doc.dispose();
    _recipient.dispose();
    _note.dispose();
    final drafts = _drafts;
    Future.microtask(drafts.reload);
    super.dispose();
  }

  void _persistInBackground() {
    unawaited(() async {
      await _captureSignature();
      await _model?.flush();
    }());
  }

  // ------------------------------------------------------------------ Kurulum

  void _ensureModel(DriverShipmentDetail detail) {
    if (_model != null) return;
    final uid = ref.read(currentUserIdProvider);
    if (uid == null) return;
    final store = ref.read(deliverDraftStoreProvider);
    final saved = store.get(uid, detail.id);
    final model = DeliverFlowModel(
      userId: uid,
      detail: detail,
      store: store,
      initial: saved,
      correction: detail.row.isDisputed,
    )..addListener(_onModel);
    _model = model;
    _doc.text = model.draft.documentNo;
    _recipient.text = model.draft.recipientName;
    _note.text = model.draft.note;
    final fixId = saved?.fixOpId;
    if (fixId != null) unawaited(_protectFilesOf(fixId));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _location.ensurePrimed();
      if (mounted && model.step == DeliverStep.summary) _maybeAutoPrimer();
    });
  }

  Future<void> _protectFilesOf(String opId) async {
    final op = await ref.read(outboxStoreProvider).get(opId);
    if (op != null && mounted) setState(() => _protected = op.files.toSet());
  }

  void _onModel() {
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------------ Adımlar

  Future<void> _next() async {
    final model = _model!;
    if (model.step == DeliverStep.signature) await _captureSignature();
    final before = model.step;
    final error = model.next();
    if (error != null) {
      AknHaptics.warning();
      _showErrors.add(before);
      setState(() => _message = error);
      _announce(error);
      return;
    }
    setState(() => _message = null);
    FocusManager.instance.primaryFocus?.unfocus();
    await model.flush();
    if (model.step == DeliverStep.summary) {
      await _location.ensurePrimed();
      if (mounted) _maybeAutoPrimer();
    }
  }

  void _back() {
    final model = _model!;
    FocusManager.instance.primaryFocus?.unfocus();
    if (model.step == DeliverStep.signature) unawaited(_captureSignature());
    setState(() => _message = null);
    model.back();
  }

  void _goTo(DeliverStep s) {
    setState(() => _message = null);
    _model?.goTo(s);
  }

  /// Konum zorunluysa ve izin hiç sorulmadıysa ön sayfa kendiliğinden bir kez gösterilir
  /// (reddedildiyse 7 gün gösterilmez).
  void _maybeAutoPrimer() {
    final model = _model;
    if (model == null || _autoPrimerTried || !model.gpsRequired) return;
    if (_location.phase != LocationPhase.needsPermission) return;
    _autoPrimerTried = true;
    unawaited(requestLocation(context, ref, _location, auto: true));
  }

  void _announce(String text) => unawaited(
    SemanticsService.sendAnnouncement(
      View.of(context),
      text,
      Directionality.of(context),
    ),
  );

  // ------------------------------------------------------------------ Fotoğraf / imza

  Future<void> _takePhoto() async {
    final camera = ref.read(driverCameraProvider);
    final prefs = ref.read(driverPrimerPrefsProvider);
    if (camera.needsCameraPrimer && prefs.cameraPrimerNeeded) {
      final ok = await showDriverPrimer(context, kind: DriverPrimerKind.camera);
      if (!ok) {
        await prefs.cameraDeclined();
        return;
      }
      await prefs.cameraAccepted();
    }
    final res = await camera.takePhoto();
    await _handleCapture(res);
  }

  Future<void> _pickPhotos() async {
    final model = _model!;
    final room = 20 - model.photoCount;
    if (room <= 0) {
      setState(() => _message = DriverCopy.photoMax);
      return;
    }
    final res = await ref
        .read(driverCameraProvider)
        .pickFromGallery(limit: room.clamp(1, 6));
    await _handleCapture(res);
  }

  Future<void> _handleCapture(CaptureResult res) async {
    switch (res.status) {
      case CaptureStatus.cancelled:
        return;
      case CaptureStatus.denied:
        if (mounted) setState(() => _cameraDenied = true);
        return;
      case CaptureStatus.failed:
        if (mounted) AppToast.error(DriverCopy.photoFailed, context: context);
        return;
      case CaptureStatus.ok:
        break;
    }
    final files = ref.read(driverFileStoreProvider);
    final kept = <String>[];
    for (final p in res.paths) {
      try {
        kept.add(await files.persistFile(p));
      } catch (_) {
        // Tek dosya kopyalanamadıysa diğerleri eklenir.
      }
    }
    if (!mounted) return;
    if (kept.isEmpty) {
      AppToast.error(DriverCopy.photoFailed, context: context);
      return;
    }
    setState(() {
      _cameraDenied = false;
      _message = null;
    });
    _model?.addPhotos(kept);
    unawaited(_model?.flush());
  }

  void _removePhoto(int index) {
    final model = _model;
    if (model == null || index < 0 || index >= model.draft.photos.length) {
      return;
    }
    final photo = model.draft.photos[index];
    final path = model.removePhoto(index);
    if (path != null && !_protected.contains(path)) {
      ref.read(driverFileStoreProvider).deleteAll([path]);
    }
    // Reddedilen önceki denemede yüklenmiş fotoğraf: sunucudaki ek de kaldırılır (yükleyen şoför, yolda
    // iken silebilir). Önceki teslimatın kanıtına (düzeltme) dokunulmaz. Başarısızlık sessizdir.
    final publicId = photo.publicId;
    if (publicId != null && !photo.fromServer) {
      unawaited(
        ref
            .read(attachmentApiProvider)
            .delete(publicId)
            .catchError((Object _) {}),
      );
    }
  }

  /// Çizilmiş imzayı PNG olarak kalıcı klasöre yazar ve taslağa ekler.
  Future<void> _captureSignature() async {
    final model = _model;
    if (model == null || _pad.isEmpty) return;
    if (model.draft.waiver != null) return;
    final png = await _pad.toPng();
    if (png == null) return;
    final path = await ref
        .read(driverFileStoreProvider)
        .persistBytes(png, extension: 'png');
    _pad.clear();
    final old = model.draft.signaturePath;
    model.setSignature(path);
    if (old != null && old != path && !_protected.contains(old)) {
      ref.read(driverFileStoreProvider).deleteAll([old]);
    }
  }

  void _redoSignature() {
    final old = _model?.clearSignature();
    if (old != null && !_protected.contains(old)) {
      ref.read(driverFileStoreProvider).deleteAll([old]);
    }
  }

  Future<void> _chooseWaiver() async {
    final model = _model!;
    final w = await showWaiverSheet(context, initial: model.draft.waiver);
    if (w == null || !mounted) return;
    _pad.clear();
    final old = model.setWaiver(w);
    if (old != null && !_protected.contains(old)) {
      ref.read(driverFileStoreProvider).deleteAll([old]);
    }
    setState(() => _message = null);
    if (model.photoCount == 0) {
      setState(() => _message = DriverCopy.waiverNeedsPhoto);
      model.goTo(DeliverStep.photos);
      _announce(DriverCopy.waiverNeedsPhoto);
    }
  }

  // ------------------------------------------------------------------ Gönder / çık

  bool get _locationOk {
    final model = _model;
    if (model == null) return false;
    if (!model.gpsRequired) return true;
    return _location.hasPosition;
  }

  bool get _ready => (_model?.isComplete ?? false) && _locationOk;

  Future<void> _submit() async {
    final model = _model;
    if (model == null || !_ready) return;
    try {
      final liters = model.liters!;
      final position = model.gpsRequired || _location.hasPosition
          ? await _location.latest()
          : null;
      final op = await ref
          .read(driverCommandsProvider)
          .deliver(draft: model.draft, liters: liters, position: position);
      model.markSubmitted();
      if (!mounted) return;
      setState(() {
        _submittedId = op.id;
        _submitted = op;
      });
    } catch (e) {
      final f = AppFailure.from(e);
      if (!mounted) return;
      AppToast.error(f.message, context: context);
      setState(() => _slideKey = UniqueKey());
    }
  }

  Future<void> _close() async {
    final model = _model;
    if (_submittedId != null || model == null || !model.isDirty) {
      if (mounted) unawaited(Navigator.of(context).maybePop());
      return;
    }
    await _captureSignature();
    if (!mounted) return;
    final choice = await showAppSheet<_LeaveChoice>(
      context: context,
      showClose: false,
      builder: (ctx) => const _LeaveSheet(),
    );
    if (!mounted) return;
    switch (choice) {
      case _LeaveChoice.keep:
        await model.flush();
      case _LeaveChoice.discard:
        await model.discard(keep: _protected);
      case _LeaveChoice.stay || null:
        return;
    }
    if (mounted) {
      setState(() => _leaving = true);
      Navigator.of(context).pop();
    }
  }

  Future<void> _fixAgain(OutboxOp op) async {
    final draft = await ref.read(driverCommandsProvider).draftForFix(op.id);
    if (!mounted || draft == null) return;
    final detail = _model?.detail;
    _model?.removeListener(_onModel);
    _model?.dispose();
    _model = null;
    _pad.clear();
    setState(() {
      _submittedId = null;
      _submitted = null;
      _showErrors.clear();
      _message = null;
      _slideKey = UniqueKey();
    });
    if (detail != null) _ensureModel(detail);
  }

  Future<void> _discardSubmitted(OutboxOp op) async {
    final ok = await showConfirmSheet(
      context,
      title: DriverCopy.discardOpTitle,
      message: DriverCopy.discardOpBody,
      confirmLabel: 'Sil',
      cancelLabel: DriverCopy.opDiscard,
      destructive: true,
    );
    if (!ok) return;
    await ref.read(driverCommandsProvider).discard(op.id);
    if (mounted) unawaited(Navigator.of(context).maybePop());
  }

  void _backToList() => context.go(DriverPaths.home);

  // ------------------------------------------------------------------ Görünüm

  @override
  Widget build(BuildContext context) {
    final submittedId = _submittedId;
    if (submittedId != null) return _result(submittedId);

    final async = ref.watch(driverShipmentProvider(widget.id));
    final detail = async.valueOrNull?.detail;
    if (detail == null) {
      return AppScaffold(
        title: DriverCopy.flowTitle,
        showBell: false,
        leading: _closeButton(),
        body: async.hasError
            ? Center(
                child: SingleChildScrollView(
                  child: ErrorState(
                    offline: AppFailure.from(async.error!) is OfflineFailure,
                    message: AppFailure.from(async.error!).message,
                    onRetry: () => unawaited(
                      ref
                          .read(driverShipmentProvider(widget.id).notifier)
                          .refresh(),
                    ),
                  ),
                ),
              )
            : const LoadingView(),
      );
    }
    final ops = ref.watchDriverOps()[detail.id];
    final blocked = _blockedReason(detail, ops);
    if (blocked != null) return _blockedView(detail, blocked);

    _ensureModel(detail);
    final model = _model;
    if (model == null) return const SizedBox.shrink();
    final step = model.step;

    return PopScope(
      canPop: !model.isDirty || _leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: AppScaffold(
        title: model.draft.correction
            ? DriverCopy.flowFixTitle
            : DriverCopy.flowTitle,
        subtitle: [detail.code, ?detail.row.customerTitle].join(' · '),
        showBell: false,
        leading: _closeButton(),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StepperHeader(steps: DriverCopy.stepShort, current: step.index),
            Expanded(
              child: SharedAxisSwitcher(
                reverse: model.reverse,
                child: KeyedSubtree(
                  key: ValueKey(step),
                  child: _stepBody(model, step),
                ),
              ),
            ),
          ],
        ),
        actionBar: _bottom(model, step),
      ),
    );
  }

  Widget _closeButton() => IconButton(
    tooltip: DriverCopy.close,
    onPressed: () => unawaited(_close()),
    icon: const Icon(Icons.close_rounded),
  );

  String? _blockedReason(DriverShipmentDetail d, DriverShipmentOps? ops) {
    final fixing = _model?.draft.fixOpId;
    final deliver = ops?.deliver;
    if (deliver != null && deliver.status.isWaiting && deliver.id != fixing) {
      return DriverCopy.deliverAlreadyQueued;
    }
    if (d.actions.canDeliver) return null;
    if (d.row.isPlanned && (ops?.startWaiting ?? false)) return null;
    if (d.row.isPlanned) return DriverCopy.flowBlockedPlanned;
    return DriverCopy.reportedLocked;
  }

  Widget _blockedView(DriverShipmentDetail d, String reason) => AppScaffold(
    title: DriverCopy.flowTitle,
    subtitle: d.code,
    showBell: false,
    leading: _closeButton(),
    body: Center(
      child: SingleChildScrollView(
        child: EmptyState(
          title: DriverCopy.flowBlockedTitle,
          message: reason,
          illustration: AknIllustration.delivery,
          actionLabel: DriverCopy.backToList,
          onAction: () => Navigator.of(context).maybePop(),
        ),
      ),
    ),
  );

  Widget _stepBody(DeliverFlowModel model, DeliverStep step) {
    final message = _message;
    final children = switch (step) {
      DeliverStep.liters => _litersStep(model),
      DeliverStep.document => _documentStep(model),
      DeliverStep.recipient => _recipientStep(model),
      DeliverStep.photos => _photosStep(model),
      DeliverStep.signature => _signatureStep(model),
      DeliverStep.summary => _summaryStep(model),
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        ...children,
        if (message != null && step != DeliverStep.liters) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: AknBanner(tone: AknTone.warn, message: message),
          ),
        ],
      ],
    );
  }

  List<Widget> _litersStep(DeliverFlowModel model) {
    final t = context.aknText;
    final showError =
        _showErrors.contains(DeliverStep.liters) ||
        model.draft.litersText.isNotEmpty;
    return [
      Text(DriverCopy.litersHint, style: t.bodySmall),
      const SizedBox(height: 12),
      LitersDisplay(
        text: model.draft.litersText,
        error: showError ? model.litersError : null,
        warning: model.tankWarning,
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          StatusChip(
            label: DriverCopy.plannedChip(Fmt.liters(model.plannedLiters)),
            tone: AknTone.info,
            icon: Icons.local_gas_station_rounded,
          ),
          AknButton.secondary(
            label: DriverCopy.fillPlanned,
            size: AknButtonSize.small,
            onPressed: model.fillPlanned,
          ),
        ],
      ),
      const SizedBox(height: 16),
      LitreKeypad(onKey: model.key, onClear: model.clearLiters),
    ];
  }

  List<Widget> _documentStep(DeliverFlowModel model) {
    final t = context.aknText;
    return [
      Text(DriverCopy.documentHint, style: t.bodySmall),
      const SizedBox(height: 12),
      AknTextField(
        controller: _doc,
        label: DriverCopy.documentLabel,
        requiredMark: true,
        prefixIcon: Icons.receipt_long_rounded,
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.next,
        maxLength: 100,
        errorText: _showErrors.contains(DeliverStep.document)
            ? model.documentError
            : null,
        onChanged: model.setDocument,
        onSubmitted: (_) => unawaited(_next()),
      ),
    ];
  }

  List<Widget> _recipientStep(DeliverFlowModel model) {
    final t = context.aknText;
    final contact = model.detail.contactName;
    return [
      Text(DriverCopy.recipientHint, style: t.bodySmall),
      const SizedBox(height: 12),
      AknTextField(
        controller: _recipient,
        label: DriverCopy.recipientLabel,
        prefixIcon: Icons.person_rounded,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.name],
        maxLength: 150,
        errorText: model.recipientError,
        onChanged: model.setRecipient,
        onSubmitted: (_) => unawaited(_next()),
      ),
      if (contact != null && model.draft.recipientName.trim().isEmpty) ...[
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: AknButton.ghost(
            label: '${DriverCopy.recipientUseContact}: $contact',
            icon: Icons.person_add_alt_1_rounded,
            size: AknButtonSize.small,
            onPressed: () {
              _recipient.text = contact;
              model.setRecipient(contact);
            },
          ),
        ),
      ],
    ];
  }

  List<Widget> _photosStep(DeliverFlowModel model) {
    final t = context.aknText;
    final c = context.akn;
    final required = model.photoRequired;
    return [
      Text(DriverCopy.photosHint, style: t.bodySmall),
      const SizedBox(height: 6),
      Row(
        children: [
          Icon(
            required ? Icons.photo_camera_rounded : Icons.info_outline_rounded,
            size: 16,
            color: required && model.photoCount == 0 ? c.warn.fg : c.dim,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              required ? DriverCopy.photosRequired : DriverCopy.photosOptional,
              style: t.caption.copyWith(
                color: required && model.photoCount == 0 ? c.warn.fg : c.dim,
              ),
            ),
          ),
          if (model.photoCount > 0)
            Text(
              DriverCopy.photoCount(model.photoCount),
              style: t.captionStrong,
            ),
        ],
      ),
      const SizedBox(height: 12),
      PhotoGrid(
        photos: model.draft.photos,
        onRemove: _removePhoto,
        onAdd: model.photoCount < 20 ? () => unawaited(_takePhoto()) : null,
      ),
      if (_cameraDenied) ...[
        const SizedBox(height: 12),
        AknBanner(
          tone: AknTone.warn,
          icon: Icons.no_photography_rounded,
          title: DriverCopy.cameraDenied,
          message: DriverCopy.cameraDeniedBody,
          actionLabel: DriverCopy.locationOpenSettings,
          onAction: () => unawaited(
            ref.read(driverLocationServiceProvider).openAppSettings(),
          ),
        ),
      ],
      const SizedBox(height: 16),
      AknButton(
        label: DriverCopy.photoTake,
        icon: Icons.photo_camera_rounded,
        expand: true,
        onPressed: model.photoCount < 20 ? () => unawaited(_takePhoto()) : null,
      ),
      const SizedBox(height: 8),
      AknButton.secondary(
        label: DriverCopy.photoPick,
        icon: Icons.photo_library_rounded,
        expand: true,
        onPressed: model.photoCount < 20
            ? () => unawaited(_pickPhotos())
            : null,
      ),
    ];
  }

  List<Widget> _signatureStep(DeliverFlowModel model) {
    final t = context.aknText;
    final c = context.akn;
    final waiver = model.draft.waiver;
    final path = model.draft.signaturePath;
    final hasRemoteSignature =
        path == null && model.draft.signaturePublicId != null;
    if (waiver != null) {
      return [
        AknCard(
          color: c.warn.bg,
          borderColor: c.warn.line,
          shadow: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.edit_off_rounded, color: c.warn.fg),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          DriverCopy.signatureWaived,
                          style: t.bodyStrong.copyWith(color: c.warn.fg),
                        ),
                        const SizedBox(height: 2),
                        Text(waiver.text, style: t.body),
                        const SizedBox(height: 6),
                        Text(DriverCopy.waiverSubtitle, style: t.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  AknButton.ghost(
                    label: DriverCopy.waiverChange,
                    size: AknButtonSize.small,
                    onPressed: () => unawaited(_chooseWaiver()),
                  ),
                  AknButton.secondary(
                    label: DriverCopy.waiverBackToSignature,
                    icon: Icons.draw_rounded,
                    size: AknButtonSize.small,
                    onPressed: model.clearWaiver,
                  ),
                ],
              ),
            ],
          ),
        ),
      ];
    }
    final hint = model.signatureRequired
        ? DriverCopy.signatureHint
        : '${DriverCopy.signatureHint} ${DriverCopy.signatureOptional}';
    return [
      Text(hint, style: t.bodySmall),
      const SizedBox(height: 12),
      if (path != null || hasRemoteSignature) ...[
        Semantics(
          image: true,
          label: DriverCopy.signatureTaken,
          child: Container(
            height: 200,
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: AknRadius.card,
              border: Border.all(color: c.lineStrong),
            ),
            clipBehavior: Clip.antiAlias,
            child: path != null
                ? Image.file(
                    File(path),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  )
                : const Center(
                    child: Icon(
                      Icons.verified_rounded,
                      color: Color(0xFF15803D),
                      size: 40,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(Icons.check_circle_rounded, size: 18, color: c.ok.fg),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                DriverCopy.signatureTaken,
                style: t.label.copyWith(color: c.ok.fg),
              ),
            ),
            AknButton.ghost(
              label: DriverCopy.signatureRedo,
              icon: Icons.refresh_rounded,
              size: AknButtonSize.small,
              onPressed: _redoSignature,
            ),
          ],
        ),
      ] else
        SignaturePad(
          controller: _pad,
          height: 220,
          hint: DriverCopy.signaturePadHint,
          ink: const Color(0xFF0F172A),
          background: const Color(0xFFFFFFFF),
          borderColor: c.lineStrong,
        ),
      const SizedBox(height: 12),
      Center(
        child: AknButton.ghost(
          label: DriverCopy.signatureCantGet,
          icon: Icons.edit_off_rounded,
          onPressed: () => unawaited(_chooseWaiver()),
        ),
      ),
      if (_showErrors.contains(DeliverStep.signature) &&
          model.signatureError != null &&
          _pad.isEmpty) ...[
        const SizedBox(height: 4),
        Text(
          model.signatureError!,
          style: t.bodySmall.copyWith(color: c.danger.fg),
          textAlign: TextAlign.center,
        ),
      ],
    ];
  }

  List<Widget> _summaryStep(DeliverFlowModel model) {
    final t = context.aknText;
    final c = context.akn;
    final d = model.draft;
    final liters = model.liters;
    final diff = liters == null ? null : liters - model.plannedLiters;
    final missing = model.firstInvalidStep;
    return [
      AknCard(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        child: Column(
          children: [
            _SummaryRow(
              label: DriverCopy.stepLiters,
              value: liters == null ? Fmt.dash : Fmt.liters(liters),
              detail: diff == null || diff.abs() < 0.001
                  ? null
                  : DriverCopy.differenceLine(
                      Fmt.liters(diff.abs()),
                      Fmt.liters(model.plannedLiters),
                      less: diff < 0,
                    ),
              invalid: model.litersError != null,
              onEdit: () => _goTo(DeliverStep.liters),
            ),
            _SummaryRow(
              label: DriverCopy.documentNo,
              value: d.documentNo.trim().isEmpty
                  ? Fmt.dash
                  : d.documentNo.trim(),
              invalid: model.documentError != null,
              onEdit: () => _goTo(DeliverStep.document),
            ),
            _SummaryRow(
              label: DriverCopy.recipient,
              value: d.recipientName.trim().isEmpty
                  ? Fmt.dash
                  : d.recipientName.trim(),
              onEdit: () => _goTo(DeliverStep.recipient),
            ),
            _SummaryRow(
              label: DriverCopy.stepPhotos,
              value: DriverCopy.summaryPhotos(model.photoCount),
              invalid: model.photosError != null,
              onEdit: () => _goTo(DeliverStep.photos),
            ),
            _SummaryRow(
              label: DriverCopy.stepSignature,
              value: d.waiver != null
                  ? '${DriverCopy.signatureWaived}: ${d.waiver!.text}'
                  : d.hasSignature
                  ? DriverCopy.signatureTaken
                  : Fmt.dash,
              invalid: model.signatureError != null,
              onEdit: () => _goTo(DeliverStep.signature),
              last: true,
            ),
          ],
        ),
      ),
      if (d.hasSignature && d.recipientName.trim().isEmpty) ...[
        const SizedBox(height: 12),
        AknBanner(
          tone: AknTone.info,
          message: DriverCopy.summaryRecipientMissing,
          actionLabel: DriverCopy.summaryEdit,
          onAction: () => _goTo(DeliverStep.recipient),
        ),
      ],
      const SizedBox(height: 12),
      LocationCard(capture: _location, required: model.gpsRequired),
      const SizedBox(height: 12),
      AknTextField(
        controller: _note,
        label: DriverCopy.summaryNote,
        hint: DriverCopy.summaryNoteHint,
        maxLines: 3,
        minLines: 2,
        maxLength: 300,
        textCapitalization: TextCapitalization.sentences,
        onChanged: model.setNote,
      ),
      if (missing != null) ...[
        const SizedBox(height: 4),
        Text(
          '${DriverCopy.summaryNotReady} (${DriverCopy.stepShort[missing.index]})',
          style: t.bodySmall.copyWith(color: c.danger.fg),
        ),
      ],
    ];
  }

  Widget _bottom(DeliverFlowModel model, DeliverStep step) {
    if (step == DeliverStep.summary) {
      return ListenableBuilder(
        listenable: _location,
        builder: (context, _) {
          final ready = _ready;
          final reason = !model.isComplete
              ? DriverCopy.summaryNotReady
              : !_locationOk
              ? (model.draft.waiver != null
                    ? DriverCopy.waiverNeedsGps
                    : DriverCopy.summaryNeedsGps)
              : null;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (reason != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    reason,
                    style: context.aknText.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ),
              Row(
                children: [
                  AknIconButton(
                    icon: Icons.arrow_back_rounded,
                    semanticLabel: DriverCopy.back,
                    onPressed: _back,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SlideToConfirm(
                      key: _slideKey,
                      label: DriverCopy.slideDeliver,
                      doneLabel: DriverCopy.slideStartDone,
                      enabled: ready,
                      semanticHint: 'Teslim etmek için iki kez dokunun',
                      onConfirmed: _submit,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_stepButtons(step)],
    );
  }

  Widget _stepButtons(DeliverStep step) {
    return Row(
      children: [
        if (step.previous != null) ...[
          Expanded(
            child: AknButton.secondary(
              label: DriverCopy.back,
              icon: Icons.arrow_back_rounded,
              expand: true,
              onPressed: _back,
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          flex: 2,
          child: AknButton(
            label: DriverCopy.next,
            trailingIcon: Icons.arrow_forward_rounded,
            expand: true,
            onPressed: () => unawaited(_next()),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------ Sonuç

  Widget _result(String opId) {
    final ops = ref.watch(outboxOpsProvider).valueOrNull ?? const <OutboxOp>[];
    final op = ops.where((o) => o.id == opId).firstOrNull ?? _submitted;
    final online = ref.watchOnline();
    final Widget body;
    if (op == null) {
      body = ResultView(
        title: DriverCopy.deliverSentTitle,
        primaryLabel: DriverCopy.backToList,
        onPrimary: _backToList,
      );
    } else {
      body = _DeliverResult(
        op: op,
        online: online,
        onBack: _backToList,
        onRetry: () => unawaited(ref.read(driverCommandsProvider).retry(op.id)),
        onFix: () => unawaited(_fixAgain(op)),
        onDiscard: () => unawaited(_discardSubmitted(op)),
      );
    }
    return AppScaffold(
      title: DriverCopy.flowTitle,
      subtitle: JsonReader.of((op ?? _submitted)?.payload).nonEmpty('code'),
      showBell: false,
      leading: _closeButton(),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: body,
          ),
        ),
      ),
    );
  }
}

enum _LeaveChoice { keep, discard, stay }

class _LeaveSheet extends StatelessWidget {
  const _LeaveSheet();

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        const Center(
          child: AknIconBox(
            icon: Icons.save_outlined,
            tone: AknTone.brand,
            size: 56,
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            DriverCopy.leaveTitle,
            style: t.headline,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          DriverCopy.leaveBody,
          style: t.body.copyWith(color: c.dim),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        AknButton(
          label: DriverCopy.leaveKeep,
          icon: Icons.save_rounded,
          expand: true,
          onPressed: () => Navigator.of(context).pop(_LeaveChoice.keep),
        ),
        const SizedBox(height: 8),
        AknButton.secondary(
          label: DriverCopy.leaveStay,
          expand: true,
          onPressed: () => Navigator.of(context).pop(_LeaveChoice.stay),
        ),
        const SizedBox(height: 4),
        AknButton.ghost(
          label: DriverCopy.leaveDiscard,
          expand: true,
          onPressed: () => Navigator.of(context).pop(_LeaveChoice.discard),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    required this.onEdit,
    this.detail,
    this.invalid = false,
    this.last = false,
  });

  final String label;
  final String value;
  final String? detail;
  final bool invalid;
  final bool last;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.lineSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              label: '$label: $value${detail == null ? '' : ', $detail'}',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: t.caption),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (invalid) ...[
                          Icon(
                            Icons.error_outline_rounded,
                            size: 16,
                            color: c.danger.fg,
                          ),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            value,
                            style: t.bodyStrong.copyWith(
                              color: invalid ? c.danger.fg : null,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (detail != null)
                      Text(detail!, style: t.caption.copyWith(color: c.text)),
                  ],
                ),
              ),
            ),
          ),
          AknIconButton(
            icon: Icons.edit_rounded,
            semanticLabel:
                '$label: ${TurkishText.lower(DriverCopy.summaryEdit)}',
            size: 20,
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

/// Teslim sonucu: işlemin canlı durumu (spec C.4a). Kuyruktayken başarı işareti asla gösterilmez.
class _DeliverResult extends StatefulWidget {
  const _DeliverResult({
    required this.op,
    required this.online,
    required this.onBack,
    required this.onRetry,
    required this.onFix,
    required this.onDiscard,
  });

  final OutboxOp op;
  final bool online;
  final VoidCallback onBack;
  final VoidCallback onRetry;
  final VoidCallback onFix;
  final VoidCallback onDiscard;

  @override
  State<_DeliverResult> createState() => _DeliverResultState();
}

class _DeliverResultState extends State<_DeliverResult> {
  OpPhase? _announced;

  @override
  Widget build(BuildContext context) {
    final op = widget.op;
    final phase = opPhaseOf(op, online: widget.online);
    if (_announced != phase) {
      _announced = phase;
      final text = switch (phase) {
        OpPhase.sending => DriverCopy.sendingTitle,
        OpPhase.queued => DriverCopy.queuedTitle,
        OpPhase.sent => DriverCopy.deliverSentTitle,
        OpPhase.attention => DriverCopy.deliverFailedTitle,
      };
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(
          SemanticsService.sendAnnouncement(
            View.of(context),
            text,
            Directionality.of(context),
          ),
        );
      });
    }
    final r = JsonReader(op.payload);
    final body = r.obj('body');
    final photos = r.list('photos', (p) => p.nonEmpty('publicId') != null);
    final uploaded = photos.where((x) => x).length;
    final details = AknCard(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        children: [
          FactRow(
            label: DriverCopy.delivered,
            value: Fmt.liters(body.decOrNull('deliveredLiters')),
          ),
          FactRow(
            label: DriverCopy.documentNo,
            value: body.str('deliveryDocumentNo', Fmt.dash),
          ),
          if (photos.isNotEmpty)
            FactRow(
              label: DriverCopy.stepPhotos,
              value: phase == OpPhase.sent
                  ? DriverCopy.photoCount(photos.length)
                  : '$uploaded / ${photos.length} yüklendi',
            ),
        ],
      ),
    );

    final Widget view = switch (phase) {
      OpPhase.sending => Padding(
        key: const ValueKey('sending'),
        padding: const EdgeInsets.fromLTRB(24, 48, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: ChevronSpinner(size: 40)),
            const SizedBox(height: 20),
            Semantics(
              liveRegion: true,
              child: Text(
                DriverCopy.sendingTitle,
                style: context.aknText.title,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),
            details,
          ],
        ),
      ),
      OpPhase.queued => ResultView(
        key: const ValueKey('queued'),
        tone: AknTone.warn,
        icon: Icons.schedule_rounded,
        title: DriverCopy.queuedTitle,
        message: DriverCopy.queuedDeliverBody,
        details: details,
        primaryLabel: DriverCopy.backToList,
        onPrimary: widget.onBack,
        secondaryLabel: widget.online ? DriverCopy.opRetry : null,
        onSecondary: widget.online ? widget.onRetry : null,
      ),
      OpPhase.sent => ResultView(
        key: const ValueKey('sent'),
        title: DriverCopy.deliverSentTitle,
        message: DriverCopy.deliverSentBody,
        details: details,
        primaryLabel: DriverCopy.backToList,
        onPrimary: widget.onBack,
      ),
      OpPhase.attention => ResultView(
        key: const ValueKey('attention'),
        tone: AknTone.danger,
        icon: Icons.error_outline_rounded,
        title: DriverCopy.deliverFailedTitle,
        message: op.lastError,
        details: details,
        primaryLabel: DriverCopy.opFix,
        onPrimary: widget.onFix,
        secondaryLabel: DriverCopy.opDiscard,
        onSecondary: widget.onDiscard,
      ),
    };
    return FadeThroughSwitcher(child: view);
  }
}

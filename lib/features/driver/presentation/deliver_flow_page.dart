import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import 'widgets/entrance.dart';
import 'widgets/litre_keypad.dart';
import 'widgets/location_card.dart';
import 'widgets/op_status.dart';
import 'widgets/permission_primer.dart';
import 'widgets/photo_grid.dart';
import 'widgets/stop_plate.dart';
import 'widgets/waiver_sheet.dart';

/// "Teslim et" / "Teslimatı düzelt" sihirbazı (spec A.4 A7, tasarım v3 "Akış" §7.10): sayaç (tuş
/// takımı, en fazla planlanan; plaka okumayı canlı gösterir, rakamlar her tuşta döner) → irsaliye
/// no → teslim alan → fotoğraflar → imza ya da "İmza alınamıyor" → özet → "Teslimatı kaydetmek için
/// kaydırın". Sürücü kipinde çizilir. Adımlar ortak eksende kayarak değişir, adımın içeriği sırayla
/// yükselir; eksik bilgide uyarı kısa bir sarsıntıyla belirir. Her adım yerelde saklanır (24 saat).
/// Onaylanınca teslim bekleyen işlem olarak kuyruğa yazılır; sonuç ekranı işlemin durumunu izler
/// (gönderiliyor / telefona kaydedildi / kaydedildi — çizilen onay, parçacık patlaması ve başarı
/// titreşimi / reddedildi + Düzelt).
class DeliverFlowPage extends StatelessWidget {
  const DeliverFlowPage({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context) =>
      AknDriverScope(child: _DeliverFlowView(id: id));
}

class _DeliverFlowView extends ConsumerStatefulWidget {
  const _DeliverFlowView({required this.id});

  final int id;

  @override
  ConsumerState<_DeliverFlowView> createState() => _DeliverFlowPageState();
}

class _DeliverFlowPageState extends ConsumerState<_DeliverFlowView> {
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

  /// Her reddedilen "İleri"de artar: uyarı satırı kısa bir sarsıntıyla belirir.
  int _shakes = 0;
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
      setState(() {
        _message = error;
        _shakes++;
      });
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
    // Reddedilen önceki denemede yüklenmiş fotoğraf: sunucudaki ek de kaldırılır (yükleyen şoför,
    // yolda iken silebilir). Önceki teslimatın kanıtına (düzeltme) dokunulmaz. Başarısızlık
    // sessizdir.
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

  void _backToList() => backToDriverList(context);

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
        subtitle: [detail.code, ?detail.row.customerTitle].join(', '),
        showBell: false,
        leading: _closeButton(),
        // Büyük yazıda (≥ 1,6×) ilerleme şeridi içerikle kayar: adım içeriğine yer kalır.
        body: _largeText
            ? SharedAxisSwitcher(
                reverse: model.reverse,
                child: KeyedSubtree(
                  key: ValueKey(step),
                  child: _stepBody(
                    model,
                    step,
                    header: StepperHeader(
                      steps: DriverCopy.stepShort,
                      current: step.index,
                      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
                    ),
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  StepperHeader(
                    steps: DriverCopy.stepShort,
                    current: step.index,
                  ),
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
    icon: const Icon(PhosphorIconsRegular.x),
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

  /// Yazı 1,6× ve üstü: şerit ve "Geri" kayan içeriğe geçer, alt raf yalnızca kaydırıcıdır.
  bool get _largeText => MediaQuery.textScalerOf(context).scale(10) >= 16;

  Widget _stepBody(DeliverFlowModel model, DeliverStep step, {Widget? header}) {
    final message = _message;
    // QA LF-1: sayaç adımında tuş takımı alt rafın hemen üstüne sabitlenir (360×640'ta da tümüyle
    // görünür); plaka ve not üstte kayar. Büyük yazıda (≥ 1,6×) her şey birlikte kayar.
    final pinKeypad = step == DeliverStep.liters && !_largeText;
    final children = switch (step) {
      DeliverStep.liters => _litersStep(model, withKeypad: !pinKeypad),
      DeliverStep.document => _documentStep(model),
      DeliverStep.recipient => _recipientStep(model),
      DeliverStep.photos => _photosStep(model),
      DeliverStep.signature => _signatureStep(model),
      DeliverStep.summary => _summaryStep(model),
    };
    final heading = switch (step) {
      DeliverStep.liters => null,
      DeliverStep.document => DriverCopy.stepDocument,
      DeliverStep.recipient => DriverCopy.stepRecipient,
      DeliverStep.photos => DriverCopy.headPhotos,
      DeliverStep.signature => DriverCopy.headSignature,
      DeliverStep.summary => DriverCopy.headSummary,
    };
    final t = context.aknText;
    final c = context.akn;
    // Adımın içeriği sırayla yükselir (adım değişince yeniden; ortak eksen geçişiyle birlikte).
    final list = StaggerScope(
      child: ListView(
        padding: EdgeInsets.fromLTRB(20, 4, 20, pinKeypad ? 8 : 24),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: driverStaggered([
          ?header,
          if (heading != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Semantics(
                header: true,
                child: Text(
                  heading,
                  style: t.title.copyWith(
                    color: c.ink,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
          ...children,
          if (step != DeliverStep.liters)
            AknAnimatedSize(
              alignment: Alignment.topCenter,
              child: message == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _Shake(
                        trigger: _shakes,
                        child: Semantics(
                          liveRegion: true,
                          child: AknBanner(
                            tone: AknTone.warn,
                            message: message,
                          ),
                        ),
                      ),
                    ),
            ),
        ]),
      ),
    );
    if (!pinKeypad) return list;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: list),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: DriverFadeUp(
            offset: 20,
            duration: AknMotion.stagger,
            curve: AknMotion.emphasizedCurve,
            delay: AknMotion.staggerStep * 2,
            child: LitreKeypad(onKey: model.key, onClear: model.clearLiters),
          ),
        ),
      ],
    );
  }

  /// Sayaç adımı: ekranın tek plakası okumayı canlı gösterir (ADR levhası, "Sayaç okuması", litre;
  /// altında planlanan, fark ve tank). Hata / uyarı plakanın altında (plakada durum rengi olmaz).
  List<Widget> _litersStep(DeliverFlowModel model, {bool withKeypad = true}) {
    final t = context.aknText;
    final c = context.akn;
    final text = model.draft.litersText;
    final showError =
        _showErrors.contains(DeliverStep.liters) || text.isNotEmpty;
    final error = showError ? model.litersError : null;
    final warning = model.tankWarning;
    final liters = model.liters;
    final diff = liters == null ? null : liters - model.plannedLiters;
    final tank = model.detail.tankCapacityLiters;
    final shown = LitersKeypad.display(text);
    return [
      DriverStopPlate(
        product: model.detail.row.productName,
        title: DriverCopy.plateReading,
        figure: shown,
        liveRegion: true,
        semanticLabel: [
          DriverCopy.stepLiters,
          text.isEmpty ? 'girilmedi' : '$shown litre',
          '${DriverCopy.readoutPlanned} ${Fmt.liters(model.plannedLiters)}',
          if (diff != null && diff.abs() >= 0.001)
            '${DriverCopy.readoutDiff} ${Fmt.liters(diff.abs())} '
                '${diff < 0 ? 'eksik' : 'fazla'}',
          ?error,
          ?warning,
        ].join(', '),
        readouts: [
          StopReadout(
            label: DriverCopy.readoutPlanned,
            value: Fmt.number(model.plannedLiters, maxFraction: 3),
            unit: 'L',
          ),
          StopReadout(
            label: DriverCopy.readoutDiff,
            value: diff == null
                ? Fmt.dash
                : diff.abs() < 0.001
                ? '0'
                : '${diff < 0 ? '−' : '+'}${Fmt.number(diff.abs(), maxFraction: 3)}',
            unit: diff == null ? null : 'L',
          ),
          if (tank != null)
            StopReadout(
              label: DriverCopy.readoutTank,
              value: Fmt.number(tank),
              unit: 'L',
            ),
        ],
      ),
      const SizedBox(height: 12),
      // İpucu / uyarı / hata satırı yumuşakça yer değiştirir; reddedilen "İleri"de sarsılır.
      _Shake(
        trigger: _shakes,
        child: AnimatedSwitcher(
          duration: AknMotion.of(context, AknMotion.base),
          layoutBuilder: (current, previous) => Stack(
            alignment: AlignmentDirectional.topStart,
            children: [...previous, ?current],
          ),
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SizeTransition(
              sizeFactor: a,
              axisAlignment: -1,
              child: child,
            ),
          ),
          child: error != null || warning != null
              ? _NoteLine(
                  key: ValueKey(error ?? warning),
                  text: error ?? warning!,
                  tone: error != null ? AknTone.danger : AknTone.warn,
                )
              : withKeypad || MediaQuery.sizeOf(context).height >= 720
              ? Text(
                  DriverCopy.litersHint,
                  key: const ValueKey('hint'),
                  style: t.bodySmall.copyWith(color: c.dim),
                )
              : const SizedBox(key: ValueKey('none'), width: double.infinity),
        ),
      ),
      if (withKeypad) ...[
        const SizedBox(height: 12),
        LitreKeypad(onKey: model.key, onClear: model.clearLiters),
      ],
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
        prefixIcon: PhosphorIconsRegular.receipt,
        textCapitalization: TextCapitalization.characters,
        // Klavye ipucu yetmez (yapıştırma, donanım klavyesi): alan büyük harf yazar (QA LF-2).
        inputFormatters: const [_UpperDocFormatter()],
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
        prefixIcon: PhosphorIconsRegular.user,
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
            icon: PhosphorIconsRegular.userPlus,
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
      Text(DriverCopy.photosHint, style: t.bodySmall.copyWith(color: c.dim)),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: AknLamp(
                label: required
                    ? DriverCopy.photosRequired
                    : DriverCopy.photosOptional,
                tone: required && model.photoCount == 0
                    ? AknTone.warn
                    : model.photoCount > 0
                    ? AknTone.ok
                    : AknTone.neutral,
              ),
            ),
          ),
          if (model.photoCount > 0) ...[
            const SizedBox(width: 12),
            AnimatedSwitcher(
              duration: AknMotion.of(context, AknMotion.iconSwap),
              switchInCurve: AknMotion.pop,
              transitionBuilder: (child, a) => ScaleTransition(
                scale: a,
                child: FadeTransition(opacity: a, child: child),
              ),
              child: Text(
                DriverCopy.photoCount(model.photoCount),
                key: ValueKey(model.photoCount),
                style: t.label.copyWith(
                  color: c.ink,
                  fontWeight: FontWeight.w700,
                  fontFeatures: AknNumerals.tabular,
                ),
              ),
            ),
          ],
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
          icon: PhosphorIconsRegular.cameraSlash,
          title: DriverCopy.cameraDenied,
          message: DriverCopy.cameraDeniedBody,
          actionLabel: DriverCopy.locationOpenSettings,
          onAction: () => unawaited(
            ref.read(driverLocationServiceProvider).openAppSettings(),
          ),
        ),
      ],
      const SizedBox(height: 16),
      // Sahip 2026-10-30: kocaman tam genişlik düğmeler yerine doğal genişlikte, 48 dp iki düğme
      // yan yana (sığmazsa alt alta). Bölgenin tek birincili alttaki "İleri"; "Ekle" kutusu da çeker.
      Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          AknButton.secondary(
            label: DriverCopy.photoTake,
            icon: PhosphorIconsRegular.camera,
            onPressed: model.photoCount < 20
                ? () => unawaited(_takePhoto())
                : null,
          ),
          AknButton.ghost(
            label: DriverCopy.photoPick,
            icon: PhosphorIconsRegular.images,
            onPressed: model.photoCount < 20
                ? () => unawaited(_pickPhotos())
                : null,
          ),
        ],
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
        const SizedBox(height: 8),
        // Uyarı tonunda yumuşak kuyu: imza yerine kaydedilen neden.
        Container(
          padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
          decoration: BoxDecoration(
            color: c.warn.bg,
            borderRadius: AknRadius.card,
            border: Border.all(color: c.warn.line),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FadeUp(
                offset: 0,
                scale: 0.6,
                curve: AknMotion.pop,
                child: SizedBox.square(
                  dimension: 40,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.isDark ? c.surfaceRaised : c.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      PhosphorIconsRegular.pencilSimpleSlash,
                      color: c.warn.fg,
                      size: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DriverCopy.signatureWaived,
                      style: t.bodyStrong.copyWith(
                        color: c.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(waiver.text, style: t.body.copyWith(color: c.ink)),
                    const SizedBox(height: 6),
                    Text(
                      DriverCopy.waiverSubtitle,
                      style: t.bodySmall.copyWith(color: c.dim),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            AknButton.secondary(
              label: DriverCopy.waiverBackToSignature,
              icon: PhosphorIconsRegular.signature,
              onPressed: model.clearWaiver,
            ),
            AknButton.ghost(
              label: DriverCopy.waiverChange,
              onPressed: () => unawaited(_chooseWaiver()),
            ),
          ],
        ),
      ];
    }
    final hint = model.signatureRequired
        ? DriverCopy.signatureHint
        : '${DriverCopy.signatureHint} ${DriverCopy.signatureOptional}';
    const paper = AknColors.light;
    return [
      Text(hint, style: t.bodySmall.copyWith(color: c.dim)),
      const SizedBox(height: 12),
      if (path != null || hasRemoteSignature) ...[
        Semantics(
          image: true,
          label: DriverCopy.signatureTaken,
          child: Container(
            height: 200,
            decoration: BoxDecoration(
              color: paper.surface,
              borderRadius: AknRadius.card,
              border: Border.all(color: c.line, width: 1.5),
              boxShadow: AknShadows.card(c),
            ),
            clipBehavior: Clip.antiAlias,
            child: path != null
                ? Image.file(
                    File(path),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  )
                : Center(
                    child: Icon(
                      PhosphorIconsRegular.sealCheck,
                      color: paper.ok.fg,
                      size: 40,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: AknLamp(
                  label: DriverCopy.signatureTaken,
                  tone: AknTone.ok,
                  solid: true,
                ),
              ),
            ),
            AknButton.ghost(
              label: DriverCopy.signatureRedo,
              icon: PhosphorIconsRegular.arrowClockwise,
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
          ink: paper.ink,
          background: paper.surface,
          borderColor: c.lineStrong,
        ),
      const SizedBox(height: 12),
      Center(
        child: AknButton.ghost(
          label: DriverCopy.signatureCantGet,
          icon: PhosphorIconsRegular.pencilSimpleSlash,
          onPressed: () => unawaited(_chooseWaiver()),
        ),
      ),
      if (_showErrors.contains(DeliverStep.signature) &&
          model.signatureError != null &&
          _pad.isEmpty) ...[
        const SizedBox(height: 4),
        _Shake(
          trigger: _shakes,
          child: Text(
            model.signatureError!,
            style: t.bodySmall.copyWith(
              color: c.danger.fg,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ];
  }

  List<Widget> _summaryStep(DeliverFlowModel model) {
    final d = model.draft;
    final liters = model.liters;
    final diff = liters == null ? null : liters - model.plannedLiters;
    final missing = model.firstInvalidStep;
    return [
      const SizedBox(height: 4),
      // Özet kartı: her satırda simge kuyusu, etiket / değer ve "Düzenle"; içeriden ince çizgiler.
      AknCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          children: [
            _SummaryRow(
              icon: PhosphorIconsRegular.gasPump,
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
              icon: PhosphorIconsRegular.receipt,
              label: DriverCopy.documentNo,
              value: d.documentNo.trim().isEmpty
                  ? Fmt.dash
                  : d.documentNo.trim(),
              invalid: model.documentError != null,
              onEdit: () => _goTo(DeliverStep.document),
            ),
            _SummaryRow(
              icon: PhosphorIconsRegular.user,
              label: DriverCopy.recipient,
              value: d.recipientName.trim().isEmpty
                  ? Fmt.dash
                  : d.recipientName.trim(),
              onEdit: () => _goTo(DeliverStep.recipient),
            ),
            _SummaryRow(
              icon: PhosphorIconsRegular.camera,
              label: DriverCopy.stepPhotos,
              value: DriverCopy.summaryPhotos(model.photoCount),
              invalid: model.photosError != null,
              onEdit: () => _goTo(DeliverStep.photos),
            ),
            _SummaryRow(
              icon: PhosphorIconsRegular.signature,
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
        _NoteLine(
          text:
              '${DriverCopy.summaryNotReady} (${DriverCopy.stepShort[missing.index]})',
          tone: AknTone.danger,
        ),
      ],
      if (_largeText) ...[
        // Konum eksikse yukarıdaki konum kuyusu söyler.
        const SizedBox(height: 16),
        AknButton.secondary(
          label: DriverCopy.back,
          icon: PhosphorIconsRegular.arrowLeft,
          expand: true,
          onPressed: _back,
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
              if (reason != null && !_largeText)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    reason,
                    style: context.aknText.bodySmall.copyWith(
                      color: context.akn.ink,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              SlideToConfirm(
                key: _slideKey,
                label: DriverCopy.slideDeliver,
                doneLabel: DriverCopy.slideStartDone,
                enabled: ready,
                semanticHint: 'Teslim etmek için iki kez dokunun',
                confirmLabel: DriverCopy.confirmDeliver,
                onConfirmed: _submit,
              ),
              if (!_largeText) ...[
                const SizedBox(height: 4),
                Center(
                  child: AknButton.ghost(
                    label: DriverCopy.back,
                    icon: PhosphorIconsRegular.arrowLeft,
                    onPressed: _back,
                  ),
                ),
              ],
            ],
          );
        },
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_stepButtons(model, step)],
    );
  }

  /// İlk adımda solda "Planlananı yaz", sonrakilerde "Geri": doğal genişlikte, çerçeveli; sağda
  /// kalan yeri dolduran birincil "İleri". Hepsi uygulamanın standart 48 dp düğmesi (sahip
  /// 2026-10-30: 64 px yarım ekran düğmeler gereksiz büyüktü). Yazı büyüyüp sol düğme yarım
  /// genişliğe sığmazsa alt alta dizilir (İleri üstte, ikisi de tam genişlik).
  Widget _stepButtons(DeliverFlowModel model, DeliverStep step) {
    final back = step.previous != null;
    Widget left({required bool expand}) => back
        ? AknButton.secondary(
            label: DriverCopy.back,
            icon: PhosphorIconsRegular.arrowLeft,
            expand: expand,
            onPressed: _back,
          )
        : AknButton.secondary(
            label: DriverCopy.fillPlanned,
            expand: expand,
            onPressed: model.fillPlanned,
          );
    final right = AknButton(
      label: DriverCopy.next,
      expand: true,
      onPressed: () => unawaited(_next()),
    );
    return LayoutBuilder(
      builder: (context, box) {
        final half = (box.maxWidth - 10) / 2;
        final side = AknButton.fitsOneLine(
          context,
          back ? DriverCopy.back : DriverCopy.fillPlanned,
          half,
          icon: back,
          bordered: true,
          size: AknButtonSize.large,
        );
        if (!side) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [right, const SizedBox(height: 8), left(expand: true)],
          );
        }
        return Row(
          children: [
            left(expand: false),
            const SizedBox(width: 10),
            Expanded(child: right),
          ],
        );
      },
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
        Center(
          child: FadeUp(
            offset: 6,
            scale: 0.7,
            duration: AknMotion.slow,
            curve: AknMotion.emphasizedCurve,
            child: SizedBox.square(
              dimension: 72,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.brandSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  PhosphorIconsRegular.floppyDisk,
                  size: 34,
                  color: c.brandInk,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            DriverCopy.leaveTitle,
            style: t.title.copyWith(fontWeight: FontWeight.w800),
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
          icon: PhosphorIconsRegular.floppyDisk,
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

/// Özet satırı (tasarım v3): solda simge kuyusu (eksikse kırmızı), etiket (15/20 soluk) üstte,
/// değer (17/24 600) altında; sağda yazılı "Düzenle" (şoförde simge-yalnız düğme yok). Eksikse
/// kırmızı simge + değer. Satırlar arasında içeriden ince çizgi.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onEdit,
    this.detail,
    this.invalid = false,
    this.last = false,
  });

  final IconData icon;
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
    final edit = AknButton.ghost(
      label: DriverCopy.summaryEdit,
      size: AknButtonSize.small,
      semanticLabel: '$label: ${TurkishText.lower(DriverCopy.summaryEdit)}',
      onPressed: onEdit,
    );
    // Büyük yazıda "Düzenle" değerin altına iner (değer sığsın).
    final stacked = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final content = Semantics(
      label: '$label: $value${detail == null ? '' : ', $detail'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AknIconBox(
              icon: invalid ? PhosphorIconsRegular.warningCircle : icon,
              tone: invalid ? AknTone.danger : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: t.bodySmall.copyWith(color: c.dim)),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: t.bodyStrong.copyWith(
                      color: invalid ? c.danger.fg : c.ink,
                      fontWeight: FontWeight.w700,
                      fontFeatures: AknNumerals.tabular,
                    ),
                  ),
                  if (detail != null)
                    Text(detail!, style: t.bodySmall.copyWith(color: c.ink)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.lineSoft)),
      ),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                content,
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: 46,
                    bottom: 8,
                  ),
                  child: edit,
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: content),
                const SizedBox(width: 8),
                edit,
              ],
            ),
    );
  }
}

/// Plakanın altındaki uyarı / hata satırı: ton simgesi + ton yazısı (beyaz zeminde durum rengi).
class _NoteLine extends StatelessWidget {
  const _NoteLine({super.key, required this.text, required this.tone});

  final String text;
  final AknTone tone;

  @override
  Widget build(BuildContext context) {
    final tc = context.akn.tone(tone);
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(AknStatus.toneIcon(tone), size: 18, color: tc.fg),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: context.aknText.bodySmall.copyWith(
                color: tc.fg,
                fontWeight: FontWeight.w500,
              ),
            ),
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
        OpPhase.queued => DriverCopy.queuedDeliverTitle,
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
          const AknLedgerDivider(indent: 0),
          FactRow(
            label: DriverCopy.documentNo,
            value: body.str('deliveryDocumentNo', Fmt.dash),
          ),
          if (photos.isNotEmpty) const AknLedgerDivider(indent: 0),
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
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: _SendingMark()),
            const SizedBox(height: 20),
            Semantics(
              liveRegion: true,
              child: Text(
                DriverCopy.sendingTitle,
                style: context.aknText.title.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
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
        icon: PhosphorIconsRegular.clock,
        title: DriverCopy.queuedDeliverTitle,
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
        icon: PhosphorIconsRegular.warningCircle,
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

/// İrsaliye no alanı büyük harf yazar (bayi "Teslim bildir" ile aynı; QA LF-2).
class _UpperDocFormatter extends TextInputFormatter {
  const _UpperDocFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.asciiUpper);
}

/// Gönderilirken işaret: turuncu dönen » ve çevresinde dışa doğru yayılan yumuşak halkalar (ortam
/// hareketi; testlerde ve hareket azaltılınca durgun).
class _SendingMark extends StatelessWidget {
  const _SendingMark();

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final disc = SizedBox.square(
      dimension: 84,
      child: DecoratedBox(
        decoration: BoxDecoration(color: c.brandSoft, shape: BoxShape.circle),
        child: const Center(child: ChevronSpinner(size: 40)),
      ),
    );
    return SizedBox.square(
      dimension: 120,
      child: AknAmbient(
        period: const Duration(milliseconds: 1600),
        curve: Curves.easeOutCubic,
        child: disc,
        builder: (context, v, child) => Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 84 + 36 * v,
              height: 84 + 36 * v,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: c.brand.withValues(alpha: 0.35 * (1 - v)),
                  width: 2,
                ),
              ),
            ),
            child!,
          ],
        ),
      ),
    );
  }
}

/// Reddedilen "İleri"de uyarıyı kısa bir sarsıntıyla gösterir (v3 §5: üç hızlı ±6 px, sonlu).
/// [trigger] değişince oynar; hareket azaltılınca durgun.
class _Shake extends StatefulWidget {
  const _Shake({required this.trigger, required this.child});

  final int trigger;
  final Widget child;

  @override
  State<_Shake> createState() => _ShakeState();
}

class _ShakeState extends State<_Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void didUpdateWidget(_Shake old) {
    super.didUpdateWidget(old);
    if (widget.trigger > old.trigger && !AknMotion.reduced(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) {
      final v = _c.value;
      // Üç sarsıntı, sönerek; ağaç hep aynı kalır (çocuk yeniden kurulmaz).
      final dx = v <= 0 || v >= 1
          ? 0.0
          : math.sin(v * math.pi * 6) * 6 * (1 - v);
      return Transform.translate(offset: Offset(dx, 0), child: child);
    },
  );
}

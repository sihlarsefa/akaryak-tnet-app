import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/media/image_capture.dart';
import '../../../../core/models/models.dart';
import '../../../../core/push/push_providers.dart';
import '../../../../core/push/push_service.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/storage/prefs_store.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../application/home_controller.dart';
import '../../application/order_submitter.dart';
import '../../application/ordering_config.dart';
import '../../application/wizard_controller.dart';
import '../../copy.dart';
import '../../data/payment_models.dart';
import '../../data/place_models.dart';
import '../widgets/common.dart';
import '../widgets/contact_actions.dart';
import '../widgets/order_parts.dart';
import '../widgets/payment_document_flow.dart';

/// Gönderim ekranı (spec C.4a): gönderiliyor → (gerekirse) "Siparişiniz kontrol ediliyor" →
/// başarı / şirket içi talep / kısmi sonuç / doğrulanamadı / yeni anahtar sorusu / ret.
class SubmissionView extends ConsumerStatefulWidget {
  const SubmissionView({
    super.key,
    required this.onEditRemaining,
    required this.onSendRemaining,
    required this.onBackToEditing,
    required this.onClose,
    required this.onOpen,
  });

  final Future<void> Function() onEditRemaining;
  final Future<void> Function() onSendRemaining;
  final Future<void> Function() onBackToEditing;
  final VoidCallback onClose;

  /// Sonuç ekranından çıkıp sayfa açar ("Siparişi görüntüle", "Siparişlere git"): gönderim
  /// onaylanır, sihirbaz kapanır; çıkış sayfası gösterilmez.
  final void Function(String route) onOpen;

  @override
  ConsumerState<SubmissionView> createState() => _SubmissionViewState();
}

class _SubmissionViewState extends ConsumerState<SubmissionView> {
  bool _primerShown = false;
  String? _announced;

  void _announce(String text) {
    if (_announced == text) return;
    _announced = text;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SemanticsService.sendAnnouncement(
        View.of(context),
        text,
        TextDirection.ltr,
      );
    });
  }

  /// Yedek öneri: izin normalde uygulamanın ilk açılışında sorulur (`PushCoordinator`); izin hâlâ
  /// belirlenmemişse (ör. açılış isteği yapılamadı) ilk siparişten sonra bir kez sorulur.
  Future<void> _maybePushPrimer() async {
    if (_primerShown) return;
    _primerShown = true;
    if (!ref.read(firebaseAvailableProvider)) return;
    final prefs = ref.read(prefsStoreProvider);
    if (prefs.getBool(PrefKeys.pushPrimerShown)) return;
    final push = ref.read(pushServiceProvider);
    if (await push.permission() != PushPermission.notDetermined) return;
    await prefs.setBool(PrefKeys.pushPrimerShown, true);
    if (!mounted) return;
    final ok = await showConfirmSheet(
      context,
      title: OrdersCopy.pushPrimerTitle,
      message: OrdersCopy.pushPrimerMessage,
      confirmLabel: 'Bildirimlere izin ver',
      cancelLabel: 'Şimdi değil',
      icon: PhosphorIconsRegular.bellRinging,
    );
    if (ok) unawaited(push.requestPermission());
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(orderSubmitProvider);
    final ctrl = ref.read(orderSubmitProvider.notifier);
    switch (s.phase) {
      case SubmitPhase.idle:
        return const SizedBox.shrink();
      case SubmitPhase.sending:
      case SubmitPhase.checking:
      case SubmitPhase.reconciling:
        final title = switch (s.phase) {
          SubmitPhase.sending => OrdersCopy.sending,
          SubmitPhase.reconciling => OrdersCopy.reconciling,
          _ => OrdersCopy.checking,
        };
        _announce(title);
        return _Busy(
          title: title,
          message: s.phase == SubmitPhase.checking
              ? OrdersCopy.checkingMessage
              : (s.phase == SubmitPhase.reconciling
                    ? OrdersCopy.reconcilingMessage
                    : null),
          attempt: s.phase == SubmitPhase.checking ? s.attempts : null,
        );
      case SubmitPhase.uncertain:
        _announce(OrdersCopy.uncertainTitle);
        return _Scroll(
          child: ResultView(
            tone: AknTone.warn,
            icon: PhosphorIconsRegular.clock,
            title: OrdersCopy.uncertainTitle,
            message: OrdersCopy.uncertainMessage,
            primaryLabel: OrdersCopy.retry,
            onPrimary: () => unawaited(ctrl.retrySameKey()),
            secondaryLabel: OrdersCopy.checkOrders,
            onSecondary: () => unawaited(ctrl.checkOrders()),
          ),
        );
      case SubmitPhase.askNewKey:
        _announce(OrdersCopy.askNewKeyTitle);
        return _Scroll(
          child: ResultView(
            tone: AknTone.info,
            icon: PhosphorIconsRegular.listMagnifyingGlass,
            title: OrdersCopy.askNewKeyTitle,
            message: OrdersCopy.askNewKeyMessage,
            primaryLabel: OrdersCopy.resend,
            onPrimary: () => unawaited(ctrl.confirmNewKey()),
            secondaryLabel: OrdersCopy.edit,
            onSecondary: () => unawaited(widget.onBackToEditing()),
          ),
        );
      case SubmitPhase.failed:
        final f = s.failure;
        final title = f == null
            ? 'Sipariş gönderilemedi'
            : OrdersCopy.failureTitle(f);
        _announce(title);
        final code = f == null ? null : OrdersCopy.supportCode(f);
        return _Scroll(
          child: Column(
            children: [
              ResultView(
                tone: AknTone.danger,
                icon: PhosphorIconsRegular.warningCircle,
                title: title,
                message: f == null ? null : OrdersCopy.failureMessage(f),
                primaryLabel: OrdersCopy.edit,
                onPrimary: () => unawaited(widget.onBackToEditing()),
                secondaryLabel: 'Kapat',
                onSecondary: widget.onClose,
              ),
              if (code != null) SupportCode(code: code),
            ],
          ),
        );
      case SubmitPhase.partial:
        _announce(OrdersCopy.partialTitle);
        return _Partial(
          state: s,
          onSendRemaining: widget.onSendRemaining,
          onEditRemaining: () async {
            await widget.onEditRemaining();
            await ctrl.backToEditing();
          },
          onOpen: widget.onOpen,
        );
      case SubmitPhase.success:
        final r = s.result;
        _announce(
          r?.isCompanyRequest ?? false
              ? OrdersCopy.companyRequestTitle
              : OrdersCopy.successTitle,
        );
        if (s.firstOrder && !(r?.isCompanyRequest ?? false)) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => unawaited(_maybePushPrimer()),
          );
        }
        return _Success(
          state: s,
          onClose: widget.onClose,
          onOpen: widget.onOpen,
        );
    }
  }
}

class _Scroll extends StatelessWidget {
  const _Scroll({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ListView(children: [ContentWidth(child: child)]);
}

class _Busy extends StatelessWidget {
  const _Busy({required this.title, this.message, this.attempt});

  final String title;
  final String? message;
  final int? attempt;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Semantics(
          liveRegion: true,
          label: title,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ChevronSpinner(size: 48),
              const SizedBox(height: 20),
              // Başlık değişince (gönderiliyor → kontrol ediliyor) yenisi söner / belirir.
              AnimatedSwitcher(
                duration: AknMotion.of(context, AknMotion.base),
                switchInCurve: AknMotion.emphasizedCurve,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, 0.25),
                      end: Offset.zero,
                    ).animate(a),
                    child: child,
                  ),
                ),
                child: Text(
                  title,
                  key: ValueKey(title),
                  style: t.title.copyWith(color: c.ink),
                  textAlign: TextAlign.center,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  style: t.body.copyWith(color: c.dim),
                  textAlign: TextAlign.center,
                ),
              ],
              if (attempt != null && attempt! > 1) ...[
                const SizedBox(height: 8),
                Text(
                  '$attempt. deneme; aynı işlem güvenle tekrarlanıyor',
                  style: t.caption.copyWith(color: c.dim),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Oluşan siparişlerin listesi.
class _CreatedList extends StatelessWidget {
  const _CreatedList({required this.orders});

  final List<CreateOrderResult> orders;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    if (orders.isEmpty) {
      return Text(
        'Sipariş oluşturulmadı.',
        style: t.bodySmall.copyWith(color: c.dim),
      );
    }
    return AknCard(
      padding: EdgeInsets.zero,
      child: AknLedger(
        children: [
          for (final (i, o) in orders.indexed)
            StaggerItem(
              index: i,
              child: AknListTile(
                dense: true,
                leading: AknIconBox(
                  icon: o.financeStatus == OrderFinanceStatus.pending
                      ? PhosphorIconsRegular.bank
                      : PhosphorIconsRegular.receipt,
                  tone: AknTone.ok,
                  size: 36,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                showChevron: true,
                title: o.orderNumber,
                subtitle: [
                  if (o.financeStatus == OrderFinanceStatus.pending)
                    'Finans onayında',
                  if (o.estimatedAmount != null)
                    'Tahmini ${Fmt.money(o.estimatedAmount)}',
                ].join(', '),
                onTap: () => context.push(AppRoutes.order(o.orderId)),
              ),
            ),
        ],
      ),
    );
  }
}

class _Success extends ConsumerWidget {
  const _Success({
    required this.state,
    required this.onClose,
    required this.onOpen,
  });

  final SubmitState state;
  final VoidCallback onClose;
  final void Function(String route) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = state.result ?? const PlaceOrderResult();
    final config = ref.watch(orderingConfigValueProvider);
    final home = ref.watch(customerHomeProvider).data;
    final receiptPath = ref.watch(
      orderWizardProvider.select((w) => w.draft.payment.receiptPath),
    );
    final submitter = ref.read(orderSubmitProvider.notifier);
    final orders = state.created.isNotEmpty ? state.created : r.orders;
    final expiryOn = config.expiryEnabled(
      home?.dashboard.expiryEnabled ?? true,
    );
    final expires = orders.isEmpty ? null : orders.first.expiresAt;
    final doc = r.paymentDocument;
    final group =
        r.paymentGroupKey ??
        (orders.isEmpty ? null : orders.first.paymentGroupKey);
    final docDone =
        state.documentUploadedGroup != null &&
        (state.documentUploadedGroup == (group ?? '-'));
    final instrument =
        doc != null &&
        (doc.kind == AttachmentKind.chequeImage ||
            doc.kind == AttachmentKind.promissoryNoteImage);

    void finish(String route) => onOpen(route);

    return ListView(
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ResultView(
                tone: AknTone.ok,
                title: r.isCompanyRequest
                    ? OrdersCopy.companyRequestTitle
                    : OrdersCopy.successTitle,
                message: r.isCompanyRequest
                    ? (r.companyRequest?.message ?? r.message)
                    : (r.message.isEmpty ? null : r.message),
                details: orders.isEmpty ? null : _CreatedList(orders: orders),
              ),
              if (state.reconciled)
                const AknBanner(
                  tone: AknTone.info,
                  icon: PhosphorIconsRegular.listMagnifyingGlass,
                  message: OrdersCopy.reconciledNote,
                  margin: EdgeInsets.fromLTRB(20, 0, 20, 12),
                ),
              if (expiryOn && expires != null && !r.isCompanyRequest)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: FadeUp(
                    delay: AknMotion.staggerDelay(3),
                    child: AknCard(
                      padding: const EdgeInsets.all(14),
                      child: FactLine(
                        icon: PhosphorIconsRegular.timer,
                        tone: AknTone.brand,
                        text:
                            'Teklif ${withDative(Fmt.time(config.deviceDeadline(expires)))} '
                            'kadar geçerli; gün sonunda kapanır.',
                      ),
                    ),
                  ),
                ),
              if (doc != null && !doc.isUploadable && doc.message != null)
                AknBanner(
                  tone: AknTone.info,
                  icon: PhosphorIconsRegular.camera,
                  message: doc.message!,
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                ),
              if (doc != null && doc.isUploadable && !docDone)
                _DocumentCard(
                  target: doc,
                  receiptPath: receiptPath,
                  orderNumber: orders.isEmpty ? null : orders.first.orderNumber,
                  onDone: () =>
                      unawaited(submitter.markDocumentUploaded(group)),
                ),
              if (doc != null && docDone)
                AknBanner(
                  tone: AknTone.ok,
                  icon: PhosphorIconsFill.checkCircle,
                  message: instrument
                      ? '${doc.label} yüklendi. ${OrdersCopy.instrumentHint}.'
                      : '${doc.label} yüklendi.',
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                ),
              if (instrument && home?.station != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: StationContactButtons(
                    station: home!.station,
                    dense: true,
                    message: orders.isEmpty
                        ? null
                        : '${orders.first.orderNumber} siparişimin çek/senet bilgileri hakkında yazıyorum.',
                  ),
                ),
              if (state.templateSaved == true)
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: AknCard(
                    padding: EdgeInsets.all(14),
                    child: FactLine(
                      icon: PhosphorIconsFill.checkCircle,
                      tone: AknTone.ok,
                      text: 'Şablon kaydedildi',
                    ),
                  ),
                ),
              if (state.templateSaved == false)
                const AknBanner(
                  tone: AknTone.warn,
                  icon: PhosphorIconsRegular.bookmarkSimple,
                  message:
                      'Şablon kaydedilemedi; sipariş ayrıntısından “Şablon yap” ile yeniden deneyebilirsiniz.',
                  margin: EdgeInsets.fromLTRB(20, 0, 20, 12),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (r.isCompanyRequest && r.companyRequest != null)
                      AknButton(
                        label: 'Talebi görüntüle',
                        expand: true,
                        onPressed: () => finish(
                          AppRoutes.companyRequest(r.companyRequest!.id),
                        ),
                      )
                    else if (orders.length == 1)
                      AknButton(
                        label: OrdersCopy.viewOrder,
                        expand: true,
                        onPressed: () =>
                            finish(AppRoutes.order(orders.first.orderId)),
                      )
                    else
                      AknButton(
                        label: OrdersCopy.viewOrders,
                        expand: true,
                        onPressed: () => finish(AppRoutes.orders),
                      ),
                    const SizedBox(height: 8),
                    AknButton.ghost(
                      label: OrdersCopy.backHome,
                      expand: true,
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Sonuç ekranındaki ödeme belgesi kartı. Sihirbazın ödeme adımında seçilen dekont ("sipariş oluşunca
/// yüklenecek") bir kez okunur, önceden seçili gelir ve kendiliğinden yüklenir (tek Idempotency-Key);
/// ilerleme ve sonuç kartta görünür, hata olursa "Tekrar yükle". Dosya bulunamazsa seçim düğmeleri.
class _DocumentCard extends StatefulWidget {
  const _DocumentCard({
    required this.target,
    required this.receiptPath,
    required this.onDone,
    this.orderNumber,
  });

  final PaymentUploadTarget target;
  final String? receiptPath;
  final String? orderNumber;
  final VoidCallback onDone;

  @override
  State<_DocumentCard> createState() => _DocumentCardState();
}

class _DocumentCardState extends State<_DocumentCard> {
  /// Sihirbazda seçilen dekont (yalnızca havale dekontu hedefinde; bir kez okunur).
  late final Future<CapturedImage?>? _receipt =
      widget.target.kind == AttachmentKind.transferReceipt &&
          widget.receiptPath != null
      ? readLocalImage(widget.receiptPath)
      : null;

  @override
  Widget build(BuildContext context) {
    final receipt = _receipt;
    if (receipt == null) return _card(null);
    return FutureBuilder<CapturedImage?>(
      future: receipt,
      builder: (context, snap) => snap.connectionState == ConnectionState.done
          ? _card(snap.data)
          : const SizedBox.shrink(),
    );
  }

  Widget _card(CapturedImage? image) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
    child: AknCard(
      padding: const EdgeInsets.all(18),
      child: PaymentDocumentPanel(
        target: widget.target,
        embedded: true,
        orderNumber: widget.orderNumber,
        preselected: image,
        autoUpload: image != null,
        onDone: widget.onDone,
      ),
    ),
  );
}

class _Partial extends ConsumerWidget {
  const _Partial({
    required this.state,
    required this.onSendRemaining,
    required this.onEditRemaining,
    required this.onOpen,
  });

  final SubmitState state;
  final Future<void> Function() onSendRemaining;
  final Future<void> Function() onEditRemaining;
  final void Function(String route) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = state.result ?? const PlaceOrderResult();
    final submitter = ref.read(orderSubmitProvider.notifier);
    final receiptPath = ref.watch(
      orderWizardProvider.select((w) => w.draft.payment.receiptPath),
    );
    final doc = r.paymentDocument;
    final group = r.paymentGroupKey;
    final docDone = state.documentUploadedGroup == (group ?? '-');
    return ListView(
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ResultView(
                tone: AknTone.warn,
                icon: PhosphorIconsRegular.arrowsSplit,
                title: OrdersCopy.partialTitle,
                message: [
                  if (r.partialError != null) r.partialError!,
                  '${state.remainingLines} satır gönderilmedi; aynı ödeme grubuyla '
                      'yeniden gönderebilirsiniz.',
                ].join('\n'),
                details: _CreatedList(orders: state.created),
              ),
              if (doc != null && doc.isUploadable && !docDone)
                _DocumentCard(
                  target: doc,
                  receiptPath: receiptPath,
                  orderNumber: state.created.isEmpty
                      ? null
                      : state.created.first.orderNumber,
                  onDone: () =>
                      unawaited(submitter.markDocumentUploaded(group)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AknButton(
                      label: OrdersCopy.sendRemaining,
                      icon: PhosphorIconsRegular.paperPlaneRight,
                      expand: true,
                      onPressedAsync: onSendRemaining,
                      showSuccess: false,
                    ),
                    const SizedBox(height: 8),
                    AknButton.secondary(
                      label: OrdersCopy.editRemaining,
                      expand: true,
                      onPressedAsync: onEditRemaining,
                      showSuccess: false,
                    ),
                    const SizedBox(height: 4),
                    // Kalan satırlar ödeme grubuyla depoda kalır ("Yarım kalan siparişiniz").
                    AknButton.ghost(
                      label: OrdersCopy.viewOrders,
                      expand: true,
                      onPressed: () => onOpen(AppRoutes.orders),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

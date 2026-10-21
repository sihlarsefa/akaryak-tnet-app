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
  });

  final Future<void> Function() onEditRemaining;
  final Future<void> Function() onSendRemaining;
  final Future<void> Function() onBackToEditing;
  final VoidCallback onClose;

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
      icon: Icons.notifications_active_rounded,
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
                    ? 'Siparişlerim listesiyle karşılaştırıyoruz; biraz sürebilir.'
                    : null),
          attempt: s.phase == SubmitPhase.checking ? s.attempts : null,
        );
      case SubmitPhase.uncertain:
        _announce(OrdersCopy.uncertainTitle);
        return _Scroll(
          child: ResultView(
            tone: AknTone.warn,
            icon: Icons.schedule_rounded,
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
            icon: Icons.manage_search_rounded,
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
                icon: Icons.error_outline_rounded,
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
          onClose: widget.onClose,
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
        return _Success(state: s, onClose: widget.onClose);
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
              Text(title, style: t.title, textAlign: TextAlign.center),
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
                  '$attempt. deneme · aynı işlem güvenle tekrarlanıyor',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final o in orders)
          AknListTile(
            dense: true,
            leadingIcon: o.financeStatus == OrderFinanceStatus.pending
                ? Icons.account_balance_rounded
                : Icons.receipt_long_rounded,
            leadingTone: o.financeStatus == OrderFinanceStatus.pending
                ? AknTone.info
                : AknTone.brand,
            title: o.orderNumber,
            subtitle: [
              if (o.financeStatus == OrderFinanceStatus.pending)
                'Finans onayında',
              if (o.estimatedAmount != null)
                'Tahmini ${Fmt.money(o.estimatedAmount)}',
            ].join(' · '),
            onTap: () => context.push(AppRoutes.order(o.orderId)),
          ),
        if (orders.isEmpty)
          Text(
            'Sipariş oluşturulmadı.',
            style: t.bodySmall.copyWith(color: c.dim),
          ),
      ],
    );
  }
}

class _Success extends ConsumerWidget {
  const _Success({required this.state, required this.onClose});

  final SubmitState state;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.aknText;
    final c = context.akn;
    final r = state.result ?? const PlaceOrderResult();
    final config = ref.watch(orderingConfigValueProvider);
    final home = ref.watch(customerHomeProvider).data;
    final wizard = ref.watch(orderWizardProvider);
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

    void finish(String route) {
      final router = GoRouter.of(context);
      submitter.acknowledge();
      if (router.canPop()) router.pop();
      unawaited(router.push(route));
    }

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
                  icon: Icons.manage_search_rounded,
                  message:
                      'Sonuç Siparişlerim listesinden doğrulandı; sipariş tekrar gönderilmedi.',
                  margin: EdgeInsets.fromLTRB(16, 0, 16, 8),
                ),
              if (expiryOn && expires != null && !r.isCompanyRequest)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 18, color: c.dim),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Teklif ${withDative(Fmt.time(config.deviceDeadline(expires)))} '
                          'kadar geçerli; gün sonunda kapanır.',
                          style: t.bodySmall.copyWith(color: c.text),
                        ),
                      ),
                    ],
                  ),
                ),
              if (doc != null && !doc.isUploadable && doc.message != null)
                AknBanner(
                  tone: AknTone.info,
                  icon: Icons.photo_camera_outlined,
                  message: doc.message!,
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                ),
              if (doc != null && doc.isUploadable && !docDone)
                FutureBuilder<CapturedImageOrNull>(
                  future: _receipt(wizard.draft.payment.receiptPath, doc),
                  builder: (context, snap) => Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: AknCard(
                      accent: doc.required ? AknTone.warn : null,
                      child: PaymentDocumentPanel(
                        target: doc,
                        embedded: true,
                        orderNumber: orders.isEmpty
                            ? null
                            : orders.first.orderNumber,
                        preselected: snap.data?.image,
                        onDone: () =>
                            unawaited(submitter.markDocumentUploaded(group)),
                      ),
                    ),
                  ),
                ),
              if (doc != null && docDone)
                AknBanner(
                  tone: AknTone.ok,
                  icon: Icons.check_circle_rounded,
                  message: instrument
                      ? '${doc.label} yüklendi. ${OrdersCopy.instrumentHint}.'
                      : '${doc.label} yüklendi.',
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                ),
              if (instrument && home?.station != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Wrap(
                    children: [
                      StatusChip(
                        label: 'Şablon kaydedildi',
                        tone: AknTone.ok,
                        icon: Icons.bookmark_added_rounded,
                      ),
                    ],
                  ),
                ),
              if (state.templateSaved == false)
                const AknBanner(
                  tone: AknTone.warn,
                  icon: Icons.bookmark_border_rounded,
                  message:
                      'Şablon kaydedilemedi; sipariş ayrıntısından “Şablon yap” ile yeniden deneyebilirsiniz.',
                  margin: EdgeInsets.fromLTRB(16, 0, 16, 8),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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

  static Future<CapturedImageOrNull> _receipt(
    String? path,
    PaymentUploadTarget doc,
  ) async {
    if (doc.kind != AttachmentKind.transferReceipt) {
      return const CapturedImageOrNull(null);
    }
    return CapturedImageOrNull(await readLocalImage(path));
  }
}

/// FutureBuilder için sarmalayıcı (null değer = görsel yok).
class CapturedImageOrNull {
  const CapturedImageOrNull(this.image);
  final CapturedImage? image;
}

class _Partial extends ConsumerWidget {
  const _Partial({
    required this.state,
    required this.onSendRemaining,
    required this.onEditRemaining,
    required this.onClose,
  });

  final SubmitState state;
  final Future<void> Function() onSendRemaining;
  final Future<void> Function() onEditRemaining;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = state.result ?? const PlaceOrderResult();
    final submitter = ref.read(orderSubmitProvider.notifier);
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
                icon: Icons.call_split_rounded,
                title: OrdersCopy.partialTitle,
                message: [
                  if (r.partialError != null) r.partialError!,
                  '${state.remainingLines} satır gönderilmedi; aynı ödeme grubuyla '
                      'yeniden gönderebilirsiniz.',
                ].join('\n'),
                details: _CreatedList(orders: state.created),
              ),
              if (doc != null && doc.isUploadable && !docDone)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: AknCard(
                    accent: doc.required ? AknTone.warn : null,
                    child: PaymentDocumentPanel(
                      target: doc,
                      embedded: true,
                      orderNumber: state.created.isEmpty
                          ? null
                          : state.created.first.orderNumber,
                      onDone: () =>
                          unawaited(submitter.markDocumentUploaded(group)),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AknButton(
                      label: OrdersCopy.sendRemaining,
                      icon: Icons.send_rounded,
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
                    AknButton.ghost(
                      label: OrdersCopy.viewOrders,
                      expand: true,
                      onPressed: () {
                        submitter.acknowledge();
                        onClose();
                      },
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

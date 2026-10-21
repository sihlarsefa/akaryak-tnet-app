import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/auth/permissions.dart';
import '../../../../core/auth/session_controller.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/ui/ui.dart';
import '../../application/home_controller.dart';
import '../../application/order_submitter.dart';
import '../../application/wizard_controller.dart';
import '../../application/wizard_models.dart';
import '../../application/wizard_store.dart';
import '../../copy.dart';
import '../widgets/common.dart';
import 'step_delivery.dart';
import 'step_payment.dart';
import 'step_products.dart';
import 'step_summary.dart';
import 'submission_view.dart';

/// "Sipariş ver" sihirbazı (spec A.3 adım 1, A.4 A2 kuralları, C.5 sihirbaz tarifi):
/// Ürünler → Teslimat → Ödeme → Özet → gönder (C.4a). Taslak kullanıcı başına saklanır; uygulama
/// kapanıp açılınca bekleyen gönderim aynı anahtarla sürdürülür.
class OrderWizardPage extends ConsumerStatefulWidget {
  const OrderWizardPage({super.key, this.launch = const WizardLaunch()});

  final WizardLaunch launch;

  @override
  ConsumerState<OrderWizardPage> createState() => _OrderWizardPageState();
}

class _OrderWizardPageState extends ConsumerState<OrderWizardPage> {
  bool _started = false;

  /// Geçiş yönü: adım geri gidince ters (Geri, "Düzenle", hatalı adıma dönüş).
  bool _reverse = false;
  int _lastIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (_started || !mounted) return;
    _started = true;
    final submitter = ref.read(orderSubmitProvider);
    final store = ref.read(wizardDraftStoreProvider);
    final snap = await store?.load();
    if (!mounted) return;
    final hasPending = snap?.pending != null || submitter.isBusy;
    await ref
        .read(orderWizardProvider.notifier)
        .init(widget.launch, hasPending: hasPending);
    if (!mounted) return;
    if (snap?.pending != null && !submitter.isActive) {
      unawaited(ref.read(orderSubmitProvider.notifier).resumeIfPending());
    }
  }

  Future<bool> _confirmExit() async {
    final w = ref.read(orderWizardProvider);
    final phase = ref.read(orderSubmitProvider).phase;
    if (phase != SubmitPhase.idle) return true;
    if (!w.draft.dirty || !w.ready) return true;
    final choice = await showAppSheet<String>(
      context: context,
      showClose: false,
      builder: (ctx) => const _ExitSheet(),
    );
    final ctrl = ref.read(orderWizardProvider.notifier);
    switch (choice) {
      case 'keep':
        await ctrl.saveDraftNow();
        return true;
      case 'discard':
        await ctrl.discardDraft();
        return true;
      default:
        return false;
    }
  }

  /// Sonuç ekranı (başarı, kısmi sonuç, ret): kapanınca gönderim onaylanır.
  static bool _isResult(SubmitPhase p) =>
      p == SubmitPhase.success ||
      p == SubmitPhase.partial ||
      p == SubmitPhase.failed;

  Future<void> _close() async {
    if (_isResult(ref.read(orderSubmitProvider).phase)) {
      _leaveResult();
      return;
    }
    if (!await _confirmExit() || !mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  /// Sonuç ekranından ayrılır: gönderim onaylanır, sihirbaz kapanır ve [route] verildiyse o sayfa
  /// açılır. Çıkış sayfası ("Girdiğiniz bilgiler kaydedilmedi") gösterilmez ve bellekteki taslak
  /// yazılmaz: başarıda taslak silinmiştir, kısmi sonuçta kalan satırlar ödeme grubuyla depodadır
  /// (ana sayfadaki "Yarım kalan siparişiniz" kartından sürdürülür), retten sonra taslak korunur.
  void _leaveResult([String? route]) {
    final router = GoRouter.of(context);
    ref.read(orderSubmitProvider.notifier).acknowledge();
    if (!router.canPop()) {
      router.go(route ?? AppRoutes.home);
      return;
    }
    router.pop();
    if (route == null) return;
    // Sihirbaz hedef sayfanın üstünde açıldıysa (ör. Siparişlerim) aynı sayfa ikinci kez açılmaz.
    final here = router.routerDelegate.currentConfiguration.uri.path;
    if (here != Uri.parse(route).path) unawaited(router.push(route));
  }

  void _next() {
    final ctrl = ref.read(orderWizardProvider.notifier);
    final ok = ctrl.next();
    if (!ok) {
      AknHaptics.warning();
      SemanticsService.sendAnnouncement(
        View.of(context),
        'Lütfen işaretli alanları kontrol edin.',
        TextDirection.ltr,
      );
      return;
    }
  }

  void _back() {
    final ctrl = ref.read(orderWizardProvider.notifier);
    if (!ctrl.back()) unawaited(_close());
  }

  Future<void> _submit() async {
    final ctrl = ref.read(orderWizardProvider.notifier);
    if (!ctrl.allValid) {
      // İlk hatalı adıma git ve hatalarını göster.
      for (final s in ctrl.steps) {
        if (ctrl.issuesFor(s).any((i) => i.blocking)) {
          ctrl.showErrorsAt(s);
          break;
        }
      }
      AknHaptics.warning();
      return;
    }
    final w = ref.read(orderWizardProvider);
    await ctrl.saveDraftNow();
    await ref
        .read(orderSubmitProvider.notifier)
        .submit(w.draft, ctrl.buildRequest());
  }

  @override
  Widget build(BuildContext context) {
    final w = ref.watch(orderWizardProvider);
    final submit = ref.watch(orderSubmitProvider);
    final ctrl = ref.read(orderWizardProvider.notifier);
    final policy = ref.watch(accessPolicyProvider);
    final steps = ctrl.steps;
    final step = w.draft.step;
    final index = steps.indexOf(step).clamp(0, steps.length - 1);
    if (index != _lastIndex) {
      _reverse = index < _lastIndex;
      _lastIndex = index;
    }
    final submitting = submit.isActive;
    final canCreate = policy.can(Pg.customerCreateOrder, Perm.create);

    Widget body;
    Widget? actionBar;
    if (!canCreate) {
      body = const Center(
        child: EmptyState(
          title: OrdersCopy.forbidden,
          message: OrdersCopy.forbiddenMessage,
          illustration: AknIllustration.locked,
        ),
      );
    } else if (submitting) {
      body = SubmissionView(
        onEditRemaining: () async {
          await ref.read(orderWizardProvider.notifier).reloadFromStore();
        },
        onSendRemaining: () async {
          await ref.read(orderWizardProvider.notifier).reloadFromStore();
          final req = ref.read(orderWizardProvider.notifier).buildRequest();
          await ref.read(orderSubmitProvider.notifier).sendRemaining(req);
        },
        onBackToEditing: () async {
          await ref.read(orderSubmitProvider.notifier).backToEditing();
          await ref.read(orderWizardProvider.notifier).reloadFromStore();
        },
        onClose: _close,
        onOpen: _leaveResult,
      );
    } else if (w.loadError != null && !w.ready) {
      body = Center(
        child: SingleChildScrollView(
          child: FailureView(
            failure: w.loadError!,
            onRetry: () {
              _started = false;
              unawaited(_start());
            },
          ),
        ),
      );
    } else if (!w.ready) {
      body = const SkeletonList(itemCount: 3, lines: 3);
    } else {
      final home = ref.watch(customerHomeProvider).data;
      if (home != null && home.stations.isEmpty) {
        body = Center(
          child: SingleChildScrollView(
            child: EmptyState(
              title: 'Bağlı bayiniz yok',
              message:
                  'Sipariş verebilmek için bayinizin sizi cari olarak eklemesi gerekir.',
              illustration: AknIllustration.customers,
              actionLabel: OrdersCopy.backHome,
              onAction: _close,
            ),
          ),
        );
      } else {
        body = Column(
          children: [
            // Adıma dokunarak dönüş yok: çekirdek başlığın dokunma alanı 16 px (C.7); geri dönüş
            // "Geri" ve özetteki "Düzenle" ile yapılır.
            StepperHeader(
              steps: [for (final s in steps) s.label],
              current: index,
            ),
            Expanded(
              child: SharedAxisSwitcher(
                reverse: _reverse,
                child: KeyedSubtree(
                  key: ValueKey(step),
                  child: switch (step) {
                    WizardStep.products => const StepProducts(),
                    WizardStep.delivery => const StepDelivery(),
                    WizardStep.payment => const StepPayment(),
                    WizardStep.summary => const StepSummary(),
                  },
                ),
              ),
            ),
          ],
        );
        final last = step == WizardStep.summary;
        final predicted = ctrl.companyRequestPredicted;
        actionBar = ButtonRow(
          children: [
            AknButton.secondary(
              label: index == 0 ? 'Vazgeç' : 'Geri',
              expand: true,
              onPressed: _back,
            ),
            if (last)
              AknButton(
                label: predicted ? OrdersCopy.sendForApproval : OrdersCopy.send,
                icon: Icons.send_rounded,
                expand: true,
                onPressedAsync: _submit,
                showSuccess: false,
              )
            else
              AknButton(
                label: 'Devam',
                trailingIcon: Icons.arrow_forward_rounded,
                expand: true,
                onPressed: w.checkingOrdering && step == WizardStep.products
                    ? null
                    : _next,
              ),
          ],
        );
      }
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_close());
      },
      child: AppScaffold(
        title: OrdersCopy.newOrder,
        showBell: false,
        leading: AknIconButton(
          icon: Icons.close_rounded,
          semanticLabel: 'Kapat',
          onPressed: _close,
        ),
        actionBar: actionBar,
        body: body,
      ),
    );
  }
}

class _ExitSheet extends StatelessWidget {
  const _ExitSheet();

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 4),
        const Center(
          child: AknIconBox(
            icon: Icons.edit_note_rounded,
            tone: AknTone.brand,
            size: 56,
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            OrdersCopy.exitTitle,
            style: t.headline,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          OrdersCopy.exitMessage,
          style: t.body.copyWith(color: c.dim),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        AknButton(
          label: OrdersCopy.keepDraft,
          expand: true,
          onPressed: () => Navigator.of(context).pop('keep'),
        ),
        const SizedBox(height: 8),
        AknButton.secondary(
          label: OrdersCopy.discard,
          expand: true,
          onPressed: () => Navigator.of(context).pop('discard'),
        ),
        const SizedBox(height: 4),
        AknButton.ghost(
          label: OrdersCopy.stay,
          expand: true,
          onPressed: () => Navigator.of(context).pop('stay'),
        ),
      ],
    );
  }
}

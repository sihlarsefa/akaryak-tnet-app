import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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

  /// Buzlu alt çubuğun ölçülen yüksekliği (adım listeleri sonlarına bu kadar boşluk ekler).
  double? _dockHeight;

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
        'İşaretli alanları kontrol edin.',
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
    Widget? dock;
    if (!canCreate) {
      body = const Center(
        child: EmptyState(
          title: OrdersCopy.forbidden,
          message: OrdersCopy.forbiddenMessage,
          illustration: AknIllustration.locked,
        ),
      );
    } else if (submitting) {
      // Gönderim ekranı yükselerek gelir (v3 §5).
      body = A2Rise(
        index: 0,
        offset: 16,
        scale: 0.97,
        child: SubmissionView(
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
        ),
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
            // Tamamlanan adıma dokunarak dönülür (48 dp hedefler); ayrıca "Geri" ve özetteki
            // "Değiştir".
            StepperHeader(
              steps: [for (final s in steps) s.label],
              current: index,
              onStepTap: (i) {
                if (i < index) {
                  AknHaptics.selection();
                  ctrl.goTo(steps[i]);
                }
              },
            ),
            _ProgressLine(value: (index + 1) / steps.length),
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
        final primary = last
            ? AknButton(
                label: predicted ? OrdersCopy.sendForApproval : OrdersCopy.send,
                expand: true,
                onPressedAsync: _submit,
                showSuccess: false,
              )
            : AknButton(
                label: 'Devam',
                expand: true,
                onPressed: w.checkingOrdering && step == WizardStep.products
                    ? null
                    : _next,
              );
        final back = AknButton.ghost(
          label: index == 0 ? 'Vazgeç' : 'Geri',
          expand: MediaQuery.textScalerOf(context).scale(15) > 19.5,
          onPressed: _back,
        );
        dock = _WizardDock(primary: primary, back: back);
      }
    }

    final d = dock;
    if (d != null) {
      // Adımlar buzlu çubuğun altından kayar; listeler sonlarına çubuğun yüksekliği kadar boşluk
      // ekler (MediaQuery alt boşluğu), böylece son satır da çubuğun üstüne çıkabilir. Klavye
      // açıkken çubuk aşağı kayıp gizlenir (içerik yerini alır).
      final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
      final mq = MediaQuery.of(context);
      final inset = keyboard
          ? 0.0
          : (_dockHeight ?? 88 + mq.viewPadding.bottom);
      body = Stack(
        children: [
          Positioned.fill(
            child: MediaQuery(
              data: mq.copyWith(padding: mq.padding.copyWith(bottom: inset)),
              child: body,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              ignoring: keyboard,
              child: AnimatedSlide(
                offset: keyboard ? const Offset(0, 1) : Offset.zero,
                duration: AknMotion.of(context, AknMotion.base),
                curve: AknMotion.emphasizedCurve,
                child: _SizeReport(
                  onSize: (size) {
                    if (mounted && size.height != _dockHeight) {
                      setState(() => _dockHeight = size.height);
                    }
                  },
                  child: _FrostedDock(child: d),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        unawaited(_close());
      },
      child: AppScaffold(
        title: OrdersCopy.wizardTitle,
        largeTitle: false,
        showBell: false,
        leading: AknIconButton(
          icon: PhosphorIconsRegular.x,
          semanticLabel: 'Kapat',
          onPressed: _close,
        ),
        body: body,
      ),
    );
  }
}

/// Sihirbazın ilerleme çizgisi (tasarım v3 §5): adım şeridinin altında, sayfa genişliğinde 3 px;
/// turuncu dolgu ilk açılışta soldan uzar, adım değişince yay eğrisiyle yeni yerine kayar.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine({required this.value});

  /// 0–1.
  final double value;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    return Semantics(
      excludeSemantics: true,
      child: SizedBox(
        height: 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: c.lineSoft),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value),
              duration: AknMotion.of(context, AknMotion.emphasized),
              curve: AknMotion.curveOf(context, AknMotion.spring),
              builder: (context, v, _) => FractionallySizedBox(
                alignment: AlignmentDirectional.centerStart,
                widthFactor: v.clamp(0.0, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [c.brandFillStart, c.brand],
                    ),
                    borderRadius: const BorderRadius.horizontal(
                      right: Radius.circular(3),
                    ),
                    boxShadow: AknShadows.glow(c.brand),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Buzlu alt çubuk (tasarım v3 §4): içerik altından kayarken %86 opak yüzey ve bulanıklık
/// (sigma 20), üstünde yumuşak çubuk gölgesi, ince çizgi yok; 12/20 dolgu ve güvenli alan.
class _FrostedDock extends StatelessWidget {
  const _FrostedDock({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final surface = c.isDark ? c.surface : c.surfaceRaised;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AknTheme.overlayFor(c.brightness),
      child: DecoratedBox(
        decoration: BoxDecoration(boxShadow: AknShadows.bar(c)),
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: ColoredBox(
              color: surface.withValues(alpha: 0.86),
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Çocuğunun yerleşim sonrası boyutunu bildirir (boyut değiştiğinde, çizimden sonra).
class _SizeReport extends SingleChildRenderObjectWidget {
  const _SizeReport({required this.onSize, required super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReport(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderSizeReport r) =>
      r.onSize = onSize;
}

class _RenderSizeReport extends RenderProxyBox {
  _RenderSizeReport(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    final s = size;
    if (s == _last) return;
    _last = s;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(s));
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
        const Align(
          alignment: AlignmentDirectional.centerStart,
          child: FadeUp(
            offset: 8,
            scale: 0.8,
            curve: AknMotion.pop,
            child: A2IconTile(
              icon: PhosphorIconsRegular.notePencil,
              tone: AknTone.brand,
              size: 52,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Semantics(
          header: true,
          child: Text(
            OrdersCopy.exitTitle,
            style: t.title.copyWith(color: c.ink),
          ),
        ),
        const SizedBox(height: 8),
        Text(OrdersCopy.exitMessage, style: t.body.copyWith(color: c.dim)),
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

/// Sihirbaz çubuğu (§7.9): solda hayalet "Geri" / "Vazgeç", sağda tam genişlikte birincil "Devam" /
/// "Siparişi gönder". Büyük yazıda aynı sırayla alt alta: "Geri" üstte, birincil başparmağa yakın
/// altta.
class _WizardDock extends StatelessWidget {
  const _WizardDock({required this.primary, required this.back});

  final Widget primary;
  final Widget back;

  @override
  Widget build(BuildContext context) {
    final stacked = MediaQuery.textScalerOf(context).scale(15) > 19.5;
    if (stacked) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [back, const SizedBox(height: 4), primary],
      );
    }
    return Row(
      children: [
        back,
        const SizedBox(width: 8),
        Expanded(child: primary),
      ],
    );
  }
}

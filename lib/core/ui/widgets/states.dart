import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../driver_mode.dart';
import '../motion.dart';
import '../painters/chevron_spinner.dart';
import '../painters/empty_illustration.dart';
import '../painters/success_check.dart';
import '../status.dart';
import '../theme.dart';
import '../tokens.dart';
import '../typography.dart';
import 'buttons.dart';
import 'toast.dart';

/// Empty list or screen (design v3 §4): the drawing on a soft 120 px
/// `surfaceAlt` disc that floats (±6 px, [AknMotion.float]), a title 18/24
/// w800, one sentence (bodySmall dim) and one primary button. Everything
/// enters in a short cascade (fade + rise). The copy invites the action:
/// "Açık siparişiniz yok. Yeni sipariş için Sipariş ver’e dokunun." Empty
/// states are the one place text is centred.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.illustration = AknIllustration.inbox,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.compact = false,
    this.tone,
  });

  final String title;
  final String? message;
  final AknIllustration illustration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// Smaller layout for sections and sheets.
  final bool compact;

  /// Deprecated: the drawings always use the graphite + orange palette.
  final AknTone? tone;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Semantics(
      container: true,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AknSpace.page,
          vertical: compact ? 16 : 32,
        ),
        child: _Cascade(
          children: [
            _FloatingArt(
              diameter: _artSize(context, compact),
              child: EmptyIllustration(
                subject: illustration,
                size: _artSize(context, compact) * 0.84,
              ),
            ),
            Padding(
              padding: EdgeInsets.only(top: compact ? 12 : 18),
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: _titleStyle(t),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    message!,
                    style: t.bodySmall.copyWith(color: c.dim),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            if ((actionLabel != null && onAction != null) ||
                (secondaryLabel != null && onSecondary != null))
              Padding(
                padding: EdgeInsets.only(top: compact ? 16 : 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (actionLabel != null && onAction != null)
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 180),
                        child: AknButton(
                          label: actionLabel!,
                          onPressed: onAction,
                        ),
                      ),
                    if (secondaryLabel != null && onSecondary != null) ...[
                      const SizedBox(height: 4),
                      AknButton.ghost(
                        label: secondaryLabel!,
                        onPressed: onSecondary,
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Load failure with a retry (design v3 §4, copy rule §10.2): the "route with
/// a gap" drawing on the floating disc — it shakes once as it appears (three
/// quick ±6 px swings) — what failed, what to do and "Tekrar dene". [offline]
/// switches to the no-connection wording and the cloud drawing; the message
/// is always Turkish and never a raw payload — never "İstek başarısız" or
/// "Bir hata oluştu".
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    this.title,
    this.message,
    this.onRetry,
    this.retryLabel = 'Tekrar dene',
    this.offline = false,
    this.compact = false,
    this.traceId,
  });

  final String? title;
  final String? message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final bool offline;
  final bool compact;

  /// Server trace id; its first 8 characters are shown as "Destek kodu" and
  /// copied on tap (spec C.7).
  final String? traceId;

  /// Default title when the reason is not known (what failed).
  static const String defaultTitle = 'Bilgiler yüklenemedi';

  /// Default sentence (what to do): the 5xx wording of §10.2.
  static const String defaultMessage =
      'Sunucuya şu an ulaşılamıyor. Birkaç dakika sonra tekrar deneyin.';

  /// Offline title and sentence (§10.2, reads).
  static const String offlineTitle = 'Bağlantı yok';
  static const String offlineMessage =
      'Bağlantı gelince bu sayfa kendiliğinden yenilenir.';

  String? get _supportCode {
    final t = traceId?.trim();
    if (t == null || t.isEmpty) return null;
    final plain = t.startsWith('fake-') ? t.substring(5) : t;
    return plain.length <= 8 ? plain : plain.substring(0, 8);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final code = _supportCode;
    final art = _artSize(context, compact);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AknSpace.page,
          vertical: compact ? 16 : 32,
        ),
        child: _Cascade(
          children: [
            _FloatingArt(
              diameter: art,
              shake: true,
              child: EmptyIllustration(
                subject: offline
                    ? AknIllustration.offline
                    : AknIllustration.error,
                size: art * 0.84,
              ),
            ),
            Padding(
              padding: EdgeInsets.only(top: compact ? 12 : 18),
              child: Semantics(
                header: true,
                child: Text(
                  title ?? (offline ? offlineTitle : defaultTitle),
                  style: _titleStyle(t),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  message ?? (offline ? offlineMessage : defaultMessage),
                  style: t.bodySmall.copyWith(color: c.dim),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            if (code != null || onRetry != null)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (code != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _SupportCode(code: code),
                    ),
                  if (onRetry != null)
                    Padding(
                      padding: EdgeInsets.only(
                        top: code != null ? 6 : (compact ? 16 : 24),
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 180),
                        child: AknButton.secondary(
                          label: retryLabel,
                          icon: PhosphorIconsRegular.arrowClockwise,
                          onPressed: onRetry,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// "Destek kodu: 1a2b3c4d" (spec C.7): a quiet pill; a tap copies the code.
class _SupportCode extends StatelessWidget {
  const _SupportCode({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    // "Destek kodu: 1a2b3c4d" (spec C.7): dokununca panoya kopyalanır.
    return Semantics(
      button: true,
      label: 'Destek kodu $code, kopyalamak için dokunun',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          AknHaptics.selection();
          await Clipboard.setData(ClipboardData(text: code));
          if (context.mounted) {
            AppToast.info('Destek kodu kopyalandı.', context: context);
          }
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight:
                AknDriverMode.maybeOf(context)?.minTap ?? AknSpace.minTap,
          ),
          child: Center(
            widthFactor: 1,
            child: PressScale(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: AknRadius.pillAll,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          'Destek kodu: $code',
                          style: t.caption.copyWith(
                            color: c.dim,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(PhosphorIconsRegular.copy, size: 15, color: c.dim),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Centred brand loader (design v3 §5): the orange » spinner on a soft
/// floating disc with an optional dim message that fades in (full-screen
/// waits).
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    return Center(
      child: Semantics(
        label: message ?? 'Yükleniyor',
        liveRegion: true,
        excludeSemantics: true,
        child: _Cascade(
          children: [
            const _FloatingArt(
              diameter: 68,
              decorated: false,
              child: ChevronSpinner(size: 24, semanticLabel: null),
            ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  message!,
                  style: t.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The offline line under the app bar (design v3 §4): a soft `surfaceAlt`
/// well (radius 16) inset on the 20 px page edge, with the icon in a small
/// white disc and "Çevrimdışı. Değişiklikler telefona kaydediliyor (3)."
/// (label 13/18 600 ink; driver mode makes it 15/20). Online with queued
/// operations it reads "3 işlem gönderilmeyi bekliyor" and the upload arrow
/// bobs. The well grows and fades in and out; the icon pops when the state
/// changes; with [onTap] it presses.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({
    super.key,
    required this.offline,
    this.pendingCount = 0,
    this.onTap,
  });

  final bool offline;
  final int pendingCount;

  /// E.g. open "Bekleyen işlemler".
  final VoidCallback? onTap;

  static String message({required bool offline, required int pending}) {
    if (offline) {
      return pending > 0
          ? 'Çevrimdışı. Değişiklikler telefona kaydediliyor ($pending).'
          : 'Çevrimdışı. Değişiklikler telefona kaydediliyor.';
    }
    return pending > 0 ? '$pending işlem gönderilmeyi bekliyor' : '';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final visible = offline || pendingCount > 0;
    final text = message(offline: offline, pending: pendingCount);
    final tap = onTap;
    return AknAnimatedSize(
      curve: AknMotion.emphasizedCurve,
      duration: AknMotion.slow,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: AknMotion.of(context, AknMotion.base),
        switchInCurve: AknMotion.standard,
        switchOutCurve: AknMotion.exit,
        child: !visible
            ? const SizedBox(key: ValueKey('none'), width: double.infinity)
            : Padding(
                key: const ValueKey('banner'),
                padding: const EdgeInsets.fromLTRB(
                  AknSpace.page,
                  8,
                  AknSpace.page,
                  4,
                ),
                child: Semantics(
                  liveRegion: true,
                  button: tap != null,
                  label: text,
                  excludeSemantics: true,
                  child: PressScale(
                    enabled: tap != null,
                    child: Material(
                      color: c.surfaceAlt,
                      shape: const RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: tap == null
                            ? null
                            : () {
                                AknHaptics.selection();
                                tap();
                              },
                        splashFactory: NoSplash.splashFactory,
                        highlightColor: c.line,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight:
                                AknDriverMode.maybeOf(context)?.minTap ??
                                AknSpace.minTap,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                            child: Row(
                              children: [
                                _BannerGlyph(offline: offline),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: AnimatedSwitcher(
                                    duration: AknMotion.of(
                                      context,
                                      AknMotion.base,
                                    ),
                                    layoutBuilder: (current, previous) => Stack(
                                      alignment:
                                          AlignmentDirectional.centerStart,
                                      children: [...previous, ?current],
                                    ),
                                    child: Text(
                                      text,
                                      key: ValueKey(text),
                                      style: t.label.copyWith(color: c.ink),
                                    ),
                                  ),
                                ),
                                if (tap != null) ...[
                                  const SizedBox(width: 8),
                                  Icon(
                                    PhosphorIconsRegular.caretRight,
                                    size: 16,
                                    color: c.dim,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// The banner's icon in a small white disc: the slashed cloud offline, the
/// upload arrow (gently bobbing) while operations wait; it pops on change.
class _BannerGlyph extends StatelessWidget {
  const _BannerGlyph({required this.offline});

  final bool offline;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final icon = offline
        ? PhosphorIconsRegular.cloudSlash
        : PhosphorIconsRegular.cloudArrowUp;
    Widget glyph = Icon(icon, size: 18, color: offline ? c.dim : c.brandInk);
    if (!offline) {
      glyph = AknAmbient(
        period: AknMotion.breathe,
        reverse: true,
        restValue: 0.5,
        child: glyph,
        builder: (context, t, child) =>
            Transform.translate(offset: Offset(0, 1.5 - 3 * t), child: child),
      );
    }
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: c.surface,
        shape: BoxShape.circle,
        boxShadow: AknShadows.pressed(c),
      ),
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: AknMotion.of(context, AknMotion.iconSwap + AknMotion.fast),
        switchInCurve: AknMotion.pop,
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: ScaleTransition(scale: a, child: child),
        ),
        child: KeyedSubtree(key: ValueKey(offline), child: glyph),
      ),
    );
  }
}

/// Outcome body after a submit (design v3 §4, §5): the success check — a
/// disc pops, the ring and check draw, particles burst once — or, for other
/// tones, the tone's icon on its soft tinted disc (danger shakes, every
/// badge sends one ripple); then a title that echoes the verb ("Siparişiniz
/// bayiye gönderildi"), the detail, a primary ("Siparişi aç") and a ghost
/// ("Ana sayfaya dön"), cascading in. Screen readers hear the title.
class ResultView extends StatelessWidget {
  const ResultView({
    super.key,
    required this.title,
    this.message,
    this.tone = AknTone.ok,
    this.icon,
    this.details,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String? message;

  /// [AknTone.ok] draws the animated check; other tones show [icon].
  final AknTone tone;
  final IconData? icon;

  /// E.g. a group of `FactRow`s (order numbers, amounts).
  final Widget? details;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final size = (t.title.fontSize ?? 20) + 2;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AknSpace.page, 28, AknSpace.page, 16),
      child: _Cascade(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: tone == AknTone.ok && icon == null
                ? const SuccessCheck(size: 84, semanticLabel: null)
                : _ToneBadge(
                    icon: icon ?? AknStatus.toneIcon(tone),
                    tone: tone,
                  ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Semantics(
              header: true,
              liveRegion: true,
              child: Text(
                title,
                style: t.title.copyWith(
                  fontSize: size,
                  height: (size + 6) / size,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
                textScaler: _resultTitleScaler(context),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                message!,
                style: t.body.copyWith(color: c.dim),
                textAlign: TextAlign.center,
              ),
            ),
          if (details != null)
            Padding(padding: const EdgeInsets.only(top: 20), child: details),
          if (primaryLabel != null && onPrimary != null)
            Padding(
              padding: const EdgeInsets.only(top: 24),
              child: AknButton(
                label: primaryLabel!,
                expand: true,
                onPressed: onPrimary,
              ),
            ),
          if (secondaryLabel != null && onSecondary != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: AknButton.ghost(
                label: secondaryLabel!,
                expand: true,
                onPressed: onSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

/// A non-success outcome mark: the tone's icon (40 px, tone fg — brand uses
/// the Pas text orange) on an 84 px soft tone disc with a 1 px tone rim. It
/// pops in, sends one ripple ring out and — for danger — shakes once.
class _ToneBadge extends StatefulWidget {
  const _ToneBadge({required this.icon, required this.tone});

  final IconData icon;
  final AknTone tone;

  @override
  State<_ToneBadge> createState() => _ToneBadgeState();
}

class _ToneBadgeState extends State<_ToneBadge>
    with SingleTickerProviderStateMixin {
  static const double _size = 84;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final tc = c.tone(widget.tone);
    final shakes = widget.tone == AknTone.danger;
    final disc = Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: tc.bg,
        shape: BoxShape.circle,
        border: Border.all(color: tc.line),
      ),
      alignment: Alignment.center,
      child: Icon(widget.icon, color: tc.fg, size: 40),
    );
    return SizedBox.square(
      dimension: _size,
      child: AnimatedBuilder(
        animation: _c,
        child: disc,
        builder: (context, child) {
          final v = _c.value;
          final appear = (v / 0.42).clamp(0.0, 1.0);
          final scale = 0.6 + 0.4 * AknMotion.pop.transform(appear);
          final ripple = ((v - 0.25) / 0.6).clamp(0.0, 1.0);
          final shake = shakes ? _shakeOffset((v - 0.42) / 0.58) : 0.0;
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              // The ripple is a fixed ring scaled outwards (no relayout).
              if (ripple > 0 && ripple < 1)
                IgnorePointer(
                  child: Transform.scale(
                    scale: 1 + 0.38 * Curves.easeOut.transform(ripple),
                    child: SizedBox.square(
                      dimension: _size,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: tc.solid.withValues(
                              alpha: 0.35 * (1 - ripple),
                            ),
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Opacity(
                opacity: appear.clamp(0.0, 1.0),
                alwaysIncludeSemantics: true,
                child: Transform.translate(
                  offset: Offset(shake, 0),
                  child: Transform.scale(scale: scale, child: child),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ───────────────────────── Shared pieces ─────────────────────────

/// The art size: 120 (compact 84), one step smaller at large text so the
/// whole state still fits a phone at 200 %.
double _artSize(BuildContext context, bool compact) {
  final large = MediaQuery.textScalerOf(context).scale(10) >= 16;
  if (compact) return large ? 72 : 84;
  return large ? 96 : 120;
}

/// Title of empty and error states: 18/24 w800 (one step up in driver
/// mode, where `headline` is larger).
TextStyle _titleStyle(AknTextStyles t) {
  final size = (t.headline.fontSize ?? 17) + 1;
  return t.headline.copyWith(
    fontSize: size,
    height: (size + 6) / size,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.3,
  );
}

/// The result title (22 px) grows with the text size up to 1.6× (like page
/// titles), so at 200 % it stays on two lines; the sentences under it keep
/// the full scale.
TextScaler _resultTitleScaler(BuildContext context) =>
    MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.6);

/// Three quick decaying ±6 px swings over linear [t] (0..1); 0 outside.
double _shakeOffset(double t) {
  if (t <= 0 || t >= 1) return 0;
  return 6 * math.sin(t * 3 * 2 * math.pi) * (1 - t);
}

/// Plays the entrance of a state view once: each child fades in, rises and
/// settles from a slightly smaller scale, 70 ms after the previous one (the
/// first — the art — pops). One controller drives the whole cascade, the
/// widget structure never changes (nothing below remounts when it ends) and
/// semantics stay present throughout; reduce motion shows everything at
/// once.
class _Cascade extends StatefulWidget {
  const _Cascade({
    required this.children,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final List<Widget> children;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  State<_Cascade> createState() => _CascadeState();
}

class _CascadeState extends State<_Cascade>
    with SingleTickerProviderStateMixin {
  static const int _each = 480;
  static const int _step = 70;
  static const int _slots = 6;
  static const int _total = _each + _step * (_slots - 1);

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _total),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final children = widget.children;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.crossAxisAlignment,
      children: [
        for (var i = 0; i < children.length; i++)
          _Rise(
            progress: _c,
            start: _step * math.min(i, _slots - 1) / _total,
            end: (_step * math.min(i, _slots - 1) + _each) / _total,
            lift: i == 0 ? 8 : 14,
            fromScale: i == 0 ? 0.86 : 0.97,
            pop: i == 0,
            child: children[i],
          ),
      ],
    );
  }
}

/// One step of a [_Cascade]: opacity, lift and scale from [progress] between
/// [start] and [end]. The structure is the same before, during and after.
class _Rise extends AnimatedWidget {
  const _Rise({
    required Animation<double> progress,
    required this.start,
    required this.end,
    required this.lift,
    required this.fromScale,
    required this.pop,
    required this.child,
  }) : super(listenable: progress);

  final double start;
  final double end;
  final double lift;
  final double fromScale;
  final bool pop;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = (listenable as Animation<double>).value;
    final lin = ((p - start) / (end - start)).clamp(0.0, 1.0);
    final v = AknMotion.emphasizedCurve.transform(lin);
    final s = pop ? AknMotion.pop.transform(lin) : v;
    return Opacity(
      opacity: v.clamp(0.0, 1.0),
      alwaysIncludeSemantics: true,
      child: Transform.translate(
        offset: Offset(0, lift * (1 - v)),
        child: Transform.scale(
          scale: fromScale + (1 - fromScale) * s,
          child: child,
        ),
      ),
    );
  }
}

/// The art of a state view: [child] on a soft `surfaceAlt` disc ([diameter])
/// with a gentle top-left light. The disc floats ±6 px ([AknMotion.float],
/// ambient), its soft ground shadow shrinks as it rises and — when
/// [decorated] — an orange dot, a small ring and a grey dot drift around it
/// with a little parallax. [shake] swings the disc three times as it
/// appears (errors).
class _FloatingArt extends StatefulWidget {
  const _FloatingArt({
    required this.diameter,
    required this.child,
    this.decorated = true,
    this.shake = false,
  });

  final double diameter;
  final Widget child;
  final bool decorated;
  final bool shake;

  @override
  State<_FloatingArt> createState() => _FloatingArtState();
}

class _FloatingArtState extends State<_FloatingArt>
    with SingleTickerProviderStateMixin {
  AnimationController? _shake;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.shake && _shake == null && !AknMotion.reduced(context)) {
      _shake = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1000),
      )..forward();
    }
  }

  @override
  void dispose() {
    _shake?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final d = widget.diameter;
    final amp = d >= 100 ? 6.0 : 4.0;
    // A soft well with a little depth (lighter top-left); in light mode a
    // white rim keeps its edge on the off-white page as well as on cards.
    Widget disc = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: c.isDark
              ? [Color.lerp(c.surfaceAlt, c.ink, 0.06)!, c.surfaceAlt]
              : [
                  Color.lerp(c.surfaceAlt, c.surface, 0.4)!,
                  Color.lerp(c.surfaceAlt, c.lineStrong, 0.12)!,
                ],
        ),
        border: c.isDark
            ? Border.all(color: Color.lerp(c.surfaceAlt, c.ink, 0.1)!)
            : Border.all(color: c.surface, width: 3),
      ),
      child: SizedBox.square(
        dimension: d,
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(top: d * 0.02),
            child: widget.child,
          ),
        ),
      ),
    );
    // The disc's picture is cached: floating and shaking only move it.
    disc = RepaintBoundary(child: disc);
    final shake = _shake;
    if (shake != null) {
      disc = AnimatedBuilder(
        animation: shake,
        child: disc,
        builder: (context, child) => Transform.translate(
          offset: Offset(_shakeOffset((shake.value - 0.4) / 0.6), 0),
          child: child,
        ),
      );
    }
    final width = d + (widget.decorated ? 44 : 16);
    final height = d + amp * 2 + 12;
    return RepaintBoundary(
      child: SizedBox(
        width: width,
        height: height,
        child: AknAmbient(
          period: AknMotion.float,
          reverse: true,
          restValue: 0.5,
          child: disc,
          builder: (context, t, child) => CustomPaint(
            painter: _ArtBackdropPainter(
              t: t,
              diameter: d,
              amplitude: amp,
              shadow: c.isDark
                  ? const Color(0x66000000)
                  : c.ink.withValues(alpha: 0.10),
              accent: widget.decorated ? c.logo : null,
              ring: c.lineStrong.withValues(alpha: 0.7),
              dot: c.lineStrong.withValues(alpha: 0.45),
            ),
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.only(top: amp),
                child: Transform.translate(
                  offset: Offset(0, amp - 2 * amp * t),
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

/// The ground shadow under a [_FloatingArt] disc and its drifting
/// decorations, for float phase [t] (0 = lowest, 1 = highest).
class _ArtBackdropPainter extends CustomPainter {
  _ArtBackdropPainter({
    required this.t,
    required this.diameter,
    required this.amplitude,
    required this.shadow,
    required this.accent,
    required this.ring,
    required this.dot,
  });

  final double t;
  final double diameter;
  final double amplitude;
  final Color shadow;

  /// The orange dot (null: no decorations).
  final Color? accent;
  final Color ring;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final r = diameter / 2;
    final dy = amplitude - 2 * amplitude * t;
    // The ground shadow: narrower and lighter while the disc is up.
    final shadowWidth = diameter * 0.58 * (1 - 0.16 * t);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx, amplitude + diameter + amplitude + 5),
        width: shadowWidth,
        height: 7,
      ),
      Paint()
        ..color = shadow.withValues(alpha: shadow.a * (1 - 0.4 * t))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    final a = accent;
    if (a == null) return;
    // Decorations drift against the disc (a little parallax).
    final center = Offset(cx, amplitude + r);
    final drift = -dy * 0.5;
    canvas.drawCircle(
      center + Offset.fromDirection(-0.8, r + 9) + Offset(0, drift),
      diameter * 0.033,
      Paint()..color = a,
    );
    canvas.drawCircle(
      center + Offset.fromDirection(2.45, r + 7) + Offset(0, drift * 0.7),
      diameter * 0.038,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = ring,
    );
    canvas.drawCircle(
      center + Offset.fromDirection(-2.35, r + 12) + Offset(0, -drift * 0.8),
      diameter * 0.02,
      Paint()..color = dot,
    );
  }

  @override
  bool shouldRepaint(_ArtBackdropPainter old) =>
      old.t != t ||
      old.diameter != diameter ||
      old.amplitude != amplitude ||
      old.shadow != shadow ||
      old.accent != accent ||
      old.ring != ring ||
      old.dot != dot;
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';

import '../../../../core/models/auth_models.dart';
import '../../../../core/network/app_failure.dart';
import '../../../../core/ui/ui.dart';
import '../../application/auth_clock.dart';
import '../../application/auth_errors.dart';
import '../../copy.dart';
import 'auth_header.dart';
import 'countdown.dart';

/// Kod doğrulama: hata fırlatırsa ([AppFailure]) mesaj kutuların altında gösterilir.
typedef CodeVerifier = Future<void> Function(String challengeId, String code);

/// Yeni kod: yeni (ya da aynı kimlikli) sorgu döner.
typedef CodeResender = Future<OtpChallenge> Function(OtpChallenge current);

/// 6 kutulu kod girişi (spec A.4 A1 "Code screen"): iOS tek seferlik kod önerisi
/// (`AutofillHints.oneTimeCode`), Android SMS onay penceresi (SMS User Consent), yapıştırma (uzun basma
/// menüsü ya da otomatik doldurma; rakam dışı karakterler atılır), altıncı hanede otomatik doğrulama,
/// geri sayımlı "Yeniden gönder" ve kodun geçerlilik süresi. 2FA, telefonla giriş ve telefon doğrulama
/// aynı bileşeni kullanır.
class CodeEntry extends ConsumerStatefulWidget {
  const CodeEntry({
    super.key,
    required this.challenge,
    required this.onVerify,
    required this.onResend,
    this.note,
    this.onRestart,
    this.autofocus = true,
    this.showHeader = true,
    this.showLogo = true,
  });

  final OtpChallenge challenge;
  final CodeVerifier onVerify;
  final CodeResender onResend;

  /// Altta küçük açıklama (2FA, telefonla giriş).
  final String? note;

  /// Sorgunun süresi tamamen dolduğunda ("Doğrulama süresi doldu") baştan başlatır.
  final VoidCallback? onRestart;
  final bool autofocus;

  /// "Kodu girin" başlığı ve kodun gittiği numara (telefon doğrulamada sayfa kendi başlığını çizer).
  final bool showHeader;

  /// Başlığın üstündeki 40 px logo karosu.
  final bool showLogo;

  @override
  ConsumerState<CodeEntry> createState() => _CodeEntryState();
}

class _CodeEntryState extends ConsumerState<CodeEntry>
    with TickerProviderStateMixin {
  static const _length = 6;

  final _controller = TextEditingController();
  final _focus = FocusNode(debugLabel: 'code');

  /// Hatalı kodda kutular üç kez hızla sağa sola sallanır (±6 px, sönerek).
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  /// Doğru kodda kutular yeşile döner ve bir kez "pop" yapar (1 → 1,05 → 1).
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  bool _verified = false;

  late OtpChallenge _challenge = widget.challenge;
  late DateTime _resendAt;
  late DateTime _expiresAt;
  DateTime? _resendBlockedUntil;
  bool _verifying = false;
  bool _resending = false;
  bool _restartNeeded = false;
  String? _error;

  DateTime _now() => ref.read(authClockProvider)();

  @override
  void initState() {
    super.initState();
    _stamp(widget.challenge);
    _controller.addListener(_onTextChanged);
  }

  void _stamp(OtpChallenge c) {
    final now = _now();
    _challenge = c;
    _resendAt = now.add(Duration(seconds: math.max(0, c.resendInSeconds)));
    _expiresAt = now.add(Duration(seconds: math.max(0, c.expiresInSeconds)));
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focus.dispose();
    _shake.dispose();
    _pop.dispose();
    super.dispose();
  }

  void _shakeBoxes() {
    if (AknMotion.reduced(context)) return;
    unawaited(_shake.forward(from: 0));
  }

  void _onTextChanged() {
    if (_error != null && _controller.text.isNotEmpty) {
      setState(() => _error = null);
    }
  }

  void _announce(String message) {
    final view = View.maybeOf(context);
    if (view == null) return;
    unawaited(
      SemanticsService.sendAnnouncement(view, message, TextDirection.ltr),
    );
  }

  Future<void> _verify([String? value]) async {
    final code = (value ?? _controller.text).trim();
    if (_verifying) return;
    if (code.length != _length) {
      setState(() => _error = AuthCopy.codeIncomplete);
      AknHaptics.warning();
      _shakeBoxes();
      _announce(AuthCopy.codeIncomplete);
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await widget.onVerify(_challenge.challengeId, code);
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _verified = true;
      });
      if (!AknMotion.reduced(context)) unawaited(_pop.forward(from: 0));
    } on AppFailure catch (f) {
      if (!mounted) return;
      final info = describeAuthFailure(
        f,
        unauthorizedMessage: AuthCopy.codeExpired,
      );
      final message = f is ValidationFailure
          ? (info.fieldError('code') ?? info.message)
          : info.message;
      setState(() {
        _verifying = false;
        _error = message;
        _restartNeeded = _isRestart(message);
      });
      _controller.clear();
      AknHaptics.warning();
      _shakeBoxes();
      _announce(message);
      if (mounted) _focus.requestFocus();
    }
  }

  bool _isRestart(String message) =>
      message.contains('baştan başlayın') && widget.onRestart != null;

  Future<void> _resend() async {
    if (_resending) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      final next = await widget.onResend(_challenge);
      if (!mounted) return;
      setState(() {
        _resending = false;
        _resendBlockedUntil = null;
        _restartNeeded = false;
        _stamp(next);
      });
      _controller.clear();
      AppToast.success(AuthCopy.codeResent);
      _focus.requestFocus();
    } on AppFailure catch (f) {
      if (!mounted) return;
      final info = describeAuthFailure(f);
      setState(() {
        _resending = false;
        _error = info.message;
        _restartNeeded = _isRestart(info.message);
        if (f is RateLimitedFailure) {
          _resendBlockedUntil = _now().add(
            f.retryAfter ?? const Duration(seconds: 60),
          );
        }
      });
      _announce(info.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final masked = _challenge.maskedPhone.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showHeader) ...[
          AuthPageHeader(
            title: AuthCopy.codeHeadline,
            message: masked.isEmpty
                ? AuthCopy.codeSentGeneric
                : AuthCopy.codeSentTo(masked),
            showLogo: widget.showLogo,
          ),
          const SizedBox(height: 28),
        ],
        AuthRise(
          delay: const Duration(milliseconds: 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _pin(context),
              const SizedBox(height: 14),
              AnimatedSwitcher(
                duration: AknMotion.of(context, AknMotion.fast),
                switchInCurve: AknMotion.standard,
                layoutBuilder: (current, previous) => Stack(
                  alignment: AlignmentDirectional.centerStart,
                  children: [...previous, ?current],
                ),
                child: KeyedSubtree(
                  key: ValueKey(_error == null ? 'time' : 'error'),
                  child: _status(context),
                ),
              ),
              const SizedBox(height: 4),
              _resendRow(context),
              if (_restartNeeded && widget.onRestart != null) ...[
                const SizedBox(height: 4),
                AknButton.secondary(
                  label: AuthCopy.restart,
                  expand: true,
                  onPressed: widget.onRestart,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        AuthRise(
          delay: const Duration(milliseconds: 160),
          child: AknButton(
            label: AuthCopy.verify,
            expand: true,
            size: AknButtonSize.large,
            loading: _verifying,
            loadingLabel: AuthCopy.verifying,
            onPressed: _verifying ? null : _verify,
          ),
        ),
        if (widget.note != null) ...[
          const SizedBox(height: 16),
          Text(widget.note!, style: t.bodySmall.copyWith(color: c.dim)),
        ],
      ],
    );
  }

  /// 6 kutu (tasarım v3): en çok 52 × 60, r14, beyaz zemin ve 1,5 px kontrol çizgisi; odaktaki kutu 2 px
  /// turuncu çizgi ve yumuşak turuncu hale alır (geçiş animasyonlu), girilen rakam hafifçe büyüyerek
  /// belirir; hatada kutular kırmızı kuyuya döner ve sallanır, doğru kodda yeşile döner ve "pop" yapar.
  /// Rakamlar eş genişlikte (tnum) 24 800.
  Widget _pin(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : 360;
        final boxW = math.min(52.0, (maxW - gap * (_length - 1)) / _length);
        final boxH = math.max(60.0, scaler.scale(24) * 1.6);
        final digit = t.number.copyWith(
          fontSize: 24,
          height: 28 / 24,
          color: c.ink,
        );
        PinTheme theme({
          required Color border,
          double width = 1.5,
          Color? fill,
          Color? text,
          List<BoxShadow>? glow,
        }) => PinTheme(
          width: boxW,
          height: boxH,
          textStyle: text == null ? digit : digit.copyWith(color: text),
          decoration: BoxDecoration(
            color: fill ?? c.surface,
            borderRadius: AknRadius.input,
            border: Border.all(color: border, width: width),
            boxShadow: glow,
          ),
        );
        final ok = theme(
          border: c.ok.fg,
          width: 2,
          fill: c.ok.bg,
          text: c.ok.fg,
        );
        final focusGlow = [
          BoxShadow(
            color: c.brand.withValues(alpha: c.isDark ? 0.28 : 0.16),
            spreadRadius: 4,
          ),
        ];
        final pinput = Pinput(
          length: _length,
          controller: _controller,
          focusNode: _focus,
          autofocus: widget.autofocus,
          enabled: !_verifying,
          separatorBuilder: (_) => const SizedBox(width: gap),
          defaultPinTheme: _verified ? ok : theme(border: c.lineStrong),
          focusedPinTheme: _verified
              ? ok
              : theme(border: c.brand, width: 2, glow: focusGlow),
          submittedPinTheme: _verified
              ? ok
              : theme(border: c.ink.withValues(alpha: c.isDark ? 0.7 : 0.55)),
          errorPinTheme: theme(
            border: c.danger.fg,
            width: 2,
            fill: c.danger.bg,
          ),
          forceErrorState: _error != null,
          autofillHints: const [AutofillHints.oneTimeCode],
          androidSmsAutofillMethod: AndroidSmsAutofillMethod.smsUserConsentApi,
          // Yeniden gönderilen kodun SMS'i de önerilsin.
          listenForMultipleSmsOnAndroid: true,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          hapticFeedbackType: HapticFeedbackType.selectionClick,
          animationDuration: AknMotion.of(context, AknMotion.base),
          animationCurve: AknMotion.pop,
          pinAnimationType: context.reduceMotion
              ? PinAnimationType.none
              : PinAnimationType.scale,
          showCursor: true,
          cursor: _Cursor(color: c.brand),
          onCompleted: _verify,
          onSubmitted: (_) => _verify(),
        );
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: Semantics(
            label: AuthCopy.codeFieldLabel,
            child: AnimatedBuilder(
              animation: Listenable.merge([_shake, _pop]),
              child: pinput,
              builder: (context, child) {
                final s = _shake.value;
                final p = _pop.value;
                return Transform.translate(
                  offset: Offset(6 * math.sin(s * 6 * math.pi) * (1 - s), 0),
                  child: Transform.scale(
                    scale: 1 + 0.05 * math.sin(math.pi * p),
                    alignment: AlignmentDirectional.centerStart,
                    child: child,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _status(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final error = _error;
    if (error != null) {
      // Alan hatası gibi (§4 v3): simge + 13/18 600 kırmızı cümle.
      return Semantics(liveRegion: true, child: AknFieldError(error, inset: 0));
    }
    return CountdownBuilder(
      until: _expiresAt,
      builder: (context, remaining) {
        final expired = remaining <= Duration.zero;
        final color = expired ? c.warn.fg : c.dim;
        return Row(
          children: [
            Icon(
              expired
                  ? PhosphorIconsRegular.hourglassLow
                  : PhosphorIconsRegular.timer,
              size: 17,
              color: color,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                expired
                    ? AuthCopy.codeExpired
                    : AuthCopy.codeExpiresIn(formatWait(remaining)),
                style: t.bodySmall.copyWith(
                  color: color,
                  fontWeight: expired ? FontWeight.w600 : FontWeight.w500,
                  fontFeatures: AknNumerals.tabular,
                ),
                semanticsLabel: expired
                    ? AuthCopy.codeExpired
                    : AuthCopy.codeExpiresIn(spokenWait(remaining)),
              ),
            ),
          ],
        );
      },
    );
  }

  /// "Kodu tekrar gönder (0:45)" (tasarım v3): sade düğme, ink 600, rakamlar eş genişlikte; beklerken
  /// soluk ve kapalı, süre dolunca ok simgesiyle birlikte belirginleşir.
  Widget _resendRow(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final blocked = _resendBlockedUntil;
    final until = blocked != null && blocked.isAfter(_resendAt)
        ? blocked
        : _resendAt;
    return CountdownBuilder(
      until: until,
      builder: (context, remaining) {
        final waiting = remaining > Duration.zero;
        final label = waiting
            ? AuthCopy.resendIn(formatWait(remaining))
            : AuthCopy.resend;
        final enabled = !waiting && !_resending;
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: Semantics(
            button: true,
            enabled: enabled,
            label: waiting
                ? AuthCopy.resendInSpoken(spokenWait(remaining))
                : AuthCopy.resend,
            excludeSemantics: true,
            onTap: enabled ? _resend : null,
            child: PressScale(
              enabled: enabled,
              child: TextButton(
                onPressed: enabled ? _resend : null,
                style: TextButton.styleFrom(
                  minimumSize: const Size(AknSpace.minTap, AknSpace.minTap),
                  // Metin 20 px kenarda başlar (sola dayalı düzen).
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  foregroundColor: c.ink,
                  disabledForegroundColor: c.dim,
                  overlayColor: c.surfaceAlt,
                  shape: const RoundedRectangleBorder(
                    borderRadius: AknRadius.buttonSmall,
                  ),
                  textStyle: t.body.copyWith(
                    height: 20 / 15,
                    fontWeight: FontWeight.w700,
                    fontFeatures: AknNumerals.tabular,
                  ),
                ),
                child: _resending
                    ? ChevronSpinner(size: 18, color: c.ink)
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PhosphorIconsRegular.arrowClockwise,
                            size: 17,
                            color: enabled ? c.brand : c.dim,
                          ),
                          const SizedBox(width: 6),
                          Flexible(child: Text(label)),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// İnce imleç: 18 × 2 turuncu çizgi; yavaşça nefes alır (opaklık 1 ↔ 0,35, [AknMotion.breathe]).
/// Azaltılmış harekette ve testlerde durur.
class _Cursor extends StatelessWidget {
  const _Cursor({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AknAmbient(
          period: AknMotion.breathe,
          reverse: true,
          builder: (context, t, child) =>
              Opacity(opacity: 1 - 0.65 * t, child: child),
          child: Container(
            width: 18,
            height: 2,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ],
    );
  }
}

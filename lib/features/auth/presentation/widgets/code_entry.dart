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
  });

  final OtpChallenge challenge;
  final CodeVerifier onVerify;
  final CodeResender onResend;

  /// Altta küçük açıklama (2FA, telefonla giriş).
  final String? note;

  /// Sorgunun süresi tamamen dolduğunda ("Doğrulama süresi doldu") baştan başlatır.
  final VoidCallback? onRestart;
  final bool autofocus;

  @override
  ConsumerState<CodeEntry> createState() => _CodeEntryState();
}

class _CodeEntryState extends ConsumerState<CodeEntry> {
  static const _length = 6;

  final _controller = TextEditingController();
  final _focus = FocusNode(debugLabel: 'code');

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
    super.dispose();
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
      setState(() => _verifying = false);
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
        const Center(
          child: AknIconBox(
            icon: Icons.sms_outlined,
            tone: AknTone.brand,
            size: 56,
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            AuthCopy.codeHeadline,
            style: t.title,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          masked.isEmpty
              ? AuthCopy.codeSentGeneric
              : AuthCopy.codeSentTo(masked),
          style: t.body.copyWith(color: c.dim),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        _pin(context),
        const SizedBox(height: 12),
        _status(context),
        const SizedBox(height: 20),
        AknButton(
          label: AuthCopy.verify,
          expand: true,
          size: AknButtonSize.large,
          loading: _verifying,
          loadingLabel: AuthCopy.verifying,
          onPressed: _verifying ? null : _verify,
        ),
        const SizedBox(height: 12),
        _resendRow(context),
        if (_restartNeeded && widget.onRestart != null) ...[
          const SizedBox(height: 4),
          AknButton.secondary(
            label: AuthCopy.restart,
            expand: true,
            onPressed: widget.onRestart,
          ),
        ],
        if (widget.note != null) ...[
          const SizedBox(height: 16),
          Text(
            widget.note!,
            style: t.caption.copyWith(color: c.dim),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }

  Widget _pin(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : 360;
        final boxW = math.min(52.0, (maxW - gap * (_length - 1)) / _length);
        final boxH = math.max(56.0, scaler.scale(22) * 1.6);
        final digit = t.title.copyWith(
          color: c.ink,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
        PinTheme theme(Color border, Color fill, {double width = 1}) =>
            PinTheme(
              width: boxW,
              height: boxH,
              textStyle: digit,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: AknRadius.input,
                border: Border.all(color: border, width: width),
              ),
            );
        final fill = c.isDark ? c.surfaceAlt : c.surface;
        return Semantics(
          label: AuthCopy.codeFieldLabel,
          child: Pinput(
            length: _length,
            controller: _controller,
            focusNode: _focus,
            autofocus: widget.autofocus,
            enabled: !_verifying,
            separatorBuilder: (_) => const SizedBox(width: gap),
            defaultPinTheme: theme(c.lineStrong, fill),
            focusedPinTheme: theme(c.brand, fill, width: 2),
            submittedPinTheme: theme(c.line, fill),
            errorPinTheme: theme(c.danger.fg, c.danger.bg, width: 1.5),
            forceErrorState: _error != null,
            autofillHints: const [AutofillHints.oneTimeCode],
            androidSmsAutofillMethod:
                AndroidSmsAutofillMethod.smsUserConsentApi,
            // Yeniden gönderilen kodun SMS'i de önerilsin.
            listenForMultipleSmsOnAndroid: true,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            hapticFeedbackType: HapticFeedbackType.selectionClick,
            animationDuration: AknMotion.of(context, AknMotion.fast),
            animationCurve: AknMotion.standard,
            pinAnimationType: context.reduceMotion
                ? PinAnimationType.none
                : PinAnimationType.fade,
            showCursor: true,
            cursor: _Cursor(color: c.brand),
            onCompleted: _verify,
            onSubmitted: (_) => _verify(),
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
      return Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(Icons.error_rounded, size: 18, color: c.danger.fg),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                error,
                style: t.bodySmall.copyWith(color: c.danger.fg),
              ),
            ),
          ],
        ),
      );
    }
    return CountdownBuilder(
      until: _expiresAt,
      builder: (context, remaining) {
        final expired = remaining <= Duration.zero;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              expired ? Icons.timer_off_outlined : Icons.timer_outlined,
              size: 16,
              color: expired ? c.warn.fg : c.dim,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                expired
                    ? AuthCopy.codeExpired
                    : AuthCopy.codeExpiresIn(formatWait(remaining)),
                style: t.caption.copyWith(
                  color: expired ? c.warn.fg : c.dim,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                semanticsLabel: expired
                    ? AuthCopy.codeExpired
                    : AuthCopy.codeExpiresIn(spokenWait(remaining)),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        );
      },
    );
  }

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
        return Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            Text(AuthCopy.noCode, style: t.bodySmall.copyWith(color: c.dim)),
            Semantics(
              button: true,
              enabled: !waiting && !_resending,
              label: waiting
                  ? AuthCopy.resendInSpoken(spokenWait(remaining))
                  : AuthCopy.resend,
              excludeSemantics: true,
              onTap: waiting || _resending ? null : _resend,
              child: TextButton(
                onPressed: waiting || _resending ? null : _resend,
                style: TextButton.styleFrom(
                  minimumSize: const Size(AknSpace.minTap, AknSpace.minTap),
                  foregroundColor: c.brandInk,
                  textStyle: t.bodyStrong.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                child: _resending
                    ? ChevronSpinner(size: 18, color: c.brandInk)
                    : Text(label),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// İnce, yanıp sönmeyen imleç (sakin hareket; azaltılmış harekette de aynı).
class _Cursor extends StatelessWidget {
  const _Cursor({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: 18,
          height: 2,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
      ],
    );
  }
}

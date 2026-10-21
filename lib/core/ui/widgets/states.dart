import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion.dart';
import '../painters/chevron_spinner.dart';
import '../painters/empty_illustration.dart';
import '../painters/success_check.dart';
import '../status.dart';
import '../theme.dart';
import '../tokens.dart';
import 'buttons.dart';
import 'toast.dart';

/// Empty list / screen: calm illustration, title, message and an optional
/// action. Every list has one (spec C.7).
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

  /// Smaller layout for cards and sheets.
  final bool compact;
  final AknTone? tone;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    return Semantics(
      container: true,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 24,
          vertical: compact ? 16 : 32,
        ),
        child: FadeUp(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EmptyIllustration(
                subject: illustration,
                size: compact ? 80 : 112,
                tone: tone,
              ),
              SizedBox(height: compact ? 12 : 20),
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: compact ? t.bodyStrong : t.headline,
                  textAlign: TextAlign.center,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Text(
                    message!,
                    style: t.body.copyWith(color: context.akn.dim),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                SizedBox(height: compact ? 12 : 20),
                AknButton(label: actionLabel!, onPressed: onAction),
              ],
              if (secondaryLabel != null && onSecondary != null)
                AknButton.ghost(label: secondaryLabel!, onPressed: onSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Load failure with a retry. [offline] switches to the "no connection"
/// wording; the message is always Turkish and never a raw payload.
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
    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 24,
          vertical: compact ? 16 : 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyIllustration(
              subject: offline
                  ? AknIllustration.offline
                  : AknIllustration.error,
              size: compact ? 80 : 112,
              tone: offline ? null : AknTone.danger,
            ),
            SizedBox(height: compact ? 12 : 20),
            Semantics(
              header: true,
              child: Text(
                title ??
                    (offline
                        ? 'İnternet bağlantısı yok'
                        : 'Bir şeyler ters gitti'),
                style: compact ? t.bodyStrong : t.headline,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                message ??
                    (offline
                        ? 'Bağlantı gelince otomatik yenilenir. Kaydettiğiniz işlemler bekleyen işlemlerde durur.'
                        : 'Bilgiler yüklenemedi. Lütfen biraz sonra tekrar deneyin.'),
                style: t.body.copyWith(color: c.dim),
                textAlign: TextAlign.center,
              ),
            ),
            if (_supportCode != null) ...[
              const SizedBox(height: 6),
              // "Destek kodu: 1a2b3c4d" (spec C.7): dokununca panoya kopyalanır.
              Semantics(
                button: true,
                label: 'Destek kodu ${_supportCode!}, kopyalamak için dokunun',
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: AknRadius.pillAll,
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: _supportCode!));
                    if (context.mounted) {
                      AppToast.info(
                        'Destek kodu kopyalandı.',
                        context: context,
                      );
                    }
                  },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: AknSpace.minTap,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              'Destek kodu: ${_supportCode!}',
                              style: t.caption.copyWith(color: c.text),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(Icons.copy_rounded, size: 16, color: c.dim),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (onRetry != null) ...[
              SizedBox(height: compact ? 12 : 20),
              AknButton.secondary(
                label: retryLabel,
                icon: Icons.refresh_rounded,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Centered brand spinner with an optional message (full-screen waits).
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ChevronSpinner(size: 30),
            if (message != null) ...[
              const SizedBox(height: 14),
              Text(message!, style: t.bodySmall, textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

/// Connection banner under the app bar: slides in while [offline] or while
/// operations wait to be sent ("2 işlem gönderilmeyi bekliyor").
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
    final ops = pending > 0 ? '$pending işlem gönderilmeyi bekliyor' : null;
    if (offline) {
      return ops == null ? 'Çevrimdışısınız' : 'Çevrimdışısınız · $ops';
    }
    return ops ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final visible = offline || pendingCount > 0;
    final tc = offline ? c.neutral : c.info;
    final text = message(offline: offline, pending: pendingCount);
    return AknAnimatedSize(
      curve: AknMotion.emphasizedCurve,
      alignment: Alignment.topCenter,
      child: !visible
          ? const SizedBox(width: double.infinity)
          : Semantics(
              liveRegion: true,
              button: onTap != null,
              label: text,
              excludeSemantics: true,
              child: Material(
                color: tc.bg,
                child: InkWell(
                  onTap: onTap,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: tc.line)),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          offline
                              ? Icons.cloud_off_rounded
                              : Icons.cloud_upload_rounded,
                          size: 18,
                          color: tc.fg,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            text,
                            style: t.label.copyWith(color: tc.fg),
                          ),
                        ),
                        if (onTap != null)
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: tc.fg,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// Outcome body (order sent, delivery confirmed, request failed): a success
/// check that draws itself (or a tone icon), title, message, optional
/// details and actions. Screen readers hear the title.
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

  /// E.g. a card of `FactRow`s (order numbers, amounts).
  final Widget? details;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final tc = c.tone(tone);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: tone == AknTone.ok && icon == null
                ? const SuccessCheck(size: 96, semanticLabel: null)
                : Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: tc.bg,
                      shape: BoxShape.circle,
                      border: Border.all(color: tc.line, width: 2),
                    ),
                    child: Icon(
                      icon ?? AknStatus.toneIcon(tone),
                      color: tc.fg,
                      size: 44,
                    ),
                  ),
          ),
          const SizedBox(height: 20),
          Semantics(
            header: true,
            liveRegion: true,
            child: Text(title, style: t.title, textAlign: TextAlign.center),
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              style: t.body.copyWith(color: c.dim),
              textAlign: TextAlign.center,
            ),
          ],
          if (details != null) ...[const SizedBox(height: 20), details!],
          if (primaryLabel != null && onPrimary != null) ...[
            const SizedBox(height: 24),
            AknButton(label: primaryLabel!, expand: true, onPressed: onPrimary),
          ],
          if (secondaryLabel != null && onSecondary != null) ...[
            const SizedBox(height: 4),
            AknButton.ghost(
              label: secondaryLabel!,
              expand: true,
              onPressed: onSecondary,
            ),
          ],
        ],
      ),
    );
  }
}

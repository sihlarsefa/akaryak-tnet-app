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

/// Empty list or screen (design v2 §6.24): a 96 px line drawing, a title
/// (17/22 600), one sentence (14/20 dim, at most two lines) and one button.
/// The copy invites the action: "Açık siparişiniz yok. Yeni sipariş için
/// Sipariş ver’e dokunun." Empty states are the one place text is centred.
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

  /// Deprecated: drawings are always dim with one orange detail.
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyIllustration(subject: illustration, size: compact ? 80 : 96),
            SizedBox(height: compact ? 10 : 14),
            Semantics(
              header: true,
              child: Text(
                title,
                style: t.headline,
                textAlign: TextAlign.center,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 340),
                child: Text(
                  message!,
                  style: t.bodySmall.copyWith(color: c.dim),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              SizedBox(height: compact ? 14 : 20),
              AknButton(label: actionLabel!, onPressed: onAction),
            ],
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 4),
              AknButton.ghost(label: secondaryLabel!, onPressed: onSecondary),
            ],
          ],
        ),
      ),
    );
  }
}

/// Load failure with a retry (§6.24, copy rule §10.2): the "route with a
/// gap" drawing, what failed, what to do and "Tekrar dene". [offline]
/// switches to the no-connection wording; the message is always Turkish and
/// never a raw payload — never "İstek başarısız" or "Bir hata oluştu".
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
    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: AknSpace.page,
          vertical: compact ? 16 : 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyIllustration(
              subject: offline
                  ? AknIllustration.offline
                  : AknIllustration.error,
              size: compact ? 80 : 96,
            ),
            SizedBox(height: compact ? 10 : 14),
            Semantics(
              header: true,
              child: Text(
                title ?? (offline ? offlineTitle : defaultTitle),
                style: t.headline,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Text(
                message ?? (offline ? offlineMessage : defaultMessage),
                style: t.bodySmall.copyWith(color: c.dim),
                textAlign: TextAlign.center,
              ),
            ),
            if (code != null)
              // "Destek kodu: 1a2b3c4d" (spec C.7): dokununca panoya kopyalanır.
              Semantics(
                button: true,
                label: 'Destek kodu $code, kopyalamak için dokunun',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: code));
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'Destek kodu: $code',
                            style: t.caption.copyWith(color: c.dim),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.copy_outlined, size: 16, color: c.dim),
                      ],
                    ),
                  ),
                ),
              ),
            if (onRetry != null) ...[
              SizedBox(height: code != null ? 4 : (compact ? 14 : 20)),
              AknButton.secondary(label: retryLabel, onPressed: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}

/// Centred brand spinner (32 px, logo orange) with an optional dim message
/// (full-screen waits).
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
            const ChevronSpinner(size: 32),
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

/// The offline line under the app bar (§6.24): one Beton line with
/// `cloud_off_outlined` 18 dim and "Çevrimdışı. Değişiklikler telefona
/// kaydediliyor (3)." (13/18 500 ink; driver mode makes it 15/20). Online
/// with queued operations it reads "3 işlem gönderilmeyi bekliyor".
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
                color: c.surfaceAlt,
                child: InkWell(
                  onTap: onTap,
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: c.line,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AknSpace.page,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          offline
                              ? Icons.cloud_off_outlined
                              : Icons.cloud_upload_outlined,
                          size: 18,
                          color: c.dim,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            text,
                            style: t.label.copyWith(color: c.ink),
                          ),
                        ),
                        if (onTap != null)
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: c.dim,
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

/// Outcome body after a submit (§6.24): a 72 px success check (ok) — or a
/// plain tone icon — then a title that echoes the verb ("Siparişiniz bayiye
/// gönderildi"), the detail, a primary ("Siparişi aç") and a ghost ("Ana
/// sayfaya dön"). Screen readers hear the title.
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
    final tc = c.tone(tone);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AknSpace.page, 32, AknSpace.page, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: tone == AknTone.ok && icon == null
                ? const SuccessCheck(size: 72, semanticLabel: null)
                : Icon(
                    icon ?? AknStatus.toneIcon(tone),
                    color: tone == AknTone.brand ? c.ink : tc.fg,
                    size: 56,
                  ),
          ),
          const SizedBox(height: 16),
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
            const SizedBox(height: 8),
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

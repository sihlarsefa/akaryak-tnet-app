import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/app_failure.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/external_activity.dart';
import '../../../core/utils/format.dart';
import '../copy.dart';

/// Destek kodu: iz kimliğinin ilk 8 karakteri (spec C.7).
String? supportCode(AppFailure f) {
  final t = f.traceId;
  if (t == null || t.isEmpty) return null;
  return t.length <= 8 ? t : t.substring(0, 8);
}

/// Kullanıcıya gösterilecek kısa hata metni (spec C.7).
String failureText(AppFailure f) => switch (f) {
  OfflineFailure() =>
    'İnternet bağlantısı yok. Bağlantınızı kontrol edip tekrar deneyin.',
  TimeoutFailure() => 'Sunucu zamanında yanıt vermedi. Lütfen tekrar deneyin.',
  RateLimitedFailure(:final retryAfter) =>
    retryAfter == null
        ? 'Çok fazla deneme. Biraz sonra tekrar deneyin.'
        : 'Çok fazla deneme. ${retryAfter.inSeconds} sn sonra tekrar deneyin.',
  ConflictFailure(:final isConcurrency) =>
    isConcurrency ? '${CmCopy.conflict}. Güncel hâli yüklendi.' : f.message,
  ServerFailure() =>
    supportCode(f) == null
        ? 'Beklenmeyen bir hata oluştu.'
        : 'Beklenmeyen bir hata oluştu. Destek kodu: ${supportCode(f)}',
  ValidationFailure(:final fieldErrors) =>
    fieldErrors.values.expand((e) => e).firstOrNull ?? f.message,
  _ => f.message,
};

/// İşlem hatası bildirimi. 403 için çekirdek zaten "Bu işlem için yetkiniz yok." gösterir.
void showFailureToast(BuildContext context, Object error) {
  final f = AppFailure.from(error);
  if (f is ForbiddenFailure) return;
  if (f is UnknownFailure && f.cancelled) return;
  AppToast.error(failureText(f), context: context);
}

/// İlk yükleme hatasının ekranı (çevrimdışı / yetki / bulunamadı / sunucu).
/// Alt eylem çubuğu içeriği: yüksekliğini çocuğundan alır (genişleyen [AknButton] içindeki `Align`
/// çubuğu ekran boyu büyütmesin).
Widget cmBar(Widget child) => Column(
  mainAxisSize: MainAxisSize.min,
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [child],
);

/// [AknSegmented] with AA-contrast labels: the core control draws unselected labels in `dim` on
/// `surfaceAlt` (4.34:1 in light mode); here they use `text` (selection still shows by thumb and
/// weight).
class CmSegmented<T> extends StatelessWidget {
  const CmSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
  });

  final List<FilterOption<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final control = AknSegmented<T>(
      segments: segments,
      value: value,
      onChanged: onChanged,
      margin: margin,
    );
    final c = context.akn;
    if (c.isDark) return control;
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        extensions: [
          for (final e in theme.extensions.values)
            if (e is AknColors) e.copyWith(dim: c.text) else e,
        ],
      ),
      child: control,
    );
  }
}

/// Kart başlığı + sağda rozet: sığmadığında (büyük yazı boyutu, uzun başlık) rozet alt satıra
/// iner; taşma olmaz.
class CmHeadRow extends StatelessWidget {
  const CmHeadRow({super.key, required this.title, required this.trailing});

  final Widget title;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    runSpacing: 4,
    children: [title, trailing],
  );
}

class CmFailureView extends StatelessWidget {
  const CmFailureView({
    super.key,
    required this.failure,
    this.onRetry,
    this.compact = false,
  });

  final AppFailure failure;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final f = failure;
    return switch (f) {
      OfflineFailure() => EmptyState(
        title: CmCopy.offlineEmpty,
        message: CmCopy.offlineEmptyMessage,
        illustration: AknIllustration.offline,
        actionLabel: onRetry == null ? null : CmCopy.retry,
        onAction: onRetry,
        compact: compact,
      ),
      ForbiddenFailure() => EmptyState(
        title: CmCopy.forbiddenTitle,
        message: CmCopy.forbiddenMessage,
        illustration: AknIllustration.error,
        compact: compact,
      ),
      NotFoundFailure() => EmptyState(
        title: CmCopy.notFound,
        message: f.message,
        illustration: AknIllustration.search,
        compact: compact,
      ),
      ServerFailure() => ErrorState(
        message:
            'Beklenmeyen bir hata oluştu. Lütfen biraz sonra tekrar deneyin.',
        traceId: supportCode(f),
        onRetry: onRetry,
        compact: compact,
      ),
      TimeoutFailure() => ErrorState(
        title: 'Sunucu zamanında yanıt vermedi',
        message: 'Bağlantınız yavaş olabilir. Lütfen tekrar deneyin.',
        onRetry: onRetry,
        compact: compact,
      ),
      _ => ErrorState(
        message: failureText(f),
        onRetry: onRetry,
        compact: compact,
      ),
    };
  }
}

/// "Son güncelleme 14:30" (çevrimdışıyken önbellekten gösterilen veri).
class CachedNote extends StatelessWidget {
  const CachedNote({super.key, required this.storedAt});

  final DateTime? storedAt;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final when = storedAt == null
        ? 'kayıtlı veri'
        : (Fmt.dayLabel(storedAt) == 'Bugün'
              ? Fmt.time(storedAt)
              : Fmt.dateTime(storedAt));
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          children: [
            Icon(Icons.history_rounded, size: 16, color: c.dim),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Son güncelleme $when · çevrimdışı gösteriliyor',
                style: t.caption.copyWith(color: c.dim),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sonsuz kaydırma alt bilgisi: yükleniyor / hata + tekrar dene.
class LoadMoreFooter extends StatelessWidget {
  const LoadMoreFooter({
    super.key,
    required this.loading,
    this.error,
    this.onRetry,
  });

  final bool loading;
  final AppFailure? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: ChevronSpinner(size: 22)),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: AknButton.ghost(
            label: CmCopy.retry,
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
          ),
        ),
      );
    }
    return const SizedBox(height: 24);
  }
}

/// Sayfa bölüm başlığı + içerik kartı.
class CmSection extends StatelessWidget {
  const CmSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.padding = AknSpace.cardPadding,
    this.accent,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final AknTone? accent;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: AknCard(
        accent: accent,
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(title, style: t.bodyStrong),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(subtitle!, style: t.caption),
                        ),
                    ],
                  ),
                ),
                // Kendi düğümü: başlığa karışmadan ayrıca odaklanır.
                if (trailing != null)
                  Semantics(container: true, child: trailing),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

/// Konumu harici harita uygulamasında açar (iOS Apple Haritalar, Android geo:, yedek Google Haritalar).
Future<bool> openInMaps(double lat, double lng, {String? label}) async {
  final q = '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
  final name = Uri.encodeComponent(label ?? 'Teslimat noktası');
  final native = defaultTargetPlatform == TargetPlatform.iOS
      ? Uri.parse('https://maps.apple.com/?ll=$q&q=$name')
      : Uri.parse('geo:$q?q=$q($name)');
  try {
    if (await launchExternal(native, mode: LaunchMode.externalApplication)) {
      return true;
    }
  } catch (_) {}
  try {
    return await launchExternal(
      Uri.parse('https://www.google.com/maps/search/?api=1&query=$q'),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}

/// Telefon araması (`tel:`).
Future<bool> callPhone(String phone) async {
  final digits = phone.replaceAll(RegExp(r'[^\d+]'), '');
  if (digits.isEmpty) return false;
  try {
    return await launchExternal(Uri(scheme: 'tel', path: digits));
  } catch (_) {
    return false;
  }
}

/// Metni panoya kopyalar ve bildirir.
Future<void> copyText(BuildContext context, String text, String toast) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) AppToast.success(toast, context: context);
}

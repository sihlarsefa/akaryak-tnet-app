import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/network/app_failure.dart';
import '../../../core/ui/ui.dart';

/// Hatanın Türkçe kısa metni (bildirim, satır içi bant). Spec C.7 hata tablosu: iş kuralı mesajı
/// sunucudan olduğu gibi; ham yanıt asla gösterilmez.
String failureText(AppFailure f) => switch (f) {
  OfflineFailure() => 'İnternet bağlantısı yok. Bağlantınızı kontrol edin.',
  TimeoutFailure() => 'Sunucu zamanında yanıt vermedi. Lütfen tekrar deneyin.',
  ServerFailure() =>
    'Beklenmeyen bir hata oluştu. Lütfen biraz sonra tekrar deneyin.',
  RateLimitedFailure(:final retryAfter) =>
    retryAfter == null
        ? 'Çok fazla deneme yapıldı. Lütfen biraz sonra tekrar deneyin.'
        : 'Çok fazla deneme. ${retryAfter.inSeconds} sn sonra tekrar deneyin.',
  ConflictFailure(:final conflictCode)
      when conflictCode == 'concurrency_conflict' =>
    'Bu kayıt sizden sonra güncellendi. Yenileyip tekrar deneyin.',
  ForbiddenFailure() => 'Bu işlem için yetkiniz yok.',
  NotFoundFailure() => 'Bu kayıt artık görüntülenemiyor.',
  _ => f.message,
};

/// Destek kodu: iz kimliğinin ilk 8 karakteri ([AppFailure.traceId]).
String? supportCodeOf(AppFailure f) {
  final t = f.traceId?.trim();
  if (t == null || t.isEmpty) return null;
  final clean = t.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
  final code = clean.length > 8 ? clean.substring(0, 8) : clean;
  return code.isEmpty ? null : code;
}

/// Yükleme hatasının ekranı (spec C.5 liste tarifi): çevrimdışı, yetki yok, kayıt yok, sunucu hatası
/// (destek koduyla) ya da sunucunun Türkçe mesajı. [onRetry] verilirse "Tekrar dene".
class A5FailureView extends StatelessWidget {
  const A5FailureView({
    super.key,
    required this.failure,
    this.onRetry,
    this.compact = false,
    this.notFoundTitle = 'Bu kayıt artık görüntülenemiyor',
    this.notFoundMessage =
        'Kayıt kaldırılmış ya da erişiminiz değişmiş olabilir.',
  });

  final AppFailure failure;
  final VoidCallback? onRetry;
  final bool compact;
  final String notFoundTitle;
  final String notFoundMessage;

  @override
  Widget build(BuildContext context) {
    final f = failure;
    switch (f) {
      case OfflineFailure():
        return ErrorState(
          offline: true,
          compact: compact,
          message: 'Çevrimdışısınız; bu ekran için kayıtlı veri yok.',
          onRetry: onRetry,
        );
      case ForbiddenFailure():
        return EmptyState(
          compact: compact,
          title: 'Bu bilgiyi görme yetkiniz yok',
          message:
              'Yetkinizin olduğunu düşünüyorsanız bayi yöneticinize başvurun.',
          illustration: AknIllustration.locked,
        );
      case NotFoundFailure():
        return EmptyState(
          compact: compact,
          title: notFoundTitle,
          message: notFoundMessage,
          illustration: AknIllustration.search,
        );
      case TimeoutFailure():
        return ErrorState(
          compact: compact,
          title: 'Sunucu zamanında yanıt vermedi',
          message: 'Bağlantı yavaş olabilir. Lütfen tekrar deneyin.',
          onRetry: onRetry,
        );
      case ServerFailure():
        final code = supportCodeOf(f);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ErrorState(
              compact: compact,
              title: 'Beklenmeyen bir hata oluştu',
              message:
                  'Bilgiler yüklenemedi. Lütfen biraz sonra tekrar deneyin.',
              onRetry: onRetry,
            ),
            if (code != null) SupportCode(code: code),
          ],
        );
      default:
        return ErrorState(
          compact: compact,
          title: 'Bilgiler yüklenemedi',
          message: failureText(f),
          onRetry: onRetry,
        );
    }
  }
}

/// "Destek kodu: ABCD1234" — dokununca panoya kopyalanır (spec C.7).
class SupportCode extends StatelessWidget {
  const SupportCode({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Semantics(
      button: true,
      label: 'Destek kodu $code, kopyalamak için dokunun',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AknRadius.pillAll,
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: code));
          if (context.mounted) {
            AppToast.info('Destek kodu kopyalandı.', context: context);
          }
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AknSpace.minTap),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.copy_rounded, size: 16, color: c.dim),
                const SizedBox(width: 6),
                Text('Destek kodu: $code', style: t.caption),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bir işlemin hatasını bildirimle gösterir (iş kuralı mesajı olduğu gibi).
void showFailureToast(BuildContext context, AppFailure f) {
  if (f is UnknownFailure && f.cancelled) return;
  // 403'ü ağ katmanı zaten bildirir ("Bu işlem için yetkiniz yok.").
  if (f is ForbiddenFailure) return;
  final code = f is ServerFailure ? supportCodeOf(f) : null;
  AppToast.error(
    code == null ? failureText(f) : '${failureText(f)} Destek kodu: $code',
    context: context,
  );
}

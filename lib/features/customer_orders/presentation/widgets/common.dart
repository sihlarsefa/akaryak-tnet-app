import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/app_failure.dart';
import '../../../../core/offline/connectivity.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../copy.dart';

/// "Son güncelleme 14:20" (önbellekten / çevrimdışı gösterilen veri; spec C.4a).
class LastUpdatedNote extends ConsumerWidget {
  const LastUpdatedNote({
    super.key,
    required this.updatedAt,
    this.fromCache = false,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 0),
  });

  final DateTime? updatedAt;
  final bool fromCache;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider);
    final at = updatedAt;
    if (at == null || (online && !fromCache)) return const SizedBox.shrink();
    final c = context.akn;
    final t = context.aknText;
    final when = Fmt.relative(at);
    return Padding(
      padding: padding,
      child: Semantics(
        label: '${OrdersCopy.lastUpdate}: $when',
        excludeSemantics: true,
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, size: 16, color: c.dim),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${OrdersCopy.lastUpdate} ${Fmt.time(at)}, ${TurkishText.lower(when)}',
                style: t.caption.copyWith(color: c.dim),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Büyük yazı (yaklaşık %130 ve üstü): yan yana duran başlık + rozet gibi öğeler alt alta dizilir.
bool isLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(14) > 18;

/// Rozet (ör. geri sayım) bulunduğu alana sığmazsa sığacak kadar küçülür; kesilmez, taşmaz.
/// Genişliği sınırlı bir ebeveyn ister (Column, Wrap); Row içinde esnek olmayan çocukta etkisizdir.
class FitBadge extends StatelessWidget {
  const FitBadge({
    super.key,
    required this.child,
    this.alignment = AlignmentDirectional.centerStart,
  });

  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) =>
      FittedBox(fit: BoxFit.scaleDown, alignment: alignment, child: child);
}

/// [AknSegmented], AA kontrastlı etiketlerle: çekirdek denetim açık temada seçili olmayan
/// etiketleri `surfaceAlt` üzerinde `dim` ile çizer (4,34:1 < 4,5:1); burada `text` kullanılır
/// (seçim kaydırıcı ve kalınlıkla belli olur). Çekirdek düzeltilince doğrudan [AknSegmented].
class A2Segmented<T> extends StatelessWidget {
  const A2Segmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  final List<FilterOption<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final control = AknSegmented<T>(
      segments: segments,
      value: value,
      onChanged: onChanged,
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

/// [AnimatedSize], hareket azaltıldığında da güvenli: sıfır süreli AnimatedSize boyut değişince
/// yerleşim sırasında kendini yeniden kirletir ("RenderAnimatedSize was mutated in its own
/// performLayout"); bu yüzden süre en az 1 ms tutulur (gözle görülmez).
class SafeAnimatedSize extends StatelessWidget {
  const SafeAnimatedSize({
    super.key,
    required this.child,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final d = AknMotion.of(context, AknMotion.base);
    return AnimatedSize(
      duration: d > Duration.zero ? d : const Duration(milliseconds: 1),
      curve: AknMotion.standard,
      alignment: alignment,
      child: child,
    );
  }
}

/// Başlık + sağda eylem (ör. "Şablondan başla", "Düzenle"): büyük yazıda eylem başlığın altına iner.
class TitleActionRow extends StatelessWidget {
  const TitleActionRow({super.key, required this.title, this.action});

  final Widget title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final a = action;
    if (a == null) return title;
    if (isLargeText(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          const SizedBox(height: 4),
          Align(alignment: AlignmentDirectional.centerStart, child: a),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: title),
        const SizedBox(width: 8),
        a,
      ],
    );
  }
}

/// Yükleme hatası (C.7 metinleri; sunucu hatasında destek kodu dokununca kopyalanır).
class FailureView extends StatelessWidget {
  const FailureView({
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
    if (f is ForbiddenFailure) {
      return EmptyState(
        title: OrdersCopy.forbidden,
        message: OrdersCopy.forbiddenMessage,
        illustration: AknIllustration.locked,
        compact: compact,
      );
    }
    if (f is NotFoundFailure) {
      return EmptyState(
        title: OrdersCopy.notFound,
        message: OrdersCopy.notFoundMessage,
        illustration: AknIllustration.search,
        compact: compact,
      );
    }
    final code = OrdersCopy.supportCode(f);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ErrorState(
          title: OrdersCopy.failureTitle(f),
          message: OrdersCopy.failureMessage(f),
          offline: f is OfflineFailure,
          onRetry: onRetry,
          compact: compact,
        ),
        if (code != null) SupportCode(code: code),
      ],
    );
  }
}

/// "Destek kodu: abcd1234" (dokununca kopyalanır).
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
        borderRadius: AknRadius.card,
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: code));
          if (context.mounted) {
            AppToast.success('Destek kodu kopyalandı.', context: context);
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
                Text(
                  'Destek kodu: $code',
                  style: t.caption.copyWith(color: c.dim),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bölüm kartı: başlık, isteğe bağlı simge ve "Tümü" bağlantısı.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    this.margin = const EdgeInsets.fromLTRB(16, 12, 16, 0),
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 16),
    this.accent,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final AknTone? accent;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Padding(
      padding: margin,
      child: AknCard(
        padding: padding,
        accent: accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TitleActionRow(
              title: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20, color: c.dim),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(title, style: t.headline),
                    ),
                  ),
                ],
              ),
              action: trailing,
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

/// Küçük bilgi çipi (renk tek başına anlam taşımaz: ikon + metin).
class InfoPill extends StatelessWidget {
  const InfoPill({
    super.key,
    required this.label,
    this.icon,
    this.tone = AknTone.neutral,
  });

  final String label;
  final IconData? icon;
  final AknTone tone;

  @override
  Widget build(BuildContext context) => StatusChip(
    label: label,
    tone: tone,
    icon: icon,
    size: StatusChipSize.small,
  );
}

/// Metin uzunsa ve yazı büyükse alt alta dizilen düğme grubu (200 % ölçek).
///
/// Satır, en küçük boyutlu bir `Column` içine konur: böylece sınırlı yükseklikteki yerlerde
/// (ör. `ActionBar`) genişleyen düğmelerin `Align`'ı tüm yüksekliği kaplamaz.
class ButtonRow extends StatelessWidget {
  const ButtonRow({super.key, required this.children, this.spacing = 12});

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final stacked =
        MediaQuery.textScalerOf(context).scale(15) > 19.5 ||
        children.length > 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: stacked
          ? [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: spacing / 2),
                children[i],
              ],
            ]
          : [
              Row(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) SizedBox(width: spacing),
                    Expanded(child: children[i]),
                  ],
                ],
              ),
            ],
    );
  }
}

/// İçerik genişliğini büyük ekranlarda sınırlar (en çok [maxWidth]; dar ekranda tam genişlik).
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 640});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}

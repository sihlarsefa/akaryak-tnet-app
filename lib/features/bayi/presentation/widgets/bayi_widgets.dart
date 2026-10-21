import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/env/app_env.dart';
import '../../../../core/network/app_failure.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/external_activity.dart';
import '../../../../core/utils/format.dart';
import '../../copy.dart';

/// Ekran düzeyinde hata / boş durum: çevrimdışı, yetki yok, kayıt yok, sunucu hatası.
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
    return switch (f) {
      OfflineFailure() => ErrorState(
        offline: true,
        compact: compact,
        title: BayiCopy.offlineTitle,
        message: BayiCopy.offlineNoData,
        onRetry: onRetry,
        retryLabel: BayiCopy.retry,
      ),
      ForbiddenFailure() => EmptyState(
        compact: compact,
        title: BayiCopy.forbiddenTitle,
        message: BayiCopy.forbiddenMessage,
        illustration: AknIllustration.locked,
      ),
      NotFoundFailure() => EmptyState(
        compact: compact,
        title: BayiCopy.notFoundTitle,
        message: BayiCopy.notFoundMessage,
        illustration: AknIllustration.search,
      ),
      ServerFailure() => ErrorState(
        compact: compact,
        message: f.message,
        traceId: _short(f.traceId),
        onRetry: onRetry,
        retryLabel: BayiCopy.retry,
      ),
      _ => ErrorState(
        compact: compact,
        message: f.message,
        onRetry: onRetry,
        retryLabel: BayiCopy.retry,
      ),
    };
  }

  static String? _short(String? traceId) {
    final t = traceId?.trim();
    if (t == null || t.isEmpty) return null;
    return t.length <= 8 ? t : t.substring(0, 8);
  }
}

/// İşlem hatasını kullanıcıya gösterir (spec C.7). 403 genel bildirimle zaten gösterilir.
void showActionFailure(BuildContext context, Object error) {
  final f = AppFailure.from(error);
  switch (f) {
    case ForbiddenFailure():
      return;
    case UnknownFailure(cancelled: true):
      return;
    case ConflictFailure(isConcurrency: true):
      AppToast.warning(BayiCopy.conflict, context: context);
    case ServerFailure():
      final t = FailureView._short(f.traceId);
      AppToast.error(
        t == null ? f.message : '${f.message} Destek kodu: $t',
        context: context,
      );
    default:
      AppToast.error(f.message, context: context);
  }
}

/// "Son güncelleme 14:30" (önbellekten gösterilen veri ya da tazeleme hatası).
class UpdatedCaption extends StatelessWidget {
  const UpdatedCaption({
    super.key,
    required this.updatedAt,
    this.fromCache = false,
    this.error,
  });

  final DateTime? updatedAt;
  final bool fromCache;
  final AppFailure? error;

  @override
  Widget build(BuildContext context) {
    final at = updatedAt;
    if (at == null || (!fromCache && error == null)) {
      return const SizedBox.shrink();
    }
    final t = context.aknText;
    final c = context.akn;
    final offline = error is OfflineFailure || fromCache;
    final text = offline
        ? 'Son güncelleme ${Fmt.relative(at)}'
        : 'Yenilenemedi · son güncelleme ${Fmt.relative(at)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Icon(
            offline ? Icons.history_rounded : Icons.sync_problem_rounded,
            size: 16,
            color: c.dim,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: t.caption.copyWith(color: c.dim)),
          ),
        ],
      ),
    );
  }
}

/// Kısa etiket (sunucunun ton anahtarıyla): "Çek · 90 gün", "Finans onaylandı".
class ToneTag extends StatelessWidget {
  const ToneTag({
    super.key,
    required this.label,
    this.tone = AknTone.neutral,
    this.icon,
  });

  final String label;
  final AknTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => FitStart(
    child: StatusChip(
      label: label,
      tone: tone,
      icon: icon ?? AknStatus.toneIcon(tone),
      size: StatusChipSize.small,
    ),
  );
}

/// Wrap / Column içindeki çip ya da rozet: genişliğe sığmazsa (büyük yazı ölçeği) taşmak yerine
/// küçülür. Satır (Row) içinde sınırsız genişlikte etkisizdir; orada [FitEnd] kullanılır.
class FitStart extends StatelessWidget {
  const FitStart({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: AlignmentDirectional.centerStart,
    child: child,
  );
}

/// Satır sonu öğesi (durum çipi, geri sayım): ekran genişliğinin en fazla [widthFactor] kadarını
/// kaplar; büyük yazı ölçeğinde taşmak yerine küçülür.
class FitEnd extends StatelessWidget {
  const FitEnd({super.key, required this.child, this.widthFactor = 0.42});

  final Widget child;
  final double widthFactor;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: MediaQuery.sizeOf(context).width * widthFactor,
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerEnd,
      child: child,
    ),
  );
}

/// Bölüm başlığı ([SectionHeader]); büyük yazı ölçeğinde eylem düğmesi başlığın altına iner (çekirdek
/// başlıkta eylem düğmesi esnemez ve 2.0 ölçekte taşar).
class BayiSectionHeader extends StatelessWidget {
  const BayiSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.count,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(16, 24, 8, 8),
  });

  final String title;
  final String? subtitle;
  final int? count;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final hasAction = actionLabel != null && onAction != null;
    if (!hasAction || !isLargeText(context)) {
      return SectionHeader(
        title: title,
        subtitle: subtitle,
        count: count,
        actionLabel: actionLabel,
        onAction: onAction,
        padding: padding,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SectionHeader(
          title: title,
          subtitle: subtitle,
          count: count,
          padding: padding,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ),
        ),
      ],
    );
  }
}

/// Büyük yazı ölçeği (yaklaşık 1,4× ve üstü): yan yana öğeler alt alta dizilir.
bool isLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(16) > 22;

/// Bölüm seçici (2–3 seçenek), Material [SegmentedButton]: 48 dp dokunma hedefi, ekran okuyucuda
/// etkinleştirilebilir seçili düğme ve AA kontrast. (Çekirdek [AknSegmented]: seçili olmayan etiket
/// 4,34:1, 42 dp yükseklik ve ekran okuyucuda dokunma eylemi yok.)
class BayiSegmented<T> extends StatelessWidget {
  const BayiSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  final List<FilterOption<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: SegmentedButton<T>(
      segments: [
        for (final s in segments)
          ButtonSegment<T>(
            value: s.value,
            label: Text(
              s.count == null ? s.label : '${s.label} (${s.count})',
              textAlign: TextAlign.center,
            ),
          ),
      ],
      selected: {value},
      showSelectedIcon: false,
      expandedInsets: EdgeInsets.zero,
      onSelectionChanged: (v) {
        if (v.isNotEmpty) onChanged(v.first);
      },
    ),
  );
}

/// [UsageBar]; etiket ve değer etiketi ("6.000 L / 16.000 L planlı") tek satıra sığmazsa (dar ekran,
/// büyük yazı) değer etiketi çubuğun altına iner (çekirdek başlık satırında değer etiketi esnemez).
class BayiUsageBar extends StatelessWidget {
  const BayiUsageBar({
    super.key,
    required this.value,
    this.label,
    this.valueLabel,
    this.tone,
    this.height = 8,
  });

  final double value;
  final String? label;
  final String? valueLabel;
  final AknTone? tone;
  final double height;

  @override
  Widget build(BuildContext context) {
    final v = valueLabel;
    if (v == null) {
      return UsageBar(value: value, label: label, tone: tone, height: height);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final t = context.aknText;
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        double width(String text, TextStyle style) {
          final p = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: direction,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final w = p.width;
          p.dispose();
          return w;
        }

        final fits =
            !constraints.hasBoundedWidth ||
            width(label ?? '', t.caption) + width(v, t.captionStrong) + 16 <=
                constraints.maxWidth;
        if (fits) {
          return UsageBar(
            value: value,
            label: label,
            valueLabel: v,
            tone: tone,
            height: height,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            UsageBar(value: value, label: label, tone: tone, height: height),
            const SizedBox(height: 4),
            Text(v, style: t.captionStrong),
          ],
        );
      },
    );
  }
}

/// Süzgeç düğmesi: rozet açık süzgeç sayısını gösterir; ekran okuyucu "N süzgeç açık" der (çekirdek
/// [AknIconButton] rozet etiketi "N yeni" der; bu sayı bildirim değildir).
class FilterButton extends StatelessWidget {
  const FilterButton({
    super.key,
    required this.label,
    required this.count,
    required this.onPressed,
  });

  final String label;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: count == 0 ? label : '$label, $count süzgeç açık',
    excludeSemantics: true,
    onTap: onPressed,
    child: AknIconButton(
      icon: Icons.tune_rounded,
      semanticLabel: label,
      badgeCount: count,
      onPressed: onPressed,
    ),
  );
}

/// "uygulamada" rozeti: şoförün açık uygulama oturumu var.
class InAppBadge extends StatelessWidget {
  const InAppBadge({super.key});

  @override
  Widget build(BuildContext context) => const StatusChip(
    label: 'uygulamada',
    tone: AknTone.ok,
    icon: Icons.phone_iphone_rounded,
    size: StatusChipSize.small,
  );
}

/// Bölüm kartı yüklenemedi ("Bu bölüm yüklenemedi"; yetkisiz bölümle karışmasın).
class SectionFailedCard extends StatelessWidget {
  const SectionFailedCard({super.key, required this.title, this.onRetry});

  final String title;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
    child: AknBanner(
      tone: AknTone.warn,
      icon: Icons.cloud_off_rounded,
      title: '$title · ${BayiCopy.sectionFailed}',
      message: BayiCopy.sectionFailedMessage,
      actionLabel: onRetry == null ? null : BayiCopy.retry,
      onAction: onRetry,
    ),
  );
}

/// Liste sonu: yükleniyor / devamı yüklenemedi.
class LoadMoreFooter extends StatelessWidget {
  const LoadMoreFooter({
    super.key,
    required this.loading,
    this.error,
    required this.onRetry,
  });

  final bool loading;
  final AppFailure? error;
  final VoidCallback onRetry;

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
            label: '${BayiCopy.loadMoreFailed} ${BayiCopy.retry}',
            icon: Icons.refresh_rounded,
            onPressed: onRetry,
          ),
        ),
      );
    }
    return const SizedBox(height: 24);
  }
}

/// Kök hedefi açar: alt menüdeyse sekmeye geçer (`go`), değilse tam ekran açar (`push`). Ayrıntı rotaları
/// her zaman `push` ile açılır.
void openDestination(BuildContext context, String location) {
  final router = GoRouter.of(context);
  final path = Uri.parse(location).path;
  final topLevel = router.configuration.routes.whereType<GoRoute>().any(
    (r) => r.path == path,
  );
  if (topLevel) {
    router.push(location);
  } else {
    router.go(location);
  }
}

/// Telefonla arama (`tel:`); başarısızsa numarayı panoya kopyalar.
Future<void> callPhone(BuildContext context, String phone) async {
  final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (digits.isEmpty) return;
  final uri = Uri(scheme: 'tel', path: digits);
  var ok = false;
  try {
    ok = await launchExternal(uri);
  } catch (_) {
    ok = false;
  }
  if (!ok && context.mounted) {
    await Clipboard.setData(ClipboardData(text: digits));
    if (context.mounted) {
      AppToast.info('Numara kopyalandı: ${Fmt.phone(phone)}', context: context);
    }
  }
}

/// Konumu harita uygulamasında açar.
Future<void> openMap(
  BuildContext context, {
  required double latitude,
  required double longitude,
  String? label,
}) async {
  final q = '$latitude,$longitude';
  final uri = Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': q,
  });
  try {
    final ok = await launchExternal(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      AppToast.error('Harita açılamadı.', context: context);
    }
  } catch (_) {
    if (context.mounted) AppToast.error('Harita açılamadı.', context: context);
  }
}

/// Web portalında sayfa açar (kurulum uyarıları): `PORTAL_BASE_URL + portalPath`.
Future<void> openPortal(
  BuildContext context,
  WidgetRef ref,
  String portalPath,
) async {
  final base = ref.read(appEnvProvider).portalBaseUrl;
  final path = portalPath.startsWith('/')
      ? portalPath.substring(1)
      : portalPath;
  final uri = Uri.tryParse('$base$path');
  if (uri == null) return;
  try {
    final ok = await launchExternal(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      AppToast.error('Portal açılamadı.', context: context);
    }
  } catch (_) {
    if (context.mounted) AppToast.error('Portal açılamadı.', context: context);
  }
}

/// Bölüm kartı: başlık satırı + içerik (ana sayfa ve ayrıntı ekranları).
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 16, 4),
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
    this.accent,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final AknTone? accent;

  @override
  Widget build(BuildContext context) =>
      AknCard(margin: margin, padding: padding, accent: accent, child: child);
}

/// Sayı + etiket satırı (ana sayfa küçük göstergeleri), dokununca hedefe gider.
class CountLine extends StatelessWidget {
  const CountLine({
    super.key,
    required this.label,
    required this.count,
    this.icon,
    this.tone,
    this.onTap,
    this.caption,
  });

  final String label;
  final int count;
  final IconData? icon;
  final AknTone? tone;
  final VoidCallback? onTap;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    final tc = tone == null ? null : c.tone(tone!);
    return AknListTile(
      dense: true,
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6),
      leadingIcon: icon,
      leadingTone: tone,
      title: label,
      subtitle: caption,
      semanticLabel: '$label: $count${caption == null ? '' : ', $caption'}',
      onTap: onTap,
      trailing: Text(
        Fmt.integer(count),
        style: t.amount.copyWith(
          fontSize: 16,
          color: count > 0 ? (tc?.fg ?? c.ink) : c.dim,
          fontWeight: FontWeight.w700,
        ),
      ),
      showChevron: onTap != null,
    );
  }
}

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
import '../../../../core/utils/tr_time.dart';
import '../../../../core/utils/turkish_text.dart';
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

/// "Son güncelleme 14:30" (önbellekten gösterilen veri ya da tazeleme hatası): tasarım v3'te sayfa
/// kenarında küçük bir Beton hap — saat ya da bulut simgesi ve soluk cümle; belirince yumuşakça
/// süzülür.
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
        : 'Yenilenemedi, son güncelleme ${Fmt.relative(at)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: FadeUp(
          offset: 6,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: AknRadius.pillAll,
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(10, 5, 12, 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    offline
                        ? PhosphorIconsRegular.clockCounterClockwise
                        : PhosphorIconsRegular.cloudWarning,
                    size: 15,
                    color: c.dim,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(text, style: t.caption.copyWith(color: c.dim)),
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

/// Büyük yazı ölçeği (yaklaşık 1,4× ve üstü): yan yana öğeler alt alta dizilir.
bool isLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(16) > 22;

/// [UsageBar]; etiket ve değer etiketi ("6.000 L / 16.000 L planlı") tek satıra sığmazsa (dar ekran,
/// büyük yazı) değer etiketi çubuğun altına iner (çekirdek başlık satırında değer etiketi esnemez).
///
/// Tasarım v3: çubuk ilk görünüşte sıfırdan dolarak büyür (çekirdek [UsageBar], vurgulu eğri), değer
/// değişince yeni değere kayar. Rengi baştan son değere göre seçilir (dolarken renk değiştirmez);
/// hareket azaltmada son kare.
class BayiUsageBar extends StatelessWidget {
  const BayiUsageBar({
    super.key,
    required this.value,
    this.label,
    this.valueLabel,
    this.tone,
    this.height = 8,
    this.warnAt = 0.8,
    this.dangerAt = 1.0,
  });

  final double value;
  final String? label;
  final String? valueLabel;
  final AknTone? tone;
  final double height;

  /// Eşikler ([UsageBar] ile aynı): üstünde uyarı, sonra tehlike rengi.
  final double warnAt;
  final double dangerAt;

  @override
  Widget build(BuildContext context) {
    final v = valueLabel;
    final end = value.isNaN ? 0.0 : value;
    // Ton son değerden: dolarken eşik geçilse de renk sabit kalır.
    final fixedTone =
        tone ??
        (end >= dangerAt
            ? AknTone.danger
            : end >= warnAt
            ? AknTone.warn
            : null);
    // Çekirdek çubuk kendisi dolarak gelir ve yeni değere kayar; burada ikinci bir ara değer
    // (tween) yok — iç içe iki tween çubuğu değerinin çok gerisinde bırakır.
    Widget bar(String? valueLabel) => UsageBar(
      value: end,
      label: label,
      valueLabel: valueLabel,
      tone: fixedTone,
      height: height,
      warnAt: warnAt,
      dangerAt: dangerAt,
    );
    if (v == null) return bar(null);
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
        if (fits) return bar(v);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            bar(null),
            const SizedBox(height: 4),
            Text(
              v,
              style: t.captionStrong.copyWith(
                color: context.akn.ink,
                fontFeatures: AknNumerals.tabular,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// "uygulamada" rozeti: şoförün açık uygulama oturumu var.
class InAppBadge extends StatelessWidget {
  const InAppBadge({super.key});

  @override
  Widget build(BuildContext context) => const AknLamp(
    label: 'uygulamada',
    tone: AknTone.ok,
    size: AknLampSize.small,
  );
}

/// Bölüm kartı yüklenemedi ("Bu bölüm yüklenemedi"; yetkisiz bölümle karışmasın).
class SectionFailedCard extends StatelessWidget {
  const SectionFailedCard({super.key, required this.title, this.onRetry});

  final String title;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
    child: AknBanner(
      tone: AknTone.warn,
      icon: PhosphorIconsRegular.cloudSlash,
      title: '$title: ${TurkishText.lower(BayiCopy.sectionFailed)}',
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
            icon: PhosphorIconsRegular.arrowClockwise,
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

/// Kart içindeki defter satırının iç boşluğu (tasarım v3 liste kartı): 16 yan, 14 dikey.
const EdgeInsets kCardRowPadding = EdgeInsets.fromLTRB(16, 14, 16, 14);

/// Tasarım v3 kartı (§3 derinlik, §4 "list cards"): sayfa zemininde süzülen beyaz yüzey (20 köşe),
/// yumuşak iki katlı kart gölgesi; koyu temada 1 px ince çizgi. İçerik köşelere kırpılır ve kartta
/// olduğunu bilir ([AknCardScope]: defter satırları düz kalır, okumalar kuyu olur). [pressable] kart
/// dokununca 0,97'ye iner, gölgesi sayfaya oturur ve bırakınca yaylanarak döner (§5 "Press");
/// dokunuşu kaydırma devralırsa kart hemen bırakılır (liste kayarken kart küçük kalmaz). Kendi basılı
/// hâli olan satırı ([AknListTile]) saran kart küçülmez (satır içeride küçülür; çift ölçek yok).
/// Hareket azaltmada ölçek değişmez.
class BayiCard extends StatefulWidget {
  const BayiCard({
    super.key,
    required this.child,
    this.margin = EdgeInsets.zero,
    this.padding = EdgeInsets.zero,
    this.radius = AknRadius.card,
    this.pressable = true,
    this.color,
    this.shadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final BorderRadius radius;
  final bool pressable;

  /// Yüzey (varsayılan `surface`, beyaz).
  final Color? color;

  /// Kart gölgesi (sayfa içi gruplar); sayfa (sheet) içinde düz kutu için false.
  final bool shadow;

  @override
  State<BayiCard> createState() => _BayiCardState();
}

class _BayiCardState extends State<BayiCard> {
  bool _down = false;
  ValueNotifier<bool>? _scrolling;

  void _press(bool down) {
    if (!widget.pressable || down == _down) return;
    if (down) {
      // Dokunuşu kaydırma devralınca kart bırakılır.
      final n = context
          .findAncestorStateOfType<ScrollableState>()
          ?.position
          .isScrollingNotifier;
      if (n != _scrolling) {
        _scrolling?.removeListener(_onScroll);
        _scrolling = n?..addListener(_onScroll);
      }
    } else {
      _scrolling?.removeListener(_onScroll);
      _scrolling = null;
    }
    setState(() => _down = down);
  }

  void _onScroll() {
    if ((_scrolling?.value ?? false) && mounted) _press(false);
  }

  @override
  void dispose() {
    _scrolling?.removeListener(_onScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final pressed = _down && widget.pressable;
    final reduced = AknMotion.reduced(context);
    final duration = pressed ? AknMotion.press : AknMotion.pressOut;
    Widget card = AnimatedContainer(
      duration: AknMotion.of(context, duration),
      curve: AknMotion.standard,
      decoration: BoxDecoration(
        color: widget.color ?? c.surface,
        borderRadius: widget.radius,
        boxShadow: !widget.shadow
            ? null
            : pressed
            ? AknShadows.pressed(c)
            : AknShadows.card(c),
      ),
      // Koyu temada kartı zeminden ayıran ince çizgi, içeriğin üstünde.
      foregroundDecoration: c.isDark
          ? BoxDecoration(
              borderRadius: widget.radius,
              border: Border.all(color: c.line),
            )
          : null,
      // İçerik kartta olduğunu bilir: defter satırları düz kalır, okumalar kuyu olur.
      child: AknCardScope(
        child: ClipRRect(
          borderRadius: widget.radius,
          child: Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    );
    if (widget.pressable) {
      card = Listener(
        onPointerDown: (_) => _press(true),
        onPointerUp: (_) => _press(false),
        onPointerCancel: (_) => _press(false),
        child: AnimatedScale(
          scale: pressed && !reduced ? AknMotion.pressScale : 1,
          duration: duration,
          curve: pressed ? AknMotion.standard : AknMotion.spring,
          child: card,
        ),
      );
    }
    return Padding(padding: widget.margin, child: card);
  }
}

/// Başlıklı olgu grubu (tasarım v4 "Sade" P6): bölüm başlığı ([SectionHeader]; sayı, alt yazı ve
/// "Tümü" bağlantısı) kartın üstünde, içerik tek bir kartta — 20 köşe, yalnızca ince çizgi (koyu
/// temada 1 px çizgi). Kartın içinde kart yok.
class GroupCard extends StatelessWidget {
  const GroupCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.count,
    this.actionLabel,
    this.onAction,
    this.margin = const EdgeInsets.fromLTRB(AknSpace.page, 4, AknSpace.page, 0),
    this.padding = const EdgeInsets.fromLTRB(18, 4, 18, 14),
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final int? count;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry margin;

  /// İçeriğin kart içindeki boşluğu (defter satırları kendi kenarını verirse sıfır).
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final head = title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (head != null)
          SectionHeader(
            title: head,
            subtitle: subtitle,
            count: count,
            actionLabel: actionLabel,
            onAction: onAction,
          ),
        Padding(
          padding: margin,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: AknRadius.card,
              border: c.isDark ? Border.all(color: c.line) : null,
              boxShadow: c.isDark ? null : [AknShadows.hairline(c)],
            ),
            child: ClipRRect(
              borderRadius: AknRadius.card,
              child: AknCardScope(
                child: Padding(
                  padding: head == null
                      ? padding
                      : padding.resolve(TextDirection.ltr).copyWith(top: 10),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Satır içi kısa not: 16 px simge ve `bodySmall` metin ("Çek, 30 gün vade", "Son alımlar: …"). Simge
/// durum taşıyorsa ([tone] uyarı / tehlike / tamam) tonun renginde, metin mürekkep; yoksa ikisi de
/// soluk.
class RowNote extends StatelessWidget {
  const RowNote({
    super.key,
    required this.text,
    this.icon,
    this.tone,
    this.maxLines,
  });

  final String text;
  final IconData? icon;
  final AknTone? tone;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final tn = tone;
    final status = tn != null && tn != AknTone.neutral && tn != AknTone.info;
    final style = t.bodySmall.copyWith(color: status ? c.ink : c.dim);
    final scaler = MediaQuery.textScalerOf(context);
    final line = scaler.scale(14) * 20 / 14;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          SizedBox(
            height: line,
            child: Icon(
              icon,
              size: scaler.scale(16).clamp(16.0, 24.0),
              color: status ? c.tone(tn).fg : c.dim,
            ),
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            text,
            style: style,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Gün başlığı (geçmiş listelerinde "Bugün", "Dün", "18 Ekim"; tasarım v3): solda küçük turuncu
/// işaret ve 15/20 700 mürekkep başlık, sağda tablo rakamlı soluk özet; 20 px kenar.
class DayHeader extends StatelessWidget {
  const DayHeader(this.text, {super.key, this.trailing});

  final String text;

  /// Sağda kısa özet ("2 sevkiyat, 18.000 L").
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final style = t.bodyStrong.copyWith(
      height: 20 / 15,
      fontWeight: FontWeight.w700,
      color: c.ink,
    );
    final line = MediaQuery.textScalerOf(context).scale(15) * 20 / 15;
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 2,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: line,
                  child: Center(
                    child: Container(
                      width: 4,
                      height: 14,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [c.brandFillStart, c.brand],
                        ),
                        borderRadius: AknRadius.pillAll,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(child: Text(text, style: style)),
              ],
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: t.caption.copyWith(
                  color: c.dim,
                  fontWeight: FontWeight.w600,
                  fontFeatures: AknNumerals.tabular,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Liste sonu cümlesi (§7.7): öğelerin nereye gittiğini söyler ("Teslim edilen siparişler …").
/// Tasarım v3: bilgi simgesiyle soluk küçük metin, listenin sonunda yumuşakça belirir.
class ListFooterNote extends StatelessWidget {
  const ListFooterNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final line = MediaQuery.textScalerOf(context).scale(14) * 20 / 14;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: FadeUp(
        offset: 8,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: line,
              child: Icon(PhosphorIconsRegular.info, size: 16, color: c.dim),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: t.bodySmall.copyWith(color: c.dim)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Beton kuyu içinde kısa bilgi (§4.5): 44 px'lik tek satır uyarı ("2 sipariş finans onayında; …").
/// Sayfa kenarına (20) hizalı.
class PageWell extends StatelessWidget {
  const PageWell({
    super.key,
    required this.message,
    this.title,
    this.tone = AknTone.info,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.top = 8,
  });

  final String message;
  final String? title;
  final AknTone tone;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, top, 20, 0),
    child: AknBanner(
      tone: tone,
      icon: icon,
      title: title,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
    ),
  );
}

/// Sayı ile birimi arasında satır kırılmasın ("10.000 L", "338.800,00 ₺", "42,35 ₺/L", "30 gün"):
/// aradaki boşluk bölünmez boşluk olur.
String keepUnits(String s) => s.replaceAllMapped(
  RegExp(r'(\d) (?=(L|₺|₺/L|m³|gün|dk|sa|km|sipariş|teslimat)(?=$|[\s,.;)]))'),
  (m) => '${m[1]} ',
);

/// "22 Ekim" (gün + tam ay adı; yıl yok).
String dayMonthLong(DateTime instant) {
  final w = TrTime.wall(instant);
  return '${w.day} ${Fmt.monthNames[w.month - 1]}';
}

/// Plaka okumaları için yazı ölçeği sınırı (en çok 1,5×): üç sütun korunur, değer sütuna sığmazsa
/// küçülür; çok büyük yazıda sayı satır ortasından bölünmez ya da taşmaz.
class PlateClamp extends StatelessWidget {
  const PlateClamp({super.key, required this.child, this.max = 1.5});

  final Widget child;
  final double max;

  @override
  Widget build(BuildContext context) =>
      MediaQuery.withClampedTextScaling(maxScaleFactor: max, child: child);
}

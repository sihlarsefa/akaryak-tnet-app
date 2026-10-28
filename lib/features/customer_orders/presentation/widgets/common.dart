import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/app_failure.dart';
import '../../../../core/offline/connectivity.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/utils/format.dart';
import '../../../../core/utils/turkish_text.dart';
import '../../copy.dart';

/// "Son güncelleme 14:20" (önbellekten / çevrimdışı gösterilen veri; spec C.4a): sessiz kuyu
/// renginde küçük bir hap (bulut simgesi + caption), görününce yumuşakça belirir.
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
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: FadeUp(
            offset: 6,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 5, 12, 5),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: AknRadius.pillAll,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIconsRegular.cloudSlash, size: 16, color: c.dim),
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
          ),
        ),
      ),
    );
  }
}

/// Sıralı giriş kapsamı ([A2Rise]; tasarım v3 §5): ilk kurulumundan sonraki [window] içinde kurulan
/// öğeler birbiri ardına ([AknMotion.staggerStep] arayla) gelir; sonradan kurulanlar (kaydırınca
/// görünen kart, yeni satır, uyarı) beklemeden yükselir. Yeni bir anahtar verilirse giriş yeniden
/// oynar.
class A2RiseScope extends StatefulWidget {
  const A2RiseScope({
    super.key,
    required this.child,
    this.window = const Duration(milliseconds: 700),
  });

  final Widget child;
  final Duration window;

  @override
  State<A2RiseScope> createState() => _A2RiseScopeState();
}

class _A2RiseScopeState extends State<A2RiseScope> {
  final Stopwatch _clock = Stopwatch()..start();

  bool get _open => _clock.elapsed < widget.window;

  @override
  Widget build(BuildContext context) =>
      _A2RiseMarker(scope: this, child: widget.child);
}

class _A2RiseMarker extends InheritedWidget {
  const _A2RiseMarker({required this.scope, required super.child});

  final _A2RiseScopeState scope;

  @override
  bool updateShouldNotify(_A2RiseMarker old) => old.scope != scope;
}

/// Bir bölümün girişi (tasarım v3 §5): ilk kurulduğunda solarak belirir, [offset] px aşağıdan
/// yükselir ve [scale]'den büyür (vurgulu eğri, [duration]); açık bir [A2RiseScope] içinde
/// [index] × [AknMotion.staggerStep] bekler. [StaggerItem] ile aynı görünüm; farkı, sarmalayıcılar
/// giriş bitince de ağaçta (birim dönüşümle) kalır: içerik yeniden kurulmaz — yazı alanı odağını
/// kaybetmez, plakanın rakamları ikinci kez yuvarlanmaz. Hareket azaltıldığında doğrudan çocuk.
class A2Rise extends StatefulWidget {
  const A2Rise({
    super.key,
    required this.index,
    required this.child,
    this.offset = 24,
    this.scale = 0.96,
    this.duration = AknMotion.stagger,
  });

  final int index;
  final Widget child;
  final double offset;
  final double scale;
  final Duration duration;

  @override
  State<A2Rise> createState() => _A2RiseState();
}

class _A2RiseState extends State<A2Rise> with SingleTickerProviderStateMixin {
  AnimationController? _c;
  CurvedAnimation? _t;
  Timer? _timer;
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    if (AknMotion.reduced(context)) return;
    final scope = context.getInheritedWidgetOfExactType<_A2RiseMarker>()?.scope;
    final cascade = scope == null || scope._open;
    final c = AnimationController(vsync: this, duration: widget.duration);
    _c = c;
    _t = CurvedAnimation(parent: c, curve: AknMotion.emphasizedCurve);
    final delay = cascade
        ? AknMotion.staggerDelay(widget.index)
        : Duration.zero;
    if (delay == Duration.zero) {
      c.forward();
    } else {
      _timer = Timer(delay, () {
        if (mounted) c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _t?.dispose();
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t == null) return widget.child;
    return AnimatedBuilder(
      animation: t,
      child: widget.child,
      builder: (context, child) {
        final v = t.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - v)),
            child: Transform.scale(
              scale: widget.scale + (1 - widget.scale) * v,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Kart yüzeyi (tasarım v3 §3–4): kırık beyaz sayfada yüzen beyaz kart — r20 (bölüm kartı r22) ve
/// iki katmanlı yumuşak kart gölgesi; koyu temada gölge kısalır, kartı 1 px `line` çizgisi belirler.
/// İçerik köşelere kırpılır (basılı satırın `surfaceAlt` vurgusu taşmaz).
///
/// [pressable]: basınca kart 0,97'ye iner ([PressScale]) ve gölgesi sayfaya oturur
/// ([AknShadows.pressed]); bırakınca yayla geri gelir. Dokunmayı içerik yakalar (ör.
/// [AknListTile.onTap]). [borderColor] seçili ya da vurgulu kartın 2 px çerçevesidir (renk
/// değişimi yumuşakça geçer).
class A2Card extends StatefulWidget {
  const A2Card({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.margin,
    this.radius = 20,
    this.color,
    this.borderColor,
    this.pressable = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final bool pressable;

  @override
  State<A2Card> createState() => _A2CardState();
}

class _A2CardState extends State<A2Card> {
  bool _down = false;

  void _set(bool v) {
    if (!widget.pressable || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final radius = BorderRadius.circular(widget.radius);
    final border = widget.borderColor ?? (c.isDark ? c.line : null);
    Widget card = AnimatedContainer(
      duration: AknMotion.of(
        context,
        _down ? AknMotion.press : AknMotion.pressOut,
      ),
      curve: AknMotion.standard,
      decoration: BoxDecoration(
        color: widget.color ?? c.surface,
        borderRadius: radius,
        boxShadow: _down ? AknShadows.pressed(c) : AknShadows.card(c),
      ),
      foregroundDecoration: border == null
          ? null
          : BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: border,
                width: widget.borderColor == null ? 1 : 2,
              ),
            ),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          type: MaterialType.transparency,
          child: Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    );
    if (widget.pressable) {
      card = Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: PressScale(child: card),
      );
    }
    final m = widget.margin;
    return m == null ? card : Padding(padding: m, child: card);
  }
}

/// 40 px yuvarlak köşeli simge karosu (tasarım v3 §4, satırın baş simgesi): sessiz kuyu
/// (`surfaceAlt`) üstünde mürekkep simge; [tone] verilirse tonun yumuşak kuyusu ve rengi ("sıra
/// sizde" turuncu, teslim yeşil, sorun kırmızı). Ton değişince renk yumuşakça geçer, simge
/// değişince yenisi küçükten büyüyerek gelir.
class A2IconTile extends StatelessWidget {
  const A2IconTile({super.key, required this.icon, this.tone, this.size = 40});

  final IconData icon;
  final AknTone? tone;
  final double size;

  /// Karonun zemini ve simge rengi.
  static (Color, Color) colorsOf(AknColors c, AknTone? tone) => switch (tone) {
    null || AknTone.info => (c.surfaceAlt, c.ink),
    AknTone.neutral => (c.surfaceAlt, c.dim),
    AknTone.brand => (c.brandSoft, c.brandInk),
    final t => (c.tone(t).bg, c.tone(t).fg),
  };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = colorsOf(context.akn, tone);
    return ExcludeSemantics(
      child: AnimatedContainer(
        duration: AknMotion.of(context, AknMotion.base),
        curve: AknMotion.standard,
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        // Simge değişince (aşama ilerledi) yenisi küçükten büyüyerek gelir.
        child: AnimatedSwitcher(
          duration: AknMotion.of(context, AknMotion.iconSwap),
          switchInCurve: AknMotion.pop,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: ScaleTransition(scale: a, child: child),
          ),
          child: Icon(icon, key: ValueKey(icon), size: size * 0.55, color: fg),
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
/// performLayout"); bu yüzden süre en az 1 ms tutulur (gözle görülmez). Açılıp kapanma vurgulu
/// eğriyle (v3 §5) akar.
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
    final d = AknMotion.of(context, AknMotion.slow);
    return AnimatedSize(
      duration: d > Duration.zero ? d : const Duration(milliseconds: 1),
      curve: AknMotion.emphasizedCurve,
      alignment: alignment,
      child: child,
    );
  }
}

/// İçerik değişimi (tasarım v3 §5): eski içerik söner, yenisi 0,96'dan büyüyerek belirir ve
/// yükseklik farkı yumuşakça kapanır. Her durumun çocuğu ayrı bir anahtar taşımalıdır.
class A2Swap extends StatelessWidget {
  const A2Swap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SafeAnimatedSize(
    child: AnimatedSwitcher(
      duration: AknMotion.of(context, AknMotion.base),
      switchInCurve: AknMotion.emphasizedCurve,
      switchOutCurve: AknMotion.exit,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: child,
    ),
  );
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
                Icon(PhosphorIconsRegular.copy, size: 16, color: c.dim),
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

/// Bölüm kartı (tasarım v3 §4): beyaz r20 kart ([A2Card]); başta isteğe bağlı simge karosu
/// ([A2IconTile], [accent] tonunda), başlık 18/24 800 ve sağda eylem; altında içerik.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    this.margin = const EdgeInsets.fromLTRB(20, 12, 20, 0),
    this.padding = const EdgeInsets.fromLTRB(18, 16, 18, 18),
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
    return A2Card(
      margin: margin,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TitleActionRow(
            title: Row(
              children: [
                if (icon != null) ...[
                  A2IconTile(icon: icon!, tone: accent, size: 36),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(title, style: a2SectionTitle(t, c)),
                  ),
                ),
              ],
            ),
            action: trailing,
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Kart satırında tutar başlığın yanında mı durur (tasarım v3): başlık tek satırda kalmalı. Başlık
/// sağdaki tutar sütunuyla ([amount] / [meta]) aynı satıra sığmıyorsa tutar alt satıra iner
/// ([A2AmountLine]) — "Motorin, 30.000" / "L" gibi kopuk satır olmaz. [width] metin sütununun
/// genişliğidir.
bool a2AmountBeside(
  BuildContext context, {
  required double width,
  required String title,
  required TextStyle titleStyle,
  String? amount,
  String? meta,
}) {
  if (amount == null && meta == null) return true;
  if (!width.isFinite) return true;
  final t = context.aknText;
  double measure(String? s, TextStyle style) =>
      s == null ? 0 : a2LineWidth(context, s, style);

  final right = math.max(measure(amount, t.amount), measure(meta, t.bodySmall));
  return measure(title, titleStyle) + 12 + right <= width;
}

/// Metnin tek satırdaki genişliği (geçerli yazı ölçeğiyle).
double a2LineWidth(BuildContext context, String text, TextStyle style) {
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final w = tp.width;
  tp.dispose();
  return w;
}

/// Rakamdan sonra gelen birimin önündeki boşluk ("20.000 L", "338.800,00 ₺", "42,35 ₺/L",
/// "12 m³").
final RegExp _unitGap = RegExp(
  r'(\d) (?=(?:L|₺|m³)(?![\p{L}\p{N}]))',
  unicode: true,
);

/// Sayıyı birimiyle aynı satırda tutar: rakam ile birim arasındaki boşluk bölünmez boşluk
/// (U+00A0) olur, satır sayıdan önce kırılır ("Motorin," / "20.000 L"). Görünüm aynıdır.
String keepUnits(String text) =>
    text.replaceAllMapped(_unitGap, (m) => '${m[1]}\u00A0');

/// Satıra sığan metin olduğu gibi kalır; sığmayacaksa sayı ile birimi birlikte kaydırılır
/// ([keepUnits]). [width] metnin sütun genişliğidir (sonsuzsa metin değişmez).
String a2WrapSafe(
  BuildContext context,
  String text,
  TextStyle style, {
  required double width,
}) {
  if (!width.isFinite || !_unitGap.hasMatch(text)) return text;
  return a2LineWidth(context, text, style) <= width ? text : keepUnits(text);
}

/// Sayı + birim içeren başlık ("Motorin, 20.000 L", "11.950 L motorin"): satıra sığıyorsa aynen,
/// sığmıyorsa sayı birimiyle aynı satırda kalarak kaydırılır ([a2WrapSafe]) — büyük yazıda
/// "20.000" / "L" kopukluğu olmaz.
class A2UnitText extends StatelessWidget {
  const A2UnitText(
    this.text, {
    super.key,
    required this.style,
    this.maxLines,
    this.overflow,
    this.textAlign,
  });

  final String text;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Text(
      a2WrapSafe(context, text, style, width: box.maxWidth),
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    ),
  );
}

/// Başlığın yanına sığmayan tutar: alt satırda tablo rakamlı tutar (17/22 700) ve küçük açıklaması
/// ("42,35 ₺/L", "tahmini").
class A2AmountLine extends StatelessWidget {
  const A2AmountLine({super.key, required this.amount, this.meta});

  final String amount;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Text.rich(
      TextSpan(
        text: amount,
        style: t.amount.copyWith(color: c.ink),
        children: [
          if (meta != null)
            TextSpan(
              text: '  $meta',
              style: t.bodySmall.copyWith(color: c.dim),
            ),
        ],
      ),
    );
  }
}

/// Kart satırı başlığı (tasarım v3 §4 AknListTile): 15/20 600, mürekkep — baş karosu ve sağdaki
/// tutarla aynı satırda rahat sığar.
TextStyle a2RowTitle(AknTextStyles t, AknColors c) =>
    t.bodyStrong.copyWith(height: 20 / 15, color: c.ink);

/// Bölüm başlığı yazısı (tasarım v3 §4 SectionHeader): 18/24 800, −0,3, mürekkep.
TextStyle a2SectionTitle(AknTextStyles t, AknColors c) => t.title.copyWith(
  fontSize: 18,
  height: 24 / 18,
  fontWeight: FontWeight.w800,
  letterSpacing: -0.3,
  color: c.ink,
);

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

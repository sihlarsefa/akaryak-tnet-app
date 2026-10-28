import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/app_failure.dart';
import '../../../core/ui/ui.dart';
import '../../../core/utils/debouncer.dart';
import '../../../core/utils/external_activity.dart';
import '../../../core/utils/format.dart';
import '../copy.dart';

/// Destek kodu: iz kimliğinin ilk 8 karakteri (spec C.7).
String? supportCode(AppFailure f) {
  final t = f.traceId;
  if (t == null || t.isEmpty) return null;
  return t.length <= 8 ? t : t.substring(0, 8);
}

/// Kullanıcıya gösterilecek kısa hata metni (ne başarısız oldu, ne yapmalı).
String failureText(AppFailure f) => switch (f) {
  OfflineFailure() =>
    'Bağlantı yok. Bağlantı gelince tekrar deneyin; girdikleriniz bu ekranda duruyor.',
  TimeoutFailure() =>
    'Sunucu zamanında yanıt vermedi. Birkaç dakika sonra tekrar deneyin.',
  RateLimitedFailure(:final retryAfter) =>
    retryAfter == null
        ? 'Çok fazla deneme. Biraz sonra tekrar deneyin.'
        : 'Çok fazla deneme. ${retryAfter.inSeconds} sn sonra tekrar deneyin.',
  ConflictFailure(:final isConcurrency) =>
    isConcurrency
        ? 'Bu kayıt siz bakarken değişti. Güncel hâli yüklendi; tekrar deneyin.'
        : f.message,
  ServerFailure() =>
    supportCode(f) == null
        ? 'Sunucuya şu an ulaşılamıyor. Birkaç dakika sonra tekrar deneyin.'
        : 'Sunucuya şu an ulaşılamıyor. Birkaç dakika sonra tekrar deneyin. Destek kodu: ${supportCode(f)}',
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

/// Bölüm seçici ([AknSegmented], tasarım v3 §4): sessiz kuyu renginde hap iz, kart gölgeli beyaz
/// başparmak yayla kayar; 20 px kenar.
class CmSegmented<T> extends StatelessWidget {
  const CmSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.margin = const EdgeInsets.symmetric(horizontal: 20),
  });

  final List<FilterOption<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) => AknSegmented<T>(
    segments: segments,
    value: value,
    onChanged: onChanged,
    margin: margin,
  );
}

/// Arama hapı (tasarım v3 §4 Inputs): `surfaceAlt` hap, büyüteç 20 soluk, ipucu soluk; odakta zemin
/// beyaza döner, 2 px turuncu kenar ve 4 px yumuşak turuncu hale yumuşakça belirir. Yüksekliği 52
/// (dokunma alanı en az 48 dp, WCAG / Android yönergesi). Yazdıkça [debounce] sonra [onChanged]
/// (kırpılmış).
class CmSearchField extends StatefulWidget {
  const CmSearchField({
    super.key,
    required this.hint,
    this.onChanged,
    this.debounce = const Duration(milliseconds: 300),
  });

  final String hint;
  final ValueChanged<String>? onChanged;
  final Duration debounce;

  @override
  State<CmSearchField> createState() => _CmSearchFieldState();
}

class _CmSearchFieldState extends State<CmSearchField> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  late final Debouncer _debouncer = Debouncer(widget.debounce);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_rebuild);
    _focus.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  void _changed(String s) {
    final cb = widget.onChanged;
    if (cb == null) return;
    _debouncer(() => cb(s.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final t = context.aknText;
    final text = t.body.copyWith(height: 20 / 15, color: c.ink);
    final focused = _focus.hasFocus;
    final duration = AknMotion.of(context, AknMotion.base);
    const none = InputBorder.none;
    return AnimatedContainer(
      duration: duration,
      curve: AknMotion.standard,
      decoration: BoxDecoration(
        color: focused ? c.surface : c.surfaceAlt,
        borderRadius: AknRadius.pillAll,
        // Kenar hep 2 px: odakta yalnızca rengi gelir, içerik kaymaz.
        border: Border.all(
          color: focused ? c.brand : c.surfaceAlt.withValues(alpha: 0),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: focused ? c.brandSoft : c.brandSoft.withValues(alpha: 0),
            spreadRadius: 4,
          ),
        ],
      ),
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        textInputAction: TextInputAction.search,
        onChanged: _changed,
        onSubmitted: (s) {
          _debouncer.cancel();
          widget.onChanged?.call(s.trim());
        },
        onTapOutside: (_) => _focus.unfocus(),
        style: text,
        cursorColor: c.brand,
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: text.copyWith(color: c.dim),
          hintMaxLines: 1,
          isDense: true,
          filled: false,
          hoverColor: Colors.transparent,
          contentPadding: const EdgeInsets.fromLTRB(0, 14, 12, 14),
          prefixIcon: TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: focused ? c.ink : c.dim),
            duration: duration,
            builder: (context, color, _) => Icon(
              PhosphorIconsRegular.magnifyingGlass,
              color: color,
              size: 20,
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 46,
            minHeight: 48,
          ),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Temizle',
                  icon: Icon(PhosphorIconsRegular.x, color: c.dim, size: 20),
                  onPressed: () {
                    AknHaptics.selection();
                    _controller.clear();
                    _debouncer.cancel();
                    widget.onChanged?.call('');
                  },
                ),
          border: none,
          enabledBorder: none,
          focusedBorder: none,
        ),
      ),
    );
  }
}

/// Kart yüzeyi (tasarım v3 §3–4): kırık beyaz sayfada yüzen beyaz kart, r20, iki katmanlı yumuşak
/// kart gölgesi; koyu temada gölge kısalır, kartı 1 px `line` belirler. İçerik köşelere kırpılır.
/// [pressable]: basınca kart 0,97'ye iner ve gölgesi sayfaya oturur; dokunmayı içerik yakalar.
/// [borderColor] vurgulu kartın 2 px çerçevesidir.
class CmCard extends StatefulWidget {
  const CmCard({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.margin,
    this.pressable = false,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final bool pressable;
  final Color? borderColor;

  /// Liste kartlarının dış boşluğu (20 px sayfa kenarı, kartlar arası 12).
  static const listMargin = EdgeInsets.fromLTRB(20, 6, 20, 6);

  /// Kart içindeki satırların dolgusu.
  static const rowPadding = EdgeInsets.fromLTRB(16, 14, 16, 14);

  @override
  State<CmCard> createState() => _CmCardState();
}

class _CmCardState extends State<CmCard> {
  bool _down = false;

  void _set(bool v) {
    if (!widget.pressable || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    const radius = AknRadius.card;
    final border = widget.borderColor ?? (c.isDark ? c.line : null);
    Widget card = AnimatedContainer(
      duration: AknMotion.of(
        context,
        _down ? AknMotion.press : AknMotion.pressOut,
      ),
      curve: AknMotion.standard,
      decoration: BoxDecoration(
        color: c.surface,
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

/// 40 px yuvarlak köşeli simge karosu (tasarım v3 §4, satırın baş simgesi): sessiz kuyu ve
/// mürekkep simge; [tone] verilirse tonun yumuşak kuyusu ("sıra sizde" turuncu, tamam yeşil, sorun
/// kırmızı). Ton değişince renk yumuşakça geçer.
class CmIconTile extends StatelessWidget {
  const CmIconTile({super.key, required this.icon, this.tone, this.size = 40});

  final IconData icon;
  final AknTone? tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final (bg, fg) = switch (tone) {
      null || AknTone.info => (c.surfaceAlt, c.ink),
      AknTone.neutral => (c.surfaceAlt, c.dim),
      AknTone.brand => (c.brandSoft, c.brandInk),
      final t => (c.tone(t).bg, c.tone(t).fg),
    };
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
        // Simge değişince (durum ilerledi) yenisi küçükten büyüyerek gelir.
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

/// Kart satırında tutar başlığın yanında mı durur (tasarım v3): başlık tek satırda kalmalı; sağdaki
/// tutar sütunuyla aynı satıra sığmıyorsa tutar alt satıra iner ([CmAmountLine]) — kopuk "… / L"
/// satırı olmaz. [width]: metin sütununun genişliği.
bool cmAmountBeside(
  BuildContext context, {
  required double width,
  required String title,
  String? amount,
  String? meta,
}) {
  if (amount == null && meta == null) return true;
  if (!width.isFinite) return true;
  final t = context.aknText;
  double measure(String? s, TextStyle style) =>
      s == null ? 0 : cmLineWidth(context, s, style);

  final right = math.max(measure(amount, t.amount), measure(meta, t.bodySmall));
  return measure(title, cmRowTitle(context)) + 12 + right <= width;
}

/// Metnin tek satırdaki genişliği (geçerli yazı ölçeğiyle).
double cmLineWidth(BuildContext context, String text, TextStyle style) {
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

/// Rakamdan sonra gelen birimin önündeki boşluk ("11.950 L", "471.350,00 ₺", "42,10 ₺/L").
final RegExp _unitGap = RegExp(
  r'(\d) (?=(?:L|₺|m³)(?![\p{L}\p{N}]))',
  unicode: true,
);

/// Satıra sığan metin aynen kalır; sığmayacaksa rakam ile birim arasındaki boşluk bölünmez
/// boşluk (U+00A0) olur: satır sayıdan önce kırılır, "11.950" / "L motorin" kopukluğu olmaz.
String cmWrapSafe(
  BuildContext context,
  String text,
  TextStyle style, {
  required double width,
}) {
  if (!width.isFinite || !_unitGap.hasMatch(text)) return text;
  if (cmLineWidth(context, text, style) <= width) return text;
  return cmKeepUnits(text);
}

/// Sayıyı birimiyle aynı satırda tutar: rakam ile birim arasındaki boşluk bölünmez boşluk olur
/// (kart başlıkları: "Motorin," / "30.000 L"). Görünüm aynıdır.
String cmKeepUnits(String text) =>
    text.replaceAllMapped(_unitGap, (m) => '${m[1]}\u00A0');

/// Sayı + birim içeren nesne başlığı ("11.950 L motorin"): satıra sığıyorsa aynen, sığmıyorsa
/// sayı birimiyle aynı satırda kalarak kaydırılır ([cmWrapSafe]).
class CmUnitText extends StatelessWidget {
  const CmUnitText(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => Text(
      cmWrapSafe(context, text, style, width: box.maxWidth),
      style: style,
    ),
  );
}

/// Başlığın yanına sığmayan tutar: alt satırda tablo rakamlı tutar ve küçük açıklaması.
class CmAmountLine extends StatelessWidget {
  const CmAmountLine({super.key, required this.amount, this.meta});

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

/// Kart satırı başlığı (tasarım v3 §4 AknListTile): 15/20 600, mürekkep.
TextStyle cmRowTitle(BuildContext context) => context.aknText.bodyStrong
    .copyWith(height: 20 / 15, color: context.akn.ink);

/// Bölüm başlığı (tasarım v3 §4 SectionHeader): 18/24 800, −0,3, mürekkep.
TextStyle cmSectionTitle(BuildContext context) =>
    context.aknText.title.copyWith(
      fontSize: 18,
      height: 24 / 18,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
      color: context.akn.ink,
    );

/// Büyük yazı (≥ 1,6×): plakalar destedeki gibi sıkı düzene geçer (§5.3, §12).
bool cmLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) >= 16;

/// Sıralı giriş kapsamı ([CmRise]; tasarım v3 §5): ilk kurulumundan sonraki [window] içinde kurulan
/// bölümler birbiri ardına ([AknMotion.staggerStep] arayla) gelir; sonradan kurulanlar beklemeden
/// yükselir. Yeni bir anahtar verilirse giriş yeniden oynar.
class CmRiseScope extends StatefulWidget {
  const CmRiseScope({
    super.key,
    required this.child,
    this.window = const Duration(milliseconds: 700),
  });

  final Widget child;
  final Duration window;

  @override
  State<CmRiseScope> createState() => _CmRiseScopeState();
}

class _CmRiseScopeState extends State<CmRiseScope> {
  final Stopwatch _clock = Stopwatch()..start();

  bool get _open => _clock.elapsed < widget.window;

  @override
  Widget build(BuildContext context) =>
      _CmRiseMarker(scope: this, child: widget.child);
}

class _CmRiseMarker extends InheritedWidget {
  const _CmRiseMarker({required this.scope, required super.child});

  final _CmRiseScopeState scope;

  @override
  bool updateShouldNotify(_CmRiseMarker old) => old.scope != scope;
}

/// Bir bölümün girişi (tasarım v3 §5): solarak belirir, [offset] px aşağıdan yükselir ve
/// [scale]'den büyür (vurgulu eğri); açık bir [CmRiseScope] içinde [index] ×
/// [AknMotion.staggerStep] bekler. [StaggerItem] ile aynı görünüm, ama sarmalayıcılar giriş
/// bitince de ağaçta kalır: içerik yeniden kurulmaz — yazı alanı odağını kaybetmez, plakanın
/// rakamları ve grafiğin çubukları ikinci kez oynamaz. Hareket azaltıldığında doğrudan çocuk.
class CmRise extends StatefulWidget {
  const CmRise({
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
  State<CmRise> createState() => _CmRiseState();
}

class _CmRiseState extends State<CmRise> with SingleTickerProviderStateMixin {
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
    final scope = context.getInheritedWidgetOfExactType<_CmRiseMarker>()?.scope;
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

/// Bir plaka: normal yazıda okumalar kuralın altında; büyük yazıda plaka sıkı düzende (baş ve rakam)
/// kalır ve okumalar plakanın altında etiket / değer satırları olarak yazılır (uzun değerler
/// sarılır, kesilmez).
class CmPlate extends StatelessWidget {
  const CmPlate({
    super.key,
    required this.head,
    required this.figure,
    required this.readouts,
    this.semanticLabel,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 0),
  });

  final Widget head;
  final Widget figure;
  final List<PlateReadout> readouts;
  final String? semanticLabel;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final large = cmLargeText(context);
    // Ekranın kahraman kartı yükselerek gelir (v3 §5); giriş bitince yeniden kurulmaz, rakamlar bir
    // kez yuvarlanır.
    final plate = CmRise(
      index: 0,
      offset: 24,
      scale: 0.94,
      duration: AknMotion.heroRise,
      child: AknPlate(
        semanticLabel: semanticLabel,
        compact: large,
        head: head,
        figure: figure,
        below: large ? null : PlateReadouts(items: readouts),
      ),
    );
    if (!large) return Padding(padding: padding, child: plate);
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          plate,
          const SizedBox(height: 8),
          for (final r in readouts)
            FactRow(
              label: r.label,
              value: r.unit == null || r.unit!.isEmpty
                  ? r.value
                  : '${r.value} ${r.unit}',
            ),
        ],
      ),
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
        title: 'Sunucuya ulaşılamıyor',
        message:
            'Sunucuya şu an ulaşılamıyor. Birkaç dakika sonra tekrar deneyin.',
        traceId: supportCode(f),
        onRetry: onRetry,
        compact: compact,
      ),
      TimeoutFailure() => ErrorState(
        title: 'Sunucu zamanında yanıt vermedi',
        message:
            'Bağlantınız yavaş olabilir. Birkaç dakika sonra tekrar deneyin.',
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
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
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
                  Icon(
                    PhosphorIconsRegular.clockCounterClockwise,
                    size: 16,
                    color: c.dim,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Son güncelleme $when, çevrimdışı gösteriliyor',
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
            icon: PhosphorIconsRegular.arrowClockwise,
            onPressed: onRetry,
          ),
        ),
      );
    }
    return const SizedBox(height: 24);
  }
}

/// Sayfa bölümü (tasarım v3 §4): kırık beyaz sayfada yüzen beyaz r20 kart; içinde başlık (18/24
/// 800), isteğe bağlı açıklama ve sağda bir denetim, altında içerik. İçerik kartın 18 px iç
/// kenarıyla gelir; satırlar gibi kart genişliğinde içerik için [bleed] true verin (satırlar kendi
/// dolgusunu taşır). [padding] ve [accent] kullanılmaz (API kararlılığı için duruyor).
class CmSection extends StatelessWidget {
  const CmSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.padding = AknSpace.cardPadding,
    this.accent,
    this.bleed = false,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final AknTone? accent;

  /// İçerik kart genişliğinde (satırlar kendi dolgusunu taşır).
  final bool bleed;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return CmCard(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              18,
              trailing == null ? 16 : 6,
              trailing == null ? 18 : 6,
              bleed ? 4 : 10,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(title, style: cmSectionTitle(context)),
                      ),
                      if (subtitle != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitle!,
                            style: t.bodySmall.copyWith(color: c.dim),
                          ),
                        ),
                    ],
                  ),
                ),
                // Kendi düğümü: başlığa karışmadan ayrıca odaklanır.
                if (trailing != null)
                  Semantics(container: true, child: trailing),
              ],
            ),
          ),
          if (bleed) ...[
            child,
            const SizedBox(height: 6),
          ] else
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: child,
            ),
        ],
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

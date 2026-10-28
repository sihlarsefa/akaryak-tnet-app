import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ui/ui.dart';
import '../../copy.dart';

/// Giriş ekranının üst alanı (tasarım v3 "Akış"): ışıklı turuncu bant ([AknBand], ortam ışığıyla), ortada
/// hafifçe süzülen beyaz logo karosu, beyaz "AkaryakıtNet" yazısı, başlık ("Siparişten teslimata.") ve tek
/// satır alt yazı. Arkada logonun » okları çok soluk ve iri, yavaşça akar. Durum çubuğunun arkasından
/// başlar (açık simgeler). Altındaki beyaz sayfa ([LoginSheet]) bandın son [sheetOverlap] pikseline biner;
/// bant o kısmı da boyar, böylece sayfanın yuvarlak köşelerinin arkası hep turuncudur.
///
/// Kod, kilit, güncelleme ve telefon doğrulama ekranları beyaz sayfalardır ([AuthPageHeader]).
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, this.compact = false});

  /// Büyük yazı ya da demo derlemesi: alan daralır, başlık satırı gizlenir.
  final bool compact;

  /// Durum çubuğunun altındaki bant yüksekliği (beyaz sayfanın bindiği kısım dahil).
  static const double bodyHeight = 236;

  /// Beyaz sayfanın banda bindiği yükseklik (sayfanın üst köşeleri r28).
  static const double sheetOverlap = 32;

  /// Dar bant (büyük yazı, demo derlemesi).
  static const double _compactBody = 160;

  // viewPadding: üst katmanlar dolguyu tüketmiş olsa da durum çubuğu payı doğru gelir.
  static double _top(BuildContext context) => math.max(
    MediaQuery.paddingOf(context).top,
    MediaQuery.viewPaddingOf(context).top,
  );

  /// Bandın yerleşimdeki yüksekliği (durum çubuğu dahil, sayfanın bindiği kısım hariç): altındaki
  /// beyaz sayfa tam buradan başlar.
  static double layoutHeight(BuildContext context, {bool compact = false}) =>
      _top(context) + (compact ? _compactBody : bodyHeight) - sheetOverlap;

  @override
  Widget build(BuildContext context) {
    final top = _top(context);
    final c = context.akn;
    final body = compact ? _compactBody : bodyHeight;
    final band = AknBand(
      padding: EdgeInsets.only(top: top),
      child: SizedBox(
        height: body,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            const Positioned.fill(child: _FlowChevrons()),
            Positioned.fill(
              bottom: sheetOverlap,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AknSpace.page,
                  compact ? 2 : 8,
                  AknSpace.page,
                  compact ? 14 : 22,
                ),
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.2,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _BandContent(compact: compact),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AknTheme.overlayOnBand(c.brightness),
      child: Semantics(
        container: true,
        header: true,
        label: AuthCopy.bandSpoken,
        excludeSemantics: true,
        // Yerleşimde bant, sayfanın bindiği kısım kadar kısa sayılır; boyası o kısmı da kaplar.
        child: SizedOverflowBox(
          size: Size(double.infinity, top + body - sheetOverlap),
          alignment: Alignment.topCenter,
          child: band,
        ),
      ),
    );
  }
}

/// Bandın ortası: süzülen logo karosu, beyaz yazı markası, başlık ve alt yazı. Açılışta logo okları
/// kendini çizer, yazılar sırayla yukarı kayarak belirir.
class _BandContent extends StatelessWidget {
  const _BandContent({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FloatingLogo(size: compact ? 42 : 60),
        SizedBox(height: compact ? 8 : 14),
        AuthRise(
          delay: const Duration(milliseconds: 60),
          offset: 10,
          child: AknWordmark(fontSize: compact ? 23 : 27, semanticLabel: null),
        ),
        if (!compact) ...[
          const SizedBox(height: 8),
          AuthRise(
            delay: const Duration(milliseconds: 110),
            offset: 10,
            child: Text(
              AuthCopy.tagline,
              textAlign: TextAlign.center,
              style: t.bodyStrong.copyWith(
                fontSize: 16,
                height: 22 / 16,
                fontWeight: FontWeight.w700,
                color: c.onHero,
              ),
            ),
          ),
        ],
        const SizedBox(height: 2),
        AuthRise(
          delay: const Duration(milliseconds: 150),
          offset: 10,
          child: Text(
            AuthCopy.bandSubtitle,
            textAlign: TextAlign.center,
            style: t.label.copyWith(
              fontWeight: FontWeight.w500,
              color: c.onHeroDim,
            ),
          ),
        ),
      ],
    );
  }
}

/// Beyaz logo karosu (bantta ters işaret: beyaz kare, turuncu oklar): camsı bir halkanın içinde yavaşça
/// süzülür (±4 px, [AknMotion.float]); altındaki sıcak gölge karo yükseldikçe yumuşar. Açılışta oklar
/// bir kez kendini çizer ve karo hafifçe büyüyerek yerine oturur.
class _FloatingLogo extends StatelessWidget {
  const _FloatingLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final ring = size + 14;
    final tile = LogoMark(size: size, animate: true, semanticLabel: null);
    return AuthPop(
      child: AknAmbient(
        period: AknMotion.float,
        reverse: true,
        child: tile,
        builder: (context, t, child) => SizedBox.square(
          dimension: ring + 10,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Camsı halka: beyaz %14 dolgu, beyaz %26 çizgi.
              Container(
                width: ring,
                height: ring,
                decoration: BoxDecoration(
                  color: c.onHero.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(ring * 0.3),
                  border: Border.all(color: c.onHero.withValues(alpha: 0.26)),
                ),
              ),
              Transform.translate(
                offset: Offset(0, -4 * t),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(size * 0.225),
                    boxShadow: [
                      BoxShadow(
                        color: c.heroEnd.withValues(alpha: 0.55 - 0.2 * t),
                        blurRadius: 14 + 8 * t,
                        offset: Offset(0, 8 + 4 * t),
                        spreadRadius: -4,
                      ),
                    ],
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Akış": logonun » okları bandın sağında iri ve çok soluk (beyaz %9), yatayda yavaşça akar
/// ([AknMotion.bandDrift]); sol altta küçük bir eşi ters yönde süzülür. Süs; ekran okuyucuda yok.
class _FlowChevrons extends StatelessWidget {
  const _FlowChevrons();

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    // Yerleşim bir kez; akış yalnızca boyada (Transform), her karede yeniden yerleşim yok.
    Widget drift(double dx, Widget child) => AknAmbient(
      period: AknMotion.bandDrift,
      reverse: true,
      child: child,
      builder: (context, t, child) =>
          Transform.translate(offset: Offset(dx * t, 0), child: child),
    );
    return IgnorePointer(
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, box) {
            // Görünen bant (sayfanın bindiği kısım hariç) ortalanır.
            final visible = box.maxHeight - AuthHeader.sheetOverlap;
            final big = visible * 1.5;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  right: -big * 0.42,
                  top: (visible - big) / 2,
                  child: drift(
                    18,
                    _Chevrons(
                      size: big,
                      color: c.onHero.withValues(alpha: 0.075),
                    ),
                  ),
                ),
                Positioned(
                  left: -big * 0.2,
                  top: visible - big * 0.3,
                  child: drift(
                    -12,
                    _Chevrons(
                      size: big * 0.4,
                      color: c.onHero.withValues(alpha: 0.06),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Chevrons extends StatelessWidget {
  const _Chevrons({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: LogoMarkPainter(
      progress: 1,
      showTile: false,
      tileColor: color,
      chevronColor: color,
    ),
  );
}

/// Giriş ekranının beyaz sayfası (tasarım v3): üst köşeleri 28 yuvarlak, yüzey rengi, banda yukarı doğru
/// yumuşak bir gölge verir. İlk açılışta tek bir hareket saatiyle yükselir: sayfa 56 px aşağıdan kayarak
/// gelir, içindeki bölümler ([AuthReveal]) sırayla belirir. Opaklık hızla tamamlanır, kayma uzun ve yumuşak
/// biter (ölçek yok: dokunma hedefleri hep tam boy). Azaltılmış harekette doğrudan görünür.
class LoginSheet extends StatefulWidget {
  const LoginSheet({super.key, required this.child});

  final Widget child;

  /// Yükselişin ve sıralı belirişin toplam süresi.
  static const Duration entrance = Duration(milliseconds: 900);

  @override
  State<LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<LoginSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: LoginSheet.entrance,
  );
  static final _rise = CurveTween(
    curve: const Interval(0, 0.72, curve: AknMotion.emphasizedCurve),
  );
  static final _fade = CurveTween(
    curve: const Interval(0, 0.26, curve: Curves.easeOut),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else {
      unawaited(_c.forward());
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.akn;
    final sheet = DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AknRadius.sheet,
        boxShadow: [
          BoxShadow(
            color: c.isDark
                ? c.shadow.withValues(alpha: 0.4)
                : c.heroEnd.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, -6),
            spreadRadius: -8,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 24),
        child: _AuthEntranceScope(animation: _c, child: widget.child),
      ),
    );
    return AnimatedBuilder(
      animation: _c,
      child: sheet,
      builder: (context, child) => Opacity(
        opacity: _fade.evaluate(_c),
        child: Transform.translate(
          offset: Offset(0, 56 * (1 - _rise.evaluate(_c))),
          child: child,
        ),
      ),
    );
  }
}

/// [LoginSheet]'in hareket saati (sayfanın içindeki [AuthReveal]'lar okur).
class _AuthEntranceScope extends InheritedWidget {
  const _AuthEntranceScope({required this.animation, required super.child});

  final Animation<double> animation;

  @override
  bool updateShouldNotify(_AuthEntranceScope old) => old.animation != animation;
}

/// Beyaz sayfanın bir bölümü (tasarım v3 §5 sıralı giriş): sayfa yükselirken [index] sırasında 22 px
/// aşağıdan kayarak gelir; opaklığı hızla, kayması uzun ve yumuşak tamamlanır. [LoginSheet] dışında
/// doğrudan çizilir. Yapısı hiç değişmez (içindeki alanların durumu korunur).
class AuthReveal extends StatelessWidget {
  const AuthReveal({super.key, required this.index, required this.child});

  /// Sıra (0 = ilk). 8'den sonrakiler sekizinciyle birlikte gelir.
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_AuthEntranceScope>();
    if (scope == null) return child;
    final start = 0.08 + 0.034 * index.clamp(0, 8);
    final move = CurveTween(
      curve: Interval(
        start,
        math.min(1, start + 0.6),
        curve: AknMotion.emphasizedCurve,
      ),
    );
    final fade = CurveTween(
      curve: Interval(start, start + 0.1, curve: Curves.easeOut),
    );
    final a = scope.animation;
    return AnimatedBuilder(
      animation: a,
      child: child,
      builder: (context, child) => Opacity(
        opacity: fade.evaluate(a),
        child: Transform.translate(
          offset: Offset(0, 22 * (1 - move.evaluate(a))),
          child: child,
        ),
      ),
    );
  }
}

/// Tek seferlik giriş hareketi (tasarım v3 §5): [delay] sonra [offset] px aşağıdan kayarak gelir ve hızla
/// belirir; kayma [duration] boyunca vurgulu eğriyle yumuşakça oturur. Ölçek yok (dokunma hedefleri hep
/// tam boy) ve yapısı hiç değişmez (içindeki durum korunur). Azaltılmış harekette doğrudan çizilir.
class AuthRise extends StatefulWidget {
  const AuthRise({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 18,
    this.duration = const Duration(milliseconds: 620),
  });

  final Widget child;
  final Duration delay;
  final double offset;
  final Duration duration;

  @override
  State<AuthRise> createState() => _AuthRiseState();
}

class _AuthRiseState extends State<AuthRise>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  static final _move = CurveTween(curve: AknMotion.emphasizedCurve);
  static final _fade = CurveTween(
    curve: const Interval(0, 0.4, curve: Curves.easeOut),
  );
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else if (widget.delay == Duration.zero) {
      unawaited(_c.forward());
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) unawaited(_c.forward());
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) => Opacity(
      opacity: _fade.evaluate(_c),
      child: Transform.translate(
        offset: Offset(0, widget.offset * (1 - _move.evaluate(_c))),
        child: child,
      ),
    ),
  );
}

/// Bir işaretin (logo karosu, durum çizimi) yerine "pop" ile oturması: %72'den büyüyüp hafifçe taşarak
/// (easeOutBack) 1'e gelir ve belirir. Yalnızca süs öğeleri için (ölçek dokunma hedefini küçültür).
class AuthPop extends StatefulWidget {
  const AuthPop({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 560),
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  @override
  State<AuthPop> createState() => _AuthPopState();
}

class _AuthPopState extends State<AuthPop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  static final _scale = CurveTween(curve: AknMotion.pop);
  static final _fade = CurveTween(
    curve: const Interval(0, 0.35, curve: Curves.easeOut),
  );
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AknMotion.reduced(context)) {
      _c.value = 1;
    } else if (widget.delay == Duration.zero) {
      unawaited(_c.forward());
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) unawaited(_c.forward());
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) => Opacity(
      opacity: _fade.evaluate(_c),
      child: Transform.scale(
        scale: 0.72 + 0.28 * _scale.evaluate(_c),
        child: child,
      ),
    ),
  );
}

/// Beyaz kimlik sayfalarının başı (tasarım v3: kod, telefon doğrulama): solda 48 px logo karosu (altında
/// sıcak bir gölgeyle yükselmiş, açılışta "pop" ile gelir), altında `display` başlık (28/34 800) ve tek cümle (`body` dim).
/// Başlık ve cümle sırayla yukarı kayarak belirir. Bant yok.
class AuthPageHeader extends StatelessWidget {
  const AuthPageHeader({
    super.key,
    required this.title,
    this.message,
    this.showLogo = true,
    this.liveRegion = false,
  });

  final String title;
  final String? message;

  /// Üstteki 48 px logo karosu (uygulama çubuğu olan sayfalarda gizlenir).
  final bool showLogo;

  /// Durum sayfaları başlığı ekran okuyucuya duyurur.
  final bool liveRegion;

  @override
  Widget build(BuildContext context) {
    final t = context.aknText;
    final c = context.akn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLogo) ...[
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AuthPop(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  boxShadow: [
                    BoxShadow(
                      color: c.logo.withValues(alpha: c.isDark ? 0.3 : 0.26),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                      spreadRadius: -6,
                    ),
                  ],
                ),
                child: const LogoMark(
                  size: 48,
                  animate: true,
                  semanticLabel: null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
        AuthRise(
          delay: const Duration(milliseconds: 40),
          child: Semantics(
            header: true,
            liveRegion: liveRegion,
            child: Text(title, style: t.display.copyWith(color: c.ink)),
          ),
        ),
        if (message != null && message!.isNotEmpty) ...[
          const SizedBox(height: 8),
          AuthRise(
            delay: const Duration(milliseconds: 90),
            child: Text(message!, style: t.body.copyWith(color: c.dim)),
          ),
        ],
      ],
    );
  }
}

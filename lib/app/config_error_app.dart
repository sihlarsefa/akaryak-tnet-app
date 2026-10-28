import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/ui/ui.dart';

/// Canlı derlemede ortam yapılandırması hatalıysa (HTTPS değil, örnek alan adı, sahte API) açılan tek
/// ekran (spec D.7 `Env.validate()`): uygulama yanlış sunucuya bağlanmaz. Yalnızca derleme hatasıdır;
/// kullanıcı verisi içermez.
///
/// Tasarım v3: açık gri sayfada, uyarı tonunun yumuşak kuyusunda dişli simgesi (96 px daire, hafifçe
/// süzülür), başlık ve açıklama sırayla yükselir; sorunlar beyaz, gölgeli bir kartta listelenir.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key, required this.problems});

  final List<String> problems;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AkaryakıtNet',
    debugShowCheckedModeBanner: false,
    theme: AknTheme.light(),
    darkTheme: AknTheme.dark(),
    locale: const Locale('tr', 'TR'),
    supportedLocales: const [Locale('tr', 'TR')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Builder(
      builder: (context) {
        final t = context.aknText;
        final c = context.akn;
        return Scaffold(
          backgroundColor: c.bg,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 24),
              children: [
                const Center(child: _GearMark()),
                const SizedBox(height: 28),
                FadeUp(
                  delay: const Duration(milliseconds: 120),
                  duration: AknMotion.slow,
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Uygulama yapılandırması eksik',
                      style: t.title,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FadeUp(
                  delay: const Duration(milliseconds: 180),
                  duration: AknMotion.slow,
                  child: Text(
                    'Bu derleme güvenli bir sunucu adresiyle yapılandırılmamış. Uygulamanın güncel '
                    'sürümünü mağazadan indirin.',
                    style: t.body.copyWith(color: c.dim),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (problems.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  FadeUp(
                    delay: const Duration(milliseconds: 240),
                    duration: AknMotion.slow,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: c.surface,
                        shape: RoundedSuperellipseBorder(
                          borderRadius: AknRadius.card,
                          side: c.isDark
                              ? BorderSide(color: c.line)
                              : BorderSide.none,
                        ),
                        shadows: AknShadows.card(c),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final p in problems)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text('• $p', style: t.bodySmall),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// The gear in the warn tone's soft well: a 96 px circle (`warn.bg`, 1 px
/// `warn.line`) with the 44 px Phosphor `gearSix` in `warn.fg`. It pops in
/// once and then floats gently (±6 px, [AknMotion.float], [AknAmbient]).
class _GearMark extends StatelessWidget {
  const _GearMark();

  @override
  Widget build(BuildContext context) {
    final tone = context.akn.warn;
    return ExcludeSemantics(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: AknMotion.of(context, AknMotion.slow),
        curve: AknMotion.pop,
        builder: (context, v, child) => Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.scale(scale: 0.7 + 0.3 * v, child: child),
        ),
        child: AknAmbient(
          period: AknMotion.float,
          reverse: true,
          restValue: 0.5,
          builder: (context, v, child) =>
              Transform.translate(offset: Offset(0, 6 - 12 * v), child: child),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tone.bg,
              shape: BoxShape.circle,
              border: Border.all(color: tone.line),
            ),
            child: SizedBox.square(
              dimension: 96,
              child: Center(
                child: Icon(
                  PhosphorIconsRegular.gearSix,
                  size: 44,
                  color: tone.fg,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

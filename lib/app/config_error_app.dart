import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/ui/ui.dart';

/// Canlı derlemede ortam yapılandırması hatalıysa (HTTPS değil, örnek alan adı, sahte API) açılan tek
/// ekran (spec D.7 `Env.validate()`): uygulama yanlış sunucuya bağlanmaz. Yalnızca derleme hatasıdır;
/// kullanıcı verisi içermez.
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
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 48),
                const Center(
                  child: AknIconBox(
                    icon: Icons.settings_suggest_rounded,
                    tone: AknTone.warn,
                    size: 64,
                  ),
                ),
                const SizedBox(height: 24),
                Semantics(
                  header: true,
                  child: Text(
                    'Uygulama yapılandırması eksik',
                    style: t.title,
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Bu derleme güvenli bir sunucu adresiyle yapılandırılmamış. Lütfen uygulamanın güncel '
                  'sürümünü mağazadan indirin.',
                  style: t.body.copyWith(color: c.dim),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                for (final p in problems)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('• $p', style: t.bodySmall),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

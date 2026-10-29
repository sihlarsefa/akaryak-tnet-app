// Duyuru ekran görüntüleri (tasarım incelemesi): Bildirimler'de duyuru satırı ve duyurunun tam
// metni, açık 1,0× ve koyu 2,0×, 390×844 dp (2× piksel) PNG; Archivo ve Phosphor simgeleriyle. Normal
// test çalışmasında atlanır; görüntü almak için:
//
//   flutter test test/features/notifications/announcement_capture_test.dart \
//     --dart-define=AKN_SHOTS_DIR=/tam/yol/shots
//
// Altın (golden) karşılaştırma değildir.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:akaryakitnet/core/routing/nav_keys.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/notifications/api.dart';
import 'package:akaryakitnet/features/notifications/data/notification_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fonts.dart';
import '../profile/a8_kit.dart';

const _outDir = String.fromEnvironment('AKN_SHOTS_DIR');

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_outDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    if (_outDir.isEmpty) return;
    await loadUiFont();
    await loadPhosphorIcons();
  });

  const variants = [
    (1.0, Brightness.light, 'acik_1x'),
    (2.0, Brightness.dark, 'koyu_2x'),
  ];
  for (final (scale, brightness, tag) in variants) {
    testWidgets('duyuru ekranları · $tag', skip: _outDir.isEmpty, (
      tester,
    ) async {
      setPhoneSize(tester, const Size(390, 844));
      final h = await A8Harness.create();
      h.server.world.addNotification(
        userId: 'u-musteri',
        category: NotificationCategory.system,
        eventCode: 'system.announcement.campaign',
        title: 'Hafta sonu kampanyası',
        body:
            'Cumartesi ve pazar günü verilen motorin siparişlerinde litre başına 0,50 TL '
            'indirim uygulanır. Kampanya 2 Kasım Pazar 23:59\'a kadar geçerlidir; ayrıntılar '
            'için bayinizle görüşebilirsiniz.',
        entityType: 'PushCampaign',
        entityId: 12,
      );
      final shot = GlobalKey();
      final router = GoRouter(
        navigatorKey: rootNavigatorKey,
        initialLocation: '/home',
        routes: [
          ...notificationsRoutes(),
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(body: SizedBox()),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: h.overrides,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            routerConfig: router,
            theme: AknTheme.light(),
            darkTheme: AknTheme.dark(),
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            locale: const Locale('tr', 'TR'),
            supportedLocales: const [Locale('tr', 'TR')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) => RepaintBoundary(
              key: shot,
              child: MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
            ),
          ),
        ),
      );
      final c = ProviderScope.containerOf(
        tester.element(find.byType(MaterialApp)),
        listen: false,
      );
      await signIn(tester, c, 'musteri');
      unawaited(router.push('/notifications'));
      await pumpFor(tester, const Duration(seconds: 2));
      await _capture(tester, shot, 'duyuru_liste_$tag');

      await tester.tap(find.text('Hafta sonu kampanyası'));
      await pumpFor(tester, const Duration(seconds: 2));
      await _capture(tester, shot, 'duyuru_sayfa_$tag');

      // Demo duyurusu (okunmuş, listenin sonunda).
      await tester.tap(find.text('Tamam'));
      await pumpFor(tester, const Duration(seconds: 1));
      await tester.scrollUntilVisible(
        find.text('Duyurular artık burada'),
        300,
        scrollable: find.byType(Scrollable).last,
      );
      await pumpFor(tester, const Duration(milliseconds: 600));
      await _capture(tester, shot, 'duyuru_demo_$tag');
      await finish(tester);
    });
  }
}

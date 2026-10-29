// Tahsilat ve Finans ekran görüntüleri (tasarım v2 "Turuncu Plaka" karşılaştırması). Normal test
// çalışmasında atlanır; görüntü almak için:
//
//   flutter test test/features/payments/finance_payments_capture_test.dart \
//     --dart-define=AKN_SCREENS_DIR=/tam/yol/finance-payments
//
// 390×844 dp (tasarım panosunun ölçüsü), 2× piksel; açık 1,0×, koyu 1,0× ve açık 2,0× varyantları.
// Yazılar gerçek Mona Sans ve Material simgeleriyle çizilir. Altın (golden) karşılaştırma değildir.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:akaryakitnet/core/ui/ui.dart' show AknFilterButton, AppSheet;
import 'package:akaryakitnet/features/payments/presentation/widgets/payment_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
import '../approvals/a5_test_kit.dart';

const _outDir = String.fromEnvironment('AKN_SCREENS_DIR');

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary =
      tester.renderObject(find.byKey(a5RootKey)) as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$_outDir/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

/// Ana kaydırılabilir alanı [dy] kadar kaydırır.
Future<void> _scroll(WidgetTester tester, double dy) async {
  ScrollableState? main;
  var best = 0.0;
  for (final e in find.byType(Scrollable).evaluate()) {
    final w = e.widget as Scrollable;
    if (axisDirectionToAxis(w.axisDirection) != Axis.vertical) continue;
    final h = e.size?.height ?? 0;
    if (h > best) {
      best = h;
      main = (e as StatefulElement).state as ScrollableState;
    }
  }
  if (main == null) return;
  final pos = main.position;
  pos.jumpTo((pos.pixels + dy).clamp(0.0, pos.maxScrollExtent));
  await pumpFor(tester, const Duration(milliseconds: 400));
}

/// v4 (P7): Tahsilat'ın süzgeçleri bandın Filtre sayfasındadır (sayfada çip satırı yok). [labels]
/// sırayla dokunulur; [close] ise sayfa kapanır ve süzülmüş liste görüntülenir.
Future<void> _filter(
  WidgetTester tester,
  List<String> labels, {
  bool close = true,
}) async {
  await tapFinder(tester, find.byType(AknFilterButton));
  for (final s in labels) {
    await tapFinder(tester, inSheet(find.text(s)).first);
  }
  if (!close) return;
  Navigator.of(tester.element(find.byType(AppSheet).last)).pop();
  await pumpFor(tester);
}

typedef _Shot = ({
  String name,
  String persona,
  String location,
  Future<void> Function(WidgetTester tester)? then,
});

void main() {
  setUpAll(() async {
    if (_outDir.isNotEmpty) await loadRealFonts();
  });

  const variants = [
    ('acik-1x', Brightness.light, 1.0),
    ('koyu-1x', Brightness.dark, 1.0),
    ('acik-2x', Brightness.light, 2.0),
  ];

  final shots = <_Shot>[
    (name: 'odemeler', persona: 'muhasebe', location: '/payments', then: null),
    (
      name: 'odemeler-asagi',
      persona: 'muhasebe',
      location: '/payments',
      then: (t) => _scroll(t, 560),
    ),
    (
      name: 'cek-senet',
      persona: 'muhasebe',
      location: '/payments?tab=instruments',
      then: null,
    ),
    (
      name: 'odeme-ayrinti',
      persona: 'muhasebe',
      location: '/payments/12002',
      then: null,
    ),
    (
      name: 'odeme-ayrinti-asagi',
      persona: 'muhasebe',
      location: '/payments/12002',
      then: (t) => _scroll(t, 640),
    ),
    (
      name: 'odeme-ayrinti-12001',
      persona: 'muhasebe',
      location: '/payments/12001',
      then: null,
    ),
    (
      name: 'odeme-durum-sayfasi',
      persona: 'muhasebe',
      location: '/payments/12002',
      then: (t) => tapText(t, 'Durumu değiştir'),
    ),
    (
      name: 'odeme-tahsil-isaretle',
      persona: 'muhasebe',
      location: '/payments/12002',
      then: (t) async {
        await tapText(t, 'Tahsil edildi olarak işaretle');
        await t.ensureVisible(find.text('Durumu kaydet'));
        await pumpFor(t);
      },
    ),
    (
      name: 'odeme-durum-iptal',
      persona: 'muhasebe',
      location: '/payments/12002',
      then: (t) async {
        await tapText(t, 'Durumu değiştir');
        await tapFinder(t, inSheet(find.text('İptal')));
        await t.ensureVisible(find.text('Durumu kaydet'));
        await pumpFor(t);
      },
    ),
    (
      name: 'cek-sayfasi',
      persona: 'muhasebe',
      location: '/payments?tab=instruments',
      then: (t) async {
        await t.tap(find.byType(InstrumentRowCard).first);
        await pumpFor(t);
      },
    ),
    (
      name: 'cari-secici',
      persona: 'muhasebe',
      location: '/payments',
      then: (t) => _filter(t, ['Cari: tümü'], close: false),
    ),
    (
      name: 'odemeler-gecikenler',
      persona: 'muhasebe',
      location: '/payments',
      then: (t) => _filter(t, ['Gecikenler']),
    ),
    (
      name: 'odemeler-tumu',
      persona: 'muhasebe',
      location: '/payments',
      then: (t) => _filter(t, ['Bekliyor', 'Belge yüklendi']),
    ),
    (name: 'finans-liste', persona: 'finans', location: '/finance', then: null),
    (
      name: 'finans-kart',
      persona: 'finans',
      location: '/finance/customers/501',
      then: null,
    ),
    (
      name: 'finans-kart-asagi',
      persona: 'finans',
      location: '/finance/customers/501',
      then: (t) => _scroll(t, 640),
    ),
    (
      name: 'finans-kart-en-asagi',
      persona: 'finans',
      location: '/finance/customers/501',
      then: (t) => _scroll(t, 1300),
    ),
    (
      name: 'finans-kart-502',
      persona: 'finans',
      location: '/finance/customers/502',
      then: null,
    ),
  ];

  for (final s in shots) {
    for (final (tag, brightness, scale) in variants) {
      testWidgets('${s.name} $tag', (tester) async {
        debugDisableShadows = false;
        addTearDown(() => debugDisableShadows = true);
        await pumpA5(
          tester,
          persona: s.persona,
          location: s.location,
          brightness: brightness,
          textScale: scale,
          size: const Size(390, 844),
        );
        if (s.then != null) await s.then!(tester);
        await pumpFor(tester, const Duration(milliseconds: 600));
        await _capture(tester, '${s.name}_$tag');
        await finish(tester);
        debugDisableShadows = true;
      }, skip: _outDir.isEmpty);
    }
  }
}

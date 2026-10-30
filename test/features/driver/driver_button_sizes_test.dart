// Şoför düğmeleri (sahip 2026-10-30: "şoför tarafında bazı butonlar gereksiz çok büyük"): sürücü
// kipinde de uygulamanın standart 48 dp düğmesi (64 değil), 20 px simge; tam genişlik gerekmeyen
// yerde doğal genişlik; ikincil eylemler çerçeveli ya da hayalet; bölge başına tek birincil; dokunma
// hedefi en az 48 dp. Rıhtım ("Yol tarifi" / "Teslim et"), itiraz şeridi ve kartı, "Ara", sihirbazın
// alt rafı ("Geri" / "İleri"), fotoğraf ve imza adımları sabitlenir.
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/core/ui/ui.dart';
import 'package:akaryakitnet/features/driver/application/driver_lists.dart';
import 'package:akaryakitnet/features/driver/copy.dart';
import 'package:akaryakitnet/features/driver/data/deliver_draft.dart';
import 'package:akaryakitnet/features/driver/data/driver_models.dart';
import 'package:akaryakitnet/features/driver/presentation/deliver_flow_page.dart';
import 'package:akaryakitnet/features/driver/presentation/widgets/shipment_card.dart';
import 'package:akaryakitnet/features/driver/presentation/widgets/stop_dock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fonts.dart';
import 'support/driver_harness.dart';

/// Uygulamanın standart düğme boyu (dokunma hedefi de bu).
const _standard = 48.0;

Finder _button(String label) => find.widgetWithText(AknButton, label).first;

void _expectStandard(WidgetTester tester, String label) {
  final size = tester.getSize(_button(label));
  expect(size.height, _standard, reason: '"$label" 48 dp yüksek (64 değil)');
}

void main() {
  // Genişlikler gerçek yazı tipiyle anlamlı; SDK önbelleğinde yoksa genişlik denetimleri atlanır
  // (yükseklikler yazı tipinden bağımsızdır).
  final fonts = realFontsAvailable();
  setUpAll(loadRealFonts);

  testWidgets('rıhtım: "Yol tarifi" ve "Teslim et" 48 dp, 20 px simge', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 300));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AknTheme.light(),
        home: Scaffold(
          body: AknDriverScope(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Align(
                alignment: Alignment.topCenter,
                child: DriverStopDock(
                  onNavigate: () {},
                  actionLabel: DriverCopy.actionDeliver,
                  actionIcon: PhosphorIconsFill.checkCircle,
                  actionIsPrimary: true,
                  onAction: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    _expectStandard(tester, DriverCopy.actionNavigate);
    _expectStandard(tester, DriverCopy.actionDeliver);
    // Rıhtım düğmeden yüksek değil (görünmez 64 dp hedef yer kaplamaz); test yazı tipinin geniş
    // karelerinde iki düğme alt alta iner.
    expect(
      tester.getSize(find.byType(DriverStopDock)).height,
      fonts ? _standard : 2 * _standard + 10,
    );
    for (final icon in tester.widgetList<Icon>(
      find.descendant(
        of: find.byType(DriverStopDock),
        matching: find.byType(Icon),
      ),
    )) {
      expect(icon.size, 20, reason: 'dev simge yok');
    }
    // Tek birincil: "Teslim et"; "Yol tarifi" ikincil.
    expect(
      tester.widget<AknButton>(_button(DriverCopy.actionDeliver)).variant,
      AknButtonVariant.primary,
    );
    expect(
      tester.widget<AknButton>(_button(DriverCopy.actionNavigate)).variant,
      AknButtonVariant.secondary,
    );
  });

  group('ekranlar', () {
    late DriverHarness h;
    late ProviderContainer c;

    Future<void> finish(WidgetTester tester) async {
      await pumpFor(tester, const Duration(milliseconds: 1500));
      await tester.pumpWidget(const SizedBox());
      await pumpFor(tester, const Duration(milliseconds: 300));
      c.dispose();
      h.dispose();
    }

    testWidgets(
      'ana sayfa: itiraz şeridi 48 dp, "Teslimatı düzelt" doğal genişlikte, "Ara" 48 dp',
      (tester) async {
        phoneSize(tester, const Size(400, 2400));
        h = await real(tester, DriverHarness.create);
        c = h.container();
        await tester.runAsync(() => DriverHarness.login(c, 'sofor'));
        await tester.pumpWidget(
          driverTestApp(container: c, initialLocation: '/driver'),
        );
        await pumpUntil(
          tester,
          () => c.read(driverListProvider(DriverTab.today)).hasValue,
        );
        await pumpFor(tester, const Duration(milliseconds: 900));

        // Rıhtım (gerçek sayfada): 48 dp.
        _expectStandard(tester, DriverCopy.actionNavigate);
        _expectStandard(tester, DriverCopy.actionDeliver);

        // İtiraz şeridinin kartı standart dokunma hedefi kadar (sürücüde de 64 değil).
        final strip = find.byWidgetPredicate(
          (w) => w is AknFactLine && w.text == DriverCopy.disputedCount(1),
        );
        final card = find
            .ancestor(of: strip, matching: find.byType(ConstrainedBox))
            .first;
        expect(tester.getSize(card).height, _standard);

        // Kişi kartındaki "Ara": 48 dp, doğal genişlikte.
        _expectStandard(tester, DriverCopy.actionCall);
        expect(
          tester.widget<AknButton>(_button(DriverCopy.actionCall)).expand,
          isFalse,
        );
        if (fonts) {
          expect(
            tester.getSize(_button(DriverCopy.actionCall)).width,
            lessThan(160),
          );
        }

        // İtirazlı satır kartındaki "Teslimatı düzelt": 48 dp, kart boyu değil.
        final fix = find.descendant(
          of: find.byType(ShipmentCard),
          matching: find.widgetWithText(AknButton, DriverCopy.actionFix),
        );
        expect(fix, findsOneWidget);
        final fixSize = tester.getSize(fix);
        final cardWidth = tester
            .getSize(
              find.ancestor(of: fix, matching: find.byType(ShipmentCard)).first,
            )
            .width;
        expect(fixSize.height, _standard);
        expect(tester.widget<AknButton>(fix).expand, isFalse);
        if (fonts) expect(fixSize.width, lessThan(cardWidth * 0.7));
        await finish(tester);
      },
    );

    testWidgets(
      'teslim sihirbazı: "Geri" doğal genişlikte, "İleri" kalanı doldurur; fotoğraf ve imza '
      'düğmeleri 48 dp, yan yana, ikincil',
      (tester) async {
        phoneSize(tester, const Size(390, 900));
        h = await real(tester, DriverHarness.create);
        c = h.container();
        await tester.runAsync(() => DriverHarness.login(c, 'sofor'));
        await tester.runAsync(
          () => c.read(driverListProvider(DriverTab.today).future),
        );
        final id =
            h.world.shipments.firstWhere(
                  (s) => s['status'] == 1 && s['driverUserId'] == 'u-sofor',
                )['id']
                as int;
        await tester.runAsync(
          () => DeliverDraftStore(PrefsStore(h.prefs), h.files).save(
            'u-sofor',
            DeliverDraft(
              shipmentId: id,
              code: DriverShipmentRow.shipmentCode(id),
              step: DeliverStep.photos,
              litersText: '9950',
              documentNo: 'IRS-5001',
              recipientName: 'Murat Kaya',
              savedAt: DateTime.now().toUtc(),
            ),
          ),
        );
        await tester.pumpWidget(
          driverTestApp(
            container: c,
            initialLocation: '/driver/shipments/$id/deliver',
          ),
        );
        await pumpUntil(
          tester,
          () => c.read(driverShipmentProvider(id)).hasValue,
        );
        await pumpFor(tester, const Duration(milliseconds: 900));
        expect(find.byType(DeliverFlowPage), findsOneWidget);
        expect(find.text(DriverCopy.headPhotos), findsOneWidget);

        // Alt raf: ikisi de 48 dp; "Geri" yarım ekran değil, "İleri" ondan geniş.
        _expectStandard(tester, DriverCopy.back);
        _expectStandard(tester, DriverCopy.next);
        final back = tester.getRect(_button(DriverCopy.back));
        final next = tester.getRect(_button(DriverCopy.next));
        expect(
          tester.widget<AknButton>(_button(DriverCopy.back)).expand,
          isFalse,
        );
        expect(back.width, lessThan((390 - 40 - 10) / 2));
        expect(next.width, greaterThan(back.width * 1.5));
        expect(back.top, next.top, reason: 'tek satırda');

        // Fotoğraf adımı: "Fotoğraf çek" ve "Galeriden seç" 48 dp, doğal genişlikte, yan yana;
        // bölgenin tek birincili alttaki "İleri".
        _expectStandard(tester, DriverCopy.photoTake);
        _expectStandard(tester, DriverCopy.photoPick);
        for (final label in [DriverCopy.photoTake, DriverCopy.photoPick]) {
          expect(tester.widget<AknButton>(_button(label)).expand, isFalse);
        }
        if (fonts) {
          final take = tester.getRect(_button(DriverCopy.photoTake));
          final pick = tester.getRect(_button(DriverCopy.photoPick));
          expect(take.width, lessThan(390 * 0.6));
          expect(take.top, pick.top, reason: 'yan yana');
        }
        expect(
          tester.widget<AknButton>(_button(DriverCopy.photoTake)).variant,
          isNot(AknButtonVariant.primary),
        );
        final primaries = tester
            .widgetList<AknButton>(find.byType(AknButton))
            .where((b) => b.variant == AknButtonVariant.primary);
        expect(primaries.map((b) => b.label), [DriverCopy.next]);

        // İmza adımı: "İmza alınamıyor" doğal genişlikte, 48 dp.
        await tester.tap(find.text(DriverCopy.photoTake).last);
        await pumpUntil(
          tester,
          () => find.text(DriverCopy.photoCount(1)).evaluate().isNotEmpty,
        );
        await tester.tap(_button(DriverCopy.next));
        await pumpFor(tester, const Duration(milliseconds: 700));
        expect(find.text(DriverCopy.headSignature), findsOneWidget);
        _expectStandard(tester, DriverCopy.signatureCantGet);
        expect(
          tester.widget<AknButton>(_button(DriverCopy.signatureCantGet)).expand,
          isFalse,
        );
        if (fonts) {
          expect(
            tester.getSize(_button(DriverCopy.signatureCantGet)).width,
            lessThan(390 * 0.7),
          );
        }
        await finish(tester);
      },
    );
  });
}

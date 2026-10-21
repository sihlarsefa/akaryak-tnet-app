// Çıkışta özellik temizlikleri (spec D.7, A-INT): uygulama katmanı `sessionCleanupHooksProvider`'a
// özelliklerin kullanıcı verisini (A3'ün saklı PDF belgeleri) ekler; çıkışta ve kullanıcı değişince
// silinir. Bir kancanın hatası çıkışı engellemez.
import 'dart:typed_data';

import 'package:akaryakitnet/core/auth/session_cleanup.dart';
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/auth/session_state.dart';
import 'package:akaryakitnet/features/customer_more/data/pdf_cache.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('çıkış kullanıcının saklı PDF belgelerini siler', () async {
    final h = await TestHarness.create();
    final pdfs = MemoryPdfCache();
    final c = h.container(extra: [pdfCacheProvider.overrideWithValue(pdfs)]);
    addTearDown(c.dispose);
    final s = c.read(sessionControllerProvider.notifier);
    await s.restore();
    await s.loginWithPassword('musteri', 'demo');
    await pdfs.write('u-musteri', 'SIP-1.pdf', Uint8List.fromList([1, 2]));
    expect(await pdfs.list('u-musteri'), hasLength(1));

    await s.signOut();
    await pumpEventQueue();
    expect(c.read(sessionControllerProvider), isA<SessionUnauthenticated>());
    expect(await pdfs.list('u-musteri'), isEmpty);
  });

  test('başka kullanıcıyla giriş öncekinin belgelerini siler', () async {
    final h = await TestHarness.create();
    final pdfs = MemoryPdfCache();
    final c = h.container(extra: [pdfCacheProvider.overrideWithValue(pdfs)]);
    addTearDown(c.dispose);
    final s = c.read(sessionControllerProvider.notifier);
    await s.restore();
    await s.loginWithPassword('musteri', 'demo');
    await pdfs.write('u-musteri', 'SIP-1.pdf', Uint8List.fromList([1]));
    // Oturum kapatılmadan (ör. süresi dolmuş) başka kullanıcı girer.
    await s.loginWithPassword('onay', 'demo');
    await pumpEventQueue();
    expect(await pdfs.list('u-musteri'), isEmpty);
  });

  test('hatalı kanca çıkışı engellemez', () async {
    final h = await TestHarness.create();
    var called = false;
    final c = h.container(
      extra: [
        sessionCleanupHooksProvider.overrideWithValue([
          (_) async => throw StateError('kanca'),
          (_) async => called = true,
        ]),
      ],
    );
    addTearDown(c.dispose);
    final s = c.read(sessionControllerProvider.notifier);
    await s.restore();
    await s.loginWithPassword('musteri', 'demo');
    await s.signOut();
    await pumpEventQueue();
    expect(c.read(sessionControllerProvider), isA<SessionUnauthenticated>());
    expect(called, isTrue);
  });
}

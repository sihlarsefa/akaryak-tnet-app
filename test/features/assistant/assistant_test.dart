// Asistan (spec A.6, B.11): onay kapısı (sohbetten önce tam ekran aydınlatma), kabul / vazgeç, sohbet
// (onay sürümü ve son 10 mesaj gider), geri bildirim, hata balonu, sürüm değişince yeniden onay,
// 503 kapalı, 429 bekleme, onayı geri alma, yazıyor göstergesi, erişilebilirlik (C.7).
import 'package:akaryakitnet/core/auth/session_controller.dart';
import 'package:akaryakitnet/core/env/app_config_controller.dart';
import 'package:akaryakitnet/core/storage/prefs_store.dart';
import 'package:akaryakitnet/features/assistant/api.dart';
import 'package:akaryakitnet/features/assistant/application/assistant_chat_controller.dart';
import 'package:akaryakitnet/features/assistant/presentation/widgets/message_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../profile/a8_kit.dart';

Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 400 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

Future<ProviderContainer> signedIn(A8Harness h, String persona) async {
  final c = h.container();
  await c.read(appConfigProvider.notifier).load();
  await c
      .read(sessionControllerProvider.notifier)
      .loginWithPassword(persona, 'demo');
  return c;
}

/// Onayı sahte sunucuda önceden verir.
Future<void> preConsent(ProviderContainer c) async {
  c.listen(assistantGateProvider, (_, _) {});
  await until(() => c.read(assistantGateProvider) is! GateChecking);
  await c.read(assistantGateProvider.notifier).accept();
}

Finder composerField() => find.byType(TextField);

Future<void> send(WidgetTester tester, String text) async {
  await tester.enterText(composerField(), text);
  await tester.pump();
  await tester.tap(find.byTooltip('Gönder'));
  await pumpFor(tester, const Duration(milliseconds: 600));
}

void main() {
  group('onay kapısı', () {
    test(
      'onay yoksa aydınlatma; kabul edince hazır ve sürüm saklanır',
      () async {
        final h = await A8Harness.create();
        final c = await signedIn(h, 'musteri');
        addTearDown(c.dispose);
        c.listen(assistantGateProvider, (_, _) {});
        await until(() => c.read(assistantGateProvider) is! GateChecking);
        final gate = c.read(assistantGateProvider);
        expect(gate, isA<GateNeedsConsent>());
        final d = (gate as GateNeedsConsent).disclosure;
        expect(d.provider, 'OpenAI, L.L.C.');
        expect(d.providerCountry, 'ABD');
        expect(d.displaySections, isNotEmpty);
        await c.read(assistantGateProvider.notifier).accept();
        expect(c.read(assistantGateProvider), isA<GateReady>());
        expect(
          h.prefs.getString(
            PrefKeys.user('u-musteri', 'assistant.consentVersion'),
          ),
          '1',
        );
      },
    );

    test(
      'kabul edilmiş sürüm uygulama ayarlarındakiyle aynıysa sunucuya sorulmaz',
      () async {
        final h = await A8Harness.create(
          prefs: {'akn.u.u-musteri.assistant.consentVersion': '1'},
        );
        final c = await signedIn(h, 'musteri');
        addTearDown(c.dispose);
        // Sunucu `app/config` yanıtı aynı sürümü taşıyor (son kaydedilen ham yanıt).
        await h.cache.write('app.config', {'assistantConsentVersion': '1'});
        c.listen(assistantGateProvider, (_, _) {});
        await until(() => c.read(assistantGateProvider) is! GateChecking);
        expect(c.read(assistantGateProvider), isA<GateReady>());
      },
    );

    test(
      'uygulama ayarlarındaki sürüm değişince asistan açılırken yeniden onay',
      () async {
        final h = await A8Harness.create();
        final c = await signedIn(h, 'musteri');
        addTearDown(c.dispose);
        await preConsent(c);
        expect(c.read(assistantGateProvider), isA<GateReady>());
        // Sunucu metni güncelledi: app/config yeni sürümü taşıyor.
        h.assistant.version = '2';
        await h.cache.write('app.config', {'assistantConsentVersion': '2'});
        await c.read(assistantGateProvider.notifier).revalidate();
        await until(() => c.read(assistantGateProvider) is! GateChecking);
        final gate = c.read(assistantGateProvider);
        expect(gate, isA<GateNeedsConsent>());
        expect((gate as GateNeedsConsent).disclosure.version, '2');
        expect(gate.notice, contains('güncellendi'));
      },
    );

    test('onay geri alınınca (DELETE) kapı yeniden kapanır', () async {
      final h = await A8Harness.create();
      final c = await signedIn(h, 'musteri');
      addTearDown(c.dispose);
      await preConsent(c);
      expect(c.read(assistantGateProvider), isA<GateReady>());
      await c.read(assistantGateProvider.notifier).withdraw();
      await until(() => c.read(assistantGateProvider) is! GateChecking);
      expect(c.read(assistantGateProvider), isA<GateNeedsConsent>());
      expect(
        h.prefs.getString(
          PrefKeys.user('u-musteri', 'assistant.consentVersion'),
        ),
        isNull,
      );
    });

    test('503 assistant_disabled → kapalı, girişler gizlenir', () async {
      final h = await A8Harness.create();
      h.assistant.disabled = true;
      final c = await signedIn(h, 'musteri');
      addTearDown(c.dispose);
      expect(c.read(assistantEnabledProvider), isTrue);
      await preConsent(c);
      await c.read(assistantChatProvider.notifier).send('Siparişim nerede?');
      expect(c.read(assistantGateProvider), isA<GateDisabled>());
      expect(c.read(assistantEnabledProvider), isFalse);
    });
  });

  group('sohbet', () {
    test('onay sürümü ve en çok 10 geçmiş mesaj gönderilir', () async {
      final h = await A8Harness.create();
      final c = await signedIn(h, 'musteri');
      addTearDown(c.dispose);
      await preConsent(c);
      c.listen(assistantChatProvider, (_, _) {});
      final chat = c.read(assistantChatProvider.notifier);
      for (var i = 0; i < 7; i++) {
        await chat.send('Soru $i');
      }
      final body = h.assistant.lastChat!;
      expect(body['consentVersion'], '1');
      expect(body['message'], 'Soru 6');
      final history = body['history'] as List;
      expect(history, hasLength(10));
      expect((history.last as Map)['role'], 'assistant');
      expect((history.first as Map)['content'], 'Soru 1');
      expect(c.read(assistantChatProvider).messages, hasLength(14));
    });

    test(
      'sürüm değişince consent_required → mesaj bekler, kapı yeniden onay ister',
      () async {
        final h = await A8Harness.create();
        final c = await signedIn(h, 'musteri');
        addTearDown(c.dispose);
        await preConsent(c);
        c.listen(assistantChatProvider, (_, _) {});
        h.assistant.version = '2';
        await c
            .read(assistantChatProvider.notifier)
            .send('Çek nasıl yüklerim?');
        final m = c.read(assistantChatProvider).messages.single;
        expect(m.failed, isTrue);
        await until(() => c.read(assistantGateProvider) is GateNeedsConsent);
        final gate = c.read(assistantGateProvider) as GateNeedsConsent;
        expect(gate.disclosure.version, '2');
        expect(gate.notice, contains('güncellendi'));
        await c.read(assistantGateProvider.notifier).accept();
        await c.read(assistantChatProvider.notifier).retry(m.id);
        final msgs = c.read(assistantChatProvider).messages;
        expect(msgs, hasLength(2));
        expect(msgs.last.text, contains('Çek ya da senet'));
      },
    );

    test('geri bildirim yalnızca bir kez ve kendi kaydına', () async {
      final h = await A8Harness.create();
      final c = await signedIn(h, 'sofor');
      addTearDown(c.dispose);
      await preConsent(c);
      c.listen(assistantChatProvider, (_, _) {});
      final chat = c.read(assistantChatProvider.notifier);
      await chat.send('Teslimatta imza zorunlu mu?');
      final reply = c.read(assistantChatProvider).messages.last;
      expect(reply.text, contains('İmza'));
      expect(
        await chat.rate(reply.id, helpful: false, comment: 'Kısa'),
        isNull,
      );
      expect(h.assistant.feedback.single, {
        'chatLogId': reply.chatLogId,
        'helpful': false,
        'comment': 'Kısa',
      });
      await chat.rate(reply.id, helpful: true);
      expect(h.assistant.feedback, hasLength(1));
    });

    test(
      'başlangıç soruları personaya göre (sunucu), boşsa yerel yedek',
      () async {
        final h = await A8Harness.create();
        final c = await signedIn(h, 'sofor');
        addTearDown(c.dispose);
        c.listen(assistantChatProvider, (_, _) {});
        await c.read(assistantChatProvider.notifier).ensureSuggestions();
        final qs = [
          for (final g in c.read(assistantChatProvider).suggestions!)
            ...g.questions,
        ];
        expect(qs, contains('Teslimatta imza zorunlu mu?'));
      },
    );
  });

  group('ekran', () {
    a11yMatrix('aydınlatma metni', (tester, scale, b) async {
      await pumpA8(tester, '/assistant', textScale: scale, brightness: b);
      expect(find.text('Kabul ediyorum'), findsOneWidget);
      expect(find.text('Vazgeç'), findsOneWidget);
      expect(composerField(), findsNothing, reason: 'onaysız sohbet yok');
    });

    a11yMatrix('sohbet', (tester, scale, b) async {
      await pumpA8(
        tester,
        '/assistant',
        textScale: scale,
        brightness: b,
        beforeOpen: preConsent,
      );
      await send(tester, 'Siparişim nerede?');
      expect(find.byType(MessageBubble), findsWidgets);
      expect(find.text('Yanıt yararlı oldu mu?'), findsOneWidget);
    });

    testWidgets(
      'kabul ediyorum → sohbet; başlangıç sorusu sorulur, yanıt gelir',
      (tester) async {
        setPhoneSize(tester, const Size(390, 844));
        final h = await A8Harness.create();
        await pumpA8(tester, '/assistant', harness: h);
        expect(
          find.text('Yapay zekâ asistanı aydınlatma metni'),
          findsOneWidget,
        );
        await tester.tap(find.text('Kabul ediyorum'));
        await pumpFor(tester, const Duration(milliseconds: 800));
        expect(find.textContaining('Merhaba Selin'), findsOneWidget);
        expect(find.text('Siparişim nerede?'), findsOneWidget);
        await tester.tap(find.text('Siparişim nerede?'));
        await tester.pump();
        await pumpFor(tester, const Duration(milliseconds: 800));
        expect(find.byType(MessageBubble), findsNWidgets(2));
        // Yer adı alt menüdeki sözcüktür (v4 §3.2): "Siparişlerim" değil.
        expect(find.textContaining('Siparişler sekmesinde'), findsWidgets);
        expect(find.textContaining('Siparişlerim'), findsNothing);
        expect(h.assistant.chatCalls, 1);
        await finish(tester);
      },
    );

    testWidgets('vazgeç → kapanır, sohbet açılmaz', (tester) async {
      setPhoneSize(tester);
      final h = await A8Harness.create();
      await pumpA8(tester, '/assistant', harness: h);
      await tapVisible(tester, find.text('Vazgeç'));
      await pumpFor(tester, const Duration(milliseconds: 800));
      expect(find.text('ANA SAYFA'), findsOneWidget);
      expect(h.assistant.chatCalls, 0);
      await finish(tester);
    });

    testWidgets('olumsuz geri bildirim yorum sayfası açar', (tester) async {
      setPhoneSize(tester, const Size(390, 844));
      final h = await A8Harness.create();
      await pumpA8(tester, '/assistant', harness: h, beforeOpen: preConsent);
      await send(tester, 'Koşullu onay ne demek?');
      await tester.tap(find.byTooltip('Yararlı değil'));
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(find.text('Neyi daha iyi yapabilirdik?'), findsWidgets);
      await tester.enterText(find.byType(TextField).last, 'Daha kısa olsun');
      await tester.tap(find.text('Gönder').last);
      await pumpFor(tester, const Duration(milliseconds: 600));
      expect(h.assistant.feedback.single['comment'], 'Daha kısa olsun');
      expect(find.text('Geri bildiriminiz için teşekkürler.'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('model hatası: hata balonu, geri bildirim yok', (tester) async {
      setPhoneSize(tester, const Size(390, 844));
      final h = await A8Harness.create();
      await pumpA8(tester, '/assistant', harness: h, beforeOpen: preConsent);
      h.assistant.modelErrorNext = true;
      await send(tester, 'Merhaba');
      expect(
        find.text(
          'Asistan şu an yanıt veremiyor; birkaç dakika sonra tekrar deneyin.',
        ),
        findsOneWidget,
      );
      expect(find.text('Yanıt yararlı oldu mu?'), findsNothing);
      await finish(tester);
    });

    testWidgets('429: mesaj gönderilemedi, bekleme süresi, tekrar dene', (
      tester,
    ) async {
      setPhoneSize(tester, const Size(390, 844));
      fixClock();
      final h = await A8Harness.create();
      await pumpA8(tester, '/assistant', harness: h, beforeOpen: preConsent);
      h.assistant.rateLimitNext = true;
      await send(tester, 'Çek nasıl yüklerim?');
      expect(find.textContaining('Gönderilemedi'), findsOneWidget);
      expect(find.textContaining('sn sonra tekrar deneyin'), findsOneWidget);
      // Bekleme süresi dolarken "Tekrar dene" bir şey yapmaz.
      await tester.tap(find.textContaining('Tekrar dene'));
      await pumpFor(tester, const Duration(milliseconds: 300));
      expect(h.assistant.chatCalls, 1);
      fixClock(a8Now.add(const Duration(seconds: 25)));
      await pumpFor(tester, const Duration(seconds: 2));
      expect(find.textContaining('sn sonra tekrar deneyin'), findsNothing);
      await tester.tap(find.textContaining('Tekrar dene'));
      await pumpFor(tester, const Duration(milliseconds: 800));
      expect(find.textContaining('Çek ya da senet'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('kapalı (503): "kullanılamıyor" ve destek', (tester) async {
      setPhoneSize(tester);
      final h = await A8Harness.create();
      h.assistant.disabled = true;
      await pumpA8(
        tester,
        '/assistant',
        harness: h,
        beforeOpen: (c) async {
          c.listen(assistantGateProvider, (_, _) {});
          await until(() => c.read(assistantGateProvider) is! GateChecking);
        },
      );
      // Aydınlatma metni okunur (kapalıyken de 200); sohbet 503 alınca kapı kapanır.
      await tester.tap(find.text('Kabul ediyorum'));
      await pumpFor(tester, const Duration(milliseconds: 800));
      await send(tester, 'Merhaba');
      expect(find.text('Asistan şu an kullanılamıyor'), findsOneWidget);
      expect(find.text('Destek ile görüş'), findsWidgets);
      await finish(tester);
    });

    testWidgets(
      'yazıyor: oklar yalnızca yanıt beklenirken; azaltılmış harekette duran metin',
      (tester) async {
        setPhoneSize(tester, const Size(390, 844));
        await tester.pumpWidget(
          const MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: true),
              child: Scaffold(body: TypingBubble()),
            ),
          ),
        );
        expect(find.text('Yazıyor…'), findsOneWidget);
        expect(tester.hasRunningAnimations, isFalse);
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: TypingBubble())),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Yazıyor…'), findsNothing);
        expect(tester.hasRunningAnimations, isTrue);
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: AssistantAvatar())),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.hasRunningAnimations, isFalse, reason: 'durgun işaret');
        await tester.pumpWidget(const SizedBox());
      },
    );
  });
}
